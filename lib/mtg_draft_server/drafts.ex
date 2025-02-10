defmodule MtgDraftServer.Drafts do
  @moduledoc """
  Context for managing drafts, players, and picks.

  In this Magic: The Gathering draft server:
    - A draft is created independently of any player.
    - When a player creates a draft, a corresponding draft_player record is created.
    - A player may only be in one active (pending/active) draft at a time.
    - Each draft supports a maximum of 8 players.
  """

  import Ecto.Query, warn: false
  alias MtgDraftServer.Repo
  alias MtgDraftServer.Drafts.{Draft, DraftPlayer, DraftPick}

  @one_day_in_seconds 86400

  @type error :: {:error, Ecto.Changeset.t() | String.t()}
  @type draft_result :: {:ok, Draft.t()} | error
  @type pick_result :: {:ok, DraftPick.t()} | error
  @type player_result :: {:ok, DraftPlayer.t()} | error

  @doc """
  Creates a new draft.

  Note that the draft itself is agnostic of a player.
  If a creator is provided in the attrs (using key `:creator`), a corresponding
  draft_player record is created.
  """
  @spec create_draft(map()) :: draft_result
  def create_draft(attrs \\ %{}) do
    Repo.transaction(fn ->
      with {:ok, draft} <- do_create_draft(attrs),
           {:ok, _player} <- maybe_create_player(draft, attrs[:creator]) do
        draft
      else
        error -> Repo.rollback(error)
      end
    end)
  end

  @doc """
  Creates a new draft, starts its draft-session GenServer,
  and (if a creator is provided) joins the creator into the draft.

  Before creating a new draft, it ensures that the player isn’t already
  in an active (pending or active) draft.
  """
  @spec create_and_join_draft(map()) :: {:ok, Draft.t()} | {:error, any()}
  def create_and_join_draft(attrs \\ %{}) do
    # If a creator is provided, ensure they are not already in an active draft.
    if creator = attrs[:creator] do
      case get_active_draft_for_player(creator) do
        nil -> :ok
        _ -> {:error, "Player already in an active draft"}
      end
    else
      :ok
    end
    |> case do
      :ok ->
        Repo.transaction(fn ->
          with {:ok, draft} <- do_create_draft(attrs),
               {:ok, _player} <- maybe_create_player(draft, attrs[:creator]) do
            # Start the draft session.
            {:ok, _pid} = MtgDraftServer.DraftSessionSupervisor.start_new_session(draft.id)
            # Have the creator join the draft session.
            if attrs[:creator] do
              :ok =
                MtgDraftServer.DraftSession.join(draft.id, %{user_id: attrs[:creator], seat: 1})
            end

            draft
          else
            error -> Repo.rollback(error)
          end
        end)

      error ->
        error
    end
  end

  @doc """
  Retrieves the most recent active draft for a given player.
  (An active draft is one whose status is either "pending" or "active".)
  """
  @spec get_active_draft_for_player(String.t()) :: DraftPlayer.t() | nil
  def get_active_draft_for_player(user_id) do
    query =
      from dp in DraftPlayer,
        join: d in Draft,
        on: dp.draft_id == d.id,
        where: dp.user_id == ^user_id and d.status in ["pending", "active"],
        order_by: [desc: dp.inserted_at],
        limit: 1,
        preload: [:draft]

    Repo.one(query)
  end

  @doc """
  Starts a draft by updating its status to "active".
  Validates that the draft exists and has at least 2 players.
  """
  @spec start_draft(binary()) :: draft_result
  def start_draft(draft_id) do
    with {:ok, draft} <- get_draft(draft_id),
         :ok <- validate_draft_can_start(draft),
         {:ok, updated_draft} <- do_start_draft(draft) do
      broadcast_draft_update(draft_id, :draft_started)
      {:ok, updated_draft}
    end
  end

  @doc """
  Records a card pick in the draft.
  Validates that the pick is legal and updates the draft state accordingly.
  """
  @spec pick_card(binary(), binary(), binary(), map()) :: pick_result
  def pick_card(draft_id, user_id, card_id, extra_attrs \\ %{}) do
    start_time = System.monotonic_time()

    result =
      with {:ok, draft} <- get_draft(draft_id),
           :ok <- validate_draft_active(draft),
           {:ok, draft_player} <- get_draft_player(draft_id, user_id),
           :ok <- validate_can_pick(draft_player, extra_attrs),
           {:ok, pick} <- do_create_pick(draft_id, draft_player, card_id, extra_attrs) do
        broadcast_draft_update(draft_id, {:pick_made, pick})
        {:ok, pick}
      end

    # Record telemetry for the pick action.
    end_time = System.monotonic_time()

    :telemetry.execute(
      [:mtg_draft_server, :drafts, :pick_card],
      %{duration: end_time - start_time},
      %{draft_id: draft_id, user_id: user_id}
    )

    result
  end

  @doc """
  Retrieves all picks for a given draft and player.
  """
  @spec get_picked_cards(binary(), binary()) :: [DraftPick.t()]
  def get_picked_cards(draft_id, user_id) do
    with {:ok, draft_player} <- get_draft_player(draft_id, user_id) do
      query =
        from pick in DraftPick,
          where: pick.draft_player_id == ^draft_player.id,
          order_by: [asc: pick.inserted_at],
          preload: [:card]

      Repo.all(query)
    else
      _error -> []
    end
  end

  @doc """
  Gets a draft by its ID.
  Returns `{:ok, draft}` if found, or `{:error, "Draft not found"}` if not.
  """
  @spec get_draft(binary()) :: draft_result
  def get_draft(draft_id) do
    case Cachex.get(:draft_cache, "draft:#{draft_id}") do
      {:ok, draft} when not is_nil(draft) ->
        {:ok, draft}

      _ ->
        case Repo.get(Draft, draft_id) do
          nil ->
            {:error, "Draft not found"}

          draft ->
            Cachex.put(:draft_cache, "draft:#{draft_id}", draft, ttl: :timer.minutes(5))
            {:ok, draft}
        end
    end
  end

  # ============================================================================
  # Private helper functions
  # ============================================================================

  defp do_create_draft(attrs) do
    %Draft{}
    |> Draft.changeset(attrs)
    |> Repo.insert()
  end

  defp do_start_draft(draft) do
    draft
    |> Draft.changeset(%{status: "active"})
    |> Repo.update()
  end

  defp do_create_pick(draft_id, draft_player, card_id, extra_attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, @one_day_in_seconds, :second)

    attrs =
      Map.merge(extra_attrs, %{
        "draft_id" => draft_id,
        "draft_player_id" => draft_player.id,
        "card_id" => card_id,
        "expires_at" => expires_at
      })

    %DraftPick{}
    |> DraftPick.changeset(attrs)
    |> Repo.insert()
  end

  def get_draft_player(draft_id, user_id) do
    case Repo.one(
           from dp in DraftPlayer,
             where: dp.draft_id == ^draft_id and dp.user_id == ^user_id,
             preload: [:draft]
         ) do
      nil -> {:error, "Player not found in draft"}
      player -> {:ok, player}
    end
  end

  # If no creator is provided, simply succeed.
  defp maybe_create_player(_draft, nil), do: {:ok, nil}

  # When a creator is provided, first check that the draft is not already full.
  defp maybe_create_player(draft, creator) do
    player_count =
      Repo.one(from dp in DraftPlayer, where: dp.draft_id == ^draft.id, select: count(dp.id))

    if player_count < 8 do
      DraftPlayer.create_draft_player(%{
        draft_id: draft.id,
        user_id: creator,
        seat: 1
      })
    else
      {:error, "Draft is full (max 8 players)"}
    end
  end

  defp validate_draft_can_start(draft) do
    with :ok <- validate_draft_status(draft),
         :ok <- validate_player_count(draft) do
      :ok
    end
  end

  defp validate_draft_status(draft) do
    if draft.status == "pending" do
      :ok
    else
      {:error, "Draft cannot be started from #{draft.status} status"}
    end
  end

  defp validate_player_count(draft) do
    player_count =
      Repo.one(from dp in DraftPlayer, where: dp.draft_id == ^draft.id, select: count(dp.id))

    if player_count >= 2 do
      :ok
    else
      {:error, "Draft needs at least 2 players to start"}
    end
  end

  defp validate_draft_active(draft) do
    if draft.status == "active" do
      :ok
    else
      {:error, "Draft is not active"}
    end
  end

  defp validate_can_pick(draft_player, attrs) do
    with :ok <- validate_pack_number(attrs["pack_number"]),
         :ok <- validate_pick_number(attrs["pick_number"]),
         :ok <- validate_player_turn(draft_player, attrs) do
      :ok
    end
  end

  defp validate_pack_number(pack_number) when pack_number in 1..3, do: :ok
  defp validate_pack_number(_), do: {:error, "Invalid pack number"}

  defp validate_pick_number(pick_number) when pick_number in 1..15, do: :ok
  defp validate_pick_number(_), do: {:error, "Invalid pick number"}

  defp validate_player_turn(_draft_player, _attrs) do
    # Implement turn-based validation here as needed.
    :ok
  end

  defp broadcast_draft_update(draft_id, event) do
    Phoenix.PubSub.broadcast(
      MtgDraftServer.PubSub,
      "draft:#{draft_id}",
      {event, draft_id}
    )
  end
end

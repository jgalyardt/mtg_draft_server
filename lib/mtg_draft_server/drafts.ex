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
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:draft, Draft.changeset(%Draft{}, attrs))
        |> maybe_multi_insert_player(attrs[:creator])
        |> Repo.transaction()

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

  Validates that the pick is legal by using the in-memory session state
  (when provided) so we never call back into the server from inside itself.
  """
  @spec pick_card(binary(), String.t(), String.t(), map()) :: pick_result
  def pick_card(draft_id, user_id, card_id, extra_attrs \\ %{}) do
    Repo.transaction(fn ->
      with {:ok, draft} <- get_draft(draft_id),
           :ok <- validate_draft_active(draft),
           {:ok, draft_player} <- get_draft_player(draft_id, user_id) do
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        expires_at = DateTime.add(now, @one_day_in_seconds, :second)

        attrs =
          Map.merge(extra_attrs, %{
            "draft_id" => draft_id,
            "draft_player_id" => draft_player.id,
            "card_id" => card_id,
            "expires_at" => expires_at,
            "pack_number" => extra_attrs["pack_number"] || 1,
            "pick_number" => extra_attrs["pick_number"] || 1
          })

        %DraftPick{}
        |> DraftPick.changeset(attrs)
        |> Repo.insert!()
      else
        error -> Repo.rollback(error)
      end
    end)
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

  @doc """
  Retrieves a draft player by draft ID and user ID.
  Returns `{:ok, draft_player}` if found, or `{:error, "Player not found in draft"}` if not.
  """
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

  @doc """
  Marks the draft as complete by updating its status.
  """
  @spec complete_draft(binary()) :: {:ok, Draft.t()} | {:error, any()}
  def complete_draft(draft_id) do
    with {:ok, draft} <- get_draft(draft_id) do
      draft
      |> Draft.changeset(%{status: "complete"})
      |> Repo.update()
    end
  end

  @doc """
  Returns a list of pending drafts that have fewer than 8 players.
  Each draft is returned as a map with keys: :id, :player_count, and :status.
  """
  def list_pending_drafts do
    query =
      from d in Draft,
        where: d.status == "pending",
        left_join: dp in DraftPlayer,
        on: dp.draft_id == d.id,
        group_by: d.id,
        having: count(dp.id) < 8,
        select: %{id: d.id, player_count: count(dp.id), status: d.status}

    Repo.all(query)
  end

  @doc """
  Joins the given user to the specified draft if it is not full.
  If the user is already in the draft, returns the existing record.
  """
  def join_draft(%Draft{} = draft, user_id) do
    case Repo.one(
           from dp in DraftPlayer,
             where: dp.draft_id == ^draft.id and dp.user_id == ^user_id
         ) do
      %DraftPlayer{} = existing_player ->
        {:ok, existing_player}

      nil ->
        player_count =
          Repo.one(from dp in DraftPlayer, where: dp.draft_id == ^draft.id, select: count(dp.id))

        if player_count < 8 do
          DraftPlayer.create_draft_player(%{
            draft_id: draft.id,
            user_id: user_id,
            seat: player_count + 1
          })
        else
          {:error, "Draft is full (max 8 players)"}
        end
    end
  end

  @doc """
  Returns a list of user IDs for all players in the specified draft.
  """
  def get_draft_players(draft_id) do
    from(dp in DraftPlayer,
      where: dp.draft_id == ^draft_id,
      order_by: dp.seat,
      select: dp.user_id
    )
    |> Repo.all()
  end

  @doc """
  Broadcasts a draft event over PubSub.
  """
  @spec notify(binary(), any()) :: :ok
  def notify(draft_id, event) when is_atom(event) do
    Phoenix.PubSub.broadcast(
      MtgDraftServer.PubSub,
      "draft:#{draft_id}",
      {event, draft_id}
    )

    :ok
  end

  def notify(draft_id, event) do
    Phoenix.PubSub.broadcast(
      MtgDraftServer.PubSub,
      "draft:#{draft_id}",
      event
    )

    :ok
  end

  @doc """
  Returns a list of active drafts, each as a map:
    %{id: draft_id, players: [%{user_id: uid, seat: seat}, …]}
  """
  def list_active_drafts_with_players do
    # 1) get all active drafts
    active =
      from(d in Draft,
        where: d.status == "active",
        select: d.id
      )
      |> Repo.all()

    # 2) for each draft, load its players (ordered by seat)
    Enum.map(active, fn draft_id ->
      players =
        from(dp in DraftPlayer,
          where: dp.draft_id == ^draft_id,
          order_by: dp.seat,
          select: %{user_id: dp.user_id, seat: dp.seat}
        )
        |> Repo.all()

      %{id: draft_id, players: players}
    end)
  end

  @doc """
    Returns a list of all supported set codes
  """
  def list_available_sets do
    import Ecto.Query

    from(c in MtgDraftServer.Cards.Card,
      distinct: true,
      select: c.set_code,
      order_by: c.set_code
    )
    |> Repo.all()
  end

  # ============================================================================
  # Private functions
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

  defp maybe_create_player(_draft, nil), do: {:ok, nil}

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

  defp maybe_multi_insert_player(multi, nil), do: multi

  defp maybe_multi_insert_player(multi, creator) do
    Ecto.Multi.run(multi, :player, fn repo, %{draft: draft} ->
      %DraftPlayer{}
      |> DraftPlayer.changeset(%{
        draft_id: draft.id,
        user_id: creator,
        seat: 1
      })
      |> repo.insert()
    end)
  end

  # ============================================================================
  # Validation Functions
  # ============================================================================

  @doc """
  Validates whether it is the given user's turn to pick.

  Optionally, an existing state can be provided to avoid an extra GenServer call.
  """
  def validate_player_turn(draft_id, user_id, state \\ nil) do
    state =
      if state != nil do
        state
      else
        case Registry.lookup(MtgDraftServer.DraftRegistry, draft_id) do
          [{pid, _}] -> GenServer.call(pid, :get_state)
          [] -> nil
        end
      end

    if state == nil do
      {:error, "Draft session not found"}
    else
      do_validate_player_turn(user_id, state)
    end
  end

  defp do_validate_player_turn(user_id, state) do
    current_user = Enum.at(state.turn_order, state.current_turn_index)
    if current_user == user_id, do: :ok, else: {:error, "Not your turn to pick"}
  end

  @doc false
  def validate_card_availability(draft_id, card_id, state \\ nil) do
    state =
      if state != nil do
        state
      else
        case Registry.lookup(MtgDraftServer.DraftRegistry, draft_id) do
          [{pid, _}] -> GenServer.call(pid, :get_state)
          [] -> nil
        end
      end

    if state == nil do
      {:error, "Draft session not found"}
    else
      do_validate_card_availability(card_id, state)
    end
  end

  defp do_validate_card_availability(card_id, state) do
    current_user = Enum.at(state.turn_order, state.current_turn_index)

    cond do
      state.booster_packs ->
        current_pack = get_current_pack_for_player(state, current_user)

        if card_in_pack?(current_pack, card_id),
          do: :ok,
          else: {:error, "Card not available in current pack"}

      card_id in state.pack ->
        :ok

      true ->
        {:error, "Card not available in current pack"}
    end
  end

  defp get_current_pack_for_player(state, user_id) do
    player_packs = Map.get(state.booster_packs, user_id, [])
    Enum.at(player_packs, state.pack_number - 1, [])
  end

  defp card_in_pack?(pack, card_id) do
    Enum.any?(pack, fn card ->
      cond do
        is_map(card) && Map.has_key?(card, :id) -> card.id == card_id
        is_map(card) && Map.has_key?(card, "id") -> card["id"] == card_id
        true -> card == card_id
      end
    end)
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

  @doc false
  defp validate_draft_active(draft) do
    if draft.status == "active" do
      :ok
    else
      {:error, "Draft is not active (current status: #{draft.status})"}
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

  defp broadcast_draft_update(draft_id, event) do
    notify(draft_id, event)
  end
end

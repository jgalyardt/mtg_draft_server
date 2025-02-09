defmodule MtgDraftServer.Drafts do
  @moduledoc """
  Context for managing drafts, players, and picks.
  This module handles all draft-related operations including creation,
  starting drafts, making picks, and retrieving draft information.
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
  Creates a new draft with an optional creator.

  ## Parameters
    * `attrs` - Map of attributes which may include:
      * `:creator` - User ID of the draft creator
      
  ## Returns
    * `{:ok, draft}` on success
    * `{:error, changeset}` on validation failure
    * `{:error, reason}` on other failures

  ## Examples
      iex> create_draft(%{creator: "user123"})
      {:ok, %Draft{}}

      iex> create_draft(%{invalid: "params"})
      {:error, %Ecto.Changeset{}}
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
  Starts a draft by updating its status to "active".
  Validates that the draft exists and has the required number of players.

  ## Parameters
    * `draft_id` - The ID of the draft to start

  ## Returns
    * `{:ok, draft}` on success
    * `{:error, reason}` on failure
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
  Validates the pick is legal and updates the draft state accordingly.

  ## Parameters
    * `draft_id` - The ID of the draft
    * `user_id` - The ID of the user making the pick
    * `card_id` - The ID of the picked card
    * `extra_attrs` - Additional attributes including:
      * `"pack_number"` - Current pack number
      * `"pick_number"` - Current pick number within the pack

  ## Returns
    * `{:ok, pick}` on success
    * `{:error, reason}` on failure
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

    # Record telemetry
    end_time = System.monotonic_time()

    :telemetry.execute(
      [:mtg_draft_server, :drafts, :pick_card],
      %{duration: end_time - start_time},
      %{draft_id: draft_id, user_id: user_id}
    )

    result
  end

  @doc """
  Retrieves all picks for a given draft and user.

  ## Parameters
    * `draft_id` - The ID of the draft
    * `user_id` - The ID of the user whose picks to retrieve

  ## Returns
    * List of picks ordered by insertion time
    * Empty list if no picks found
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
  Gets a draft by ID.

  Returns `{:ok, draft}` if found, `{:error, "Draft not found"}` if not found.
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

  # Private helper functions

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

  defp get_draft_player(draft_id, user_id) do
    case Repo.one(
           from dp in DraftPlayer,
             where: dp.draft_id == ^draft_id and dp.user_id == ^user_id,
             preload: [:draft]
         ) do
      nil -> {:error, "Player not found in draft"}
      player -> {:ok, player}
    end
  end

  defp maybe_create_player(_draft, nil), do: {:ok, nil}

  defp maybe_create_player(draft, creator) do
    DraftPlayer.create_draft_player(%{
      draft_id: draft.id,
      user_id: creator,
      seat: 1
    })
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
    # Add logic to verify it's this player's turn to pick
    # This would depend on your specific draft rules
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

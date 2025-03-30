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
  def pick_card(draft_id, user_id, card_id, extra_attrs \\ %{}) do
    # Start a transaction to ensure all validations and updates are atomic
    Repo.transaction(fn ->
      with {:ok, draft} <- get_draft(draft_id),
           :ok <- validate_draft_status(draft),
           {:ok, draft_player} <- get_draft_player(draft_id, user_id),
           :ok <- validate_player_turn(draft_id, user_id),
           :ok <- validate_card_availability(draft_id, card_id),
           :ok <- validate_pack_number(extra_attrs["pack_number"]),
           :ok <- validate_pick_number(extra_attrs["pick_number"]),
           :ok <-
             validate_no_duplicate_pick(
               draft_player.id,
               extra_attrs["pack_number"],
               extra_attrs["pick_number"]
             ) do
        # All validations passed, create the pick record
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
    # First check if player is already in this draft
    case Repo.one(from dp in DraftPlayer, 
                  where: dp.draft_id == ^draft.id and dp.user_id == ^user_id) do
      %DraftPlayer{} = existing_player ->
        # User is already in this draft, return success with existing player
        {:ok, existing_player}
        
      nil ->
        # User is not in this draft yet, check if draft is full
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
    from(dp in DraftPlayer, where: dp.draft_id == ^draft_id, select: dp.user_id)
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

  # Check if it's the player's turn to pick
  defp validate_player_turn(draft_id, user_id) do
    case Registry.lookup(MtgDraftServer.DraftRegistry, draft_id) do
      [{pid, _}] ->
        # Get current state from the draft session
        state = GenServer.call(pid, :get_state)
        current_user = Enum.at(state.turn_order, state.current_turn_index)

        if current_user == user_id do
          :ok
        else
          {:error, "Not your turn to pick"}
        end

      [] ->
        {:error, "Draft session not found"}
    end
  end

  # Check if the card is available in the current pack
  defp validate_card_availability(draft_id, card_id) do
    case Registry.lookup(MtgDraftServer.DraftRegistry, draft_id) do
      [{pid, _}] ->
        state = GenServer.call(pid, :get_state)

        # Get current player
        current_user = Enum.at(state.turn_order, state.current_turn_index)

        # For integrated boosters, check the actual booster pack
        if state.booster_packs do
          # If using real booster packs
          current_pack = get_current_pack_for_player(state, current_user)

          if card_in_pack?(current_pack, card_id) do
            :ok
          else
            {:error, "Card not available in current pack"}
          end
        else
          # Fallback for simulation packs
          if card_id in state.pack do
            :ok
          else
            {:error, "Card not available in current pack"}
          end
        end

      [] ->
        {:error, "Draft session not found"}
    end
  end

  defp get_current_pack_for_player(state, user_id) do
    # For a real draft with booster packs, this would be more complex
    # and would need to account for pack passing
    player_packs = Map.get(state.booster_packs, user_id, [])
    Enum.at(player_packs, state.pack_number - 1, [])
  end

  # Helper to check if a card is in a pack
  defp card_in_pack?(pack, card_id) do
    Enum.any?(pack, fn card ->
      # Handle both map-like structures (with string/atom keys) and Card structs
      cond do
        is_map(card) && Map.has_key?(card, :id) -> card.id == card_id
        is_map(card) && Map.has_key?(card, "id") -> card["id"] == card_id
        # For simple simulation packs with just IDs
        true -> card == card_id
      end
    end)
  end

  # Check for duplicate picks from the same player
  defp validate_no_duplicate_pick(draft_player_id, pack_number, pick_number) do
    existing_pick =
      Repo.one(
        from p in DraftPick,
          where:
            p.draft_player_id == ^draft_player_id and
              p.pack_number == ^pack_number and
              p.pick_number == ^pick_number
      )

    if existing_pick do
      {:error, "Already made a pick for this pack/pick combination"}
    else
      :ok
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

  defp validate_pack_number(pack_number) when pack_number in 1..3, do: :ok
  defp validate_pack_number(_), do: {:error, "Invalid pack number"}

  defp validate_pick_number(pick_number) when pick_number in 1..15, do: :ok
  defp validate_pick_number(_), do: {:error, "Invalid pick number"}

  defp broadcast_draft_update(draft_id, event) do
    Phoenix.PubSub.broadcast(
      MtgDraftServer.PubSub,
      "draft:#{draft_id}",
      {event, draft_id}
    )
  end
end

defmodule MtgDraftServer.DraftSession do
  @moduledoc """
  A GenServer that represents a draft session and manages picking order.

  The session state includes:
    - the current (simulation) pack (a list of card IDs or card data) used before the draft starts
    - the turn order (a list of user IDs)
    - the current turn index
    - the pack number (1, 2, or 3) and pick number within the pack

  **New behavior:** When a player joins the session and the total number of players reaches 8, the draft
  automatically “starts” by generating 8×3 booster packs (24 packs total, each containing 15 cards)
  via the `MtgDraftServer.Drafts.PackGenerator`. The resulting booster pack distribution (a map of
  player ID to a list of 3 packs) is stored in the session state (in the `booster_packs` field) and a
  broadcast is issued to notify connected clients that the draft has started.

  (Note: This example uses a simplified simulation for the picking process. You may later wish to
  update the pick logic so that players draft from their distributed booster packs.)
  """

  use GenServer
  alias MtgDraftServer.Drafts

  ## Client API

  def start_link(draft_id) do
    GenServer.start_link(__MODULE__, draft_id, name: via_tuple(draft_id))
  end

  def join(draft_id, player) do
    GenServer.call(via_tuple(draft_id), {:join, player})
  end

  def pick(draft_id, user_id, card_id) do
    GenServer.cast(via_tuple(draft_id), {:pick, user_id, card_id})
  end

  def get_state(draft_id) do
    GenServer.call(via_tuple(draft_id), :get_state)
  end

  defp via_tuple(draft_id) do
    {:via, Registry, {MtgDraftServer.DraftRegistry, draft_id}}
  end

  ## Server Callbacks

  @impl true
  def init(draft_id) do
    # Initial state for an empty draft session
    state = %{
      draft_id: draft_id,
      # map of user_id => player info
      players: %{},
      # list of user_ids in picking order
      turn_order: [],
      # index in turn_order that is picking
      current_turn_index: 0,
      # legacy/simulation field
      pack: [],
      # current pack number (1, 2, or 3)
      pack_number: 1,
      # pick number within the current pack
      pick_number: 1,
      status: :pending,
      # map of user_id => list of 3 booster packs
      booster_packs: nil,
      # flag for when booster packs are generated
      draft_started: false,
      # direction packs are being passed
      current_pack_direction: :left
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:join, player}, _from, state) do
    user_id = player["user_id"] || player[:user_id]
    new_players = Map.put(state.players, user_id, player)
    new_turn_order = state.turn_order ++ [user_id]
    new_state = %{state | players: new_players, turn_order: new_turn_order}

    # If this is the 8th player and the draft has not yet started,
    # generate booster packs and update the state
    if map_size(new_players) == 8 and not state.draft_started do
      # Generate and distribute booster packs
      booster_packs =
        MtgDraftServer.Drafts.PackGenerator.generate_and_distribute_booster_packs(
          %{},
          new_turn_order
        )

      updated_state =
        new_state
        |> Map.put(:booster_packs, booster_packs)
        |> Map.put(:draft_started, true)
        |> Map.put(:status, :active)
        # Pass left for pack 1
        |> Map.put(:current_pack_direction, :left)

      # Broadcast the draft started event
      Phoenix.PubSub.broadcast(
        MtgDraftServer.PubSub,
        "draft:#{state.draft_id}",
        {:draft_started, updated_state.draft_id}
      )

      # Update the database draft status
      Drafts.start_draft(state.draft_id)

      {:reply, :ok, updated_state}
    else
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:start_draft_with_boosters, _from, state) do
    if not state.draft_started and length(state.turn_order) >= 2 do
      # Generate and distribute booster packs
      booster_packs =
        MtgDraftServer.Drafts.PackGenerator.generate_and_distribute_booster_packs(
          %{},
          state.turn_order
        )

      updated_state =
        state
        |> Map.put(:booster_packs, booster_packs)
        |> Map.put(:draft_started, true)
        |> Map.put(:status, :active)
        # Pass left for pack 1
        |> Map.put(:current_pack_direction, :left)
        # Clear simulation pack
        |> Map.put(:pack, [])

      # Update the database draft status
      Drafts.start_draft(state.draft_id)

      # Broadcast the draft started event
      Phoenix.PubSub.broadcast(
        MtgDraftServer.PubSub,
        "draft:#{state.draft_id}",
        {:draft_started, updated_state.draft_id}
      )

      {:reply, {:ok, updated_state}, updated_state}
    else
      {:reply, {:error, "Cannot start draft"}, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:pick, user_id, card_id}, state) do
    current_user = Enum.at(state.turn_order, state.current_turn_index)

    if user_id == current_user do
      if state.booster_packs do
        # Process the pick with real booster packs
        handle_real_booster_pick(state, user_id, card_id)
      else
        # No booster packs available
        {:noreply, state}
      end
    else
      # Not this player's turn
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:ai_pick, user_id}, state) do
    if Enum.at(state.turn_order, state.current_turn_index) == user_id do
      if state.booster_packs do
        # Get the current pack for this AI player
        player_packs = Map.get(state.booster_packs, user_id, [])
        current_pack = Enum.at(player_packs, state.pack_number - 1, [])

        if current_pack != [] do
          # Pick a random card from the pack
          random_card = Enum.random(current_pack)

          card_id =
            case random_card do
              %{id: id} -> id
              %{"id" => id} -> id
              simple_id when is_binary(simple_id) -> simple_id
              _ -> nil
            end

          if card_id do
            IO.puts("AI #{user_id} auto-picks card #{card_id}.")
            GenServer.cast(self(), {:pick, user_id, card_id})
          end
        end
      end
    end

    {:noreply, state}
  end

  # ============================================================================
  # Private functions
  # ============================================================================

  defp handle_real_booster_pick(state, user_id, card_id) do
    # Get current pack for this user
    current_player_packs = Map.get(state.booster_packs, user_id, [])
    current_pack_index = state.pack_number - 1
    current_pack = Enum.at(current_player_packs, current_pack_index, [])

    # Find the selected card in the pack
    picked_card =
      Enum.find(current_pack, fn card ->
        case card do
          %{id: id} -> id == card_id
          %{"id" => id} -> id == card_id
          _ -> false
        end
      end)

    if picked_card do
      # Record the pick in the database
      _ =
        Drafts.pick_card(state.draft_id, user_id, card_id, %{
          "pack_number" => state.pack_number,
          "pick_number" => state.pick_number
        })

      # Remove card from the current pack
      updated_pack =
        Enum.reject(current_pack, fn card ->
          case card do
            %{id: id} -> id == card_id
            %{"id" => id} -> id == card_id
            _ -> false
          end
        end)

      # Update player's packs with the card removed
      updated_player_packs =
        List.replace_at(current_player_packs, current_pack_index, updated_pack)

      updated_booster_packs = Map.put(state.booster_packs, user_id, updated_player_packs)

      # Determine the next player to receive this pack
      next_player_index = next_player_index(state)
      next_player = Enum.at(state.turn_order, next_player_index)

      # If there are still cards in the pack, pass it to the next player
      if updated_pack != [] do
        # Pass the pack to the next player
        updated_booster_packs =
          pass_pack(
            updated_booster_packs,
            user_id,
            next_player,
            updated_pack,
            current_pack_index
          )

        # Move to the next player's turn
        updated_state = %{
          state
          | booster_packs: updated_booster_packs,
            current_turn_index: next_player_index,
            pick_number: state.pick_number + 1
        }

        # Broadcast the pack update
        Phoenix.PubSub.broadcast(
          MtgDraftServer.PubSub,
          "draft:#{state.draft_id}",
          {:pack_updated, next_player, state.pack_number, state.pick_number + 1}
        )

        # Schedule AI pick if needed
        maybe_schedule_ai(updated_state)

        {:noreply, updated_state}
      else
        # This pack is now empty, check if we need to move to the next pack
        # Check if all players have empty packs for this round
        if current_pack_empty?(updated_booster_packs) do
          if state.pack_number < 3 do
            # Move to the next pack
            new_pack_number = state.pack_number + 1
            new_direction = if new_pack_number == 2, do: :right, else: :left

            updated_state = %{
              state
              | booster_packs: updated_booster_packs,
                pack_number: new_pack_number,
                pick_number: 1,
                # Reset to first player for new pack
                current_turn_index: 0,
                current_pack_direction: new_direction
            }

            # Broadcast the new pack event
            Phoenix.PubSub.broadcast(
              MtgDraftServer.PubSub,
              "draft:#{state.draft_id}",
              {:new_pack, new_pack_number}
            )

            maybe_schedule_ai(updated_state)
            {:noreply, updated_state}
          else
            # Draft is complete
            completed_state = complete_draft(state)
            {:stop, :normal, completed_state}
          end
        else
          # Handle the case where only this player's pack is empty
          # but others are still picking
          updated_state = %{
            state
            | booster_packs: updated_booster_packs,
              current_turn_index: next_player_index
          }

          {:noreply, updated_state}
        end
      end
    else
      # Card not found in pack
      {:noreply, state}
    end
  end

  defp pass_pack(booster_packs, _from_player, to_player, pack, pack_index) do
    # Get the recipient's existing packs
    to_player_packs = Map.get(booster_packs, to_player, [])

    # Update the recipient's packs with the new pack
    updated_to_player_packs =
      if Enum.count(to_player_packs) > pack_index do
        List.replace_at(to_player_packs, pack_index, pack)
      else
        # Ensure the list is long enough
        pad_list(to_player_packs, pack_index, []) ++ [pack]
      end

    # Update the booster packs map
    Map.put(booster_packs, to_player, updated_to_player_packs)
  end

  defp pad_list(list, target_index, padding) do
    current_length = length(list)

    if current_length <= target_index do
      list ++ List.duplicate(padding, target_index - current_length)
    else
      list
    end
  end

  defp next_player_index(state) do
    player_count = length(state.turn_order)
    current_index = state.current_turn_index

    case state.current_pack_direction do
      :left ->
        # Pass to the left (increment index)
        rem(current_index + 1, player_count)

      :right ->
        # Pass to the right (decrement index)
        rem(player_count + current_index - 1, player_count)
    end
  end

  # Check if all cards in the current pack have been picked
  defp current_pack_empty?(booster_packs) do
    # Check if every player has an empty pack for the current pack number
    Enum.all?(booster_packs, fn {_player_id, packs} ->
      # Current pack is always the first one
      current_pack = Enum.at(packs, 0, [])
      current_pack == []
    end)
  end

  # If the next player is AI, schedule an automatic pick after 1 second.
  defp maybe_schedule_ai(state) do
    next_player = Enum.at(state.turn_order, state.current_turn_index)
    next_player_info = Map.get(state.players, next_player, %{})

    if Map.get(next_player_info, "ai") || Map.get(next_player_info, :ai) do
      Process.send_after(self(), {:ai_pick, next_player}, 1_000)
    end
  end

  # Complete the draft and clean up
  defp complete_draft(state) do
    # Mark draft as complete in the database
    Drafts.complete_draft(state.draft_id)

    # Broadcast completion message
    Phoenix.PubSub.broadcast(
      MtgDraftServer.PubSub,
      "draft:#{state.draft_id}",
      {:draft_complete, state.draft_id}
    )

    # Return the state unchanged, as we'll stop the process after this
    %{state | status: :complete}
  end
end

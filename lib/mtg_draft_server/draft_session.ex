defmodule MtgDraftServer.DraftSession do
  @moduledoc """
  A GenServer that represents a draft session and manages picking order.

  The session state includes:
    - the current (simulation) pack (a list of card IDs or card data) used before the draft starts
    - the turn order (a list of user IDs)
    - the current turn index
    - the pack number (1, 2, or 3) and pick number within the pack

  **New behavior:** When a player joins the session and the total number of players reaches 8, the draft
  automatically "starts" by generating 8×3 booster packs (24 packs total, each containing 15 cards)
  via the `MtgDraftServer.Drafts.PackGenerator`. The resulting booster pack distribution (a map of
  player ID to a list of 3 packs) is stored in the session state (in the `booster_packs` field) and a
  broadcast is issued to notify connected clients that the draft has started.
  """

  use GenServer
  alias MtgDraftServer.Drafts
  import Ecto.Query

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
    state = %{
      draft_id: draft_id,
      players: %{},
      turn_order: [],
      current_turn_index: 0,
      pack: [],
      pack_number: 1,
      pick_number: 1,
      status: :pending,
      booster_packs: nil,
      draft_started: false,
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

    if map_size(new_players) == 8 and not state.draft_started do
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
        |> Map.put(:current_pack_direction, :left)

      Phoenix.PubSub.broadcast(
        MtgDraftServer.PubSub,
        "draft:#{state.draft_id}",
        {:draft_started, updated_state.draft_id}
      )

      Drafts.start_draft(state.draft_id)
      
      # Trigger AI pick if first player is AI
      maybe_schedule_ai(updated_state)

      {:reply, :ok, updated_state}
    else
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:start_draft_with_boosters, _from, state) do
    if not state.draft_started and length(state.turn_order) >= 2 do
      # Get the draft to check if it has specific set configurations
      {:ok, draft} = Drafts.get_draft(state.draft_id)
      player_count = length(state.turn_order)

      booster_packs =
        if draft.pack_sets && length(draft.pack_sets) > 0 do
          # Use specific set configuration
          MtgDraftServer.Drafts.PackGenerator.generate_multi_set_packs(
            player_count,
            draft.pack_sets
          )
        else
          # Use default method (all sets)
          MtgDraftServer.Drafts.PackGenerator.generate_and_distribute_booster_packs(
            %{},
            state.turn_order
          )
        end

      updated_state =
        state
        |> Map.put(:booster_packs, booster_packs)
        |> Map.put(:draft_started, true)
        |> Map.put(:status, :active)
        |> Map.put(:current_pack_direction, :left)
        |> Map.put(:pack, [])
        |> Map.put(:pack_sets, draft.pack_sets)

      Drafts.start_draft(state.draft_id)

      Phoenix.PubSub.broadcast(
        MtgDraftServer.PubSub,
        "draft:#{state.draft_id}",
        {:draft_started, updated_state.draft_id, updated_state.pack_sets}
      )
      
      # Trigger AI pick if first player is AI
      maybe_schedule_ai(updated_state)

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
    # Do validation directly with the state we already have
    current_user = Enum.at(state.turn_order, state.current_turn_index)
    
    if current_user == user_id do
      # Check if card is available in current pack
      current_pack = get_current_pack_for_player(state, user_id)
      
      if card_in_pack?(current_pack, card_id) do
        # Create a separate process to handle database operations
        # This prevents deadlocks by avoiding circular dependencies
        spawn(fn ->
          # First get the player id directly without using the GenServer
          case MtgDraftServer.Repo.one(
            from dp in MtgDraftServer.Drafts.DraftPlayer,
            where: dp.draft_id == ^state.draft_id and dp.user_id == ^user_id,
            select: dp.id
          ) do
            nil -> 
              IO.puts("Player #{user_id} not found in draft #{state.draft_id}")
              
            player_id ->
              # Create the pick directly in the database
              now = DateTime.utc_now() |> DateTime.truncate(:second)
              expires_at = DateTime.add(now, 86400, :second)
              
              attrs = %{
                draft_id: state.draft_id,
                draft_player_id: player_id,
                card_id: card_id,
                pack_number: state.pack_number,
                pick_number: state.pick_number,
                expires_at: expires_at
              }
              
              case %MtgDraftServer.Drafts.DraftPick{}
                |> MtgDraftServer.Drafts.DraftPick.changeset(attrs)
                |> MtgDraftServer.Repo.insert() do
                {:ok, pick} -> 
                  IO.puts("Pick #{pick.id} recorded for player #{user_id}")
                {:error, changeset} -> 
                  IO.puts("Error recording pick: #{inspect(changeset.errors)}")
              end
          end
        end)
        
        # Update game state
        new_state = handle_pack_updates(state, user_id, card_id)
        {:noreply, new_state}
      else
        IO.puts("Card #{card_id} not available in current pack")
        {:noreply, state}
      end
    else
      IO.puts("Not player #{user_id}'s turn. Current turn: #{current_user}")
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:ai_pick, user_id}, state) do
    if Enum.at(state.turn_order, state.current_turn_index) == user_id do
      if state.booster_packs do
        player_packs = Map.get(state.booster_packs, user_id, [])
        current_pack = Enum.at(player_packs, state.pack_number - 1, [])

        if current_pack != [] do
          # Sort cards by a simple heuristic (rarity for now)
          # This makes AI picks slightly more realistic
          sorted_cards = Enum.sort_by(current_pack, fn card ->
            priority = case card do
              %{rarity: "mythic"} -> 1
              %{rarity: "rare"} -> 2
              %{rarity: "uncommon"} -> 3
              %{rarity: "common"} -> 4
              %{"rarity" => "mythic"} -> 1
              %{"rarity" => "rare"} -> 2
              %{"rarity" => "uncommon"} -> 3
              %{"rarity" => "common"} -> 4
              _ -> 5
            end
            # Add some randomness so it's not always picking the best card
            priority + :rand.uniform()
          end)
          
          # Pick the first card after sorting
          best_card = List.first(sorted_cards)

          card_id =
            case best_card do
              %{id: id} -> id
              %{"id" => id} -> id
              simple_id when is_binary(simple_id) -> simple_id
              _ -> nil
            end

          if card_id do
            IO.puts("AI #{user_id} picks card #{card_id}.")
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

  # Renamed from handle_real_booster_pick to better reflect its purpose
  defp handle_pack_updates(state, user_id, card_id) do
    current_player_packs = Map.get(state.booster_packs, user_id, [])
    current_pack_index = state.pack_number - 1
    current_pack = Enum.at(current_player_packs, current_pack_index, [])

    # Remove picked card from pack
    updated_pack =
      Enum.reject(current_pack, fn card ->
        case card do
          %{id: id} -> id == card_id
          %{"id" => id} -> id == card_id
          _ -> false
        end
      end)

    updated_player_packs =
      List.replace_at(current_player_packs, current_pack_index, updated_pack)

    updated_booster_packs = Map.put(state.booster_packs, user_id, updated_player_packs)
    next_player_index = next_player_index(state)
    next_player = Enum.at(state.turn_order, next_player_index)

    cond do
      updated_pack != [] ->
        updated_booster_packs =
          pass_pack(
            updated_booster_packs,
            user_id,
            next_player,
            updated_pack,
            current_pack_index
          )

        updated_state = %{
          state
          | booster_packs: updated_booster_packs,
            current_turn_index: next_player_index,
            pick_number: state.pick_number + 1
        }

        Phoenix.PubSub.broadcast(
          MtgDraftServer.PubSub,
          "draft:#{state.draft_id}",
          {:pack_updated, next_player, state.pack_number, state.pick_number + 1}
        )

        maybe_schedule_ai(updated_state)
        updated_state

      current_pack_empty?(updated_booster_packs) and state.pack_number < 3 ->
        new_pack_number = state.pack_number + 1
        new_direction = if new_pack_number == 2, do: :right, else: :left

        updated_state = %{
          state
          | booster_packs: updated_booster_packs,
            pack_number: new_pack_number,
            pick_number: 1,
            current_turn_index: 0,
            current_pack_direction: new_direction
        }

        Phoenix.PubSub.broadcast(
          MtgDraftServer.PubSub,
          "draft:#{state.draft_id}",
          {:new_pack, new_pack_number}
        )

        maybe_schedule_ai(updated_state)
        updated_state

      current_pack_empty?(updated_booster_packs) and state.pack_number >= 3 ->
        # Final pack is empty; complete the draft.
        complete_draft(state)

      true ->
        updated_state = %{
          state
          | booster_packs: updated_booster_packs,
            current_turn_index: next_player_index
        }

        updated_state
    end
  end

  defp get_current_pack_for_player(state, user_id) do
    if state.booster_packs do
      player_packs = Map.get(state.booster_packs, user_id, [])
      Enum.at(player_packs, state.pack_number - 1, [])
    else
      []
    end
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

  defp pass_pack(booster_packs, _from_player, to_player, pack, pack_index) do
    to_player_packs = Map.get(booster_packs, to_player, [])

    updated_to_player_packs =
      if Enum.count(to_player_packs) > pack_index do
        List.replace_at(to_player_packs, pack_index, pack)
      else
        pad_list(to_player_packs, pack_index, []) ++ [pack]
      end

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
        rem(current_index + 1, player_count)

      :right ->
        rem(player_count + current_index - 1, player_count)
    end
  end

  defp current_pack_empty?(booster_packs) do
    Enum.all?(booster_packs, fn {_player_id, packs} ->
      current_pack = Enum.at(packs, 0, [])
      current_pack == []
    end)
  end

  defp maybe_schedule_ai(state) do
    next_player = Enum.at(state.turn_order, state.current_turn_index)
    next_player_info = Map.get(state.players, next_player, %{})

    if Map.get(next_player_info, "ai") || Map.get(next_player_info, :ai) do
      Process.send_after(self(), {:ai_pick, next_player}, 1_000)
    end
  end

  defp complete_draft(state) do
    Drafts.complete_draft(state.draft_id)

    Phoenix.PubSub.broadcast(
      MtgDraftServer.PubSub,
      "draft:#{state.draft_id}",
      {:draft_complete, state.draft_id}
    )

    %{state | status: :complete}
  end
end
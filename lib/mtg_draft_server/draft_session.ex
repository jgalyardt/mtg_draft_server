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
    # For simulation, before the draft starts we use a simple pack of numbers 1..15.
    initial_pack = Enum.to_list(1..15)
    state = %{
      draft_id: draft_id,
      players: %{},            # map of user_id => player info (optionally includes "ai" flag)
      turn_order: [],          # list of user_ids in picking order
      current_turn_index: 0,   # index in turn_order that is picking
      pack: initial_pack,      # a simulation pack used before the full draft starts
      pack_number: 1,          # current pack number (1, 2, or 3)
      pick_number: 1,          # pick number within the current pack
      status: :pending,
      booster_packs: nil,      # will be populated once 8 players have joined
      draft_started: false     # flag indicating whether the draft (booster generation) has started
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:join, player}, _from, state) do
    user_id = player["user_id"] || player[:user_id]
    new_players = Map.put(state.players, user_id, player)
    new_turn_order = state.turn_order ++ [user_id]
    new_state = %{state | players: new_players, turn_order: new_turn_order}

    IO.puts("Player #{user_id} joined (AI? #{inspect(Map.get(player, "ai") || Map.get(player, :ai) || false)})")

    # If this is the 8th player and the draft has not yet started,
    # generate 24 booster packs (8 players × 3 packs per player) and update the state.
    if map_size(new_players) == 8 and not state.draft_started do
      # Use default options (set_codes, allowed_rarities, distribution) as defined in the PackGenerator.
      booster_packs = MtgDraftServer.Drafts.PackGenerator.generate_and_distribute_booster_packs(%{}, new_turn_order)
      
      updated_state =
        new_state
        |> Map.put(:booster_packs, booster_packs)
        |> Map.put(:draft_started, true)
        |> Map.put(:status, :active)

      IO.puts("Draft reached 8 players. Booster packs generated and draft started.")
      
      Phoenix.PubSub.broadcast(
        MtgDraftServer.PubSub,
        "draft:#{state.draft_id}",
        {:draft_started, booster_packs}
      )

      {:reply, :ok, updated_state}
    else
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:pick, user_id, card_id}, state) do
    current_user = Enum.at(state.turn_order, state.current_turn_index)

    if user_id == current_user and card_id in state.pack do
      new_pack = List.delete(state.pack, card_id)
      current_pick = state.pick_number
      current_pack = state.pack_number

      IO.puts("User #{user_id} picked card #{card_id} (pack #{current_pack}, pick #{current_pick}).")

      # Persist the pick (assumes Drafts.pick_card/4 exists).
      _ = Drafts.pick_card(state.draft_id, user_id, card_id, %{
        "pack_number" => current_pack,
        "pick_number" => current_pick
      })

      new_pick_number = current_pick + 1

      cond do
        # End of current pack and it is not the final (third) pack.
        new_pack == [] and state.pack_number < 3 ->
          new_pack_generated = generate_pack(state.pack_number + 1)
          updated_state = %{
            state
            | pack: new_pack_generated,
              pack_number: state.pack_number + 1,
              pick_number: 1,
              current_turn_index: rem(state.current_turn_index + 1, length(state.turn_order))
          }
          Phoenix.PubSub.broadcast(
            MtgDraftServer.PubSub,
            "draft:#{state.draft_id}",
            {:new_pack, updated_state.pack, updated_state.pack_number}
          )
          maybe_schedule_ai(updated_state)
          {:noreply, updated_state}

        # End of final (third) pack – draft complete.
        new_pack == [] and state.pack_number == 3 ->
          Phoenix.PubSub.broadcast(
            MtgDraftServer.PubSub,
            "draft:#{state.draft_id}",
            {:draft_complete, state.draft_id}
          )
          _ = Drafts.complete_draft(state.draft_id)
          {:stop, :normal, state}

        # Normal pick – pack still has cards.
        true ->
          updated_state = %{
            state
            | pack: new_pack,
              pick_number: new_pick_number,
              current_turn_index: rem(state.current_turn_index + 1, length(state.turn_order))
          }
          Phoenix.PubSub.broadcast(
            MtgDraftServer.PubSub,
            "draft:#{state.draft_id}",
            {:pack_updated, updated_state.pack, Enum.at(updated_state.turn_order, updated_state.current_turn_index)}
          )
          maybe_schedule_ai(updated_state)
          {:noreply, updated_state}
      end
    else
      IO.puts("Pick rejected: either not #{user_id}'s turn or card #{card_id} not in pack.")
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:ai_pick, user_id}, state) do
    if Enum.at(state.turn_order, state.current_turn_index) == user_id and state.pack != [] do
      random_card = Enum.random(state.pack)
      IO.puts("AI #{user_id} auto-picks card #{random_card}.")
      GenServer.cast(self(), {:pick, user_id, random_card})
    end
    {:noreply, state}
  end

  # Helper: Simulate a new pack based on pack number.
  defp generate_pack(2), do: Enum.to_list(16..30)
  defp generate_pack(3), do: Enum.to_list(31..45)

  # Helper: If the next player is AI, schedule an automatic pick after 1 second.
  defp maybe_schedule_ai(state) do
    next_player = Enum.at(state.turn_order, state.current_turn_index)
    next_player_info = Map.get(state.players, next_player, %{})
    if Map.get(next_player_info, "ai") || Map.get(next_player_info, :ai) do
      Process.send_after(self(), {:ai_pick, next_player}, 1_000)
    end
  end
end

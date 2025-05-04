defmodule MtgDraftServer.DraftSession do
  @moduledoc """
  A GenServer that manages a Magic: The Gathering draft session with asynchronous,
  queue‑based picking. Each player starts with three booster packs. Packs are
  passed around in alternating directions (left for rounds 1 & 3, right for round 2).
  Players (human or AI) may pick as soon as they have cards in their head pack,
  and “pile‑up” behavior is automatic via per‑player FIFO queues.
  """

  use GenServer
  alias MtgDraftServer.Drafts
  alias MtgDraftServer.Drafts.PackGenerator
  alias MtgDraftServer.DraftSession.PackDistributor
  require Logger

  ## Client API

  @doc """
  Start the session process for a given draft ID.
  """
  def start_link(draft_id) do
    GenServer.start_link(__MODULE__, draft_id, name: via_tuple(draft_id))
  end

  @doc """
  Join a player (or AI) into the session. Expects a map with "user_id" and
  optional "ai" boolean (defaults to false).
  """
  def join(draft_id, %{"user_id" => uid} = player) do
    ai_flag = Map.get(player, "ai", false)
    GenServer.call(via_tuple(draft_id), {:join, uid, ai_flag})
  end

  @doc """
  Submit a pick for a given user and card ID.
  """
  def pick(draft_id, user_id, card_id) do
    GenServer.cast(via_tuple(draft_id), {:pick, user_id, card_id})
  end

  @doc """
  Fetch the entire in‑memory session state.
  """
  def get_state(draft_id) do
    GenServer.call(via_tuple(draft_id), :get_state)
  end

  defp via_tuple(draft_id) do
    {:via, Registry, {MtgDraftServer.DraftRegistry, draft_id}}
  end

  ## Server Callbacks

  @impl true
  def init(draft_id) do
    {:ok, db_draft} = Drafts.get_draft(draft_id)

    state = %{
      draft_id: draft_id,
      status: db_draft.status,
      # user_id => %{ai: boolean}
      players: %{},
      # user_id => [{round_number, pack_list}, ...]
      booster_queues: %{},
      current_round: 1,
      # seating order by user_id
      player_positions: [],
      # %{user_id => %{1 => 0, 2 => 0, 3 => 0}}
      pick_counters: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:join, uid, ai_flag}, _from, state) do
    players = Map.put(state.players, uid, %{ai: ai_flag})
    queues = Map.put_new(state.booster_queues, uid, [])
    counters = Map.put_new(state.pick_counters, uid, %{1 => 0, 2 => 0, 3 => 0})

    {:reply, :ok, %{state | players: players, booster_queues: queues, pick_counters: counters}}
  end

  @impl true
  def handle_call({:start_with_options, opts}, _from, state) do
    player_ids = MtgDraftServer.Drafts.get_draft_players(state.draft_id)
    booster_map = PackGenerator.generate_and_distribute_booster_packs(opts, player_ids)

    # Restructure booster queues by round
    round_separated_queues =
      Enum.map(player_ids, fn uid ->
        # Get the player's 3 packs (one for each round)
        player_packs = Map.get(booster_map, uid, [])

        # Create a map with round numbers as keys
        round_queues =
          player_packs
          |> Enum.with_index(1)
          |> Enum.reduce(%{}, fn {pack, round}, acc ->
            Map.put(acc, round, [pack])
          end)

        {uid, round_queues}
      end)
      |> Enum.into(%{})

    # Update state with the new structure
    {:ok, _updated} = Drafts.start_draft(state.draft_id)

    new_state = %{
      state
      | booster_queues: round_separated_queues,
        current_round: 1,
        status: "active",
        player_positions: player_ids,
        pick_counters: Enum.into(player_ids, %{}, fn uid -> {uid, %{1 => 0, 2 => 0, 3 => 0}} end)
    }

    # Broadcast and schedule AI
    Drafts.notify(state.draft_id, {:draft_started, state.draft_id, []})

    Enum.each(player_ids, fn uid ->
      if state.players[uid].ai do
        Process.send_after(self(), {:ai_pick, uid}, 500)
      end
    end)

    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:pick, user_id, card_id}, state) do
    current_round = state.current_round
    user_queues = Map.get(state.booster_queues, user_id, %{})
    current_round_queue = Map.get(user_queues, current_round, [])

    # Handle empty queue case
    if current_round_queue == [] do
      Logger.info("User #{user_id} has no packs in round #{current_round}")
      {:noreply, state}
    else
      # Get the first pack in the queue for this round
      current_pack = List.first(current_round_queue)

      if current_pack && PackDistributor.card_in_pack?(current_pack, card_id) do
        # Process the pick
        Logger.debug("Removing card #{card_id} from pack of size #{length(current_pack)}")
        updated_pack = PackDistributor.remove_card(current_pack, card_id)
        Logger.debug("Pack size after removal: #{length(updated_pack)}")

        # Determine direction based on round
        direction = if current_round == 2, do: :right, else: :left
        neighbor = PackDistributor.next_neighbor(user_id, state.player_positions, direction)

        # Update pick counter
        user_counters = Map.get(state.pick_counters, user_id, %{1 => 0, 2 => 0, 3 => 0})
        pick_no = user_counters[current_round] + 1

        # Persist pick
        {:ok, _pick} =
          Drafts.pick_card(
            state.draft_id,
            user_id,
            card_id,
            %{"pack_number" => current_round, "pick_number" => pick_no}
          )

        # Update queues for current round
        new_user_queues =
          if updated_pack == [] do
            # If pack is empty, remove it from the queue
            Map.put(user_queues, current_round, Enum.drop(current_round_queue, 1))
          else
            # Otherwise, remove the first pack and add the updated one to the end
            new_queue = Enum.drop(current_round_queue, 1)
            Map.put(user_queues, current_round, new_queue)
          end

        # Only pass non-empty packs
        new_neighbor_queues =
          if updated_pack == [] do
            Map.get(state.booster_queues, neighbor, %{})
          else
            neighbor_queues = Map.get(state.booster_queues, neighbor, %{})
            neighbor_round_queue = Map.get(neighbor_queues, current_round, [])
            Map.put(neighbor_queues, current_round, neighbor_round_queue ++ [updated_pack])
          end

        # Update the state with new queues
        new_booster_queues =
          state.booster_queues
          |> Map.put(user_id, new_user_queues)
          |> Map.put(neighbor, new_neighbor_queues)

        # Update pick counters
        new_pick_counters =
          state.pick_counters
          |> Map.put(user_id, Map.put(user_counters, current_round, pick_no))

        # Check if round is complete
        new_state = %{
          state
          | booster_queues: new_booster_queues,
            pick_counters: new_pick_counters
        }

        # Determine if we need to advance to the next round
        round_complete =
          new_booster_queues
          |> Map.values()
          |> Enum.all?(fn user_queues ->
            round_queue = Map.get(user_queues, current_round, [])
            round_queue == []
          end)

        new_state =
          cond do
            round_complete && current_round < 3 ->
              # Advance to next round
              %{new_state | current_round: current_round + 1}

            round_complete && current_round == 3 ->
              # Draft is complete
              {:ok, _} = MtgDraftServer.Drafts.complete_draft(state.draft_id)
              MtgDraftServer.Drafts.notify(state.draft_id, {:draft_completed, state.draft_id})
              %{new_state | status: "complete"}

            true ->
              # Stay on current round
              new_state
          end

        # Notify and schedule AI pick if needed
        Drafts.notify(state.draft_id, {:pack_updated, user_id, neighbor})

        if state.players[neighbor].ai do
          Process.send_after(self(), {:ai_pick, neighbor}, 500)
        end

        {:noreply, new_state}
      else
        Logger.error("Invalid pick #{card_id} by #{user_id}")
        {:noreply, state}
      end
    end
  end

  @impl true
  def handle_info({:ai_pick, user_id}, state) do
    current_round = state.current_round
    user_queues = Map.get(state.booster_queues, user_id, %{})
    current_round_queue = Map.get(user_queues, current_round, [])

    # Handle empty queue case
    if current_round_queue == [] do
      Logger.info("AI #{user_id} has no packs to pick from in round #{current_round}")
      {:noreply, state}
    else
      # Get the first pack in the queue
      current_pack = List.first(current_round_queue)

      if current_pack && length(current_pack) > 0 do
        # Get card to pick (first card or random)
        head = List.first(current_pack)
        card = ai_select_card(current_pack, head)
        card_id = extract_card_id(card)

        # Log the pick
        Logger.info(
          "AI #{user_id} picking card #{inspect(card_id)} " <>
            "from pack of size #{length(current_pack)} in round #{current_round}"
        )

        # Make the pick if we have a valid card ID
        if card_id do
          GenServer.cast(self(), {:pick, user_id, card_id})
        else
          Logger.error("AI pick failed: Invalid card format: #{inspect(card)}")
        end

        {:noreply, state}
      else
        Logger.info("AI #{user_id} has empty pack in queue for round #{current_round}")
        {:noreply, state}
      end
    end
  end

  # Private functions

  defp ai_select_card(pack, default) do
    try do
      Enum.random(pack)
    rescue
      _ ->
        Logger.warning("Enum.random failed, using first card")
        default
    end
  end

  defp extract_card_id(card) do
    cond do
      is_map(card) && Map.has_key?(card, :id) -> card.id
      is_map(card) && Map.has_key?(card, "id") -> card["id"]
      is_binary(card) -> card
      true -> nil
    end
  end
end

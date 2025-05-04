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
  Kick off the draft by generating booster packs and loading them into state.
  Call this once all players have joined.
  """
  def start_with_boosters(draft_id) do
    GenServer.call(via_tuple(draft_id), :start_draft_with_boosters)
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
  def handle_call(:start_draft_with_boosters, _from, _state) do
  end

  @impl true
  def handle_call({:start_with_options, opts}, _from, state) do
    # 1) Determine seating and generate packs
    player_ids = MtgDraftServer.Drafts.get_draft_players(state.draft_id)
    booster_map = PackGenerator.generate_and_distribute_booster_packs(opts, player_ids)

    # 2) Wrap packs with round numbers: Enum.with_index returns {pack, round}
    wrapped_queues =
      booster_map
      |> Enum.map(fn {uid, packs} ->
        indexed =
          packs
          |> Enum.with_index(1)
          |> Enum.map(fn {pack, round} -> {round, pack} end)

        {uid, indexed}
      end)
      |> Enum.into(%{})

    # 3) Persist draft status and update in-memory state
    {:ok, _updated} = Drafts.start_draft(state.draft_id)

    new_state = %{
      state
      | booster_queues: wrapped_queues,
        status: "active",
        player_positions: player_ids,
        pick_counters: Enum.into(player_ids, %{}, fn uid -> {uid, %{1 => 0, 2 => 0, 3 => 0}} end)
    }

    # 4) Broadcast and schedule AI
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
    case Map.get(state.booster_queues, user_id, []) do
      [{round, current_pack} | rest] ->
        if PackDistributor.card_in_pack?(current_pack, card_id) do
          updated_pack = PackDistributor.remove_card(current_pack, card_id)
          direction = if round == 2, do: :right, else: :left
          neighbor = PackDistributor.next_neighbor(user_id, state.player_positions, direction)

          # get and bump pick number
          user_counters = Map.get(state.pick_counters, user_id, %{1 => 0, 2 => 0, 3 => 0})
          pick_no = user_counters[round] + 1

          # persist pick with tuple match for {:ok, pick}
          {:ok, _pick} =
            Drafts.pick_card(
              state.draft_id,
              user_id,
              card_id,
              %{"pack_number" => round, "pick_number" => pick_no}
            )

          Drafts.notify(state.draft_id, {:pack_updated, user_id, neighbor})

          if state.players[neighbor].ai do
            Process.send_after(self(), {:ai_pick, neighbor}, 500)
          end

          q1 = if updated_pack == [], do: rest, else: rest ++ [{round, updated_pack}]
          q2 = Map.get(state.booster_queues, neighbor, []) ++ [{round, updated_pack}]

          # 1) Update the booster queues as before
          new_queues =
            state.booster_queues
            |> Map.put(user_id, q1)
            |> Map.put(neighbor, q2)

          # 2) Check if draft has ended
          all_empty? = new_queues |> Map.values() |> Enum.all?(&(&1 == []))

          if all_empty? do
            # mark complete in DB
            {:ok, _} = MtgDraftServer.Drafts.complete_draft(state.draft_id)
            # broadcast completion
            MtgDraftServer.Drafts.notify(state.draft_id, {:draft_completed, state.draft_id})
          end

          # 3) Safely update pick_counters: if there's no entry for this user
          #    we default to a {1=>0,2=>0,3=>0} map, then put the new pick_no.
          new_counters =
            state.pick_counters
            |> Map.put_new(user_id, %{1 => 0, 2 => 0, 3 => 0})
            |> Map.update!(user_id, fn counters ->
              Map.put(counters, round, pick_no)
            end)

          {:noreply, %{state | booster_queues: new_queues, pick_counters: new_counters}}
        else
          Logger.error("Invalid pick #{card_id} by #{user_id}")
          {:noreply, state}
        end

      [] ->
        # no packs left
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:ai_pick, user_id}, state) do
    case Map.get(state.booster_queues, user_id, []) do
      [{_, [_ | _] = pack} | _] ->
        card_id = Enum.random(pack) |> Map.get(:id)
        GenServer.cast(self(), {:pick, user_id, card_id})

      _ ->
        :ok
    end

    {:noreply, state}
  end
end

defmodule MtgDraftServer.DraftSession do
  use GenServer

  @moduledoc """
  A GenServer that represents a draft session.
  """

  ## Client API

  @doc """
  Starts a draft session for a given draft_id.
  """
  def start_link(draft_id) do
    GenServer.start_link(__MODULE__, draft_id, name: via_tuple(draft_id))
  end

  @doc """
  Allows a player to join a draft session.
  """
  def join(draft_id, player) do
    GenServer.call(via_tuple(draft_id), {:join, player})
  end

  @doc """
  Retrieve the current state of the draft session.
  """
  def get_state(draft_id) do
    GenServer.call(via_tuple(draft_id), :get_state)
  end

  ## Helper for Registry lookup

  defp via_tuple(draft_id) do
    {:via, Registry, {MtgDraftServer.DraftRegistry, draft_id}}
  end

  ## Server Callbacks

  @impl true
  def init(draft_id) do
    state = %{
      draft_id: draft_id,
      # a map of user_id => player info
      players: %{},
      status: :pending
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:join, player}, _from, state) do
    new_players = Map.put(state.players, player.user_id, player)

    new_state = %{state | players: new_players}

    # If the draft has reached 8 players, update the state and trigger any side effects
    new_state =
      if map_size(new_players) >= 8 and state.status != :active do
        # You might also want to persist this change to the DB
        broadcast_draft_started(state.draft_id)
        # Also trigger the creation of a new draft session so that new players aren’t
        # forced into a draft that is already full.
        spawn_new_draft()
        %{new_state | status: :active}
      else
        new_state
      end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  defp broadcast_draft_started(draft_id) do
    Phoenix.PubSub.broadcast(
      MtgDraftServer.PubSub,
      "draft:#{draft_id}",
      {:draft_started, draft_id}
    )
  end

  defp spawn_new_draft do
    # For example, generate a new UUID for the draft (or use your Ecto workflow)
    new_draft_id = Ecto.UUID.generate()
    # You can also create a record in the database here if desired.
    MtgDraftServer.DraftSessionSupervisor.start_new_session(new_draft_id)
  end
end

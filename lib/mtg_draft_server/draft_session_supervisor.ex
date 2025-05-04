defmodule MtgDraftServer.DraftSessionSupervisor do
  @moduledoc """
  A dynamic supervisor for managing draft session processes.

  This supervisor is responsible for starting and supervising individual draft session
  processes. Each draft session is a GenServer that manages the state and logic for
  a single Magic: The Gathering draft.

  The supervisor uses a one-for-one strategy, meaning that if a draft session crashes,
  only that specific session will be restarted, without affecting other drafts.
  """
  use DynamicSupervisor

  @doc """
  Starts the DraftSessionSupervisor.

  This function is called by the application supervisor during application startup.
  """
  def start_link(_args) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  @doc """
  Initializes the supervisor with a one-for-one strategy.
  """
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new draft session.
  """
  def start_new_session(draft_id) do
    spec = %{
      id: {MtgDraftServer.DraftSession, draft_id},
      start: {MtgDraftServer.DraftSession, :start_link, [draft_id]},
      restart: :temporary
    }
  
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end

defmodule MtgDraftServer.DraftSessionSupervisor do
  use DynamicSupervisor

  def start_link(_args) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new draft session.
  """
  def start_new_session(draft_id) do
    spec = {MtgDraftServer.DraftSession, draft_id}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end

defmodule MtgDraftServer.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MtgDraftServerWeb.Telemetry,
      MtgDraftServer.Repo,
      {DNSCluster, query: Application.get_env(:mtg_draft_server, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MtgDraftServer.PubSub},
      {Finch, name: MtgDraftServer.Finch},
      MtgDraftServerWeb.Endpoint,
      {Registry, keys: :unique, name: MtgDraftServer.DraftRegistry},
      MtgDraftServer.DraftSessionSupervisor
    ]

    opts = [strategy: :one_for_one, name: MtgDraftServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MtgDraftServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

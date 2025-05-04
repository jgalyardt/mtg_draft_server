defmodule MtgDraftServer.Application do
  @moduledoc """
  The MtgDraftServer Application module.
  
  This module is responsible for starting and supervising all the processes
  required by the MTG Draft Server application, including:
  
  - The Phoenix endpoint
  - The Ecto repository
  - The PubSub system
  - The Registry for draft sessions
  - The DraftSessionSupervisor for managing draft sessions
  
  It also handles cleaning up draft data on application restart.
  """
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
      MtgDraftServer.DraftSessionSupervisor,
      MtgDraftServer.RateLimit
    ]

    opts = [strategy: :one_for_one, name: MtgDraftServer.Supervisor]

    # start your supervision tree
    {:ok, sup} = Supervisor.start_link(children, opts)

    # —————————————————————————————————————————————————————————
    # WIPE DRAFTS + PLAYERS ON EVERY RESTART
    #
    # Once the Repo child is up, delete all old drafts.
    # Because of on_delete: :delete_all FKs, this also removes draft_players
    # and draft_picks.
    alias MtgDraftServer.Repo
    alias MtgDraftServer.Drafts.{Draft, DraftPlayer}

    Repo.delete_all(Draft)
    Repo.delete_all(DraftPlayer)

    # —————————————————————————————————————————————————————————

    {:ok, sup}
  end

  @impl true
  def config_change(changed, _new, removed) do
    MtgDraftServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

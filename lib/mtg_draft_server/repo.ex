defmodule MtgDraftServer.Repo do
  use Ecto.Repo,
    otp_app: :mtg_draft_server,
    adapter: Ecto.Adapters.Postgres
end

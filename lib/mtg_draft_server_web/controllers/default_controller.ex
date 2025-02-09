# lib/mtg_draft_server_web/controllers/default_controller.ex
defmodule MtgDraftServerWeb.DefaultController do
  use MtgDraftServerWeb, :controller

  def index(conn, _params) do
    json(conn, %{
      message: "Welcome to MTG Draft Server API",
      version: "1.0",
      endpoints: %{
        drafts: %{
          create: "POST /api/drafts",
          start: "POST /api/drafts/:id/start",
          pick: "POST /api/drafts/:id/pick",
          picked_cards: "GET /api/drafts/:id/picks"
        }
      }
    })
  end
end

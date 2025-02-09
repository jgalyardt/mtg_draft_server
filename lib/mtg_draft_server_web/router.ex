defmodule MtgDraftServerWeb.Router do
  use MtgDraftServerWeb, :router

  alias MtgDraftServerWeb.AuthPlug

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth_api do
    plug :accepts, ["json"]
    plug AuthPlug
  end

  # Public (unauthenticated) routes for the root path.
  scope "/", MtgDraftServerWeb do
    pipe_through :api

    get "/", DefaultController, :index
  end

  scope "/api", MtgDraftServerWeb do
    pipe_through :auth_api

    post "/drafts", DraftController, :create
    post "/drafts/:id/start", DraftController, :start
    post "/drafts/:id/pick", DraftController, :pick
    get "/drafts/:id/picks", DraftController, :picked_cards
    post "/drafts/reconnect", DraftController, :reconnect
  end
end

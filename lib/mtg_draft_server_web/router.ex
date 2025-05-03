defmodule MtgDraftServerWeb.Router do
  use MtgDraftServerWeb, :router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth_api do
    plug :accepts, ["json"]
    plug MtgDraftServerWeb.AuthPlug
  end

  scope "/", MtgDraftServerWeb do
    pipe_through :browser

    get "/", DefaultController, :index
  end

  scope "/admin", MtgDraftServerWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
  end

  scope "/api", MtgDraftServerWeb, as: :api do
    pipe_through :auth_api

    get "/drafts/:id/state", DraftController, :state
    get "/drafts/pending", DraftController, :pending_drafts
    get "/drafts/:id/picks", DraftController, :picked_cards
    post "/drafts", DraftController, :create
    post "/drafts/:id/start", DraftController, :start
    post "/drafts/:id/pick", DraftController, :pick
    post "/drafts/reconnect", DraftController, :reconnect
    post "/drafts/booster_packs", DraftController, :generate_booster_packs
    post "/drafts/:id/add_ai", DraftController, :add_ai
    post "/drafts/:id/join", DraftController, :join
    get "/drafts/sets", DraftController, :sets
    get "/drafts/:id/deck", DraftController, :deck
  end
end

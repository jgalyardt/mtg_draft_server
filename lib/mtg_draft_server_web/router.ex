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

  scope "/", MtgDraftServerWeb do
    pipe_through :api
    get "/", DefaultController, :index
  end

  scope "/api", MtgDraftServerWeb, as: :api do
    pipe_through :auth_api

    get "/drafts/:id/state", DraftController, :state
    get "/drafts/pending", DraftController, :pending_drafts
    get "/drafts/:id/picks", DraftController, :picked_cards

    post "/drafts", DraftController, :create
    post "/drafts/:id/start", DraftController, :start
    post "/drafts/:id/start_with_boosters", DraftController, :start_draft_with_boosters
    post "/drafts/:id/pick", DraftController, :pick
    post "/drafts/reconnect", DraftController, :reconnect
    post "/drafts/booster_packs", DraftController, :generate_booster_packs
    post "/drafts/:id/add_ai", DraftController, :add_ai
    post "/drafts/:id/join", DraftController, :join
  end
end

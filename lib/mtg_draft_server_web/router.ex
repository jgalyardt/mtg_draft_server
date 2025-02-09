defmodule MtgDraftServerWeb.Router do
  use MtgDraftServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]

    # Guardian pipeline
    plug Guardian.Plug.Pipeline,
      module: MtgDraftServer.Guardian,
      error_handler: MtgDraftServer.AuthErrorHandler

    plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
    plug Guardian.Plug.LoadResource, allow_blank: false
  end

  # Add a new pipeline for public routes that don't need authentication
  pipeline :public_api do
    plug :accepts, ["json"]
  end

  # Add a public scope for routes that don't need authentication
  scope "/", MtgDraftServerWeb do
    pipe_through :public_api

    get "/", DefaultController, :index
  end

  scope "/api", MtgDraftServerWeb do
    pipe_through :api
  
    post "/drafts", DraftController, :create
    post "/drafts/:id/start", DraftController, :start
    post "/drafts/:id/pick", DraftController, :pick
    get "/drafts/:id/picks", DraftController, :picked_cards
    post "/drafts/reconnect", DraftController, :reconnect
  end
  
end

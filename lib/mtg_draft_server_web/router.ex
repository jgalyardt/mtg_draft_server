defmodule MtgDraftServerWeb.Router do
  use MtgDraftServerWeb, :router
  import Phoenix.LiveView.Router

  # Define pipelines for different rate limit types
  pipeline :limit_auth do
    plug MtgDraftServerWeb.RateLimitPlug, limit_type: :auth_endpoints
  end

  pipeline :limit_draft_creation do
    plug MtgDraftServerWeb.RateLimitPlug, limit_type: :draft_creation
  end

  pipeline :limit_draft_joining do
    plug MtgDraftServerWeb.RateLimitPlug, limit_type: :draft_joining
  end

  pipeline :limit_draft_pick do
    plug MtgDraftServerWeb.RateLimitPlug, limit_type: :draft_pick
  end

  pipeline :limit_standard do
    plug MtgDraftServerWeb.RateLimitPlug, limit_type: :api_standard
  end

  # Your existing pipelines
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

  # Apply the rate limits to your routes

  # Routes with standard rate limits
  scope "/api", MtgDraftServerWeb, as: :api do
    pipe_through [:api, :limit_standard]

    get "/drafts/pending", DraftController, :pending_drafts
    get "/drafts/sets", DraftController, :sets
  end

  # Draft creation routes
  scope "/api", MtgDraftServerWeb, as: :api do
    pipe_through [:auth_api, :limit_draft_creation]

    post "/drafts", DraftController, :create
  end

  # Draft joining routes
  scope "/api", MtgDraftServerWeb, as: :api do
    pipe_through [:auth_api, :limit_draft_joining]

    post "/drafts/:id/join", DraftController, :join
    post "/drafts/reconnect", DraftController, :reconnect
  end

  # Draft pick routes
  scope "/api", MtgDraftServerWeb, as: :api do
    pipe_through [:auth_api, :limit_draft_pick]

    post "/drafts/:id/pick", DraftController, :pick
  end

  # Other API routes
  scope "/api", MtgDraftServerWeb, as: :api do
    pipe_through [:auth_api, :limit_standard]

    get "/drafts/:id/state", DraftController, :state
    get "/drafts/:id/picks", DraftController, :picked_cards
    post "/drafts/:id/start", DraftController, :start
    post "/drafts/booster_packs", DraftController, :generate_booster_packs
    post "/drafts/:id/add_ai", DraftController, :add_ai
    get "/drafts/:id/deck", DraftController, :deck
  end
end

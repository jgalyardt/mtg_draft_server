import Config

# Specify dev environment
config :mtg_draft_server,
  environment: :prod,
  # This should never be true in prod!
  skip_auth: false

config :mtg_draft_server, :rate_limits,
  # Stricter limits for production
  draft_creation: {30, 60_000},
  draft_joining: {60, 60_000},
  draft_pick: {90, 60_000},
  api_standard: {120, 60_000},
  auth_endpoints: {5, 60_000}

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: MtgDraftServer.Finch

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
config :mtg_draft_server, MtgDraftServerWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  url: [scheme: "https", host: "yourdomain.com", port: 443]

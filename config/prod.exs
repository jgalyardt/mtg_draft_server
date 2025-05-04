import Config

# Specify dev environment
config :mtg_draft_server,
  environment: :prod,
  skip_auth: false # This should never be true in prod!

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

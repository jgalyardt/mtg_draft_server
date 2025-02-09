# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mtg_draft_server,
  ecto_repos: [MtgDraftServer.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :mtg_draft_server, MtgDraftServer.Guardian,
  issuer: "mtg_draft_server",
  # generate a strong key for production!
  secret_key: "YOUR_SECRET_KEY_HERE"

# Firebase configuration
config :mtg_draft_server,
  firebase_project_id: "draft-client"

# Configures the endpoint
config :mtg_draft_server, MtgDraftServerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: MtgDraftServerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MtgDraftServer.PubSub,
  live_view: [signing_salt: "JuirA2cG"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :mtg_draft_server, MtgDraftServer.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

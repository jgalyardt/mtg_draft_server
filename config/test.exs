import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :mtg_draft_server, MtgDraftServer.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mtg_draft_server_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Specify dev environment
config :mtg_draft_server,
  environment: :test,
  skip_auth: true

# config/test.exs
config :mtg_draft_server, :rate_limits,
  # Higher limits for testing
  draft_creation: {1000, 60_000},
  draft_joining: {1000, 60_000},
  draft_pick: {1000, 60_000},
  api_standard: {1000, 60_000},
  auth_endpoints: {1000, 60_000}

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :mtg_draft_server, MtgDraftServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "xHEMmkils/pV6jClQCJWdxpFiE4rRg/fdlz4Tyrtby8T3RaiAYGePakN5j5EfQkJ",
  server: false

# In test we don't send emails
config :mtg_draft_server, MtgDraftServer.Mailer, adapter: Swoosh.Adapters.Test

# Disable authentication for tests
config :mtg_draft_server, skip_auth: true

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

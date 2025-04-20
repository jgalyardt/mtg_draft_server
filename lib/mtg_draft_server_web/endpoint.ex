defmodule MtgDraftServerWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :mtg_draft_server

  plug CORSPlug,
    origin: ["http://localhost:5173"],
    methods: ["GET", "POST"],
    headers: ["Authorization", "Content-Type", "Accept"],
    expose: ["Authorization"],
    credentials: true,
    max_age: 86400

  # Force SSL in production if configured
  if Application.compile_env(:mtg_draft_server, :force_ssl, false) do
    plug Plug.SSL, rewrite_on: [:x_forwarded_proto]
  end

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_mtg_draft_server_key",
    signing_salt: "WOTNq3DB",
    same_site: "Lax"
  ]

  # socket "/live", Phoenix.LiveView.Socket,
  #   websocket: [connect_info: [session: @session_options]],
  #   longpoll: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :mtg_draft_server,
    gzip: false,
    only: MtgDraftServerWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :mtg_draft_server
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  plug MtgDraftServerWeb.Router
end

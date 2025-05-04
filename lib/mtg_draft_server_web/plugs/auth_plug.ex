defmodule MtgDraftServerWeb.AuthPlug do
  import Plug.Conn
  alias MtgDraftServer.FirebaseToken
  require Logger

  def init(default), do: default

  def call(conn, _opts) do
    env = Application.get_env(:mtg_draft_server, :environment, :prod)
    skip_auth = Application.get_env(:mtg_draft_server, :skip_auth, false)

    # Never skip auth in production, regardless of config
    if skip_auth && env != :prod do
      # Log a warning that auth is being skipped
      Logger.warning("⚠️ SECURITY WARNING: Authentication is bypassed in #{env} environment")
      
      # Only bypass in dev/test environments
      assign(conn, :current_user, %{"uid" => "test_user"})
    else
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] ->
          verify_token(conn, token)

        _ ->
          conn
          |> send_resp(401, Jason.encode!(%{error: "Missing or invalid Authorization header"}))
          |> halt()
      end
    end
  end

  defp verify_token(conn, token) do
    case FirebaseToken.verify_firebase_token(token) do
      {:ok, claims} ->
        Logger.debug("✅ Firebase token verification successful")
        # Map "user_id" to "uid" so controllers can consistently use "uid"
        claims = Map.put(claims, "uid", claims["user_id"])
        assign(conn, :current_user, claims)

      {:error, reason} ->
        Logger.warning("❌ Token verification failed: #{inspect(reason)}")

        conn
        |> send_resp(401, Jason.encode!(%{error: "Invalid token"}))
        |> halt()
    end
  end
end
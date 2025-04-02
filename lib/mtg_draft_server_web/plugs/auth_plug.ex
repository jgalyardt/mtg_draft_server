defmodule MtgDraftServerWeb.AuthPlug do
  import Plug.Conn
  alias MtgDraftServer.FirebaseToken

  def init(default), do: default

  def call(conn, _opts) do
    if Application.get_env(:mtg_draft_server, :skip_auth, false) do
      # In test (or any env where :skip_auth is true), bypass real auth
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
        IO.inspect(claims, label: "✅ Firebase Token Claims")
        # Map "user_id" to "uid" so controllers can consistently use "uid"
        claims = Map.put(claims, "uid", claims["user_id"])
        assign(conn, :current_user, claims)

      {:error, reason} ->
        IO.inspect(reason, label: "❌ Token Verification Failed")

        conn
        |> send_resp(401, Jason.encode!(%{error: "Invalid token"}))
        |> halt()
    end
  end
end

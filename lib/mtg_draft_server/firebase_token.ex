defmodule MtgDraftServer.FirebaseToken do
  use Joken.Config
  require Logger

  @firebase_jwks_url "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"
  
  # Get the Firebase project ID from config
  # Store this in your config/config.exs or environment-specific configs
  defp project_id, do: Application.get_env(:mtg_draft_server, :firebase_project_id)

  def verify_firebase_token(nil), do: {:error, :no_token_provided}

  def verify_firebase_token(token) do
    with {:ok, %{body: body}} <-
           Finch.build(:get, @firebase_jwks_url) |> Finch.request(MtgDraftServer.Finch),
         {:ok, certs} <- Jason.decode(body),
         {:ok, header} <- Joken.peek_header(token),
         %{"kid" => kid} = header,
         {:ok, jwk} <- get_jwk(certs, kid),
         {true, jose_jwt, _} <- JOSE.JWT.verify(jwk, token),
         {_, claims} <- JOSE.JWT.to_map(jose_jwt),
         :ok <- validate_claims(claims) do
      {:ok, claims}
    else
      {:error, reason} = err -> 
        Logger.warning("Token validation failed: #{inspect(reason)}")
        err
      _ -> 
        Logger.warning("Token validation failed with unknown error")
        {:error, :invalid_token}
    end
  end

  defp get_jwk(%{"keys" => keys}, kid) do
    keys
    |> Enum.find(fn key -> key["kid"] == kid end)
    |> case do
      nil -> {:error, :invalid_kid}
      key -> {:ok, JOSE.JWK.from_map(key)}
    end
  end

  # Validate all required claims for a Firebase ID token
  defp validate_claims(claims) do
    with :ok <- validate_issuer(claims["iss"]),
         :ok <- validate_audience(claims["aud"]),
         :ok <- validate_expiration(claims["exp"]),
         :ok <- validate_issued_at(claims["iat"]),
         :ok <- validate_subject(claims["sub"]),
         :ok <- validate_auth_time(claims["auth_time"]) do
      :ok
    end
  end

  # Issuer should be "https://securetoken.google.com/<project-id>"
  defp validate_issuer(iss) do
    expected_issuer = "https://securetoken.google.com/#{project_id()}"
    if iss == expected_issuer do
      :ok
    else
      {:error, {:invalid_issuer, "Expected #{expected_issuer}, got #{iss}"}}
    end
  end

  # Audience should match the Firebase project ID
  defp validate_audience(aud) when is_binary(aud) do
    if aud == project_id() do
      :ok
    else
      {:error, {:invalid_audience, "Expected #{project_id()}, got #{aud}"}}
    end
  end
  
  # Handle case where aud is a list (should contain project_id)
  defp validate_audience(aud) when is_list(aud) do
    if project_id() in aud do
      :ok
    else
      {:error, {:invalid_audience, "Project ID not in audience list"}}
    end
  end
  
  defp validate_audience(_), do: {:error, {:invalid_audience, "Missing audience claim"}}

  # Expiration time must be in the future
  defp validate_expiration(nil), do: {:error, {:invalid_expiration, "Missing exp claim"}}
  defp validate_expiration(exp) when is_integer(exp) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    # Add a small leeway to account for clock skew (30 seconds)
    if exp > now - 30 do
      :ok
    else
      {:error, {:token_expired, "Token expired at #{exp}, current time is #{now}"}}
    end
  end
  defp validate_expiration(_), do: {:error, {:invalid_expiration, "Invalid exp claim format"}}

  # Issued at time must be in the past
  defp validate_issued_at(nil), do: {:error, {:invalid_issued_at, "Missing iat claim"}}
  defp validate_issued_at(iat) when is_integer(iat) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    # Add a small leeway to account for clock skew (30 seconds)
    if iat < now + 30 do
      :ok
    else
      {:error, {:invalid_issued_at, "Token issued in the future"}}
    end
  end
  defp validate_issued_at(_), do: {:error, {:invalid_issued_at, "Invalid iat claim format"}}

  # Subject (user ID) must not be empty
  defp validate_subject(nil), do: {:error, {:invalid_subject, "Missing sub claim"}}
  defp validate_subject(""), do: {:error, {:invalid_subject, "Empty sub claim"}}
  defp validate_subject(sub) when is_binary(sub), do: :ok
  defp validate_subject(_), do: {:error, {:invalid_subject, "Invalid sub claim format"}}

  # Auth time must be in the past
  defp validate_auth_time(nil), do: {:error, {:invalid_auth_time, "Missing auth_time claim"}}
  defp validate_auth_time(auth_time) when is_integer(auth_time) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    # Add a small leeway to account for clock skew (30 seconds)
    if auth_time < now + 30 do
      :ok
    else
      {:error, {:invalid_auth_time, "Authentication time is in the future"}}
    end
  end
  defp validate_auth_time(_), do: {:error, {:invalid_auth_time, "Invalid auth_time claim format"}}
end
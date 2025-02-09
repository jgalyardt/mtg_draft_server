defmodule MtgDraftServer.FirebaseToken do
  use Joken.Config

  @firebase_jwks_url "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"

  def verify_firebase_token(nil), do: {:error, :no_token_provided}

  def verify_firebase_token(token) do
    with {:ok, %{body: body}} <- Finch.build(:get, @firebase_jwks_url) |> Finch.request(MtgDraftServer.Finch),
         {:ok, certs} <- Jason.decode(body),
         {:ok, header} <- Joken.peek_header(token),
         %{"kid" => kid} = header,
         {:ok, jwk} <- get_jwk(certs, kid),
         {true, jose_jwt, _} <- JOSE.JWT.verify(jwk, token),
         {_, claims} <- JOSE.JWT.to_map(jose_jwt) do
      {:ok, claims}
    else
      {:error, _} = err -> err
      _ -> {:error, :invalid_token}
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
end

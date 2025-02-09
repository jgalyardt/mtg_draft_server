defmodule MtgDraftServer.FirebaseToken do
  use Joken.Config

  # Add the JokenJwks hook with your JWKS strategy
  add_hook(JokenJwks, strategy: MtgDraftServer.JWKSStrategy)

  @impl true
  def token_config do
    default_claims()
  end

  def verify_firebase_token(token) do
    verify_and_validate(token)
  end
end

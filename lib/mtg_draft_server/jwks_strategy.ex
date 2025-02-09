defmodule MtgDraftServer.JWKSStrategy do
    use JokenJwks.DefaultStrategyTemplate
  
    def init_opts(_) do
      [jwks_url: "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"]
    end
  end
  
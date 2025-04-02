defmodule MtgDraftServer.FirebaseTokenTest do
    use ExUnit.Case, async: true
    alias MtgDraftServer.FirebaseToken
  
    test "verify_firebase_token/1 returns error when token is nil" do
      assert {:error, :no_token_provided} = FirebaseToken.verify_firebase_token(nil)
    end
  end
  
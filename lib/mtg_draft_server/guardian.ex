defmodule MtgDraftServer.Guardian do
  use Guardian, otp_app: :mtg_draft_server

  def subject_for_token(%{uid: uid}, _claims) do
    {:ok, uid}
  end

  def subject_for_token(_, _) do
    {:error, :invalid_resource}
  end

  def resource_from_claims(%{"sub" => uid}) do
    {:ok, %{uid: uid}}
  end

  def resource_from_claims(_claims) do
    {:error, :invalid_claims}
  end

  def build_claims(claims, _resource, _opts) do
    {:ok, claims}
  end
end

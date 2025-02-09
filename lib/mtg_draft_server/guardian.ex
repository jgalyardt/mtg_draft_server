defmodule MtgDraftServer.Guardian do
  use Guardian, otp_app: :mtg_draft_server

  @doc """
  Encode the resource into the token. In this example the resource is expected
  to be a map with a `uid` key (such as coming from Firebase or your user table).
  """
  def subject_for_token(resource, _claims) do
    sub = to_string(resource.uid)
    {:ok, sub}
  end

  @doc """
  Given the claims, return the resource. Typically you’d query your database here.
  For now we just return a dummy user with the uid.
  """
  def resource_from_claims(claims) do
    uid = claims["sub"]
    {:ok, %{uid: uid}}
  end
end

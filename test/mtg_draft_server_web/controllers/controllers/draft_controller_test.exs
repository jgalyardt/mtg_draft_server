defmodule MtgDraftServerWeb.DraftControllerTest do
  use MtgDraftServerWeb.ConnCase
  alias MtgDraftServer.Drafts
  alias MtgDraftServerWeb.Router.Helpers, as: Routes

  @valid_user %{"uid" => "user_123"}

  setup %{conn: conn} do
    conn = assign(conn, :current_user, @valid_user)
    {:ok, conn: conn}
  end

  test "POST /api/drafts creates a new draft", %{conn: conn} do
    conn = post(conn, Routes.api_draft_path(conn, :create), %{})
    response = json_response(conn, 201)
    assert Map.has_key?(response, "draft_id")
    assert response["status"] in ["pending", "active"]
  end

  test "POST /api/drafts/:id/join allows a user to join a draft", %{conn: conn} do
    {:ok, draft} = Drafts.create_draft(%{status: "pending"})
    conn = post(conn, Routes.api_draft_path(conn, :join, draft.id))
    json = json_response(conn, 200)
    assert json["draft_id"] == draft.id
    assert json["message"] == "Joined draft"
  end
end

defmodule MtgDraftServerWeb.DraftController do
  use MtgDraftServerWeb, :controller

  alias MtgDraftServer.Drafts
  alias MtgDraftServer.Guardian

  action_fallback MtgDraftServerWeb.FallbackController

  @doc """
  Create a new draft. The current user (from Guardian) is recorded as the creator.
  POST /api/drafts
  """
  def create(conn, _params) do
    case Guardian.Plug.current_resource(conn) do
      nil ->
        {:error, "Authentication required"}

      current_user ->
        with {:ok, draft} <- Drafts.create_draft(%{creator: current_user.uid}) do
          conn
          |> put_status(:created)
          |> put_resp_header("location", "/api/drafts/#{draft.id}")
          |> json(%{draft_id: draft.id, status: draft.status})
        end
    end
  end

  @doc """
  Start the draft by updating its status to "active".
  POST /api/drafts/:id/start
  """
  def start(conn, %{"id" => draft_id}) do
    with {:ok, current_user} <- fetch_current_user(conn),
         {:ok, draft} <- Drafts.start_draft(draft_id),
         {:ok, _authorized} <- authorize_draft_action(draft, current_user) do
      json(conn, %{draft_id: draft.id, status: draft.status})
    end
  end

  @doc """
  Persist a card pick.
  POST /api/drafts/:id/pick
  """
  def pick(conn, %{
        "id" => draft_id,
        "card_id" => card_id,
        "pack_number" => pack_number,
        "pick_number" => pick_number
      }) do
    with {:ok, current_user} <- fetch_current_user(conn),
         {:ok, draft} <- Drafts.get_draft(draft_id),
         {:ok, _authorized} <- authorize_draft_action(draft, current_user),
         {:ok, pick} <-
           Drafts.pick_card(draft_id, current_user.uid, card_id, %{
             "pack_number" => pack_number,
             "pick_number" => pick_number
           }) do
      conn
      |> put_status(:created)
      |> json(%{pick: pick})
    end
  end

  @doc """
  Get all picks for the current user in a given draft.
  GET /api/drafts/:id/picks
  """
  def picked_cards(conn, %{"id" => draft_id}) do
    with {:ok, current_user} <- fetch_current_user(conn),
         {:ok, draft} <- Drafts.get_draft(draft_id),
         {:ok, _authorized} <- authorize_draft_action(draft, current_user) do
      picks = Drafts.get_picked_cards(draft_id, current_user.uid)
      json(conn, %{picks: picks})
    end
  end

  # Helper functions
  defp fetch_current_user(conn) do
    case Guardian.Plug.current_resource(conn) do
      nil -> {:error, "Authentication required"}
      user -> {:ok, user}
    end
  end

  defp authorize_draft_action(draft, user) do
    cond do
      draft.creator == user.uid -> {:ok, true}
      # Add more authorization conditions here
      true -> {:error, "Unauthorized"}
    end
  end
end

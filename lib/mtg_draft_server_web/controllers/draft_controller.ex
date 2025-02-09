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
        with {:ok, draft} <- Drafts.create_and_join_draft(%{creator: current_user.uid}) do
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
         {:ok, _} <- ensure_in_draft_session(draft_id, current_user.uid),
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
  Reconnect a user to their active draft session.
  POST /api/drafts/reconnect

  If a draft session exists, the user rejoins it. If no session exists but the user
  has an active draft, a new session is started and the user joins it.
  """
  def reconnect(conn, _params) do
    with {:ok, current_user} <- fetch_current_user(conn),
         draft_player when not is_nil(draft_player) <-
           Drafts.get_active_draft_for_player(current_user.uid) do
      draft_id = draft_player.draft.id

      case Registry.lookup(MtgDraftServer.DraftRegistry, draft_id) do
        [{_pid, _}] ->
          # The draft session exists; join the session.
          :ok = MtgDraftServer.DraftSession.join(draft_id, %{user_id: current_user.uid})
          json(conn, %{message: "Rejoined draft", draft_id: draft_id})

        [] ->
          # The draft session is not running; start it and then join.
          {:ok, _pid} = MtgDraftServer.DraftSessionSupervisor.start_new_session(draft_id)
          :ok = MtgDraftServer.DraftSession.join(draft_id, %{user_id: current_user.uid})
          json(conn, %{message: "Draft session restarted and rejoined", draft_id: draft_id})
      end
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "No active draft found for user"})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: reason})
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
  defp ensure_in_draft_session(draft_id, user_id) do
    # Calling join/2 on the draft session is idempotent.
    :ok = MtgDraftServer.DraftSession.join(draft_id, %{user_id: user_id})
    {:ok, :joined}
  end

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

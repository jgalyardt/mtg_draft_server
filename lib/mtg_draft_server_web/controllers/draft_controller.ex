defmodule MtgDraftServerWeb.DraftController do
  use MtgDraftServerWeb, :controller

  alias MtgDraftServer.Drafts

  action_fallback MtgDraftServerWeb.FallbackController

  @doc """
  Create a new draft using the Firebase authenticated user.
  """
  def create(conn, _params) do
    case conn.assigns[:current_user] do
      %{"uid" => uid} ->
        with {:ok, draft} <- Drafts.create_and_join_draft(%{creator: uid}) do
          conn
          |> put_status(:created)
          |> put_resp_header("location", "/api/drafts/#{draft.id}")
          |> json(%{draft_id: draft.id, status: draft.status})
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{"error" => "Authentication required"})
    end
  end
  
  @doc """
  Start the draft by updating its status to "active".
  POST /api/drafts/:id/start
  """
  def start(conn, %{"id" => draft_id}) do
    case conn.assigns[:current_user] do
      %{"uid" => uid} ->
        with {:ok, draft} <- Drafts.start_draft(draft_id),
             {:ok, _authorized} <- authorize_draft_action(draft, uid) do
          json(conn, %{draft_id: draft.id, status: draft.status})
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{"error" => "Authentication required"})
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
    case conn.assigns[:current_user] do
      %{"uid" => uid} ->
        with {:ok, _} <- ensure_in_draft_session(draft_id, uid),
             {:ok, draft} <- Drafts.get_draft(draft_id),
             {:ok, _authorized} <- authorize_draft_action(draft, uid),
             {:ok, pick} <-
               Drafts.pick_card(draft_id, uid, card_id, %{
                 "pack_number" => pack_number,
                 "pick_number" => pick_number
               }) do
          conn
          |> put_status(:created)
          |> json(%{pick: pick})
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{"error" => "Authentication required"})
    end
  end

  @doc """
  Reconnect a user to their active draft session.
  POST /api/drafts/reconnect

  If a draft session exists, the user rejoins it. If no session exists but the user
  has an active draft, a new session is started and the user joins it.
  """
  def reconnect(conn, _params) do
    case conn.assigns[:current_user] do
      %{"uid" => uid} ->
        case Drafts.get_active_draft_for_player(uid) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "No active draft found for user"})

          draft_player ->
            draft_id = draft_player.draft.id

            case Registry.lookup(MtgDraftServer.DraftRegistry, draft_id) do
              [{_pid, _}] ->
                # The draft session exists; join the session.
                :ok = MtgDraftServer.DraftSession.join(draft_id, %{user_id: uid})
                json(conn, %{message: "Rejoined draft", draft_id: draft_id})

              [] ->
                # The draft session is not running; start it and then join.
                {:ok, _pid} = MtgDraftServer.DraftSessionSupervisor.start_new_session(draft_id)
                :ok = MtgDraftServer.DraftSession.join(draft_id, %{user_id: uid})
                json(conn, %{message: "Draft session restarted and rejoined", draft_id: draft_id})
            end
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{"error" => "Authentication required"})
    end
  end

  @doc """
  Get all picks for the current user in a given draft.
  GET /api/drafts/:id/picks
  """
  def picked_cards(conn, %{"id" => draft_id}) do
    case conn.assigns[:current_user] do
      %{"uid" => uid} ->
        with {:ok, draft} <- Drafts.get_draft(draft_id),
             {:ok, _authorized} <- authorize_draft_action(draft, uid) do
          picks = Drafts.get_picked_cards(draft_id, uid)
          json(conn, %{picks: picks})
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{"error" => "Authentication required"})
    end
  end

  # ===================
  # Helper Functions
  # ===================

  defp ensure_in_draft_session(draft_id, user_id) do
    :ok = MtgDraftServer.DraftSession.join(draft_id, %{user_id: user_id})
    {:ok, :joined}
  end

  defp authorize_draft_action(draft, user_id) do
    case MtgDraftServer.Drafts.get_draft_player(draft.id, user_id) do
      {:ok, _player} -> {:ok, true}
      _ -> {:error, "Unauthorized"}
    end
  end
end

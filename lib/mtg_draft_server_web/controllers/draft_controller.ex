defmodule MtgDraftServerWeb.DraftController do
  use MtgDraftServerWeb, :controller

  alias MtgDraftServer.Drafts
  alias MtgDraftServer.DraftSession

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
  """
  def pick(conn, %{"id" => draft_id, "card_id" => card_id}) do
    case conn.assigns[:current_user] do
      %{"uid" => uid} ->
        with {:ok, _} <- ensure_in_draft_session(draft_id, uid),
             {:ok, draft} <- Drafts.get_draft(draft_id),
             {:ok, _authorized} <- authorize_draft_action(draft, uid) do
          # Delegate the pick to the DraftSession.
          DraftSession.pick(draft_id, uid, card_id)
          json(conn, %{message: "Pick registered"})
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{"error" => "Authentication required"})
    end
  end

  @doc """
  Reconnect a user to their active draft session.
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
                :ok = DraftSession.join(draft_id, %{"user_id" => uid})
                json(conn, %{message: "Rejoined draft", draft_id: draft_id})
              [] ->
                {:ok, _pid} = MtgDraftServer.DraftSessionSupervisor.start_new_session(draft_id)
                :ok = DraftSession.join(draft_id, %{"user_id" => uid})
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

  @doc """
  Generate booster packs and distribute them among players.
  """
  def generate_booster_packs(conn, params) do
    players = Map.get(params, "players", [])
    opts = %{
      set_codes: Map.get(params, "set_codes", []),
      allowed_rarities:
        Map.get(params, "allowed_rarities", ["basic", "common", "uncommon", "rare", "mythic"]),
      distribution:
        Map.get(params, "distribution", %{"basic" => 1, "common" => 10, "uncommon" => 3, "rare" => 1})
    }
    packs_distribution = Drafts.PackGenerator.generate_and_distribute_booster_packs(opts, players)
    json(conn, packs_distribution)
  end

  @doc """
  Add an AI player to an active draft.

  Expects JSON with:
    - "id": the draft id
    - "ai_id": a unique identifier for the AI (e.g. "AI_1")
  """
  def add_ai(conn, %{"id" => draft_id, "ai_id" => ai_id}) do
    case conn.assigns[:current_user] do
      %{"uid" => _uid} ->
        :ok = DraftSession.join(draft_id, %{"user_id" => ai_id, "ai" => true})
        json(conn, %{message: "AI player #{ai_id} added to draft", draft_id: draft_id})
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{"error" => "Authentication required"})
    end
  end

  # --------------------
  # Helper Functions
  # --------------------

  defp ensure_in_draft_session(draft_id, user_id) do
    :ok = DraftSession.join(draft_id, %{"user_id" => user_id})
    {:ok, :joined}
  end

  defp authorize_draft_action(draft, user_id) do
    case Drafts.get_draft_player(draft.id, user_id) do
      {:ok, _player} -> {:ok, true}
      _ -> {:error, "Unauthorized"}
    end
  end
end

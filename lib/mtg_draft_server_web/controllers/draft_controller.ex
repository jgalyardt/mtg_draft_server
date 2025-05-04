defmodule MtgDraftServerWeb.DraftController do
  use MtgDraftServerWeb, :controller

  alias MtgDraftServer.Drafts
  alias MtgDraftServer.DraftSession
  alias MtgDraftServer.DraftSessionSupervisor

  action_fallback MtgDraftServerWeb.FallbackController

  @doc """
  Create a new draft, auto‑add 7 AIs, and return the draft info.
  """
  def create(conn, params) do
    %{"uid" => uid} = conn.assigns.current_user

    # Build a map with only atom keys
    args = %{
      creator: uid,
      pack_sets: Map.get(params, "pack_sets", []),
      allowed_rarities: Map.get(params, "allowed_rarities", [])
    }

    with {:ok, %{draft: draft, player: _human_player}} <- Drafts.create_and_join_draft(args) do
      # start GenServer and join players as before…
      {:ok, _pid} = DraftSessionSupervisor.start_new_session(draft.id)
      :ok = DraftSession.join(draft.id, %{"user_id" => uid, "ai" => false})

      # render the new draft
      response =
        %{draft_id: draft.id, status: draft.status}
        |> Map.merge(if draft.pack_sets != [], do: %{pack_sets: draft.pack_sets}, else: %{})

      conn
      |> put_status(:created)
      |> put_resp_header("location", "/api/drafts/#{draft.id}")
      |> json(response)
    end
  end

  @doc """
  Start the draft by updating its status to "active" and loading all players into session.
  """
  def start(conn, %{"id" => draft_id}) do
    %{"uid" => uid} = conn.assigns.current_user

    with {:ok, draft} <- Drafts.get_draft(draft_id),
         {:ok, _} <- authorize_draft_action(draft, uid) do
      # 1) Ensure the session process exists
      pid =
        case Registry.lookup(MtgDraftServer.DraftRegistry, draft_id) do
          [{pid, _}] ->
            pid

          [] ->
            {:ok, pid} = DraftSessionSupervisor.start_new_session(draft_id)
            pid
        end

      # 2) Join all players into the session
      Drafts.get_draft_players(draft_id)
      |> Enum.each(fn user_id ->
        is_ai = String.starts_with?(user_id, "AI_")
        :ok = DraftSession.join(draft_id, %{"user_id" => user_id, "ai" => is_ai})
      end)

      # 3) Kick off booster generation with options
      opts = %{
        set_codes: draft.pack_sets,
        allowed_rarities: draft.allowed_rarities
      }

      case GenServer.call(pid, {:start_with_options, opts}) do
        {:ok, _state} ->
          conn
          |> json(%{
            draft_id: draft_id,
            status: "active",
            message: "Draft started with booster packs"
          })

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: reason})
      end
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
             {:ok, _} <- authorize_draft_action(draft, uid) do
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
  Get all picks for the current user in a given draft.
  """
  def picked_cards(conn, %{"id" => draft_id}) do
    case conn.assigns[:current_user] do
      %{"uid" => uid} ->
        with {:ok, draft} <- Drafts.get_draft(draft_id),
             {:ok, _} <- authorize_draft_action(draft, uid) do
          picks = Drafts.get_picked_cards(draft_id, uid)
          json(conn, %{picks: picks})
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{"error" => "Authentication required"})
    end
  end

  @doc "Get your completed deck (all picks) once draft is done"
  def deck(conn, %{"id" => draft_id}) do
    %{"uid" => uid} = conn.assigns.current_user

    case Drafts.get_draft(draft_id) do
      {:ok, %{status: "complete"}} ->
        picks = Drafts.get_picked_cards(draft_id, uid)
        cards = Enum.map(picks, & &1.card)
        json(conn, %{deck: cards})

      {:ok, draft} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Draft not complete (status: #{draft.status})"})

      {:error, reason} ->
        conn |> put_status(:not_found) |> json(%{error: reason})
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
        Map.get(params, "distribution", %{
          "basic" => 1,
          "common" => 10,
          "uncommon" => 3,
          "rare" => 1
        })
    }

    packs_distribution =
      Drafts.PackGenerator.generate_and_distribute_booster_packs(opts, players)

    json(conn, packs_distribution)
  end

  @doc """
  Add an AI player to an active draft.
  """
  def add_ai(conn, %{"id" => draft_id, "ai_id" => ai_id}) do
    case conn.assigns[:current_user] do
      %{"uid" => _uid} ->
        with {:ok, draft} <- Drafts.get_draft(draft_id),
             {:ok, _player} <- Drafts.join_draft(draft, ai_id) do
          :ok = DraftSession.join(draft_id, %{"user_id" => ai_id, "ai" => true})
          json(conn, %{message: "AI player #{ai_id} added to draft", draft_id: draft_id})
        else
          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: reason})
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{"error" => "Authentication required"})
    end
  end

  @doc """
  Lists pending drafts (those in "pending" status with fewer than 8 players).
  """
  def pending_drafts(conn, _params) do
    drafts = Drafts.list_pending_drafts()
    json(conn, %{drafts: drafts})
  end

  @doc """
  Allows a user to join an existing pending draft.
  """
  def join(conn, %{"id" => draft_id}) do
    case conn.assigns[:current_user] do
      %{"uid" => uid} ->
        with {:ok, draft} <- Drafts.get_draft(draft_id),
             {:ok, player} <- Drafts.join_draft(draft, uid) do
          case Registry.lookup(MtgDraftServer.DraftRegistry, draft_id) do
            [] ->
              {:ok, _pid} = DraftSessionSupervisor.start_new_session(draft_id)
              :ok = DraftSession.join(draft_id, %{"user_id" => uid})

            [{_pid, _}] ->
              :ok = DraftSession.join(draft_id, %{"user_id" => uid})
          end

          json(conn, %{draft_id: draft.id, message: "Joined draft", player: player})
        else
          error ->
            conn |> put_status(:bad_request) |> json(%{error: error})
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required"})
    end
  end

  @doc """
  Get the current state of the draft, including your queue and current pack.
  """
  def state(conn, %{"id" => draft_id}) do
    case conn.assigns[:current_user] do
      %{"uid" => uid} ->
        with {:ok, draft} <- Drafts.get_draft(draft_id),
             {:ok, _} <- authorize_draft_action(draft, uid),
             [{pid, _}] <- Registry.lookup(MtgDraftServer.DraftRegistry, draft_id) do
          # Get the current state
          state = GenServer.call(pid, :get_state)

          # Access the user's queue using the new structure
          user_queues = Map.get(state.booster_queues, uid, %{})
          current_round = state.current_round
          current_round_queue = Map.get(user_queues, current_round, [])
          current_pack = List.first(current_round_queue)

          json(conn, %{
            status: state.status,
            current_round: current_round,
            has_pack: current_pack != nil && current_pack != [],
            queue_length: length(current_round_queue),
            current_pack: current_pack
          })
        else
          [] ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Draft session not found"})

          _ ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "Authentication required"})
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required"})
    end
  end

  @doc """
  Reconnects the user to their active draft and returns lobby state.
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
                players = Drafts.get_draft_players(draft_id)

                json(conn, %{message: "Rejoined draft", draft_id: draft_id, players: players})

              [] ->
                {:ok, _pid} = DraftSessionSupervisor.start_new_session(draft_id)
                :ok = DraftSession.join(draft_id, %{"user_id" => uid})
                players = Drafts.get_draft_players(draft_id)

                json(conn, %{
                  message: "Draft session restarted and rejoined",
                  draft_id: draft_id,
                  players: players
                })
            end
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{"error" => "Authentication required"})
    end
  end

  @doc "List all set codes for drafts"
  def sets(conn, _params) do
    sets = Drafts.list_available_sets()
    json(conn, %{sets: sets})
  end

  # --------------------
  # Private Functions
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

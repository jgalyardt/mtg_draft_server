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
        with {:ok, draft} <- Drafts.get_draft(draft_id),
             {:ok, _authorized} <- authorize_draft_action(draft, uid) do
          # Call the draft session to start with booster packs
          case Registry.lookup(MtgDraftServer.DraftRegistry, draft_id) do
            [{pid, _}] ->
              case GenServer.call(pid, :start_draft_with_boosters) do
                {:ok, _state} ->
                  json(conn, %{
                    draft_id: draft_id,
                    status: "active",
                    message: "Draft started with booster packs"
                  })

                {:error, reason} ->
                  conn |> put_status(:bad_request) |> json(%{error: reason})
              end

            [] ->
              # Start a new session if one doesn't exist
              {:ok, pid} = MtgDraftServer.DraftSessionSupervisor.start_new_session(draft_id)

              case GenServer.call(pid, :start_draft_with_boosters) do
                {:ok, _state} ->
                  json(conn, %{
                    draft_id: draft_id,
                    status: "active",
                    message: "Draft started with booster packs"
                  })

                {:error, reason} ->
                  conn |> put_status(:bad_request) |> json(%{error: reason})
              end
          end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{"error" => "Authentication required"})
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
        Map.get(params, "distribution", %{
          "basic" => 1,
          "common" => 10,
          "uncommon" => 3,
          "rare" => 1
        })
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
          # Check if draft session exists, start it if it doesn't
          case Registry.lookup(MtgDraftServer.DraftRegistry, draft_id) do
            [] ->
              # Session doesn't exist, start a new one
              {:ok, _pid} = MtgDraftServer.DraftSessionSupervisor.start_new_session(draft_id)
              :ok = DraftSession.join(draft_id, %{"user_id" => uid})

            [{_pid, _}] ->
              # Session exists, join it
              :ok = DraftSession.join(draft_id, %{"user_id" => uid})
          end

          json(conn, %{draft_id: draft.id, message: "Joined draft", player: player})
        else
          error -> conn |> put_status(:bad_request) |> json(%{error: error})
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required"})
    end
  end

  @doc """
  Get the current state of the draft, including if it's the user's turn and the current pack if applicable.
  """
  def state(conn, %{"id" => draft_id}) do
    case conn.assigns[:current_user] do
      %{"uid" => uid} ->
        with {:ok, draft} <- Drafts.get_draft(draft_id),
             {:ok, _authorized} <- authorize_draft_action(draft, uid) do
          # Get draft session state
          case Registry.lookup(MtgDraftServer.DraftRegistry, draft_id) do
            [{pid, _}] ->
              state = GenServer.call(pid, :get_state)
              current_user_index = Enum.find_index(state.turn_order, fn id -> id == uid end)
              is_your_turn = state.current_turn_index == current_user_index

              # Only include current pack if it's the user's turn
              current_pack =
                if is_your_turn do
                  get_current_pack_for_user(state, uid)
                else
                  []
                end

              json(conn, %{
                status: state.status,
                pack_number: state.pack_number,
                pick_number: state.pick_number,
                is_your_turn: is_your_turn,
                current_pack: current_pack
              })

            [] ->
              conn
              |> put_status(:not_found)
              |> json(%{error: "Draft session not found"})
          end
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
                {:ok, _pid} = MtgDraftServer.DraftSessionSupervisor.start_new_session(draft_id)
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

  defp get_current_pack_for_user(state, user_id) do
    if state.booster_packs do
      # Get the player's packs
      player_packs = Map.get(state.booster_packs, user_id, [])
      # Get the current pack based on pack_number (1-indexed, so subtract 1)
      current_pack = Enum.at(player_packs, state.pack_number - 1, [])
      current_pack
    else
      []
    end
  end
end

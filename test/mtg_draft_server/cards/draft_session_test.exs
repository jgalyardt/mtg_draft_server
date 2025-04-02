defmodule MtgDraftServer.DraftSessionTest do
  use ExUnit.Case, async: false
  alias MtgDraftServer.DraftSession

  setup do
    # Checkout the connection and set shared mode
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(MtgDraftServer.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(MtgDraftServer.Repo, {:shared, self()})

    # Generate a draft_id and insert a corresponding draft record.
    draft_id = Ecto.UUID.generate()

    {:ok, _draft} =
      %MtgDraftServer.Drafts.Draft{id: draft_id, status: "active"}
      |> MtgDraftServer.Drafts.Draft.changeset(%{status: "active"})
      |> MtgDraftServer.Repo.insert()

    # Insert a draft player record for "player1".
    {:ok, _player} =
      MtgDraftServer.Drafts.DraftPlayer.create_draft_player(%{
        draft_id: draft_id,
        user_id: "player1",
        seat: 1
      })

    {:ok, pid} = start_supervised({DraftSession, draft_id})
    # Allow the GenServer process to use the DB connection.
    Ecto.Adapters.SQL.Sandbox.allow(MtgDraftServer.Repo, self(), pid)
    %{draft_id: draft_id, pid: pid}
  end

  test "join adds a player and updates turn order", %{draft_id: draft_id} do
    :ok = DraftSession.join(draft_id, %{"user_id" => "player1"})
    state = DraftSession.get_state(draft_id)
    assert state.turn_order == ["player1"]
    assert Map.has_key?(state.players, "player1")
  end

  test "picking a card updates the session state", %{draft_id: draft_id, pid: pid} do
    # Build an initial state with a booster pack for testing.
    initial_state = %{
      draft_id: draft_id,
      players: %{"player1" => %{"user_id" => "player1"}},
      turn_order: ["player1"],
      current_turn_index: 0,
      pack: [],
      pack_number: 1,
      pick_number: 1,
      status: :active,
      booster_packs: %{
        "player1" => [
          [
            %{"id" => "card1"},
            %{"id" => "card2"}
          ]
        ]
      },
      draft_started: true,
      current_pack_direction: :left
    }

    # Replace the GenServer state.
    :sys.replace_state(pid, fn _ -> initial_state end)

    DraftSession.pick(draft_id, "player1", "card1")
    # Allow some time for asynchronous processing.
    Process.sleep(100)
    state = DraftSession.get_state(draft_id)
    booster = state.booster_packs || %{}
    [pack] = Map.get(booster, "player1", [[]])
    # After picking "card1", only one card ("card2") should remain.
    assert length(pack) == 1

    assert Enum.any?(pack, fn card ->
             is_map(card) and (card["id"] == "card2" or Map.get(card, :id) == "card2")
           end)
  end
end

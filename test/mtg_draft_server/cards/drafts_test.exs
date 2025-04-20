defmodule MtgDraftServer.DraftsTest do
  use ExUnit.Case, async: false
  alias MtgDraftServer.Drafts
  alias MtgDraftServer.Drafts.Draft

  setup do
    # Checkout the connection and set shared mode.
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(MtgDraftServer.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(MtgDraftServer.Repo, {:shared, self()})
    :ok
  end

  @draft_attrs %{status: "pending"}
  @creator "test_user_1"

  test "create_draft/1 creates a draft" do
    assert {:ok, %Draft{} = draft} = Drafts.create_draft(@draft_attrs)
    assert draft.status == "pending"
  end

  test "create_and_join_draft/1 creates a draft and joins the creator" do
    assert {:ok, %Draft{} = draft} =
             Drafts.create_and_join_draft(%{status: "pending", creator: @creator})

    {:ok, draft_player} = Drafts.get_draft_player(draft.id, @creator)
    assert draft_player.user_id == @creator
  end

  test "get_active_draft_for_player/1 returns active draft player" do
    {:ok, _draft} = Drafts.create_and_join_draft(%{status: "pending", creator: @creator})
    draft_player = Drafts.get_active_draft_for_player(@creator)
    assert draft_player != nil
    assert draft_player.user_id == @creator
  end

  test "join_draft/2 adds a new player if draft is not full" do
    {:ok, draft} = Drafts.create_draft(%{status: "pending"})
    {:ok, player} = Drafts.join_draft(draft, "test_user_2")
    assert player.user_id == "test_user_2"
  end

  test "list_pending_drafts/0 returns drafts with fewer than 8 players" do
    {:ok, draft} = Drafts.create_draft(%{status: "pending"})
    pending = Drafts.list_pending_drafts()
    assert Enum.any?(pending, fn d -> d.id == draft.id and d.player_count == 0 end)
  end

  test "notify/2 broadcasts atom events with draft_id" do
    draft_id = Ecto.UUID.generate()

    # Subscribe to the topic
    Phoenix.PubSub.subscribe(MtgDraftServer.PubSub, "draft:#{draft_id}")

    # Send a notification with an atom event
    Drafts.notify(draft_id, :test_event)

    # Assert we receive the expected message
    assert_receive {:test_event, ^draft_id}, 500
  end

  test "notify/2 broadcasts complex event structures" do
    draft_id = Ecto.UUID.generate()

    # Subscribe to the topic
    Phoenix.PubSub.subscribe(MtgDraftServer.PubSub, "draft:#{draft_id}")

    # Send a notification with a complex event
    complex_event = {:pack_updated, "player1", 1, 2}
    Drafts.notify(draft_id, complex_event)

    # Assert we receive the expected message
    assert_receive ^complex_event, 500
  end
end

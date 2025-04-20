defmodule MtgDraftServer.DraftSession.HelpersTest do
  use ExUnit.Case, async: true
  alias MtgDraftServer.DraftSession.TurnLogic
  alias MtgDraftServer.DraftSession.PackDistributor

  describe "TurnLogic" do
    test "next_index with left direction" do
      assert TurnLogic.next_index(0, 8, :left) == 1
      assert TurnLogic.next_index(7, 8, :left) == 0
    end

    test "next_index with right direction" do
      assert TurnLogic.next_index(0, 8, :right) == 7
      assert TurnLogic.next_index(7, 8, :right) == 6
    end
  end

  describe "PackDistributor" do
    test "remove_card removes the correct card" do
      pack = [
        %{"id" => "card1"},
        %{"id" => "card2"},
        %{id: "card3"}
      ]

      updated_pack = PackDistributor.remove_card(pack, "card2")
      assert length(updated_pack) == 2
      assert Enum.any?(updated_pack, fn card -> card["id"] == "card1" end)
      assert Enum.any?(updated_pack, fn card -> card[:id] == "card3" end)
      refute Enum.any?(updated_pack, fn card -> card["id"] == "card2" end)
    end

    test "match_card? correctly identifies cards" do
      assert PackDistributor.match_card?(%{"id" => "card1"}, "card1")
      assert PackDistributor.match_card?(%{id: "card1"}, "card1")
      refute PackDistributor.match_card?(%{"id" => "card2"}, "card1")
      refute PackDistributor.match_card?(%{id: "card2"}, "card1")
      refute PackDistributor.match_card?("not_a_map", "card1")
    end

    test "pass_pack correctly passes a pack to another player" do
      booster_packs = %{
        "player1" => [
          [%{"id" => "card1"}, %{"id" => "card2"}],
          [%{"id" => "card3"}, %{"id" => "card4"}]
        ],
        "player2" => [
          [%{"id" => "card5"}, %{"id" => "card6"}],
          []
        ]
      }

      pack_to_pass = [%{"id" => "card7"}, %{"id" => "card8"}]

      # Pass pack to player2 at index 1
      updated_packs =
        PackDistributor.pass_pack(booster_packs, "player1", "player2", pack_to_pass, 1)

      # Check that player2 now has the pack at index 1
      player2_packs = updated_packs["player2"]
      assert length(player2_packs) == 2
      assert Enum.at(player2_packs, 1) == pack_to_pass

      # Check that player1's packs are unchanged
      player1_packs = updated_packs["player1"]
      assert player1_packs == booster_packs["player1"]
    end

    test "current_pack_empty? correctly identifies when all packs are empty" do
      # All packs are empty
      booster_packs = %{
        "player1" => [[], [], []],
        "player2" => [[], [], []]
      }

      assert PackDistributor.current_pack_empty?(booster_packs)

      # Not all packs are empty
      booster_packs = %{
        "player1" => [[], [], []],
        "player2" => [[%{"id" => "card1"}], [], []]
      }

      refute PackDistributor.current_pack_empty?(booster_packs)
    end
  end
end

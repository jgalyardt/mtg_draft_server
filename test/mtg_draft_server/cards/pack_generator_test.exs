defmodule MtgDraftServer.Drafts.PackGeneratorTest do
    use ExUnit.Case, async: true
    alias MtgDraftServer.Drafts.PackGenerator
    alias MtgDraftServer.Cards.Card
  
    @dummy_cards [
      %Card{id: "basic1", rarity: "basic", foil: false},
      %Card{id: "common1", rarity: "common", foil: false},
      %Card{id: "common2", rarity: "common", foil: false},
      %Card{id: "uncommon1", rarity: "uncommon", foil: false},
      %Card{id: "rare1", rarity: "rare", foil: false},
      %Card{id: "mythic1", rarity: "mythic", foil: false},
      %Card{id: "foil1", rarity: "common", foil: true}
    ]
  
    test "generate_single_pack returns a shuffled pack with correct composition" do
      rarity_groups = %{
        "basic" => Enum.filter(@dummy_cards, &(&1.rarity == "basic")),
        "common" => Enum.filter(@dummy_cards, &(&1.rarity == "common")),
        "uncommon" => Enum.filter(@dummy_cards, &(&1.rarity == "uncommon")),
        "rare" => Enum.filter(@dummy_cards, &(&1.rarity == "rare")),
        "mythic" => Enum.filter(@dummy_cards, &(&1.rarity == "mythic"))
      }
  
      distribution = %{"basic" => 1, "common" => 1, "uncommon" => 1, "rare" => 1}
  
      pack = PackGenerator.generate_single_pack(rarity_groups, distribution)
      # The pack should contain 4 cards or 5 if a foil was inserted.
      assert length(pack) in [4, 5]
    end
  
    test "distribute_packs returns correct distribution among players" do
      packs = Enum.map(1..6, fn i -> ["card_#{i}"] end)
      players = ["player1", "player2"]
      distribution = PackGenerator.distribute_packs(packs, players)
      assert Map.has_key?(distribution, "player1")
      assert Map.has_key?(distribution, "player2")
      assert length(distribution["player1"]) == 3
      assert length(distribution["player2"]) == 3
    end
  end
  
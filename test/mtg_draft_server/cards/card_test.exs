defmodule MtgDraftServer.Cards.CardTest do
  use ExUnit.Case, async: true
  alias MtgDraftServer.Cards.Card

  @valid_attrs %{
    oracle_id: "00037840-6089-42ec-8c5c-281f9f474504",
    name: "Nissa, Worldsoul Speaker",
    mana_cost: "{3}{G}",
    cmc: 4.0,
    type_line: "Legendary Creature — Elf Druid",
    oracle_text: "Landfall — Whenever a land you control enters, you get {E}{E}.",
    power: "3",
    toughness: "3",
    colors: ["G"],
    color_identity: ["G"],
    set_code: "drc",
    rarity: "rare",
    foil: false,
    image_uris: %{
      "small" =>
        "https://cards.scryfall.io/small/front/a/4/a471b306-4941-4e46-a0cb-d92895c16f8a.jpg?1738355341"
    },
    legalities: %{"legacy" => "legal"}
  }

  test "changeset with valid attributes" do
    changeset = Card.changeset(%Card{}, @valid_attrs)
    assert changeset.valid?
  end

  test "changeset without required fields" do
    changeset = Card.changeset(%Card{}, %{})
    refute changeset.valid?

    errors = errors_on(changeset)
    assert errors.oracle_id == ["can't be blank"]
    assert errors.name == ["can't be blank"]
    assert errors.set_code == ["can't be blank"]
    assert errors.rarity == ["can't be blank"]
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end

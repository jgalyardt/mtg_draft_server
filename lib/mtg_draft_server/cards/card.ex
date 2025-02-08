defmodule MtgDraftServer.Cards.Card do
    use Ecto.Schema
    import Ecto.Changeset
  
    @primary_key {:id, :binary_id, autogenerate: false}  # we use the Scryfall id as primary key
    schema "cards" do
      field :oracle_id, Ecto.UUID
      field :name, :string
      field :mana_cost, :string
      field :cmc, :float
      field :type_line, :string
      field :oracle_text, :string
      field :power, :string
      field :toughness, :string
      field :colors, {:array, :string}
      field :color_identity, {:array, :string}
      field :image_uris, :map
      field :legalities, :map
  
      timestamps()
    end
  
    @doc false
    def changeset(card, attrs) do
      card
      |> cast(attrs, [
        "id",
        "oracle_id",
        "name",
        "mana_cost",
        "cmc",
        "type_line",
        "oracle_text",
        "power",
        "toughness",
        "colors",
        "color_identity",
        "image_uris",
        "legalities"
      ])
      |> validate_required(["id", "oracle_id", "name"])
    end
  end
  
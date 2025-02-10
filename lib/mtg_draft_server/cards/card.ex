defmodule MtgDraftServer.Cards.Card do
  @derive {Jason.Encoder,
           only: [
             :id,
             :oracle_id,
             :name,
             :mana_cost,
             :cmc,
             :type_line,
             :oracle_text,
             :power,
             :toughness,
             :colors,
             :color_identity,
             :set_code,
             :rarity,
             :foil,
             :image_uris,
             :legalities,
             :inserted_at,
             :updated_at
           ]}
  use Ecto.Schema
  import Ecto.Changeset

  # Ensures id is binary_id
  @primary_key {:id, :binary_id, autogenerate: true}
  # Ensures foreign keys also use binary_id
  @foreign_key_type :binary_id
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
    field :set_code, :string
    field :rarity, :string
    field :foil, :boolean, default: false
    field :image_uris, :map
    field :legalities, :map

    timestamps()
  end

  @doc false
  def changeset(card, attrs) do
    card
    |> cast(attrs, [
      # Keep id here to allow it to be cast
      :id,
      :oracle_id,
      :name,
      :mana_cost,
      :cmc,
      :type_line,
      :oracle_text,
      :power,
      :toughness,
      :colors,
      :color_identity,
      :set_code,
      :rarity,
      :foil,
      :image_uris,
      :legalities
    ])
    |> validate_required([:oracle_id, :name, :set_code, :rarity])
  end
end

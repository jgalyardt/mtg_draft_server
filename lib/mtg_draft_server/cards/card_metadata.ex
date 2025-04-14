defmodule MtgDraftServer.Cards.CardMetadata do
    use Ecto.Schema
    import Ecto.Changeset
  
    schema "card_metadata" do
      belongs_to :card, MtgDraftServer.Cards.Card, type: :binary_id
      field :layout, :string
      field :is_token, :boolean, default: false
      field :is_digital, :boolean, default: false
      field :is_promo, :boolean, default: false
  
      timestamps()
    end
  
    def changeset(metadata, attrs) do
      metadata
      |> cast(attrs, [:card_id, :layout, :is_token, :is_digital, :is_promo])
      |> validate_required([:card_id])
    end
  end
defmodule MtgDraftServer.Drafts.DraftPick do
  @derive {Jason.Encoder,
           only: [
             :id,
             :pack_number,
             :pick_number,
             :draft_id,
             :draft_player_id,
             :card_id,
             :card,
             :inserted_at,
             :updated_at
           ]}
  use Ecto.Schema
  import Ecto.Changeset

  schema "draft_picks" do
    field :pack_number, :integer
    field :pick_number, :integer
    field :expires_at, :utc_datetime

    belongs_to :draft, MtgDraftServer.Drafts.Draft, type: :binary_id
    belongs_to :draft_player, MtgDraftServer.Drafts.DraftPlayer
    belongs_to :card, MtgDraftServer.Cards.Card, type: :binary_id

    timestamps()
  end

  @type t :: %__MODULE__{
          id: integer() | nil,
          pack_number: integer() | nil,
          pick_number: integer() | nil,
          expires_at: DateTime.t() | nil,
          draft_id: Ecto.UUID.t() | nil,
          draft_player_id: integer() | nil,
          card_id: Ecto.UUID.t() | nil,
          draft: MtgDraftServer.Drafts.Draft.t() | Ecto.Association.NotLoaded.t() | nil,
          draft_player:
            MtgDraftServer.Drafts.DraftPlayer.t() | Ecto.Association.NotLoaded.t() | nil,
          card: MtgDraftServer.Cards.Card.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  def changeset(draft_pick, attrs) do
    draft_pick
    |> cast(attrs, [
      :draft_id,
      :draft_player_id,
      :card_id,
      :pack_number,
      :pick_number,
      :expires_at
    ])
    |> validate_required([
      :draft_id,
      :draft_player_id,
      :card_id,
      :pack_number,
      :pick_number,
      :expires_at
    ])
  end
end

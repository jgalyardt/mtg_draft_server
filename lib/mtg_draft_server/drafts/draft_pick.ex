defmodule MtgDraftServer.Drafts.DraftPick do
  use Ecto.Schema
  import Ecto.Changeset

  schema "draft_picks" do
    field :card_id, :binary_id
    field :pack_number, :integer
    field :pick_number, :integer
    field :expires_at, :utc_datetime
    belongs_to :draft, MtgDraftServer.Drafts.Draft, type: :binary_id
    belongs_to :draft_player, MtgDraftServer.Drafts.DraftPlayer

    timestamps()
  end

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

defmodule MtgDraftServer.Drafts.DraftPlayer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "draft_players" do
    field :user_id, :string
    field :seat, :integer
    field :connected, :boolean, default: true
    belongs_to :draft, MtgDraftServer.Drafts.Draft, type: :binary_id

    timestamps()
  end

  def changeset(draft_player, attrs) do
    draft_player
    |> cast(attrs, [:draft_id, :user_id, :seat, :connected])
    |> validate_required([:draft_id, :user_id, :seat])
  end

  def create_draft_player(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> MtgDraftServer.Repo.insert()
  end
end

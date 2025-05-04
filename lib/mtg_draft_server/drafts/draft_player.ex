defmodule MtgDraftServer.Drafts.DraftPlayer do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [:id, :user_id, :seat, :connected, :draft_id, :inserted_at, :updated_at]}
  schema "draft_players" do
    field :user_id, :string
    field :seat, :integer
    field :connected, :boolean, default: true
    belongs_to :draft, MtgDraftServer.Drafts.Draft, type: :binary_id

    timestamps()
  end

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: String.t() | nil,
          seat: integer() | nil,
          connected: boolean() | nil,
          draft_id: Ecto.UUID.t() | nil,
          draft: MtgDraftServer.Drafts.Draft.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

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

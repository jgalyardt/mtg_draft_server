defmodule MtgDraftServer.Drafts.Draft do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "drafts" do
    field :status, :string, default: "pending"
    field :pack_sets, {:array, :string}, default: []
    field :allowed_rarities, {:array, :string}, default: ["basic","common","uncommon","rare","mythic"]
    timestamps()
  end

  @type t :: %__MODULE__{
    id: Ecto.UUID.t() | nil,
    status: String.t() | nil,
    pack_sets: [String.t()] | nil,
    allowed_rarities: [String.t()] | nil,
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [:status, :pack_sets, :allowed_rarities])
    |> validate_required([:status])
  end
end
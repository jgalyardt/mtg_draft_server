defmodule MtgDraftServer.Drafts.Draft do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "drafts" do
    field :status, :string, default: "pending"
    timestamps()
  end

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [:status])
    |> validate_required([:status])
  end
end

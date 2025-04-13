defmodule MtgDraftServer.Repo.Migrations.AddPackSetsToDrafts do
  use Ecto.Migration

  def change do
    alter table(:drafts) do
      add :pack_sets, {:array, :string}, default: []
    end
  end
end

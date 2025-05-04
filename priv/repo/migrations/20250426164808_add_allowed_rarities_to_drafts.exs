defmodule MtgDraftServer.Repo.Migrations.AddAllowedRaritiesToDrafts do
  use Ecto.Migration

  def change do
    alter table(:drafts) do
      add :allowed_rarities, {:array, :string},
        default: ["basic", "common", "uncommon", "rare", "mythic"],
        null: false
    end
  end
end

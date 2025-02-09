defmodule MtgDraftServer.Repo.Migrations.CreateDrafts do
  use Ecto.Migration

  def change do
    create table(:drafts, primary_key: false) do
      add :id, :uuid, primary_key: true
      # Use a string status (e.g., "pending", "active", "complete")
      add :status, :string, default: "pending"
      timestamps()
    end
  end
end

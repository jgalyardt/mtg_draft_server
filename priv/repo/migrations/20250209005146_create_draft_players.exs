defmodule MtgDraftServer.Repo.Migrations.CreateDraftPlayers do
  use Ecto.Migration

  def change do
    create table(:draft_players) do
      add :draft_id, references(:drafts, type: :uuid, on_delete: :delete_all), null: false
      # Storing the Firebase UID (or any user identifier) as a string:
      add :user_id, :string, null: false
      add :seat, :integer, null: false
      # Optionally track connection status for handling disconnects:
      add :connected, :boolean, default: true

      timestamps()
    end

    create index(:draft_players, [:draft_id])
    create unique_index(:draft_players, [:draft_id, :user_id])
  end
end

defmodule MtgDraftServer.Repo.Migrations.CreateDraftPicks do
  use Ecto.Migration

  def change do
    create table(:draft_picks) do
      add :draft_id, references(:drafts, type: :uuid, on_delete: :delete_all), null: false
      add :draft_player_id, references(:draft_players, on_delete: :delete_all), null: false
      add :card_id, references(:cards, type: :uuid, on_delete: :nothing), null: false
      # 1, 2, or 3
      add :pack_number, :integer, null: false
      # Order of the pick within the pack
      add :pick_number, :integer, null: false

      timestamps()
    end

    create index(:draft_picks, [:draft_id])
    create index(:draft_picks, [:draft_player_id])
    create index(:draft_picks, [:card_id])
  end
end

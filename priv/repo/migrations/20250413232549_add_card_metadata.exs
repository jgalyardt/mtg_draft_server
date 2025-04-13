# Create a new migration: mix ecto.gen.migration add_card_metadata
defmodule MtgDraftServer.Repo.Migrations.AddCardMetadata do
  use Ecto.Migration

  def change do
    create table(:card_metadata) do
      add :card_id, references(:cards, type: :uuid, on_delete: :delete_all), null: false
      add :layout, :string
      add :is_token, :boolean, default: false
      add :is_digital, :boolean, default: false
      add :is_promo, :boolean, default: false
      
      timestamps()
    end

    create index(:card_metadata, [:card_id])
    create index(:card_metadata, [:layout])
  end
end
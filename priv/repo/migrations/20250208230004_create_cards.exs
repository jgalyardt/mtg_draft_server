defmodule MtgDraftServer.Repo.Migrations.CreateCards do
  use Ecto.Migration

  def change do
    create table(:cards, primary_key: false) do
      # Use the Scryfall card id (a UUID string) as the primary key.
      add :id, :uuid, primary_key: true
      add :oracle_id, :uuid, null: false
      add :name, :string, null: false
      add :mana_cost, :string
      add :cmc, :float
      add :type_line, :string
      add :oracle_text, :text
      add :power, :string
      add :toughness, :string
      add :colors, {:array, :string}
      add :color_identity, {:array, :string}
      # Store structured data such as image URIs and legalities as JSONB
      add :image_uris, :map
      add :legalities, :map

      timestamps()
    end

    create unique_index(:cards, [:oracle_id])
    create unique_index(:cards, [:name])
  end
end

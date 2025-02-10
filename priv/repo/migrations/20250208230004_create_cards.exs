defmodule MtgDraftServer.Repo.Migrations.CreateCards do
  use Ecto.Migration

  def change do
    create table(:cards, primary_key: false) do
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

      # NEW FIELDS FOR BOOSTER GENERATION
      add :set_code, :string, null: false
      add :rarity, :string
      add :foil, :boolean, default: false

      add :image_uris, :map
      add :legalities, :map

      timestamps()
    end

    create unique_index(:cards, [:oracle_id])
    create unique_index(:cards, [:name])
  end
end

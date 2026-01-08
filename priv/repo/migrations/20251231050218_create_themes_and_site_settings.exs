defmodule Playground.Repo.Migrations.CreateThemesAndSiteSettings do
  use Ecto.Migration

  def change do
    create table(:themes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :mode, :string, null: false
      add :is_system, :boolean, null: false, default: false
      add :tokens, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:themes, [:slug])
    create index(:themes, [:mode])

    create table(:site_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :light_theme_id, references(:themes, type: :binary_id, on_delete: :nilify_all)
      add :dark_theme_id, references(:themes, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end
  end
end

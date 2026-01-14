defmodule Playground.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text

      # Chunking configuration
      add :chunk_size, :integer, null: false, default: 1000
      add :chunk_overlap, :integer, null: false, default: 200

      # UI/Display
      add :color, :string
      add :icon, :string
      add :display_order, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:categories, [:slug])
    create index(:categories, [:display_order])

    # Add category_id to files table
    alter table(:files) do
      add :category_id, references(:categories, on_delete: :nilify_all)
      add :ai_summary, :text
    end

    create index(:files, [:category_id])
  end
end

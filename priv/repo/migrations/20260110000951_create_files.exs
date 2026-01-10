defmodule Playground.Repo.Migrations.CreateFiles do
  use Ecto.Migration

  def change do
    create table(:files) do
      add :connector_organization_id, references(:connector_organizations, on_delete: :delete_all),
        null: false

      add :provider_file_id, :string, null: false
      add :name, :string, null: false
      add :mime_type, :string
      add :size_bytes, :bigint
      add :sync_status, :string, null: false, default: "unsynced"
      add :metadata, :map, default: %{}
      add :synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Unique constraint: one record per provider file per connector
    create unique_index(:files, [:connector_organization_id, :provider_file_id])
    create index(:files, [:connector_organization_id])
    create index(:files, [:sync_status])
  end
end

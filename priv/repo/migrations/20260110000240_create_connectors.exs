defmodule Playground.Repo.Migrations.CreateConnectors do
  use Ecto.Migration

  def change do
    # Connectors catalog table (Google Drive, Dropbox, etc.)
    create table(:connectors) do
      add :key, :string, null: false
      add :name, :string, null: false
      add :icon, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:connectors, [:key])

    # Seed Google Drive connector
    execute(
      """
      INSERT INTO connectors (key, name, icon, inserted_at, updated_at)
      VALUES ('google_drive', 'Google Drive', 'hero-document', NOW(), NOW())
      """,
      "DELETE FROM connectors WHERE key = 'google_drive'"
    )

    # Connector organizations join table (org's connection to a connector)
    create table(:connector_organizations) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :connector_id, references(:connectors, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :status, :string, null: false, default: "pending_auth"
      add :metadata, :map, default: %{}
      add :last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # One connection per org per connector type
    create unique_index(:connector_organizations, [:organization_id, :connector_id])
    create index(:connector_organizations, [:organization_id])
    create index(:connector_organizations, [:connector_id])
    create index(:connector_organizations, [:user_id])
    create index(:connector_organizations, [:status])
  end
end

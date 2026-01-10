defmodule Playground.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  def change do
    # Organizations table
    create table(:organizations) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # Organization users join table
    create table(:organization_users) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    # Ensure one user can only belong to one organization (for now)
    create unique_index(:organization_users, [:organization_id, :user_id])
    create index(:organization_users, [:organization_id])
    create index(:organization_users, [:user_id])
  end
end

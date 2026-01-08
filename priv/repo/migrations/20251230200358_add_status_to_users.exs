defmodule Playground.Repo.Migrations.AddStatusToUsers do
  use Ecto.Migration

  def up do
    # Add status field
    alter table(:users) do
      add :status, :string, default: "unconfirmed", null: false
    end

    # Backfill existing users based on confirmed_at
    execute """
    UPDATE users
    SET status = CASE
      WHEN confirmed_at IS NOT NULL THEN 'confirmed'
      ELSE 'unconfirmed'
    END
    """

    # Add index for queries
    create index(:users, [:status])
  end

  def down do
    alter table(:users) do
      remove :status
    end
  end
end

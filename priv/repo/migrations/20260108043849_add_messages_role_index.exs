defmodule Playground.Repo.Migrations.AddMessagesRoleIndex do
  use Ecto.Migration

  def change do
    # Index on role to optimize queries filtering by role (user/assistant)
    # Used in cost calculations and analytics queries
    create index(:messages, [:chat_id, :role])
  end
end

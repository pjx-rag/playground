defmodule Playground.Repo.Migrations.AddAnalyticsIndexes do
  use Ecto.Migration

  def up do
    PhoenixAnalytics.Migration.add_indexes()
  end

  def down do
    # Indexes will be dropped when table is dropped
    :ok
  end
end

defmodule Playground.Repo.Migrations.CreateAnalyticsTable do
  use Ecto.Migration

  def up do
    PhoenixAnalytics.Migration.up()
  end

  def down do
    PhoenixAnalytics.Migration.down()
  end
end

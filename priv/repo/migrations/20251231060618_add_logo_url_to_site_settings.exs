defmodule Playground.Repo.Migrations.AddLogoUrlToSiteSettings do
  use Ecto.Migration

  def change do
    alter table(:site_settings) do
      add :logo_url, :string
    end
  end
end

defmodule Playground.Repo.Migrations.AddParentFolderIdToFiles do
  use Ecto.Migration

  def change do
    alter table(:files) do
      add :parent_folder_id, :string
    end

    create index(:files, [:connector_organization_id, :parent_folder_id])
  end
end

defmodule Playground.Files.FolderOperations do
  @moduledoc """
  Folder hierarchy operations for files.

  Handles recursive folder queries for bulk operations.

  Used by:
  - FilesLive.Index (bulk folder sync)
  - GoogleDriveSync (folder structure mapping)
  """

  import Ecto.Query
  alias Playground.Repo
  alias Playground.Files.File

  @doc """
  Gets all file IDs that are descendants of a folder (recursively).

  Uses recursive CTE to find all nested files under a folder.
  Only returns non-folder files (actual documents).

  ## Examples

      iex> get_descendant_ids(connector_org_id, "folder123")
      [1, 2, 3]

  """
  def get_descendant_ids(connector_organization_id, folder_provider_id) do
    # Use recursive CTE to find all descendants
    # Start with direct children, then recursively find their children
    query = """
    WITH RECURSIVE descendants AS (
      -- Base case: direct children of the folder
      SELECT id, provider_file_id, mime_type, parent_folder_id
      FROM files
      WHERE connector_organization_id = $1
        AND parent_folder_id = $2
        AND sync_status != 'deleted'

      UNION ALL

      -- Recursive case: children of folders we've found
      SELECT f.id, f.provider_file_id, f.mime_type, f.parent_folder_id
      FROM files f
      INNER JOIN descendants d ON f.parent_folder_id = d.provider_file_id
      WHERE f.connector_organization_id = $1
        AND f.sync_status != 'deleted'
    )
    SELECT id FROM descendants
    WHERE mime_type != 'application/vnd.google-apps.folder'
    """

    case Repo.query(query, [connector_organization_id, folder_provider_id]) do
      {:ok, %{rows: rows}} -> List.flatten(rows)
      {:error, _} -> []
    end
  end

  @doc """
  Gets all file IDs directly in a folder (non-recursive).

  ## Examples

      iex> get_direct_child_ids(connector_org_id, "folder123")
      [1, 2, 3]

  """
  def get_direct_child_ids(connector_organization_id, folder_provider_id) do
    from(f in File,
      where: f.connector_organization_id == ^connector_organization_id,
      where: f.parent_folder_id == ^folder_provider_id,
      where: f.sync_status != "deleted",
      where: f.mime_type != "application/vnd.google-apps.folder",
      select: f.id
    )
    |> Repo.all()
  end
end

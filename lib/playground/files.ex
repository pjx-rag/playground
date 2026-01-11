defmodule Playground.Files do
  @moduledoc """
  The Files context.

  Manages file metadata from external connectors.
  All files from the provider are tracked, with sync_status indicating
  which files the user has selected for the RAG pipeline.
  """

  import Ecto.Query, warn: false
  alias Playground.Repo
  alias Playground.Files.File
  alias Playground.Organizations

  @text_mime_types ~w(text/plain text/markdown text/csv application/json text/html)

  @doc """
  Lists all files for a connector organization, excluding deleted files by default.

  ## Examples

      iex> list_files(connector_organization_id)
      [%File{}, ...]

      iex> list_files(connector_organization_id, include_deleted: true)
      [%File{}, ...]

  """
  def list_files(connector_organization_id, opts \\ []) do
    include_deleted = Keyword.get(opts, :include_deleted, false)

    query =
      from(f in File,
        where: f.connector_organization_id == ^connector_organization_id,
        order_by: [desc: f.inserted_at]
      )

    query =
      if include_deleted do
        query
      else
        from(f in query, where: f.sync_status != "deleted")
      end

    Repo.all(query)
  end

  @doc """
  Lists synced files for a user's organization connectors.

  Always scopes by the user's organization.

  ## Examples

      iex> list_synced_files(user)
      [%File{}, ...]

  """
  def list_synced_files(user) do
    org = Organizations.get_user_organization(user)
    connector_org_ids = get_connector_org_ids(org.id)

    from(f in File,
      where: f.connector_organization_id in ^connector_org_ids,
      where: f.sync_status == "synced",
      preload: [connector_organization: :connector]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single file.

  Raises `Ecto.NoResultsError` if the File does not exist.

  ## Examples

      iex> get_file!(123)
      %File{}

      iex> get_file!(456)
      ** (Ecto.NoResultsError)

  """
  def get_file!(id) do
    Repo.get!(File, id)
    |> Repo.preload(:connector_organization)
  end

  @doc """
  Gets a file by provider file ID and connector organization.

  ## Examples

      iex> get_file_by_provider_id(connector_org_id, "abc123")
      %File{}

      iex> get_file_by_provider_id(connector_org_id, "unknown")
      nil

  """
  def get_file_by_provider_id(connector_organization_id, provider_file_id) do
    Repo.get_by(File,
      connector_organization_id: connector_organization_id,
      provider_file_id: provider_file_id
    )
  end

  @doc """
  Creates a file.

  ## Examples

      iex> create_file(%{field: value})
      {:ok, %File{}}

      iex> create_file(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_file(attrs \\ %{}) do
    %File{}
    |> File.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a file.

  ## Examples

      iex> update_file(file, %{field: new_value})
      {:ok, %File{}}

      iex> update_file(file, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_file(%File{} = file, attrs) do
    file
    |> File.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the sync status of a file.

  ## Examples

      iex> update_sync_status(file, "synced")
      {:ok, %File{}}

  """
  def update_sync_status(%File{} = file, status) do
    file
    |> File.sync_status_changeset(status)
    |> Repo.update()
  end

  @doc """
  Marks a file as deleted (soft delete).

  ## Examples

      iex> mark_file_deleted(file)
      {:ok, %File{}}

  """
  def mark_file_deleted(%File{} = file) do
    file
    |> File.delete_changeset()
    |> Repo.update()
  end

  @doc """
  Deletes a file (hard delete).

  ## Examples

      iex> delete_file(file)
      {:ok, %File{}}

      iex> delete_file(file)
      {:error, %Ecto.Changeset{}}

  """
  def delete_file(%File{} = file) do
    Repo.delete(file)
  end

  @doc """
  Upserts a file (insert or update if exists).

  Used during sync to handle both new files and updates to existing files.

  ## Examples

      iex> upsert_file(%{connector_organization_id: 1, provider_file_id: "abc", name: "file.txt"})
      {:ok, %File{}}

  """
  def upsert_file(attrs) do
    %File{}
    |> File.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at, :sync_status, :synced_at]},
      conflict_target: [:connector_organization_id, :provider_file_id]
    )
  end

  @doc """
  Syncs multiple files to a given status.

  Used for bulk operations like selecting/deselecting folders.

  ## Examples

      iex> bulk_update_sync_status([file1, file2], "synced")
      {2, nil}

  """
  def bulk_update_sync_status(file_ids, status) when is_list(file_ids) do
    now = DateTime.utc_now()

    from(f in File,
      where: f.id in ^file_ids
    )
    |> Repo.update_all(set: [sync_status: status, synced_at: now, updated_at: now])
  end

  @doc """
  Syncs selected files and enqueues them for RAG processing.

  This is the entry point for starting the RAG pipeline:
  1. Updates files to sync_status: "synced"
  2. Resets processing_status to "draft"
  3. Enqueues appropriate worker jobs based on MIME type

  ## Examples

      iex> sync_and_process_files([file1.id, file2.id])
      {:ok, 2}

  """
  def sync_and_process_files(file_ids) when is_list(file_ids) do
    Repo.transaction(fn ->
      now = DateTime.utc_now()

      # Update sync status and reset processing status
      {count, _} =
        from(f in File, where: f.id in ^file_ids)
        |> Repo.update_all(
          set: [
            sync_status: "synced",
            synced_at: now,
            processing_status: "draft",
            updated_at: now
          ]
        )

      # Enqueue chunking jobs for each file
      files = from(f in File, where: f.id in ^file_ids) |> Repo.all()

      Enum.each(files, fn file ->
        enqueue_chunking_job(file)
      end)

      count
    end)
  end

  # Private: Enqueue appropriate chunking worker based on MIME type
  defp enqueue_chunking_job(file) do
    cond do
      file.mime_type in @text_mime_types ->
        enqueue_worker(Playground.RAG.Workers.ProcessTextFileWorker, file.id)

      file.mime_type == "application/pdf" ->
        # TODO: Implement ProcessPdfFileWorker
        :ok

      true ->
        # Default to text worker for unknown types
        enqueue_worker(Playground.RAG.Workers.ProcessTextFileWorker, file.id)
    end
  end

  defp enqueue_worker(worker_module, file_id) do
    %{file_id: file_id}
    |> worker_module.new()
    |> Oban.insert()
  end

  @doc """
  Resets a file for reprocessing by incrementing its revision and clearing chunks.

  This allows a file to be reprocessed from scratch:
  1. Transitions file to "draft" status (via Machinery)
  2. Increments processing_revision
  3. Deletes all chunks from the old revision

  ## Examples

      iex> reset_file_for_reprocessing(file)
      {:ok, %File{}}

      iex> reset_file_for_reprocessing(invalid_file)
      {:error, reason}

  """
  def reset_file_for_reprocessing(%File{} = file) do
    alias Playground.RAG.Chunk

    Repo.transaction(fn ->
      # Check if file has chunks (meaning we need to increment revision)
      has_chunks = Repo.exists?(from(c in Chunk, where: c.file_id == ^file.id))

      # Build the base changes - always reset to draft and clear claim state
      base_changes = %{
        processing_status: "draft",
        processing_claim_id: nil,
        processing_claimed_at: nil,
        processing_attempt: 0
      }

      # Add revision increment if there were chunks
      changes =
        if has_chunks do
          new_revision = (file.processing_revision || 1) + 1
          Map.put(base_changes, :processing_revision, new_revision)
        else
          base_changes
        end

      # Update file directly (bypass Machinery to avoid GenServer issues)
      updated_file =
        file
        |> Ecto.Changeset.change(changes)
        |> Repo.update!()

      # Delete old chunks if any existed
      if has_chunks do
        from(c in Chunk, where: c.file_id == ^file.id)
        |> Repo.delete_all()
      end

      # Broadcast the reset event for real-time UI updates
      Playground.Files.PubSub.broadcast_file_updated(updated_file, :file_reset)

      updated_file
    end)
  end

  @doc """
  Gets the count of files by sync status for a connector organization.

  ## Examples

      iex> count_files_by_status(connector_org_id)
      %{"synced" => 10, "unsynced" => 5}

  """
  def count_files_by_status(connector_organization_id) do
    from(f in File,
      where: f.connector_organization_id == ^connector_organization_id,
      where: f.sync_status != "deleted",
      group_by: f.sync_status,
      select: {f.sync_status, count(f.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Gets all file IDs that are descendants of a folder (recursively).

  Uses recursive CTE to find all nested files under a folder.
  Only returns non-folder files (actual documents).

  ## Examples

      iex> get_descendant_file_ids(connector_org_id, "folder123")
      [1, 2, 3]

  """
  def get_descendant_file_ids(connector_organization_id, folder_provider_id) do
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

      iex> get_direct_child_file_ids(connector_org_id, "folder123")
      [1, 2, 3]

  """
  def get_direct_child_file_ids(connector_organization_id, folder_provider_id) do
    from(f in File,
      where: f.connector_organization_id == ^connector_organization_id,
      where: f.parent_folder_id == ^folder_provider_id,
      where: f.sync_status != "deleted",
      where: f.mime_type != "application/vnd.google-apps.folder",
      select: f.id
    )
    |> Repo.all()
  end

  # Private helper to get connector org IDs for an organization
  defp get_connector_org_ids(organization_id) do
    from(co in Playground.Connectors.ConnectorOrganization,
      where: co.organization_id == ^organization_id,
      select: co.id
    )
    |> Repo.all()
  end
end

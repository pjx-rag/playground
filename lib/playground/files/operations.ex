defmodule Playground.Files.Operations do
  @moduledoc """
  CRUD operations for file management.

  Used by:
  - GoogleDriveSync (create/upsert during sync)
  - AdminFilesLive.Index (update, delete)
  - FilesLive.Index (mark deleted)
  """

  import Ecto.Query
  alias Playground.Repo
  alias Playground.Files.File

  @doc """
  Creates a file.

  ## Examples

      iex> create(%{field: value})
      {:ok, %File{}}

      iex> create(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create(attrs \\ %{}) do
    %File{}
    |> File.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a file.

  ## Examples

      iex> update(file, %{field: new_value})
      {:ok, %File{}}

      iex> update(file, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update(%File{} = file, attrs) do
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

      iex> mark_deleted(file)
      {:ok, %File{}}

  """
  def mark_deleted(%File{} = file) do
    file
    |> File.delete_changeset()
    |> Repo.update()
  end

  @doc """
  Deletes a file (hard delete).

  ## Examples

      iex> delete(file)
      {:ok, %File{}}

      iex> delete(file)
      {:error, %Ecto.Changeset{}}

  """
  def delete(%File{} = file) do
    Repo.delete(file)
  end

  @doc """
  Upserts a file (insert or update if exists).

  Used during sync to handle both new files and updates to existing files.

  ## Examples

      iex> upsert(%{connector_organization_id: 1, provider_file_id: "abc", name: "file.txt"})
      {:ok, %File{}}

  """
  def upsert(attrs) do
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
  Resets a file for reprocessing by incrementing its revision and clearing chunks.

  This allows a file to be reprocessed from scratch:
  1. Transitions file to "draft" status (via Machinery)
  2. Increments processing_revision
  3. Deletes all chunks from the old revision

  ## Examples

      iex> reset_for_reprocessing(file)
      {:ok, %File{}}

      iex> reset_for_reprocessing(invalid_file)
      {:error, reason}

  """
  def reset_for_reprocessing(%File{} = file) do
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
end

defmodule Playground.Files.Processing do
  @moduledoc """
  File processing and RAG pipeline operations.

  Entry point for the RAG pipeline:
  - Updates sync status
  - Resets processing status
  - Enqueues chunking workers based on MIME type

  Used by:
  - FilesLive.Index (bulk sync)
  - GoogleDriveSync (automatic processing)
  """

  import Ecto.Query
  alias Playground.Repo
  alias Playground.Files.File

  @text_mime_types ~w(text/plain text/markdown text/csv application/json text/html)

  @doc """
  Syncs selected files and enqueues them for RAG processing.

  This is the entry point for starting the RAG pipeline:
  1. Updates files to sync_status: "synced"
  2. Resets processing_status to "draft"
  3. Enqueues appropriate worker jobs based on MIME type

  ## Examples

      iex> sync_and_enqueue([file1.id, file2.id])
      {:ok, 2}

  """
  def sync_and_enqueue(file_ids) when is_list(file_ids) do
    # First update sync status in transaction
    {count, _} =
      Repo.transaction(fn ->
        now = DateTime.utc_now()

        # Update sync status and reset processing status
        result =
          from(f in File, where: f.id in ^file_ids)
          |> Repo.update_all(
            set: [
              sync_status: "synced",
              synced_at: now,
              processing_status: "draft",
              updated_at: now
            ]
          )

        result
      end)

    # Then enqueue jobs OUTSIDE the transaction (avoids Machinery GenServer deadlock)
    files = from(f in File, where: f.id in ^file_ids) |> Repo.all()

    Enum.each(files, fn file ->
      enqueue_chunking_job(file)
    end)

    {:ok, count}
  end

  # Private: Enqueue appropriate chunking worker based on MIME type
  defp enqueue_chunking_job(file) do
    # Preload connector_organization to get organization_id
    file = Repo.preload(file, :connector_organization)
    organization_id = file.connector_organization.organization_id

    cond do
      file.mime_type in @text_mime_types ->
        enqueue_worker(Playground.RAG.Workers.ProcessTextFileWorker, file.id, organization_id)

      file.mime_type == "application/pdf" ->
        # PDFs go directly to awaiting_analysis (batch job will pick them up)
        Machinery.transition_to(file, File, "awaiting_analysis")

      true ->
        # Default to text worker for unknown types
        enqueue_worker(Playground.RAG.Workers.ProcessTextFileWorker, file.id, organization_id)
    end
  end

  defp enqueue_worker(worker_module, file_id, organization_id) do
    %{file_id: file_id, organization_id: organization_id}
    |> worker_module.new()
    |> Oban.insert()
  end
end

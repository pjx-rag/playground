defmodule Playground.RAG.Workers.ProcessTextFileWorker do
  @moduledoc """
  Processes text files for RAG pipeline.

  Handles: text/plain, text/markdown, text/csv, application/json

  ## Processing Flow

  1. **Claim**: Atomically claim the file (draft → processing)
  2. **Download & Chunk**: Stream file content and chunk with offset tracking
  3. **Persist**: Insert chunks idempotently with conflict handling
  4. **Complete**: Transition to chunked status

  ## Error Handling

  - Retries up to 3 times with exponential backoff
  - Errors logged to event_logs table
  - Failed files marked with processing_status: "failed"
  """
  use Oban.Worker, queue: :process_text_file, max_attempts: 3

  require Logger

  import Ecto.Query
  alias Playground.Repo
  alias Playground.Files.File
  alias Playground.RAG.{Chunk, ChunkHash, TextChunker, EventLogger}
  alias Playground.Services.GoogleDrive
  alias Playground.ApiTokens

  @text_mime_types ~w(text/plain text/markdown text/csv application/json text/html)

  @doc """
  Returns list of text MIME types this worker can process.
  """
  def text_mime_types, do: @text_mime_types

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_id" => file_id}}) do
    file = Repo.get!(File, file_id) |> Repo.preload(:connector_organization)

    # Guardrail: Only process synced files with text MIME types
    if file.sync_status != "synced" or file.mime_type not in @text_mime_types do
      Logger.info("Skipping file",
        file_id: file_id,
        sync_status: file.sync_status,
        mime_type: file.mime_type
      )

      :ok
    else
      process_file(file)
    end
  end

  defp process_file(file) do
    claim_id = Ecto.UUID.generate()
    start_ms = System.monotonic_time(:millisecond)

    # Step 1: Claim the file (draft → processing)
    case claim_file(file.id, claim_id, file.processing_revision) do
      {:ok, _} ->
        Logger.info("Claimed file for processing",
          file_id: file.id,
          claim_id: claim_id,
          file_name: file.name
        )

        # Step 2: Download and chunk the file
        case download_and_chunk(file, claim_id, start_ms) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            handle_failure(file.id, reason, start_ms)
            {:error, reason}
        end

      {:error, :not_claimed} ->
        Logger.info("File already being processed", file_id: file.id)
        :ok
    end
  rescue
    e ->
      Logger.error("Unexpected error processing file",
        file_id: file.id,
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      handle_failure(file.id, e, System.monotonic_time(:millisecond))
      {:error, e}
  end

  defp claim_file(file_id, claim_id, revision) do
    Repo.transaction(fn ->
      # Atomic claim: only succeeds if status is "draft"
      query =
        from f in File,
          where: f.id == ^file_id and f.processing_status == "draft"

      {updated, _} =
        Repo.update_all(query,
          set: [
            processing_status: "processing",
            processing_claim_id: claim_id,
            processing_claimed_at: DateTime.utc_now()
          ],
          inc: [processing_attempt: 1]
        )

      if updated != 1, do: Repo.rollback(:not_claimed)

      # Log claim event
      EventLogger.log_claim(file_id, claim_id, revision)

      :ok
    end)
  end

  defp download_and_chunk(file, claim_id, start_ms) do
    # Get access token for the connector
    token = get_access_token(file.connector_organization)

    # Download file as stream
    case GoogleDrive.get_file(token, file.provider_file_id, stream: true) do
      {:ok, content_stream} ->
        # Chunk the stream with offset tracking
        chunks =
          content_stream
          |> TextChunker.chunk_stream_with_offsets(chunk_size: 1000, overlap: 200)
          |> Enum.to_list()

        Logger.info("Chunked file",
          file_id: file.id,
          chunk_count: length(chunks),
          file_name: file.name
        )

        # Persist chunks transactionally
        persist_chunks(file, chunks, claim_id, start_ms)

      {:error, reason} ->
        Logger.error("Failed to download file",
          file_id: file.id,
          file_name: file.name,
          error: inspect(reason)
        )

        {:error, "Download failed: #{inspect(reason)}"}
    end
  end

  defp persist_chunks(file, chunks, claim_id, start_ms) do
    Repo.transaction(fn ->
      now = DateTime.utc_now()

      # Prepare chunk rows with hashes for idempotency
      rows =
        Enum.map(chunks, fn chunk ->
          %{
            file_id: file.id,
            revision: file.processing_revision,
            position: chunk.position,
            content: chunk.text,
            start_byte: chunk.start_byte,
            end_byte: chunk.end_byte,
            chunk_hash:
              ChunkHash.sha256(
                file.id,
                file.processing_revision,
                chunk.text,
                chunk.start_byte,
                chunk.end_byte
              ),
            inserted_at: now,
            updated_at: now
          }
        end)

      # Insert chunks with conflict handling (idempotent)
      {inserted_count, _} =
        Repo.insert_all(Chunk, rows,
          on_conflict: :nothing,
          conflict_target: [:file_id, :revision, :chunk_hash]
        )

      Logger.info("Inserted chunks",
        file_id: file.id,
        total_chunks: length(rows),
        inserted: inserted_count
      )

      duration = System.monotonic_time(:millisecond) - start_ms

      # Log chunking complete event
      EventLogger.log_success(
        file.id,
        "chunking_complete",
        "processing",
        "chunked",
        claim_id: claim_id,
        revision: file.processing_revision,
        duration_ms: duration,
        metadata: %{chunk_count: length(chunks)}
      )

      # Update file status: processing → chunked
      {updated, _} =
        Repo.update_all(
          from(f in File,
            where: f.id == ^file.id and f.processing_claim_id == ^claim_id
          ),
          set: [
            processing_status: "chunked",
            processing_claim_id: nil,
            processing_claimed_at: nil
          ]
        )

      if updated != 1 do
        Logger.warning("Failed to update file status, claim mismatch", file_id: file.id)
      end

      {:ok, length(chunks)}
    end)
  end

  defp handle_failure(file_id, error, start_ms) do
    duration = System.monotonic_time(:millisecond) - start_ms

    Repo.transaction(fn ->
      # Log failure event
      EventLogger.log_failure(
        file_id,
        "chunking_failed",
        "processing",
        "failed",
        error,
        duration_ms: duration
      )

      # Update file status to failed
      Repo.update_all(
        from(f in File, where: f.id == ^file_id),
        set: [
          processing_status: "failed",
          processing_claim_id: nil,
          processing_claimed_at: nil
        ]
      )
    end)
  end

  defp get_access_token(connector_organization) do
    # Get the API token for this connector organization
    case ApiTokens.get_valid_token(connector_organization.id, "Google Drive") do
      {:ok, token} ->
        token.access_token

      {:error, _} ->
        raise "No valid access token found for connector organization #{connector_organization.id}"
    end
  end
end

defmodule Playground.RAG.Workers.ProcessTextFileWorker do
  @moduledoc """
  Processes text files for RAG pipeline.

  ## Supported MIME Types

  Native text formats (downloaded directly):
  - text/plain, text/markdown, text/csv, application/json, text/html

  Google Workspace formats (exported to text):
  - application/vnd.google-apps.document → text/plain
  - application/vnd.google-apps.spreadsheet → text/csv
  - application/vnd.google-apps.presentation → text/plain

  ## Processing Flow (via Machinery state machine)

  1. **Transition**: draft → downloading (claims the file)
  2. **Download**: Stream file content from provider
  3. **Transition**: downloading → chunking
  4. **Chunk**: Split content with offset tracking
  5. **Persist**: Insert chunks idempotently with conflict handling
  6. **Transition**: chunking → chunked

  All state transitions use Machinery which handles:
  - State validation
  - Persistence
  - PubSub broadcasts for real-time UI updates

  ## Error Handling

  - Retries up to 3 times with exponential backoff
  - Errors logged to event_logs table
  - Failed files transition to "failed" status
  """
  use Oban.Worker, queue: :process_text_file, max_attempts: 3

  require Logger

  import Ecto.Query
  alias Playground.Repo
  alias Playground.Files.File
  alias Playground.RAG.{Chunk, ChunkHash, TextChunker, EventLogger}
  alias Playground.Services.GoogleDrive
  alias Playground.ApiTokens

  # Native text MIME types that can be downloaded directly
  @text_mime_types ~w(text/plain text/markdown text/csv application/json text/html)

  # Google Workspace types that need to be exported to text
  # Maps Google MIME type to export format
  @google_export_formats %{
    "application/vnd.google-apps.document" => "text/plain",
    "application/vnd.google-apps.spreadsheet" => "text/csv",
    "application/vnd.google-apps.presentation" => "text/plain"
  }

  @doc """
  Returns list of text MIME types this worker can process.
  """
  def text_mime_types, do: @text_mime_types

  @doc """
  Returns map of Google Workspace types to their export formats.
  """
  def google_export_formats, do: @google_export_formats

  @doc """
  Checks if a MIME type is processable by this worker.
  """
  def can_process?(mime_type) do
    mime_type in @text_mime_types or Map.has_key?(@google_export_formats, mime_type)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_id" => file_id, "organization_id" => organization_id}}) do
    # Multi-tenancy enforcement: Verify file belongs to specified organization
    file =
      from(f in File,
        join: co in assoc(f, :connector_organization),
        where: f.id == ^file_id and co.organization_id == ^organization_id,
        preload: [:connector_organization]
      )
      |> Repo.one!()

    # Guardrail: Only process synced files with supported MIME types
    if file.sync_status != "synced" or not can_process?(file.mime_type) do
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

    # Handle retry: If file is in "failed" status, reset to "draft" first
    file =
      if file.processing_status == "failed" do
        case Machinery.transition_to(file, File, "draft") do
          {:ok, reset_file} ->
            Logger.info("Reset failed file to draft for retry",
              file_id: file.id,
              file_name: file.name
            )

            reset_file

          {:error, reason} ->
            Logger.error("Failed to reset file to draft",
              file_id: file.id,
              reason: inspect(reason)
            )

            file
        end
      else
        file
      end

    # Step 1: Transition draft → downloading (claims the file via Machinery)
    case Machinery.transition_to(file, File, "downloading", %{claim_id: claim_id}) do
      {:ok, file} ->
        Logger.info("Transitioned to downloading",
          file_id: file.id,
          claim_id: claim_id,
          file_name: file.name
        )

        # Log claim event
        EventLogger.log_claim(file.id, claim_id, file.processing_revision)

        # Step 2: Download and chunk the file
        case download_and_chunk(file, claim_id, start_ms) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            handle_failure(file, reason, start_ms)
            {:error, reason}
        end

      {:error, reason} ->
        Logger.info("Cannot transition to downloading",
          file_id: file.id,
          reason: inspect(reason)
        )

        :ok
    end
  rescue
    e ->
      Logger.error("Unexpected error processing file",
        file_id: file.id,
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      handle_failure(file, e, System.monotonic_time(:millisecond))
      {:error, e}
  end

  defp download_and_chunk(file, claim_id, start_ms) do
    # Get access token for the connector
    token = get_access_token(file.connector_organization)

    # Build download options - Google Workspace types need export format
    download_opts =
      case Map.get(@google_export_formats, file.mime_type) do
        nil -> [stream: true]
        export_format -> [stream: true, export_format: export_format]
      end

    # Download file (exports Google Workspace types to text format)
    case GoogleDrive.get_file(token, file.provider_file_id, download_opts) do
      {:ok, content_stream} ->
        # Transition downloading → chunking
        case Machinery.transition_to(file, File, "chunking") do
          {:ok, file} ->
            Logger.info("Transitioned to chunking", file_id: file.id)

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

            # Persist chunks and transition to chunked
            persist_chunks(file, chunks, claim_id, start_ms)

          {:error, reason} ->
            {:error, "Failed to transition to chunking: #{inspect(reason)}"}
        end

      {:error, reason} ->
        Logger.error("Failed to download file",
          file_id: file.id,
          file_name: file.name,
          error: inspect(reason)
        )

        {:error, "Download failed: #{inspect(reason)}"}
    end
  end

  defp persist_chunks(file, chunks, _claim_id, start_ms) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

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
      "chunking",
      "chunked",
      revision: file.processing_revision,
      duration_ms: duration,
      metadata: %{chunk_count: length(chunks)}
    )

    # Transition chunking → chunked (via Machinery - handles persistence and PubSub)
    case Machinery.transition_to(file, File, "chunked") do
      {:ok, _file} ->
        Logger.info("Transitioned to chunked", file_id: file.id)
        {:ok, length(chunks)}

      {:error, reason} ->
        {:error, "Failed to transition to chunked: #{inspect(reason)}"}
    end
  end

  defp handle_failure(%File{} = file, error, start_ms) do
    duration = System.monotonic_time(:millisecond) - start_ms

    # Reload file to get current state from database
    current_file = Repo.get!(File, file.id)

    # Log failure event
    EventLogger.log_failure(
      file.id,
      "processing_failed",
      current_file.processing_status,
      "failed",
      error,
      duration_ms: duration
    )

    # Transition to failed - bypass Machinery GenServer to avoid crashes
    # Use direct Ecto update for reliability
    {count, _} =
      Repo.update_all(
        from(f in File, where: f.id == ^file.id),
        set: [
          processing_status: "failed",
          processing_claim_id: nil,
          processing_claimed_at: nil,
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        ]
      )

    if count > 0 do
      Logger.info("Transitioned to failed", file_id: file.id)

      # Broadcast PubSub event manually (normally done by Machinery after_transition)
      updated_file = Repo.get!(File, file.id)

      Phoenix.PubSub.broadcast(
        Playground.PubSub,
        "files:#{file.id}",
        {:file_failed, updated_file}
      )

      Phoenix.PubSub.broadcast(
        Playground.PubSub,
        "files:index",
        {:file_failed, updated_file}
      )
    else
      Logger.error("Failed to transition to failed state", file_id: file.id)
    end
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

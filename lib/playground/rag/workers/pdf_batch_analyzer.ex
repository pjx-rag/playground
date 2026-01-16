defmodule Playground.RAG.Workers.PdfBatchAnalyzer do
  @moduledoc """
  Batch processes PDFs awaiting AI analysis.

  ## Processing Flow (Task Fan-out)

  1. **Query**: Fetch up to 2 PDFs with status "awaiting_analysis"
  2. **Fan-out**: Launch async Task for each PDF
  3. **Per-PDF**: Download → AI Analyze → Chunk
  4. **Await**: Wait for all Tasks to complete (2 min timeout per PDF)
  5. **Batch Update**: Transaction to persist all results

  ## Performance

  - Processes 2 PDFs concurrently (configurable via @batch_size)
  - ~10 DB operations per batch (vs 208 with Oban-per-file approach)
  - Explicit GC after batch to free PDF binary memory

  ## Error Handling

  - Per-PDF errors don't fail the batch
  - Failed PDFs transition to "failed" status
  - Successful PDFs transition to "chunked" status
  - Event logs track all state transitions
  """
  use Oban.Worker, queue: :pdf_batch_analyzer, max_attempts: 3

  require Logger
  import Ecto.Query

  alias Playground.Repo
  alias Playground.Files.File
  alias Playground.RAG.{Chunk, ChunkHash, TextChunker, EventLogger}
  alias Playground.Services.Integrations.GoogleDrive
  alias Playground.Services.AI.PdfAnalyzer
  alias Playground.ApiTokens

  @batch_size 2
  @task_timeout 120_000

  # 2 minutes per PDF

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting PDF batch analysis", batch_size: @batch_size)

    # Fetch PDFs awaiting analysis
    files =
      from(f in File,
        join: co in assoc(f, :connector_organization),
        where: f.processing_status == "awaiting_analysis",
        where: f.mime_type == "application/pdf",
        order_by: [asc: f.updated_at],
        limit: ^@batch_size,
        preload: [:connector_organization]
      )
      |> Repo.all()

    if Enum.empty?(files) do
      Logger.debug("No PDFs awaiting analysis")
      :ok
    else
      Logger.info("Processing batch", file_count: length(files))

      # Fan out async tasks
      results =
        files
        |> Enum.map(&Task.async(fn -> process_single_pdf(&1) end))
        |> Task.await_many(@task_timeout)

      # Batch persist results in transaction
      persist_batch_results(results)

      # Explicit GC to free PDF binary memory
      :erlang.garbage_collect()

      Logger.info("Batch analysis complete",
        file_count: length(files),
        success: Enum.count(results, &match?({:ok, _}, &1)),
        failed: Enum.count(results, &match?({:error, _}, &1))
      )

      :ok
    end
  end

  defp process_single_pdf(file) do
    start_ms = System.monotonic_time(:millisecond)
    claim_id = Ecto.UUID.generate()

    Logger.info("Processing PDF",
      file_id: file.id,
      file_name: file.name,
      claim_id: claim_id
    )

    # Transition to "analyzing"
    case Machinery.transition_to(file, File, "analyzing", %{claim_id: claim_id}) do
      {:ok, file} ->
        # Log claim event (awaiting_analysis → analyzing)
        EventLogger.log_claim(file.id, claim_id, file.processing_revision, "awaiting_analysis", "analyzing")

        # Execute full pipeline
        case execute_pipeline(file, claim_id, start_ms) do
          {:ok, result} ->
            {:ok, Map.put(result, :file_id, file.id)}

          {:error, reason} ->
            handle_failure(file, reason, start_ms)
            {:error, %{file_id: file.id, reason: reason}}
        end

      {:error, reason} ->
        Logger.info("Cannot transition to analyzing",
          file_id: file.id,
          reason: inspect(reason)
        )

        {:error, %{file_id: file.id, reason: "transition_failed"}}
    end
  rescue
    e ->
      Logger.error("Unexpected error processing PDF",
        file_id: file.id,
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      handle_failure(file, e, System.monotonic_time(:millisecond))
      {:error, %{file_id: file.id, reason: Exception.message(e)}}
  end

  defp execute_pipeline(file, claim_id, start_ms) do
    # Get access token
    token = get_access_token(file.connector_organization)

    with {:ok, pdf_binary} <- download_pdf(token, file),
         {:ok, event_log} <- log_analysis_start(file, claim_id),
         {:ok, analysis} <- PdfAnalyzer.analyze(pdf_binary, event_log_id: event_log.id),
         {:ok, chunks} <- chunk_content(file, analysis.content, analysis.category_id),
         :ok <- log_analysis_complete(file, analysis, chunks, start_ms) do
      {:ok,
       %{
         chunks: chunks,
         category_id: analysis.category_id,
         revision: file.processing_revision
       }}
    else
      {:error, reason} ->
        Logger.error("Pipeline failed",
          file_id: file.id,
          file_name: file.name,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp download_pdf(token, file) do
    Logger.debug("Downloading PDF", file_id: file.id)

    case GoogleDrive.get_file(token, file.provider_file_id, stream: false) do
      {:ok, binary} when is_binary(binary) ->
        {:ok, binary}

      {:error, reason} ->
        {:error, "Download failed: #{inspect(reason)}"}
    end
  end

  defp chunk_content(file, content, category_id) do
    # Get category to determine chunk size/overlap
    category = Repo.get(Playground.Files.Category, category_id)

    chunk_size = if category, do: category.chunk_size, else: 1000
    chunk_overlap = if category, do: category.chunk_overlap, else: 200

    Logger.debug("Chunking content",
      file_id: file.id,
      category_id: category_id,
      chunk_size: chunk_size,
      chunk_overlap: chunk_overlap
    )

    chunks =
      [content]
      |> TextChunker.chunk_stream_with_offsets(
        chunk_size: chunk_size,
        overlap: chunk_overlap
      )
      |> Enum.to_list()

    {:ok, chunks}
  end

  defp log_analysis_start(file, claim_id) do
    event_log =
      EventLogger.log_success(
        file.id,
        "analysis_started",
        "awaiting_analysis",
        "analyzing",
        claim_id: claim_id,
        revision: file.processing_revision
      )

    {:ok, event_log}
  end

  defp log_analysis_complete(file, analysis, chunks, start_ms) do
    duration = System.monotonic_time(:millisecond) - start_ms

    EventLogger.log_success(
      file.id,
      "analysis_complete",
      "analyzing",
      "chunked",
      revision: file.processing_revision,
      duration_ms: duration,
      metadata: %{
        chunk_count: length(chunks),
        category_id: analysis.category_id
      }
    )

    :ok
  end

  defp persist_batch_results(results) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      Enum.each(results, fn
        {:ok, result} ->
          # Insert chunks
          rows =
            Enum.map(result.chunks, fn chunk ->
              %{
                file_id: result.file_id,
                revision: result.revision,
                position: chunk.position,
                content: chunk.text,
                start_byte: chunk.start_byte,
                end_byte: chunk.end_byte,
                chunk_hash:
                  ChunkHash.sha256(
                    result.file_id,
                    result.revision,
                    chunk.text,
                    chunk.start_byte,
                    chunk.end_byte
                  ),
                inserted_at: now,
                updated_at: now
              }
            end)

          {inserted_count, _} =
            Repo.insert_all(Chunk, rows,
              on_conflict: :nothing,
              conflict_target: [:file_id, :revision, :chunk_hash]
            )

          Logger.info("Inserted chunks",
            file_id: result.file_id,
            total_chunks: length(rows),
            inserted: inserted_count
          )

          # Update file with category
          from(f in File, where: f.id == ^result.file_id)
          |> Repo.update_all(
            set: [
              category_id: result.category_id,
              processing_status: "chunked",
              processing_claim_id: nil,
              processing_claimed_at: nil,
              updated_at: now
            ]
          )

          # Broadcast success
          updated_file = Repo.get!(File, result.file_id)

          Phoenix.PubSub.broadcast(
            Playground.PubSub,
            "files:#{result.file_id}",
            {:file_chunked, updated_file}
          )

          Phoenix.PubSub.broadcast(
            Playground.PubSub,
            "files:index",
            {:file_chunked, updated_file}
          )

        {:error, error_result} ->
          Logger.warning("Skipping failed PDF",
            file_id: error_result.file_id,
            reason: error_result.reason
          )
      end)
    end)
  end

  defp handle_failure(file, error, start_ms) do
    duration = System.monotonic_time(:millisecond) - start_ms

    # Reload file to get current state
    current_file = Repo.get!(File, file.id)

    # Log failure event
    EventLogger.log_failure(
      file.id,
      "analysis_failed",
      current_file.processing_status,
      "failed",
      error,
      duration_ms: duration
    )

    # Transition to failed
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

      # Broadcast failure
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
    end
  end

  defp get_access_token(connector_organization) do
    case ApiTokens.get_valid_token(connector_organization.id, "Google Drive") do
      {:ok, token} ->
        token.access_token

      {:error, _} ->
        raise "No valid access token found for connector organization #{connector_organization.id}"
    end
  end
end

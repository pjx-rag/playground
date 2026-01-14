defmodule Playground.RAG.Workers.EmbedChunksWorker do
  @moduledoc """
  Generates embeddings for a batch of chunks using OpenRouter API.

  ## Processing Flow

  1. **Receive batch**: Worker receives list of chunk IDs (up to 100)
  2. **Load chunks**: Fetch chunks with their files
  3. **Transition files**: Move affected files to "embedding" status
  4. **Generate embeddings**: Single API call for entire batch
  5. **Batch update**: Update all chunks with embeddings in one query
  6. **Transition files**: Move completed files to "ready" status

  ## Batching Strategy

  - Processes up to 100 chunks in a single API call (OpenRouter limit)
  - Uses batch update to avoid N+1 queries
  - Handles multiple files' chunks in one job
  - Transitions files to "embedding" when first chunk is processed
  - Transitions files to "ready" when all chunks are embedded

  ## Error Handling

  - Retries up to 3 times with exponential backoff
  - Errors logged to event_logs table
  - Failed files transition to "failed" status
  """
  use Oban.Worker, queue: :embed_chunks, max_attempts: 3

  require Logger

  import Ecto.Query
  alias Playground.Repo
  alias Playground.Files.File
  alias Playground.RAG.{Chunk, EventLogger}
  alias Playground.Services.OpenRouterEmbeddings

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"chunk_ids" => chunk_ids, "organization_id" => organization_id}}) do
    start_ms = System.monotonic_time(:millisecond)

    # Multi-tenancy enforcement: Load chunks with organization verification
    chunks =
      from(c in Chunk,
        join: f in File,
        on: c.file_id == f.id,
        join: co in assoc(f, :connector_organization),
        where: c.id in ^chunk_ids and co.organization_id == ^organization_id,
        preload: [file: f],
        order_by: [asc: c.position]
      )
      |> Repo.all()

    if Enum.empty?(chunks) do
      Logger.info("No chunks found for batch", chunk_ids: chunk_ids, organization_id: organization_id)
      :ok
    else
      process_chunk_batch(chunks, start_ms)
    end
  end

  defp process_chunk_batch(chunks, start_ms) do
    # Group chunks by file
    chunks_by_file = Enum.group_by(chunks, & &1.file_id)
    file_ids = Map.keys(chunks_by_file)

    Logger.info("Processing chunk batch",
      total_chunks: length(chunks),
      file_count: length(file_ids),
      file_ids: file_ids
    )

    # Transition all affected files to "embedding" status
    case transition_files_to_embedding(file_ids) do
      {:ok, transitioned_files} ->
        # Generate embeddings for all chunks in batch
        case generate_batch_embeddings(chunks, start_ms) do
          {:ok, _} ->
            # Check which files are now complete and transition them to "ready"
            complete_files_to_ready(chunks_by_file, start_ms)
            :ok

          {:error, reason} ->
            # Mark all affected files as failed
            handle_batch_failure(transitioned_files, reason, start_ms)
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to transition files to embedding",
          reason: inspect(reason),
          file_ids: file_ids
        )

        :ok
    end
  rescue
    e ->
      Logger.error("Unexpected error in chunk batch processing",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )

      # Try to mark files as failed
      chunks_by_file = Enum.group_by(chunks, & &1.file_id)
      files = Repo.all(from f in File, where: f.id in ^Map.keys(chunks_by_file))
      Enum.each(files, &handle_failure(&1, e, start_ms))

      {:error, e}
  end

  defp transition_files_to_embedding(file_ids) do
    # Load files and transition them
    files =
      from(f in File,
        where: f.id in ^file_ids,
        where: f.processing_status == "chunked"
      )
      |> Repo.all()

    # Transition each file
    transitioned =
      Enum.reduce_while(files, {:ok, []}, fn file, {:ok, acc} ->
        claim_id = Ecto.UUID.generate()

        case Machinery.transition_to(file, File, "embedding", %{claim_id: claim_id}) do
          {:ok, updated_file} ->
            Logger.info("Transitioned file to embedding",
              file_id: file.id,
              claim_id: claim_id
            )

            # Log claim event (chunked → embedding)
            EventLogger.log_claim(file.id, claim_id, file.processing_revision, "chunked", "embedding")
            {:cont, {:ok, [updated_file | acc]}}

          {:error, reason} ->
            Logger.warning("Could not transition file to embedding",
              file_id: file.id,
              reason: inspect(reason)
            )

            # Continue with other files
            {:cont, {:ok, acc}}
        end
      end)

    transitioned
  end

  defp generate_batch_embeddings(chunks, start_ms) do
    Logger.info("Generating embeddings for batch",
      chunk_count: length(chunks)
    )

    # Extract texts from chunks
    texts = Enum.map(chunks, & &1.content)

    # Generate embeddings in single API call
    case OpenRouterEmbeddings.create_embeddings(texts) do
      {:ok, embeddings} ->
        # Batch update chunks with embeddings
        batch_update_chunks_with_embeddings(chunks, embeddings, start_ms)

      {:error, reason} ->
        Logger.error("Failed to generate embeddings",
          chunk_count: length(chunks),
          error: inspect(reason)
        )

        {:error, "Embedding generation failed: #{inspect(reason)}"}
    end
  end

  defp batch_update_chunks_with_embeddings(chunks, embeddings, start_ms) do
    # Pair chunks with their embeddings
    chunk_embedding_pairs = Enum.zip(chunks, embeddings)

    # Use Ecto.Multi to batch update all chunks
    multi =
      Enum.reduce(chunk_embedding_pairs, Ecto.Multi.new(), fn {chunk, embedding}, multi ->
        changeset = Ecto.Changeset.change(chunk, %{embedding: embedding})
        Ecto.Multi.update(multi, {:chunk, chunk.id}, changeset)
      end)

    case Repo.transaction(multi) do
      {:ok, results} ->
        count = map_size(results)
        duration = System.monotonic_time(:millisecond) - start_ms

        Logger.info("Batch updated chunks with embeddings",
          total_chunks: length(chunks),
          updated: count,
          duration_ms: duration
        )

        {:ok, count}

      {:error, failed_operation, changeset, _} ->
        Logger.error("Failed to batch update chunks",
          failed_operation: failed_operation,
          errors: inspect(changeset.errors),
          chunk_count: length(chunks)
        )

        {:error, "Batch update failed: #{inspect(changeset.errors)}"}
    end
  end

  defp complete_files_to_ready(chunks_by_file, start_ms) do
    file_ids = Map.keys(chunks_by_file)

    # Single query for all completion stats (fixes N+1 query)
    chunk_stats =
      from(c in Chunk,
        join: f in File,
        on: c.file_id == f.id,
        where: c.file_id in ^file_ids and c.revision == f.processing_revision,
        group_by: [c.file_id, f.processing_revision],
        select: {
          c.file_id,
          f.processing_revision,
          count(c.id),
          sum(fragment("CASE WHEN ? IS NOT NULL THEN 1 ELSE 0 END", c.embedding))
        }
      )
      |> Repo.all()
      |> Map.new(fn {file_id, revision, total, embedded} -> {file_id, {revision, total, embedded}} end)

    # Batch query all files
    files =
      from(f in File,
        where: f.id in ^file_ids
      )
      |> Repo.all()
      |> Map.new(fn file -> {file.id, file} end)

    # Transition completed files to ready
    Enum.each(chunk_stats, fn {file_id, {revision, total_chunks, embedded_chunks}} ->
      file = Map.get(files, file_id)

      if total_chunks == embedded_chunks do
        # All chunks embedded - transition to ready
        duration = System.monotonic_time(:millisecond) - start_ms

        EventLogger.log_success(
          file.id,
          "embedding_complete",
          "embedding",
          "ready",
          revision: revision,
          duration_ms: duration,
          metadata: %{chunk_count: total_chunks}
        )

        case Machinery.transition_to(file, File, "ready") do
          {:ok, _file} ->
            Logger.info("File complete - transitioned to ready",
              file_id: file.id,
              total_chunks: total_chunks
            )

          {:error, reason} ->
            Logger.error("Failed to transition file to ready",
              file_id: file.id,
              reason: inspect(reason)
            )
        end
      else
        Logger.info("File partially embedded",
          file_id: file.id,
          embedded: embedded_chunks,
          total: total_chunks
        )
      end
    end)
  end

  defp handle_batch_failure(files, error, start_ms) do
    # Mark all files in the batch as failed
    Enum.each(files, fn file ->
      handle_failure(file, error, start_ms)
    end)
  end

  defp handle_failure(%File{} = file, error, start_ms) do
    duration = System.monotonic_time(:millisecond) - start_ms

    # Reload file to get current state from database
    current_file = Repo.get!(File, file.id)

    # Log failure event
    EventLogger.log_failure(
      file.id,
      "embedding_failed",
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
      Phoenix.PubSub.broadcast(
        Playground.PubSub,
        "files:#{file.id}",
        {:file_failed, Repo.get!(File, file.id)}
      )

      Phoenix.PubSub.broadcast(
        Playground.PubSub,
        "files:index",
        {:file_failed, Repo.get!(File, file.id)}
      )
    end
  end
end

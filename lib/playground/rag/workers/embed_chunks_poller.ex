defmodule Playground.RAG.Workers.EmbedChunksPoller do
  @moduledoc """
  Polls for chunks ready for embedding and enqueues them in batches.

  ## Poller Benefits

  - **Batching**: Processes chunks in optimal batches matching OpenRouter API limits (100)
  - **Rate Control**: Limits concurrent embedding jobs to manage API rate limits
  - **Resilience**: Recovers stuck chunks that didn't transition properly
  - **Efficiency**: Maximizes API usage by batching chunks from multiple files

  ## Scheduling

  Runs every 1 minute via Oban cron to check for chunks needing embeddings.

  ## Configuration

  - `@batch_size`: Maximum chunks per API call (OpenRouter limit: 100)
  - `@max_concurrent`: Maximum concurrent embedding jobs (controlled by queue size)

  ## Query Strategy

  Finds chunks that are:
  - Belong to files in "chunked" status (ready for embedding)
  - Have no embedding yet (embedding IS NULL)
  - From synced files (not deleted)
  - Ordered by file synced_at, then chunk position (FIFO processing)
  - Limited to batch size (100 chunks)
  """
  use Oban.Worker, queue: :embed_poller, max_attempts: 1

  require Logger

  import Ecto.Query
  alias Playground.Repo
  alias Playground.Files.File
  alias Playground.RAG.Chunk
  alias Playground.RAG.Workers.EmbedChunksWorker

  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Find chunks ready for embedding
    # Join with files to ensure we only get chunks from files in correct state
    chunks =
      from(c in Chunk,
        join: f in File,
        on: c.file_id == f.id,
        where: f.processing_status == "chunked",
        where: f.sync_status == "synced",
        where: is_nil(c.embedding),
        order_by: [asc: f.synced_at, asc: c.position],
        limit: ^@batch_size,
        select: c.id
      )
      |> Repo.all()

    if Enum.empty?(chunks) do
      Logger.debug("No chunks ready for embedding")
      :ok
    else
      Logger.info("Found chunks ready for embedding",
        count: length(chunks)
      )

      # Enqueue single batch job for all chunks
      job = EmbedChunksWorker.new(%{chunk_ids: chunks})

      case Oban.insert(job) do
        {:ok, _job} ->
          Logger.info("Enqueued embedding batch job",
            chunk_count: length(chunks)
          )

          :ok

        {:error, reason} ->
          Logger.error("Failed to enqueue embedding job",
            reason: inspect(reason),
            chunk_count: length(chunks)
          )

          {:error, reason}
      end
    end
  end
end

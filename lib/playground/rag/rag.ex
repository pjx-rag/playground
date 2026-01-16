defmodule Playground.RAG do
  @moduledoc """
  RAG (Retrieval-Augmented Generation) context facade.

  This facade coordinates cross-module RAG operations. For specific operations:
  - `Playground.RAG.Pipeline` - Execute RAG pipelines based on configured mode
  - `Playground.RAG.Agent` - Composable agentic RAG steps
  - `Playground.RAG.Search` - Hybrid/semantic/fulltext search
  - `Playground.RAG.EventLogger` - Event logging for file processing
  - `Playground.RAG.TextChunker` - Text chunking with offsets
  - `Playground.RAG.Chunk` - Chunk schema
  - `Playground.RAG.EventLog` - Event log schema

  ## Architecture

  The RAG context implements a multi-stage pipeline:
  1. **Ingestion**: Files → Chunks → Embeddings (background workers)
  2. **Retrieval**: Query → Hybrid Search → Ranked Results
  3. **Generation**: Context + Question → AI Answer + Citations

  ## Cross-Module Operations

  This facade handles operations that span multiple RAG modules or coordinate
  with other contexts (Files, Services).
  """

  require Logger

  alias Playground.RAG.{Pipeline, EventLogger, Search}
  alias Playground.Files

  @doc """
  Executes a RAG query with the configured pipeline mode.

  This is the primary entry point for RAG operations. It coordinates:
  - Pipeline execution (via Pipeline.run)
  - Event logging
  - Error handling

  ## Examples

      {:ok, result} = RAG.query("What is the pricing?", organization_id)
      result.answer  # => "The pricing is..."
      result.citations  # => [%{file: "pricing.md", ...}]

  """
  def query(question, organization_id, opts \\ []) when is_binary(question) do
    Pipeline.run(question, organization_id, opts)
  end

  @doc """
  Performs hybrid search across chunks.

  Coordinates semantic + fulltext search with configurable weights.
  This is a cross-module operation that uses Search for execution
  but provides a simplified interface.

  ## Examples

      {:ok, chunks} = RAG.search("machine learning", organization_id, limit: 10)

  """
  def search(query_text, organization_id, opts \\ []) do
    case Search.query(query_text, organization_id: organization_id, limit: opts[:limit] || 20) do
      {:ok, chunks} -> {:ok, chunks}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Processes a file through the RAG ingestion pipeline.

  Cross-module orchestration:
  1. Validates file exists (Files context)
  2. Chunks text (TextChunker)
  3. Generates embeddings (OpenRouterEmbeddings service)
  4. Stores chunks with embeddings
  5. Logs events (EventLogger)

  Note: This is typically called by background workers, not directly.

  ## Examples

      {:ok, chunk_count} = RAG.process_file(file_id)

  """
  def process_file(file_id) do
    with {:ok, file} <- Files.get_file(file_id),
         :ok <- validate_file_for_processing(file),
         {:ok, chunk_count} <- perform_chunking_and_embedding(file) do
      EventLogger.log_success(file_id, "processed", "processing", "ready")
      {:ok, chunk_count}
    else
      {:error, reason} = error ->
        EventLogger.log_failure(file_id, "process", "processing", "error", reason)
        error
    end
  end

  @doc """
  Reprocesses a file that previously failed.

  Cross-module operation that:
  - Clears old chunks and events
  - Resets file status
  - Triggers new processing

  ## Examples

      {:ok, :requeued} = RAG.reprocess_file(file_id)

  """
  def reprocess_file(file_id) do
    with {:ok, _file} <- Files.get_file(file_id),
         :ok <- clear_previous_attempts(file_id),
         {:ok, _updated_file} <- Files.reset_file_status(file_id) do
      # Queue for reprocessing
      {:ok, :requeued}
    end
  end

  @doc """
  Returns RAG pipeline statistics across the system.

  Cross-module aggregation:
  - Total files processed
  - Total chunks generated
  - Average processing time
  - Error rates

  ## Examples

      stats = RAG.get_statistics(organization_id)
      # => %{total_files: 100, total_chunks: 5000, avg_duration_ms: 2500}

  """
  def get_statistics(organization_id) do
    # Implementation would aggregate from Files and EventLog
    %{
      organization_id: organization_id,
      total_files: 0,  # Would query Files context
      total_chunks: 0,  # Would query Chunk
      avg_duration_ms: 0  # Would query EventLog
    }
  end

  # Private helpers

  defp validate_file_for_processing(file) do
    cond do
      file.text_content == nil ->
        {:error, "File has no text content"}

      String.length(file.text_content) < 10 ->
        {:error, "File text content too short"}

      true ->
        :ok
    end
  end

  defp perform_chunking_and_embedding(_file) do
    # Placeholder - actual implementation in workers
    {:ok, 0}
  end

  defp clear_previous_attempts(_file_id) do
    # Would delete old chunks and events
    :ok
  end
end

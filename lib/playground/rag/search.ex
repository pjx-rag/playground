defmodule Playground.RAG.Search do
  @moduledoc """
  Hybrid search combining semantic (vector) and full-text (tsvector) search.

  Based on patterns from Arcana RAG library with improvements for multi-tenancy,
  event sourcing, and production safety.

  ## Search Modes

  - `:hybrid` - Combines semantic + fulltext with min-max normalization (default)
  - `:semantic` - Pure vector similarity search
  - `:fulltext` - Pure PostgreSQL full-text search

  ## Multi-Tenancy

  All searches are automatically scoped to the organization via `connector_organization` FK.

  ## Example

      iex> Search.query("machine learning algorithms", 
      ...>   organization_id: org_id, 
      ...>   mode: :hybrid, 
      ...>   limit: 10
      ...> )
      {:ok, [
        %{
          chunk: %Chunk{...},
          file: %File{...},
          semantic_score: 0.89,
          fulltext_score: 2.3,
          norm_fulltext: 0.82,
          hybrid_score: 0.87
        },
        ...
      ]}
  """

  import Ecto.Query
  alias Playground.Repo
  alias Playground.RAG.Chunk
  alias Playground.Files.File
  alias Playground.Services.OpenRouterEmbeddings

  @default_limit 20
  @default_semantic_weight 0.7
  @default_fulltext_weight 0.3
  @min_semantic_score 0.3

  @doc """
  Main search interface. Generates embedding and executes search based on mode.

  ## Options

  - `:organization_id` - Required. Organization to scope search to.
  - `:mode` - `:hybrid` (default), `:semantic`, or `:fulltext`
  - `:limit` - Number of results (default: 20)
  - `:semantic_weight` - Weight for semantic score in hybrid mode (default: 0.7)
  - `:fulltext_weight` - Weight for fulltext score in hybrid mode (default: 0.3)
  - `:min_semantic_score` - Minimum semantic score threshold (default: 0.3)
  """
  def query(text, opts \\ []) when is_binary(text) do
    organization_id = Keyword.fetch!(opts, :organization_id)
    mode = Keyword.get(opts, :mode, :hybrid)

    # Generate embedding for semantic/hybrid modes
    with {:ok, embedding} <- maybe_generate_embedding(text, mode) do
      case mode do
        :hybrid ->
          hybrid_search(text, embedding, organization_id, opts)

        :semantic ->
          semantic_only(embedding, organization_id, opts)

        :fulltext ->
          fulltext_only(text, organization_id, opts)
      end
    end
  end

  @doc """
  Hybrid search combining semantic and full-text search with min-max normalization.

  Uses a single SQL query with CTEs for efficiency. Returns chunks with all scores
  for debugging/analysis.
  """
  def hybrid_search(query_text, query_embedding, organization_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    semantic_weight = Keyword.get(opts, :semantic_weight, @default_semantic_weight)
    fulltext_weight = Keyword.get(opts, :fulltext_weight, @default_fulltext_weight)
    min_semantic_score = Keyword.get(opts, :min_semantic_score, @min_semantic_score)

    # Build the hybrid search query with CTEs
    query =
      from(f in File,
        join: co in assoc(f, :connector_organization),
        where: co.organization_id == ^organization_id,
        where: f.sync_status == "synced",
        where: f.processing_status == "ready",
        select: f.id
      )

    file_ids = Repo.all(query)

    if Enum.empty?(file_ids) do
      {:ok, []}
    else
      # Execute hybrid search SQL
      sql = """
      WITH base_scores AS (
        SELECT
          c.id,
          c.file_id,
          c.content,
          c.metadata,
          c.position,
          c.start_byte,
          c.end_byte,
          (1 - (c.embedding <=> $1::vector)) AS semantic_score,
          ts_rank(c.search_vector, websearch_to_tsquery('english', $2)) AS fulltext_score
        FROM chunks c
        JOIN files f ON f.id = c.file_id
        WHERE c.file_id = ANY($3::bigint[])
          AND c.revision = f.processing_revision
      ),
      score_bounds AS (
        SELECT
          MIN(fulltext_score) AS min_ft,
          MAX(fulltext_score) AS max_ft
        FROM base_scores
        WHERE fulltext_score > 0
      ),
      normalized AS (
        SELECT
          b.*,
          CASE
            WHEN sb.max_ft - sb.min_ft > 0
            THEN (b.fulltext_score - sb.min_ft) / (sb.max_ft - sb.min_ft)
            ELSE 0
          END AS norm_fulltext
        FROM base_scores b
        CROSS JOIN score_bounds sb
      )
      SELECT
        id,
        file_id,
        content,
        metadata,
        position,
        start_byte,
        end_byte,
        semantic_score,
        fulltext_score,
        norm_fulltext,
        ($4 * semantic_score + $5 * norm_fulltext) AS hybrid_score
      FROM normalized
      WHERE semantic_score > $6 OR fulltext_score > 0
      ORDER BY hybrid_score DESC
      LIMIT $7
      """

      params = [
        query_embedding,
        query_text,
        file_ids,
        semantic_weight,
        fulltext_weight,
        min_semantic_score,
        limit
      ]

      case Repo.query(sql, params) do
        {:ok, result} ->
          chunks = build_search_results(result)
          {:ok, chunks}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Pure semantic (vector similarity) search.
  """
  def semantic_only(query_embedding, organization_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    min_score = Keyword.get(opts, :min_semantic_score, @min_semantic_score)

    query =
      from(c in Chunk,
        join: f in assoc(c, :file),
        join: co in assoc(f, :connector_organization),
        where: co.organization_id == ^organization_id,
        where: f.sync_status == "synced",
        where: f.processing_status == "ready",
        where: c.revision == f.processing_revision,
        where: not is_nil(c.embedding),
        order_by: [desc: fragment("(1 - (? <=> ?::vector))", c.embedding, ^query_embedding)],
        limit: ^limit,
        preload: [file: :connector_organization],
        select: %{
          chunk: c,
          file: f,
          semantic_score: fragment("(1 - (? <=> ?::vector))", c.embedding, ^query_embedding),
          fulltext_score: 0.0,
          norm_fulltext: 0.0,
          hybrid_score: fragment("(1 - (? <=> ?::vector))", c.embedding, ^query_embedding)
        }
      )

    results = Repo.all(query)
    filtered = Enum.filter(results, &(&1.semantic_score >= min_score))
    {:ok, filtered}
  end

  @doc """
  Pure full-text search using PostgreSQL tsvector.
  """
  def fulltext_only(query_text, organization_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    query =
      from(c in Chunk,
        join: f in assoc(c, :file),
        join: co in assoc(f, :connector_organization),
        where: co.organization_id == ^organization_id,
        where: f.sync_status == "synced",
        where: f.processing_status == "ready",
        where: c.revision == f.processing_revision,
        where:
          fragment(
            "? @@ websearch_to_tsquery('english', ?)",
            c.search_vector,
            ^query_text
          ),
        order_by: [
          desc:
            fragment(
              "ts_rank(?, websearch_to_tsquery('english', ?))",
              c.search_vector,
              ^query_text
            )
        ],
        limit: ^limit,
        preload: [file: :connector_organization],
        select: %{
          chunk: c,
          file: f,
          semantic_score: 0.0,
          fulltext_score:
            fragment(
              "ts_rank(?, websearch_to_tsquery('english', ?))",
              c.search_vector,
              ^query_text
            ),
          norm_fulltext: 1.0,
          hybrid_score:
            fragment(
              "ts_rank(?, websearch_to_tsquery('english', ?))",
              c.search_vector,
              ^query_text
            )
        }
      )

    results = Repo.all(query)
    {:ok, results}
  end

  # Private Functions

  defp maybe_generate_embedding(text, :fulltext), do: {:ok, nil}

  defp maybe_generate_embedding(text, _mode) do
    case OpenRouterEmbeddings.create_embeddings([text]) do
      {:ok, [embedding]} -> {:ok, embedding}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_search_results(%{columns: columns, rows: rows}) do
    # Map column names to indices
    col_indices =
      columns
      |> Enum.with_index()
      |> Map.new(fn {col, idx} -> {col, idx} end)

    # Convert rows to result maps
    Enum.map(rows, fn row ->
      chunk_id = Enum.at(row, col_indices["id"])
      file_id = Enum.at(row, col_indices["file_id"])
      content = Enum.at(row, col_indices["content"])
      metadata = Enum.at(row, col_indices["metadata"])
      position = Enum.at(row, col_indices["position"])
      start_byte = Enum.at(row, col_indices["start_byte"])
      end_byte = Enum.at(row, col_indices["end_byte"])
      semantic_score = Enum.at(row, col_indices["semantic_score"])
      fulltext_score = Enum.at(row, col_indices["fulltext_score"])
      norm_fulltext = Enum.at(row, col_indices["norm_fulltext"])
      hybrid_score = Enum.at(row, col_indices["hybrid_score"])

      # Load full chunk and file for associations
      chunk = Repo.get!(Chunk, chunk_id) |> Repo.preload(file: :connector_organization)

      %{
        chunk: chunk,
        file: chunk.file,
        semantic_score: semantic_score || 0.0,
        fulltext_score: fulltext_score || 0.0,
        norm_fulltext: norm_fulltext || 0.0,
        hybrid_score: hybrid_score || 0.0
      }
    end)
  end
end

defmodule Playground.RAG.Agent do
  @moduledoc """
  Agentic RAG pipeline with composable functional steps.

  Supports two modes:
  - **RAG**: Simple retrieval-augmented generation (search → answer)
  - **Agentic RAG**: Advanced pipeline with gating, decomposition, reranking, multi-hop reasoning

  ## Architecture

  Immutable context struct flows through pipeline steps via Elixir pipes.
  Each step enriches the context and returns updated context.

  ## Example (RAG Mode)

      ctx =
        Agent.new("What is machine learning?", organization_id)
        |> Agent.search()
        |> Agent.answer()

      ctx.answer  # => "Machine learning is..."
      ctx.citations  # => [%{file: "ml_intro.md", position: 3}, ...]

  ## Example (Agentic RAG Mode)

      ctx =
        Agent.new("Compare pricing and features", organization_id)
        |> Agent.gate()        # Decide if retrieval needed
        |> Agent.decompose()   # Split into sub-questions
        |> Agent.search()      # Hybrid search for each
        |> Agent.rerank()      # Score relevance
        |> Agent.reason()      # Multi-hop if insufficient
        |> Agent.answer()      # Generate with citations

  ## Multi-Tenancy

  All operations scoped by `organization_id` from context.

  ## Event Logging

  Each LLM call automatically logged via OpenRouter service.
  """

  require Logger

  alias Playground.RAG.Search
  alias Playground.Services.AI.OpenRouter
  alias Playground.Services.AI.OpenRouterEmbeddings
  alias Playground.Settings

  defmodule Context do
    @moduledoc """
    Immutable context that flows through the RAG pipeline.
    """
    defstruct [
      # Input
      :question,
      :organization_id,

      # Intermediate state
      :needs_retrieval,
      :sub_questions,
      :query_embeddings,
      :search_results,
      :ranked_chunks,
      :context_sufficient,

      # Output
      :answer,
      :citations,

      # Metadata for debugging
      :metadata,

      # Dependencies (for testing)
      search: Search,
      llm: OpenRouter,
      embedder: OpenRouterEmbeddings
    ]

    @type t :: %__MODULE__{
            question: String.t(),
            organization_id: integer(),
            needs_retrieval: boolean() | nil,
            sub_questions: [String.t()] | nil,
            query_embeddings: [list(float())] | nil,
            search_results: [map()] | nil,
            ranked_chunks: [map()] | nil,
            context_sufficient: boolean() | nil,
            answer: String.t() | nil,
            citations: [map()] | nil,
            metadata: map(),
            search: module(),
            llm: module(),
            embedder: module()
          }
  end

  @doc """
  Create a new agent context.

  ## Options

  - `:search` - Search module (default: Playground.RAG.Search)
  - `:llm` - LLM service module (default: Playground.Services.AI.OpenRouter)
  - `:embedder` - Embedder service module (default: Playground.Services.AI.OpenRouterEmbeddings)
  """
  def new(question, organization_id, opts \\ []) do
    %Context{
      question: question,
      organization_id: organization_id,
      metadata: %{
        started_at: DateTime.utc_now(),
        steps: []
      },
      search: Keyword.get(opts, :search, Search),
      llm: Keyword.get(opts, :llm, OpenRouter),
      embedder: Keyword.get(opts, :embedder, OpenRouterEmbeddings)
    }
  end

  # Pipeline Steps

  @doc """
  Gate step: Decide if retrieval is needed.

  Uses LLM to determine if the question requires external knowledge.
  For general questions like "Hello" or "What is 2+2?", skips retrieval.

  If `needs_retrieval` is false, subsequent search steps will be skipped.
  """
  def gate(%Context{} = ctx) do
    prompt = """
    You are a gating agent for a document knowledge base. Decide if the user's question might benefit from searching uploaded documents.

    <user_question>
    #{ctx.question}
    </user_question>

    Respond with ONLY "yes" or "no":
    - "yes" if the question asks about specific people, events, data, or facts that could be in documents
    - "yes" if the question mentions inspections, contracts, reports, or any domain-specific topic
    - "no" ONLY if it's clearly a greeting, small talk, or asks about general knowledge unrelated to documents

    When in doubt, answer "yes" - it's better to search and find nothing than to miss relevant information.

    Response:
    """

    model = rag_agent_model()

    case ctx.llm.chat([%{role: "user", content: prompt}], model: model) do
      {:ok, response} ->
        needs_retrieval = String.downcase(String.trim(response)) == "yes"

        ctx
        |> put_in([Access.key(:needs_retrieval)], needs_retrieval)
        |> add_metadata_step(:gate, %{needs_retrieval: needs_retrieval})

      {:error, _reason} ->
        # On error, assume retrieval is needed (safe default)
        ctx
        |> put_in([Access.key(:needs_retrieval)], true)
        |> add_metadata_step(:gate, %{needs_retrieval: true, error: true})
    end
  end

  @doc """
  Decompose step: Break complex questions into simpler sub-questions.

  For multi-part questions like "Compare X and Y", splits into separate questions.
  Each sub-question will be searched independently, then merged with RRF.

  Skipped if gate determined no retrieval needed.
  """
  def decompose(%Context{needs_retrieval: false} = ctx), do: ctx

  def decompose(%Context{} = ctx) do
    prompt = """
    You are a query decomposition agent. Break down complex questions into simpler sub-questions.

    <user_question>
    #{ctx.question}
    </user_question>

    If the question is already simple and focused, respond with just the original question.
    If the question has multiple parts, list each sub-question on a new line.

    Do NOT include numbering or bullets, just one question per line.

    Sub-questions:
    """

    model = rag_agent_model()

    case ctx.llm.chat([%{role: "user", content: prompt}], model: model) do
      {:ok, response} ->
        sub_questions =
          response
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        # If only one sub-question and it's the same as original, use original
        sub_questions =
          if length(sub_questions) == 1 &&
               String.downcase(hd(sub_questions)) == String.downcase(ctx.question) do
            [ctx.question]
          else
            sub_questions
          end

        ctx
        |> put_in([Access.key(:sub_questions)], sub_questions)
        |> add_metadata_step(:decompose, %{sub_questions: sub_questions})

      {:error, _reason} ->
        # On error, use original question
        ctx
        |> put_in([Access.key(:sub_questions)], [ctx.question])
        |> add_metadata_step(:decompose, %{sub_questions: [ctx.question], error: true})
    end
  end

  @doc """
  Search step: Execute hybrid search.

  If decompose was run, searches for each sub-question and merges results with RRF.
  Otherwise, searches for the original question.

  Skipped if gate determined no retrieval needed.
  """
  def search(%Context{needs_retrieval: false} = ctx), do: ctx

  def search(%Context{} = ctx) do
    queries = ctx.sub_questions || [ctx.question]

    # Search for each query separately
    results_per_query =
      Enum.map(queries, fn query ->
        case ctx.search.query(query, organization_id: ctx.organization_id, mode: :hybrid) do
          {:ok, results} -> results
          {:error, _} -> []
        end
      end)

    # Merge using Reciprocal Rank Fusion (RRF) to preserve top results from each sub-query
    # RRF score = sum(1 / (k + rank)) across all queries where the chunk appears
    # k=60 is a standard constant that prevents high-ranked items from dominating
    # Increased limit to 30 to ensure more diverse results for reranking
    search_results = merge_with_rrf(results_per_query, k: 60, limit: 30)

    ctx
    |> put_in([Access.key(:search_results)], search_results)
    |> add_metadata_step(:search, %{
      num_queries: length(queries),
      num_results: length(search_results)
    })
  end

  # Reciprocal Rank Fusion merges multiple ranked lists fairly
  # Ensures top results from each sub-query get representation in final results
  defp merge_with_rrf(results_per_query, opts) do
    k = Keyword.get(opts, :k, 60)
    limit = Keyword.get(opts, :limit, 20)

    # Calculate RRF scores for each chunk across all query results
    rrf_scores =
      results_per_query
      |> Enum.with_index()
      |> Enum.flat_map(fn {results, _query_idx} ->
        results
        |> Enum.with_index(1)  # 1-indexed rank
        |> Enum.map(fn {result, rank} ->
          {result.chunk.id, result, 1.0 / (k + rank)}
        end)
      end)
      |> Enum.group_by(fn {chunk_id, _result, _score} -> chunk_id end)
      |> Enum.map(fn {_chunk_id, entries} ->
        # Sum RRF scores across queries, keep the result with best hybrid_score
        total_rrf = Enum.reduce(entries, 0, fn {_, _, score}, acc -> acc + score end)
        best_result = entries |> Enum.map(fn {_, result, _} -> result end) |> Enum.max_by(& &1.hybrid_score)
        {best_result, total_rrf}
      end)

    # Sort by RRF score and take top results
    rrf_scores
    |> Enum.sort_by(fn {_result, rrf_score} -> rrf_score end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {result, _rrf_score} -> result end)
  end

  @doc """
  Rerank step: Use LLM to score relevance of each chunk.

  Asks LLM to rate each chunk's relevance to the question on a scale of 0-10.
  Re-sorts chunks by LLM relevance score.

  Skipped if no search results.
  """
  def rerank(%Context{search_results: nil} = ctx), do: ctx
  def rerank(%Context{search_results: []} = ctx), do: ctx

  def rerank(%Context{} = ctx) do
    # Take top 30 chunks to rerank (ensures diverse sources from RRF are included)
    chunks_to_rank = Enum.take(ctx.search_results, 30)

    # Build prompt with full chunk content for accurate relevance scoring
    chunks_text =
      chunks_to_rank
      |> Enum.with_index(1)
      |> Enum.map(fn {result, idx} ->
        "[#{idx}] From: #{result.file.name}\n#{result.chunk.content}"
      end)
      |> Enum.join("\n\n---\n\n")

    prompt = """
    Rate each chunk's relevance to this question.

    <user_question>
    #{ctx.question}
    </user_question>

    <chunks>
    #{chunks_text}
    </chunks>

    For each chunk 1-#{length(chunks_to_rank)}, provide a relevance score 0-10:
    - 10: Directly answers the question (contains names, facts being asked)
    - 5-9: Related context but doesn't directly answer
    - 0-4: Unrelated or tangential

    Output ONLY scores, one number per line:
    """

    model = rag_agent_model()

    case ctx.llm.chat([%{role: "user", content: prompt}], model: model) do
      {:ok, response} ->
        scores =
          response
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.with_index(1)
          |> Enum.map(fn {line, idx} ->
            # Extract just the number, handling formats like "1. 8" or "8" or "[1] 8"
            case Regex.run(~r/(\d+)\s*$/, line) do
              [_, num] ->
                String.to_integer(num)

              _ ->
                case Integer.parse(line) do
                  {score, _} ->
                    score

                  :error ->
                    Logger.warning("Failed to parse rerank score for chunk #{idx}: #{inspect(line)}")
                    0
                end
            end
          end)

        # Validate score count matches chunk count
        if length(scores) != length(chunks_to_rank) do
          Logger.warning(
            "Rerank score count mismatch: got #{length(scores)} scores for #{length(chunks_to_rank)} chunks"
          )
        end

        # Combine chunks with scores (pad with 0s if needed)
        scores = scores ++ List.duplicate(0, max(0, length(chunks_to_rank) - length(scores)))

        ranked_chunks =
          chunks_to_rank
          |> Enum.zip(scores)
          |> Enum.map(fn {result, score} ->
            Map.put(result, :rerank_score, score)
          end)
          |> Enum.sort_by(& &1.rerank_score, :desc)

        ctx
        |> put_in([Access.key(:ranked_chunks)], ranked_chunks)
        |> add_metadata_step(:rerank, %{num_ranked: length(ranked_chunks)})

      {:error, _reason} ->
        # On error, use hybrid scores as-is
        ctx
        |> put_in([Access.key(:ranked_chunks)], chunks_to_rank)
        |> add_metadata_step(:rerank, %{error: true})
    end
  end

  @doc """
  Reason step: Multi-hop reasoning.

  Evaluates if the retrieved context is sufficient to answer the question.
  If not, generates a follow-up query and loops back to search.

  Currently a simple implementation. Can be enhanced with iterative refinement.

  Skipped if no ranked chunks.
  """
  def reason(%Context{ranked_chunks: nil} = ctx), do: ctx
  def reason(%Context{ranked_chunks: []} = ctx), do: ctx

  def reason(%Context{} = ctx) do
    # Simple implementation: Check if top chunk has high relevance
    top_chunk = hd(ctx.ranked_chunks)
    rerank_score = Map.get(top_chunk, :rerank_score, 0)

    context_sufficient = rerank_score >= 7

    ctx
    |> put_in([Access.key(:context_sufficient)], context_sufficient)
    |> add_metadata_step(:reason, %{
      context_sufficient: context_sufficient,
      top_rerank_score: rerank_score
    })
  end

  @doc """
  Answer step: Generate final answer with citations.

  Uses retrieved chunks as context for LLM to generate answer.
  Includes citations to source files.

  If no retrieval was needed or no results found, generates answer without RAG.
  """
  def answer(%Context{} = ctx) do
    chunks = ctx.ranked_chunks || ctx.search_results || []

    if Enum.empty?(chunks) do
      # No retrieval - answer directly
      answer_without_rag(ctx)
    else
      # RAG answer with citations
      answer_with_rag(ctx, chunks)
    end
  end

  # Private Helpers

  defp answer_without_rag(ctx) do
    case ctx.llm.chat([%{role: "user", content: ctx.question}]) do
      {:ok, answer} ->
        ctx
        |> put_in([Access.key(:answer)], answer)
        |> put_in([Access.key(:citations)], [])
        |> add_metadata_step(:answer, %{mode: :no_rag})

      {:error, reason} ->
        ctx
        |> put_in([Access.key(:answer)], "I encountered an error: #{inspect(reason)}")
        |> put_in([Access.key(:citations)], [])
        |> add_metadata_step(:answer, %{mode: :error, error: reason})
    end
  end

  defp answer_with_rag(ctx, chunks) do
    # Group chunks by file for file-level citations
    # Take 15 chunks to ensure diverse file coverage for compound questions
    top_chunks = Enum.take(chunks, 15)

    files_with_chunks =
      top_chunks
      |> Enum.group_by(& &1.file.id)
      |> Enum.map(fn {_file_id, file_chunks} ->
        # Use first chunk's file info, collect all chunks
        first = hd(file_chunks)
        %{file: first.file, chunks: file_chunks}
      end)

    # Build context grouped by file (no numbering to avoid LLM citing them)
    context_text =
      files_with_chunks
      |> Enum.map(fn %{file: file, chunks: file_chunks} ->
        chunk_contents =
          file_chunks
          |> Enum.map(fn result ->
            result.chunk.content
          end)
          |> Enum.join("\n\n---\n\n")

        """
        From: #{file.name}

        #{chunk_contents}
        """
      end)
      |> Enum.join("\n\n===\n\n")

    prompt = """
    You are a helpful assistant. Answer the question using the provided context.

    Context:
    #{context_text}

    Question: #{ctx.question}

    Instructions:
    - Answer based on the context provided
    - If the context doesn't contain enough information, say so
    - Be concise and accurate

    Answer:
    """

    case ctx.llm.chat([%{role: "user", content: prompt}]) do
      {:ok, answer} ->
        # Build file-level citations (one per unique file)
        citations =
          files_with_chunks
          |> Enum.map(fn %{file: file, chunks: file_chunks} ->
            # Aggregate scores from all chunks of this file
            best_chunk = Enum.max_by(file_chunks, & &1.hybrid_score)

            %{
              file_id: file.id,
              file_name: file.name,
              file_url: get_file_url(file),
              chunk_count: length(file_chunks),
              positions: Enum.map(file_chunks, & &1.chunk.position),
              semantic_score: best_chunk.semantic_score,
              hybrid_score: best_chunk.hybrid_score,
              rerank_score: Map.get(best_chunk, :rerank_score)
            }
          end)

        ctx
        |> put_in([Access.key(:answer)], answer)
        |> put_in([Access.key(:citations)], citations)
        |> add_metadata_step(:answer, %{mode: :rag, num_citations: length(citations)})

      {:error, reason} ->
        ctx
        |> put_in([Access.key(:answer)], "I encountered an error: #{inspect(reason)}")
        |> put_in([Access.key(:citations)], [])
        |> add_metadata_step(:answer, %{mode: :error, error: reason})
    end
  end

  defp add_metadata_step(ctx, step_name, step_data) do
    step = Map.merge(%{step: step_name, timestamp: DateTime.utc_now()}, step_data)
    # Prepend to list (O(1) instead of O(n)) - will reverse at the end
    steps = [step | ctx.metadata.steps]
    put_in(ctx.metadata.steps, steps)
  end

  # Extract file URL from Google Drive metadata or construct it
  defp get_file_url(file) do
    metadata = file.metadata || %{}

    # Try to get web view link from metadata (check both key formats)
    cond do
      # Google Drive stores web_view_link in metadata
      Map.get(metadata, "web_view_link") ->
        Map.get(metadata, "web_view_link")

      # Also check camelCase variant
      Map.get(metadata, "webViewLink") ->
        Map.get(metadata, "webViewLink")

      # Construct Google Drive link from provider_file_id if available
      file.provider_file_id ->
        "https://drive.google.com/file/d/#{file.provider_file_id}/view"

      # Fallback: no external link available
      true ->
        nil
    end
  end

  # Get RAG agent model from app settings
  defp rag_agent_model do
    Settings.get_app_setting_value("rag_agent_model", "anthropic/claude-3.5-haiku")
  end
end

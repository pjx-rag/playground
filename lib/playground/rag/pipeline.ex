defmodule Playground.RAG.Pipeline do
  @moduledoc """
  Convenience module for executing RAG pipelines based on configured mode.

  Reads the `rag_mode` app setting and executes the appropriate pipeline:
  - `"rag"` - Simple retrieval-augmented generation (search → answer)
  - `"agentic_rag"` - Advanced agentic pipeline (gate → decompose → search → rerank → reason → answer)

  ## Usage

      # Execute with configured mode
      {:ok, ctx} = Pipeline.run("What is machine learning?", organization_id)
      
      ctx.answer  # => "Machine learning is..."
      ctx.citations  # => [%{file: "ml_intro.md", ...}, ...]
      ctx.metadata.steps  # => [%{step: :search, ...}, ...]

      # Override mode
      {:ok, ctx} = Pipeline.run("Compare pricing", organization_id, mode: :rag)

  ## Modes

  ### RAG Mode (Simple)
  - Fastest response time (~2-3 seconds)
  - Lower cost (1 embedding + 1 LLM call)
  - Best for straightforward questions

  ### Agentic RAG Mode (Advanced)
  - Intelligent gating (skips retrieval for general questions)
  - Query decomposition (splits complex multi-part questions)
  - Reranking (LLM scores relevance of chunks)
  - Multi-hop reasoning (iterative refinement)
  - Higher latency (~5-10 seconds)
  - Higher cost (3-5 LLM calls)
  - Best for complex questions requiring reasoning
  """

  alias Playground.RAG.Agent
  alias Playground.Settings

  @doc """
  Run the RAG pipeline for a question.

  ## Options

  - `:mode` - Override the configured RAG mode (`:rag` or `:agentic_rag`)
  - `:organization_id` - Required. Organization to scope search to.

  ## Returns

  - `{:ok, context}` - Successful execution with answer and citations
  - `{:error, reason}` - Execution failed
  """
  def run(question, organization_id, opts \\ []) when is_binary(question) do
    mode = Keyword.get(opts, :mode) || get_rag_mode()

    ctx = Agent.new(question, organization_id)

    result_ctx =
      case mode do
        :rag ->
          run_simple_rag(ctx)

        :agentic_rag ->
          run_agentic_rag(ctx)

        _ ->
          # Invalid mode, default to simple RAG
          run_simple_rag(ctx)
      end

    {:ok, result_ctx}
  rescue
    e ->
      {:error, e}
  end

  @doc """
  Get the configured RAG mode from app settings.

  Returns `:rag` or `:agentic_rag` (default).
  """
  def get_rag_mode do
    mode_string = Settings.get_app_setting_value("rag_mode", "agentic_rag")

    case mode_string do
      "rag" -> :rag
      "agentic_rag" -> :agentic_rag
      _ -> :agentic_rag
    end
  end

  # Private Pipeline Implementations

  defp run_simple_rag(ctx) do
    ctx
    |> Agent.search()
    |> Agent.answer()
  end

  defp run_agentic_rag(ctx) do
    ctx
    |> Agent.gate()
    |> Agent.decompose()
    |> Agent.search()
    |> Agent.rerank()
    |> Agent.reason()
    |> Agent.answer()
  end
end

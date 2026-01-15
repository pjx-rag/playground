defmodule Playground.Repo.Migrations.AddRagMetadataToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      # RAG pipeline execution data
      add :rag_mode, :string  # "rag" or "agentic_rag"
      add :skip_retrieval, :boolean  # true if gate determined no retrieval needed
      add :needs_retrieval, :boolean  # gate's decision
      add :context_sufficient, :boolean  # reason step's evaluation
      add :reason_iterations, :integer, default: 0  # number of multi-hop searches

      # Query decomposition
      add :sub_questions, {:array, :string}  # decomposed queries

      # Retrieval metrics
      add :num_chunks_retrieved, :integer  # total chunks from search
      add :chunks_used, :integer  # chunks actually used in citations

      # Extended metadata for search results, scores, etc (JSONB for flexibility)
      add :rag_debug_data, :jsonb
    end

    # Indexes for analytics and filtering
    create index(:messages, [:rag_mode])
    create index(:messages, [:skip_retrieval])
    create index(:messages, [:reason_iterations])
    create index(:messages, [:rag_debug_data], using: :gin)
  end
end

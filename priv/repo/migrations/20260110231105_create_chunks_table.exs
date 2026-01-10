defmodule Playground.Repo.Migrations.CreateChunksTable do
  use Ecto.Migration

  def change do
    # Enable pgvector extension if not already enabled
    execute "CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector"

    create table(:chunks) do
      add :file_id, references(:files, on_delete: :delete_all), null: false
      add :revision, :integer, null: false, default: 1
      add :position, :integer, null: false, default: 0

      add :content, :text, null: false
      add :embedding, :vector, size: 1536
      add :search_vector, :tsvector
      add :metadata, :map, default: %{}

      add :chunk_hash, :binary, null: false
      add :start_byte, :integer
      add :end_byte, :integer

      timestamps(type: :utc_datetime)
    end

    # Indexes for querying and performance
    create index(:chunks, [:file_id, :revision, :position])
    create unique_index(:chunks, [:file_id, :revision, :chunk_hash])

    # HNSW index for vector similarity search (using raw SQL for operator class)
    execute """
    CREATE INDEX chunks_embedding_hnsw_idx ON chunks
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);
    """, "DROP INDEX IF EXISTS chunks_embedding_hnsw_idx;"

    # GIN index for full-text search
    create index(:chunks, [:search_vector], using: "gin")

    # Index for finding chunks without embeddings
    create index(:chunks, [:file_id], where: "embedding IS NULL")
  end
end

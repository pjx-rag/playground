defmodule Playground.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def up do
    # Index for finding files ready for embedding in embed_chunks_poller
    # Used in: WHERE processing_status = 'chunked' AND sync_status = 'synced' ORDER BY synced_at
    execute """
    CREATE INDEX files_ready_for_embedding_idx
    ON files (processing_status, sync_status, synced_at)
    WHERE processing_status = 'chunked' AND sync_status = 'synced'
    """

    # Composite index for finding chunks pending embedding with ordering
    # Used in: WHERE file_id IN (...) AND embedding IS NULL ORDER BY position
    execute """
    CREATE INDEX chunks_pending_embedding_ordered_idx
    ON chunks (file_id, position)
    WHERE embedding IS NULL
    """

    # Index for file status queries by organization (common in LiveViews)
    # Used in: JOIN connector_organizations WHERE processing_status = X AND org_id = Y
    create index(:files, [:processing_status])
  end

  def down do
    execute "DROP INDEX files_ready_for_embedding_idx"
    execute "DROP INDEX chunks_pending_embedding_ordered_idx"
    drop index(:files, [:processing_status])
  end
end

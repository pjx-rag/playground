defmodule Playground.Repo.Migrations.AddValidationConstraints do
  use Ecto.Migration

  def up do
    # File size validation
    execute """
    ALTER TABLE files
    ADD CONSTRAINT files_size_check
    CHECK (size_bytes IS NULL OR size_bytes >= 0)
    """

    # Sync status validation
    execute """
    ALTER TABLE files
    ADD CONSTRAINT files_sync_status_check
    CHECK (sync_status IN ('unsynced', 'synced', 'deleted'))
    """

    # Processing status validation
    execute """
    ALTER TABLE files
    ADD CONSTRAINT files_processing_status_check
    CHECK (processing_status IN ('draft', 'downloading', 'download_failed',
                                   'chunking', 'chunking_failed', 'chunked',
                                   'embedding', 'embedding_failed', 'ready', 'failed'))
    """
  end

  def down do
    execute "ALTER TABLE files DROP CONSTRAINT files_size_check"
    execute "ALTER TABLE files DROP CONSTRAINT files_sync_status_check"
    execute "ALTER TABLE files DROP CONSTRAINT files_processing_status_check"
  end
end

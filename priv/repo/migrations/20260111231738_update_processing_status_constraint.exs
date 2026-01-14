defmodule Playground.Repo.Migrations.UpdateProcessingStatusConstraint do
  use Ecto.Migration

  def up do
    # Drop the old constraint
    execute "ALTER TABLE files DROP CONSTRAINT files_processing_status_check"

    # Add the new constraint with awaiting_analysis and analyzing states
    execute """
    ALTER TABLE files
    ADD CONSTRAINT files_processing_status_check
    CHECK (processing_status IN ('draft', 'downloading', 'download_failed',
                                   'chunking', 'chunking_failed', 'chunked',
                                   'awaiting_analysis', 'analyzing',
                                   'embedding', 'embedding_failed', 'ready', 'failed'))
    """
  end

  def down do
    # Drop the new constraint
    execute "ALTER TABLE files DROP CONSTRAINT files_processing_status_check"

    # Restore the old constraint without awaiting_analysis and analyzing
    execute """
    ALTER TABLE files
    ADD CONSTRAINT files_processing_status_check
    CHECK (processing_status IN ('draft', 'downloading', 'download_failed',
                                   'chunking', 'chunking_failed', 'chunked',
                                   'embedding', 'embedding_failed', 'ready', 'failed'))
    """
  end
end

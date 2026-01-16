defmodule Playground.Files do
  @moduledoc """
  The Files context facade.

  Manages file metadata from external connectors.
  All files from the provider are tracked, with sync_status indicating
  which files the user has selected for the RAG pipeline.

  Delegates to domain-specific mini-contexts:
  - `Files.Queries` - Query and retrieval operations
  - `Files.Operations` - CRUD operations
  - `Files.Processing` - RAG pipeline entry point
  - `Files.FolderOperations` - Recursive folder queries
  """

  alias Playground.Files.{FolderOperations, Operations, Processing, Queries}

  # ============================================================================
  # QUERY OPERATIONS
  # ============================================================================

  defdelegate list_files(connector_organization_id, opts \\ []),
    to: Queries,
    as: :list_for_connector

  defdelegate list_synced_files(user), to: Queries, as: :list_synced_for_user
  defdelegate get_file(id), to: Queries, as: :get
  defdelegate get_file!(id, user), to: Queries, as: :get_for_user!

  defdelegate get_file_by_provider_id(connector_organization_id, provider_file_id),
    to: Queries,
    as: :get_by_provider_id

  defdelegate count_files_by_status(connector_organization_id),
    to: Queries,
    as: :count_by_status

  # ============================================================================
  # CRUD OPERATIONS
  # ============================================================================

  defdelegate create_file(attrs \\ %{}), to: Operations, as: :create
  defdelegate update_file(file, attrs), to: Operations, as: :update
  defdelegate update_sync_status(file, status), to: Operations
  defdelegate mark_file_deleted(file), to: Operations, as: :mark_deleted
  defdelegate delete_file(file), to: Operations, as: :delete
  defdelegate upsert_file(attrs), to: Operations, as: :upsert
  defdelegate bulk_update_sync_status(file_ids, status), to: Operations
  defdelegate reset_file_for_reprocessing(file), to: Operations, as: :reset_for_reprocessing
  defdelegate reset_file_status(file_id), to: Operations, as: :reset_status

  # ============================================================================
  # PROCESSING & RAG PIPELINE
  # ============================================================================

  defdelegate sync_and_process_files(file_ids), to: Processing, as: :sync_and_enqueue

  # ============================================================================
  # FOLDER OPERATIONS
  # ============================================================================

  defdelegate get_descendant_file_ids(connector_organization_id, folder_provider_id),
    to: FolderOperations,
    as: :get_descendant_ids

  defdelegate get_direct_child_file_ids(connector_organization_id, folder_provider_id),
    to: FolderOperations,
    as: :get_direct_child_ids
end

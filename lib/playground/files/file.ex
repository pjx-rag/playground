defmodule Playground.Files.File do
  @moduledoc """
  File metadata from external connectors (Google Drive, Dropbox, etc.).

  Stores ALL files from the provider, not just selected ones.
  The `sync_status` field tracks which files the user has selected for the RAG pipeline.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @sync_statuses ~w(unsynced synced deleted)
  @processing_statuses ~w(draft processing chunked ready failed)

  @derive {
    Flop.Schema,
    filterable: [:name, :mime_type, :sync_status, :processing_status, :connector_organization_id],
    sortable: [:name, :size_bytes, :synced_at, :inserted_at],
    default_order: %{
      order_by: [:synced_at],
      order_directions: [:desc_nulls_last]
    },
    default_limit: 50
  }

  schema "files" do
    belongs_to :connector_organization, Playground.Connectors.ConnectorOrganization

    # File metadata from connector
    field :provider_file_id, :string
    field :parent_folder_id, :string
    field :name, :string
    field :mime_type, :string
    field :size_bytes, :integer
    field :metadata, :map, default: %{}

    # User selection
    field :sync_status, :string, default: "unsynced"
    field :synced_at, :utc_datetime

    # Processing pipeline
    field :processing_status, :string, default: "draft"

    # Concurrency safety (claims)
    field :processing_claim_id, Ecto.UUID
    field :processing_claimed_at, :utc_datetime
    field :processing_attempt, :integer, default: 0

    # Reprocessing safety
    field :processing_revision, :integer, default: 1

    # Virtual fields for aggregations
    field :chunks_count, :integer, virtual: true

    has_many :chunks, Playground.RAG.Chunk
    has_many :event_logs, Playground.RAG.EventLog

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(file, attrs) do
    file
    |> cast(attrs, [
      :connector_organization_id,
      :provider_file_id,
      :parent_folder_id,
      :name,
      :mime_type,
      :size_bytes,
      :sync_status,
      :metadata,
      :synced_at,
      :processing_status,
      :processing_claim_id,
      :processing_claimed_at,
      :processing_attempt,
      :processing_revision
    ])
    |> validate_required([:connector_organization_id, :provider_file_id, :name])
    |> validate_inclusion(:sync_status, @sync_statuses)
    |> validate_inclusion(:processing_status, @processing_statuses)
    |> unique_constraint([:connector_organization_id, :provider_file_id])
    |> foreign_key_constraint(:connector_organization_id)
  end

  @doc """
  Changeset for updating sync status.
  """
  def sync_status_changeset(file, status) do
    file
    |> cast(%{sync_status: status, synced_at: DateTime.utc_now()}, [:sync_status, :synced_at])
    |> validate_required([:sync_status])
    |> validate_inclusion(:sync_status, @sync_statuses)
  end

  @doc """
  Changeset for marking a file as deleted.
  """
  def delete_changeset(file) do
    file
    |> cast(%{sync_status: "deleted"}, [:sync_status])
    |> validate_required([:sync_status])
  end
end

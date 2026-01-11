defmodule Playground.Files.File do
  @moduledoc """
  File metadata from external connectors (Google Drive, Dropbox, etc.).

  Stores ALL files from the provider, not just selected ones.
  The `sync_status` field tracks which files the user has selected for the RAG pipeline.

  ## Processing Status State Machine

  The `processing_status` field is managed by Machinery and tracks the RAG pipeline state:

  - `draft`: File is synced but not yet processed
  - `downloading`: File content is being downloaded from provider
  - `chunking`: File is being split into chunks
  - `chunked`: Chunking complete, awaiting embeddings
  - `embedding`: Chunks are being embedded (via poller)
  - `ready`: All chunks embedded and indexed
  - `failed`: Processing failed (can retry)

  ## Transitions

  ```
  draft → downloading → chunking → chunked → embedding → ready
            ↓             ↓                      ↓
          failed        failed                 failed
  ```

  ## Usage

      # Start processing a file
      {:ok, file} = Machinery.transition_to(file, File, "downloading", %{claim_id: claim_id})

      # Mark chunking complete
      {:ok, file} = Machinery.transition_to(file, File, "chunked", %{chunk_count: 42})

      # Retry a failed file
      {:ok, file} = Machinery.transition_to(file, File, "draft", %{})
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Playground.Repo

  @sync_statuses ~w(unsynced synced deleted)

  # State machine configuration
  @processing_states ~w(draft downloading chunking chunked embedding ready failed)
  @processing_transitions %{
    # Wildcard: any state can reset to draft (for stuck jobs)
    "*" => ["draft"],
    "draft" => ["downloading"],
    "downloading" => ["chunking", "failed"],
    "chunking" => ["chunked", "failed"],
    "chunked" => ["embedding"],
    "embedding" => ["ready", "failed"],
    "failed" => ["draft"]
  }

  use Machinery,
    field: :processing_status,
    states: @processing_states,
    transitions: @processing_transitions

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
    |> validate_inclusion(:processing_status, @processing_states)
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

  # ============================================================================
  # STATE MACHINE - Helper Functions
  # ============================================================================

  @doc """
  Returns the list of all processing states.
  """
  def processing_states, do: @processing_states

  @doc """
  Returns the processing transitions map.
  """
  def processing_transitions, do: @processing_transitions

  # ============================================================================
  # STATE MACHINE - Before Transition Callback
  # ============================================================================

  @doc """
  Runs validation logic BEFORE the state transition occurs.
  Must return the struct (not a tuple).
  """
  def before_transition(file, _next_state) do
    file
  end

  def before_transition(file, _next_state, _metadata) do
    file
  end

  # ============================================================================
  # STATE MACHINE - After Transition Callback
  # ============================================================================

  @doc """
  Triggers side effects AFTER successful state transition.
  Broadcasts PubSub events for real-time UI updates.
  """
  # Arity 2 versions (delegate to arity 3)
  def after_transition(%__MODULE__{} = file, state) do
    after_transition(file, state, %{})
  end

  # Arity 3 versions with pattern matching on state
  def after_transition(%__MODULE__{} = file, "downloading", _metadata) do
    broadcast_file_event(file, :file_downloading)
    file
  end

  def after_transition(%__MODULE__{} = file, "chunking", _metadata) do
    broadcast_file_event(file, :file_chunking)
    file
  end

  def after_transition(%__MODULE__{} = file, "chunked", _metadata) do
    broadcast_file_event(file, :file_chunked)
    # Note: Embedding is triggered by EmbedChunksPoller which batches multiple files
    file
  end

  def after_transition(%__MODULE__{} = file, "embedding", _metadata) do
    broadcast_file_event(file, :file_embedding)
    file
  end

  def after_transition(%__MODULE__{} = file, "ready", _metadata) do
    broadcast_file_event(file, :file_ready)
    file
  end

  def after_transition(%__MODULE__{} = file, "failed", _metadata) do
    broadcast_file_event(file, :file_failed)
    file
  end

  def after_transition(%__MODULE__{} = file, "draft", _metadata) do
    # Retry - reset to draft
    broadcast_file_event(file, :file_reset)
    file
  end

  defp broadcast_file_event(file, event) do
    # Broadcast to specific file view (matches subscribe_to_file topic)
    Phoenix.PubSub.broadcast(
      Playground.PubSub,
      "files:#{file.id}",
      {event, file}
    )

    # Also broadcast to index view for list updates
    Phoenix.PubSub.broadcast(
      Playground.PubSub,
      "files:index",
      {event, file}
    )
  end

  # ============================================================================
  # STATE MACHINE - Persist Callback
  # ============================================================================

  @doc """
  Handles persisting the state change to the database.
  """
  def persist(%__MODULE__{} = file, next_state) do
    persist(file, next_state, %{})
  end

  def persist(%__MODULE__{} = file, next_state, metadata) do
    changeset =
      file
      |> Ecto.Changeset.change(%{processing_status: next_state})
      |> maybe_set_claim(next_state, metadata)
      |> maybe_clear_claim(next_state)

    case Repo.update(changeset) do
      {:ok, updated_file} ->
        updated_file

      {:error, changeset} ->
        raise "Failed to persist file state: #{inspect(changeset.errors)}"
    end
  end

  defp maybe_set_claim(changeset, "downloading", metadata) do
    claim_id = Map.get(metadata, :claim_id) || Ecto.UUID.generate()

    changeset
    |> Ecto.Changeset.put_change(:processing_claim_id, claim_id)
    |> Ecto.Changeset.put_change(:processing_claimed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> Ecto.Changeset.put_change(:processing_attempt, (changeset.data.processing_attempt || 0) + 1)
  end

  defp maybe_set_claim(changeset, _state, _metadata), do: changeset

  defp maybe_clear_claim(changeset, state) when state in ["chunked", "ready", "failed", "draft"] do
    changeset
    |> Ecto.Changeset.put_change(:processing_claim_id, nil)
    |> Ecto.Changeset.put_change(:processing_claimed_at, nil)
  end

  defp maybe_clear_claim(changeset, _state), do: changeset
end

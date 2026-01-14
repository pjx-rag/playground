defmodule Playground.RAG.EventLog do
  @moduledoc """
  Event log for tracking file processing pipeline state changes.

  This is the single source of truth for state transitions, errors, and timing.
  Milestone timestamps (like "chunked_at" or "embedded_at") are derived from events.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [:file_id, :event, :success, :revision],
    sortable: [:inserted_at, :event, :duration_ms, :id],
    default_limit: 25,
    default_order: %{order_by: [:inserted_at, :id], order_directions: [:desc, :desc]}
  }

  schema "event_logs" do
    belongs_to :file, Playground.Files.File
    has_one :api_request_log, Playground.APIRequestLog

    field :event, :string
    field :from_status, :string
    field :to_status, :string
    field :success, :boolean
    field :error_message, :string
    field :error_type, :string
    field :duration_ms, :integer
    field :metadata, :map, default: %{}

    # Correlate events to a specific run/revision
    field :claim_id, Ecto.UUID
    field :revision, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(event_log, attrs) do
    event_log
    |> cast(attrs, [
      :file_id,
      :event,
      :from_status,
      :to_status,
      :success,
      :error_message,
      :error_type,
      :duration_ms,
      :metadata,
      :claim_id,
      :revision
    ])
    |> validate_required([:file_id, :event, :success])
    |> foreign_key_constraint(:file_id)
  end
end

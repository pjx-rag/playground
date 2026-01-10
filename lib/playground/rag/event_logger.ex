defmodule Playground.RAG.EventLogger do
  @moduledoc """
  Helper functions for logging RAG pipeline events.

  Provides a clean API for recording state transitions, errors, and metrics.
  All events are stored in the event_logs table for audit trail and debugging.
  """

  import Ecto.Query
  alias Playground.Repo
  alias Playground.RAG.EventLog

  @doc """
  Logs a claim event when processing starts.
  """
  def log_claim(file_id, claim_id, revision) do
    %EventLog{}
    |> EventLog.changeset(%{
      file_id: file_id,
      event: "claim_processing",
      from_status: "draft",
      to_status: "processing",
      success: true,
      claim_id: claim_id,
      revision: revision
    })
    |> Repo.insert!()
  end

  @doc """
  Logs a successful state transition with optional metadata.
  """
  def log_success(file_id, event, from_status, to_status, opts \\ []) do
    claim_id = Keyword.get(opts, :claim_id)
    revision = Keyword.get(opts, :revision)
    duration_ms = Keyword.get(opts, :duration_ms)
    metadata = Keyword.get(opts, :metadata, %{})

    %EventLog{}
    |> EventLog.changeset(%{
      file_id: file_id,
      event: event,
      from_status: from_status,
      to_status: to_status,
      success: true,
      claim_id: claim_id,
      revision: revision,
      duration_ms: duration_ms,
      metadata: metadata
    })
    |> Repo.insert!()
  end

  @doc """
  Logs a failure event with error details.
  """
  def log_failure(file_id, event, from_status, to_status, error, opts \\ []) do
    claim_id = Keyword.get(opts, :claim_id)
    revision = Keyword.get(opts, :revision)
    duration_ms = Keyword.get(opts, :duration_ms)

    error_message = if is_exception(error), do: Exception.message(error), else: inspect(error)
    error_type = if is_exception(error), do: error.__struct__ |> to_string(), else: nil

    %EventLog{}
    |> EventLog.changeset(%{
      file_id: file_id,
      event: event,
      from_status: from_status,
      to_status: to_status,
      success: false,
      error_message: error_message,
      error_type: error_type,
      claim_id: claim_id,
      revision: revision,
      duration_ms: duration_ms
    })
    |> Repo.insert!()
  end

  @doc """
  Gets the complete timeline of events for a file.
  """
  def get_timeline(file_id) do
    EventLog
    |> where([e], e.file_id == ^file_id)
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets the last error for a file, if any.
  """
  def get_last_error(file_id) do
    EventLog
    |> where([e], e.file_id == ^file_id)
    |> where([e], e.success == false)
    |> order_by([e], desc: e.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets the timestamp when a file was chunked.
  """
  def get_chunked_at(file_id) do
    EventLog
    |> where([e], e.file_id == ^file_id)
    |> where([e], e.event == "chunking_complete")
    |> select([e], e.inserted_at)
    |> Repo.one()
  end

  @doc """
  Gets the total processing duration for a file across all events.
  """
  def get_total_duration(file_id) do
    EventLog
    |> where([e], e.file_id == ^file_id)
    |> where([e], not is_nil(e.duration_ms))
    |> select([e], sum(e.duration_ms))
    |> Repo.one()
    |> case do
      nil -> 0
      duration -> duration
    end
  end
end

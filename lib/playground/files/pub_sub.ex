defmodule Playground.Files.PubSub do
  @moduledoc """
  PubSub utilities for broadcasting file status changes.

  Enables real-time updates in the UI when file processing states change.
  """

  alias Phoenix.PubSub

  @pubsub Playground.PubSub

  @doc """
  Broadcasts a file update event.

  ## Topics
  - `"files:index"` - General updates for the files list view
  - `"files:{file_id}"` - Updates for a specific file

  ## Events
  - `:file_updated` - File status or metadata changed
  - `:file_processing_started` - File processing began
  - `:file_chunked` - File chunking completed
  - `:file_failed` - File processing failed
  """
  def broadcast_file_updated(file, event_type \\ :file_updated) do
    # Broadcast to index view
    PubSub.broadcast(@pubsub, "files:index", {event_type, file})

    # Broadcast to specific file view
    PubSub.broadcast(@pubsub, "files:#{file.id}", {event_type, file})

    {:ok, file}
  end

  @doc """
  Subscribes to file updates for the index view.
  """
  def subscribe_to_files_index do
    PubSub.subscribe(@pubsub, "files:index")
  end

  @doc """
  Subscribes to updates for a specific file.
  """
  def subscribe_to_file(file_id) do
    PubSub.subscribe(@pubsub, "files:#{file_id}")
  end

  @doc """
  Unsubscribes from file updates.
  """
  def unsubscribe_from_files_index do
    PubSub.unsubscribe(@pubsub, "files:index")
  end

  @doc """
  Unsubscribes from updates for a specific file.
  """
  def unsubscribe_from_file(file_id) do
    PubSub.unsubscribe(@pubsub, "files:#{file_id}")
  end
end

defmodule Playground.RAG.ChunkHash do
  @moduledoc """
  Generates deterministic hashes for chunk content to enable idempotent inserts.

  The hash incorporates:
  - file_id: Which file the chunk belongs to
  - revision: Which processing revision created it
  - text: The actual chunk content
  - start_byte/end_byte: Position in original file

  This ensures retries insert the exact same hash, triggering ON CONFLICT DO NOTHING.
  """

  @doc """
  Generates a SHA256 hash for a chunk.

  ## Examples

      iex> ChunkHash.sha256(123, 1, "hello world", 0, 11)
      <<...binary...>>

  """
  def sha256(file_id, revision, text, start_byte, end_byte) do
    data = "#{file_id}:#{revision}:#{start_byte}:#{end_byte}:#{text}"
    :crypto.hash(:sha256, data)
  end
end

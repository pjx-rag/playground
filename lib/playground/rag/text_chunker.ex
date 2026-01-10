defmodule Playground.RAG.TextChunker do
  @moduledoc """
  Chunks text streams into overlapping segments with byte offset tracking.

  Uses a sliding window approach with configurable chunk size and overlap.
  Tracks byte positions for precise citations and stable re-chunking.
  """

  @default_chunk_size 1000
  @default_overlap 200

  @doc """
  Chunks a text stream into segments with position tracking.

  Returns a stream of maps with:
  - `text`: The chunk content
  - `position`: Sequential position (0, 1, 2, ...)
  - `start_byte`: Starting byte offset in original text
  - `end_byte`: Ending byte offset in original text

  ## Options

  - `:chunk_size` - Maximum characters per chunk (default: #{@default_chunk_size})
  - `:overlap` - Characters to overlap between chunks (default: #{@default_overlap})

  ## Examples

      stream = ["Hello ", "world ", "this is ", "a test"]
      chunks = TextChunker.chunk_stream_with_offsets(stream, chunk_size: 20, overlap: 5)
      Enum.to_list(chunks)
      # => [
      #   %{text: "Hello world this is ", position: 0, start_byte: 0, end_byte: 20},
      #   %{text: " is a test", position: 1, start_byte: 15, end_byte: 25}
      # ]

  """
  def chunk_stream_with_offsets(stream, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    overlap = Keyword.get(opts, :overlap, @default_overlap)

    # First, concatenate the stream into full text
    full_text = stream |> Enum.join("")

    # Then chunk it
    do_chunk_text(full_text, 0, 0, chunk_size, overlap, [])
    |> Enum.reverse()
    |> Stream.into([])
  end

  # Recursively chunk text with overlapping windows
  defp do_chunk_text(text, byte_offset, position, chunk_size, overlap, acc) do
    text_length = String.length(text)

    cond do
      # Empty text - return accumulated chunks
      text_length == 0 ->
        acc

      # Text fits in one chunk - emit final chunk
      text_length <= chunk_size ->
        chunk = %{
          text: text,
          position: position,
          start_byte: byte_offset,
          end_byte: byte_offset + byte_size(text)
        }
        [chunk | acc]

      # Need multiple chunks - extract first chunk and continue
      true ->
        # Extract chunk
        chunk_text = String.slice(text, 0, chunk_size)
        chunk = %{
          text: chunk_text,
          position: position,
          start_byte: byte_offset,
          end_byte: byte_offset + byte_size(chunk_text)
        }

        # Slide window forward (chunk_size - overlap)
        step = chunk_size - overlap
        next_text = String.slice(text, step..-1//1)
        next_offset = byte_offset + byte_size(String.slice(text, 0, step))

        do_chunk_text(next_text, next_offset, position + 1, chunk_size, overlap, [chunk | acc])
    end
  end

  @doc """
  Simple chunker for non-streaming text.

  ## Examples

      text = "Lorem ipsum dolor sit amet..."
      chunks = TextChunker.chunk_text(text, chunk_size: 100, overlap: 20)

  """
  def chunk_text(text, opts \\ []) when is_binary(text) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    overlap = Keyword.get(opts, :overlap, @default_overlap)

    do_chunk_text(text, 0, 0, chunk_size, overlap, [])
    |> Enum.reverse()
  end
end

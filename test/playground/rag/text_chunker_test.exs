defmodule Playground.RAG.TextChunkerTest do
  use ExUnit.Case, async: true

  alias Playground.RAG.TextChunker

  describe "chunk_stream_with_offsets/2" do
    test "chunks short text that fits in one chunk" do
      stream = Stream.map(["Hello, world!"], & &1)

      chunks = TextChunker.chunk_stream_with_offsets(stream, chunk_size: 100, overlap: 20)
               |> Enum.to_list()

      assert length(chunks) == 1
      assert [chunk] = chunks
      assert chunk.text == "Hello, world!"
      assert chunk.position == 0
      assert chunk.start_byte == 0
      assert chunk.end_byte == 13
    end

    test "chunks longer text into multiple chunks with overlap" do
      # Create a text that will need 3 chunks with chunk_size: 50, overlap: 10
      text = String.duplicate("a", 120)
      stream = Stream.map([text], & &1)

      chunks = TextChunker.chunk_stream_with_offsets(stream, chunk_size: 50, overlap: 10)
               |> Enum.to_list()

      assert length(chunks) == 3

      # First chunk: 0-50
      assert Enum.at(chunks, 0).text == String.duplicate("a", 50)
      assert Enum.at(chunks, 0).position == 0
      assert Enum.at(chunks, 0).start_byte == 0
      assert Enum.at(chunks, 0).end_byte == 50

      # Second chunk: 40-90 (overlaps last 10 chars of first chunk)
      assert Enum.at(chunks, 1).text == String.duplicate("a", 50)
      assert Enum.at(chunks, 1).position == 1
      assert Enum.at(chunks, 1).start_byte == 40
      assert Enum.at(chunks, 1).end_byte == 90

      # Third chunk: 80-120 (overlaps last 10 chars of second chunk)
      assert Enum.at(chunks, 2).text == String.duplicate("a", 40)
      assert Enum.at(chunks, 2).position == 2
      assert Enum.at(chunks, 2).start_byte == 80
      assert Enum.at(chunks, 2).end_byte == 120
    end

    test "handles empty stream" do
      stream = Stream.map([], & &1)

      chunks = TextChunker.chunk_stream_with_offsets(stream, chunk_size: 100, overlap: 20)
               |> Enum.to_list()

      assert chunks == []
    end

    test "handles stream with multiple items" do
      stream = Stream.map(["Hello, ", "world!"], & &1)

      chunks = TextChunker.chunk_stream_with_offsets(stream, chunk_size: 100, overlap: 20)
               |> Enum.to_list()

      assert length(chunks) == 1
      assert [chunk] = chunks
      assert chunk.text == "Hello, world!"
      assert chunk.start_byte == 0
      assert chunk.end_byte == 13
    end

    test "preserves unicode characters correctly" do
      # Unicode chars like emoji take multiple bytes
      text = "Hello 🌍 world"
      stream = Stream.map([text], & &1)

      chunks = TextChunker.chunk_stream_with_offsets(stream, chunk_size: 100, overlap: 20)
               |> Enum.to_list()

      assert length(chunks) == 1
      assert [chunk] = chunks
      assert chunk.text == text
      assert chunk.start_byte == 0
      # "Hello " = 6 bytes, "🌍" = 4 bytes, " world" = 6 bytes = 16 total
      assert chunk.end_byte == byte_size(text)
    end

    test "byte offsets are accurate for overlapping chunks" do
      # Use distinct characters to verify overlap correctness
      text = "AAAAA" <> "BBBBB" <> "CCCCC" <> "DDDDD"  # 20 chars total
      stream = Stream.map([text], & &1)

      chunks = TextChunker.chunk_stream_with_offsets(stream, chunk_size: 10, overlap: 3)
               |> Enum.to_list()

      assert length(chunks) == 3

      # Chunk 0: positions 0-10 (AAAAABBBBB)
      assert Enum.at(chunks, 0).text == "AAAAABBBBB"
      assert Enum.at(chunks, 0).start_byte == 0
      assert Enum.at(chunks, 0).end_byte == 10

      # Chunk 1: positions 7-17 (BBBCCCCCDD) - overlaps last 3 chars of previous (BBB)
      # Step = chunk_size - overlap = 10 - 3 = 7, so starts at position 7
      assert Enum.at(chunks, 1).text == "BBBCCCCCDD"
      assert Enum.at(chunks, 1).start_byte == 7
      assert Enum.at(chunks, 1).end_byte == 17

      # Chunk 2: positions 14-20 (CDDDDD) - overlaps last 3 chars of previous (CDD)
      assert Enum.at(chunks, 2).text == "CDDDDD"
      assert Enum.at(chunks, 2).start_byte == 14
      assert Enum.at(chunks, 2).end_byte == 20
    end

    test "position increments correctly" do
      text = String.duplicate("x", 150)
      stream = Stream.map([text], & &1)

      chunks = TextChunker.chunk_stream_with_offsets(stream, chunk_size: 50, overlap: 10)
               |> Enum.to_list()

      assert length(chunks) == 4
      assert Enum.at(chunks, 0).position == 0
      assert Enum.at(chunks, 1).position == 1
      assert Enum.at(chunks, 2).position == 2
      assert Enum.at(chunks, 3).position == 3
    end

    test "handles newlines and whitespace correctly" do
      text = "Line 1\nLine 2\n\nLine 3"
      stream = Stream.map([text], & &1)

      chunks = TextChunker.chunk_stream_with_offsets(stream, chunk_size: 100, overlap: 20)
               |> Enum.to_list()

      assert length(chunks) == 1
      assert [chunk] = chunks
      assert chunk.text == text
      assert chunk.end_byte == byte_size(text)
    end

    test "chunk_size and overlap parameters are respected" do
      text = String.duplicate("a", 200)
      stream = Stream.map([text], & &1)

      # Different chunk sizes
      chunks_50 = TextChunker.chunk_stream_with_offsets(stream, chunk_size: 50, overlap: 0)
                  |> Enum.to_list()

      chunks_100 = TextChunker.chunk_stream_with_offsets(stream, chunk_size: 100, overlap: 0)
                   |> Enum.to_list()

      assert length(chunks_50) == 4
      assert length(chunks_100) == 2
    end

    test "handles text exactly matching chunk size" do
      text = String.duplicate("x", 100)
      stream = Stream.map([text], & &1)

      chunks = TextChunker.chunk_stream_with_offsets(stream, chunk_size: 100, overlap: 10)
               |> Enum.to_list()

      assert length(chunks) == 1
      assert [chunk] = chunks
      assert chunk.text == text
      assert chunk.start_byte == 0
      assert chunk.end_byte == 100
    end
  end
end

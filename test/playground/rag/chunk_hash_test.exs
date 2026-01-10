defmodule Playground.RAG.ChunkHashTest do
  use ExUnit.Case, async: true

  alias Playground.RAG.ChunkHash

  describe "sha256/5" do
    test "generates deterministic hash for same inputs" do
      file_id = 123
      revision = 1
      text = "Hello, world!"
      start_byte = 0
      end_byte = 13

      hash1 = ChunkHash.sha256(file_id, revision, text, start_byte, end_byte)
      hash2 = ChunkHash.sha256(file_id, revision, text, start_byte, end_byte)

      assert hash1 == hash2
      assert is_binary(hash1)
      assert byte_size(hash1) == 32  # SHA256 produces 32 bytes
    end

    test "generates different hashes for different file_ids" do
      text = "Same text content"
      revision = 1
      start_byte = 0
      end_byte = 17

      hash1 = ChunkHash.sha256(1, revision, text, start_byte, end_byte)
      hash2 = ChunkHash.sha256(2, revision, text, start_byte, end_byte)

      assert hash1 != hash2
    end

    test "generates different hashes for different revisions" do
      file_id = 123
      text = "Same text content"
      start_byte = 0
      end_byte = 17

      hash1 = ChunkHash.sha256(file_id, 1, text, start_byte, end_byte)
      hash2 = ChunkHash.sha256(file_id, 2, text, start_byte, end_byte)

      assert hash1 != hash2
    end

    test "generates different hashes for different text content" do
      file_id = 123
      revision = 1
      start_byte = 0
      end_byte = 10

      hash1 = ChunkHash.sha256(file_id, revision, "Text one", start_byte, end_byte)
      hash2 = ChunkHash.sha256(file_id, revision, "Text two", start_byte, end_byte)

      assert hash1 != hash2
    end

    test "generates different hashes for different byte offsets" do
      file_id = 123
      revision = 1
      text = "Same text"

      hash1 = ChunkHash.sha256(file_id, revision, text, 0, 10)
      hash2 = ChunkHash.sha256(file_id, revision, text, 10, 20)

      assert hash1 != hash2
    end

    test "generates same hash when same chunk appears at same position in reprocessing" do
      # Simulate reprocessing scenario: same chunk at same position should have same hash
      file_id = 123
      revision = 1
      chunk_text = "This is chunk 5 of the document."
      start_byte = 5000
      end_byte = 5033

      hash_first_run = ChunkHash.sha256(file_id, revision, chunk_text, start_byte, end_byte)
      hash_retry = ChunkHash.sha256(file_id, revision, chunk_text, start_byte, end_byte)

      assert hash_first_run == hash_retry
    end

    test "handles empty text" do
      hash = ChunkHash.sha256(1, 1, "", 0, 0)

      assert is_binary(hash)
      assert byte_size(hash) == 32
    end

    test "handles very long text" do
      long_text = String.duplicate("a", 10_000)
      hash = ChunkHash.sha256(1, 1, long_text, 0, 10_000)

      assert is_binary(hash)
      assert byte_size(hash) == 32
    end

    test "handles unicode text correctly" do
      unicode_text = "Hello 世界 🌍"
      hash1 = ChunkHash.sha256(1, 1, unicode_text, 0, byte_size(unicode_text))
      hash2 = ChunkHash.sha256(1, 1, unicode_text, 0, byte_size(unicode_text))

      assert hash1 == hash2
    end
  end
end

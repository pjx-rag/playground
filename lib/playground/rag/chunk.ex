defmodule Playground.RAG.Chunk do
  @moduledoc """
  A chunk of content extracted from a file for RAG processing.

  Chunks belong to files and are versioned via the `revision` field.
  Only chunks matching the file's current `processing_revision` are considered active.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "chunks" do
    belongs_to :file, Playground.Files.File

    field :content, :string
    field :embedding, Pgvector.Ecto.Vector
    field :search_vector, :map, virtual: true
    field :metadata, :map, default: %{}

    # Reprocessing + ordering
    field :revision, :integer
    field :position, :integer

    # Idempotency
    field :chunk_hash, :binary

    # Optional but recommended for citations/order
    field :start_byte, :integer
    field :end_byte, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [
      :file_id,
      :content,
      :embedding,
      :metadata,
      :revision,
      :position,
      :chunk_hash,
      :start_byte,
      :end_byte
    ])
    |> validate_required([:file_id, :content, :revision, :position, :chunk_hash])
    |> foreign_key_constraint(:file_id)
  end
end

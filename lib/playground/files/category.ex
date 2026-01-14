defmodule Playground.Files.Category do
  @moduledoc """
  Schema for document categories with chunking configuration.

  Each category defines optimal chunking parameters for different document types.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "categories" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :instructions, :string

    # Chunking configuration
    field :chunk_size, :integer, default: 1000
    field :chunk_overlap, :integer, default: 200

    # UI/Display
    field :color, :string
    field :icon, :string
    field :display_order, :integer, default: 0

    has_many :files, Playground.Files.File

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :instructions,
      :chunk_size,
      :chunk_overlap,
      :color,
      :icon,
      :display_order
    ])
    |> validate_required([:name, :slug, :chunk_size, :chunk_overlap])
    |> validate_number(:chunk_size, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_number(:chunk_overlap, greater_than_or_equal_to: 0)
    |> validate_overlap_less_than_size()
    |> unique_constraint(:slug)
  end

  defp validate_overlap_less_than_size(changeset) do
    chunk_size = get_field(changeset, :chunk_size)
    chunk_overlap = get_field(changeset, :chunk_overlap)

    if chunk_size && chunk_overlap && chunk_overlap >= chunk_size do
      add_error(changeset, :chunk_overlap, "must be less than chunk_size")
    else
      changeset
    end
  end

  @doc """
  Returns list of all category slugs for AI prompts.
  """
  def all_slugs do
    [
      "technical_documentation",
      "business_report",
      "academic_paper",
      "presentation",
      "financial_document",
      "legal_contract",
      "marketing_material",
      "general"
    ]
  end
end

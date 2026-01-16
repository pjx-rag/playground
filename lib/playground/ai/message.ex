defmodule Playground.AI.Message do
  @moduledoc """
  Schema for individual messages within AI chat conversations.

  Messages can be from either the user or the assistant, and include
  cost tracking and API request logging for full traceability.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :role, :string
    field :content, :string
    field :tokens_used, :integer
    field :cost_usd, :decimal

    # RAG pipeline execution data
    field :rag_mode, :string
    field :skip_retrieval, :boolean
    field :needs_retrieval, :boolean
    field :context_sufficient, :boolean
    field :reason_iterations, :integer
    field :sub_questions, {:array, :string}
    field :num_chunks_retrieved, :integer
    field :chunks_used, :integer
    field :rag_debug_data, :map

    belongs_to :chat, Playground.AI.Chat
    belongs_to :api_request_log, Playground.Services.APIRequestLog

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :role,
      :content,
      :tokens_used,
      :cost_usd,
      :chat_id,
      :api_request_log_id,
      :rag_mode,
      :skip_retrieval,
      :needs_retrieval,
      :context_sufficient,
      :reason_iterations,
      :sub_questions,
      :num_chunks_retrieved,
      :chunks_used,
      :rag_debug_data
    ])
    |> validate_required([:role, :content, :chat_id])
    |> validate_inclusion(:role, ["user", "assistant"])
    |> validate_length(:content, max: 32_000, message: "Message is too long (maximum 32,000 characters)")
    |> validate_rag_mode()
    |> validate_rag_numeric_fields()
    |> foreign_key_constraint(:chat_id)
    |> foreign_key_constraint(:api_request_log_id)
  end

  # Validate RAG mode is one of the allowed values
  defp validate_rag_mode(changeset) do
    case get_field(changeset, :rag_mode) do
      nil -> changeset
      mode when mode in ["rag", "agentic_rag"] -> changeset
      _ -> add_error(changeset, :rag_mode, "must be 'rag' or 'agentic_rag'")
    end
  end

  # Validate RAG numeric fields are non-negative
  defp validate_rag_numeric_fields(changeset) do
    changeset
    |> validate_number(:reason_iterations, greater_than_or_equal_to: 0)
    |> validate_number(:num_chunks_retrieved, greater_than_or_equal_to: 0)
    |> validate_number(:chunks_used, greater_than_or_equal_to: 0)
  end
end

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

    belongs_to :chat, Playground.AI.Chat
    belongs_to :api_request_log, Playground.APIRequestLog

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :tokens_used, :cost_usd, :chat_id, :api_request_log_id])
    |> validate_required([:role, :content, :chat_id])
    |> validate_inclusion(:role, ["user", "assistant"])
    |> validate_length(:content, max: 32_000, message: "Message is too long (maximum 32,000 characters)")
    |> foreign_key_constraint(:chat_id)
    |> foreign_key_constraint(:api_request_log_id)
  end
end

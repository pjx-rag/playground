defmodule Playground.AI.Chat do
  @moduledoc """
  Schema for AI chat conversations.

  Each chat represents a conversation thread between a user and an AI assistant.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "chats" do
    field :title, :string
    field :model, :string
    field :is_processing, :boolean, default: false

    # AI configuration settings (per-chat, defaults from app settings)
    field :temperature, :float, default: 0.7
    field :max_tokens, :integer, default: 4096
    field :top_p, :float, default: 1.0
    field :frequency_penalty, :float, default: 0.0
    field :presence_penalty, :float, default: 0.0

    belongs_to :user, Playground.Accounts.User
    has_many :messages, Playground.AI.Message

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(chat, attrs) do
    chat
    |> cast(attrs, [
      :title,
      :model,
      :user_id,
      :is_processing,
      :temperature,
      :max_tokens,
      :top_p,
      :frequency_penalty,
      :presence_penalty
    ])
    |> validate_required([:title, :model, :user_id])
    |> validate_length(:title, max: 255)
    |> validate_number(:temperature, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 2.0)
    |> validate_number(:max_tokens, greater_than: 0, less_than_or_equal_to: 128_000)
    |> validate_number(:top_p, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:frequency_penalty, greater_than_or_equal_to: -2.0, less_than_or_equal_to: 2.0)
    |> validate_number(:presence_penalty, greater_than_or_equal_to: -2.0, less_than_or_equal_to: 2.0)
    |> foreign_key_constraint(:user_id)
  end
end

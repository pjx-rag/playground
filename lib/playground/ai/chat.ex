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

    belongs_to :user, Playground.Accounts.User
    has_many :messages, Playground.AI.Message

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(chat, attrs) do
    chat
    |> cast(attrs, [:title, :model, :user_id, :is_processing])
    |> validate_required([:title, :model, :user_id])
    |> validate_length(:title, max: 255)
    |> foreign_key_constraint(:user_id)
  end
end

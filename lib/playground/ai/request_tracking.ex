defmodule Playground.AI.RequestTracking do
  @moduledoc """
  Schema for tracking individual AI request timestamps per user.
  Used for sliding window rate limiting.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "ai_request_tracking" do
    field :requested_at, :utc_datetime

    belongs_to :user, Playground.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(request_tracking, attrs) do
    request_tracking
    |> cast(attrs, [:user_id, :requested_at])
    |> validate_required([:user_id, :requested_at])
    |> foreign_key_constraint(:user_id)
  end
end

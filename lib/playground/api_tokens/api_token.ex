defmodule Playground.ApiTokens.ApiToken do
  @moduledoc """
  Generic polymorphic OAuth token storage.

  Works for any OAuth integration: connectors, external APIs, etc.
  The Oban worker automatically refreshes ANY token in this table that's expiring.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "api_tokens" do
    field :resource_type, :string
    field :resource_id, :integer
    field :access_token, :string
    field :refresh_token, :string
    field :expires_at, :utc_datetime
    field :token_type, :string, default: "Bearer"
    field :scope, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(api_token, attrs) do
    api_token
    |> cast(attrs, [:resource_type, :resource_id, :access_token, :refresh_token, :expires_at, :token_type, :scope])
    |> validate_required([:resource_type, :resource_id, :access_token])
    |> unique_constraint([:resource_type, :resource_id])
  end

  @doc """
  Changeset for updating tokens after refresh.
  """
  def refresh_changeset(api_token, attrs) do
    api_token
    |> cast(attrs, [:access_token, :refresh_token, :expires_at, :token_type, :scope])
    |> validate_required([:access_token, :expires_at])
  end
end

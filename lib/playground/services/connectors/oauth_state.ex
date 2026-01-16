defmodule Playground.Services.Connectors.OAuthState do
  @moduledoc """
  Represents a temporary OAuth state parameter for CSRF protection.

  States are stored in the database with a TTL and automatically cleaned up.
  Each state is single-use and expires after 10 minutes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:state_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime, updated_at: false]

  schema "oauth_states" do
    field :user_id, :integer
    field :connector_id, :integer
    field :expires_at, :utc_datetime

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(oauth_state, attrs) do
    oauth_state
    |> cast(attrs, [:state_id, :user_id, :connector_id, :expires_at])
    |> validate_required([:state_id, :user_id, :connector_id, :expires_at])
  end

  @doc """
  Generates a new cryptographically secure state ID.
  """
  def generate_state_id do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end
end

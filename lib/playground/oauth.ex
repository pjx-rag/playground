defmodule Playground.OAuth do
  @moduledoc """
  Context for managing OAuth state parameters with CSRF protection.

  Provides secure, single-use state tokens with automatic expiration.
  """

  import Ecto.Query
  alias Playground.Repo
  alias Playground.OAuth.OAuthState

  @state_ttl_seconds 600  # 10 minutes

  @doc """
  Creates a new OAuth state for the given user and connector.

  Returns the state ID that should be sent to the OAuth provider.

  ## Examples

      iex> create_state(user_id, connector_id)
      {:ok, "abc123...xyz"}

  """
  def create_state(user_id, connector_id) do
    state_id = OAuthState.generate_state_id()
    expires_at = DateTime.utc_now() |> DateTime.add(@state_ttl_seconds, :second)

    attrs = %{
      state_id: state_id,
      user_id: user_id,
      connector_id: connector_id,
      expires_at: expires_at
    }

    case %OAuthState{}
         |> OAuthState.changeset(attrs)
         |> Repo.insert() do
      {:ok, _oauth_state} -> {:ok, state_id}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Verifies and consumes an OAuth state (single-use).

  Returns {:ok, {user_id, connector_id}} if valid and not expired.
  Returns {:error, :invalid_state} if not found or expired.
  Deletes the state after successful verification (single-use).

  ## Examples

      iex> verify_and_consume_state("abc123...xyz")
      {:ok, {1, 5}}

      iex> verify_and_consume_state("invalid")
      {:error, :invalid_state}

  """
  def verify_and_consume_state(state_id) do
    now = DateTime.utc_now()

    # Find and delete in a transaction for atomicity
    Repo.transaction(fn ->
      case Repo.get(OAuthState, state_id) do
        nil ->
          Repo.rollback(:invalid_state)

        state ->
          # Check expiration
          if DateTime.compare(state.expires_at, now) == :lt do
            # Expired - delete it and fail
            Repo.delete(state)
            Repo.rollback(:invalid_state)
          else
            # Valid - delete it (single-use) and return data
            Repo.delete(state)
            {state.user_id, state.connector_id}
          end
      end
    end)
    |> case do
      {:ok, {user_id, connector_id}} -> {:ok, user_id, connector_id}
      {:error, :invalid_state} -> {:error, :invalid_state}
    end
  end

  @doc """
  Cleans up expired OAuth states.

  Should be called periodically (e.g., via Oban cron job every hour).

  ## Examples

      iex> cleanup_expired_states()
      {5, nil}  # Deleted 5 expired states

  """
  def cleanup_expired_states do
    now = DateTime.utc_now()

    from(s in OAuthState,
      where: s.expires_at < ^now
    )
    |> Repo.delete_all()
  end
end

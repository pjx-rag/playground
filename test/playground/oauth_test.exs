defmodule Playground.OAuthTest do
  @moduledoc """
  Tests OAuth state management and CSRF protection.

  Critical security requirements:
  - State parameters must be cryptographically random and unpredictable
  - States must expire after TTL
  - States must be single-use (consumed on verification)
  - Invalid/expired states must be rejected
  """
  use Playground.DataCase, async: true

  import Playground.AccountsFixtures

  alias Playground.OAuth
  alias Playground.OAuth.OAuthState

  describe "create_state/2" do
    test "creates state with cryptographically random state_id" do
      user = user_fixture()
      connector_id = 1

      {:ok, state_id1} = OAuth.create_state(user.id, connector_id)
      {:ok, state_id2} = OAuth.create_state(user.id, connector_id)

      # State IDs should be different
      assert state_id1 != state_id2

      # State IDs should be long enough (>= 32 bytes base64 encoded)
      assert String.length(state_id1) >= 40
      assert String.length(state_id2) >= 40
    end

    test "stores state in database with expiration" do
      user = user_fixture()
      connector_id = 1

      {:ok, state_id} = OAuth.create_state(user.id, connector_id)

      # Verify state exists in database
      state = Repo.get(OAuthState, state_id)
      assert state != nil
      assert state.user_id == user.id
      assert state.connector_id == connector_id

      # Verify expiration is set (15 minutes from now)
      now = DateTime.utc_now()
      expected_expiry = DateTime.add(now, 15 * 60, :second)

      # Allow 5 second tolerance for test execution time
      assert_in_delta DateTime.to_unix(state.expires_at),
                      DateTime.to_unix(expected_expiry),
                      5
    end

    test "sets inserted_at timestamp" do
      user = user_fixture()
      connector_id = 1

      {:ok, state_id} = OAuth.create_state(user.id, connector_id)

      state = Repo.get(OAuthState, state_id)
      assert state.inserted_at != nil
    end
  end

  describe "verify_and_consume_state/1" do
    test "successfully verifies and consumes valid state" do
      user = user_fixture()
      connector_id = 1

      {:ok, state_id} = OAuth.create_state(user.id, connector_id)

      # First verification should succeed
      {:ok, {verified_user_id, verified_connector_id}} =
        OAuth.verify_and_consume_state(state_id)

      assert verified_user_id == user.id
      assert verified_connector_id == connector_id

      # State should be deleted after consumption
      assert Repo.get(OAuthState, state_id) == nil
    end

    test "rejects already-consumed state (single-use enforcement)" do
      user = user_fixture()
      connector_id = 1

      {:ok, state_id} = OAuth.create_state(user.id, connector_id)

      # First verification succeeds
      {:ok, _} = OAuth.verify_and_consume_state(state_id)

      # Second verification should fail - state already consumed
      {:error, :invalid_state} = OAuth.verify_and_consume_state(state_id)
    end

    test "rejects non-existent state" do
      fake_state_id = "nonexistent_state_#{:crypto.strong_rand_bytes(16) |> Base.url_encode64()}"

      {:error, :invalid_state} = OAuth.verify_and_consume_state(fake_state_id)
    end

    test "rejects expired state" do
      user = user_fixture()
      connector_id = 1

      # Create state
      {:ok, state_id} = OAuth.create_state(user.id, connector_id)

      # Manually expire the state by updating expires_at to the past
      state = Repo.get!(OAuthState, state_id)

      Repo.update!(
        Ecto.Changeset.change(state, %{
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })
      )

      # Verification should fail
      {:error, :invalid_state} = OAuth.verify_and_consume_state(state_id)

      # Expired state should be deleted
      assert Repo.get(OAuthState, state_id) == nil
    end

    test "uses database transaction for atomicity" do
      user = user_fixture()
      connector_id = 1

      {:ok, state_id} = OAuth.create_state(user.id, connector_id)

      # Simulate concurrent verification attempts
      # Only one should succeed due to transaction isolation
      task1 = Task.async(fn -> OAuth.verify_and_consume_state(state_id) end)
      task2 = Task.async(fn -> OAuth.verify_and_consume_state(state_id) end)

      results = [Task.await(task1), Task.await(task2)]

      # Exactly one should succeed
      successes = Enum.filter(results, &match?({:ok, _}, &1))
      failures = Enum.filter(results, &match?({:error, :invalid_state}, &1))

      assert length(successes) == 1
      assert length(failures) == 1
    end
  end

  describe "cleanup_expired_states/0" do
    test "deletes expired states" do
      user = user_fixture()

      # Create 3 states: 2 expired, 1 valid
      {:ok, state_id1} = OAuth.create_state(user.id, 1)
      {:ok, state_id2} = OAuth.create_state(user.id, 2)
      {:ok, state_id3} = OAuth.create_state(user.id, 3)

      # Expire first two states
      for state_id <- [state_id1, state_id2] do
        state = Repo.get!(OAuthState, state_id)

        Repo.update!(
          Ecto.Changeset.change(state, %{
            expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
          })
        )
      end

      # Run cleanup
      {count, _} = OAuth.cleanup_expired_states()

      # Should have deleted 2 expired states
      assert count == 2

      # Verify expired states are gone
      assert Repo.get(OAuthState, state_id1) == nil
      assert Repo.get(OAuthState, state_id2) == nil

      # Valid state should remain
      assert Repo.get(OAuthState, state_id3) != nil
    end

    test "returns 0 when no expired states exist" do
      user = user_fixture()

      # Create valid state
      {:ok, _state_id} = OAuth.create_state(user.id, 1)

      # Run cleanup
      {count, _} = OAuth.cleanup_expired_states()

      # Should have deleted 0 states
      assert count == 0
    end

    test "handles empty table gracefully" do
      # No states in database
      {count, _} = OAuth.cleanup_expired_states()
      assert count == 0
    end
  end

  describe "state_id generation" do
    test "generates URL-safe base64 strings without padding" do
      state_id = Playground.OAuth.OAuthState.generate_state_id()

      # Should be URL-safe (no +, /, or =)
      refute String.contains?(state_id, "+")
      refute String.contains?(state_id, "/")
      refute String.contains?(state_id, "=")

      # Should be base64url encoded
      assert String.match?(state_id, ~r/^[A-Za-z0-9_-]+$/)
    end

    test "generates unique state IDs" do
      # Generate 1000 state IDs and ensure they're all unique
      state_ids =
        for _ <- 1..1000 do
          Playground.OAuth.OAuthState.generate_state_id()
        end

      unique_ids = Enum.uniq(state_ids)
      assert length(unique_ids) == 1000
    end

    test "uses strong random bytes (not predictable)" do
      # Generate 10 state IDs and verify they're sufficiently random
      state_ids =
        for _ <- 1..10 do
          Playground.OAuth.OAuthState.generate_state_id()
        end

      # Check that no two state IDs share a common prefix > 8 chars
      # (if they did, it might indicate weak randomness)
      for id1 <- state_ids, id2 <- state_ids, id1 != id2 do
        common_prefix_length =
          Enum.zip(String.graphemes(id1), String.graphemes(id2))
          |> Enum.take_while(fn {c1, c2} -> c1 == c2 end)
          |> length()

        assert common_prefix_length < 8,
               "State IDs #{id1} and #{id2} share suspiciously long common prefix"
      end
    end
  end

  describe "OAuth integration with AuthController" do
    # These would be controller tests, but here are the security requirements:
    #
    # 1. Authorization URL must include state parameter
    # 2. Callback must verify state before proceeding
    # 3. Callback must reject requests with invalid/missing state
    # 4. State must be consumed (deleted) after successful verification
    # 5. Failed verification must not leak information about valid states

    test "placeholder for controller integration tests" do
      # These should be in controller tests, but documenting requirements here:
      # - Test that /auth/google_drive/callback with valid state succeeds
      # - Test that /auth/google_drive/callback with invalid state fails
      # - Test that /auth/google_drive/callback with expired state fails
      # - Test that /auth/google_drive/callback with reused state fails
      # - Test that /auth/google_drive/callback without state parameter fails
      assert true
    end
  end
end

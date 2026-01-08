defmodule Playground.Accounts.User do
  @moduledoc """
  User schema with integrated state machine for account confirmation status.

  ## States

  - `unconfirmed`: User created but email not verified
  - `confirmed`: User email verified and account active

  ## Transitions

  - `unconfirmed → confirmed`: Email verification (via token or admin)
  - `confirmed → unconfirmed`: Admin revokes confirmation

  ## Usage

      # Confirm a user
      {:ok, user} = Machinery.transition_to(user, User, "confirmed", %{})

      # Revoke confirmation (admin only)
      {:ok, user} = Machinery.transition_to(user, User, "unconfirmed", %{actor: "admin:\#{admin_id}"})
  """

  use Ecto.Schema

  # State machine configuration - defined inline to avoid circular dependencies
  @states ["unconfirmed", "confirmed"]
  @transitions %{
    "unconfirmed" => ["confirmed"],
    "confirmed" => ["unconfirmed"]
  }

  use Machinery,
    field: :status,
    states: @states,
    transitions: @transitions

  import Ecto.Changeset
  alias Playground.Repo

  @derive {
    Flop.Schema,
    filterable: [:email, :confirmed_at, :status],
    sortable: [:id, :email, :confirmed_at, :status, :inserted_at],
    default_order: %{order_by: [:inserted_at], order_directions: [:desc]}
  }

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :current_password, :string, virtual: true, redact: true
    field :confirmed_at, :utc_datetime
    field :status, :string, default: "unconfirmed"
    field :first_name, :string
    field :last_name, :string
    field :avatar_url, :string
    field :preferences, :map, default: %{"theme" => "system"}

    timestamps(type: :utc_datetime)
  end

  @allowed ~w(email password hashed_password current_password confirmed_at status first_name last_name avatar_url preferences)a

  # ============================================================================
  # STATE MACHINE - States & Transitions
  # ============================================================================

  @doc """
  Returns all possible states in the user lifecycle.
  """
  def states, do: @states

  @doc """
  Returns the allowed state transitions as a map.
  """
  def transitions, do: @transitions

  # ============================================================================
  # STATE MACHINE - Guard Functions
  # ============================================================================

  @doc """
  Guards control WHO can perform state transitions.
  """

  # Anyone can confirm (via token or admin action)
  def guard_transition(%__MODULE__{}, "confirmed", _metadata) do
    :ok
  end

  # Only admins can revoke confirmation
  def guard_transition(%__MODULE__{}, "unconfirmed", %{actor: "admin:" <> _}) do
    :ok
  end

  def guard_transition(%__MODULE__{}, "unconfirmed", _metadata) do
    {:error, "Only admins can revoke confirmation"}
  end

  # ============================================================================
  # STATE MACHINE - Before/After Hooks
  # ============================================================================

  @doc """
  Runs validation logic BEFORE the state transition occurs.
  """
  def before_transition(user, _next_state, _metadata) do
    {:ok, user}
  end

  @doc """
  Triggers side effects AFTER successful state transition.
  """
  def after_transition(%__MODULE__{} = user, "confirmed", _metadata) do
    Phoenix.PubSub.broadcast(Playground.PubSub, "users", {:user_confirmed, user.id})
    user
  end

  def after_transition(%__MODULE__{} = user, "unconfirmed", _metadata) do
    Phoenix.PubSub.broadcast(Playground.PubSub, "users", {:user_unconfirmed, user.id})
    user
  end

  # ============================================================================
  # STATE MACHINE - Persist Callback
  # ============================================================================

  @doc """
  Handles persisting the state change to the database.
  """
  def persist(%__MODULE__{} = user, next_state, _metadata) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changeset =
      user
      |> Ecto.Changeset.change(%{status: next_state})
      |> maybe_set_confirmed_at(next_state, now)

    case Repo.update(changeset) do
      {:ok, updated_user} -> updated_user
      {:error, changeset} ->
        raise "Failed to persist user state: #{inspect(changeset.errors)}"
    end
  end

  defp maybe_set_confirmed_at(changeset, "confirmed", now) do
    Ecto.Changeset.put_change(changeset, :confirmed_at, now)
  end

  defp maybe_set_confirmed_at(changeset, "unconfirmed", _now) do
    Ecto.Changeset.put_change(changeset, :confirmed_at, nil)
  end

  # ============================================================================
  # STATE MACHINE - Helper Functions
  # ============================================================================

  @doc """
  Returns human-readable state names for UI display.
  """
  def state_name("unconfirmed"), do: "Unconfirmed"
  def state_name("confirmed"), do: "Confirmed"
  def state_name(state), do: state

  @doc """
  Returns available transitions for a user based on current state.
  """
  def available_transitions(%__MODULE__{status: current_state}) do
    Map.get(@transitions, current_state, [])
  end

  # ============================================================================
  # CHANGESETS
  # ============================================================================

  @doc """
  A user changeset for registration.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. Defaults to `true`.

    * `:validate_email` - Validates the uniqueness of the email. Defaults to `true`.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, @allowed)
    |> validate_email(validate_email: true)
    |> validate_password(opts)
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 10, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, Playground.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the email.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  @doc """
  A user changeset for changing the password.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.
  """
  def validate_current_password(changeset, password) do
    changeset = cast(changeset, %{current_password: password}, [:current_password])

    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  @doc """
  Gets the theme preference from user preferences.
  """
  def theme_preference(%__MODULE__{preferences: %{"theme" => theme}}), do: theme
  def theme_preference(%__MODULE__{preferences: preferences}) when is_map(preferences), do: "system"
  def theme_preference(_), do: "system"

  @doc """
  Gets the sidebar collapsed preference from user preferences.
  """
  def sidebar_collapsed?(%__MODULE__{preferences: %{"sidebar_collapsed" => true}}), do: true
  def sidebar_collapsed?(_), do: false

  @doc """
  A user changeset for updating preferences.
  """
  def preferences_changeset(user, attrs) do
    user
    |> cast(attrs, [:preferences])
  end

  @doc """
  A user changeset for changing the profile.
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:first_name, :last_name])
    |> validate_length(:first_name, max: 160)
    |> validate_length(:last_name, max: 160)
  end

  @doc """
  A user changeset for admin updates (without password requirements).
  """
  def admin_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :first_name, :last_name])
    |> validate_email(opts)
  end
end

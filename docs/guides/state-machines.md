# State Machines in Playground

Playground uses the [Machinery](https://hex.pm/packages/machinery) library for state machine management. This provides a clean, declarative way to manage entity lifecycles with explicit states and controlled transitions.

## Why Use State Machines?

State machines are useful when you need to:
- Track entities through well-defined lifecycles (e.g., user confirmation, order processing, document workflows)
- Enforce business rules about valid state transitions
- Separate authorization logic (who can transition) from validation logic (when transitions are allowed)
- Trigger side effects automatically when states change (e.g., send emails, schedule jobs)
- Maintain audit trails of state changes

## Example: User Confirmation Status

Playground includes a complete example implementation in the User model:

- **States:** `unconfirmed`, `confirmed`
- **Transitions:**
  - `unconfirmed → confirmed`: Email verification (via token or admin)
  - `confirmed → unconfirmed`: Admin revokes confirmation

See [`lib/playground/accounts/user_state_machine.ex`](../../lib/playground/accounts/user_state_machine.ex) for the complete implementation.

## Quick Start

### 1. Add Machinery to Your Schema

```elixir
defmodule Playground.MyContext.MyModel do
  use Ecto.Schema
  use Machinery,
    field: :status,
    states: Playground.MyContext.MyModelStateMachine.states(),
    transitions: Playground.MyContext.MyModelStateMachine.transitions()

  schema "my_models" do
    field :status, :string, default: "initial_state"
    # ... other fields
    timestamps()
  end
end
```

### 2. Create a State Machine Module

```elixir
defmodule Playground.MyContext.MyModelStateMachine do
  alias Playground.MyContext.MyModel
  alias Playground.Repo

  # Define states
  def states, do: ["draft", "published", "archived"]

  # Define valid transitions
  def transitions do
    %{
      "draft" => ["published"],
      "published" => ["archived"],
      "archived" => ["draft"]
    }
  end

  # Guard: Who can transition?
  def guard_transition(%MyModel{}, "published", _metadata) do
    :ok  # Anyone can publish
  end

  def guard_transition(%MyModel{}, "archived", %{actor: "admin:" <> _}) do
    :ok  # Only admins can archive
  end

  def guard_transition(%MyModel{}, _state, _metadata) do
    {:error, "Unauthorized"}
  end

  # Before: Validate before transition
  def before_transition(model, _next_state, _metadata) do
    {:ok, model}  # Add validation logic here
  end

  # After: Side effects after transition
  def after_transition(%MyModel{} = model, "published", _metadata) do
    # Send notification, schedule job, etc.
    model
  end

  def after_transition(model, _state, _metadata), do: model

  # Persist: Save to database
  def persist(%MyModel{} = model, next_state, _metadata) do
    changeset = Ecto.Changeset.change(model, %{status: next_state})

    case Repo.update(changeset) do
      {:ok, updated_model} -> updated_model
      {:error, changeset} ->
        raise "Failed to persist state: #{inspect(changeset.errors)}"
    end
  end
end
```

### 3. Create a Migration

```elixir
defmodule Playground.Repo.Migrations.AddStatusToMyModels do
  use Ecto.Migration

  def change do
    alter table(:my_models) do
      add :status, :string, default: "draft", null: false
    end

    create index(:my_models, [:status])
  end
end
```

### 4. Use in Your Context

```elixir
defmodule Playground.MyContext do
  alias Playground.MyContext.{MyModel, MyModelStateMachine}

  def publish_model(%MyModel{} = model, user) do
    case Machinery.transition_to(model, MyModelStateMachine, "published", %{
      actor: "user:#{user.id}"
    }) do
      {:ok, updated_model} -> {:ok, updated_model}
      {:error, reason} -> {:error, reason}
    end
  end

  def archive_model(%MyModel{} = model, admin_user) do
    case Machinery.transition_to(model, MyModelStateMachine, "archived", %{
      actor: "admin:#{admin_user.id}"
    }) do
      {:ok, updated_model} -> {:ok, updated_model}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## State Machine Components

### States

Define all possible states as a list of strings:

```elixir
def states, do: ["pending", "processing", "completed", "failed"]
```

### Transitions

Define which state transitions are allowed as a map:

```elixir
def transitions do
  %{
    "pending" => ["processing"],
    "processing" => ["completed", "failed"],
    "failed" => ["pending"]  # Allow retry
  }
end
```

### Guard Functions

Controls **WHO** can perform transitions (authorization):

```elixir
# Allow anyone
def guard_transition(%MyModel{}, "published", _metadata) do
  :ok
end

# Admin only
def guard_transition(%MyModel{}, "deleted", %{actor: "admin:" <> _}) do
  :ok
end

# Owner or admin
def guard_transition(%MyModel{user_id: user_id}, "edit", %{actor: actor}) do
  case actor do
    "user:" <> id when id == to_string(user_id) -> :ok
    "admin:" <> _ -> :ok
    _ -> {:error, "Only owner or admin can edit"}
  end
end

# Deny transition
def guard_transition(_model, _state, _metadata) do
  {:error, "Unauthorized transition"}
end
```

### Before Hooks

Validates business rules **BEFORE** the transition (validation):

```elixir
# Validate before publishing
def before_transition(%MyModel{} = model, "published", _metadata) do
  cond do
    is_nil(model.title) ->
      {:error, "Must have a title to publish"}

    not ready_for_publish?(model) ->
      {:error, "Not ready to publish"}

    true ->
      {:ok, model}
  end
end

# Allow all other transitions
def before_transition(model, _state, _metadata), do: {:ok, model}
```

### After Hooks

Triggers side effects **AFTER** successful transition:

```elixir
# Send email after publishing
def after_transition(%MyModel{} = model, "published", _metadata) do
  # Schedule background job
  %{model_id: model.id}
  |> Playground.Workers.NotificationWorker.new()
  |> Oban.insert()

  # Broadcast real-time update
  Phoenix.PubSub.broadcast(
    Playground.PubSub,
    "models",
    {:model_published, model.id}
  )

  model
end

def after_transition(model, _state, _metadata), do: model
```

### Persist Callback

Handles saving the state change to the database:

```elixir
def persist(%MyModel{} = model, next_state, metadata) do
  now = DateTime.utc_now() |> DateTime.truncate(:second)

  changeset =
    model
    |> Ecto.Changeset.change(%{
      status: next_state,
      last_transitioned_by: metadata[:actor],
      last_transitioned_at: now
    })

  case Repo.update(changeset) do
    {:ok, updated_model} -> updated_model
    {:error, changeset} ->
      raise "Failed to persist state: #{inspect(changeset.errors)}"
  end
end
```

## Integration Patterns

### With Oban (Background Jobs)

Use a system actor for background job transitions:

```elixir
def perform(%Oban.Job{args: %{"model_id" => id}}) do
  model = MyContext.get_model!(id)

  Machinery.transition_to(
    model,
    MyModelStateMachine,
    "processing",
    %{actor: "system:worker"}
  )

  # Do work...

  Machinery.transition_to(
    model,
    MyModelStateMachine,
    "completed",
    %{actor: "system:worker", result: "success"}
  )
end
```

### With Authorization

Check permissions in guard functions:

```elixir
def guard_transition(%MyModel{}, "publish", %{actor: "user:" <> id}) do
  user = Accounts.get_user!(id)

  if Authorization.can?(user, "models:publish") do
    :ok
  else
    {:error, "No permission to publish"}
  end
end
```

### With PubSub

Broadcast state changes for real-time updates:

```elixir
def after_transition(%MyModel{} = model, new_state, _metadata) do
  Phoenix.PubSub.broadcast(
    Playground.PubSub,
    "model:#{model.id}",
    {:state_changed, model.id, new_state}
  )

  model
end
```

### With Audit Trail

Track all state transitions in a separate table:

```elixir
def persist(%MyModel{} = model, next_state, metadata) do
  Ecto.Multi.new()
  |> Ecto.Multi.update(:model, Ecto.Changeset.change(model, %{status: next_state}))
  |> Ecto.Multi.insert(:audit, %StateTransition{
    model_id: model.id,
    from_state: model.status,
    to_state: next_state,
    actor: metadata[:actor],
    metadata: metadata,
    inserted_at: DateTime.utc_now()
  })
  |> Repo.transaction()
  |> case do
    {:ok, %{model: updated_model}} -> updated_model
    {:error, _, changeset, _} ->
      raise "Failed to persist: #{inspect(changeset.errors)}"
  end
end
```

## Testing

Test state machines thoroughly:

```elixir
defmodule Playground.MyContext.MyModelStateMachineTest do
  use Playground.DataCase

  alias Playground.MyContext.{MyModel, MyModelStateMachine}

  describe "state transitions" do
    test "allows draft -> published transition" do
      model = %MyModel{status: "draft"}

      {:ok, updated} = Machinery.transition_to(
        model,
        MyModelStateMachine,
        "published",
        %{}
      )

      assert updated.status == "published"
    end

    test "prevents unauthorized transitions" do
      model = %MyModel{status: "published"}

      result = Machinery.transition_to(
        model,
        MyModelStateMachine,
        "archived",
        %{actor: "user:123"}
      )

      assert {:error, "Unauthorized"} = result
    end
  end
end
```

## Best Practices

1. **Keep states simple** - Use clear, descriptive state names
2. **Document transitions** - Explain why each transition exists
3. **Test thoroughly** - Test all valid and invalid transitions
4. **Use metadata** - Pass context (actor, reason) in metadata
5. **Fail fast** - Validate early in guard and before hooks
6. **Side effects in after hooks** - Keep persist callback focused on database updates
7. **Use system actors** - Distinguish user actions from automated processes
8. **Index status field** - Add database index for efficient queries

## Common Patterns

### Linear Workflow

```elixir
def transitions do
  %{
    "step1" => ["step2"],
    "step2" => ["step3"],
    "step3" => ["complete"]
  }
end
```

### With Failure States

```elixir
def transitions do
  %{
    "pending" => ["processing"],
    "processing" => ["completed", "failed"],
    "failed" => ["pending"]  # Allow retry
  }
end
```

### With Cancel/Archive

```elixir
def transitions do
  %{
    "draft" => ["published", "archived"],
    "published" => ["archived"],
    "archived" => ["draft"]  # Allow restore
  }
end
```

### Approval Workflow

```elixir
def transitions do
  %{
    "submitted" => ["approved", "rejected"],
    "approved" => ["published"],
    "rejected" => ["submitted"]  # Allow resubmit
  }
end
```

## Further Reading

- [Machinery Documentation](https://hexdocs.pm/machinery)
- [User Confirmation Example](../../lib/playground/accounts/user_state_machine.ex)
- [Building State Machines in Elixir with Ecto](https://blog.appsignal.com/2020/07/14/building-state-machines-in-elixir-with-ecto.html)

# PhoenixAnalytics Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate self-hosted PhoenixAnalytics for tracking all user activity with admin-only dashboard access.

**Architecture:** Add PhoenixAnalytics dependency, configure with existing Playground.Repo, protect dashboard with Bodyguard policy requiring admin role, track all requests via endpoint plug positioned after static file serving.

**Tech Stack:** PhoenixAnalytics 0.4.x, Bodyguard (existing), Ecto/PostgreSQL (existing), Phoenix LiveView (existing)

---

## Task 1: Add PhoenixAnalytics Dependency

**Files:**
- Modify: `mix.exs:50-117` (deps function)

**Step 1: Add dependency to mix.exs**

In the `deps/0` function, add phoenix_analytics after the existing dependencies:

```elixir
# Analytics
{:phoenix_analytics, "~> 0.4"},
```

Place it after the `:error_tracker` dependency around line 105.

**Step 2: Fetch dependencies**

Run: `mix deps.get`
Expected: Downloads phoenix_analytics and reports "All dependencies are up to date"

**Step 3: Commit**

```bash
git add mix.exs mix.lock
git commit -m "deps: add phoenix_analytics ~> 0.4"
```

---

## Task 2: Create Analytics Table Migration

**Files:**
- Create: `priv/repo/migrations/20260101_create_analytics_table.exs`

**Step 1: Generate migration file**

Run: `mix ecto.gen.migration create_analytics_table`
Expected: Creates migration file with timestamp prefix

**Step 2: Implement migration with PhoenixAnalytics.Migration**

```elixir
defmodule Playground.Repo.Migrations.CreateAnalyticsTable do
  use Ecto.Migration

  def up do
    PhoenixAnalytics.Migration.up()
  end

  def down do
    PhoenixAnalytics.Migration.down()
  end
end
```

**Step 3: Run migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully, creates `analytics` table

**Step 4: Verify table created**

Run: `psql -h localhost -p 5555 -U postgres -d playground_dev -c "\d analytics"`
Expected: Shows table structure with columns for request data

**Step 5: Commit**

```bash
git add priv/repo/migrations/*_create_analytics_table.exs
git commit -m "migration: create analytics table for PhoenixAnalytics"
```

---

## Task 3: Add Analytics Indexes Migration

**Files:**
- Create: `priv/repo/migrations/20260101_add_analytics_indexes.exs`

**Step 1: Generate indexes migration**

Run: `mix ecto.gen.migration add_analytics_indexes`
Expected: Creates migration file

**Step 2: Implement indexes migration**

```elixir
defmodule Playground.Repo.Migrations.AddAnalyticsIndexes do
  use Ecto.Migration

  def up do
    PhoenixAnalytics.Migration.add_indexes()
  end

  def down do
    # Indexes will be dropped when table is dropped
    :ok
  end
end
```

**Step 3: Run migration**

Run: `mix ecto.migrate`
Expected: Creates indexes on analytics table

**Step 4: Commit**

```bash
git add priv/repo/migrations/*_add_analytics_indexes.exs
git commit -m "migration: add indexes to analytics table"
```

---

## Task 4: Configure PhoenixAnalytics

**Files:**
- Modify: `config/dev.exs:1-end`
- Modify: `config/runtime.exs:1-end`

**Step 1: Add configuration to config/dev.exs**

Add after the `:playground, :environment, :dev` line (end of file):

```elixir
# PhoenixAnalytics configuration
config :phoenix_analytics,
  repo: Playground.Repo,
  cache_ttl: :timer.minutes(5)
```

**Step 2: Add configuration to config/runtime.exs**

Find the production config section and add:

```elixir
# PhoenixAnalytics configuration
config :phoenix_analytics,
  repo: Playground.Repo,
  cache_ttl: :timer.minutes(10)
```

Use longer TTL (10 min) in production for better performance.

**Step 3: Commit**

```bash
git add config/dev.exs config/runtime.exs
git commit -m "config: add PhoenixAnalytics settings for dev and prod"
```

---

## Task 5: Create Bodyguard Policy for Analytics

**Files:**
- Create: `lib/playground/analytics/policy.ex`

**Step 1: Create analytics directory**

Run: `mkdir -p lib/playground/analytics`
Expected: Directory created

**Step 2: Write Bodyguard policy**

```elixir
defmodule Playground.Analytics.Policy do
  @moduledoc """
  Authorization policy for PhoenixAnalytics dashboard access.
  """
  @behaviour Bodyguard.Policy

  @doc """
  Only admin users can view analytics dashboard.
  """
  def authorize(:view_analytics, %{role: :admin}, _params), do: :ok
  def authorize(:view_analytics, _user, _params), do: :error
end
```

**Step 3: Commit**

```bash
git add lib/playground/analytics/policy.ex
git commit -m "feat(analytics): add Bodyguard policy for admin-only access"
```

---

## Task 6: Add Authorization Helper to UserAuth

**Files:**
- Modify: `lib/playground_web/user_auth.ex:1-end`

**Step 1: Find the end of the module**

Locate the last function in `PlaygroundWeb.UserAuth` module.

**Step 2: Add authorize_analytics plug**

Add this private function before the final `end`:

```elixir
@doc """
Authorizes access to the analytics dashboard.
Redirects non-admin users to home page with error message.
"""
def authorize_analytics(conn, _opts) do
  case Bodyguard.permit(Playground.Analytics.Policy, :view_analytics, conn.assigns.current_user, %{}) do
    :ok ->
      conn

    :error ->
      conn
      |> put_flash(:error, "You are not authorized to view analytics")
      |> redirect(to: ~p"/")
      |> halt()
  end
end
```

**Step 3: Compile and verify**

Run: `mix compile`
Expected: No errors, successful compilation

**Step 4: Commit**

```bash
git add lib/playground_web/user_auth.ex
git commit -m "feat(auth): add analytics authorization helper"
```

---

## Task 7: Add Analytics Pipeline and Mount Dashboard

**Files:**
- Modify: `lib/playground_web/router.ex:1-end`

**Step 7.1: Add import for phoenix_analytics_dashboard**

After the existing imports around line 117-119, add:

```elixir
import PhoenixAnalytics.Router
```

**Step 7.2: Add analytics_auth pipeline**

After the `:api` pipeline (around line 18), add:

```elixir
pipeline :analytics_auth do
  plug :require_authenticated_user
  plug :authorize_analytics
end
```

**Step 7.3: Mount analytics dashboard**

In the `scope "/admin"` block (around line 119), before the LiveDashboard mount, add:

```elixir
# PhoenixAnalytics Dashboard - admin only
pipe_through :analytics_auth
phoenix_analytics_dashboard "/analytics"
```

**Step 7.4: Verify routing**

Run: `mix phx.routes | grep analytics`
Expected: Shows route for `/admin/analytics`

**Step 7.5: Commit**

```bash
git add lib/playground_web/router.ex
git commit -m "feat(router): mount PhoenixAnalytics dashboard with auth"
```

---

## Task 8: Add Request Tracking Plug to Endpoint

**Files:**
- Modify: `lib/playground_web/endpoint.ex:1-end`

**Step 1: Read endpoint file to find Plug.Static location**

Run: `grep -n "Plug.Static" lib/playground_web/endpoint.ex`
Expected: Shows line number of Plug.Static

**Step 2: Add PhoenixAnalytics.Plugs.RequestTracker**

Add **after** `Plug.Static` but **before** the router plug:

```elixir
# Track analytics (after static files, before router)
plug PhoenixAnalytics.Plugs.RequestTracker
```

Typical position is after all Plug.Static declarations and before `plug PlaygroundWeb.Router`.

**Step 3: Verify endpoint compiles**

Run: `mix compile`
Expected: Compiles without errors

**Step 4: Commit**

```bash
git add lib/playground_web/endpoint.ex
git commit -m "feat(endpoint): add PhoenixAnalytics request tracker"
```

---

## Task 9: Add Analytics Link to Admin Dashboard

**Files:**
- Modify: `lib/playground_web/live/admin_dashboard_live/index.ex:1-end`

**Step 1: Locate the render function**

Find the HEEx template section in `index.ex`.

**Step 2: Add analytics tile**

Look for existing admin tiles (like API Health Check, Backups, etc.) and add a new tile:

```elixir
<.link navigate={~p"/admin/analytics"} class="group">
  <.dashboard_tile
    icon="hero-chart-bar"
    title="Analytics"
    description="View application usage analytics and metrics"
  />
</.link>
```

Place it in the "Monitoring & Logs" or "System Tools" section, or create a new section if appropriate.

**Step 3: Commit**

```bash
git add lib/playground_web/live/admin_dashboard_live/index.ex
git commit -m "feat(admin): add Analytics link to admin dashboard"
```

---

## Task 10: Write Access Control Tests

**Files:**
- Create: `test/playground_web/controllers/analytics_access_test.exs`

**Step 10.1: Write failing test for admin access**

```elixir
defmodule PlaygroundWeb.AnalyticsAccessTest do
  use PlaygroundWeb.ConnCase, async: true

  import Playground.AccountsFixtures

  describe "GET /admin/analytics" do
    test "redirects unauthenticated users to login", %{conn: conn} do
      conn = get(conn, ~p"/admin/analytics")
      assert redirected_to(conn) =~ "/users/log_in"
    end

    test "redirects non-admin authenticated users to home with error", %{conn: conn} do
      user = user_fixture(%{role: :user})
      conn = conn |> log_in_user(user) |> get(~p"/admin/analytics")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not authorized"
    end

    test "allows admin users to access analytics dashboard", %{conn: conn} do
      admin = user_fixture(%{role: :admin})
      conn = conn |> log_in_user(admin) |> get(~p"/admin/analytics")

      assert html_response(conn, 200)
      assert conn.resp_body =~ "Analytics"
    end
  end
end
```

**Step 10.2: Run tests to verify they fail**

Run: `mix test test/playground_web/controllers/analytics_access_test.exs`
Expected: Tests may fail if dashboard route needs specific setup

**Step 10.3: Fix any test failures**

Adjust tests based on actual PhoenixAnalytics dashboard response.

**Step 10.4: Run tests to verify they pass**

Run: `mix test test/playground_web/controllers/analytics_access_test.exs`
Expected: All tests pass

**Step 10.5: Commit**

```bash
git add test/playground_web/controllers/analytics_access_test.exs
git commit -m "test(analytics): add access control tests"
```

---

## Task 11: Manual Verification and Testing

**Files:**
- None (manual testing)

**Step 11.1: Start the development server**

Run: `mix phx.server`
Expected: Server starts without errors on port 4000

**Step 11.2: Test unauthenticated access**

1. Open browser to `http://localhost:4000/admin/analytics`
2. Expected: Redirected to login page

**Step 11.3: Test non-admin user access**

1. Log in as regular user (role: :user)
2. Navigate to `/admin/analytics`
3. Expected: Redirected to home with error message "You are not authorized to view analytics"

**Step 11.4: Test admin user access**

1. Log in as admin user (role: :admin)
2. Navigate to `/admin/analytics`
3. Expected: Analytics dashboard loads successfully

**Step 11.5: Test request tracking**

1. While logged in as admin, browse several pages (/dashboard, /admin, etc.)
2. Return to `/admin/analytics`
3. Expected: See tracked requests appearing in dashboard

**Step 11.6: Test keyboard shortcuts**

1. On analytics dashboard, press `t` key
2. Expected: Filters to "Today"
3. Press `w` key
4. Expected: Filters to "Last week"

**Step 11.7: Test dark mode**

1. Toggle dark mode in dashboard
2. Expected: Dashboard theme changes

**Step 11.8: Document any issues**

If issues found, create tasks to fix them.

---

## Task 12: Run Full Test Suite

**Files:**
- None (testing)

**Step 12.1: Run all tests**

Run: `mix test`
Expected: All tests pass

**Step 12.2: Fix any failures**

If tests fail, investigate and fix issues.

**Step 12.3: Run tests again**

Run: `mix test`
Expected: All tests pass

**Step 12.4: Final commit**

```bash
git add -A
git commit -m "test: verify all tests pass with PhoenixAnalytics"
```

---

## Task 13: Final Cleanup and Documentation

**Files:**
- Modify: `README.md` (if exists)

**Step 13.1: Update README with analytics information**

Add section about analytics dashboard:

```markdown
## Analytics

This application includes PhoenixAnalytics for tracking user behavior and application performance.

### Access
- URL: `/admin/analytics`
- Access: Admin users only
- Features: Request tracking, date filtering, dark mode

### Keyboard Shortcuts
- `t` - Today
- `w` - Last week
- `m` - Last 30 days
- `y` - Last 12 months
- `a` - All time
```

**Step 13.2: Commit documentation**

```bash
git add README.md
git commit -m "docs: add PhoenixAnalytics information to README"
```

---

## Rollback Plan

If integration needs to be removed:

1. Remove plug from `lib/playground_web/endpoint.ex`
2. Remove route from `lib/playground_web/router.ex`
3. Run: `mix ecto.rollback --step 2` (removes both migrations)
4. Remove dependency from `mix.exs`
5. Remove configuration from config files
6. Remove policy file
7. Remove authorization helper
8. Run: `mix deps.clean phoenix_analytics --unlock`

---

## Success Criteria

- [ ] Server starts without errors
- [ ] Unauthenticated users cannot access `/admin/analytics`
- [ ] Non-admin users are redirected with error message
- [ ] Admin users can access analytics dashboard
- [ ] Requests are tracked and visible in dashboard
- [ ] Keyboard shortcuts work (t, w, m, etc.)
- [ ] Dark mode toggle works
- [ ] All tests pass
- [ ] Analytics link appears in admin dashboard

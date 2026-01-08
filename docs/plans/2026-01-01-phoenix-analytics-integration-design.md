# PhoenixAnalytics Integration Design

**Date:** 2026-01-01
**Status:** Approved

## Overview

Integrate PhoenixAnalytics into the Playground application to provide self-hosted, privacy-focused analytics tracking for all user activity with admin-only dashboard access.

## Goals

- Track all user activity (authenticated and anonymous users)
- Provide admin-only access to analytics dashboard via Bodyguard authorization
- Use existing database infrastructure (Playground.Repo)
- Minimal performance overhead
- Self-hosted with no external dependencies

## Architecture

### 1. Installation & Configuration

**Dependencies:**
- Add `{:phoenix_analytics, "~> 0.4"}` to mix.exs
- All required dependencies already present (Cachex, LiveView, Ecto)

**Database:**
- Create analytics table via `PhoenixAnalytics.Migration.up()`
- Add PostgreSQL indexes via `PhoenixAnalytics.Migration.add_indexes()`
- Uses existing `Playground.Repo`

**Configuration:**
```elixir
# config/dev.exs and config/runtime.exs
config :phoenix_analytics,
  repo: Playground.Repo,
  cache_ttl: :timer.minutes(5)
```

**Rationale:**
- Leverages existing infrastructure
- 5-minute cache TTL balances freshness with performance
- PostgreSQL indexes optimize analytics query performance

### 2. Authorization & Dashboard Access

**Bodyguard Policy:**
```elixir
defmodule Playground.Analytics.Policy do
  @behaviour Bodyguard.Policy

  def authorize(:view_analytics, %{role: :admin}, _params), do: :ok
  def authorize(:view_analytics, _user, _params), do: :error
end
```

**Router Integration:**
```elixir
# New pipeline for analytics authorization
pipeline :analytics_auth do
  plug :require_authenticated_user
  plug :authorize_analytics
end

# Mount dashboard
scope "/" do
  pipe_through [:browser, :analytics_auth]
  phoenix_analytics_dashboard "/analytics"
end
```

**Authorization Helper:**
```elixir
# In lib/playground_web/user_auth.ex
defp authorize_analytics(conn, _opts) do
  case Bodyguard.permit(Playground.Analytics.Policy, :view_analytics, conn.assigns.current_user, %{}) do
    :ok -> conn
    :error ->
      conn
      |> put_flash(:error, "You are not authorized to view analytics")
      |> redirect(to: "/")
      |> halt()
  end
end
```

**Rationale:**
- Integrates with existing Bodyguard authorization system
- Follows Phoenix pipeline conventions
- Secure by default (unauthorized users redirected)
- Easy to extend with additional roles or conditions

### 3. Request Tracking

**Endpoint Configuration:**
Add tracking plug in `lib/playground_web/endpoint.ex`:

```elixir
# After Plug.Static (don't track static assets)
plug Plug.Static, ...

# Analytics tracking
plug PhoenixAnalytics.Plugs.RequestTracker

# Before router (capture all requests including 404s)
plug PlaygroundWeb.Router
```

**Performance:**
- Asynchronous tracking (<1ms overhead per request)
- Separate analytics table (no lock contention)
- Cache-based aggregations (configurable TTL)

**Tracked Data:**
- HTTP method, path, status code
- Timestamp
- User agent, referrer
- Response timing

**Rationale:**
- Positioned after static file serving (don't track assets)
- Positioned before router (capture all route-level activity)
- Minimal performance impact on request processing

### 4. Admin Dashboard Integration

**Navigation Link:**
Add analytics link to admin dashboard navigation (specific location TBD during implementation).

### 5. Testing & Validation

**Manual Verification:**
1. Server starts without errors
2. `/analytics` accessible by admin users
3. Non-admin users redirected with error message
4. Request tracking appears in dashboard
5. Date filtering shortcuts work (t, w, m, etc.)
6. Theme toggles function correctly

**Automated Tests:**
Create `test/playground_web/controllers/analytics_access_test.exs`:
- Admin users can access dashboard
- Non-admin users are redirected
- Unauthenticated users hit auth wall

**Rollback Plan:**
- Migration has `down()` function for clean removal
- Remove plug from endpoint
- Remove dependency

## Implementation Checklist

- [ ] Add dependency to mix.exs
- [ ] Run `mix deps.get`
- [ ] Create analytics migration
- [ ] Create indexes migration
- [ ] Run migrations
- [ ] Add configuration to config files
- [ ] Create Bodyguard policy
- [ ] Add authorization helper to user_auth.ex
- [ ] Add router pipeline and mount dashboard
- [ ] Add plug to endpoint
- [ ] Add link to admin dashboard navigation
- [ ] Create access control tests
- [ ] Restart server and verify
- [ ] Test with admin and non-admin users

## Future Considerations

- Monitor cache hit rates and adjust TTL if needed
- Explore the 12 color themes
- Consider custom dashboard views for specific metrics
- Evaluate separating to dedicated analytics database if traffic grows significantly

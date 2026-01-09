# Playground

Phoenix starter kit with auth, authorization, AI chat, background jobs, and admin dashboard.

## Quick Start

### With Doppler (Recommended - Secrets Management)

```bash
# 1. Install Doppler CLI
brew install dopplerhq/cli/doppler

# 2. Authenticate
doppler login

# 3. Set up project (first time only)
doppler setup
# Select: pjx-rag
# Select environment: dev

# 4. Install dependencies
doppler run -- mix deps.get

# 5. Set up database
doppler run -- mix ecto.create
doppler run -- mix ecto.migrate
doppler run -- mix run priv/repo/seeds.exs

# 6. Start server with secrets auto-injected
./bin/dev
```

**📚 See [docs/DOPPLER_SETUP.md](docs/DOPPLER_SETUP.md) for detailed Doppler documentation**

### Without Doppler (Local Development)

```bash
# Install dependencies
mix setup

# Configure environment
cp .env.example .env
# Edit .env with your values

# Load environment and start server
source .env
mix phx.server
```

Visit [localhost:4000](http://localhost:4000)

## Secrets Management

This project uses **Doppler** for secure secrets management. All API keys and sensitive config are stored in Doppler and injected at runtime.

**Benefits:**
- 🔐 Never commit secrets to git
- 🔄 Instant secret updates across team
- 🌍 Separate secrets for dev/staging/production
- 📊 Audit trail for all secret access

**Quick commands:**
```bash
./bin/dev        # Start server with Doppler
./bin/console    # IEx console with Doppler
./bin/test       # Run tests with Doppler
```

See [docs/DOPPLER_SETUP.md](docs/DOPPLER_SETUP.md) for full setup guide.

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

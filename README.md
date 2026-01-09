# Playground

Phoenix starter kit with authentication, authorization, AI chat, background jobs, and admin dashboard.

## Prerequisites

- Elixir 1.17+ and Erlang/OTP 27+
- PostgreSQL 16+ (or use Neon - already configured)
- Node.js 18+ (for asset compilation)
- [Doppler CLI](https://docs.doppler.com/docs/install-cli) for secrets management

## Quick Start

### 1. Install Doppler CLI

```bash
brew install dopplerhq/cli/doppler
```

### 2. Authenticate with Doppler

```bash
doppler login
```

### 3. Clone and Set Up Project

```bash
cd /Users/giovanniorlando/pjx-rag/playground

# Link to Doppler project (first time only)
doppler setup
# Select: pjx-rag
# Select environment: dev
```

### 4. Install Dependencies

```bash
mix deps.get
npm install --prefix assets
```

### 5. Set Up Database

The database URL is already configured in Doppler (Neon PostgreSQL).

```bash
# Run migrations (requires DATABASE_URL from Doppler)
doppler run -- mix ecto.migrate

# Seed database with admin user and initial data
doppler run -- mix run priv/repo/seeds.exs
```

### 6. Start Development Server

```bash
./bin/dev
```

Visit [http://localhost:4000](http://localhost:4000)

**Default admin credentials (from seeds):**
- Email: `admin@example.com`
- Password: `password123`

## Development Commands

Convenience scripts that automatically load secrets from Doppler:

```bash
./bin/dev        # Start Phoenix server
./bin/console    # Open IEx console
./bin/test       # Run tests
```

Or prefix any command that needs secrets with Doppler:

```bash
doppler run -- mix ecto.migrate
doppler run -- mix phx.server
# etc.
```

## Secrets Management

This project uses [Doppler](https://www.doppler.com/) for secure secrets management. All API keys and configuration are stored in Doppler and injected at runtime—never committed to git.

**View all secrets:**
```bash
doppler secrets
```

**Set a new secret:**
```bash
doppler secrets set MY_SECRET="value"
```

**📚 Full documentation:** [docs/DOPPLER_SETUP.md](docs/DOPPLER_SETUP.md)

## Project Structure

```
lib/
├── playground/              # Business logic
│   ├── accounts/           # User authentication
│   ├── ai/                 # AI chat system
│   ├── authorization.ex    # Authorization rules
│   ├── services/           # External API clients
│   └── workers/            # Background jobs (Oban)
├── playground_web/         # Web interface
│   ├── live/              # LiveView pages
│   ├── components/        # Reusable UI components
│   └── controllers/       # HTTP controllers
config/                     # Configuration files
priv/repo/migrations/       # Database migrations
assets/                     # Frontend assets
docs/                       # Documentation
```

## Features

- 🔐 **Authentication** - User registration, login, password reset
- 👮 **Authorization** - Role-based access control with Authorizir
- 🤖 **AI Chat** - Streaming chat with OpenRouter integration
- 📊 **Admin Dashboard** - User management, roles, permissions, analytics
- 🎨 **Theming** - Multiple built-in themes with Fluxon UI
- 📧 **Email** - Transactional emails with Resend (optional)
- 💾 **Background Jobs** - Async processing with Oban
- 📈 **Analytics** - Built-in request tracking with PhoenixAnalytics
- 🔍 **API Logging** - Comprehensive external API request logging

## Tech Stack

- **Framework:** Phoenix 1.7 with LiveView
- **Database:** PostgreSQL (Neon)
- **UI:** Fluxon component library
- **Background Jobs:** Oban
- **Authentication:** Bcrypt
- **Authorization:** Authorizir + Bodyguard
- **AI:** OpenRouter (LLM streaming)
- **Secrets:** Doppler
- **Testing:** ExUnit

## Deployment

This project is configured for deployment on [Fly.io](https://fly.io). See deployment documentation for details.

## Documentation

- [Doppler Setup Guide](docs/DOPPLER_SETUP.md) - Secrets management
- [State Machines Guide](docs/guides/state-machines.md) - Using Machinery for workflows

## Support

For issues or questions, check the admin dashboard or review the documentation in `docs/`.

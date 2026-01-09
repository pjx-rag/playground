# Doppler Secrets Management

This project uses [Doppler](https://www.doppler.com/) for secure secrets management. All sensitive configuration (API keys, database credentials, etc.) is stored in Doppler and injected at runtime.

## Why Doppler?

- 🔐 **Never commit secrets** - Secrets stay in Doppler's secure vault
- 🔄 **Instant sync** - Update secrets in Doppler, no code changes needed
- 👥 **Team collaboration** - Secure secret sharing across your team
- 🌍 **Multi-environment** - Separate secrets for dev, staging, production
- 📊 **Audit trail** - Track who accessed/changed secrets and when

## Quick Start

### 1. Install Doppler CLI

```bash
brew install dopplerhq/cli/doppler
```

### 2. Authenticate

```bash
doppler login
```

### 3. Set up project

The project is already configured via `doppler.yaml`:

```bash
cd /Users/giovanniorlando/pjx-rag/playground
doppler setup
# Select: pjx-rag
# Select environment: dev (or staging/production)
```

### 4. Run your app

Use the provided scripts that automatically inject Doppler secrets:

```bash
# Start development server
./bin/dev

# Open IEx console
./bin/console

# Run tests
./bin/test
```

Or run any command with Doppler:

```bash
doppler run -- mix deps.get
doppler run -- mix ecto.create
doppler run -- mix ecto.migrate
doppler run -- mix run priv/repo/seeds.exs
```

## Current Secrets

The following secrets are currently configured in Doppler:

### Development Environment (dev)

| Secret | Description | Status |
|--------|-------------|--------|
| `DATABASE_URL` | Neon PostgreSQL connection string | ✅ Set |
| `OPENROUTER_API_KEY` | OpenRouter API key for AI chat | ✅ Set |
| `SECRET_KEY_BASE` | Phoenix secret for signing/encryption | ✅ Set |
| `PHX_HOST` | Phoenix host (localhost for dev) | ✅ Set |
| `PORT` | Phoenix port (4000 for dev) | ✅ Set |
| `PHX_SERVER` | Auto-start server | ✅ Set |
| `POOL_SIZE` | Database connection pool size | ✅ Set |
| `RESEND_API_KEY` | Email API key (Resend) | ⏳ TODO |
| `FROM_EMAIL` | Email sender address | ⏳ TODO |
| `TIGRIS_ACCESS_KEY_ID` | S3-compatible storage | ⏳ TODO |
| `TIGRIS_SECRET_ACCESS_KEY` | S3-compatible storage | ⏳ TODO |
| `TIGRIS_BUCKET_NAME` | S3 bucket name | ⏳ TODO |

## Managing Secrets

### View all secrets

```bash
doppler secrets
```

### Set a secret

```bash
doppler secrets set API_KEY="your-secret-key"
```

### Delete a secret

```bash
doppler secrets delete API_KEY
```

### Download secrets to .env (local backup only)

```bash
doppler secrets download --no-file --format env > .env
```

**⚠️ Warning:** Don't commit the generated `.env` file!

## Multi-Environment Setup

### Create environments

```bash
# Development (already set up)
doppler configs create dev

# Staging
doppler configs create staging

# Production
doppler configs create production
```

### Switch environments

```bash
doppler setup
# Select different config
```

Or specify explicitly:

```bash
doppler run --config staging -- mix phx.server
doppler run --config production -- mix ecto.migrate
```

## CI/CD Integration

For automated deployments, use Service Tokens:

### 1. Create a Service Token

```bash
doppler configs tokens create ci-token --config production
```

### 2. Set in CI environment

```bash
export DOPPLER_TOKEN="dp.st.xxxxx"
```

### 3. Use in CI scripts

```bash
# Install CLI
curl -Ls https://cli.doppler.com/install.sh | sh

# Run with token
doppler run -- mix release
```

## Production Deployment

### Fly.io Example

```bash
# Set Doppler token as Fly secret
fly secrets set DOPPLER_TOKEN="dp.st.xxxxx"

# Update Dockerfile to use Doppler
# Add to Dockerfile:
RUN curl -Ls https://cli.doppler.com/install.sh | sh
CMD ["doppler", "run", "--", "bin/server"]
```

### Using runtime.exs with Doppler

Your `config/runtime.exs` already uses `System.get_env()`, which works perfectly with Doppler:

```elixir
# This reads from Doppler-injected environment
config :playground, :openrouter,
  api_key: System.get_env("OPENROUTER_API_KEY")
```

No code changes needed! Doppler injects secrets as environment variables.

## Troubleshooting

### "Not authenticated" error

```bash
doppler login
```

### "No project configured" error

```bash
doppler setup
```

### Secrets not loading

Check you're in the right directory:

```bash
cd /Users/giovanniorlando/pjx-rag/playground
doppler configure get
```

### See what secrets would be injected

```bash
doppler run --command="env | grep -E 'DATABASE|API_KEY|SECRET'"
```

## Best Practices

1. ✅ **Never commit secrets** - Always use Doppler
2. ✅ **Use different secrets per environment** - Dev/staging/prod separation
3. ✅ **Rotate secrets regularly** - Update in Doppler, no code changes needed
4. ✅ **Use Service Tokens for CI** - Not your personal login
5. ✅ **Grant minimal access** - Team members only get environments they need
6. ✅ **Enable audit logging** - Track all secret access in Doppler dashboard

## Resources

- [Doppler Documentation](https://docs.doppler.com/)
- [Doppler Elixir/Ecto Guide](https://docs.doppler.com/docs/ecto)
- [Doppler CLI Reference](https://docs.doppler.com/docs/cli)
- [Doppler Integrations](https://www.doppler.com/integrations)

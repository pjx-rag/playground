# Playground

Phoenix starter kit with auth, authorization, background jobs, and admin dashboard.

## Development Setup

### Prerequisites

1. **Doppler CLI**
   ```bash
   brew install dopplerhq/cli/doppler
   doppler login
   ```

2. **Neon CLI**
   ```bash
   npm install -g neonctl
   neon auth
   ```

### Setup Steps

1. **Install dependencies**
   ```bash
   mix setup
   ```

2. **Set up Doppler project**
   ```bash
   doppler setup
   # Select your project
   ```

3. **Create your personal dev config**

   Each developer creates their own branch config under dev:
   ```bash
   # Create your personal config (e.g., dev_alice, dev_bob)
   doppler configs create dev_yourname --environment dev

   # Switch to your config
   doppler setup --config dev_yourname
   ```

4. **Create your personal Neon dev branch**
   ```bash
   # Create a branch named dev-yourname
   neon branches create --name dev-yourname

   # Get the connection string and save it
   neon connection-string dev-yourname
   ```

5. **Configure your secrets**
   ```bash
   # Set your Neon branch connection string
   doppler secrets set DATABASE_URL --config dev_yourname
   ```

6. **Start the server**
   ```bash
   doppler run -- mix phx.server
   ```

Visit localhost:4000

## Deployment

Infrastructure is ready:
- Neon database branches: `staging` and `prod`
- Doppler configs: `stg` and `prd` (with all required secrets)
- Fly.io apps: `playground-staging` and `playground-pjx`

### Deploying Updates

The Fluxon license key is needed at build time, so we use Doppler to inject it:

```bash
# Staging
doppler run --config stg --command='fly deploy -a playground-staging --build-arg FLUXON_LICENSE_KEY=$FLUXON_LICENSE_KEY'

# Production
doppler run --config prd --command='fly deploy -a playground-pjx --build-arg FLUXON_LICENSE_KEY=$FLUXON_LICENSE_KEY'
```

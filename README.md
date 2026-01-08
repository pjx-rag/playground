# Playground

Phoenix starter kit with auth, authorization, background jobs, and admin dashboard.

## Setup

```bash
# Install dependencies
mix setup

# Configure environment
cp .env.example .env
# Edit .env with your values (optional for local dev)

# Load environment and start server
source .env
mix phx.server
```

Visit [localhost:4000](http://localhost:4000)

## Environment Variables

See `.env.example` for all options. For local development, defaults work out of the box.

For full functionality (backups, emails), set:
- `TIGRIS_ACCESS_KEY_ID` / `TIGRIS_SECRET_ACCESS_KEY` - Object storage
- `RESEND_API_KEY` - Email service

## direnv (optional)

Auto-load `.env` when entering the directory:

```bash
brew install direnv
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
direnv allow
```

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

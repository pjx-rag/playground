# Theme Admin Tool Design

## Overview

Admin-only theme customization that applies site-wide. Users can toggle between light/dark modes in their settings (default: "system" which respects OS preference).

## Data Model

### Theme Schema (`Playground.Settings.Theme`)

```elixir
field :name, :string           # "Fluxon Light", "Pastel", "My Custom Theme"
field :slug, :string           # "fluxon-light", "pastel", unique identifier
field :mode, :string           # "light" or "dark" - which color scheme this theme is for
field :is_system, :boolean     # true = seeded default, can't be deleted
field :tokens, :map            # The ~10 color tokens as a JSON map
```

### Token Structure

Based on Fluxon's preview showing ~10 colors:

```elixir
%{
  "primary" => "#000000",            # Primary button/brand color
  "primary_foreground" => "#FFFFFF", # Text on primary
  "background" => "#FFFFFF",         # Page background
  "surface" => "#FFFFFF",            # Card/panel background
  "foreground" => "#374151",         # Main text color
  "border" => "#E5E7EB",             # Border color
  "danger" => "#DC2626",             # Red - errors/destructive
  "success" => "#16A34A",            # Green - success states
  "warning" => "#F59E0B",            # Amber - warnings
  "info" => "#2563EB"                # Blue - informational
}
```

### Site Settings (`Playground.Settings.SiteSettings` - singleton)

```elixir
field :light_theme_id, :binary_id   # FK to Theme (mode: "light")
field :dark_theme_id, :binary_id    # FK to Theme (mode: "dark")
```

### User Preference (add to `User` schema)

```elixir
field :color_mode, :string, default: "system"  # "system" | "light" | "dark"
```

## Admin UI

### Route: `/admin/themes`

### Page Layout

- **Header**: "Themes" title with [+ Create Theme] button
- **Active Themes Section**: Two dropdowns to select the active light and dark themes
- **Available Themes Grid**: Theme cards showing preview swatches (like Fluxon's design)

### Theme Card Preview

Each card displays:
- Theme name
- Background color with primary button swatch
- Grid of 6 status colors (foreground variants + danger/success/warning/info)
- Edit button (opens modal with color pickers)
- Delete button (custom themes only)

### Behavior

- Clicking a theme card instantly applies it (page becomes the preview)
- System themes can be edited but have "Reset to Default" option
- Active Theme dropdowns filter by mode (light shows only light-mode themes)

## Theme Application Mechanism

### CSS Variable Injection

1. **Server-side rendering**: `root.html.heex` injects active theme CSS variables inline in a `<style>` tag to prevent FOUC

2. **ThemeManager Hook**: JavaScript hook that:
   - Reads user's `color_mode` preference ("system", "light", "dark")
   - Listens to `prefers-color-scheme` media query changes
   - Fetches theme tokens via `/api/theme/:mode` endpoint
   - Applies tokens to `:root` as CSS variables

3. **Live Preview**: Admin theme changes push events to hook for instant application

### API Endpoint

`GET /api/theme/:mode` - Returns active theme tokens for light or dark mode as JSON. Public endpoint (no auth), returns CSS variables.

## Seeded Themes

Seed the following Fluxon default themes:

1. **Fluxon Light** (mode: "light", is_system: true)
2. **Fluxon Dark** (mode: "dark", is_system: true)
3. **Pastel** (mode: "light", is_system: true)
4. **Cappuccino** (mode: "light", is_system: true)

## User Settings Addition

Add color mode selector to user settings page with three options:
- System (default) - follows OS preference
- Light - always use light theme
- Dark - always use dark theme

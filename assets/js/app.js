// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import LiveSelect from "../../deps/live_select/priv/static/live_select.min.js"

// Import Fluxon UI components
import { Hooks as FluxonHooks, DOM as FluxonDOM } from 'fluxon'

// LiveView Hooks
let Hooks = Object.assign({}, LiveSelect, FluxonHooks)

// Sidebar collapse hook - pushes toggle event to server
Hooks.SidebarCollapse = {
  mounted() {
    this.el.addEventListener('click', (e) => {
      if (e.target.closest('[data-collapse-trigger]')) {
        // Add transitioning attribute to enable animation only during toggle
        const layout = this.el.closest('.group\\/layout')
        if (layout) {
          layout.dataset.sidebarTransitioning = ''
          // Remove after transition completes (matches duration-200 = 200ms)
          setTimeout(() => {
            delete layout.dataset.sidebarTransitioning
          }, 200)
        }
        this.pushEvent('toggle_sidebar', {})
      }
    })
  }
}

// Auto-focus hook - refocuses input after LiveView updates
Hooks.AutoFocus = {
  mounted() {
    this.el.focus()
  },
  updated() {
    // Refocus after the input value is cleared (message sent)
    if (!this.el.disabled && this.el.value === '') {
      this.el.focus()
    }
  }
}

// Chat scroll hook - auto-scroll and scroll-to-bottom button
Hooks.ChatScroll = {
  mounted() {
    this.isNearBottom = true
    this.scrollButton = document.getElementById('scroll-to-bottom')

    // Scroll to bottom on initial load
    this.scrollToBottom()

    // Track scroll position
    this.el.addEventListener('scroll', () => {
      this.checkScrollPosition()
    })

    // Listen for scroll-to-bottom event
    this.el.addEventListener('scroll-to-bottom', () => {
      this.scrollToBottom()
    })
  },

  updated() {
    // Auto-scroll if user was near bottom before update
    if (this.isNearBottom) {
      this.scrollToBottom()
    } else {
      // Show the scroll button if there's new content and user scrolled up
      this.showScrollButton()
    }
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
    this.hideScrollButton()
    this.isNearBottom = true
  },

  checkScrollPosition() {
    const threshold = 100 // pixels from bottom
    const distanceFromBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight
    this.isNearBottom = distanceFromBottom < threshold

    if (this.isNearBottom) {
      this.hideScrollButton()
    }
  },

  showScrollButton() {
    if (this.scrollButton) {
      this.scrollButton.classList.remove('hidden')
    }
  },

  hideScrollButton() {
    if (this.scrollButton) {
      this.scrollButton.classList.add('hidden')
    }
  }
}

// Copy to clipboard hook
Hooks.Clipboard = {
  mounted() {
    this.el.addEventListener('click', () => {
      const text = this.el.dataset.clipboardText

      if (text && navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(() => {
          this.showFeedback()
        }).catch(err => {
          console.error('Failed to copy: ', err)
          this.fallbackCopy(text)
        })
      } else if (text) {
        this.fallbackCopy(text)
      }
    })
  },

  fallbackCopy(text) {
    const textArea = document.createElement('textarea')
    textArea.value = text
    textArea.style.position = 'fixed'
    textArea.style.left = '-999999px'
    textArea.style.top = '-999999px'
    document.body.appendChild(textArea)
    textArea.focus()
    textArea.select()

    try {
      document.execCommand('copy')
      this.showFeedback()
    } catch (err) {
      console.error('Fallback copy failed: ', err)
    } finally {
      document.body.removeChild(textArea)
    }
  },

  showFeedback() {
    this.pushEvent("copied_to_clipboard", { text: this.el.dataset.clipboardText })
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
  dom: {
    onBeforeElUpdated(from, to) {
      FluxonDOM.onBeforeElUpdated(from, to)
    }
  }
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Theme management
const ThemeManager = {
  // Cache for fetched theme tokens
  themeCache: {},

  // Determine the effective mode (light/dark) based on user preference
  getEffectiveMode(preference) {
    if (preference === 'dark') return 'dark';
    if (preference === 'light') return 'light';
    // 'system' - check OS preference
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  },

  // Apply dark/light class and color-scheme to HTML element
  applyModeClass(mode) {
    const html = document.documentElement;
    if (mode === 'dark') {
      html.classList.add('dark');
      html.style.colorScheme = 'dark';
    } else {
      html.classList.remove('dark');
      html.style.colorScheme = 'light';
    }
  },

  // Fetch theme tokens from API
  async fetchThemeTokens(mode) {
    if (this.themeCache[mode]) {
      return this.themeCache[mode];
    }

    try {
      const response = await fetch(`/api/theme/${mode}`);
      if (!response.ok) return null;
      const data = await response.json();
      this.themeCache[mode] = data;
      return data;
    } catch (error) {
      console.error('Failed to fetch theme:', error);
      return null;
    }
  },

  // Apply theme tokens as CSS custom properties
  applyThemeTokens(tokens) {
    if (!tokens) return;

    const root = document.documentElement;
    Object.entries(tokens).forEach(([key, value]) => {
      const cssVar = `--${key.replace(/_/g, '-')}`;
      root.style.setProperty(cssVar, value);
    });
  },

  // Clear any dynamically applied theme tokens
  clearDynamicTokens() {
    const root = document.documentElement;
    // Token keys match Fluxon's CSS variable names
    const tokenKeys = [
      'primary', 'primary-soft', 'foreground', 'foreground-soft', 'foreground-softer',
      'foreground-softest', 'foreground-primary', 'background-base', 'background-accent',
      'background-input', 'surface', 'overlay', 'border-base', 'danger', 'success', 'warning', 'info'
    ];
    tokenKeys.forEach(key => {
      root.style.removeProperty(`--${key}`);
    });
  },

  // Main function to apply theme based on user preference
  async applyTheme(preference) {
    const mode = this.getEffectiveMode(preference);
    this.applyModeClass(mode);

    // Fetch and apply theme tokens
    const themeData = await this.fetchThemeTokens(mode);
    if (themeData && themeData.tokens) {
      this.applyThemeTokens(themeData.tokens);
    }
  },

  // Clear cache (useful when admin changes themes)
  clearCache() {
    this.themeCache = {};
  },

  // Apply tokens directly (for admin preview without fetching)
  previewTokens(tokens, mode) {
    if (mode) {
      this.applyModeClass(mode);
    }
    this.applyThemeTokens(tokens);
  }
};

// Initialize theme on page load
document.addEventListener('DOMContentLoaded', function() {
  const preference = document.body.dataset.theme || 'system';
  ThemeManager.applyTheme(preference);

  // Listen for system preference changes
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function() {
    const currentPreference = document.body.dataset.theme || 'system';
    if (currentPreference === 'system') {
      ThemeManager.applyTheme('system');
    }
  });
});

// Apply theme after LiveView navigation
window.addEventListener("phx:page-loading-stop", function() {
  const preference = document.body.dataset.theme || 'system';
  ThemeManager.applyTheme(preference);
});

// Listen for theme preference update events from LiveView
window.addEventListener("phx:update_theme", function(e) {
  const preference = e.detail.theme;
  document.body.dataset.theme = preference;
  ThemeManager.applyTheme(preference);
});

// Listen for theme tokens preview (admin live editing)
window.addEventListener("phx:preview_theme_tokens", function(e) {
  ThemeManager.previewTokens(e.detail.tokens, e.detail.mode);
});

// Listen for theme cache clear (when admin saves new active theme)
window.addEventListener("phx:clear_theme_cache", function(e) {
  ThemeManager.clearCache();
  const preference = document.body.dataset.theme || 'system';
  ThemeManager.applyTheme(preference);
});

// Expose ThemeManager globally for debugging
window.ThemeManager = ThemeManager;

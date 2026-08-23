#!/usr/bin/env bash
# theme-switcher.sh — Select and apply a Hyprland theme via Rofi
#
# Bound to: SUPER + T
# Lists available themes via `theme-generate list --porcelain`, shows them in a
# Rofi menu, and applies the chosen one via `theme-generate set <slug>`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
GENERATOR="$CONFIG_HOME/hypr/theme/generate.py"
if [ ! -f "$GENERATOR" ]; then
  GENERATOR="$(dirname "$SCRIPT_DIR")/theme/generate.py"
fi
ROFI_THEME="$CONFIG_HOME/rofi/current-theme.rasi"
ROFI_DEFAULT="$CONFIG_HOME/rofi/comet-glass.rasi"

notify() {
  local title="$1" message="$2"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$message"
  else
    printf '%s: %s\n' "$title" "$message" >&2
  fi
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Required command not found: $1"
  fi
}

require_cmd rofi

# ── Get current theme ───────────────────────────────────────────────────────
current_theme() {
  python3 "$GENERATOR" current 2>/dev/null || printf 'None'
}

# ── Build theme list with display names ─────────────────────────────────────
# `list --porcelain` emits `slug\tname\tmode\tactive`; we render a menu line of
# `name (slug)` and prefix the active theme with an asterisk.
build_menu() {
  python3 "$GENERATOR" list --porcelain \
    | while IFS=$'\t' read -r slug name mode active; do
        [ -z "$slug" ] && continue
        if [ -n "$active" ]; then
          printf '* %s (%s)\n' "$name" "$slug"
        else
          printf '  %s (%s)\n' "$name" "$slug"
        fi
      done
}

# ── Validate and apply ──────────────────────────────────────────────────────
apply_theme() {
  local selection="$1"
  local slug

  # "Tokyo Night (tokyo-night)" -> "tokyo-night"
  slug=$(printf '%s' "$selection" | sed -n 's/.*(\([^)]*\))$/\1/p')

  if [ -z "$slug" ]; then
    notify "Theme Switcher" "Could not parse selection"
    exit 1
  fi

  if [ ! -f "$GENERATOR" ]; then
    die "Theme generator not found: $GENERATOR"
  fi

  python3 "$GENERATOR" set "$slug"
}

# ── Main ────────────────────────────────────────────────────────────────────
if pgrep -x rofi >/dev/null 2>&1; then
  pkill rofi 2>/dev/null || true
  sleep 0.1
fi

CURRENT=$(current_theme)

# Build the rofi command with the right theme
rofi_cmd=(rofi -i -dmenu -p "Theme Switcher" -mesg "Current: $CURRENT")
if [ -f "$ROFI_THEME" ]; then
  rofi_cmd+=(-theme "$ROFI_THEME")
elif [ -f "$ROFI_DEFAULT" ]; then
  rofi_cmd+=(-theme "$ROFI_DEFAULT")
fi

SELECTION=$(build_menu | "${rofi_cmd[@]}") || exit 0

if [ -z "$SELECTION" ]; then
  exit 0
fi

apply_theme "$SELECTION"

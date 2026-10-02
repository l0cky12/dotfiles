#!/usr/bin/env bash

set -euo pipefail

notify() {
  local title="$1"
  local message="$2"

  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$message" || true
  else
    printf '%s: %s\n' "$title" "$message" >&2
  fi
}

current="$(hyprctl getoption general:layout -j | jq -r '.str')"

if [ "$current" = "master" ]; then
  next="dwindle"
else
  next="master"
fi

hyprctl eval "hl.config({ general = { layout = \"$next\" } })" >/dev/null

notify "Hyprland Layout" "Switched to $next"

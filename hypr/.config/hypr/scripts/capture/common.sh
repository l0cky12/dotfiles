#!/usr/bin/env bash
# =============================================================================
# capture/common.sh — shared helpers for the capture system
#
# Sourced, never executed. Defines notification, dependency-check, path and
# filename helpers, plus the runtime state directory. Sourcing this also sources
# config.sh, so a caller only ever needs this one line:
#
#     source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# =============================================================================

capture_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=config.sh
source "$capture_dir/config.sh"

# Session state (pidfiles). Never the dotfiles repo, never /tmp.
CAPTURE_RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/hypr-capture"
mkdir -p "$CAPTURE_RUNTIME"

CAPTURE_APP="Capture"

# --- notifications -----------------------------------------------------------

# notify <title> <message> [extra notify-send args...]
# Follows the repo convention: notify-send when present, stderr otherwise.
notify() {
  local title="$1" message="$2"
  shift 2 || true

  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "$CAPTURE_APP" "$@" "$title" "$message"
  else
    printf '%s: %s\n' "$title" "$message" >&2
  fi
}

# notify_error <message>
# Confirmations for something the user just did should surface even under Do Not
# Disturb -- the same reasoning night-light.sh and dnd.sh already use.
notify_error() {
  notify "$CAPTURE_APP" "$1" -u critical -h boolean:swaync-bypass-dnd:true
}

# --- dependencies ------------------------------------------------------------

# require_cmd <command> [package-hint]
# Returns 1 and notifies with an actionable install hint instead of dying
# silently, so a missing optional backend degrades cleanly.
require_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  notify_error "$cmd is not installed — run: sudo pacman -S $pkg"
  return 1
}

# has <command> — quiet probe, no notification.
has() { command -v "$1" >/dev/null 2>&1; }

# --- paths and filenames -----------------------------------------------------

# capture_outfile <dir> <prefix> <ext>
# Reserve a unique timestamped filename, including for editors that save later.
# Callers remove an empty reservation if capture/editing does not produce data.
capture_outfile() {
  local dir="$1" prefix="$2" ext="$3"
  mkdir -p "$dir" || return 1
  mktemp -- "$dir/$prefix-$(date +'%Y-%m-%d_%H-%M-%S')-XXXXXX.$ext"
}

# capture_require_writable <dir>
capture_require_writable() {
  local dir="$1"
  if ! mkdir -p "$dir" 2>/dev/null; then
    notify_error "Cannot create $dir"
    return 1
  fi
  if [ ! -w "$dir" ]; then
    notify_error "$dir is not writable"
    return 1
  fi
  return 0
}

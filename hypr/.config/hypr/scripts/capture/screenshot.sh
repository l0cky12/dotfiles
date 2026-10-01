#!/usr/bin/env bash
# =============================================================================
# capture/screenshot.sh — screenshots via the shared selection engine
#
# Usage: screenshot.sh [smart|region|window|monitor] [options]
#   --copy          clipboard only, write no file
#   --save          file only, do not touch the clipboard
#   --delay=N       notify, wait N seconds, then select
#   --editor=CMD    override SCREENSHOT_EDITOR for this run
#
# Default behaviour copies image/png and offers Edit/Save notification actions.
#
# The freeze is held across grim, not merely across slurp: releasing it first
# would let the screen change between choosing a region and reading its pixels.
# =============================================================================
set -euo pipefail

_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=select.sh
source "$_dir/select.sh"

MODE="smart"
PROCESSING="default"
DELAY=0
EDITOR_CMD="$SCREENSHOT_EDITOR"

for arg in "$@"; do
  case "$arg" in
    smart|region|window|monitor) MODE="$arg" ;;
    --copy)      PROCESSING="copy" ;;
    --save)      PROCESSING="save" ;;
    --delay=*)   DELAY="${arg#--delay=}" ;;
    --editor=*)  EDITOR_CMD="${arg#--editor=}" ;;
    *) printf 'screenshot.sh: unknown argument: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

require_cmd grim || exit 1
has wl-copy || [ "$PROCESSING" = "save" ] || { notify_error "wl-clipboard is not installed"; exit 1; }

# --- delay -------------------------------------------------------------------
if [ "$DELAY" -gt 0 ] 2>/dev/null; then
  notify "Screenshot" "Capturing in ${DELAY}s…" -t $((DELAY * 1000))
  sleep "$DELAY"
fi

# --- select ------------------------------------------------------------------
capture_trap_cleanup
capture_freeze_start

TARGET=""
if ! TARGET=$(capture_select "$MODE"); then
  # Cancelled: the EXIT trap lifts the freeze. Silent, as a cancel is deliberate.
  exit 0
fi

# --- build the grim invocation -----------------------------------------------
grim_args=()
[ "$SCREENSHOT_CURSOR" = "1" ] && grim_args+=(-c)

case "$TARGET" in
  region:*) grim_args+=(-g "${TARGET#region:}") ;;
  monitor:*) grim_args+=(-o "${TARGET#monitor:}") ;;
  *) notify_error "Unrecognised capture target"; exit 1 ;;
esac

# --- capture -----------------------------------------------------------------
if [ "$PROCESSING" = "copy" ]; then
  # Straight to the clipboard, no file at all.
  if ! grim "${grim_args[@]}" - | wl-copy -t image/png; then
    notify_error "Screenshot failed"
    exit 1
  fi
  capture_freeze_stop
  notify "Screenshot" "Copied to clipboard"
  exit 0
fi

if [ "$PROCESSING" = "save" ]; then
  capture_require_writable "$SCREENSHOT_DIR" || exit 1
  FILE=$(capture_outfile "$SCREENSHOT_DIR" screenshot png)
else
  FILE=$(mktemp "$CAPTURE_RUNTIME/screenshot-XXXXXX.png")
fi

if ! grim "${grim_args[@]}" "$FILE"; then
  notify_error "Screenshot failed"
  rm -f "$FILE"
  exit 1
fi

# Pixels are captured; the frozen frame has done its job.
capture_freeze_stop

BODY="$(basename "$FILE")"
if [ "$PROCESSING" != "save" ]; then
  if wl-copy -t image/png < "$FILE"; then
    BODY="$BODY — copied to clipboard"
  fi
fi

# --- notify, with actions ----------------------------------------------------
# notify-send -A blocks until the notification is dismissed or actioned, so it
# is fully detached; otherwise the keybind would appear to hang.
# -t matters as much as the actions do: `notify-send -A` blocks until the
# notification is actioned or expires, so without an expiry every screenshot
# leaves a stuck process behind for the rest of the session.
notify_args=(-a "$CAPTURE_APP" -t 8000 -i "$FILE" -h "string:image-path:$FILE")

if has notify-send; then
  action_args=()
  if [ -n "$EDITOR_CMD" ]; then
    action_args+=(-A "edit=Edit")
  fi
  TITLE="Screenshot ready"
  if [ "$PROCESSING" = "save" ]; then
    TITLE="Screenshot saved"
    action_args+=(-A "open=Open")
  else
    action_args+=(-A "save=Save")
  fi

  # shellcheck disable=SC2016 # Variables below belong to the detached shell.
  setsid --fork bash -c '
    file="$1"; editor="$2"; body="$3"; title="$4"; processing="$5"
    source "$6/common.sh"; shift 6
    if [ "$processing" != save ]; then
      trap '\''rm -f -- "$file"'\'' EXIT
    fi
    choice=$(notify-send "$@" "$title" "$body" 2>/dev/null) || exit 0
    case "$choice" in
      open) command -v xdg-open >/dev/null 2>&1 && exec xdg-open "$file" ;;
      edit)
        require_cmd "${editor%% *}" || exit 1
        if [ "${editor%% *}" = satty ]; then
          output=$(capture_outfile "$SCREENSHOT_DIR" screenshot png) || exit 1
          $editor "$file" --output-filename "$output"
        else
          $editor "$file"
        fi
        ;;
      save)
        if capture_require_writable "$SCREENSHOT_DIR" &&
           output=$(capture_outfile "$SCREENSHOT_DIR" screenshot png) &&
           mv -- "$file" "$output"; then
          notify "Screenshot saved" "$output"
        else
          trap - EXIT
          notify_error "Could not save screenshot; kept at $file"
          exit 1
        fi
        ;;
    esac
  ' _ "$FILE" "$EDITOR_CMD" "$BODY" "$TITLE" "$PROCESSING" "$_dir" \
      "${notify_args[@]}" "${action_args[@]}" >/dev/null 2>&1 </dev/null || true
else
  if [ "$PROCESSING" = save ]; then
    notify "Screenshot saved" "$BODY"
  else
    notify "Screenshot" "$BODY"
    rm -f -- "$FILE"
  fi
fi

printf '%s\n' "$FILE"

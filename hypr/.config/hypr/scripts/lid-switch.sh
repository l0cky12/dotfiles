#!/usr/bin/env bash
# lid-switch.sh -- make the internal panel follow the laptop lid.
#
# Bound to Hyprland's `switch:on:Lid Switch` (close) and `switch:off:Lid
# Switch` (open) in both keybinding graphs. Only live compositor state is
# touched, via `hyprctl eval 'hl.monitor(...)'`; the generated monitors.lua is
# never edited here.
#
# close: disables the internal panel. Refuses when it is the only enabled
#        monitor -- an undocked lid close is logind's suspend to handle, and a
#        session with zero monitors is never acceptable.
# open:  re-enables the panel with preferred/auto. The resulting monitoradded
#        event triggers auto-monitor-profile.sh, which snaps the panel to the
#        active profile's exact mode and position. The applier is lid-aware,
#        so it will not fight either direction.
set -uo pipefail

HYPRCTL="${HYPRCTL:-hyprctl}"
INTERNAL_OUTPUT="${HYPR_INTERNAL_OUTPUT:-eDP-1}"

log() {
  command -v logger >/dev/null 2>&1 && logger -t hypr-lid -- "$*" 2>/dev/null
  return 0
}

usage() {
  printf 'usage: %s close|open\n' "$(basename "$0")" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage

command -v jq >/dev/null 2>&1 || { log 'jq is required'; exit 1; }

# Disabled monitors are absent from `hyprctl -j monitors`, so presence in the
# list is the "enabled" test.
LIVE_JSON="$("$HYPRCTL" -j monitors 2>/dev/null)"
jq -e 'type == "array"' >/dev/null 2>&1 <<<"$LIVE_JSON" || {
  log 'cannot read monitors -- is Hyprland running?'
  exit 1
}

internal_enabled() {
  jq -e --arg m "$INTERNAL_OUTPUT" 'any(.[]; .name == $m)' \
    >/dev/null 2>&1 <<<"$LIVE_JSON"
}

case "$1" in
  close)
    internal_enabled || { log "close: $INTERNAL_OUTPUT already disabled"; exit 0; }
    if (($(jq -r 'length' <<<"$LIVE_JSON") <= 1)); then
      log "close: $INTERNAL_OUTPUT is the only enabled monitor, leaving it on"
      exit 0
    fi
    log "close: disabling $INTERNAL_OUTPUT"
    "$HYPRCTL" -q eval "hl.monitor({ output = \"$INTERNAL_OUTPUT\", disabled = true })"
    ;;
  open)
    internal_enabled && { log "open: $INTERNAL_OUTPUT already enabled"; exit 0; }
    log "open: enabling $INTERNAL_OUTPUT"
    "$HYPRCTL" -q eval "hl.monitor({ output = \"$INTERNAL_OUTPUT\", mode = \"preferred\", position = \"auto\", scale = 1 })"
    ;;
  *)
    usage
    ;;
esac

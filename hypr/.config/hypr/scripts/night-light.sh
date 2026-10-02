#!/usr/bin/env bash
# Toggle a compositor screen shader. Hyprsunset's CTM is accepted but not
# rendered on this system, while the legacy gamma protocol fails on both
# outputs, so neither color-control backend can provide a working night light.
set -euo pipefail

state_home=${XDG_STATE_HOME:-$HOME/.local/state}
state_file=${NIGHT_LIGHT_STATE_FILE:-$state_home/hyprland-desktop/night-light-shader}
hyprctl_command=${NIGHT_LIGHT_HYPRCTL:-hyprctl}
shader=$HOME/.config/hypr/shaders/night-light.frag
dry_run=0
action=toggle

usage() {
  printf 'usage: %s [--dry-run] [toggle|on|off|status]\n' "${0##*/}"
}

for argument in "$@"; do
  case "$argument" in
    --dry-run) dry_run=1 ;;
    toggle|on|off|status) action=$argument ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

is_enabled() {
  [[ -f "$state_file" ]]
}

# Apply the shader live. `hyprctl reload` re-parses the whole Lua config on the
# compositor thread (about a second of frozen screen) and resets runtime
# toggles such as gaps and zoom; a runtime hl.config() of screen_shader makes
# Hyprland recompile just the shader. hyprland.lua reads the state file at login.
apply_shader() {
  local expression
  expression="hl.config({ decoration = { screen_shader = [==[$1]==] } })"
  if [[ "$dry_run" -eq 1 ]]; then
    printf '+ %q eval %q\n' "$hyprctl_command" "$expression"
  else
    "$hyprctl_command" eval "$expression" >/dev/null
  fi
}

set_enabled() {
  local temporary_file

  if [[ "$dry_run" -eq 1 ]]; then
    printf '+ enable shader state: %s\n' "$state_file"
    apply_shader "$shader"
    return
  fi

  mkdir -p -- "${state_file%/*}"
  temporary_file="${state_file}.tmp.$$"
  printf 'enabled\n' >"$temporary_file"
  mv -f -- "$temporary_file" "$state_file"
  apply_shader "$shader"
  printf 'night-light: on (screen shader)\n'
}

set_disabled() {
  if [[ "$dry_run" -eq 1 ]]; then
    printf '+ disable shader state: %s\n' "$state_file"
    apply_shader ""
    return
  fi

  if [[ -e "$state_file" ]]; then
    rm -f -- "$state_file"
  fi
  apply_shader ""
  printf 'night-light: off\n'
}

case "$action" in
  status)
    if is_enabled; then
      printf 'night-light: on (screen shader)\n'
    else
      printf 'night-light: off\n'
    fi
    ;;
  on) set_enabled ;;
  off) set_disabled ;;
  toggle)
    if is_enabled; then
      set_disabled
    else
      set_enabled
    fi
    ;;
esac

#!/usr/bin/env bash
# Open btop as a centered floating terminal window.
set -euo pipefail

dry_run=0
if [[ ${1:-} == "--dry-run" ]]; then
  dry_run=1
  shift
fi
if (($#)); then
  printf 'usage: %s [--dry-run]\n' "${0##*/}" >&2
  exit 2
fi

hyprctl_command=${HYPRCTL:-hyprctl}
terminal=${TERMINAL:-kitty}
command="[float] $terminal -e btop"
lua_command=${command//\\/\\\\}
lua_command=${lua_command//\"/\\\"}
lua_code="hl.dispatch(hl.dsp.exec_cmd(\"$lua_command\"))"

if ((dry_run)); then
  printf '+ %q eval %q\n' "$hyprctl_command" "$lua_code"
else
  "$hyprctl_command" eval "$lua_code"
fi

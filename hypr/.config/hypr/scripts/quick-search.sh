#!/usr/bin/env bash
# Unified Rofi search for windows, applications, commands, and system actions.
set -euo pipefail

dry_run=0
if [[ ${1:-} == "--dry-run" ]]; then
  dry_run=1
  shift
fi
start_mode=${1:-everything}
if (($#)); then
  shift
fi
if (($#)) || [[ $start_mode != everything && $start_mode != drun ]]; then
  printf 'usage: %s [--dry-run] [everything|drun]\n' "${0##*/}" >&2
  exit 2
fi

rofi_command=${ROFI:-rofi}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
everything_mode="Everything:$script_dir/quick-search-everything.sh"
if [[ $start_mode == everything ]]; then
  show_mode=Everything
else
  show_mode=drun
fi
theme=${QUICK_SEARCH_THEME:-$HOME/.config/rofi/everything.rasi}
command=(
  "$rofi_command"
  -show "$show_mode"
  -modes "$everything_mode,drun,window,run"
  -display-drun Apps
  -display-window Windows
  -display-run Commands
  -kb-mode-next Tab
  -kb-mode-previous ISO_Left_Tab
  -kb-row-tab ''
  -kb-element-next ''
  -kb-element-prev ''
  -show-icons
  -theme "$theme"
)

if ((dry_run)); then
  printf '+ '
  printf '%q ' "${command[@]}"
  printf '\n'
else
  exec "${command[@]}"
fi

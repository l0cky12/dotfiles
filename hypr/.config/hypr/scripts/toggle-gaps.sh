#!/usr/bin/env bash
# Toggle gaps globally without hard-coding the configured defaults.
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
jq_command=${JQ:-jq}
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/hyprland-desktop
state_file=$state_dir/gaps-defaults.json

run() {
  if ((dry_run)); then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

number() {
  [[ $1 =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

option_value() {
  "$hyprctl_command" getoption "$1" -j | "$jq_command" -er '
    if .custom != null then .custom
    elif .int != null then .int
    elif .css != null then (.css | split(" ")[0])
    else error("option has no numeric value") end
  '
}

if [[ -f $state_file ]]; then
  IFS=$'\t' read -r gaps_out gaps_in border_size < <(
    "$jq_command" -er '
      [.gaps_out, .gaps_in, .border_size]
      | if all(.[]; type == "number") then @tsv
        else error("saved gaps are not numeric") end
    ' "$state_file"
  )
  if ! number "$gaps_out" || ! number "$gaps_in" || ! number "$border_size"; then
    printf 'toggle-gaps: saved gaps or border size is not numeric\n' >&2
    exit 1
  fi

  config="hl.config({ general = { gaps_out = $gaps_out, gaps_in = $gaps_in, border_size = $border_size } })"
  run "$hyprctl_command" eval "$config"
  run rm -- "$state_file"
else
  gaps_out=$(option_value general:gaps_out)
  gaps_in=$(option_value general:gaps_in)
  border_size=$(option_value general:border_size)
  if ! number "$gaps_out" || ! number "$gaps_in" || ! number "$border_size"; then
    printf 'toggle-gaps: configured gaps or border size is not numeric\n' >&2
    exit 1
  fi

  if ((dry_run)); then
    printf '+ save gap defaults: gaps_out=%s gaps_in=%s border_size=%s\n' \
      "$gaps_out" "$gaps_in" "$border_size"
  else
    mkdir -p -- "$state_dir"
    state_tmp=$state_file.tmp.$$
    trap 'rm -f -- "$state_tmp"' EXIT
    # The dollar-prefixed names in the filter are jq variables.
    # shellcheck disable=SC2016
    "$jq_command" -n \
      --argjson gaps_out "$gaps_out" \
      --argjson gaps_in "$gaps_in" \
      --argjson border_size "$border_size" \
      '{gaps_out: $gaps_out, gaps_in: $gaps_in, border_size: $border_size}' \
      >"$state_tmp"
    mv -- "$state_tmp" "$state_file"
    trap - EXIT
  fi

  config='hl.config({ general = { gaps_out = 0, gaps_in = 0, border_size = 0 } })'
  run "$hyprctl_command" eval "$config"
fi

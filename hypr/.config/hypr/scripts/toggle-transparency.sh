#!/usr/bin/env bash
# Toggle window transparency globally while preserving configured defaults.
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
state_file=$state_dir/opacity-defaults.json

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
    if .float != null then .float
    elif .custom != null then .custom
    else error("option has no numeric value") end
  '
}

if [[ -f $state_file ]]; then
  IFS=$'\t' read -r active inactive fullscreen < <(
    "$jq_command" -er '
      [.active, .inactive, .fullscreen]
      | if all(.[]; type == "number") then @tsv
        else error("saved opacity values are not numeric") end
    ' "$state_file"
  )
  if ! number "$active" || ! number "$inactive" || ! number "$fullscreen"; then
    printf 'toggle-transparency: saved opacity values are not numeric\n' >&2
    exit 1
  fi

  config="hl.config({ decoration = { active_opacity = $active, inactive_opacity = $inactive, fullscreen_opacity = $fullscreen } })"
  run "$hyprctl_command" eval "$config"
  run rm -- "$state_file"
else
  active=$(option_value decoration:active_opacity)
  inactive=$(option_value decoration:inactive_opacity)
  fullscreen=$(option_value decoration:fullscreen_opacity)
  if ! number "$active" || ! number "$inactive" || ! number "$fullscreen"; then
    printf 'toggle-transparency: configured opacity values are not numeric\n' >&2
    exit 1
  fi

  if ((dry_run)); then
    printf '+ save opacity defaults: active=%s inactive=%s fullscreen=%s\n' \
      "$active" "$inactive" "$fullscreen"
  else
    mkdir -p -- "$state_dir"
    state_tmp=$state_file.tmp.$$
    trap 'rm -f -- "$state_tmp"' EXIT
    # The dollar-prefixed names in the filter are jq variables.
    # shellcheck disable=SC2016
    "$jq_command" -n \
      --argjson active "$active" \
      --argjson inactive "$inactive" \
      --argjson fullscreen "$fullscreen" \
      '{active: $active, inactive: $inactive, fullscreen: $fullscreen}' \
      >"$state_tmp"
    mv -- "$state_tmp" "$state_file"
    trap - EXIT
  fi

  config='hl.config({ decoration = { active_opacity = 1, inactive_opacity = 1, fullscreen_opacity = 1 } })'
  run "$hyprctl_command" eval "$config"
fi

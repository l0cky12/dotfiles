#!/usr/bin/env bash
# Cycle Hyprland layouts and make Dwindle-only split controls explicit.
set -euo pipefail

HYPRCTL=${HYPRCTL:-hyprctl}
NOTIFY_SEND=${NOTIFY_SEND:-notify-send}
GDBUS=${GDBUS:-gdbus}

usage() {
  printf 'usage: %s [--dry-run] {cycle|split-horizontal|split-vertical}\n' "${0##*/}" >&2
  exit 64
}

layout_name() {
  case "$1" in
    dwindle) printf 'Dwindle' ;;
    master) printf 'Master' ;;
    scrolling) printf 'Scrolling' ;;
    monocle) printf 'Monocle' ;;
    *) printf '%s' "$1" ;;
  esac
}

current_layout() {
  if [[ -n ${HYPR_LAYOUT:-} ]]; then
    printf '%s' "$HYPR_LAYOUT"
  else
    "$HYPRCTL" getoption general:layout -j | jq -er '.str'
  fi
}

notify() {
  local title=$1 body=$2
  "$NOTIFY_SEND" -a Hyprland -r 9930 -t 2500 "$title" "$body" >/dev/null 2>&1 && return
  "$GDBUS" call --session \
    --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.Notify \
    Hyprland 9930 '' "$title" "$body" '[]' '{}' 2500 >/dev/null
}

cycle_layout() {
  local current next
  current=$(current_layout)
  case "$current" in
    dwindle) next=master ;;
    master) next=scrolling ;;
    scrolling) next=monocle ;;
    *) next=dwindle ;;
  esac
  if ((dry_run)); then
    printf 'current=%s\naction=cycle\nnext=%s\nnotification=Window layout: %s\n' \
      "$current" "$next" "$(layout_name "$next")"
    return
  fi
  "$HYPRCTL" -q eval "hl.config({ general = { layout = '$next' } })"
  notify "Window layout: $(layout_name "$next")" 'Active window layout changed'
}

set_split_direction() {
  local direction=$1 description=$2 current
  current=$(current_layout)
  if [[ "$current" != dwindle ]]; then
    if ((dry_run)); then
      printf 'current=%s\naction=split-%s\nresult=unavailable\nnotification=Window layout: %s\n' \
        "$current" "$description" "$(layout_name "$current")"
    else
      notify "Window layout: $(layout_name "$current")" \
        'Split direction is available in Dwindle'
    fi
    return
  fi
  if ((dry_run)); then
    printf 'current=dwindle\naction=split-%s\nlayoutmsg=preselect %s\n' "$description" "$direction"
    return
  fi
  "$HYPRCTL" dispatch layoutmsg "preselect $direction"
  notify 'Dwindle split' "Next window opens ${description}"
}

main() {
  dry_run=0
  if [[ ${1:-} == --dry-run ]]; then
    dry_run=1
    shift
  fi
  case ${1:-} in
    cycle) cycle_layout ;;
    split-horizontal) set_split_direction r 'to the right' ;;
    split-vertical) set_split_direction d 'below' ;;
    *) usage ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi

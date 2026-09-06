#!/usr/bin/env bash
# Omakub-style stateful desktop toggles. A <name>-off flag means disabled.
set -euo pipefail

state_root=${XDG_STATE_HOME:-"$HOME/.local/state"}/toggles
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
hyprctl_command=${HYPRCTL:-hyprctl}
desktop_mode=${DESKTOP_MODE_EXECUTABLE:-"$HOME/.local/bin/desktop-mode"}
notificationctl_command=${NOTIFICATIONCTL:-"$HOME/.local/bin/notificationctl"}
screensaver_toggle=${TOGGLE_SCREENSAVER_EXECUTABLE:-"$HOME/.local/bin/toggle-screensaver"}
quickshell_command=${QUICKSHELL:-quickshell}
dry_run=0

usage() {
  printf 'usage: %s [--dry-run] [menu|nightlight|dnd|stay-awake|screensaver|touchpad|suspend|bar|status]\n' "${0##*/}"
}

run() {
  if ((dry_run)); then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

is_off() {
  [[ -e "$state_root/$1-off" ]]
}

set_off() {
  if ((dry_run)); then
    printf '+ touch %q\n' "$state_root/$1-off"
  else
    mkdir -p -- "$state_root"
    touch -- "$state_root/$1-off"
  fi
}

set_on() {
  if ((dry_run)); then
    printf '+ rm -f %q\n' "$state_root/$1-off"
  else
    rm -f -- "$state_root/$1-off"
  fi
}

state() {
  local item=$1
  case "$item" in
    nightlight)
      "$script_dir/night-light.sh" status | grep -q '^night-light: on' && printf 'on' || printf 'off'
      ;;
    dnd)
      [[ -x $notificationctl_command ]] &&
        "$notificationctl_command" status --json | jq -e '.dnd == true' >/dev/null && printf 'on' || printf 'off'
      ;;
    stay-awake)
      [[ -x $desktop_mode ]] &&
        "$desktop_mode" status stay-awake --json | jq -e '.observed == true' >/dev/null && printf 'on' || printf 'off'
      ;;
    screensaver)
      [[ -x $screensaver_toggle ]] &&
        "$screensaver_toggle" status | grep -qx 'screensaver: on' && printf 'on' || printf 'off'
      ;;
    touchpad)
      "$hyprctl_command" devices -j | jq -e \
        '(.touchpads | length > 0) and all(.touchpads[]; (.enabled // true) == true)' >/dev/null && printf 'on' || printf 'off'
      ;;
    suspend)
      pgrep -x hypridle >/dev/null && printf 'on' || printf 'off'
      ;;
    bar)
      "$quickshell_command" ipc call bar statusJson 2>/dev/null |
        jq -e '.visible == true' >/dev/null && printf 'on' || printf 'off'
      ;;
    *)
      return 2
      ;;
  esac
}

sync_flag() {
  if [[ $(state "$1") == on ]]; then
    set_on "$1"
  else
    set_off "$1"
  fi
}

label() {
  printf '%s  %s (%s)' "$1" "$2" "$(state "$3")"
}

active_rows() {
  local item index=0 rows=()
  for item in nightlight dnd stay-awake screensaver touchpad suspend bar; do
    if [[ $(state "$item") == on ]]; then
      rows+=("$index")
    fi
    ((index += 1))
  done
  local IFS=,
  printf '%s' "${rows[*]}"
}

pick() {
  local options=$1 active=$2
  if command -v fuzzel >/dev/null 2>&1; then
    printf '%s\n' "$options" | fuzzel --dmenu --prompt 'Toggles: '
  elif command -v rofi >/dev/null 2>&1; then
    printf '%s\n' "$options" | rofi -dmenu -i -no-custom -p 'Toggles' \
      -theme "$HOME/.config/rofi/power-menu.rasi" -a "$active" \
      -theme-str 'window { width: 720px; }' \
      -theme-str 'listview { columns: 1; lines: 7; }' \
      -theme-str 'element { orientation: horizontal; padding: 12px 18px; }' \
      -theme-str 'element-text { expand: true; horizontal-align: 0; }' \
      -theme-str 'textbox-prompt-colon { str: "Toggles"; }'
  elif command -v wofi >/dev/null 2>&1; then
    printf '%s\n' "$options" | wofi --dmenu --prompt 'Toggles'
  elif command -v bemenu >/dev/null 2>&1; then
    printf '%s\n' "$options" | bemenu -p 'Toggles'
  else
    printf 'No launcher found. Install fuzzel, rofi, wofi, or bemenu.\n' >&2
    return 1
  fi
}

toggle_touchpad() {
  local enabled next
  if ! "$hyprctl_command" devices -j | jq -e '.touchpads | length > 0' >/dev/null; then
    printf 'toggle: no touchpad device is connected\n' >&2
    return 1
  fi
  enabled=$("$hyprctl_command" getoption input:touchpad:enabled -j | jq -er '.int')
  if [[ $enabled == 0 ]]; then
    next=true
  else
    next=false
  fi
  run "$hyprctl_command" eval "hl.config({ input = { touchpad = { enabled = $next } } })"
}

toggle_item() {
  local item=$1
  case "$item" in
    nightlight)
      run "$script_dir/night-light.sh" toggle
      ;;
    dnd)
      run "$notificationctl_command" dnd-toggle
      ;;
    stay-awake)
      run "$desktop_mode" toggle stay-awake
      ;;
    screensaver)
      run "$script_dir/run-if-deployed.sh" screensaver toggle-screensaver
      ;;
    touchpad)
      toggle_touchpad
      ;;
    suspend)
      run loginctl lock-session
      run systemctl suspend
      ;;
    bar)
      run "$quickshell_command" ipc call bar toggle
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
  sync_flag "$item"
}

show_status() {
  local nightlight dnd stay_awake screensaver touchpad suspend bar_state
  nightlight=$(state nightlight)
  dnd=$(state dnd)
  stay_awake=$(state stay-awake)
  screensaver=$(state screensaver)
  touchpad=$(state touchpad)
  suspend=$(state suspend)
  bar_state=$(state bar)
  jq -cn \
    --arg nightlight "$nightlight" \
    --arg dnd "$dnd" \
    --arg stay_awake "$stay_awake" \
    --arg screensaver "$screensaver" \
    --arg touchpad "$touchpad" \
    --arg suspend "$suspend" \
    --arg bar "$bar_state" \
    '{nightlight: $nightlight, dnd: $dnd, "stay-awake": $stay_awake,
      screensaver: $screensaver, touchpad: $touchpad, suspend: $suspend,
      bar: $bar}'
}

show_menu() {
  local choice options
  options=$(printf '%s\n' \
    "$(label '🌙' 'Night light' nightlight)" \
    "$(label '🔕' 'Do Not Disturb' dnd)" \
    "$(label '☕' 'Stay awake' stay-awake)" \
    "$(label '🎬' 'Screensaver' screensaver)" \
    "$(label '🖱️' 'Touchpad' touchpad)" \
    "$(label '💤' 'Suspend' suspend)" \
    "$(label '📺' 'Menu bar' bar)")
  choice=$(pick "$options" "$(active_rows)") || return 0
  case "$choice" in
    '🌙  Night light ('*) toggle_item nightlight ;;
    '🔕  Do Not Disturb ('*) toggle_item dnd ;;
    '☕  Stay awake ('*) toggle_item stay-awake ;;
    '🎬  Screensaver ('*) toggle_item screensaver ;;
    '🖱️  Touchpad ('*) toggle_item touchpad ;;
    '💤  Suspend ('*) toggle_item suspend ;;
    '📺  Menu bar ('*) toggle_item bar ;;
  esac
}

while (($#)); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    -h|--help) usage; exit 0 ;;
    *) break ;;
  esac
  shift
done

case ${1:-menu} in
  menu) show_menu ;;
  nightlight|dnd|stay-awake|screensaver|touchpad|suspend|bar) toggle_item "$1" ;;
  status) show_status ;;
  *) usage >&2; exit 2 ;;
esac

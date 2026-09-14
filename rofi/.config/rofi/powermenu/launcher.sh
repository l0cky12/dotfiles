#!/usr/bin/env bash
set -euo pipefail

MENU_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly MENU_DIR
readonly THEME="${POWER_MENU_THEME:-$MENU_DIR/layout.rasi}"
readonly LOCK_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprlock.conf"

usage() {
  cat <<'EOF'
Usage: launcher.sh [ACTION | --dry-run ACTION]

With ACTION alone, runs it directly with no picker or confirmation.

Actions: lock, logout, suspend, reboot, shutdown
EOF
}

print_command() {
  printf 'DRY-RUN:'
  printf ' %q' "$@"
  printf '\n'
}

ensure_locked() {
  if (( DRY_RUN )); then
    print_command pgrep -x hyprlock
    print_command hyprlock --config "$LOCK_CONFIG" '&'
    return
  fi

  if ! pgrep -x hyprlock >/dev/null 2>&1; then
    hyprlock --config "$LOCK_CONFIG" &
  fi
}

run_action() {
  local action="$1"

  case "$action" in
    lock)
      if (( DRY_RUN )); then
        print_command hyprlock --config "$LOCK_CONFIG"
      elif ! pgrep -x hyprlock >/dev/null 2>&1; then
        exec hyprlock --config "$LOCK_CONFIG"
      fi
      ;;
    logout)
      if (( DRY_RUN )); then
        print_command hyprctl dispatch exit
      else
        hyprctl dispatch exit
      fi
      ;;
    suspend)
      ensure_locked
      if (( DRY_RUN )); then
        print_command sleep 1
        print_command systemctl suspend
      else
        sleep 1
        systemctl suspend
      fi
      ;;
    reboot)
      if (( DRY_RUN )); then
        print_command systemctl reboot
      else
        systemctl reboot
      fi
      ;;
    shutdown)
      if (( DRY_RUN )); then
        print_command systemctl poweroff
      else
        systemctl poweroff
      fi
      ;;
    *)
      printf 'Unknown action: %s\n' "$action" >&2
      usage >&2
      return 2
      ;;
  esac
}

confirm_action() {
  local action="$1"
  local selected status

  set +e
  selected="$({
    printf '%s\n' \
      '<span size="large">Cancel</span>' \
      "<span size=\"large\" weight=\"bold\">Confirm ${action}</span>"
  } | rofi -dmenu -no-custom -markup-rows -format i \
      -p "${action}?" -mesg 'Enter confirms · Esc cancels' \
      -theme "$THEME" \
      -theme-str 'listview { columns: 2; }' \
      -theme-str 'window { padding: 22%; }' \
      -u 1)"
  status=$?
  set -e

  [[ $status -eq 0 && $selected == 1 ]]
}

select_action() {
  local selected status
  local -a actions=(lock logout suspend reboot shutdown)

  set +e
  selected="$({
    printf '%s\n' \
      '<span size="xx-large"></span>\n<span weight="bold">Lock</span>\n<span size="small">L</span>' \
      '<span size="xx-large">󰍃</span>\n<span weight="bold">Logout</span>\n<span size="small">E</span>' \
      '<span size="xx-large">󰤄</span>\n<span weight="bold">Suspend</span>\n<span size="small">U / H</span>' \
      '<span size="xx-large">󰜉</span>\n<span weight="bold">Reboot</span>\n<span size="small">R</span>' \
      '<span size="xx-large"></span>\n<span weight="bold">Shutdown</span>\n<span size="small">S</span>'
  } | rofi -dmenu -no-custom -markup-rows -format i \
      -p Session -mesg 'Click or press L · E · U/H · R · S' \
      -theme "$THEME" -a 0,1,2 -u 3,4 \
      -kb-custom-1 l -kb-custom-2 e -kb-custom-3 u \
      -kb-custom-4 h -kb-custom-5 r -kb-custom-6 s)"
  status=$?
  set -e

  case "$status" in
    0)
      [[ $selected =~ ^[0-4]$ ]] || return 1
      printf '%s\n' "${actions[selected]}"
      ;;
    10) printf '%s\n' lock ;;
    11) printf '%s\n' logout ;;
    12|13) printf '%s\n' suspend ;;
    14) printf '%s\n' reboot ;;
    15) printf '%s\n' shutdown ;;
    *) return 1 ;;
  esac
}

DRY_RUN=0
if [[ ${1:-} == --dry-run ]]; then
  DRY_RUN=1
  [[ $# -eq 2 ]] || {
    usage >&2
    exit 2
  }
  run_action "$2"
  exit
fi

if [[ $# -eq 1 ]]; then
  run_action "$1"
  exit
fi
[[ $# -eq 0 ]] || {
  usage >&2
  exit 2
}

command -v rofi >/dev/null 2>&1 || {
  printf 'Power menu requires rofi.\n' >&2
  exit 127
}

action="$(select_action)" || exit 0
case "$action" in
  logout|reboot|shutdown)
    confirm_action "$action" || exit 0
    ;;
esac
run_action "$action"

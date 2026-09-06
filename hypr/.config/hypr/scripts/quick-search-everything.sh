#!/usr/bin/env bash
# Rofi root menu for application, window, command, and power actions.
set -euo pipefail

print_action() {
  printf '+ systemctl %s\n' "$1"
}

run_action() {
  local action=$1

  if [[ ${QUICK_SEARCH_DRY_RUN:-0} == 1 ]]; then
    print_action "$action"
    return
  fi

  # Rofi script modes must background external programs or the menu waits for
  # their output. Both streams are detached from the script-mode protocol.
  coproc {
    systemctl "$action" >/dev/null 2>&1
  }
}

emit_initial() {
  printf '\0no-custom\x1ftrue\n'
  printf 'apps\0display\x1fApps                         ›\x1ficon\x1fapplications-other\x1fmeta\x1finstalled applications launcher\n'
  printf 'windows\0display\x1fWindows                      ›\x1ficon\x1fpreferences-system-windows\x1fmeta\x1fopen windows switcher\n'
  printf 'commands\0display\x1fCommands                     ›\x1ficon\x1futilities-terminal\x1fmeta\x1fexecutable commands run\n'
  printf 'reboot\0display\x1fReboot                       ›\x1ficon\x1fsystem-reboot\x1fmeta\x1frestart system\n'
  printf 'shutdown\0display\x1fShutdown                     ›\x1ficon\x1fsystem-shutdown\x1fmeta\x1fpower off system\n'
}

switch_mode() {
  printf '\0switch-mode\x1f%s\n' "$1"
}

emit_confirmation() {
  local action=$1
  printf '\0prompt\x1fConfirm %s?\n' "$action"
  printf '\0message\x1fThis %s the computer.\n' "$([[ $action == reboot ]] && printf reboots || printf 'shuts down')"
  printf '\0data\x1f%s\n' "$action"
  printf '\0no-custom\x1ftrue\n'
  printf '\0switch-mode\x1fEverything\n'
  printf 'cancel\0display\x1fCancel\n'
  printf 'confirm\0display\x1fConfirm %s\x1furgent\x1ftrue\n' "$action"
}

if [[ ${1:-} == --dry-run ]]; then
  [[ $# -eq 2 ]] || {
    printf 'usage: %s --dry-run {reboot|shutdown}\n' "${0##*/}" >&2
    exit 2
  }
  case $2 in
    reboot) print_action reboot ;;
    shutdown) print_action poweroff ;;
    *) printf 'usage: %s --dry-run {reboot|shutdown}\n' "${0##*/}" >&2; exit 2 ;;
  esac
  exit
fi

case ${ROFI_RETV:-0} in
  0)
    emit_initial
    ;;
  1)
    if [[ -z ${ROFI_DATA:-} ]]; then
      case ${1:-} in
        apps) switch_mode drun ;;
        windows) switch_mode window ;;
        commands) switch_mode run ;;
        reboot|shutdown) emit_confirmation "$1" ;;
        *) exit 0 ;;
      esac
    elif [[ ${1:-} == confirm ]]; then
      case $ROFI_DATA in
        reboot) run_action reboot ;;
        shutdown) run_action poweroff ;;
        *) exit 2 ;;
      esac
    fi
    ;;
esac

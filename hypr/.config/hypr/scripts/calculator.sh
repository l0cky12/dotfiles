#!/usr/bin/env bash
set -euo pipefail

ROFI_THEME="${CALCULATOR_ROFI_THEME:-$HOME/.config/rofi/calculator.rasi}"
if [[ ! -r "$HOME/.config/rofi/current-theme.rasi" || ! -r "$ROFI_THEME" ]]; then
  ROFI_THEME="$HOME/.config/rofi/comet-glass.rasi"
fi
HISTORY_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/calculator/history"
HISTORY_LIMIT=100

notify_error() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Calculator" -u critical "Calculator" "$1" 2>/dev/null || true
  else
    printf 'Calculator: %s\n' "$1" >&2
  fi
}

for command_name in rofi qalc wl-copy; do
  command -v "$command_name" >/dev/null 2>&1 || {
    notify_error "$command_name is not installed"
    exit 1
  }
done

copy_result() {
  printf '%s' "$1" | wl-copy --type text/plain
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Calculator" "Calculator" "Copied: $1" 2>/dev/null || true
  fi
}

# History is "expression<TAB>result" per line, oldest first.
save_history() (
  local dir tmp
  dir=$(dirname -- "$HISTORY_FILE")
  mkdir -p -- "$dir" || return 1
  exec 9>"$dir/.history.lock" || return 1
  flock -x 9 || return 1
  tmp=$(mktemp "$HISTORY_FILE.XXXXXX") || return 1
  # A failed tail (e.g. unreadable history) aborts before the old file is replaced.
  if ! { { [[ ! -e "$HISTORY_FILE" ]] || tail -n "$((HISTORY_LIMIT - 1))" -- "$HISTORY_FILE"; } > "$tmp" &&
    printf '%s\t%s\n' "${1//$'\t'/ }" "$2" >> "$tmp" &&
    mv -f -- "$tmp" "$HISTORY_FILE"; }; then
    rm -f -- "$tmp"
    return 1
  fi
)

history=""
[[ -r "$HISTORY_FILE" ]] && { history=$(tac -- "$HISTORY_FILE") || history=""; }

# Enter always calculates the typed text; Ctrl+Enter (custom key 1, exit 10)
# copies the highlighted history row. -format i:f prints "<row index or -1>:<typed text>".
status=0
selection=$({ [[ -z "$history" ]] || printf '%s\n' "$history"; } | sed 's/\t/ = /' |
  rofi -dmenu -i -format 'i:f' -kb-accept-custom '' -kb-custom-1 'Control+Return' \
    -p "Calculator" \
    -mesg "Enter calculates • Ctrl+Enter copies the highlighted history result" \
    -theme "$ROFI_THEME" -theme-str 'listview { lines: 6; } element { padding: 10px 18px; }') ||
  status=$?
[[ "$status" == 0 || "$status" == 10 ]] || exit 0
index=${selection%%:*}
expression=${selection#*:}

if [[ "$index" =~ ^[0-9]+$ ]] && [[ "$status" == 10 || -z "${expression//[[:space:]]/}" ]]; then
  result=$(printf '%s\n' "$history" | sed -n "$((index + 1))p" | cut -f2-)
  [[ -n "$result" ]] || { notify_error "History entry not found"; exit 1; }
  copy_result "$result"
  exit 0
fi
[[ -n "${expression//[[:space:]]/}" ]] || exit 0

error_file=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/calculator.XXXXXX") || exit 1
trap 'rm -f -- "$error_file"' EXIT INT TERM

if ! result=$(qalc -t -m 2000 "$expression" 2>"$error_file"); then
  error=$(sed -n '/[^[:space:]]/{s/^[[:space:]]*//;p;q;}' "$error_file")
  notify_error "${error:-Invalid expression}"
  exit 1
fi
result=$(printf '%s\n' "$result" | sed -n '/[^[:space:]]/{p;q;}')
[[ -n "$result" ]] || { notify_error "No result"; exit 1; }
save_history "$expression" "$result" || true

choice=$(printf '%s\n' "$result" | rofi -dmenu -i -no-custom -p "Answer" \
  -mesg "Press Enter to copy • Escape to close" -theme "$ROFI_THEME") || exit 0
[[ -n "$choice" ]] || exit 0

copy_result "$choice"

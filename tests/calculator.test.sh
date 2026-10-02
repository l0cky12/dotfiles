#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
calculator="$repo_root/hypr/.config/hypr/scripts/calculator.sh"
test_root=$(mktemp -d -t calculator-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "expected [$1], got [$2]"
}

mkdir -p "$test_root/bin" "$test_root/config" "$test_root/runtime"

# Fake rofi. Screen 1 (history/input) emulates -format i:f: CALCULATOR_EXPRESSION is
# the typed text, ROFI_PICK the highlighted row (-1 = none), ROFI_KEY=ctrl-enter
# exits 10 like kb-custom-1. Later screens echo their input (the Answer row).
cat > "$test_root/bin/rofi" <<'SH'
#!/usr/bin/env bash
count=0
[[ -f "$ROFI_STATE" ]] && count=$(<"$ROFI_STATE")
count=$((count + 1))
printf '%s' "$count" > "$ROFI_STATE"
input=$(cat)
if [[ "${ROFI_CANCEL_AT:-0}" == "$count" ]]; then
  exit 1
fi
if [[ "$count" == 1 ]]; then
  printf '%s\n' "$*" > "$ROFI_ARGS"
  printf '%s' "$input" > "$ROFI_MENU"
  printf '%s:%s\n' "${ROFI_PICK:--1}" "${CALCULATOR_EXPRESSION-2 + 3 * 4}"
  [[ "${ROFI_KEY:-}" == ctrl-enter ]] && exit 10
  exit 0
fi
printf '%s\n' "$input"
SH
cat > "$test_root/bin/wl-copy" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CALCULATOR_CLIPBOARD_ARGS"
cat > "$CALCULATOR_CLIPBOARD_DATA"
SH
cat > "$test_root/bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALCULATOR_NOTIFICATIONS"
SH
cat > "$test_root/bin/qalc" <<'SH'
#!/usr/bin/env bash
# Minimal qalc stand-in: evaluates simple integer arithmetic so the test
# does not depend on libqalculate being installed.
# Strip qalc's flags (-t -m 2000) and whitespace; keep only the expression.
args=()
for a in "$@"; do
  case $a in
    -t|-m|2000) ;;
    *) args+=("$a") ;;
  esac
done
expr="${args[*]}"
expr="${expr//[[:space:]]/}"
(( result = 0 + expr ))
printf '%s\n' "$result"
SH
chmod +x "$test_root/bin/rofi" "$test_root/bin/wl-copy" "$test_root/bin/notify-send" "$test_root/bin/qalc"

export ROFI_STATE="$test_root/rofi-state"
export ROFI_ARGS="$test_root/rofi-args"
export ROFI_MENU="$test_root/rofi-menu"
export CALCULATOR_CLIPBOARD_ARGS="$test_root/clipboard-args"
export CALCULATOR_CLIPBOARD_DATA="$test_root/clipboard-data"
export CALCULATOR_NOTIFICATIONS="$test_root/notifications"
history_file="$test_root/.local/state/calculator/history"

run_calc() {
  local -a state_env=(-u XDG_STATE_HOME)
  [[ -z "${CALCULATOR_STATE_HOME:-}" ]] || state_env=("XDG_STATE_HOME=$CALCULATOR_STATE_HOME")
  rm -f "$ROFI_STATE" "$CALCULATOR_CLIPBOARD_DATA" "$CALCULATOR_NOTIFICATIONS"
  env "${state_env[@]}" PATH="$test_root/bin:$PATH" HOME="$test_root" \
    XDG_CONFIG_HOME="$test_root/config" XDG_RUNTIME_DIR="$test_root/runtime" "$calculator"
}

run_calc
assert_eq 14 "$(<"$CALCULATOR_CLIPBOARD_DATA")"
grep -Fq -- '--type text/plain' "$CALCULATOR_CLIPBOARD_ARGS" ||
  fail 'calculator did not set text/plain clipboard type'
grep -Fq -- 'Copied: 14' "$CALCULATOR_NOTIFICATIONS" ||
  fail 'calculator did not notify after copying'
grep -Fq -- '-format i:f' "$ROFI_ARGS" || fail 'history screen does not ask rofi for index:filter'
grep -Fq -- "-kb-accept-custom  -kb-custom-1 Control+Return" "$ROFI_ARGS" ||
  fail 'Ctrl+Enter is not bound to copying a history row'
assert_eq "$(printf '2 + 3 * 4\t14')" "$(<"$history_file")"

CALCULATOR_EXPRESSION='6 * 7' run_calc
assert_eq 42 "$(<"$CALCULATOR_CLIPBOARD_DATA")"
assert_eq "$(printf '2 + 3 * 4 = 14')" "$(<"$ROFI_MENU")"

# Typed text that matches an old row still calculates on Enter.
CALCULATOR_EXPRESSION='2 + 2' ROFI_PICK=1 run_calc
assert_eq 4 "$(<"$CALCULATOR_CLIPBOARD_DATA")"
assert_eq "$(printf '6 * 7 = 42\n2 + 3 * 4 = 14')" "$(<"$ROFI_MENU")"

# Ctrl+Enter copies the highlighted (newest-first) history row without calculating.
CALCULATOR_EXPRESSION='2 +' ROFI_PICK=2 ROFI_KEY=ctrl-enter run_calc
assert_eq "$(printf '2 + 2 = 4\n6 * 7 = 42\n2 + 3 * 4 = 14')" "$(<"$ROFI_MENU")"
assert_eq 14 "$(<"$CALCULATOR_CLIPBOARD_DATA")"
assert_eq 1 "$(<"$ROFI_STATE")"

# With nothing typed, Enter on a highlighted row copies it; with no row it closes.
CALCULATOR_EXPRESSION='' ROFI_PICK=1 run_calc
assert_eq 42 "$(<"$CALCULATOR_CLIPBOARD_DATA")"
CALCULATOR_EXPRESSION='' run_calc
[[ ! -e "$CALCULATOR_CLIPBOARD_DATA" ]] || fail 'empty input copied something'
assert_eq 3 "$(wc -l < "$history_file")"

# Ctrl+Enter with no matching row falls back to calculating the typed text.
CALCULATOR_EXPRESSION='1 + 1' ROFI_KEY=ctrl-enter run_calc
assert_eq 2 "$(<"$CALCULATOR_CLIPBOARD_DATA")"

# History keeps only the newest 100 entries.
for n in $(seq 1 120); do printf '%s\t%s\n' "$n" "$n"; done > "$history_file"
run_calc
assert_eq 100 "$(wc -l < "$history_file")"
assert_eq "$(printf '22\t22')" "$(head -n1 "$history_file")"
assert_eq "$(printf '2 + 3 * 4\t14')" "$(tail -n1 "$history_file")"

# An unreadable history file is left alone rather than replaced.
if [[ "$(id -u)" != 0 ]]; then
  chmod 000 "$history_file"
  run_calc 2>/dev/null
  chmod 600 "$history_file"
  assert_eq 14 "$(<"$CALCULATOR_CLIPBOARD_DATA")"
  assert_eq 100 "$(wc -l < "$history_file")"
fi
[[ -z "$(find "${history_file%/*}" -name 'history.*')" ]] || fail 'history temp file left behind'

# A read error still permits calculating; a failed replacement keeps old entries.
printf '#!/usr/bin/env bash\nexit 1\n' > "$test_root/bin/tac"
chmod +x "$test_root/bin/tac"
run_calc
assert_eq 14 "$(<"$CALCULATOR_CLIPBOARD_DATA")"
[[ ! -s "$ROFI_MENU" ]] || fail 'failed history read displayed partial history'
rm "$test_root/bin/tac"
history_before=$(cat "$history_file")
printf '#!/usr/bin/env bash\nexit 1\n' > "$test_root/bin/mv"
chmod +x "$test_root/bin/mv"
run_calc
assert_eq "$history_before" "$(cat "$history_file")"
[[ -z "$(find "${history_file%/*}" -name 'history.*')" ]] || fail 'failed replacement left temporary history'
rm "$test_root/bin/mv"

# Concurrent instances retain every successful result in a custom state directory.
cat > "$test_root/bin/tail" <<'SH'
#!/usr/bin/env bash
sleep 0.1
exec /usr/bin/tail "$@"
SH
chmod +x "$test_root/bin/tail"
parallel_state="$test_root/parallel state"
CALCULATOR_STATE_HOME="$parallel_state" run_calc
pids=()
for n in {1..8}; do
  CALCULATOR_STATE_HOME="$parallel_state" CALCULATOR_EXPRESSION="$n + 10" \
    ROFI_STATE="$test_root/rofi-state-$n" \
    CALCULATOR_CLIPBOARD_DATA="$test_root/clipboard-$n" \
    CALCULATOR_NOTIFICATIONS="$test_root/notifications-$n" run_calc &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
assert_eq 9 "$(wc -l < "$parallel_state/calculator/history")"
for n in {1..8}; do
  grep -Fxq "$(printf '%s + 10\t%s' "$n" "$((n + 10))")" "$parallel_state/calculator/history" ||
    fail "concurrent save lost calculation $n"
done
rm "$test_root/bin/tail"

for cancel_at in 1 2; do
  history_before=$(cat "$history_file")
  ROFI_CANCEL_AT="$cancel_at" run_calc
  [[ ! -e "$CALCULATOR_CLIPBOARD_DATA" ]] || fail "cancel stage $cancel_at copied a result"
  [[ ! -e "$CALCULATOR_NOTIFICATIONS" ]] || fail "cancel stage $cancel_at notified"
  if [[ "$cancel_at" == 1 ]]; then
    assert_eq "$history_before" "$(cat "$history_file")"
  else
    assert_eq "$(printf '2 + 3 * 4\t14')" "$(tail -n1 "$history_file")"
  fi
done

set +e
CALCULATOR_EXPRESSION='sqrt(' run_calc >/dev/null 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]] || fail 'invalid expression reported success'
[[ ! -e "$CALCULATOR_CLIPBOARD_DATA" ]] || fail 'invalid expression copied output'
[[ -s "$CALCULATOR_NOTIFICATIONS" ]] || fail 'invalid expression was not reported'
! grep -Fq 'sqrt(' "$history_file" || fail 'invalid expression was saved to history'

printf 'ok: calculator fixtures\n'

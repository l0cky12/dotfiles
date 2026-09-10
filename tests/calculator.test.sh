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
  printf '%s\n' "${CALCULATOR_EXPRESSION:-2 + 3 * 4}"
else
  printf '%s\n' "$input"
fi
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
export CALCULATOR_CLIPBOARD_ARGS="$test_root/clipboard-args"
export CALCULATOR_CLIPBOARD_DATA="$test_root/clipboard-data"
export CALCULATOR_NOTIFICATIONS="$test_root/notifications"

PATH="$test_root/bin:$PATH" HOME="$test_root" XDG_CONFIG_HOME="$test_root/config" \
  XDG_RUNTIME_DIR="$test_root/runtime" "$calculator"
assert_eq 14 "$(<"$CALCULATOR_CLIPBOARD_DATA")"
grep -Fq -- '--type text/plain' "$CALCULATOR_CLIPBOARD_ARGS" ||
  fail 'calculator did not set text/plain clipboard type'
grep -Fq -- 'Copied: 14' "$CALCULATOR_NOTIFICATIONS" ||
  fail 'calculator did not notify after copying'

for cancel_at in 1 2; do
  rm -f "$ROFI_STATE" "$CALCULATOR_CLIPBOARD_DATA" "$CALCULATOR_NOTIFICATIONS"
  ROFI_CANCEL_AT="$cancel_at" PATH="$test_root/bin:$PATH" HOME="$test_root" \
    XDG_CONFIG_HOME="$test_root/config" XDG_RUNTIME_DIR="$test_root/runtime" \
    "$calculator"
  [[ ! -e "$CALCULATOR_CLIPBOARD_DATA" ]] || fail "cancel stage $cancel_at copied a result"
  [[ ! -e "$CALCULATOR_NOTIFICATIONS" ]] || fail "cancel stage $cancel_at notified"
done

rm -f "$ROFI_STATE" "$CALCULATOR_CLIPBOARD_DATA" "$CALCULATOR_NOTIFICATIONS"
set +e
CALCULATOR_EXPRESSION='sqrt(' PATH="$test_root/bin:$PATH" HOME="$test_root" \
  XDG_CONFIG_HOME="$test_root/config" XDG_RUNTIME_DIR="$test_root/runtime" \
  "$calculator" >/dev/null 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]] || fail 'invalid expression reported success'
[[ ! -e "$CALCULATOR_CLIPBOARD_DATA" ]] || fail 'invalid expression copied output'
[[ -s "$CALCULATOR_NOTIFICATIONS" ]] || fail 'invalid expression was not reported'

printf 'ok: calculator fixtures\n'

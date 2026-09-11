#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
state="$repo_root/quickshell/.config/quickshell/BatteryState.qml"
logic="$repo_root/quickshell/.config/quickshell/battery/BatteryLogic.js"
logic_test="$repo_root/tests/battery-alerts.logic.test.js"
battery_config="$repo_root/quickshell/.config/quickshell/battery/config.json"
notification_config="$repo_root/quickshell/.config/quickshell/notifications/config.json"
smoke="$repo_root/quickshell/.config/quickshell/BatterySmoke.qml"
shell="$repo_root/quickshell/.config/quickshell/shell.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

actual='node unavailable'
if command -v node >/dev/null 2>&1; then
  actual=$(node "$logic_test" "$logic")

  expected=$'warn:20\nsevere:10\ncritical:5\nwarn:20'
  [[ "$actual" == "$expected" ]] || {
    printf 'expected alerts:\n%s\nactual alerts:\n%s\n' "$expected" "$actual" >&2
    fail 'threshold edge fixture emitted the wrong alert sequence'
  }
else
  printf 'skip: node is not installed, battery logic fixtures not run\n'
fi

python3 -m json.tool "$battery_config" >/dev/null
python3 -m json.tool "$notification_config" >/dev/null

grep -Fq '"Battery"' "$notification_config" \
  || fail 'notification service does not allow Battery to bypass DND'
grep -Fq '"-u", "critical"' "$state" \
  || fail 'battery alerts are not unconditionally critical'
grep -Fq 'boolean:swaync-bypass-dnd:true' "$state" \
  || fail 'battery alerts do not unconditionally bypass DND'
grep -Fq '"-t", "0"' "$state" \
  || fail 'battery alerts are not unconditionally persistent'
grep -Fq 'batteryState: BatteryState' "$shell" \
  || fail 'the shell does not instantiate BatteryState'

refresh_ms=$(python3 - "$state" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text()
match = re.search(
    r"readonly\s+property\s+int\s+refreshInterval\s*:\s*(\d+)\s*\*\s*(\d+)",
    source,
)
if not match:
    raise SystemExit("could not parse refreshInterval")
print(int(match.group(1)) * int(match.group(2)))
PY
) || fail 'battery reconciliation interval could not be parsed'
(( refresh_ms > 0 && refresh_ms <= 30000 )) \
  || fail 'battery poll interval exceeds the 30-second limit'

if [[ "$actual" != 'node unavailable' ]]; then
  printf 'ok: battery threshold alert fixtures (%s)\n' \
    "$(tr '\n' ',' <<<"$actual" | sed 's/,$//; s/,/, /g')"
fi

if command -v quickshell >/dev/null 2>&1; then
  smoke_log=$(mktemp)
  trap 'rm -f -- "$smoke_log"' EXIT
  BATTERY_SMOKE_TEST=1 QT_QPA_PLATFORM=offscreen \
    timeout 60 quickshell -p "$smoke" >"$smoke_log" 2>&1 || true
  grep -Fq 'ok: BatteryState logic' "$smoke_log" \
    || { sed -n '1,120p' "$smoke_log" >&2; fail 'BatterySmoke.qml did not report success'; }
  if grep -Fq 'FAIL' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail 'BatterySmoke.qml reported a failing assertion'
  fi
  printf 'ok: BatterySmoke.qml (%s assertions)\n' \
    "$(grep -c '^.*ok   ' "$smoke_log" || true)"
else
  printf 'skip: quickshell is not installed, BatterySmoke.qml not run\n'
fi

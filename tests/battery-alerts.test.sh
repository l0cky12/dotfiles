#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
state="$repo_root/quickshell/.config/quickshell/BatteryState.qml"
logic="$repo_root/quickshell/.config/quickshell/battery/BatteryLogic.js"
battery_config="$repo_root/quickshell/.config/quickshell/battery/config.json"
notification_config="$repo_root/quickshell/.config/quickshell/notifications/config.json"
smoke="$repo_root/quickshell/.config/quickshell/BatterySmoke.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v node >/dev/null 2>&1 || {
  printf 'skip: node is not installed\n'
  exit 0
}

actual=$(node - "$logic" <<'JS'
const logic = require(process.argv[2]);
const thresholds = {warn: 20, severe: 10, critical: 5};
let state = logic.initialState();
const alerts = [];

function sample(percent, powerState, hasBattery = true) {
  const result = logic.update(state, {hasBattery, percent, powerState}, thresholds);
  state = result.state;
  for (const alert of result.alerts)
    alerts.push(`${alert.level}:${alert.percent}`);
}

sample(21, "discharging");
sample(20, "discharging");
sample(19, "indeterminate"); // A transient Unknown state must not re-arm warn.
sample(19, "discharging");
sample(12, "discharging");
sample(12, "charging");      // A short charge blip clears the cycle at 12%.
sample(12, "discharging");   // It must not replay warn below its crossing.
sample(10, "discharging");
sample(5, "discharging");
sample(0, "indeterminate", false); // Missing hardware is inert.

// Charging above warn establishes a new downward crossing and discharge cycle.
sample(21, "charging");
sample(20, "discharging");

// Zero disables an individual threshold.
let disabledState = logic.initialState();
const disabled = logic.update(disabledState,
  {hasBattery: true, percent: 0, powerState: "discharging"},
  {warn: 0, severe: 0, critical: 0});
if (disabled.alerts.length !== 0)
  throw new Error("disabled thresholds emitted alerts");

process.stdout.write(alerts.join("\n") + "\n");
JS
)

expected=$'warn:20\nsevere:10\ncritical:5\nwarn:20'
[[ "$actual" == "$expected" ]] || {
  printf 'expected alerts:\n%s\nactual alerts:\n%s\n' "$expected" "$actual" >&2
  fail 'threshold edge fixture emitted the wrong alert sequence'
}

python3 -m json.tool "$battery_config" >/dev/null
python3 -m json.tool "$notification_config" >/dev/null

grep -Fq '"Battery"' "$notification_config" \
  || fail 'notification service does not allow Battery to bypass DND'

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

printf 'ok: battery threshold alert fixtures (%s)\n' \
  "$(tr '\n' ',' <<<"$actual" | sed 's/,$//; s/,/, /g')"

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

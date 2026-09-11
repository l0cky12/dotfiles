#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
state="$repo_root/quickshell/.config/quickshell/BatteryState.qml"
logic="$repo_root/quickshell/.config/quickshell/battery/BatteryLogic.js"
battery_config="$repo_root/quickshell/.config/quickshell/battery/config.json"
notification_config="$repo_root/quickshell/.config/quickshell/notifications/config.json"
shell="$repo_root/quickshell/.config/quickshell/shell.qml"

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

function sample(percent, discharging, hasBattery = true) {
  const result = logic.update(state, {hasBattery, percent, discharging}, thresholds);
  state = result.state;
  for (const alert of result.alerts)
    alerts.push(`${alert.level}:${alert.percent}`);
}

sample(21, true);
sample(20, true);
sample(19, true);
sample(19, false); // Charging/AC resets the discharge cycle.
sample(21, true);
sample(20, true);
sample(11, true);
sample(10, true);
sample(9, true);
sample(5, true);
sample(4, true);
sample(0, false, false); // Missing hardware is inert.

process.stdout.write(alerts.join("\n") + "\n");
JS
)

expected=$'warn:20\nwarn:20\nsevere:10\ncritical:5'
[[ "$actual" == "$expected" ]] || {
  printf 'expected alerts:\n%s\nactual alerts:\n%s\n' "$expected" "$actual" >&2
  fail 'threshold edge fixture emitted the wrong alert sequence'
}

python3 -m json.tool "$battery_config" >/dev/null
python3 -m json.tool "$notification_config" >/dev/null

grep -Fq '"-u", "critical"' "$state" \
  || fail 'battery sends are not critical'
grep -Fq '"-h", "boolean:swaync-bypass-dnd:true"' "$state" \
  || fail 'battery sends do not request the established DND bypass hint'
grep -Fq '"-t", "0"' "$state" \
  || fail 'battery sends do not explicitly request persistence'
grep -Fq '"Battery"' "$notification_config" \
  || fail 'notification service does not allow Battery to bypass DND'
grep -Fq 'interval: root.refreshInterval' "$state" \
  || fail 'battery reconciliation timer does not use its bounded interval'
grep -Fq 'readonly property int refreshInterval: 30 * 1000' "$state" \
  || fail 'battery poll interval exceeds or obscures the 30-second limit'
grep -Fq 'batteryState: BatteryState' "$shell" \
  || fail 'shell does not instantiate battery monitoring'

printf 'ok: battery threshold alert fixtures (%s)\n' \
  "$(tr '\n' ',' <<<"$actual" | sed 's/,$//; s/,/, /g')"

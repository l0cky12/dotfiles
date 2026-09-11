#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
state="$shell_dir/BatteryState.qml"
icon="$shell_dir/BatteryIcon.qml"
smoke="$shell_dir/BatterySmoke.qml"
bar="$shell_dir/Bar.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

grep -Fq 'import Quickshell.Services.UPower' "$state" \
  || fail 'BatteryState does not use the built-in UPower service'
grep -Fq 'refreshInterval: 30 * 1000' "$state" \
  || fail 'battery reconciliation interval is not 30 seconds'
grep -Fq 'BatteryIcon {' "$bar" || fail 'bar does not mount BatteryIcon'
grep -Fq 'Theme.critical' "$icon" \
  || fail 'critical battery does not use the theme critical token'

if grep -nE '"#[0-9a-fA-F]{3,8}"' "$state" "$icon" "$smoke"; then
  fail 'battery QML contains a hardcoded color'
fi

if command -v quickshell >/dev/null 2>&1; then
  test_root=$(mktemp -d)
  trap 'rm -rf -- "$test_root"' EXIT
  smoke_log="$test_root/smoke.log"
  QT_QPA_PLATFORM=offscreen timeout 30 quickshell -p "$smoke" >"$smoke_log" 2>&1 || true
  grep -Fq 'ok: Battery widget projections' "$smoke_log" \
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

printf 'ok: battery widget static checks\n'

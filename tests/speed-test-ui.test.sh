#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
qml_root="$repo_root/quickshell/.config/quickshell"
menu="$repo_root/menu/.config/lmenu/menu.jsonc"
test_root=$(mktemp -d -t speed-test-ui.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

grep -Fq '"id": "trigger.speedtest"' "$menu" || fail 'Trigger menu lost Speed Test'
grep -Fq '"action": "quickshell ipc call speedtest toggle"' "$menu" || fail 'Speed Test does not open the visual overlay'
grep -Fq 'target: "speedtest"' "$qml_root/Bar.qml" || fail 'speedtest IPC target is missing'
grep -Fq 'SpeedTestOverlay {' "$qml_root/Bar.qml" || fail 'per-monitor speed-test overlay is missing'
grep -Fq '[root.backend, "speed-test"]' "$qml_root/SpeedTestState.qml" || fail 'visual state does not call the existing backend'
grep -Fq 'SpeedTestState.wallpaperPath' "$qml_root/SpeedTestOverlay.qml" || fail 'overlay does not use the current wallpaper'

if grep -nE '"#[0-9a-fA-F]{3,8}"' "$qml_root/SpeedTestState.qml" \
    "$qml_root/SpeedGauge.qml" "$qml_root/SpeedTestOverlay.qml"; then
  fail 'speed-test UI bypasses the semantic theme palette'
fi

if command -v quickshell >/dev/null 2>&1; then
  QT_QPA_PLATFORM=offscreen timeout 30 quickshell -p "$qml_root/SpeedTestSmoke.qml" \
    >"$test_root/smoke.log" 2>&1 || true
  grep -Fq 'ok: SpeedTest UI logic' "$test_root/smoke.log" || {
    sed -n '1,160p' "$test_root/smoke.log" >&2
    fail 'SpeedTest state or gauge QML did not parse and run'
  }
  ! grep -Fq 'FAIL' "$test_root/smoke.log" || fail 'SpeedTest smoke test reported a failure'
fi

printf 'ok: speed-test UI fixtures\n'

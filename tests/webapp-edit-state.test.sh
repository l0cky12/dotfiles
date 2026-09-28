#!/usr/bin/env bash
# Exercise asynchronous icon discovery against a delayed, offline backend.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v quickshell >/dev/null || { echo 'skip: quickshell unavailable'; exit 0; }
test_root=$(mktemp -d -t webapp-edit-state.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/home/.config/hypr/webapp" "$test_root/runtime"
chmod 700 "$test_root/runtime"
cp "$repo_root/quickshell/.config/quickshell/WebAppState.qml" "$test_root/"
cat >"$test_root/home/.config/hypr/webapp/manager.py" <<'PY'
import json, signal, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
if sys.argv[1] == 'discover-icon':
    time.sleep(0.5)
    print(json.dumps({'ok': True, 'path': '/wrong-icon.png'}))
PY
cat >"$test_root/smoke.qml" <<'QML'
import Quickshell
import QtQuick
Scope {
  Component.onCompleted: {
    WebAppState.prefillUrl("https://old.example.com")
    edit.start()
  }
  Timer {
    id: edit
    interval: 200
    onTriggered: {
      WebAppState.startEdit({id: "keep", name: "Keep", url: "https://keep.example.com", icon: "/keep.png"})
      verify.start()
    }
  }
  Timer {
    id: verify
    interval: 900
    onTriggered: {
      const s = WebAppState
      if (s.editingId === "keep" && s.iconState === "current" && s.iconPath === "/keep.png")
        console.log("ok: stale discovery preserves edit icon")
      else
        console.log("FAIL: stale discovery overwrote edit icon: " + s.iconPath)
      Qt.quit()
    }
  }
}
QML
HOME="$test_root/home" XDG_RUNTIME_DIR="$test_root/runtime" QT_QPA_PLATFORM=offscreen \
  timeout 10 quickshell -p "$test_root/smoke.qml" >"$test_root/log" 2>&1 || true
if ! grep -Fq 'ok: stale discovery preserves edit icon' "$test_root/log"; then
  cat "$test_root/log" >&2
  exit 1
fi
echo 'ok: webapp edit state fixtures'

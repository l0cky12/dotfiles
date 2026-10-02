#!/usr/bin/env bash
# The bar's background state must come from resident watchers (desktop-mode
# watch, nmcli monitor, gdbus monitor) and IPC pokes, not from re-running status
# scripts every few seconds. Runs PollingSmoke.qml against logging stubs.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
qs_root="$repo_root/quickshell/.config/quickshell"
test_root=$(mktemp -d -t shell-polling-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v quickshell >/dev/null 2>&1 || {
  printf 'skip: quickshell is not installed\n'
  exit 0
}

home=$test_root/home
calls=$test_root/calls
mkdir -p "$home/.local/bin" "$home/.config/hypr/scripts/capture" "$test_root/bin"
: >"$calls"

# One logging stub for every helper; it answers the few calls that need output.
stub=$test_root/stub
cat >"$stub" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >>"$POLL_CALLS"
mode() { printf '{"name":"stay-awake","desired":%s,"observed":%s,"available":true,"expires_at":null,"error":null}' "$1" "$1"; }
case "${0##*/} $*" in
  'desktop-mode watch')
    printf '{"daemon":true,"settings":{},"modes":[%s]}\n' "$(mode false)"
    sleep 0.3
    printf '{"daemon":true,"settings":{},"modes":[%s]}\n' "$(mode true)"
    exec sleep 60 ;;
  'nmcli monitor'|'gdbus monitor '*)
    sleep 0.5
    printf 'state changed\n'
    exec sleep 60 ;;
  'hyprctl monitors -j') printf '[{"name":"DP-1","width":1920,"height":1080,"scale":1}]\n' ;;
  'ddcutil detect --terse') printf 'Display 1\n I2C bus: /dev/i2c-6\n DRM connector: card0-DP-1\n' ;;
  'ddcutil --bus 6 getvcp 10 --brief') printf 'VCP 10 C 50 100\n' ;;
  'cava '*) printf '50 50 50 50\n'; exec sleep 60 ;;
  'network-control status') printf '{"connectionType":"wifi"}\n' ;;
  'capture.sh record status') printf 'idle\n' ;;
  'windows-vm status --bar') printf 'off\n' ;;
esac
SH
chmod +x "$stub"
ln -s "$stub" "$home/.local/bin/desktop-mode"
ln -s "$stub" "$home/.local/bin/windows-vm"
ln -s "$stub" "$home/.config/hypr/scripts/capture/capture.sh"
ln -s "$stub" "$home/.config/hypr/scripts/bluetooth-control"
ln -s "$stub" "$test_root/bin/network-control"
for name in nmcli gdbus hyprctl ddcutil cava; do ln -s "$stub" "$test_root/bin/$name"; done

log=$test_root/smoke.log
HOME=$home PATH="$test_root/bin:$PATH" POLL_CALLS=$calls \
  NETWORK_CONTROL="$test_root/bin/network-control" QT_QPA_PLATFORM=offscreen \
  timeout 30 quickshell -p "$qs_root/PollingSmoke.qml" >"$log" 2>&1 || true
grep -Fq 'ok: polling smoke' "$log" || { sed -n '1,80p' "$log" >&2; fail 'PollingSmoke.qml did not pass'; }

count() { grep -c -- "^$1" "$calls" || true; }

# 2.5 s of runtime: the old 2 s polls would each have run twice.
[[ $(count 'desktop-mode watch') == 1 ]] || fail 'desktop-mode watch did not start exactly once'
[[ $(count 'desktop-mode status') == 0 ]] || fail 'modes still poll desktop-mode status'
[[ $(count 'capture.sh record status') == 1 ]] || fail 'record status is still polled every 2 s'
# Startup refresh plus one from the stubbed monitor event.
[[ $(count 'network-control status') == 2 ]] || fail 'nmcli monitor events do not refresh the network state'
[[ $(count 'bluetooth-control status') == 2 ]] || fail 'BlueZ signals do not refresh the Bluetooth state'
[[ $(count 'hyprctl monitors') == 1 ]] || fail 'display discovery must run once at startup without closed-panel polling'

# Real cava state against two closed-panel dependencies: the visible bar still
# needs its spectrum while music plays.
mkdir -p "$test_root/cava"
cp "$qs_root/CavaState.qml" "$test_root/cava/"
printf '%s\n' 'singleton CavaState 1.0 CavaState.qml' \
  'singleton MediaState 1.0 MediaState.qml' \
  'singleton VisualizerState 1.0 VisualizerState.qml' >"$test_root/cava/qmldir"
cat >"$test_root/cava/MediaState.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject { property bool isPlaying: true; property bool panelVisible: false }
QML
cat >"$test_root/cava/VisualizerState.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject { property bool visible: false }
QML
cat >"$test_root/cava/shell.qml" <<'QML'
import Quickshell
import QtQuick
import "."
Scope {
  readonly property var state: CavaState
  Timer {
    interval: 300; running: true
    onTriggered: {
      console.log(CavaState.available ? "ok: bar spectrum with panels closed" : "FAIL: bar spectrum stopped")
      Qt.quit()
    }
  }
}
QML
HOME=$home PATH="$test_root/bin:$PATH" POLL_CALLS=$calls QT_QPA_PLATFORM=offscreen \
  timeout 10 quickshell -p "$test_root/cava/shell.qml" >"$test_root/cava.log" 2>&1 || true
grep -Fq 'ok: bar spectrum with panels closed' "$test_root/cava.log" || \
  { cat "$test_root/cava.log" >&2; fail 'the visible bar lost its spectrum feed'; }

printf 'ok: bar state is event-driven\n'

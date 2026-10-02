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
for name in nmcli gdbus hyprctl ddcutil; do ln -s "$stub" "$test_root/bin/$name"; done

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
[[ $(count 'hyprctl monitors') == 0 ]] || fail 'display state polls monitors with its panel closed'

printf 'ok: bar state is event-driven\n'

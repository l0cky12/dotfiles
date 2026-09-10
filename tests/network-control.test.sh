#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
backend="$repo_root/hypr/.config/hypr/scripts/network-control"
panel="$repo_root/quickshell/.config/quickshell/NetworkPanel.qml"
state="$repo_root/quickshell/.config/quickshell/NetworkState.qml"
test_root=$(mktemp -d -t network-control-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert() { "$@" || fail "$*"; }
mkdir -p "$test_root/bin" "$test_root/runtime"

cat > "$test_root/bin/nmcli" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NMCLI_CALLS"
case "$*" in
  '-t -f WIFI general status') printf 'enabled\n' ;;
  '-t -f DEVICE,TYPE,STATE device status')
    if [[ ${NMCLI_WIRED_FIRST:-} == 1 ]]; then
      printf 'enp1s0:ethernet:connected\nwlp2s0:wifi:connected\n'
    else
      printf 'wlp2s0:wifi:connected\nenp1s0:ethernet:disconnected\n'
    fi
    ;;
  '-t -f DEVICE,TYPE device status') printf 'wlp2s0:wifi\nenp1s0:ethernet\n' ;;
  '-g GENERAL.TYPE device show wlp2s0')
    # NetworkManager >= 1.10 reports the short name; older releases the
    # settings name. The panel has to normalize both to "wifi".
    if [[ ${NMCLI_LEGACY_TYPES:-} == 1 ]]; then printf '802-11-wireless\n'; else printf 'wifi\n'; fi
    ;;
  '-g GENERAL.CONNECTION device show wlp2s0') printf 'Cafe;Net\n' ;;
  '-g IP4.ADDRESS device show wlp2s0') printf '192.0.2.22/24\n' ;;
  '-g IP4.GATEWAY device show wlp2s0') printf '192.0.2.1\n' ;;
  '-t -f IP4.DNS device show wlp2s0') printf 'IP4.DNS[1]:1.1.1.1\nIP4.DNS[2]:1.0.0.1\n' ;;
  '-g ipv4.method connection show Cafe;Net') printf 'auto\n' ;;
  '-t -f IN-USE,SIGNAL,SSID device wifi list ifname wlp2s0 --rescan no') printf '*:71:Cafe;Net\n' ;;
  'device wifi rescan ifname wlp2s0') : ;;
  '-t -f BSSID,SSID,SIGNAL,SECURITY device wifi list ifname wlp2s0 --rescan no') printf 'AA:BB:CC:DD:EE:FF:Open Cafe:84:--\n11:22:33:44:55:66:Secure Cafe:62:WPA2\n' ;;
  '-g 802-11-wireless.ssid connection show id Cafe;Net') printf 'Cafe;Net\n' ;;
  '-g 802-11-wireless-security.key-mgmt connection show id Cafe;Net') printf 'wpa-psk\n' ;;
  '--ask --show-secrets --get-values 802-11-wireless-security.psk connection show id Cafe;Net')
    if [[ ${NMCLI_DENY_SECRETS:-} == 1 ]]; then
      printf 'Error: NetworkManager authorization denied\n' >&2
      exit 1
    fi
    printf 'fixture:secret;\\value\n'
    ;;
  *) : ;;
esac
SH
chmod +x "$test_root/bin/nmcli"

cat > "$test_root/bin/qrencode" <<'SH'
#!/usr/bin/env bash
while (($#)); do
  if [[ $1 == -o ]]; then output=$2; shift 2; continue; fi
  shift
done
cat > "$output"
SH
chmod +x "$test_root/bin/qrencode"

export NMCLI_CALLS="$test_root/nmcli.calls"
run() { NMCLI="$test_root/bin/nmcli" QRENCODE="$test_root/bin/qrencode" XDG_RUNTIME_DIR="$test_root/runtime" "$backend" "$@"; }

# Read-only panel status deliberately exposes addresses and DNS, never a PSK.
status=$(run status)
jq -e '.wifiEnabled and .connectionType == "wifi" and .ssid == "Cafe;Net" and .signal == 71 and .ipv4 == "192.0.2.22" and .dns == ["1.1.1.1", "1.0.0.1"] and .ipv4Method == "auto"' <<<"$status" >/dev/null || fail 'status JSON omitted active connection information'
! grep -Fq 'fixture:secret' <<<"$status" || fail 'status leaked a Wi-Fi secret'
NMCLI_LEGACY_TYPES=1 run status >"$test_root/legacy-status.json" 2>&1 \
  || fail 'status failed on a legacy 802-11-wireless device type'
jq -e '.connectionType == "wifi"' "$test_root/legacy-status.json" >/dev/null \
  || fail 'status did not normalize a legacy 802-11-wireless device type'

scan=$(run scan)
jq -e 'length == 2 and .[0].ssid == "Open Cafe" and .[0].security == "--" and .[1].security == "WPA2"' <<<"$scan" >/dev/null || fail 'scan JSON did not preserve connection options'

: > "$NMCLI_CALLS"
run --dry-run dns custom '1.1.1.1 1.0.0.1' >/dev/null
run --dry-run ipv4 manual 192.0.2.44 24 192.0.2.1 '9.9.9.9' >/dev/null
! grep -E '^(connection modify|connection up|radio wifi|device disconnect|device wifi connect)' "$NMCLI_CALLS" \
  || fail 'dry-run made a NetworkManager mutation'

if run --dry-run ipv4 manual not-an-ip 24 192.0.2.1 '' >/dev/null 2>&1; then
  fail 'manual IPv4 accepted an invalid address'
fi
if run --dry-run ipv4 manual 192.0.2.44 33 192.0.2.1 '' >/dev/null 2>&1; then
  fail 'manual IPv4 accepted an invalid prefix'
fi
if run --dry-run dns custom bad.ip >/dev/null 2>&1; then
  fail 'DNS accepted an invalid address'
fi

qr_json=$(run qr)
jq -e '.ssid == "Cafe;Net" and .security == "WPA" and (.path | endswith("/wifi.svg"))' <<<"$qr_json" >/dev/null || fail 'QR output did not limit itself to metadata'
! grep -Fq 'fixture:secret' <<<"$qr_json" || fail 'QR JSON leaked a Wi-Fi secret'
qr_file=$(jq -r .path <<<"$qr_json")
[[ $(stat -c '%a' "$qr_file") == 600 ]] || fail 'QR SVG is not owner-readable only'
grep -Fq 'WIFI:T:WPA;S:Cafe\;Net;P:fixture\:secret\;\\value;;' "$qr_file" || fail 'QR payload is not standards escaped'
! grep -Fq 'fixture:secret' "$NMCLI_CALLS" || fail 'Wi-Fi secret was passed to NetworkManager as an argument'
grep -Fqx -- '--ask --show-secrets --get-values 802-11-wireless-security.psk connection show id Cafe;Net' "$NMCLI_CALLS" \
  || fail 'QR secret read did not enable NetworkManager authorization'
if NMCLI_DENY_SECRETS=1 run qr >"$test_root/denied.out" 2>"$test_root/denied.err"; then
  fail 'QR generation ignored denied NetworkManager authorization'
fi
grep -Fq 'authorization was cancelled or denied' "$test_root/denied.err" \
  || fail 'QR authorization failure did not provide an actionable error'
! grep -Fq 'fixture:secret' "$test_root/denied.out" "$test_root/denied.err" \
  || fail 'QR authorization failure leaked a Wi-Fi secret'
NMCLI_LEGACY_TYPES=1 run qr >"$test_root/legacy-qr.json" 2>&1 \
  || fail 'QR refused a legacy 802-11-wireless device type'
jq -e '.ssid == "Cafe;Net"' "$test_root/legacy-qr.json" >/dev/null \
  || fail 'QR metadata changed on a legacy 802-11-wireless device type'
NMCLI_WIRED_FIRST=1 run qr >"$test_root/wired-first-qr.json" 2>&1 \
  || fail 'QR followed the wired link instead of the connected Wi-Fi device'
jq -e '.ssid == "Cafe;Net"' "$test_root/wired-first-qr.json" >/dev/null \
  || fail 'QR shared the wrong network while a wired link was also up'

# The panel and state must remain theme-driven and must not contain a password
# input, a raw resolv.conf write, or a shell command assembled from UI text.
! sed '/^[[:space:]]*\/\//d' "$panel" "$state" | grep -nE '"#[0-9a-fA-F]{3,8}"|resolv\.conf|password|pkexec|sudo|sh", "-c' \
  || fail 'panel bypasses theme or credential boundaries'
grep -Fq 'NetworkState.applyManual' "$panel" || fail 'manual IPv4 control is not wired to the state'
grep -Fq 'NetworkState.shareWifi' "$panel" || fail 'Wi-Fi QR action is not wired to the state'
grep -Fq 'stderr: StdioCollector { id: qrErr }' "$state" || fail 'Wi-Fi QR errors are not surfaced to the panel'
grep -Fq 'root.backendError(qrErr.text)' "$state" || fail 'Wi-Fi QR errors are not cleaned up for the panel'
grep -Fq 'speedProc' "$state" || fail 'speed test is not asynchronous'
grep -Fq 'NetworkState.togglePanel(bar.focusedScreen())' "$repo_root/quickshell/.config/quickshell/Bar.qml" || fail 'network manage IPC does not open the panel'
grep -Fqx 'exec(mod .. " + CTRL + W", "manage Wi-Fi and network", "quickshell ipc call network manage")' \
  "$repo_root/hypr/.config/hypr/conf/keybindings.lua" || fail 'Lua Super+Ctrl+W binding is missing or changed'
# shellcheck disable=SC2016 # The legacy binding must contain a literal $mainMod.
grep -Fqx 'bindd = $mainMod CTRL, W, manage Wi-Fi and network, exec, quickshell ipc call network manage' \
  "$repo_root/hypr/.config/hypr/conf/keybinding.conf" || fail 'legacy Super+Ctrl+W binding is missing or changed'

if command -v quickshell >/dev/null 2>&1; then
  smoke_log="$test_root/network-smoke.log"
  QT_QPA_PLATFORM=offscreen NETWORK_CONTROL="$backend" NMCLI="$test_root/bin/nmcli" \
    timeout 30 quickshell -p "$repo_root/quickshell/.config/quickshell/NetworkSmoke.qml" >"$smoke_log" 2>&1 || true
  grep -Fq 'ok: NetworkState logic' "$smoke_log" \
    || { sed -n '1,120p' "$smoke_log" >&2; fail 'NetworkSmoke.qml did not parse and run'; }
  ! grep -Fq 'FAIL' "$smoke_log" || fail 'NetworkSmoke.qml reported a failing assertion'
fi

printf 'ok: network-control fixtures\n'

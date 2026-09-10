#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
backend="$repo_root/hypr/.config/hypr/scripts/bluetooth-control"
shell_dir="$repo_root/quickshell/.config/quickshell"
panel="$shell_dir/BluetoothPanel.qml"
state="$shell_dir/BluetoothState.qml"
smoke="$shell_dir/BluetoothSmoke.qml"
test_root=$(mktemp -d -t bluetooth-control-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s
' "$1" >&2
  exit 1
}

require_jq() {
  command -v jq >/dev/null 2>&1 || {
    printf 'skip: jq is not installed
'
    exit 0
  }
}

require_jq

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]"
}

mkdir -p "$test_root/bin"
cat > "$test_root/bin/bluetoothctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BLUETOOTH_CALLS"
case "$*" in
  show)
    if [[ "${BLUETOOTH_FIXTURE_MODE:-}" == no-controller ]]; then
      printf '%s\n' 'No default controller available'
      exit 0
    fi
    printf '%s\n' \
      'Controller AA:BB:CC:DD:EE:FF workstation [default]' \
      '        Powered: yes' \
      '        Discovering: no'
    ;;
  devices)
    printf '%s\n' \
      'Device 11:22:33:44:55:66 Quiet Headphones' \
      'Device AA:00:BB:11:CC:22 Pocket Keyboard' \
      'Device DE:AD:BE:EF:00:01 Travel Mouse'
    ;;
  'devices Paired')
    printf '%s\n' \
      'Device 11:22:33:44:55:66 Quiet Headphones' \
      'Device AA:00:BB:11:CC:22 Pocket Keyboard' \
      'Device DE:AD:BE:EF:00:01 Travel Mouse'
    ;;
  'devices Connected')
    printf '%s\n' \
      'Device 11:22:33:44:55:66 Quiet Headphones' \
      'Device AA:00:BB:11:CC:22 Pocket Keyboard'
    ;;
  'devices Trusted')
    # A BlueZ too old for this filter prints usage text instead of failing;
    # the backend has to ignore anything that is not a device line.
    if [[ "${BLUETOOTH_FIXTURE_MODE:-}" == old-bluez ]]; then
      printf '%s\n' 'Invalid argument Trusted'
      exit 0
    fi
    printf '%s\n' 'Device 11:22:33:44:55:66 Quiet Headphones'
    ;;
  paired-devices)
    printf '%s\n' 'Device 11:22:33:44:55:66 Quiet Headphones'
    ;;
  'info 11:22:33:44:55:66')
    printf '%s\n' \
      'Device 11:22:33:44:55:66 (public)' \
      '        Name: Quiet Headphones' \
      '        Icon: audio-headphones' \
      '        Paired: yes' \
      '        Trusted: yes' \
      '        Connected: yes' \
      '        Battery Percentage: 0x57 (87)'
    ;;
  'info AA:00:BB:11:CC:22')
    printf '%s\n' \
      'Device AA:00:BB:11:CC:22 (public)' \
      '        Name: Pocket Keyboard' \
      '        Icon: input-keyboard' \
      '        Trusted: no' \
      '        Connected: yes'
    ;;
  'info DE:AD:BE:EF:00:01')
    printf '%s\n' \
      'Device DE:AD:BE:EF:00:01 (public)' \
      '        Name: Travel Mouse' \
      '        Icon: input-mouse' \
      '        Trusted: no' \
      '        Connected: no'
    ;;
  *) printf 'ok\n' ;;
esac
SH
chmod +x "$test_root/bin/bluetoothctl"

cat > "$test_root/bin/upower" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "upower $*" >> "$BLUETOOTH_CALLS"
case "$*" in
  -e)
    printf '%s\n' '/org/freedesktop/UPower/devices/keyboard_dev_AA_00_BB_11_CC_22'
    ;;
  '-i /org/freedesktop/UPower/devices/keyboard_dev_AA_00_BB_11_CC_22')
    printf '%s\n' \
      '  native-path:          /org/bluez/hci0/dev_AA_00_BB_11_CC_22' \
      '  percentage:           64%'
    ;;
  *) exit 1 ;;
esac
SH
chmod +x "$test_root/bin/upower"
export BLUETOOTH_CALLS="$test_root/calls"
# Keep the device-class cache inside the fixture tree; the real one belongs to
# the live session and must not be touched by the suite.
export XDG_CACHE_HOME="$test_root/cache"

run_backend() {
  PATH="$test_root/bin:$PATH" "$backend" "$@"
}

# --- status -------------------------------------------------------------------

status=$(run_backend status)
jq -e '
  .available and .powered and (.scanning | not) and
  (.devices | length == 3) and
  (.devices[0].name == "Quiet Headphones") and
  .devices[0].paired and .devices[0].connected and (.devices[0].battery == 87) and
  .devices[1].paired and .devices[1].connected and (.devices[1].battery == 64) and
  .devices[2].paired and (.devices[2].connected | not) and
  (.devices[2].battery == null)
' <<< "$status" >/dev/null || fail 'status JSON did not describe fixture devices'

jq -e '
  (.devices[0].icon == "audio-headphones") and
  (.devices[1].icon == "input-keyboard") and
  (.devices[2].icon == "input-mouse")
' <<< "$status" >/dev/null || fail 'status JSON did not report device classes'

jq -e '
  .devices[0].trusted and
  (.devices[1].trusted | not) and (.devices[2].trusted | not)
' <<< "$status" >/dev/null || fail 'status JSON did not report trust state'

# The panel polls this every couple of seconds, so the whole device list has to
# be encoded by a single jq run rather than by two jq runs per device.
per_device_jq=$(grep -c -- '--argjson item' "$backend" || true)
[[ "$per_device_jq" -eq 0 ]] \
  || fail "status still spawns a jq per device ($per_device_jq sites)"

# --- device-class cache -------------------------------------------------------

# The first run inspects every unknown device; later runs only re-inspect the
# connected ones, which need a live battery reading anyway.
cold_info=$(grep -c '^info ' "$BLUETOOTH_CALLS")
[[ "$cold_info" -eq 3 ]] || fail "cold run made $cold_info info calls, expected 3"

: > "$BLUETOOTH_CALLS"
run_backend status > /dev/null
warm_info=$(grep -c '^info ' "$BLUETOOTH_CALLS")
[[ "$warm_info" -eq 2 ]] || fail "warm run made $warm_info info calls, expected 2"

[[ -s "$XDG_CACHE_HOME/bluetooth-control/device-icons.tsv" ]] \
  || fail 'device-class cache was not written'
grep -q $'DE:AD:BE:EF:00:01\tinput-mouse' \
  "$XDG_CACHE_HOME/bluetooth-control/device-icons.tsv" \
  || fail 'device-class cache did not record the disconnected device'

# upower is enumerated once per status run, not once per device.
upower_enumerations=$(grep -c '^upower -e$' "$BLUETOOTH_CALLS" || true)
[[ "$upower_enumerations" -le 1 ]] \
  || fail "upower was enumerated $upower_enumerations times in one status run"

# --- degraded adapters --------------------------------------------------------

unavailable=$(BLUETOOTH_FIXTURE_MODE=no-controller run_backend status)
jq -e '
  (.available | not) and (.powered | not) and
  (.devices | length == 0) and (.error == "No Bluetooth controller available")
' <<< "$unavailable" >/dev/null || fail 'missing controller was not reported safely'

old_bluez=$(BLUETOOTH_FIXTURE_MODE=old-bluez run_backend status)
jq -e '(.devices | length == 3) and .devices[0].trusted' <<< "$old_bluez" >/dev/null \
  || fail 'an unsupported "devices Trusted" filter was not ignored'

# --- commands -----------------------------------------------------------------

run_backend power off >/dev/null
assert_contains "$BLUETOOTH_CALLS" 'power off'

run_backend connect aa:00:bb:11:cc:22 >/dev/null
assert_contains "$BLUETOOTH_CALLS" 'connect AA:00:BB:11:CC:22'

run_backend pair aa:00:bb:11:cc:22 >/dev/null
assert_contains "$BLUETOOTH_CALLS" '--agent NoInputNoOutput --timeout 45 pair AA:00:BB:11:CC:22'
assert_contains "$BLUETOOTH_CALLS" 'trust AA:00:BB:11:CC:22'

run_backend trust aa:00:bb:11:cc:22 >/dev/null
assert_contains "$BLUETOOTH_CALLS" 'trust AA:00:BB:11:CC:22'
run_backend untrust aa:00:bb:11:cc:22 >/dev/null
assert_contains "$BLUETOOTH_CALLS" 'untrust AA:00:BB:11:CC:22'

: > "$BLUETOOTH_CALLS"
run_backend forget aa:00:bb:11:cc:22 >/dev/null
assert_contains "$BLUETOOTH_CALLS" 'disconnect AA:00:BB:11:CC:22'
assert_contains "$BLUETOOTH_CALLS" 'remove AA:00:BB:11:CC:22'
[[ "$(sed -n '1p' "$BLUETOOTH_CALLS")" == 'disconnect AA:00:BB:11:CC:22' ]] \
  || fail 'forget removed the device before disconnecting it'

run_backend scan 8 >/dev/null
assert_contains "$BLUETOOTH_CALLS" '--timeout 8 scan on'
run_backend scan off >/dev/null
assert_contains "$BLUETOOTH_CALLS" 'scan off'

# --- argument validation ------------------------------------------------------

for command in disconnect connect trust untrust forget pair; do
  before=$(wc -l < "$BLUETOOTH_CALLS")
  set +e
  run_backend "$command" 'not-an-address' >/dev/null 2>&1
  invalid_status=$?
  set -e
  [[ "$invalid_status" -eq 2 ]] \
    || fail "$command accepted an invalid address (status $invalid_status)"
  after=$(wc -l < "$BLUETOOTH_CALLS")
  [[ "$before" -eq "$after" ]] || fail "$command reached bluetoothctl with a bad address"
done

set +e
run_backend scan 999 >/dev/null 2>&1
scan_status=$?
set -e
[[ "$scan_status" -eq 2 ]] || fail 'an out-of-range scan duration was accepted'

# --- panel expectations -------------------------------------------------------

assert_contains "$panel" 'deviceRow.battery'
assert_contains "$panel" '" — " + deviceRow.battery + "%"'
# Every colour must come from the theme; no literal hex in the panel.
if grep -nE '"#[0-9a-fA-F]{3,8}"' "$panel" "$state"; then
  fail 'a colour is hardcoded instead of coming from Theme'
fi
# Keyboard navigation.
for binding in Keys.onUpPressed Keys.onDownPressed Keys.onReturnPressed \
               Keys.onEscapePressed Qt.Key_Home Qt.Key_End Qt.Key_Delete; do
  assert_contains "$panel" "$binding"
done
# The list must be fed by the incrementally-synced model, not a raw array.
assert_contains "$panel" 'model: BluetoothState.model'
assert_contains "$state" 'ListModel { id: deviceModel }'

# --- QML logic smoke ----------------------------------------------------------

if command -v quickshell >/dev/null 2>&1; then
  smoke_log="$test_root/smoke.log"
  QT_QPA_PLATFORM=offscreen timeout 60 quickshell -p "$smoke" > "$smoke_log" 2>&1 || true
  grep -Fq 'ok: BluetoothState logic' "$smoke_log" \
    || { sed -n '1,80p' "$smoke_log" >&2; fail 'BluetoothSmoke.qml did not report success'; }
  if grep -Fq 'FAIL' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail 'BluetoothSmoke.qml reported a failing assertion'
  fi
  printf 'ok: BluetoothSmoke.qml (%s assertions)\n' \
    "$(grep -c '^.*ok   ' "$smoke_log" || true)"
else
  printf 'skip: quickshell is not installed, BluetoothSmoke.qml not run\n'
fi

printf 'ok: bluetooth-control fixtures\n'

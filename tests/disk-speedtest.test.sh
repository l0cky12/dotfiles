#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/hypr/.local/bin/disk-speedtest"
qs="$repo_root/quickshell/.config/quickshell"
test_root=$(mktemp -d -t disk-speedtest-test.XXXXXX)
trap 'chmod -R u+w -- "$test_root" 2>/dev/null; rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || {
  printf 'skip: jq is not installed\n'
  exit 0
}

export PYTHONDONTWRITEBYTECODE=1
export HOME="$test_root/home"
export XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$test_root/bin" "$HOME" "$test_root/media/usb" "$test_root/media/usb-big" \
  "$test_root/media/cd" "$test_root/media/locked"
chmod 555 "$test_root/media/locked"
small=$((8 * 1024 * 1024))

# Stand-in udisksctl for every run: it records calls, and "mounts" by flipping
# a state file that the stand-in lsblk reads.
cat >"$test_root/bin/udisksctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$UDISKS_CALLS"
if [[ ${UDISKS_FAIL:-} == 1 ]]; then
  printf 'Error mounting /dev/sdc1: GDBus.Error:org.freedesktop.UDisks2.Error.NotAuthorizedCanObtain: Not authorized to perform operation\n' >&2
  exit 1
fi
case $1 in
  mount) mkdir -p "$MOUNT_DIR"; : >"$MOUNT_STATE" ;;
  unmount) rm -f -- "$MOUNT_STATE" ;;
esac
SH
cat >"$test_root/bin/lsblk" <<'SH'
#!/usr/bin/env bash
mountpoints='[]'
[[ ! -e $MOUNT_STATE ]] || mountpoints="[\"$MOUNT_DIR\"]"
cat <<JSON
{"blockdevices":[{"name":"sdc","path":"/dev/sdc","type":"disk","size":64023257088,
  "rm":true,"ro":false,"tran":"usb","model":"SanDisk Ultra","fstype":null,"mountpoints":[],
  "children":[{"name":"sdc1","path":"/dev/sdc1","type":"part","size":64022208512,
    "rm":true,"ro":false,"fstype":"exfat","mountpoints":$mountpoints,"fsavail":64000000000}]}]}
JSON
SH
chmod +x "$test_root/bin/"*
export UDISKS_CALLS="$test_root/udisks.calls"
export MOUNT_STATE="$test_root/mounted"
export MOUNT_DIR="$test_root/media/stick"
: >"$UDISKS_CALLS"

run() {
  UDISKS_FAIL="${UDISKS_FAIL:-}" PATH="$test_root/bin:/usr/bin" "$script" "$@"
}

# Every kind of disk the picker has to sort out. Paths under $test_root are
# real directories, so the writable checks behave as they would on a desktop.
fixture="$test_root/lsblk.json"
cat >"$fixture" <<JSON
{"blockdevices": [
  {"name": "sda", "path": "/dev/sda", "type": "disk", "size": 0, "rm": true, "tran": "usb",
   "model": "SD/MMC CRW", "fstype": null, "mountpoints": []},
  {"name": "zram0", "path": "/dev/zram0", "type": "disk", "size": 15614345216, "rm": false,
   "fstype": "swap", "mountpoints": ["[SWAP]"]},
  {"name": "sdb", "path": "/dev/sdb", "type": "disk", "size": 32000000000, "rm": "1", "tran": "usb",
   "model": "Two Partitions", "mountpoints": [], "children": [
    {"name": "sdb1", "path": "/dev/sdb1", "type": "part", "size": 1000000000, "fstype": "vfat",
     "mountpoints": ["$test_root/media/usb"], "fsavail": 1000},
    {"name": "sdb2", "path": "/dev/sdb2", "type": "part", "size": 31000000000, "fstype": "ext4",
     "mountpoints": ["$test_root/media/usb-big"], "fsavail": 5000}]},
  {"name": "sdc", "path": "/dev/sdc", "type": "disk", "size": 64023257088, "rm": true, "tran": "usb",
   "model": "SanDisk Ultra", "mountpoints": [], "children": [
    {"name": "sdc1", "path": "/dev/sdc1", "type": "part", "size": 64022208512, "fstype": "exfat",
     "mountpoints": []}]},
  {"name": "sdd", "path": "/dev/sdd", "type": "disk", "size": 700000000, "rm": true, "tran": "usb",
   "model": "Disc", "mountpoints": [], "children": [
    {"name": "sdd1", "path": "/dev/sdd1", "type": "part", "size": 700000000, "ro": true,
     "fstype": "iso9660", "mountpoints": ["$test_root/media/cd"]}]},
  {"name": "sde", "path": "/dev/sde", "type": "disk", "size": 16000000000, "rm": true, "tran": "usb",
   "model": "Root Owned", "mountpoints": [], "children": [
    {"name": "sde1", "path": "/dev/sde1", "type": "part", "size": 16000000000, "fstype": "ext4",
     "mountpoints": ["$test_root/media/locked"]}]},
  {"name": "sdf", "path": "/dev/sdf", "type": "disk", "size": 16000000000, "rm": true, "tran": "usb",
   "model": "Locked Vault", "mountpoints": [], "children": [
    {"name": "sdf1", "path": "/dev/sdf1", "type": "part", "size": 16000000000,
     "fstype": "crypto_LUKS", "mountpoints": []}]},
  {"name": "nvme1n1", "path": "/dev/nvme1n1", "type": "disk", "size": 500107862016, "tran": "nvme",
   "model": "Blank Drive", "fstype": null, "mountpoints": []},
  {"name": "nvme0n1", "path": "/dev/nvme0n1", "type": "disk", "size": 1000204886016, "rm": false,
   "tran": "nvme", "model": "WD_BLACK SN770 1TB", "mountpoints": [], "children": [
    {"name": "nvme0n1p1", "path": "/dev/nvme0n1p1", "type": "part", "size": 1073741824,
     "fstype": "vfat", "mountpoints": ["/boot"], "fsavail": 991703040},
    {"name": "nvme0n1p2", "path": "/dev/nvme0n1p2", "type": "part", "size": 999128301568,
     "fstype": "crypto_LUKS", "mountpoints": [], "children": [
      {"name": "root", "path": "/dev/mapper/root", "type": "crypt", "size": 999111524352,
       "fstype": "btrfs", "mountpoints": ["$HOME", "/"], "fsavail": 732763451392}]}]}
]}
JSON

listing=$(run --list-json --fixture "$fixture")
state() { jq -r --arg name "$1" '.disks[] | select(.name == $name) | "\(.state):\(.reason)"' <<<"$listing"; }
jq -e '[.disks[].name] | index("sda") == null and index("zram0") == null' <<<"$listing" >/dev/null ||
  fail 'empty card readers and zram were offered as disks'
jq -e '.default == "nvme0n1" and .disks[0].name == "nvme0n1" and .disks[0].system' <<<"$listing" >/dev/null ||
  fail 'the system disk is not listed first and preselected'
jq -e --arg target "$XDG_CACHE_HOME/disk-speedtest" --arg home "$HOME" \
  '.disks[0] | .target == $target and .mountpoint == $home and .encrypted and .fstype == "btrfs"' \
  <<<"$listing" >/dev/null || fail 'the system disk is not tested in the cache directory'
jq -e --arg target "$test_root/media/usb-big/.disk-speedtest" \
  '.disks[] | select(.name == "sdb") | .state == "ready" and .target == $target and .removable' \
  <<<"$listing" >/dev/null || fail 'a multi-partition drive did not use its partition with the most free space'
jq -e '.disks[] | select(.name == "sdc") | .state == "mountable" and .mountDevice == "/dev/sdc1"' \
  <<<"$listing" >/dev/null || fail 'an unmounted drive is not offered for mounting'
[[ $(state sdd) == unavailable:read-only ]] || fail 'a read-only mount was not greyed out'
[[ $(id -u) == 0 || $(state sde) == "unavailable:not writable" ]] ||
  fail 'an unwritable mount was not greyed out'
[[ $(state sdf) == "unavailable:encrypted and locked" ]] || fail 'a locked LUKS drive was not explained'
[[ $(state nvme1n1) == "unavailable:no filesystem" ]] || fail 'a blank drive was not explained'

# --fixture implies --dry-run: it plans, but never mounts and never writes.
output=$(run --fixture "$fixture")
[[ $output == "Would test nvme0n1 in $XDG_CACHE_HOME/disk-speedtest" ]] ||
  fail 'dry run did not plan the system disk test'
output=$(run --fixture "$fixture" --disk /dev/sdc --stream-json)
grep -Fqx 'Would mount /dev/sdc1 with udisksctl' <<<"$output" || fail 'dry run did not plan the mount'
grep -Fqx 'Would unmount /dev/sdc1 afterwards' <<<"$output" || fail 'dry run did not plan the unmount'
[[ ! -s $UDISKS_CALLS ]] || fail 'the fixture path called udisksctl'
[[ ! -e $XDG_CACHE_HOME/disk-speedtest ]] || fail 'the fixture path created a test directory'
if run --fixture "$fixture" --disk sdd 2>"$test_root/ro.err"; then
  fail 'a read-only disk was accepted'
fi
grep -Fq 'disk-speedtest: sdd cannot be tested: read-only' "$test_root/ro.err" ||
  fail 'a read-only disk did not explain why'
if run --fixture "$fixture" --disk nope 2>"$test_root/missing.err"; then
  fail 'an unknown disk was accepted'
fi
grep -Fq 'no disk named nope' "$test_root/missing.err" || fail 'an unknown disk did not explain why'
status=0
run --bogus 2>/dev/null || status=$?
[[ $status == 2 ]] || fail 'an unknown option did not exit with usage status 2'

# Near-full disks shrink the test file to half the free space, down to a floor.
python3 - "$script" <<'PY' || fail 'test file sizing does not follow the free-space rules'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("disk_speedtest", sys.argv[1])
spec = importlib.util.spec_from_loader("disk_speedtest", loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
GiB, MiB = 1024 ** 3, 1024 ** 2
assert module.plan_size(3 * GiB, GiB) == (GiB, False)
assert module.plan_size(GiB + 3 * MiB, GiB) == (513 * MiB, True)
try:
    module.plan_size(400 * MiB, GiB)
except module.Failure as error:
    assert str(error) == "needs 512.0 MiB free, 400.0 MiB available", error
else:
    raise AssertionError("400 MiB free was accepted")
PY

# A real, tiny benchmark in a scratch directory. A leftover file from a dead
# run is removed first, and the directory is gone afterwards.
target="$test_root/target"
mkdir -p "$target"
: >"$target/run-2147483646.bin"
stream=$(run --stream-json --target-dir "$target" --seconds 1 --max-bytes "$small" --buffered)
jq -se --argjson small "$small" '
  .[0].phase == "start" and .[0].direct == false and .[0].bytes == $small
  and (map(select(.phase == "write")) | length >= 1)
  and (map(select(.phase == "read")) | length >= 1)
  and (map(select(.phase == "random" and (.iops | type) == "number")) | length >= 1)
  and (map(.phase) | index("write") < index("read") and index("read") < index("random"))
  and .[-1].phase == "complete" and .[-1].write > 0 and .[-1].read > 0
  and .[-1].random > 0 and .[-1].iops > 0 and .[-1].latency_us > 0' <<<"$stream" >/dev/null ||
  fail 'stream mode did not emit start, write, read, random, and complete in order'
[[ ! -e $target ]] || fail 'the test file, a stale file, or the scratch directory was left behind'

output=$(run --target-dir "$target" --seconds 0.3 --max-bytes "$small")
for line in 'Write: ' 'Read: ' 'Random 4K read: ' 'Test file: 8.0 MiB, '; do
  grep -Fq "$line" <<<"$output" || fail "plain output is missing '$line'"
done

# Picking an unmounted drive mounts it through udisksctl, tests it, and
# unmounts it again. A refused mount is reported and never unmounted.
stream=$(run --stream-json --disk sdc --seconds 0.3 --max-bytes "$small" --buffered)
jq -se '.[0] == {"phase": "mount", "device": "/dev/sdc1"} and .[-1].phase == "complete"' \
  <<<"$stream" >/dev/null || fail 'an unmounted drive was not mounted before its test'
[[ $(cat "$UDISKS_CALLS") == $'mount --no-user-interaction -b /dev/sdc1\nunmount --no-user-interaction -b /dev/sdc1' ]] ||
  fail 'the drive was not mounted and unmounted exactly once'
[[ ! -e $MOUNT_DIR/.disk-speedtest ]] || fail 'the test directory was left on the drive'
: >"$UDISKS_CALLS"
if UDISKS_FAIL=1 run --stream-json --disk sdc >/dev/null 2>"$test_root/mount.err"; then
  fail 'a refused mount did not fail'
fi
grep -Fq 'could not mount /dev/sdc1: Error mounting /dev/sdc1' "$test_root/mount.err" ||
  fail 'a refused mount did not explain why'
[[ $(cat "$UDISKS_CALLS") == 'mount --no-user-interaction -b /dev/sdc1' ]] ||
  fail 'a refused mount was followed by an unmount'

# Escape in the overlay stops the process with SIGTERM; it must clean up.
target="$test_root/term"
PATH="$test_root/bin:/usr/bin" "$script" --stream-json --target-dir "$target" \
  --seconds 10 --max-bytes "$small" --buffered >"$test_root/term.out" &
pid=$!
for _ in $(seq 50); do
  grep -Fq '"phase":"write"' "$test_root/term.out" && break
  /usr/bin/sleep 0.1
done
grep -Fq '"phase":"write"' "$test_root/term.out" || fail 'the benchmark never started writing'
kill -TERM "$pid"
status=0
wait "$pid" || status=$?
[[ $status == 143 ]] || fail "SIGTERM exited with $status instead of 143"
[[ ! -e $target ]] || fail 'SIGTERM left the test file behind'

# Quickshell wiring: the menu row is the only entry point, and the QML stays
# theme-driven and unprivileged.
grep -Fq 'DiskSpeedOverlay {' "$qs/Bar.qml" || fail 'the disk overlay is not mounted'
grep -Fq 'DiskState.open(bar.focusedScreen())' "$qs/Bar.qml" || fail 'the disk IPC does not open the overlay'
grep -Fq '"action": "quickshell ipc call disk speedTest"' "$repo_root/menu/.config/lmenu/menu.jsonc" ||
  fail 'the lmenu row does not open the disk overlay'
! grep -Fq 'disk speedTest' "$repo_root/hypr/.config/hypr/conf/keybindings.lua" \
  "$repo_root/hypr/.config/hypr/conf/keybinding.conf" || fail 'the disk speed test gained a keybinding'
grep -Fq 'testProc.command = [backend, "--stream-json", "--disk", name]' "$qs/DiskState.qml" ||
  fail 'the overlay does not launch the streaming CLI'
grep -Fq 'Keys.onEscapePressed: DiskState.close()' "$qs/DiskSpeedOverlay.qml" ||
  fail 'the disk overlay cannot close with Escape'
grep -Fq 'SpeedTestGauge {' "$qs/DiskSpeedOverlay.qml" || fail 'the disk overlay does not reuse the speed-test gauge'
! sed '/^[[:space:]]*\/\//d' "$qs/DiskState.qml" "$qs/DiskSpeedOverlay.qml" |
  grep -nE '"#[0-9a-fA-F]{3,8}"|pkexec|sudo|sh", "-c' || fail 'disk QML bypasses the theme or privilege boundary'

if command -v quickshell >/dev/null 2>&1; then
  smoke_log="$test_root/disk-smoke.log"
  QT_QPA_PLATFORM=offscreen timeout 30 quickshell -p "$qs/DiskSpeedSmoke.qml" >"$smoke_log" 2>&1 || true
  grep -Fq 'ok: Disk speed test logic' "$smoke_log" ||
    { sed -n '1,120p' "$smoke_log" >&2; fail 'DiskSpeedSmoke.qml did not parse and run'; }
  ! grep -Fq 'FAIL' "$smoke_log" || fail 'DiskSpeedSmoke.qml reported a failing assertion'
fi

printf 'ok: disk speed test fixtures\n'

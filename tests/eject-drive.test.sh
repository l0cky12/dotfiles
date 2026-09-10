#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
eject_drive="$repo_root/hypr/.config/hypr/scripts/eject-drive.sh"
test_root=$(mktemp -d -t eject-drive-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || {
  printf 'skip: jq is not installed\n'
  exit 0
}


# Keybind pair stays in sync across both config dialects.
# shellcheck disable=SC2016
grep -Fq '$scriptsDir/eject-drive.sh' \
  "$repo_root/hypr/.config/hypr/conf/keybinding.conf" ||
  fail 'legacy keybinding does not run eject-drive.sh'
grep -Fq 'cfg.scripts_dir .. "/eject-drive.sh"' \
  "$repo_root/hypr/.config/hypr/conf/keybindings.lua" ||
  fail 'Lua keybinding does not run eject-drive.sh'

fixture="$test_root/lsblk.json"
cat >"$fixture" <<'EOF'
{"blockdevices":[
  {"name":"nvme0n1","rm":false,"tran":"nvme","mountpoint":null,"label":null,"size":"500G","children":[
    {"name":"nvme0n1p2","rm":false,"mountpoint":"/","label":"archroot","size":"100G"}]},
  {"name":"sda","rm":true,"tran":"usb","mountpoint":null,"label":null,"size":"32G","children":[
    {"name":"sda1","rm":true,"mountpoint":"/run/media/liam/KEY","label":"KEY","size":"32G"}]},
  {"name":"sdd","rm":"1","tran":"usb","mountpoint":null,"label":null,"size":"16G","children":[
    {"name":"sdd1","rm":"1","mountpoints":["/run/media/liam/A","/media/liam/A"],"label":null,"size":"16G"}]},
  {"name":"sdf","rm":true,"tran":"usb","mountpoint":null,"label":null,"size":"32G","children":[
    {"name":"sdf1","rm":true,"mountpoint":null,"label":null,"size":"32G","children":[
      {"name":"luks-1234","rm":true,"mountpoint":"/mnt/secure","label":null,"size":"32G"}]}]}
]}
EOF

dry_run=$("$eject_drive" --dry-run --fixture "$fixture")
grep -Fq 'Would unmount sda1 at /run/media/liam/KEY' <<<"$dry_run" ||
  fail 'dry-run did not plan the unmount of sda1'
grep -Fq 'Would unmount luks-1234 at /mnt/secure' <<<"$dry_run" ||
  fail 'dry-run did not plan the unmount of the LUKS node'
grep -cFq 'Would power off' <<<"$dry_run" ||
  fail 'dry-run did not plan a power-off'
[[ $(grep -Fc 'Would unmount sdd1' <<<"$dry_run") == 2 ]] ||
  fail 'multi-mountpoint node was not fully covered'

# Internal drives must never appear.
grep -Fq 'nvme0n1' <<<"$dry_run" && fail 'internal drive leaked into the plan'

# No drives at all.
echo '{"blockdevices":[{"name":"sda","rm":false,"mountpoint":null,"label":null,"children":[]}]}' \
  >"$fixture"
[[ $("$eject_drive" --dry-run --fixture "$fixture") == 'No mounted removable drives.' ]] ||
  fail 'empty fixture did not report no drives'

# --fixture must never reach the mutating path even without --dry-run.
out=$("$eject_drive" --fixture "$fixture")
[[ "$out" == 'No mounted removable drives.' ]] ||
  fail '--fixture without --dry-run did not stay read-only'

printf 'ok: eject-drive dry-run fixtures\n'

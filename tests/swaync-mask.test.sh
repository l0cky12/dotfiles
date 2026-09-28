#!/usr/bin/env bash
# Quickshell owns org.freedesktop.Notifications. The swaync package ships a
# D-Bus activation file for the same name, so the systemd package must keep
# swaync.service masked or the first notification at login starts SwayNC ahead
# of Quickshell. Static checks only; no systemd or D-Bus state is touched.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
unit="$repo_root/systemd/.config/systemd/user/swaync.service"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# An empty unit file is masked (systemd.unit(5)). Stow refuses the other form,
# an absolute symlink to /dev/null, so the package ships an empty file.
[[ -f $unit && ! -L $unit ]] || fail 'swaync.service is not a regular file in the systemd package'
[[ ! -s $unit ]] || fail 'swaync.service is not empty, so it does not mask the unit'

# The rollback instructions must say how to undo the mask.
grep -Fq 'rm ~/.config/systemd/user/swaync.service' "$repo_root/wiki/Notifications.md" ||
  fail 'wiki rollback does not remove the swaync mask'
grep -Fq 'rm ~/.config/systemd/user/swaync.service' "$repo_root/README.md" ||
  fail 'README rollback does not remove the swaync mask'

printf 'swaync mask: ok\n'

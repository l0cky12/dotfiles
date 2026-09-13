#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
widget="$repo_root/quickshell/.config/quickshell/UpdatesIcon.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

! grep -Fq 'opacity: (UpdatesState.updating || UpdatesState.checking) ? 0.55 : 1' "$widget" ||
  fail 'update checks still dim the Pacman indicator'

printf 'updates widget: ok\n'

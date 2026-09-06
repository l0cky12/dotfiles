#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bar="$repo_root/quickshell/.config/quickshell/Bar.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for component in \
  'ArchIcon {' \
  'WorkspacesModule {' \
  'ModeIndicators {' \
  'UpdatesIcon {' \
  'KeyboardLayoutWidget {' \
  'SystemTrayWidget {' \
  'AgentIcon {' \
  'BluetoothIcon {' \
  'NetworkIcon {' \
  'AudioIcon {' \
  'DisplayIcon {'; do
  grep -Fq "$component" "$bar" || fail "bar does not mount $component"
done

grep -Fq '"HH:mm"' "$bar" || fail 'center clock is not fixed to HH:mm'
grep -Fq 'anchors.centerIn: parent' "$bar" || fail 'clock has no centered anchor'
grep -Fq 'onDoubleClicked:' "$bar" || fail 'empty-space transparency toggle is missing'
grep -Fq 'bar.barAtBottom = true' "$bar" || fail 'downward position drag is missing'
grep -Fq 'bar.barAtBottom = false' "$bar" || fail 'upward position drag is missing'

printf 'omakub bar layout: ok\n'

#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bar="$repo_root/quickshell/.config/quickshell/Bar.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for component in \
  'WorkspacesModule {' \
  'ModeIndicators {' \
  'UpdatesIcon {' \
  'BatteryIcon {' \
  'KeyboardLayoutWidget {' \
  'AppLauncher {' \
  'AgentIcon {' \
  'BluetoothIcon {' \
  'NetworkIcon {' \
  'AudioIcon {' \
  'DisplayIcon {'; do
  grep -Fq "$component" "$bar" || fail "bar does not mount $component"
done

# The clock-anchored dashboard drawer was removed; the clock is a plain label.
for removed in \
  'DashboardPanel' \
  'DashboardState' \
  'DashTab'; do
  if grep -Fq "$removed" "$bar"; then
    fail "bar still references removed $removed"
  fi
done

grep -Fq '"h:mm AP"' "$bar" || fail 'center clock is not fixed to 12-hour h:mm AP'
grep -Fq 'anchors.centerIn: parent' "$bar" || fail 'clock has no centered anchor'
! grep -Fq 'onClicked: DashboardState.togglePanel(panel.modelData.name)' "$bar" || fail 'center clock still opens the dashboard'
awk '
  /id: clockClickGuard/ { in_guard = 1 }
  in_guard && /anchors.fill: clockLabel/ { fills_clock = 1 }
  in_guard && /acceptedButtons: Qt.LeftButton/ { accepts_left_click = 1 }
  in_guard && /^        }/ { exit }
  END { exit !(fills_clock && accepts_left_click) }
' "$bar" || fail 'center clock does not absorb clicks before they reach the bar control'
! grep -Fq 'onDoubleClicked: bar.barTransparent = !bar.barTransparent' "$bar" || fail 'empty-bar clicks still toggle transparency'
! grep -Fq 'barTransparent' "$bar" || fail 'bar retains unused transparency state'
grep -Fq 'bar.barAtBottom = true' "$bar" || fail 'downward position drag is missing'
grep -Fq 'bar.barAtBottom = false' "$bar" || fail 'upward position drag is missing'

printf 'omakub bar layout: ok\n'

#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bar="$repo_root/quickshell/.config/quickshell/Bar.qml"
island="$repo_root/quickshell/.config/quickshell/BarIsland.qml"
theme="$repo_root/quickshell/.config/quickshell/Theme.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for component in \
  'WorkspacesModule {' \
  'ModeIndicators {' \
  'BatteryIcon {' \
  'AppLauncher {' \
  'AgentIcon {' \
  'BluetoothIcon {' \
  'NetworkIcon {' \
  'AudioIcon {' \
  'ClipboardPanel {' \
  'DisplayPanel {'; do
  grep -Fq "$component" "$bar" || fail "bar does not mount $component"
done

for removed in 'UpdatesIcon {' 'KeyboardLayoutWidget {' 'WeatherForecastPopup {' \
               'ClipboardIcon {' 'DisplayIcon {'; do
  ! grep -Fq "$removed" "$bar" || fail "bar still mounts $removed"
done

awk '
  /id: trayIsland/ { in_tray = 1 }
  in_tray && /BatteryIcon \{/ { battery_in_tray = 1 }
  in_tray && /^        }/ { exit }
  END { exit !battery_in_tray }
' "$bar" || fail 'battery is not in the right tray island'
[[ $(grep -Fc 'BatteryIcon {' "$bar") == 1 ]] || fail 'bar mounts battery more than once'

# The clock-anchored dashboard drawer was removed; clicking the clock opens the calendar.
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
! grep -Fq 'barAtBottom' "$bar" || fail 'bar position is still movable'
grep -Fq 'top: true' "$bar" || fail 'bar is not pinned to the top edge'

# The bar is a transparent strip carrying floating capsules. A full-bleed fill
# anywhere on the panel would put the slab back.
grep -Fq 'color: "transparent"' "$bar" || fail 'bar strip is not transparent'
awk '
  /anchors.fill: parent/ { pending = 1; next }
  pending && /color: Theme.bg/ { found = 1 }
  { pending = 0 }
  END { exit found }
' "$bar" || fail 'bar still paints a full-bleed background behind the islands'

for grouping in \
  'BarIsland {' \
  'id: leftIsland' \
  'id: centerIsland' \
  'id: trayIsland' \
  'id: powerIsland'; do
  grep -Fq "$grouping" "$bar" || fail "bar does not group modules into $grouping"
done

# Power is deliberately not in the tray capsule: it is the only destructive
# control on the bar.
awk '
  /id: trayIsland/ { in_tray = 1 }
  in_tray && /IconButton/ { exit 1 }
  in_tray && /^        }/ { exit 0 }
' "$bar" || fail 'power button shares the tray island'

grep -Fq 'radius: height / 2' "$island" || fail 'island is not a stadium capsule'
grep -Fq 'color: Theme.bgDeep' "$island" || fail 'island colour is not theme-derived'
! grep -Eq 'color: "#[0-9a-fA-F]{3,8}"' "$island" || fail 'island hardcodes a colour instead of following the theme'

# The reserved strip has to clear the capsule on both sides, or the island
# butts against the screen edge and stops reading as floating.
grep -Fq 'barHeight: barIslandHeight + barGap * 2' "$theme" \
  || fail 'reserved bar height does not account for the gap above and below the island'

# A rotated 1920x1080 output gives a 1080px bar, too narrow for three islands
# at full scale. The old floor of 1.0 gave the bar no way to shrink into it.
! grep -Fq 'Math.max(1.0, Math.min(1.25, width / 800))' "$bar" \
  || fail 'bar scale still has a floor that cannot shrink to fit a rotated monitor'
grep -Fq 'Theme.barScaleFor(width)' "$bar" \
  || fail 'bar does not take its content scale from the shared curve'
grep -Fq 'function barScaleFor' "$theme" || fail 'theme does not define the bar scale curve'

# Backstop for when scaling down is still not enough.
grep -Fq 'anchors.horizontalCenterOffset' "$bar" \
  || fail 'clock cannot shift off centre to avoid an island collision'
grep -Fq 'collisionShift' "$bar" || fail 'bar has no island collision clamp'

printf 'omakub bar layout: ok\n'

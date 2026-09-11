pragma Singleton
import Quickshell
import Quickshell.Services.UPower
import QtQuick

Singleton {
  id: root

  readonly property var device: UPower.displayDevice
  readonly property int refreshInterval: 30 * 1000

  property bool hasBattery: false
  property int percent: 0
  property bool charging: false
  property string state: "unknown"
  property real timeToEmpty: 0
  property real timeToCharge: 0

  function stateName(deviceState) {
    switch (deviceState) {
    case UPowerDeviceState.Charging:
      return "charging"
    case UPowerDeviceState.Discharging:
      return "discharging"
    case UPowerDeviceState.Empty:
      return "empty"
    case UPowerDeviceState.FullyCharged:
      return "full"
    case UPowerDeviceState.PendingCharge:
      return "pending charge"
    case UPowerDeviceState.PendingDischarge:
      return "pending discharge"
    default:
      return "unknown"
    }
  }

  function refresh() {
    const battery = root.device
    const present = battery && battery.ready
                    && battery.isLaptopBattery && battery.isPresent
    root.hasBattery = Boolean(present)
    if (!present) {
      root.percent = 0
      root.charging = false
      root.state = "unknown"
      root.timeToEmpty = 0
      root.timeToCharge = 0
      return
    }

    root.percent = Math.max(0, Math.min(100,
                                       Math.round(battery.percentage * 100)))
    root.state = root.stateName(battery.state)
    root.charging = battery.state === UPowerDeviceState.Charging
                    || battery.state === UPowerDeviceState.PendingCharge
    root.timeToEmpty = Math.max(0, Number(battery.timeToEmpty) || 0)
    root.timeToCharge = Math.max(0, Number(battery.timeToFull) || 0)
  }

  // UPower pushes changes over D-Bus. Snapshot them immediately, with the
  // timer as a conservative reconciliation path rather than a fast poll.
  Connections {
    target: root.device
    ignoreUnknownSignals: true
    function onReadyChanged() { root.refresh() }
    function onIsPresentChanged() { root.refresh() }
    function onIsLaptopBatteryChanged() { root.refresh() }
    function onPercentageChanged() { root.refresh() }
    function onStateChanged() { root.refresh() }
    function onTimeToEmptyChanged() { root.refresh() }
    function onTimeToFullChanged() { root.refresh() }
  }

  Timer {
    interval: root.refreshInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}

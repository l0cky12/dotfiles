// Canonical battery singleton base. PR #25 must reconcile onto this file;
// powerState and the alert engine belong to #25. deviceOverride is the agreed
// fixture injection mechanism for downstream battery work.
pragma Singleton
import Quickshell
import Quickshell.Services.UPower
import QtQuick

Singleton {
  id: root

  property var deviceOverride: null
  readonly property var device: deviceOverride || UPower.displayDevice
  readonly property var devices: deviceOverride ? [] : UPower.devices.values
  readonly property int refreshInterval: 30 * 1000

  readonly property bool displayBatteryPresent: Boolean(
    device && device.type === UPowerDeviceType.Battery && device.isPresent)
  readonly property bool laptopBatteryPresent: {
    const connectedDevices = root.devices
    for (let i = 0; i < connectedDevices.length; ++i) {
      const candidate = connectedDevices[i]
      if (candidate && candidate.isLaptopBattery && candidate.isPresent)
        return true
    }
    return false
  }

  property bool hasBattery: false
  property int percent: 0
  property bool charging: false
  property bool discharging: false
  property string state: "unknown"
  property real timeToEmpty: 0
  property real timeToCharge: 0
  readonly property int criticalThreshold: 15

  onDisplayBatteryPresentChanged: root.refresh()
  onLaptopBatteryPresentChanged: root.refresh()

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
    const present = root.displayBatteryPresent || root.laptopBatteryPresent
    root.hasBattery = Boolean(present)
    if (!present || !battery || !battery.ready) {
      root.percent = 0
      root.charging = false
      root.discharging = false
      root.state = "unknown"
      root.timeToEmpty = 0
      root.timeToCharge = 0
      return
    }

    // Quickshell exposes UPower percentage as a 0..1 ratio. Do not hide a
    // source-scale regression by clamping values above 100.
    root.percent = Math.max(0, Math.round(battery.percentage * 100))
    root.state = root.stateName(battery.state)
    root.charging = battery.state === UPowerDeviceState.Charging
                    || battery.state === UPowerDeviceState.PendingCharge
    root.discharging = battery.state === UPowerDeviceState.Discharging
                       || battery.state === UPowerDeviceState.PendingDischarge
    root.timeToEmpty = root.discharging
      ? Math.max(0, Number(battery.timeToEmpty) || 0) : 0
    root.timeToCharge = root.charging
      ? Math.max(0, Number(battery.timeToFull) || 0) : 0
  }

  // UPower pushes changes over D-Bus. Snapshot them immediately, with the
  // timer as a conservative reconciliation path rather than a fast poll.
  Connections {
    target: root.device
    ignoreUnknownSignals: true
    function onReadyChanged() { root.refresh() }
    function onIsPresentChanged() { root.refresh() }
    function onTypeChanged() { root.refresh() }
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

pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import "battery" as Battery
import "battery/BatteryLogic.js" as BatteryLogic

Singleton {
  id: root

  readonly property var device: UPower.displayDevice
  readonly property int refreshInterval: 30 * 1000

  property bool hasBattery: false
  property int percent: 0
  property bool charging: false
  property bool discharging: false
  property string state: "unknown"
  property var alertState: BatteryLogic.initialState()
  property var notificationQueue: []

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

  function evaluateAlerts() {
    const result = BatteryLogic.update(root.alertState, {
      hasBattery: root.hasBattery,
      percent: root.percent,
      discharging: root.discharging
    }, {
      warn: Battery.BatteryConfig.warnPercent,
      severe: Battery.BatteryConfig.severePercent,
      critical: Battery.BatteryConfig.criticalPercent
    })
    root.alertState = result.state
    for (let i = 0; i < result.alerts.length; i++)
      root.queueAlert(result.alerts[i])
  }

  function refresh() {
    const battery = root.device
    const present = battery && battery.ready
                    && battery.isLaptopBattery && battery.isPresent
    root.hasBattery = Boolean(present)
    if (!present) {
      root.percent = 0
      root.charging = false
      root.discharging = false
      root.state = "unknown"
      root.evaluateAlerts()
      return
    }

    root.percent = Math.max(0, Math.min(100,
                                       Math.round(battery.percentage * 100)))
    root.state = root.stateName(battery.state)
    root.charging = battery.state === UPowerDeviceState.Charging
                    || battery.state === UPowerDeviceState.PendingCharge
    root.discharging = battery.state === UPowerDeviceState.Discharging
                       || battery.state === UPowerDeviceState.PendingDischarge
    root.evaluateAlerts()
  }

  function alertTitle(level) {
    if (level === "critical") return "Battery critically low"
    if (level === "severe") return "Battery very low"
    return "Battery low"
  }

  function queueAlert(alert) {
    root.notificationQueue = root.notificationQueue.concat([alert])
    root.startNextNotification()
  }

  function startNextNotification() {
    if (notifyProcess.running || root.notificationQueue.length === 0)
      return
    const alert = root.notificationQueue[0]
    notifyProcess.command = [
      "notify-send",
      "-a", "Battery",
      "-u", "critical",
      "-h", "boolean:swaync-bypass-dnd:true",
      "-t", "0",
      root.alertTitle(alert.level),
      alert.percent + "% remaining. Connect a charger."
    ]
    notifyProcess.running = true
  }

  Process {
    id: notifyProcess
    running: false
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function() {
      root.notificationQueue = root.notificationQueue.slice(1)
      Qt.callLater(root.startNextNotification)
    }
  }

  // UPower normally pushes these changes. The timer is only a conservative
  // reconciliation path and is the feature's sole scheduler.
  Connections {
    target: root.device
    ignoreUnknownSignals: true
    function onReadyChanged() { root.refresh() }
    function onIsPresentChanged() { root.refresh() }
    function onIsLaptopBatteryChanged() { root.refresh() }
    function onPercentageChanged() { root.refresh() }
    function onStateChanged() { root.refresh() }
  }

  Timer {
    interval: root.refreshInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}

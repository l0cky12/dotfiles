// Canonical battery singleton base with low-battery alert reconciliation.
pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import "battery" as Battery
import "battery/BatteryLogic.js" as BatteryLogic

Singleton {
  id: root
  property var deviceOverride: null
  readonly property var device: root.deviceOverride || UPower.displayDevice
  readonly property var devices: root.deviceOverride ? [] : UPower.devices.values
  readonly property bool fixtureMode: Boolean(Quickshell.env("BATTERY_SMOKE_TEST"))
  readonly property int refreshInterval: 30 * 1000
  readonly property bool displayBatteryPresent: Boolean(device && device.type === UPowerDeviceType.Battery && device.isPresent)
  readonly property bool laptopBatteryPresent: {
    const connectedDevices = root.devices
    for (let i = 0; i < connectedDevices.length; ++i) {
      const candidate = connectedDevices[i]
      if (candidate && candidate.isLaptopBattery && candidate.isPresent) return true
    }
    return false
  }
  property bool hasBattery: false
  property int percent: 0
  property bool charging: false
  property bool discharging: false
  property string powerState: "indeterminate"
  property string state: "unknown"
  property real timeToEmpty: 0
  property real timeToCharge: 0
  readonly property int criticalThreshold: 15
  property var alertState: BatteryLogic.initialState()
  property var alertThresholds: null
  property var notificationQueue: []
  property var fixtureCommands: []
  property bool notificationStarted: false
  property bool notificationExited: false
  readonly property bool notificationProcessRunning: notifyProcess.running
  onDisplayBatteryPresentChanged: root.refresh()
  onLaptopBatteryPresentChanged: root.refresh()

  function stateName(deviceState) {
    switch (deviceState) {
    case UPowerDeviceState.Charging: return "charging"
    case UPowerDeviceState.Discharging: return "discharging"
    case UPowerDeviceState.Empty: return "empty"
    case UPowerDeviceState.FullyCharged: return "full"
    case UPowerDeviceState.PendingCharge: return "pending charge"
    case UPowerDeviceState.PendingDischarge: return "pending discharge"
    default: return "unknown"
    }
  }
  function currentThresholds() { return {warn: Battery.BatteryConfig.warnPercent, severe: Battery.BatteryConfig.severePercent, critical: Battery.BatteryConfig.criticalPercent} }
  function evaluateAlerts() {
    if (!Battery.BatteryConfig.loaded) return
    const result = BatteryLogic.update(root.alertState, {hasBattery: root.hasBattery, percent: root.percent, powerState: root.powerState, onBattery: root.fixtureMode && root.deviceOverride ? root.discharging : UPower.onBattery}, root.currentThresholds())
    root.alertState = result.state
    for (let i = 0; i < result.alerts.length; ++i) root.queueAlert(result.alerts[i])
  }
  function applyConfigChange() {
    if (!Battery.BatteryConfig.loaded) return
    const next = root.currentThresholds()
    if (root.alertThresholds !== null) root.alertState = BatteryLogic.rearmChanged(root.alertState, root.alertThresholds, next)
    root.alertThresholds = next
    root.evaluateAlerts()
  }
  function refresh() {
    if (root.fixtureMode && !root.deviceOverride) return
    const battery = root.device
    const present = battery && battery.ready && (root.displayBatteryPresent || root.laptopBatteryPresent || (root.fixtureMode && root.deviceOverride && battery.isPresent))
    root.hasBattery = Boolean(present)
    if (!present) {
      root.percent = 0; root.charging = false; root.discharging = false
      root.powerState = "indeterminate"; root.state = "unknown"
      root.timeToEmpty = 0; root.timeToCharge = 0
      root.evaluateAlerts()
      return
    }
    // Quickshell exposes UPower percentage as a 0..1 ratio. Do not hide a
    // source-scale regression by clamping values above 100.
    root.percent = Math.max(0, Math.round(battery.percentage * 100))
    root.state = root.stateName(battery.state)
    root.charging = battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.PendingCharge
    root.discharging = battery.state === UPowerDeviceState.Discharging || battery.state === UPowerDeviceState.PendingDischarge
    root.timeToEmpty = root.discharging ? Math.max(0, Number(battery.timeToEmpty) || 0) : 0
    root.timeToCharge = root.charging ? Math.max(0, Number(battery.timeToFull) || 0) : 0
    const onBattery = root.fixtureMode && root.deviceOverride ? root.discharging : UPower.onBattery
    root.powerState = root.charging || battery.state === UPowerDeviceState.FullyCharged || onBattery === false ? "charging" : (root.discharging || onBattery === true ? "discharging" : "indeterminate")
    root.evaluateAlerts()
  }
  function alertTitle(level) { if (level === "critical") return "Battery critically low"; if (level === "severe") return "Battery very low"; return "Battery low" }
  function queueAlert(alert) { root.notificationQueue = root.notificationQueue.concat([alert]); root.startNextNotification() }
  function notificationCommand(alert) { return ["notify-send", "-a", "Battery", "-u", "critical", "-h", "boolean:swaync-bypass-dnd:true", "-t", "0", root.alertTitle(alert.level), alert.percent + "% remaining. Connect a charger."] }
  function finishNotification(succeeded, reason) { if (root.notificationQueue.length === 0) return; if (!succeeded) console.warn("battery: notify-send failed" + (reason ? ": " + reason : "")); root.notificationQueue = root.notificationQueue.slice(1) }
  function startNextNotification() {
    if (notifyProcess.running || root.notificationQueue.length === 0) return
    const command = root.notificationCommand(root.notificationQueue[0])
    root.notificationStarted = false; root.notificationExited = false
    if (root.fixtureMode) { root.fixtureCommands = root.fixtureCommands.concat([command]); return }
    notifyProcess.command = command; notifyProcess.running = true
  }
  Process {
    id: notifyProcess
    running: false
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onStarted: root.notificationStarted = true
    onExited: function(code) { root.notificationExited = true; root.finishNotification(code === 0, "exit code " + code) }
    onRunningChanged: { if (running) return; if (!root.notificationExited && !root.notificationStarted) root.finishNotification(false, "failed to start"); root.notificationStarted = false; root.notificationExited = false; Qt.callLater(root.startNextNotification) }
  }
  Connections {
    target: root.device
    ignoreUnknownSignals: true
    function onReadyChanged() { root.refresh() }
    function onIsPresentChanged() { root.refresh() }
    function onIsLaptopBatteryChanged() { root.refresh() }
    function onTypeChanged() { root.refresh() }
    function onPercentageChanged() { root.refresh() }
    function onStateChanged() { root.refresh() }
    function onTimeToEmptyChanged() { root.refresh() }
    function onTimeToFullChanged() { root.refresh() }
  }
  Connections {
    target: Battery.BatteryConfig
    function onLoadedChanged() { root.applyConfigChange() }
    function onValuesChanged() { root.applyConfigChange() }
  }
  Timer { interval: root.refreshInterval; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}

import Quickshell
import Quickshell.Services.UPower
import QtQuick
import "battery" as Battery

// One headless harness: ordinary runs cover widget projections; fixture-mode
// runs cover the alert engine without starting notify-send.
Scope {
  id: smoke
  property int failures: 0
  readonly property bool fixtureMode: Boolean(Quickshell.env("BATTERY_SMOKE_TEST"))
  readonly property var state: BatteryState
  QtObject { id: readyDevice; property bool ready: true; property bool isLaptopBattery: false; property bool isPresent: true; property int type: UPowerDeviceType.Battery; property real percentage: 0.54; property int state: UPowerDeviceState.Discharging; property real timeToEmpty: 5400; property real timeToFull: 2700; property real energy: 26.2; property real energyCapacity: 48.5; property real changeRate: 13.3 }
  QtObject { id: notReadyDevice; property bool ready: false; property bool isLaptopBattery: false; property bool isPresent: false; property int type: UPowerDeviceType.Battery; property real percentage: 0.88; property int state: UPowerDeviceState.Charging; property real timeToEmpty: 0; property real timeToFull: 1800 }
  QtObject { id: fakeDevice; property bool ready: true; property bool isLaptopBattery: true; property bool isPresent: true; property real percentage: 0.42; property int state: UPowerDeviceState.Charging }
  // The icon needs a visible parent. Qt reports effective visibility, so a
  // parentless Item reads back as invisible once the scene settles no matter
  // what its own binding says, which would make both visibility assertions
  // below depend on startup ordering rather than on hasBattery.
  Item { id: iconHost; visible: true; BatteryIcon { id: batteryIcon } }
  BatteryPanelContent { id: batteryPanel; width: Theme.fs(320) }
  function check(name, condition) { if (condition) console.log("ok   " + name); else { console.log("FAIL " + name); ++smoke.failures } }
  function checkStateNames() {
    check("unknown state maps correctly", state.stateName(UPowerDeviceState.Unknown) === "unknown")
    check("charging state maps correctly", state.stateName(UPowerDeviceState.Charging) === "charging")
    check("discharging state maps correctly", state.stateName(UPowerDeviceState.Discharging) === "discharging")
    check("empty state maps correctly", state.stateName(UPowerDeviceState.Empty) === "empty")
    check("fully charged state maps correctly", state.stateName(UPowerDeviceState.FullyCharged) === "full")
    check("pending charge state maps correctly", state.stateName(UPowerDeviceState.PendingCharge) === "pending charge")
    check("pending discharge state maps correctly", state.stateName(UPowerDeviceState.PendingDischarge) === "pending discharge")
    check("supply state maps full", state.supplyStateFor(UPowerDeviceState.FullyCharged) === "full")
    check("supply state maps charging", state.supplyStateFor(UPowerDeviceState.Charging) === "charging")
    check("supply state maps pending charge to idle", state.supplyStateFor(UPowerDeviceState.PendingCharge) === "idle")
    check("supply state maps discharging", state.supplyStateFor(UPowerDeviceState.Discharging) === "discharging")
    check("supply state maps pending discharge to discharging", state.supplyStateFor(UPowerDeviceState.PendingDischarge) === "discharging")
    check("supply state maps empty", state.supplyStateFor(UPowerDeviceState.Empty) === "empty")
    check("supply state maps unknown", state.supplyStateFor(UPowerDeviceState.Unknown) === "unknown")
  }
  Component.onCompleted: { if (fixtureMode) { state.deviceOverride = fakeDevice; alertTimer.start() } else runWidgetStart() }
  function runWidgetStart() {
    checkStateNames(); state.deviceOverride = readyDevice; state.refresh()
    check("ready display battery is present", state.hasBattery)
    check("percentage ratio is converted and rounded", state.percent === 54)
    check("discharging projection is true", state.discharging && !state.charging)
    check("discharge estimate is projected only while discharging", state.timeToEmpty === 5400 && state.timeToCharge === 0)
    check("battery is visible when present", batteryIcon.visible)
    check("percentage is projected", batteryIcon.percentText === "54%")
    check("energy figures are projected", state.energy === 26.2 && state.energyCapacity === 48.5)
    check("instantaneous rate is projected", state.changeRate === 13.3)
    check("discharging maps to a discharging supply state", state.supplyState === "discharging")
    check("panel percentage is projected", batteryPanel.percentText === "54%")
    check("panel discharge estimate is spaced out", batteryPanel.supplyLine === "On battery · 1 h 30 min left")
    check("panel power tile reports outflow", batteryPanel.powerFlowing && batteryPanel.powerPrimary === "13.3 W" && batteryPanel.powerSecondary === "coming out")
    check("panel charge tile reports energy against full capacity", batteryPanel.chargeKnown && batteryPanel.chargePrimary === "26.2 Wh" && batteryPanel.chargeSecondary === "of 48.5 Wh full")
    check("non-finite estimates yield no duration", batteryPanel.formatDuration(Number.NaN) === "")
    check("non-finite estimates read as estimating", batteryPanel.estimateOr(Number.NaN, " left") === "estimating")
    check("whole hours omit the minutes", batteryPanel.formatDuration(7200) === "2 h")
    check("sub-hour estimates omit the hours", batteryPanel.formatDuration(1500) === "25 min")
    check("tiles split the panel width", batteryPanel.tileWidth > 0 && batteryPanel.tileWidth < batteryPanel.width / 2)
    readyDevice.percentage = 0.42; Qt.callLater(continueWidget)
  }
  function continueWidget() {
    check("percentage change signal updates the projection", state.percent === 42); readyDevice.percentage = 0.54
    readyDevice.state = UPowerDeviceState.Charging; state.refresh(); check("charging projection is true", state.charging && !state.discharging); check("charge estimate is projected only while charging", state.timeToCharge === 2700 && state.timeToEmpty === 0); check("panel charge estimate uses time to full", batteryPanel.supplyLine === "Charging · 45 min to full"); check("panel power tile reports inflow", batteryPanel.powerSecondary === "going in")
    readyDevice.state = UPowerDeviceState.PendingDischarge; state.refresh(); check("pending discharge projects as discharging", state.discharging && !state.charging && state.timeToEmpty === 5400 && state.timeToCharge === 0); check("pending discharge reads as on battery", state.supplyState === "discharging")
    // The alert engine rearms off powerState === "charging" and must keep
    // treating PendingCharge as charging; the readout must not, because
    // PendingCharge is the kernel's "Not charging".
    readyDevice.state = UPowerDeviceState.PendingCharge; state.refresh(); check("pending charge still counts as charging for alerts", state.charging && state.powerState === "charging"); check("pending charge reads as plugged in and idle", state.supplyState === "idle" && batteryPanel.supplyLine === "Plugged in · Not charging")
    readyDevice.state = UPowerDeviceState.FullyCharged; state.refresh(); check("panel omits an estimate when full", state.supplyState === "full" && batteryPanel.supplyLine === "Plugged in · Fully charged")
    readyDevice.changeRate = 0; state.refresh(); check("a settled charger reads as a real zero, not missing data", !batteryPanel.powerFlowing && batteryPanel.powerPrimary === "0.0 W" && batteryPanel.powerSecondary === "no flow")
    readyDevice.energyCapacity = 0; state.refresh(); check("unknown capacity is not reported as full", !batteryPanel.chargeKnown && batteryPanel.chargeSecondary === "capacity unknown")
    readyDevice.changeRate = 13.3; readyDevice.energyCapacity = 48.5
    readyDevice.state = UPowerDeviceState.Unknown; state.refresh(); check("unknown state does not invent an AC state", state.supplyState === "unknown" && batteryPanel.supplyLine === "Unknown" && state.timeToEmpty === 0 && state.timeToCharge === 0)
    readyDevice.percentage = 0.15; state.refresh(); check("shared threshold marks low charge critical regardless of state", state.criticalThreshold === 15 && !state.discharging && batteryIcon.critical)
    readyDevice.state = UPowerDeviceState.Empty; readyDevice.percentage = 0.54; state.refresh(); check("empty state is critical regardless of discharge projection", !state.discharging && batteryIcon.critical)
    readyDevice.state = UPowerDeviceState.Discharging; readyDevice.percentage = 1.01; state.refresh(); check("percentage scale mismatches remain visible", state.percent === 101); check("high discharging charge does not use the full glyph", batteryIcon.glyph !== batteryIcon.glyphFor(0, "full", false))
    state.deviceOverride = notReadyDevice; state.refresh(); Qt.callLater(finishWidget)
  }
  function finishWidget() { timeoutTimer.stop(); check("not-ready device is absent", !state.hasBattery); check("absent battery icon is invisible", !batteryIcon.visible); check("absent battery clears the energy projections", state.energy === 0 && state.energyCapacity === 0 && state.changeRate === 0 && state.supplyState === "unknown"); finish("ok: Battery widget projections") }
  function runAlert() {
    const engine = state
    check("alert engine is instantiated", engine.alertState !== undefined && typeof engine.evaluateAlerts === "function")
    check("stateName resolves UPower charging", engine.stateName(UPowerDeviceState.Charging) === "charging"); check("stateName resolves UPower discharging", engine.stateName(UPowerDeviceState.Discharging) === "discharging"); check("stateName resolves UPower empty", engine.stateName(UPowerDeviceState.Empty) === "empty"); check("stateName resolves UPower fully charged", engine.stateName(UPowerDeviceState.FullyCharged) === "full"); check("stateName resolves UPower pending charge", engine.stateName(UPowerDeviceState.PendingCharge) === "pending charge"); check("stateName resolves UPower pending discharge", engine.stateName(UPowerDeviceState.PendingDischarge) === "pending discharge")
    check("BatteryConfig loaded config.json", Battery.BatteryConfig.warnPercent === 20 && Battery.BatteryConfig.severePercent === 10 && Battery.BatteryConfig.criticalPercent === 5)
    const fallback = Battery.BatteryConfig.validatedValues({warnPercent: 5, severePercent: 10, criticalPercent: 20}); check("misordered thresholds fall back to defaults", fallback.warnPercent === 20 && fallback.severePercent === 10 && fallback.criticalPercent === 5)
    const equal = Battery.BatteryConfig.validatedValues({warnPercent: 10, severePercent: 10, criticalPercent: 5}); check("equal thresholds fall back to defaults", equal.warnPercent === 20 && equal.severePercent === 10 && equal.criticalPercent === 5)
    const disabled = Battery.BatteryConfig.validatedValues({warnPercent: 0, severePercent: 10, criticalPercent: 5}); check("zero disables an individual threshold", disabled.warnPercent === 0 && disabled.severePercent === 10 && disabled.criticalPercent === 5)
    engine.refresh(); fakeDevice.percentage = 0.37; Qt.callLater(finishAlert)
  }
  function finishAlert() {
    check("Connections percentage handler refreshes state", state.percent === 37)
    const command = state.notificationCommand({level: "critical", percent: 5}); check("notify command executable and app name", command[0] === "notify-send" && command[1] === "-a" && command[2] === "Battery"); check("notify command is critical", command[3] === "-u" && command[4] === "critical"); check("notify command bypasses DND", command[5] === "-h" && command[6] === "boolean:swaync-bypass-dnd:true"); check("notify command is persistent", command[7] === "-t" && command[8] === "0"); check("notify command contains title and body", command[9] === "Battery critically low" && command[10] === "5% remaining. Connect a charger.")
    state.notificationQueue = []; state.fixtureCommands = []; fakeDevice.state = UPowerDeviceState.Discharging; fakeDevice.percentage = 0.20; state.refresh(); check("fake discharging device queues warning", state.notificationQueue.length === 1 && state.fixtureCommands.length === 1 && state.fixtureCommands[0][9] === "Battery low"); check("fixture mode never starts notification Process", !state.notificationStarted && !state.notificationProcessRunning); finish("ok: BatteryState logic")
  }
  function finish(success) { console.log(smoke.failures === 0 ? success : ("FAIL: " + smoke.failures + " assertion(s) failed")); exitTimer.start() }
  Timer { id: alertTimer; interval: 50; running: false; repeat: true; onTriggered: { if (Battery.BatteryConfig.loaded) { stop(); runAlert() } } }
  Timer { id: timeoutTimer; interval: 1000; running: true; onTriggered: { console.log("FAIL Battery smoke test timed out"); Qt.quit() } }
  Timer { id: exitTimer; interval: 250; onTriggered: Qt.quit() }
}

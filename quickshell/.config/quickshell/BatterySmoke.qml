import Quickshell
import Quickshell.Services.UPower
import QtQuick

// Headless behavior harness. It drives the real singleton with fixture UPower
// devices, so projections and the bar's invisible-child layout are covered
// without depending on a battery, UPower daemon, or compositor.
Scope {
  id: smoke
  property int failures: 0
  property real widthWithBattery: 0

  readonly property var state: BatteryState

  QtObject {
    id: readyDevice
    property bool ready: true
    property bool isLaptopBattery: true
    property bool isPresent: true
    property real percentage: 0.54
    property int state: UPowerDeviceState.Discharging
    property real timeToEmpty: 5400
    property real timeToFull: 2700
  }

  QtObject {
    id: notReadyDevice
    property bool ready: false
    property bool isLaptopBattery: true
    property bool isPresent: true
    property real percentage: 0.88
    property int state: UPowerDeviceState.Charging
    property real timeToEmpty: 0
    property real timeToFull: 1800
  }

  Row {
    id: baselineBar
    spacing: 3
    Rectangle { implicitWidth: 20; implicitHeight: 10 }
  }

  Row {
    id: barWithBattery
    spacing: 3
    Rectangle { implicitWidth: 20; implicitHeight: 10 }
    BatteryIcon { id: absentIcon }
  }

  function check(name, condition) {
    if (condition)
      console.log("ok   " + name)
    else {
      console.log("FAIL " + name)
      smoke.failures += 1
    }
  }

  function checkStateNames() {
    check("unknown state maps correctly",
          state.stateName(UPowerDeviceState.Unknown) === "unknown")
    check("charging state maps correctly",
          state.stateName(UPowerDeviceState.Charging) === "charging")
    check("discharging state maps correctly",
          state.stateName(UPowerDeviceState.Discharging) === "discharging")
    check("empty state maps correctly",
          state.stateName(UPowerDeviceState.Empty) === "empty")
    check("fully charged state maps correctly",
          state.stateName(UPowerDeviceState.FullyCharged) === "full")
    check("pending charge state maps correctly",
          state.stateName(UPowerDeviceState.PendingCharge) === "pending charge")
    check("pending discharge state maps correctly",
          state.stateName(UPowerDeviceState.PendingDischarge)
          === "pending discharge")
  }

  Component.onCompleted: {
    checkStateNames()
    check("alert extension surface is available",
          state.alertState !== undefined
          && state.notificationQueue !== undefined
          && typeof state.evaluateAlerts === "function")

    state.device = readyDevice
    state.refresh()
    check("ready laptop battery is present", state.hasBattery)
    check("percentage ratio is converted and rounded", state.percent === 54)
    check("discharging projection is true",
          state.discharging && !state.charging)
    check("discharge estimate is projected only while discharging",
          state.timeToEmpty === 5400 && state.timeToCharge === 0)
    check("battery is visible when present", absentIcon.visible)
    check("percentage is projected", absentIcon.percentText === "54%")
    check("discharge estimate is formatted",
          absentIcon.tooltipText.indexOf("Time remaining: 1h 30m") !== -1)
    check("non-finite estimates are safe",
          absentIcon.formatTime(Number.NaN) === "estimating")
    smoke.widthWithBattery = barWithBattery.implicitWidth

    readyDevice.state = UPowerDeviceState.Charging
    state.refresh()
    check("charging projection is true", state.charging && !state.discharging)
    check("charge estimate is projected only while charging",
          state.timeToCharge === 2700 && state.timeToEmpty === 0)
    check("charging tooltip uses time to full",
          absentIcon.tooltipText.indexOf("Time to full: 45m") !== -1)

    readyDevice.state = UPowerDeviceState.PendingDischarge
    state.refresh()
    check("pending discharge projects as discharging",
          state.discharging && !state.charging
          && state.timeToEmpty === 5400 && state.timeToCharge === 0)

    readyDevice.state = UPowerDeviceState.FullyCharged
    state.refresh()
    check("full tooltip omits an estimate",
          absentIcon.tooltipText === "54% · Full")

    readyDevice.state = UPowerDeviceState.Unknown
    state.refresh()
    check("inactive AC tooltip omits an estimate",
          absentIcon.tooltipText === "54% · On AC"
          && state.timeToEmpty === 0 && state.timeToCharge === 0)

    readyDevice.state = UPowerDeviceState.Discharging
    readyDevice.percentage = 0.15
    state.refresh()
    check("shared threshold marks a discharging battery critical",
          state.criticalThreshold === 15 && absentIcon.critical)

    state.device = notReadyDevice
    state.refresh()
    Qt.callLater(smoke.finish)
  }

  function finish() {
    check("not-ready device is absent", !state.hasBattery)
    check("absent battery icon is invisible", !absentIcon.visible)
    check("absent icon leaves bar width unchanged",
          smoke.widthWithBattery > baselineBar.implicitWidth
          && barWithBattery.implicitWidth === baselineBar.implicitWidth)

    console.log(smoke.failures === 0
      ? "ok: Battery widget projections"
      : ("FAIL: " + smoke.failures + " assertion(s) failed"))
    Qt.callLater(Qt.quit)
  }

  Timer {
    interval: 1000
    running: true
    onTriggered: {
      console.log("FAIL Battery smoke test timed out")
      Qt.quit()
    }
  }
}

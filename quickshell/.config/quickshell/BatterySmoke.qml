import Quickshell
import Quickshell.Services.UPower
import QtQuick

// Headless behavior harness. It drives the real singleton with fixture UPower
// devices, so projections and icon visibility are covered without depending
// on a battery, UPower daemon, compositor, or window-backed item polish.
Scope {
  id: smoke
  property int failures: 0

  readonly property var state: BatteryState

  QtObject {
    id: readyDevice
    property bool ready: true
    property bool isLaptopBattery: false
    property bool isPresent: true
    property int type: UPowerDeviceType.Battery
    property real percentage: 0.54
    property int state: UPowerDeviceState.Discharging
    property real timeToEmpty: 5400
    property real timeToFull: 2700
  }

  QtObject {
    id: notReadyDevice
    property bool ready: false
    property bool isLaptopBattery: false
    property bool isPresent: false
    property int type: UPowerDeviceType.Battery
    property real percentage: 0.88
    property int state: UPowerDeviceState.Charging
    property real timeToEmpty: 0
    property real timeToFull: 1800
  }

  BatteryIcon { id: batteryIcon }

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
    state.deviceOverride = readyDevice
    state.refresh()
    check("ready display battery is present", state.hasBattery)
    check("percentage ratio is converted and rounded", state.percent === 54)
    check("discharging projection is true",
          state.discharging && !state.charging)
    check("discharge estimate is projected only while discharging",
          state.timeToEmpty === 5400 && state.timeToCharge === 0)
    check("battery is visible when present", batteryIcon.visible)
    check("percentage is projected", batteryIcon.percentText === "54%")
    check("discharge estimate is formatted",
          batteryIcon.tooltipText.indexOf("Time remaining: 1h 30m") !== -1)
    check("non-finite estimates are safe",
          batteryIcon.formatTime(Number.NaN) === "estimating")

    // Exercise the UPower signal path. The continuation observes the
    // projection without calling refresh(), well before the 30s poll.
    readyDevice.percentage = 0.42
    Qt.callLater(smoke.continueAfterPercentagePush)
  }

  function continueAfterPercentagePush() {
    check("percentage change signal updates the projection",
          state.percent === 42)
    readyDevice.percentage = 0.54

    readyDevice.state = UPowerDeviceState.Charging
    state.refresh()
    check("charging projection is true", state.charging && !state.discharging)
    check("charge estimate is projected only while charging",
          state.timeToCharge === 2700 && state.timeToEmpty === 0)
    check("charging tooltip uses time to full",
          batteryIcon.tooltipText.indexOf("Time to full: 45m") !== -1)

    readyDevice.state = UPowerDeviceState.PendingDischarge
    state.refresh()
    check("pending discharge projects as discharging",
          state.discharging && !state.charging
          && state.timeToEmpty === 5400 && state.timeToCharge === 0)

    readyDevice.state = UPowerDeviceState.FullyCharged
    state.refresh()
    check("full tooltip omits an estimate",
          batteryIcon.tooltipText === "54% · Full")

    readyDevice.state = UPowerDeviceState.Unknown
    state.refresh()
    check("unknown tooltip does not invent an AC state",
          batteryIcon.tooltipText === "54% · Unknown"
          && state.timeToEmpty === 0 && state.timeToCharge === 0)

    readyDevice.state = UPowerDeviceState.Unknown
    readyDevice.percentage = 0.15
    state.refresh()
    check("shared threshold marks low charge critical regardless of state",
          state.criticalThreshold === 15 && !state.discharging
          && batteryIcon.critical)

    readyDevice.state = UPowerDeviceState.Empty
    readyDevice.percentage = 0.54
    state.refresh()
    check("empty state is critical regardless of discharge projection",
          !state.discharging && batteryIcon.critical)

    readyDevice.state = UPowerDeviceState.Discharging
    readyDevice.percentage = 1.01
    state.refresh()
    check("percentage scale mismatches remain visible", state.percent === 101)
    check("high discharging charge does not use the full glyph",
          batteryIcon.glyph !== batteryIcon.glyphFor(0, "full", false))

    state.deviceOverride = notReadyDevice
    state.refresh()
    Qt.callLater(smoke.finish)
  }

  function finish() {
    timeoutTimer.stop()
    check("not-ready device is absent", !state.hasBattery)
    check("absent battery icon is invisible", !batteryIcon.visible)

    console.log(smoke.failures === 0
      ? "ok: Battery widget projections"
      : ("FAIL: " + smoke.failures + " assertion(s) failed"))
    exitTimer.start()
  }

  Timer {
    id: timeoutTimer
    interval: 1000
    running: true
    onTriggered: {
      console.log("FAIL Battery smoke test timed out")
      Qt.quit()
    }
  }

  Timer {
    id: exitTimer
    interval: 250
    onTriggered: Qt.quit()
  }
}

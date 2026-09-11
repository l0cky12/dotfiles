import Quickshell
import Quickshell.Services.UPower
import QtQuick
import "battery" as Battery

// Headless parse/instantiation and behavior harness. It never starts a Process
// or sends a notification; command construction is exercised as a pure value.
Scope {
  id: smoke

  readonly property var alertEngine: BatteryState
  property int failures: 0

  QtObject {
    id: fakeDevice
    property bool ready: true
    property bool isLaptopBattery: true
    property bool isPresent: true
    property real percentage: 0.42
    property int state: UPowerDeviceState.Charging
  }

  Component.onCompleted: BatteryState.deviceOverride = fakeDevice

  function check(name, condition) {
    if (condition)
      console.log("ok   " + name)
    else {
      console.log("FAIL " + name)
      smoke.failures += 1
    }
  }

  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (!Battery.BatteryConfig.loaded)
        return
      stop()

      const state = smoke.alertEngine
      check("alert engine is instantiated",
            state.alertState !== undefined && typeof state.evaluateAlerts === "function")
      check("stateName resolves UPower charging",
            state.stateName(UPowerDeviceState.Charging) === "charging")
      check("stateName resolves UPower discharging",
            state.stateName(UPowerDeviceState.Discharging) === "discharging")
      check("stateName resolves UPower empty",
            state.stateName(UPowerDeviceState.Empty) === "empty")
      check("stateName resolves UPower fully charged",
            state.stateName(UPowerDeviceState.FullyCharged) === "full")
      check("stateName resolves UPower pending charge",
            state.stateName(UPowerDeviceState.PendingCharge) === "pending charge")
      check("stateName resolves UPower pending discharge",
            state.stateName(UPowerDeviceState.PendingDischarge) === "pending discharge")

      check("BatteryConfig loaded config.json",
            Battery.BatteryConfig.warnPercent === 20
            && Battery.BatteryConfig.severePercent === 10
            && Battery.BatteryConfig.criticalPercent === 5)
      const fallback = Battery.BatteryConfig.validatedValues({
        warnPercent: 5, severePercent: 10, criticalPercent: 20
      })
      check("misordered thresholds fall back to defaults",
            fallback.warnPercent === 20 && fallback.severePercent === 10
            && fallback.criticalPercent === 5)
      const equal = Battery.BatteryConfig.validatedValues({
        warnPercent: 10, severePercent: 10, criticalPercent: 5
      })
      check("equal thresholds fall back to defaults",
            equal.warnPercent === 20 && equal.severePercent === 10
            && equal.criticalPercent === 5)
      const disabled = Battery.BatteryConfig.validatedValues({
        warnPercent: 0, severePercent: 10, criticalPercent: 5
      })
      check("zero disables an individual threshold",
            disabled.warnPercent === 0 && disabled.severePercent === 10
            && disabled.criticalPercent === 5)

      state.refresh()
      fakeDevice.percentage = 0.37
      Qt.callLater(smoke.finish)
    }
  }

  function finish() {
    const state = smoke.alertEngine
    check("Connections percentage handler refreshes state", state.percent === 37)

    const command = state.notificationCommand({ level: "critical", percent: 5 })
    check("notify command executable and app name",
          command[0] === "notify-send" && command[1] === "-a" && command[2] === "Battery")
    check("notify command is critical", command[3] === "-u" && command[4] === "critical")
    check("notify command bypasses DND",
          command[5] === "-h" && command[6] === "boolean:swaync-bypass-dnd:true")
    check("notify command is persistent", command[7] === "-t" && command[8] === "0")
    check("notify command contains title and body",
          command[9] === "Battery critically low"
          && command[10] === "5% remaining. Connect a charger.")

    console.log(smoke.failures === 0
      ? "ok: BatteryState logic"
      : ("FAIL: " + smoke.failures + " assertion(s) failed"))
    Qt.callLater(Qt.quit)
  }

  Timer {
    interval: 5000
    running: true
    onTriggered: {
      console.log("FAIL BatteryConfig did not load config.json")
      Qt.quit()
    }
  }
}

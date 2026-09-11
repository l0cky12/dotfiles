import Quickshell
import QtQuick

// Headless projection harness. Fixture objects avoid depending on a real
// battery or UPower daemon while exercising both footprint paths.
Scope {
  id: smoke
  property int failures: 0

  QtObject {
    id: fixture
    property bool hasBattery: true
    property int percent: 54
    property bool charging: false
    property string state: "discharging"
    property real timeToEmpty: 5400
    property real timeToCharge: 0
  }

  QtObject {
    id: absentFixture
    property bool hasBattery: false
    property int percent: 0
    property bool charging: false
    property string state: "unknown"
    property real timeToEmpty: 0
    property real timeToCharge: 0
  }

  BatteryIcon { id: presentIcon; batteryState: fixture }
  BatteryIcon { id: absentIcon; batteryState: absentFixture }

  function check(name, condition) {
    if (condition)
      console.log("ok   " + name)
    else {
      console.log("FAIL " + name)
      smoke.failures += 1
    }
  }

  Component.onCompleted: {
    check("battery is visible when present",
          presentIcon.visible && presentIcon.implicitWidth > 0)
    check("desktop path has zero footprint",
          !absentIcon.visible && absentIcon.implicitWidth === 0
          && absentIcon.implicitHeight === 0)
    check("percentage is projected", presentIcon.percentText === "54%")
    check("discharge estimate is formatted",
          presentIcon.tooltipText.indexOf("1h 30m") !== -1)
    check("full state has a distinct glyph",
          presentIcon.glyphFor(100, "full", false)
          !== presentIcon.glyphFor(54, "discharging", false))
    check("critical state has a distinct glyph",
          presentIcon.glyphFor(10, "discharging", false)
          !== presentIcon.glyphFor(54, "discharging", false))

    fixture.charging = true
    fixture.state = "charging"
    fixture.timeToCharge = 2700
    check("charging state updates the glyph",
          presentIcon.glyph === presentIcon.glyphFor(54, "charging", true))
    check("charging tooltip uses time to full",
          presentIcon.tooltipText.indexOf("Time to full: 45m") !== -1)

    fixture.charging = false
    fixture.state = "discharging"
    fixture.percent = 10
    check("low discharging battery becomes critical", presentIcon.critical)
  }

  Timer {
    interval: 300
    running: true
    onTriggered: {
      console.log(smoke.failures === 0
                  ? "ok: Battery widget projections"
                  : "FAIL: Battery widget projections")
      Qt.quit()
    }
  }
}

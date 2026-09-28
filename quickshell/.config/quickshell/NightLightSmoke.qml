import Quickshell
import QtQuick

// Headless harness for NightLightState. The panel needs a Wayland backend to
// compile, so NightLightPanelSmoke.qml checks it separately. Run by
// tests/night-light-schedule.test.sh with NIGHT_LIGHT_SCHEDULE_BIN pointing at
// a fixture that prints a canned status and records every call.
Scope {
  id: smoke
  readonly property var state: NightLightState

  function check(condition, message) {
    if (!condition) console.log("FAIL: " + message)
    return condition
  }

  Component.onCompleted: {
    const s = NightLightState
    let ok = true
    ok = check(s.formatClock("21:00") === "9:00 PM", "formatClock 21:00 -> " + s.formatClock("21:00")) && ok
    ok = check(s.formatClock("07:05") === "7:05 AM", "formatClock 07:05") && ok
    ok = check(s.describeOffset(0, "sunset") === "At sunset", "zero offset") && ok
    ok = check(s.describeOffset(-30, "sunset") === "30 min before sunset", "negative offset") && ok
    ok = check(s.describeOffset(60, "sunrise") === "1 h after sunrise", "hour offset") && ok
    ok = check(s.offsetTime("2026-09-27T18:40-05:00", -30) !== "--", "offsetTime parses ISO") && ok
    // Wrapping past midnight in both directions.
    s.offTime = "23:58"
    s.shiftClock("off", 5)
    ok = check(s.offTime === "00:03", "shiftClock wraps forward -> " + s.offTime) && ok
    s.onTime = "00:02"
    s.shiftClock("on", -5)
    ok = check(s.onTime === "23:57", "shiftClock wraps back -> " + s.onTime) && ok
    s.sunsetOffset = 180
    s.shiftOffset("sunset", 15)
    ok = check(s.sunsetOffset === 180, "offset clamps at the maximum") && ok
    s.refresh()
    if (ok) statusCheck.start()
  }

  Timer {
    id: statusCheck
    interval: 1500
    onTriggered: {
      const s = NightLightState
      let ok = true
      ok = smoke.check(s.mode === "sunset", "status mode -> " + s.mode) && ok
      ok = smoke.check(s.light === true, "status light") && ok
      ok = smoke.check(s.location && s.location.latitude === 41.8781, "status location") && ok
      ok = smoke.check(s.today.sunset === "2026-09-27T18:40-05:00", "status today") && ok
      if (ok) console.log("ok: NightLightState logic")
      Qt.quit()
    }
  }
}

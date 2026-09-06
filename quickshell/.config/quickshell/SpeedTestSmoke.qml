import Quickshell
import QtQuick

Scope {
  id: smoke
  readonly property var state: SpeedTestState
  property int failures: 0

  Component { SpeedGauge {} }

  function check(name, condition) {
    if (condition)
      console.log("ok   " + name)
    else {
      console.log("FAIL " + name)
      failures += 1
    }
  }

  Component.onCompleted: {
    check("formats fractional Mbps", SpeedTestState.formatMbps(7.25) === "7.25")
    check("formats fast Mbps", SpeedTestState.formatMbps(412.4) === "412")
    check("gauge starts at zero", SpeedTestState.gaugeFraction(0) === 0)
    check("gauge clamps gigabit", SpeedTestState.gaugeFraction(1000) === 1)
  }

  Timer {
    interval: 300
    running: true
    onTriggered: {
      console.log(smoke.failures === 0 ? "ok: SpeedTest UI logic" : "FAIL: SpeedTest UI logic")
      Qt.quit()
    }
  }
}

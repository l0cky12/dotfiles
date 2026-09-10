import QtQuick
import Quickshell

Scope {
  id: smoke
  Component { id: gaugeComponent; SpeedTestGauge {} }

  property int failures: 0
  function check(name, condition) {
    if (condition) console.log("ok   " + name)
    else { console.log("FAIL " + name); failures += 1 }
  }

  Component.onCompleted: {
    const gauge = gaugeComponent.createObject(null, { value: 59, peak: 59 })
    check("autorange keeps 59 Mbps mid-arc", gauge.scaleFor(59) === 100)
    check("autorange keeps 940 Mbps readable", gauge.scaleFor(940) === 1600)
    gauge.destroy()
  }
  Timer {
    interval: 100
    running: true
    onTriggered: {
      console.log(smoke.failures === 0 ? "ok: Speed test logic" : "FAIL: Speed test logic")
      Qt.quit()
    }
  }
}

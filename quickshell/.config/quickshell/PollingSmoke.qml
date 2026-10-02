import Quickshell
import QtQuick

// Headless check that the bar's background state is fed by resident watchers
// instead of fast status polls. tests/shell-polling.test.sh supplies stub
// executables that log every call, then counts them after this exits.
Scope {
  id: smoke
  property int failures: 0
  function check(name, condition) {
    if (condition) console.log("ok   " + name)
    else { console.log("FAIL " + name); failures += 1 }
  }

  // Referencing the singletons instantiates them, timers and watchers included.
  readonly property var singletons: [ModesState, NetworkState, BluetoothState,
                                     RecordState, WindowsVmState, DisplayState]

  CavaBars { id: bars; width: 250; height: 50 }

  Component.onCompleted: {
    const row = bars.children[0]
    const first = row.children[0]
    CavaState.available = true
    CavaState.levels = Array(CavaState.barCount).fill(0.5)
    check("a cava frame keeps the bar delegates", row.children[0] === first)
    check("a cava frame updates bar heights", Math.abs(first.height - 25) < 0.01)
  }

  Timer {
    interval: 2500; running: true
    onTriggered: {
      check("display scroll state is ready without opening its panel",
            DisplayState.monitorFor("DP-1") !== null && DisplayState.monitorFor("DP-1").ddcOk)
      check("desktop-mode watch lines update the modes",
            ModesState.mode("stay-awake").observed === true)
      console.log(smoke.failures === 0 ? "ok: polling smoke" : "FAIL: polling smoke")
      Qt.quit()
    }
  }
}

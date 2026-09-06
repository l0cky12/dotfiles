import Quickshell
import QtQuick

// Headless parser/logic harness. NetworkPanel itself is only compiled because
// a PopupWindow needs a live layer-shell compositor to be constructed.
Scope {
  id: smoke
  readonly property var state: NetworkState
  Component { NetworkPanel { ownerScreen: "smoke" } }
  property int failures: 0
  function check(name, condition) {
    if (condition) console.log("ok   " + name)
    else { console.log("FAIL " + name); failures += 1 }
  }
  Component.onCompleted: {
    check("accepts a valid IPv4 address", NetworkState.validateIp("192.0.2.44"))
    check("rejects an out-of-range IPv4 address", !NetworkState.validateIp("192.0.2.999"))
    check("accepts two DNS servers", NetworkState.validateDns("1.1.1.1 1.0.0.1"))
    check("rejects more than two DNS servers", !NetworkState.validateDns("1.1.1.1 1.0.0.1 9.9.9.9"))
  }
  Timer {
    interval: 300; running: true
    onTriggered: { console.log(smoke.failures === 0 ? "ok: NetworkState logic" : "FAIL: NetworkState logic"); Qt.quit() }
  }
}

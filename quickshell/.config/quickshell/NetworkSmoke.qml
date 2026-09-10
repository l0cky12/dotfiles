import Quickshell
import QtQuick

// Headless parser/logic harness. NetworkPanel and WifiQrOverlay are only
// compiled because a layer-shell window needs a live compositor to be
// constructed.
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
    check("strips the backend prefix from an error",
      NetworkState.backendError("network-control: Connect to Wi-Fi before sharing it\n") === "Connect to Wi-Fi before sharing it")
    check("keeps the most specific backend error line",
      NetworkState.backendError("Error: some nmcli noise\nnetwork-control: NetworkManager authorization was cancelled or denied\n") === "NetworkManager authorization was cancelled or denied")
    check("reports no error for empty backend output", NetworkState.backendError("\n  \n") === "")

    // QR overlay wiring: opening the panel targets an overlay screen, and the
    // panel itself never holds a QR view of its own.
    check("overlay screen starts empty", NetworkState.overlayScreen === "")
    NetworkState.togglePanel("smoke")
    check("togglePanel targets the overlay", NetworkState.overlayScreen === "smoke")
    check("qrResult stays null without sharing", NetworkState.qrResult === null)
    // Clearing the result is the overlay's dismissal path.
    NetworkState.qrResult = {path: "/tmp/x.svg", ssid: "S", security: "WPA"}
    check("qrResult accepts a result", NetworkState.qrResult !== null)
    NetworkState.qrResult = null
    check("clearing qrResult dismisses", NetworkState.qrResult === null)
  }
  Timer {
    interval: 300; running: true
    onTriggered: { console.log(smoke.failures === 0 ? "ok: NetworkState logic" : "FAIL: NetworkState logic"); Qt.quit() }
  }
}

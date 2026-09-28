import Quickshell
import QtQuick

// Construct the schedule panel without showing it. No layer surface is mapped.
Scope {
  NightLightPanel {
    id: panel
    ownerScreen: "smoke"
  }
  Component.onCompleted: {
    Qt.callLater(function() {
      if (panel.visible)
        console.log("FAIL: the schedule panel is visible before it was asked for")
      else
        console.log("ok: night-light panel compiles")
      Qt.quit()
    })
  }
}

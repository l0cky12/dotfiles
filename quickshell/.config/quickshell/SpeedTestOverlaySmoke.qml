import Quickshell
import QtQuick

Scope {
  Variants {
    model: Quickshell.screens
    SpeedTestOverlay {
      required property var modelData
      output: modelData
    }
  }
  Timer { interval: 100; running: true; onTriggered: Qt.quit() }
}

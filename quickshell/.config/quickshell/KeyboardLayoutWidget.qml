import QtQuick
import Quickshell.Io

Item {
  id: root
  property real barScale: 1.0
  property string layout: "US"
  function s(n) { return Theme.fs(n * root.barScale) }

  implicitWidth: label.implicitWidth + root.s(10)
  implicitHeight: label.implicitHeight + root.s(6)

  Text {
    id: label
    anchors.centerIn: parent
    text: root.layout
    color: Theme.textDim
    font.family: Theme.uiFamily
    font.pixelSize: root.s(11)
    font.bold: true
  }

  Process {
    id: keyboardQuery
    command: ["hyprctl", "devices", "-j"]
    stdout: StdioCollector { id: keyboardOutput }
    onExited: function(code) {
      if (code !== 0)
        return
      try {
        const keyboards = JSON.parse(keyboardOutput.text).keyboards || []
        const keyboard = keyboards.find(item => item.main === true)
        if (!keyboard || !keyboard.active_keymap)
          return
        const match = keyboard.active_keymap.match(/\(([^)]+)\)$/)
        root.layout = match ? match[1].toUpperCase() : keyboard.active_keymap
      } catch (error) {}
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: keyboardQuery.running = true
  }
}

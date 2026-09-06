import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }

  implicitWidth: root.s(28)
  implicitHeight: root.s(28)

  Text {
    anchors.centerIn: parent
    text: String.fromCodePoint(0xf0d0a)
    color: Theme.text
    font.family: Theme.glyphFamily
    font.pixelSize: root.s(15)
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: agentLauncher.running = true
  }

  Process {
    id: agentLauncher
    command: ["kitty", "-e",
              Quickshell.env("HOME") + "/.config/hypr/scripts/run-if-deployed.sh",
              "ai", "ai-agent"]
  }
}

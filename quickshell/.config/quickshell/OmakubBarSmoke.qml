import QtQuick
import Quickshell

FloatingWindow {
  id: window
  implicitWidth: 900
  implicitHeight: 60

  Row {
    anchors.centerIn: parent
    spacing: 4

    KeyboardLayoutWidget {}
    SystemTrayWidget { parentWindow: window }
    AgentIcon {}
    BluetoothIcon { screenName: "fixture" }
    NetworkIcon { screenName: "fixture" }
    AudioIcon { screenName: "fixture" }
    DisplayIcon { screenName: "fixture" }
  }
}

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Row {
  id: root
  required property var parentWindow
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }
  spacing: root.s(2)

  Repeater {
    model: SystemTray.items

    Item {
      required property var modelData
      implicitWidth: root.s(26)
      implicitHeight: root.s(26)

      Image {
        anchors.centerIn: parent
        width: root.s(16)
        height: root.s(16)
        source: Quickshell.iconPath(parent.modelData.icon)
        fillMode: Image.PreserveAspectFit
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
          if (mouse.button === Qt.RightButton && parent.modelData.hasMenu)
            parent.modelData.display(root.parentWindow, mouse.x, parent.height)
          else if (mouse.button === Qt.MiddleButton)
            parent.modelData.secondaryActivate()
          else
            parent.modelData.activate()
        }
        onWheel: wheel => parent.modelData.scroll(wheel.angleDelta.y, false)
      }
    }
  }
}

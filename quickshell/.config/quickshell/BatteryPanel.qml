import QtQuick
import Quickshell

// Battery readout under the bar's battery icon. Visibility is a plain local
// property toggled by BatteryIcon, which is the per-screen popup ownership
// CalendarPopup and PowerPopup already use; AudioState's panelScreen bookkeeping
// is only needed by panels that other code has to open remotely.
PopupWindow {
  id: panel
  required property Item anchorItem

  visible: false
  grabFocus: true

  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: Theme.gapS

  implicitWidth: Theme.fs(320)
  implicitHeight: body.implicitHeight + Theme.gapL * 2

  Rectangle {
    anchors.fill: parent
    color: Theme.bg

    Item {
      id: content
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: panel.visible = false

      BatteryPanelContent {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.gapL
      }
    }
  }

  onVisibleChanged: if (visible) content.forceActiveFocus()
}

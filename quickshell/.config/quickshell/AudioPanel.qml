import QtQuick
import Quickshell

PopupWindow {
  id: panel
  required property Item anchorItem
  required property string ownerScreen
  property var audio: AudioState

  visible: audio.panelVisible && audio.panelScreen === panel.ownerScreen
  grabFocus: true

  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: Theme.gapS

  implicitWidth: Theme.fs(412)
  readonly property int maxHeight: Theme.fs(640)
  implicitHeight: Math.min(maxHeight, body.implicitHeight + Theme.gapL * 2)

  Behavior on implicitHeight {
    NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.bg

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: panel.audio.panelVisible = false

      Flickable {
        anchors.fill: parent
        anchors.margins: Theme.gapL
        clip: true
        contentWidth: width
        contentHeight: body.implicitHeight
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        AudioPanelContent {
          id: body
          width: parent.width
          audio: panel.audio
        }
      }
    }
  }

  onVisibleChanged: if (visible) focusScope.forceActiveFocus()
}

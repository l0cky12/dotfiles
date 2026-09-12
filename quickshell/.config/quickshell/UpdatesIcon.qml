import Quickshell
import QtQuick

Item {
  id: root

  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }

  implicitWidth: label.implicitWidth + root.s(16)
  implicitHeight: label.implicitHeight + root.s(6)

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusCell
    color: UpdatesState.totalCount > 0 ? Theme.accent : "transparent"
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: "󰚰  " + UpdatesState.totalCount
    font.family: Theme.glyphFamily
    font.pixelSize: root.s(14)
    color: UpdatesState.totalCount > 0 ? Theme.onAccent : Theme.textMuted
    opacity: (UpdatesState.updating || UpdatesState.checking) ? 0.55 : 1
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    enabled: !UpdatesState.checking && !UpdatesState.updating
    onClicked: UpdatesState.update()
  }

  PopupWindow {
    visible: mouse.containsMouse
    anchor.item: root
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 6
    implicitWidth: 360
    implicitHeight: tip.implicitHeight + 16

    Rectangle {
      anchors.fill: parent
      color: Theme.bg
    }

    Text {
      id: tip
      anchors.centerIn: parent
      width: parent.width - 20
      horizontalAlignment: Text.AlignLeft
      wrapMode: Text.Wrap
      text: "Pacman (" + UpdatesState.repoCount + "): "
            + (UpdatesState.repoPackages.length > 0
              ? UpdatesState.repoPackages.join(", ")
              : "None")
            + "\nAUR (" + UpdatesState.aurCount + "): "
            + (UpdatesState.aurPackages.length > 0
              ? UpdatesState.aurPackages.join(", ")
              : "None")
            + (UpdatesState.stale ? "\nLast check failed" : "")
            + "\nClick to update"
      color: Theme.text
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(12)
    }
  }
}

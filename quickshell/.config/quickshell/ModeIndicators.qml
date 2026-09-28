import QtQuick

Item {
  id: root
  required property string screenName
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }

  readonly property var activeModes: ModesState.modes.filter(mode =>
    (mode.name === "screensaver-auto" ? !mode.observed : mode.observed) || mode.error)

  visible: activeModes.length > 0 || ModesState.lastError !== ""
  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    spacing: root.s(2)

    Repeater {
      model: root.activeModes
      Rectangle {
        id: pill
        required property var modelData
        readonly property var meta: ModesState.metadata[modelData.name]
        width: content.implicitWidth + root.s(14)
        height: content.implicitHeight + root.s(6)
        radius: Theme.radiusCell
        color: modelData.error ? Theme.critical : Theme.accent
        Row {
          id: content
          anchors.centerIn: parent
          spacing: root.s(4)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.meta.glyph
            font.family: Theme.glyphFamily
            font.pixelSize: root.s(15)
            color: Theme.onAccent
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            text: pill.meta.badge || ""
            font.family: Theme.uiFamily
            font.bold: true
            font.pixelSize: root.s(12)
            color: Theme.onAccent
          }
        }
      }
    }

    Rectangle {
      visible: ModesState.lastError !== ""
      width: errorGlyph.implicitWidth + root.s(14)
      height: errorGlyph.implicitHeight + root.s(6)
      radius: Theme.radiusCell
      color: Theme.critical
      Text {
        id: errorGlyph
        anchors.centerIn: parent
        text: "!"
        font.bold: true
        font.pixelSize: root.s(14)
        color: Theme.onAccent
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: ModesState.togglePanel(root.screenName)
  }
}

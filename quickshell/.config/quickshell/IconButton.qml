import QtQuick

// Square glyph button for the media controls. The config previously hand-rolled
// this markup in NetworkPanel and AudioPanel; this is the shared version.
//
// Uses the built-in Item.enabled, which already blocks the MouseArea when false.
Item {
  id: root
  property string glyph: ""
  property bool active: false
  property int size: Theme.fs(30)
  property int glyphSize: Theme.fs(15)
  // Off on the bar, where the button already sits inside a BarIsland and the
  // resting outline would draw a rounded square inside the capsule.
  property bool bordered: true
  signal clicked()

  implicitWidth: size
  implicitHeight: size
  opacity: enabled ? 1 : Theme.opacityDisabled

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusCell
    color: root.active ? Theme.accent : "transparent"
    border.width: root.bordered || root.active ? Theme.borderWidth : 0
    border.color: root.active ? Theme.accent : Theme.surface
  }

  Text {
    anchors.centerIn: parent
    text: root.glyph
    font.family: Theme.glyphFamily
    font.pixelSize: root.glyphSize
    color: root.active ? Theme.bgDeep : Theme.text
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.clicked()
  }
}

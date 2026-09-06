import QtQuick

Item {
  id: root
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }
  required property string screenName
  implicitWidth: label.implicitWidth + root.s(16)
  implicitHeight: label.implicitHeight + root.s(6)
  readonly property string glyph: {
    if (NetworkState.connType === "ethernet") return String.fromCodePoint(0xef44)
    if (NetworkState.connType === "wifi") {
      const strength = NetworkState.signalPct
      if (strength >= 75) return String.fromCodePoint(0xf0928)
      if (strength >= 50) return String.fromCodePoint(0xf0925)
      if (strength >= 25) return String.fromCodePoint(0xf0922)
      return String.fromCodePoint(0xf091f)
    }
    return String.fromCodePoint(0xf05aa)
  }
  Text { id: label; anchors.centerIn: parent; text: root.glyph; font.family: Theme.glyphFamily; font.pixelSize: root.s(15); color: Theme.text }
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; onClicked: NetworkState.togglePanel(root.screenName) }
  NetworkPanel { anchorItem: root; ownerScreen: root.screenName }
}

import Quickshell
import QtQuick

Item {
  id: root

  property real barScale: 1.0
  property var batteryState: BatteryState
  readonly property bool critical: batteryState.hasBattery
                                   && (batteryState.percent
                                       <= batteryState.criticalThreshold
                                       || batteryState.state === "empty")
  readonly property string glyph: glyphFor(batteryState.percent,
                                             batteryState.state,
                                             batteryState.charging)
  readonly property string percentText: batteryState.percent + "%"
  function s(n) { return Theme.fs(n * root.barScale) }

  function glyphFor(percent, state, charging) {
    if (charging)
      return String.fromCodePoint(0xf0084) // md-battery_charging
    if (state === "full")
      return String.fromCodePoint(0xf0079) // md-battery
    if (percent <= batteryState.criticalThreshold)
      return String.fromCodePoint(0xf0083) // md-battery_alert
    if (percent <= 35)
      return String.fromCodePoint(0xf007b) // md-battery_20
    if (percent <= 65)
      return String.fromCodePoint(0xf007f) // md-battery_60
    return String.fromCodePoint(0xf0082)   // md-battery_90
  }

  visible: batteryState.hasBattery
  implicitWidth: content.implicitWidth + root.s(12)
  implicitHeight: content.implicitHeight + root.s(6)

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusCell
    color: root.batteryState.charging && !root.critical
           ? Theme.accent : "transparent"
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: root.s(4)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.glyph
      color: root.critical ? Theme.critical
                           : (root.batteryState.charging ? Theme.onAccent : Theme.text)
      font.family: Theme.glyphFamily
      font.pixelSize: root.s(15)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.percentText
      color: root.critical ? Theme.critical
                           : (root.batteryState.charging ? Theme.onAccent : Theme.textDim)
      font.family: Theme.uiFamily
      font.pixelSize: root.s(12)
    }
  }

  // No hover tooltip: BatteryPanel is a strict superset of what the tooltip
  // said, and a hover popup would fight the click popup for the same space
  // directly under the icon.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: panel.visible = !panel.visible
  }

  BatteryPanel {
    id: panel
    anchorItem: root
  }
}

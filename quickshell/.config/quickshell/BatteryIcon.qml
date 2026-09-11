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
  readonly property string tooltipText: tooltipFor(batteryState)
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

  function formatTime(seconds) {
    const minutes = Math.max(0, Math.round(Number(seconds) / 60))
    if (!isFinite(minutes) || minutes <= 0)
      return "estimating"
    const hours = Math.floor(minutes / 60)
    const remainder = minutes % 60
    if (hours === 0)
      return remainder + "m"
    return hours + "h" + (remainder > 0 ? " " + remainder + "m" : "")
  }

  function stateLabel(state) {
    if (!state || state === "unknown")
      return "Unknown"
    return state.charAt(0).toUpperCase() + state.slice(1)
  }

  function tooltipFor(battery) {
    const summary = battery.percent + "% · " + stateLabel(battery.state)
    if (battery.state === "charging" || battery.state === "pending charge")
      return summary + "\nTime to full: " + formatTime(battery.timeToCharge)
    if (battery.state === "discharging"
        || battery.state === "pending discharge")
      return summary + "\nTime remaining: " + formatTime(battery.timeToEmpty)
    if (battery.state === "full")
      return battery.percent + "% · Full"
    return summary
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

  HoverHandler { id: hover }

  PopupWindow {
    visible: root.visible && hover.hovered
    anchor.item: root
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: root.s(6)
    implicitWidth: tip.implicitWidth + Theme.gapL
    implicitHeight: tip.implicitHeight + Theme.gapM

    Rectangle {
      anchors.fill: parent
      radius: Theme.radiusCell
      color: Theme.bg
      border.width: Theme.borderWidth
      border.color: Theme.surface
    }

    Text {
      id: tip
      anchors.centerIn: parent
      text: root.tooltipText
      color: Theme.text
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(12)
    }
  }
}

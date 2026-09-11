import Quickshell
import QtQuick

Item {
  id: root

  property real barScale: 1.0
  property var batteryState: BatteryState
  readonly property bool critical: batteryState.hasBattery
                                   && !batteryState.charging
                                   && batteryState.percent <= 15
  readonly property string glyph: glyphFor(batteryState.percent,
                                             batteryState.state,
                                             batteryState.charging)
  readonly property string percentText: batteryState.percent + "%"
  readonly property string tooltipText: tooltipFor(batteryState)
  function s(n) { return Theme.fs(n * root.barScale) }

  function glyphFor(percent, state, charging) {
    if (charging)
      return "󰂄"
    if (state === "full" || percent >= 95)
      return "󰁹"
    if (percent <= 15)
      return "󰂃"
    if (percent <= 35)
      return "󰁻"
    if (percent <= 65)
      return "󰁿"
    return "󰂂"
  }

  function formatTime(seconds) {
    const minutes = Math.max(0, Math.round(Number(seconds) / 60))
    if (minutes <= 0)
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
    const estimate = battery.charging ? battery.timeToCharge : battery.timeToEmpty
    const estimateLabel = battery.charging ? "Time to full" : "Time remaining"
    return battery.percent + "% · " + stateLabel(battery.state)
           + "\n" + estimateLabel + ": " + formatTime(estimate)
  }

  visible: batteryState.hasBattery
  implicitWidth: visible ? content.implicitWidth + root.s(12) : 0
  implicitHeight: visible ? content.implicitHeight + root.s(6) : 0

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusCell
    color: "transparent"
    border.width: Theme.borderWidth
    border.color: root.critical ? Theme.critical : Theme.surface
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: root.s(4)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.glyph
      color: root.critical ? Theme.critical
                           : (root.batteryState.charging ? Theme.accent : Theme.text)
      font.family: Theme.glyphFamily
      font.pixelSize: root.s(15)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.percentText
      color: root.critical ? Theme.critical : Theme.textDim
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

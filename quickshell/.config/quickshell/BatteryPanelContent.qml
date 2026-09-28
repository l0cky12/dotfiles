import QtQuick
import "battery" as Battery

// Battery readout: percentage and supply line across the top, then the two
// absolute figures UPower hands us directly -- the instantaneous rate in W and
// stored energy against full capacity in Wh.
//
// Split out of BatteryPanel.qml so BatterySmoke.qml can instantiate it and
// assert on its projections without standing up a PopupWindow, the same split
// AudioPanel / AudioPanelContent uses.
Item {
  id: root
  property var batteryState: BatteryState

  readonly property real tileSpacing: Theme.gapL
  readonly property real tileWidth: Math.max(0, (width - tileSpacing) / 2)

  implicitHeight: body.implicitHeight

  // "4 h 8 min", not the bar icon's compact "4h 8m": this readout has room for
  // the spaced form and it is what the design calls for. Empty string means
  // UPower has not produced a usable estimate yet, which every caller below
  // turns into "estimating" rather than a fabricated 0.
  function formatDuration(seconds) {
    const minutes = Math.round(Number(seconds) / 60)
    if (!isFinite(minutes) || minutes <= 0)
      return ""
    const hours = Math.floor(minutes / 60)
    const remainder = minutes % 60
    if (hours === 0)
      return remainder + " min"
    if (remainder === 0)
      return hours + " h"
    return hours + " h " + remainder + " min"
  }

  function estimateOr(seconds, suffix) {
    const formatted = root.formatDuration(seconds)
    return formatted === "" ? "estimating" : formatted + suffix
  }

  readonly property string percentText: root.batteryState.percent + "%"

  readonly property string supplyLine: {
    const battery = root.batteryState
    switch (battery.supplyState) {
    case "discharging":
      return "On battery · " + root.estimateOr(battery.timeToEmpty, " left")
    case "charging":
      return "Charging · " + root.estimateOr(battery.timeToCharge, " to full")
    case "full":
      return "Plugged in · Fully charged"
    case "idle":
      return "Plugged in · Not charging"
    case "empty":
      return "On battery · Empty"
    default:
      return "Unknown"
    }
  }

  readonly property bool critical: root.batteryState.supplyState === "empty"
                                   || root.batteryState.percent
                                      <= root.batteryState.criticalThreshold
  readonly property bool low: root.batteryState.supplyState === "discharging"
                              && root.batteryState.percent
                                 <= Battery.BatteryConfig.warnPercent

  readonly property color levelColor: root.critical
                                      ? Theme.critical
                                      : (root.low ? Theme.warning : Theme.success)

  // The ring already carries the level, so the glyph inside it only has to say
  // whether energy is going in. No need for the icon's full level ladder here.
  readonly property string glyph: root.batteryState.supplyState === "charging"
                                  ? String.fromCodePoint(0xf0084)
                                  : String.fromCodePoint(0xf0079)

  // A connected idle charger, or a full battery, genuinely reports 0 W: nothing
  // is moving through the pack. The figure stays "0.0 W" rather than a
  // placeholder, because zero is a real reading here and not missing data.
  // Only the direction qualifier drops out, since there is no direction.
  //
  // Worth knowing when reading this tile: it measures flow through the
  // battery, not what the machine consumes. On AC the charger carries the load
  // directly, so this sits at 0 W however hard the machine is working. System
  // draw would have to come from RAPL, whose sysfs counters are root-only.
  readonly property bool powerFlowing: root.batteryState.changeRate >= 0.05
  readonly property string powerPrimary: root.batteryState.changeRate.toFixed(1) + " W"
  readonly property string powerSecondary: {
    if (!root.powerFlowing)
      return "no flow"
    switch (root.batteryState.supplyState) {
    case "charging":
      return "going in"
    case "discharging":
    case "empty":
      return "coming out"
    default:
      return "in use"
    }
  }

  // energyCapacity is UPower's energy-full, so this is charge against the
  // pack's present full charge, not against its design capacity.
  readonly property bool chargeKnown: root.batteryState.energyCapacity > 0
  readonly property string chargePrimary: root.batteryState.energy.toFixed(1) + " Wh"
  readonly property string chargeSecondary: root.chargeKnown
    ? "of " + root.batteryState.energyCapacity.toFixed(1) + " Wh full"
    : "capacity unknown"

  Column {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Theme.gapL

    Item {
      id: hero
      width: parent.width
      implicitHeight: Math.max(ring.implicitHeight, heroText.implicitHeight)
      height: implicitHeight

      Gauge {
        id: ring
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        size: Theme.fs(52)
        thickness: Theme.fs(5)
        trackColor: Theme.bgDeep
        ringColor: root.levelColor
        value: root.batteryState.percent / 100
        // The glyph is drawn over the ring instead, since Gauge's own inner
        // Text does not set a font family and so cannot render a Nerd Font
        // codepoint.
        text: ""
      }

      Text {
        anchors.centerIn: ring
        text: root.glyph
        color: root.levelColor
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(20)
      }

      Column {
        id: heroText
        anchors.left: ring.right
        anchors.leftMargin: Theme.gapM
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.fs(2)

        Text {
          width: parent.width
          text: root.percentText
          color: Theme.text
          font.family: Theme.uiFamily
          font.pixelSize: Theme.fs(22)
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: root.supplyLine
          color: Theme.textDim
          font.family: Theme.uiFamily
          font.pixelSize: Theme.fs(11)
          elide: Text.ElideRight
        }
      }
    }

    Row {
      id: tiles
      width: parent.width
      spacing: root.tileSpacing

      BatteryMetric {
        width: root.tileWidth
        label: "POWER"
        primary: root.powerPrimary
        secondary: root.powerSecondary
      }

      BatteryMetric {
        width: root.tileWidth
        label: "CHARGE"
        primary: root.chargePrimary
        secondary: root.chargeSecondary
        available: root.chargeKnown
      }
    }
  }
}

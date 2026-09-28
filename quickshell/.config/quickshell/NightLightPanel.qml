pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

// Night-light schedule (Super+Shift+N, or "Night light schedule…" in lmenu).
//
// Same layer-shell shape as ModesPanel: one instance per monitor, only the one
// matching panelScreen visible, exclusive keyboard focus. Every control writes
// through night-light-schedule.py; nothing here decides when the light is on.
PanelWindow {
  id: panel
  required property string ownerScreen

  visible: NightLightState.panelVisible && NightLightState.panelScreen === ownerScreen
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.namespace: "quickshell-night-light"

  readonly property var loc: NightLightState.location
  readonly property bool polar: NightLightState.today.kind === "polar-day"
                              || NightLightState.today.kind === "polar-night"

  // A small clickable pill; `active` fills it with the accent colour.
  component Pill: Rectangle {
    id: pill
    property string label: ""
    property bool active: false
    signal clicked()
    implicitWidth: Math.max(Theme.fs(42), pillText.implicitWidth + Theme.gapM * 2)
    implicitHeight: Theme.fs(28)
    radius: Theme.radiusCell
    color: active ? Theme.accent : (pillMouse.containsMouse ? Theme.surfaceAlt : Theme.surface)
    opacity: enabled ? 1 : Theme.opacityDisabled
    Text {
      id: pillText
      anchors.centerIn: parent
      text: pill.label
      color: pill.active ? Theme.onAccent : Theme.text
      font.bold: pill.active
      font.pixelSize: Theme.fs(11)
    }
    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.clicked()
    }
  }

  // Label on the left, − value + on the right.
  component Stepper: Item {
    id: stepper
    property string title: ""
    property string detail: ""
    property string value: ""
    property var steps: []           // [{ label, minutes }], applied in order
    signal step(int minutes)
    width: parent ? parent.width : 0
    implicitHeight: Theme.fs(40)

    Column {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1
      Text { text: stepper.title; color: Theme.text; font.bold: true; font.pixelSize: Theme.fs(13) }
      Text {
        visible: stepper.detail !== ""
        text: stepper.detail
        color: Theme.textMuted
        font.pixelSize: Theme.fs(10)
      }
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.gapXS
      Repeater {
        model: stepper.steps.filter(s => s.minutes < 0)
        Pill {
          required property var modelData
          label: modelData.label
          onClicked: stepper.step(modelData.minutes)
        }
      }
      Text {
        width: Theme.fs(76)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: stepper.value
        color: Theme.text
        font.bold: true
        font.pixelSize: Theme.fs(14)
      }
      Repeater {
        model: stepper.steps.filter(s => s.minutes > 0)
        Pill {
          required property var modelData
          label: modelData.label
          onClicked: stepper.step(modelData.minutes)
        }
      }
    }
  }

  component Divider: Rectangle { width: parent ? parent.width : 0; height: 1; color: Theme.surface }

  component SectionTitle: Text {
    color: Theme.textDim
    font.pixelSize: Theme.fs(10)
    font.bold: true
  }

  component Field: Rectangle {
    id: field
    property alias text: input.text
    property string placeholder: ""
    width: Theme.fs(120)
    height: Theme.fs(30)
    radius: Theme.radiusCell
    color: Theme.bgDeep
    border.width: Theme.borderWidth
    border.color: input.activeFocus ? Theme.accent : Theme.surface
    TextInput {
      id: input
      anchors.fill: parent
      anchors.leftMargin: Theme.gapS
      anchors.rightMargin: Theme.gapS
      verticalAlignment: TextInput.AlignVCenter
      color: Theme.text
      font.pixelSize: Theme.fs(12)
      selectByMouse: true
      clip: true
      inputMethodHints: Qt.ImhFormattedNumbersOnly
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text === ""
        text: field.placeholder
        color: Theme.textMuted
        font.pixelSize: parent.font.pixelSize
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, Theme.scrimOpacity)
    MouseArea { anchors.fill: parent; onClicked: NightLightState.close() }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(Theme.fs(500), panel.width - 2 * Theme.menuOuterMargin)
    height: Math.min(content.implicitHeight + 2 * Theme.menuPadding,
                     panel.height - 2 * Theme.menuOuterMargin)
    radius: Theme.menuRadius
    color: Theme.bg
    border.width: Theme.menuBorderWidth
    border.color: Theme.borderActive1
    clip: true
    focus: true
    Keys.onEscapePressed: NightLightState.close()
    MouseArea { anchors.fill: parent }

    Column {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.menuPadding
      spacing: Theme.gapM

      // --- HEADER: title, current state and the manual switch ---
      Item {
        width: parent.width
        height: Theme.fs(40)

        Text {
          id: glyph
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: String.fromCodePoint(0xf0594)
          color: NightLightState.light ? Theme.accent : Theme.text
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(24)
        }
        Column {
          anchors.left: glyph.right
          anchors.leftMargin: Theme.gapM
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1
          Text {
            text: "Night light"
            color: Theme.text
            font.bold: true
            font.pixelSize: Theme.menuFontTitle
          }
          Text {
            text: {
              const now = NightLightState.light ? "On now" : "Off now"
              const next = NightLightState.next
              if (NightLightState.mode === "off" || !next)
                return now
              return now + " · turns " + (next.light ? "on" : "off")
                   + " at " + NightLightState.formatIso(next.at)
            }
            color: Theme.textMuted
            font.pixelSize: Theme.fs(11)
          }
        }
        Pill {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: Theme.fs(64)
          label: NightLightState.light ? "ON" : "OFF"
          active: NightLightState.light
          onClicked: NightLightState.toggleLight()
        }
      }

      Divider {}

      // --- MODE ---
      SectionTitle { text: "SCHEDULE" }
      Row {
        id: modeRow
        width: parent.width
        spacing: Theme.gapXS
        readonly property var modes: [
          { value: "off", label: "Off" },
          { value: "fixed", label: "Set times" },
          { value: "sunset", label: "Sunset to sunrise" }
        ]
        Repeater {
          model: modeRow.modes
          Pill {
            required property var modelData
            width: (modeRow.width - Theme.gapXS * (modeRow.modes.length - 1)) / modeRow.modes.length
            implicitHeight: Theme.fs(32)
            label: modelData.label
            active: NightLightState.mode === modelData.value
            onClicked: NightLightState.setMode(modelData.value)
          }
        }
      }

      Text {
        visible: NightLightState.mode === "off"
        width: parent.width
        wrapMode: Text.WordWrap
        text: "No schedule. The light only changes when you switch it (Super+Ctrl+N)."
        color: Theme.textMuted
        font.pixelSize: Theme.menuFontBody
      }

      // --- FIXED TIMES ---
      Column {
        visible: NightLightState.mode === "fixed"
        width: parent.width
        spacing: Theme.gapS
        readonly property var steps: [
          { label: "−1h", minutes: -60 }, { label: "−5m", minutes: -5 },
          { label: "+5m", minutes: 5 }, { label: "+1h", minutes: 60 }
        ]
        Stepper {
          title: "Turn on"
          value: NightLightState.formatClock(NightLightState.onTime)
          steps: parent.steps
          onStep: minutes => NightLightState.shiftClock("on", minutes)
        }
        Stepper {
          title: "Turn off"
          value: NightLightState.formatClock(NightLightState.offTime)
          steps: parent.steps
          onStep: minutes => NightLightState.shiftClock("off", minutes)
        }
      }

      // --- SUNSET ---
      Column {
        visible: NightLightState.mode === "sunset"
        width: parent.width
        spacing: Theme.gapS
        readonly property var steps: [
          { label: "−15m", minutes: -NightLightState.offsetStep },
          { label: "+15m", minutes: NightLightState.offsetStep }
        ]
        Stepper {
          title: "Turn on"
          detail: NightLightState.describeOffset(NightLightState.sunsetOffset, "sunset")
          value: NightLightState.offsetTime(NightLightState.today.sunset, NightLightState.sunsetOffset)
          steps: parent.steps
          onStep: minutes => NightLightState.shiftOffset("sunset", minutes)
        }
        Stepper {
          title: "Turn off"
          detail: NightLightState.describeOffset(NightLightState.sunriseOffset, "sunrise")
          value: NightLightState.offsetTime(NightLightState.today.sunrise, NightLightState.sunriseOffset)
          steps: parent.steps
          onStep: minutes => NightLightState.shiftOffset("sunrise", minutes)
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: panel.polar
            ? (NightLightState.today.kind === "polar-day"
               ? "The sun does not set here today, so the light stays off."
               : "The sun does not rise here today, so the light stays on.")
            : "Today: sunset " + NightLightState.formatIso(NightLightState.today.sunset)
              + " · sunrise " + NightLightState.formatIso(NightLightState.today.sunrise)
              + ". Recalculated every day for your location."
          color: Theme.textMuted
          font.pixelSize: Theme.fs(11)
        }
      }

      Divider {}

      // --- LOCATION ---
      SectionTitle { text: "LOCATION" }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: {
          if (!panel.loc)
            return "No location set."
          const coords = panel.loc.latitude.toFixed(4) + ", " + panel.loc.longitude.toFixed(4)
          const name = panel.loc.place ? panel.loc.place + " · " + coords : coords
          return panel.loc.source === "saved" ? name : name + " (default, not detected)"
        }
        color: Theme.text
        font.pixelSize: Theme.menuFontBody
      }
      Row {
        spacing: Theme.gapXS
        Field {
          id: latField
          placeholder: "Latitude"
        }
        Field {
          id: lonField
          placeholder: "Longitude"
        }
        Pill {
          anchors.verticalCenter: parent.verticalCenter
          label: "Save"
          onClicked: NightLightState.saveLocation(latField.text, lonField.text)
        }
        Pill {
          anchors.verticalCenter: parent.verticalCenter
          label: NightLightState.detecting ? "Detecting…" : "Detect"
          enabled: !NightLightState.detecting
          onClicked: NightLightState.detectLocation()
        }
      }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Detect looks up your approximate location from your IP address (ipinfo.io) once. "
            + "The weather widget uses the same location."
        color: Theme.textMuted
        font.pixelSize: Theme.fs(10)
      }

      Text {
        visible: NightLightState.lastError !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        text: NightLightState.lastError
        color: Theme.warning
        font.pixelSize: Theme.menuFontBody
      }
    }
  }

  // The fields are edited in place, so they are refilled rather than bound:
  // on open and whenever Detect or Save brings back a new location.
  function fillLocation() {
    latField.text = panel.loc ? String(panel.loc.latitude) : ""
    lonField.text = panel.loc ? String(panel.loc.longitude) : ""
  }
  onLocChanged: fillLocation()
  onVisibleChanged: if (visible) { fillLocation(); card.forceActiveFocus() }
}

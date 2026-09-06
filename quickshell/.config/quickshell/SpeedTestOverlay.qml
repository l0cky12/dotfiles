import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
  id: panel

  required property var output
  screen: output
  visible: SpeedTestState.panelVisible && output &&
    SpeedTestState.panelScreen === output.name
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.namespace: "quickshell-speed-test"

  readonly property real contentScale: Math.min(1.0, width / Theme.fs(920), height / Theme.fs(610))
  readonly property string connectionLabel: {
    if (NetworkState.connType === "ethernet")
      return "Ethernet"
    if (NetworkState.connType === "wifi")
      return NetworkState.ssid !== "" ? NetworkState.ssid : "Wi-Fi"
    return "Internet connection"
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.bgDeep
  }

  Image {
    anchors.fill: parent
    source: SpeedTestState.wallpaperPath
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    visible: status === Image.Ready
    opacity: 0.36
  }

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(Theme.bgDeep.r, Theme.bgDeep.g, Theme.bgDeep.b, 0.68) }
      GradientStop { position: 0.55; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.82) }
      GradientStop { position: 1.0; color: Qt.rgba(Theme.bgDeep.r, Theme.bgDeep.g, Theme.bgDeep.b, 0.96) }
    }
  }

  FocusScope {
    anchors.fill: parent
    focus: panel.visible
    Keys.onPressed: event => {
      if (event.key === Qt.Key_Escape) {
        SpeedTestState.close()
        event.accepted = true
      } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) &&
                 !SpeedTestState.running) {
        SpeedTestState.start()
        event.accepted = true
      }
    }
  }

  Column {
    anchors.centerIn: parent
    width: Math.min(panel.width - Theme.fs(48), Theme.fs(820))
    spacing: Theme.fs(22) * panel.contentScale

    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Theme.fs(6)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: panel.connectionLabel.toUpperCase()
        color: Theme.accent
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(12)
        font.bold: true
        font.letterSpacing: Theme.fs(3)
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: SpeedTestState.running ? "MEASURING BANDWIDTH" :
          (SpeedTestState.result ? Math.round(SpeedTestState.pingMs) + " ms ping" : "READY")
        color: Theme.textMuted
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(10)
        font.letterSpacing: Theme.fs(1)
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Theme.fs(42) * panel.contentScale

      SpeedGauge {
        width: Theme.fs(330) * panel.contentScale
        height: Theme.fs(285) * panel.contentScale
        label: "Download"
        mbps: SpeedTestState.downloadMbps
        running: SpeedTestState.running
        accentColor: Theme.accent
      }
      SpeedGauge {
        width: Theme.fs(330) * panel.contentScale
        height: Theme.fs(285) * panel.contentScale
        label: "Upload"
        mbps: SpeedTestState.uploadMbps
        running: SpeedTestState.running
        accentColor: Theme.accentAlt
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: SpeedTestState.lastError !== ""
      text: SpeedTestState.lastError
      color: Theme.error
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(12)
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Theme.fs(142)
      height: Theme.fs(38)
      radius: Theme.radiusRow
      color: rerun.containsMouse ? Theme.selection : "transparent"
      border.width: Theme.borderWidth
      border.color: Theme.borderColor
      visible: !SpeedTestState.running

      Text {
        anchors.centerIn: parent
        text: SpeedTestState.result || SpeedTestState.lastError !== "" ? "RUN AGAIN" : "START"
        color: Theme.text
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(11)
        font.bold: true
      }
      MouseArea {
        id: rerun
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: SpeedTestState.start()
      }
    }
  }

  Rectangle {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Theme.fs(14)
    width: Theme.fs(36)
    height: width
    color: closeArea.containsMouse ? Theme.selection : "transparent"
    border.width: Theme.borderWidth
    border.color: Theme.borderAccent

    Text {
      anchors.centerIn: parent
      text: "×"
      color: Theme.accent
      font.pixelSize: Theme.fs(25)
    }
    MouseArea {
      id: closeArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: SpeedTestState.close()
    }
  }
}

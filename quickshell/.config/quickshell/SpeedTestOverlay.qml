import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects

PanelWindow {
  id: window

  required property var output
  screen: output
  visible: NetworkState.speedTestVisible
    && NetworkState.speedTestScreen === output.name
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "hyprland-network-speedtest"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  readonly property string wallpaperStatePath: {
    const override = Quickshell.env("HYPR_WALLPAPER_STATE_FILE")
    if (override)
      return override
    const stateHome = Quickshell.env("XDG_STATE_HOME") ||
      (Quickshell.env("HOME") + "/.local/state")
    return stateHome + "/hyprland-desktop/wallpaper/current"
  }
  property string wallpaperPath: ""

  FileView {
    id: wallpaperState
    path: window.wallpaperStatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        window.wallpaperPath = JSON.parse(wallpaperState.text()).path || ""
      } catch (error) {
        window.wallpaperPath = ""
      }
    }
    onLoadFailed: window.wallpaperPath = ""
  }

  Image {
    id: wallpaper
    anchors.fill: parent
    source: window.wallpaperPath === "" ? "" : "file://" + window.wallpaperPath
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    visible: false
    sourceSize.width: window.width
    sourceSize.height: window.height
  }

  MultiEffect {
    anchors.fill: parent
    source: wallpaper
    blurEnabled: true
    blur: 1.0
    blurMax: Theme.fs(24)
    visible: wallpaper.status === Image.Ready
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.background
    opacity: 0.62
  }

  FocusScope {
    id: input
    anchors.fill: parent
    focus: window.visible
    Keys.onEscapePressed: NetworkState.closeSpeedTest()

    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height * 0.14
      spacing: Theme.fs(34)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: NetworkState.speedTestConnection.toUpperCase()
        color: Theme.text
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(14)
        font.letterSpacing: Theme.fs(4)
        font.bold: true
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.fs(76)

        SpeedTestGauge {
          value: NetworkState.downloadMbps
          peak: NetworkState.downloadPeakMbps
          active: NetworkState.speedTestPhase === "download"
          label: "Download"
        }
        SpeedTestGauge {
          value: NetworkState.uploadMbps
          peak: NetworkState.uploadPeakMbps
          active: NetworkState.speedTestPhase === "upload"
          label: "Upload"
        }
      }

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !NetworkState.speedTestRunning
        width: Theme.fs(118)
        height: Theme.fs(32)
        radius: Theme.fs(6)
        color: Theme.surface

        Text {
          anchors.centerIn: parent
          text: "Run again"
          color: Theme.text
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(12)
          font.letterSpacing: Theme.fs(1)
        }
        MouseArea {
          anchors.fill: parent
          onClicked: NetworkState.runSpeedTest(NetworkState.speedTestScreen)
        }
      }
    }
  }

  onVisibleChanged: if (visible) input.forceActiveFocus()
}

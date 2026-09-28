import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects

// Full-screen disk speed test, styled after SpeedTestOverlay: a disk picker
// when more than one disk can be tested, then write, read, and random 4K dials
// that fill in the order the backend runs them.
PanelWindow {
  id: window

  required property var output
  screen: output
  visible: DiskState.overlayVisible
    && DiskState.overlayScreen === output.name
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "hyprland-disk-speedtest"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  readonly property bool picking: DiskState.phase === "pick"
  readonly property bool testing: DiskState.diskName !== "" && !picking
  readonly property bool finished: DiskState.phase === "complete" || DiskState.phase === "error"

  readonly property string wallpaperStatePath: {
    const override = Quickshell.env("HYPR_WALLPAPER_STATE_FILE")
    if (override)
      return override
    const stateHome = Quickshell.env("XDG_STATE_HOME") ||
      (Quickshell.env("HOME") + "/.local/state")
    return stateHome + "/hyprland-desktop/wallpaper/current"
  }
  property string wallpaperPath: ""

  function statusText() {
    switch (DiskState.phase) {
    case "loading": return "Finding disks…"
    case "mount": return "Mounting " + (DiskState.disk.mountDevice || DiskState.diskName) + "…"
    case "start": return "Preparing the test file…"
    case "error": return DiskState.lastError
    default: return ""
    }
  }

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
    Keys.onEscapePressed: DiskState.close()
    Keys.onUpPressed: DiskState.moveSelection(-1)
    Keys.onDownPressed: DiskState.moveSelection(1)
    Keys.onReturnPressed: window.picking ? DiskState.choose(DiskState.selectedIndex) : DiskState.runAgain()
    Keys.onEnterPressed: window.picking ? DiskState.choose(DiskState.selectedIndex) : DiskState.runAgain()

    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height * 0.14
      spacing: Theme.fs(34)

      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.fs(10)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: (window.testing ? DiskState.headerTitle() : "Disk speed test").toUpperCase()
          color: Theme.text
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(14)
          font.letterSpacing: Theme.fs(4)
          font.bold: true
        }
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Theme.fs(14)
          visible: detailText.text !== "" || cachedText.visible

          Text {
            id: detailText
            text: window.testing ? DiskState.headerDetail()
              : (window.picking ? "Choose a disk" : "")
            color: Theme.textMuted
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(12)
            font.letterSpacing: Theme.fs(1)
          }
          Text {
            id: cachedText
            visible: window.testing && !DiskState.direct
            text: "⚠ cached, numbers inflated"
            color: Theme.warning
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(12)
            font.letterSpacing: Theme.fs(1)
          }
        }
      }

      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: window.picking
        spacing: Theme.fs(10)

        Repeater {
          model: DiskState.disks

          Rectangle {
            id: card
            required property var modelData
            required property int index
            readonly property bool testable: DiskState.isTestable(modelData)
            readonly property bool selected: index === DiskState.selectedIndex

            width: Theme.fs(480)
            height: Theme.fs(62)
            radius: Theme.fs(8)
            color: Theme.surface
            border.width: selected ? Theme.fs(2) : Theme.borderWidth
            border.color: selected ? Theme.info : Theme.borderColor
            opacity: testable ? 1 : Theme.opacityUnavailable

            Row {
              anchors.fill: parent
              anchors.leftMargin: Theme.fs(18)
              anchors.rightMargin: Theme.fs(18)
              spacing: Theme.fs(16)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: card.modelData.removable ? "󰕓" : "󰋊"
                color: card.selected ? Theme.info : Theme.textMuted
                font.family: Theme.glyphFamily
                font.pixelSize: Theme.fs(24)
              }
              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.fs(4)

                Row {
                  spacing: Theme.fs(10)
                  Text {
                    id: modelText
                    text: card.modelData.model || card.modelData.name
                    color: Theme.text
                    font.family: Theme.glyphFamily
                    font.pixelSize: Theme.fs(13)
                    font.bold: true
                  }
                  Text {
                    visible: card.modelData.system === true
                    anchors.baseline: modelText.baseline
                    text: "SYSTEM"
                    color: Theme.info
                    font.family: Theme.glyphFamily
                    font.pixelSize: Theme.fs(10)
                    font.letterSpacing: Theme.fs(2)
                  }
                }
                Text {
                  text: DiskState.cardDetail(card.modelData)
                  color: Theme.textMuted
                  font.family: Theme.glyphFamily
                  font.pixelSize: Theme.fs(11)
                }
              }
            }
            MouseArea {
              anchors.fill: parent
              enabled: card.testable
              hoverEnabled: true
              onEntered: DiskState.selectedIndex = card.index
              onClicked: DiskState.choose(card.index)
            }
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: window.testing
        spacing: Theme.fs(56)

        SpeedTestGauge {
          value: DiskState.writeMbs
          peak: DiskState.writePeakMbs
          active: DiskState.phase === "write"
          label: DiskState.failedPhase === "write" ? "Write ✕" : "Write"
          unit: "MB/s"
          scaleSteps: DiskState.scaleSteps
        }
        SpeedTestGauge {
          value: DiskState.readMbs
          peak: DiskState.readPeakMbs
          active: DiskState.phase === "read"
          label: DiskState.failedPhase === "read" ? "Read ✕" : "Read"
          unit: "MB/s"
          scaleSteps: DiskState.scaleSteps
        }
        SpeedTestGauge {
          value: DiskState.randomMbs
          peak: DiskState.randomPeakMbs
          active: DiskState.phase === "random"
          label: DiskState.failedPhase === "random" ? "4K Random ✕" : "4K Random"
          unit: "MB/s"
          scaleSteps: DiskState.scaleSteps
          detail: DiskState.randomDetail()
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: text !== ""
        width: Math.min(implicitWidth, window.width * 0.6)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: window.statusText()
        color: DiskState.phase === "error" ? Theme.error : Theme.textMuted
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(12)
        font.letterSpacing: Theme.fs(1)
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: window.testing && window.finished && !DiskState.running
        spacing: Theme.fs(14)

        Rectangle {
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
            onClicked: DiskState.runAgain()
          }
        }
        Rectangle {
          visible: DiskState.testableCount > 1
          width: Theme.fs(118)
          height: Theme.fs(32)
          radius: Theme.fs(6)
          color: Theme.surface

          Text {
            anchors.centerIn: parent
            text: "Change disk"
            color: Theme.text
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(12)
            font.letterSpacing: Theme.fs(1)
          }
          MouseArea {
            anchors.fill: parent
            onClicked: DiskState.changeDisk()
          }
        }
      }
    }
  }

  onVisibleChanged: if (visible) input.forceActiveFocus()
}

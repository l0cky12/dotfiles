import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Scope {
  id: bar
  property bool barVisible: true
  property bool barTransparent: false
  property bool barAtBottom: false

  // Panels opened from a keybind rather than a click target the focused
  // monitor, so they land where the user is looking.
  function focusedScreen(): string {
    const f = Hyprland.focusedMonitor
    return f ? f.name : ""
  }
  IpcHandler {
    target: "bar"
    function toggle(): string {
      bar.barVisible = !bar.barVisible
      return JSON.stringify({visible: bar.barVisible})
    }
    function statusJson(): string {
      return JSON.stringify({visible: bar.barVisible})
    }
  }

  IpcHandler {
    target: "network"
    function toggle(): void {
      NetworkState.togglePanel(bar.focusedScreen())
    }
    function manage(): void {
      NetworkState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "speedtest"
    function toggle(): void {
      SpeedTestState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "audio"
    function toggle(): void {
      AudioState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "bluetooth"
    function toggle(): void {
      BluetoothState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "media"
    function toggle(): void {
      MediaState.togglePanel(bar.focusedScreen())
    }

  }

  IpcHandler {
    target: "visualizer"
    function toggle(): void {
      VisualizerState.toggle()
    }
  }

  IpcHandler {
    target: "clipboard"
    function toggle(): void {
      ClipboardState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "dashboard"
    function toggle(): void {
      DashboardState.togglePanel(bar.focusedScreen())
    }

  }

  IpcHandler {
    target: "display"
    function toggle(): void {
      DisplayState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "keybinds"
    function toggle(): void {
      KeybindsState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "theme"
    function toggle(): void {
      ThemeState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "wallpaper"
    function toggle(): void {
      WallpaperState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "webapps"
    function toggle(): void {
      WebAppState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "modes"
    function toggle(): void {
      ModesState.togglePanel(bar.focusedScreen())
    }
  }

  // The keybindings palette is a fullscreen overlay rather than a bar-anchored
  // popup, so it gets its own per-screen instance instead of living inside a
  // bar widget. Only the one on the focused monitor ever becomes visible.
  Variants {
    model: Quickshell.screens

    KeybindsPanel {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
    }
  }

  // Same arrangement for the theme gallery: fullscreen, so per-screen instances
  // gated on ThemeState.panelScreen rather than one window that has to move.
  Variants {
    model: Quickshell.screens

    ThemePicker {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
    }
  }

  // The wallpaper gallery deliberately shares the exact theme cover-flow.
  Variants {
    model: Quickshell.screens

    ThemePicker {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
      controller: WallpaperState
      layerNamespace: "quickshell-wallpaper-picker"
    }
  }

  // And the web app manager, same arrangement again.
  Variants {
    model: Quickshell.screens

    WebAppPanel {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
    }
  }

  Variants {
    model: Quickshell.screens

    ModesPanel {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
    }
  }

  Variants {
    model: Quickshell.screens

    SpeedTestOverlay {
      required property var modelData
      output: modelData
    }
  }

  Variants {
    model: Quickshell.screens

    CavaEdgeVisualizer {
      required property var modelData
      output: modelData
    }
  }

  Variants {
    model: Quickshell.screens

    CavaEdgeVisualizer {
      required property var modelData
      output: modelData
      anchorTop: true
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: bar.barVisible

      anchors {
        top: !bar.barAtBottom
        bottom: bar.barAtBottom
        left: true
        right: true
      }
      implicitHeight: Theme.barHeight

      // Content scale for a 45px bar: the tallest chrome is the workspace cell
      // at 26 design px, so 1.25x gives 33px inside 45px -- about 6px of padding
      // above and below. Capped there rather than filling the bar edge to edge.
      // The width/800 term only bites on a bar narrower than 1000px, where the
      // fixed content (Arch icon, 10 workspace cells, status icons, weekday
      // clock) would otherwise crowd out the centred media widget.
      readonly property real barScale: Math.max(1.0, Math.min(1.25, width / 800))

      Rectangle {
        anchors.fill: parent
        color: bar.barTransparent ? "transparent" : Theme.bg
      }

      // Empty bar space toggles transparency on double click. Dragging it
      // down/up moves the bar between screen edges without stealing clicks
      // from any widget layered above this area.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        property real pressedY: 0
        onPressed: mouse => pressedY = mouse.y
        onReleased: mouse => {
          const distance = mouse.y - pressedY
          if (distance > Theme.fs(12))
            bar.barAtBottom = true
          else if (distance < -Theme.fs(12))
            bar.barAtBottom = false
        }
        onDoubleClicked: bar.barTransparent = !bar.barTransparent
      }

      // Arch button first, then workspaces.
      Row {
        id: leftGroup
        anchors.left: parent.left
        anchors.leftMargin: Theme.fs(8 * panel.barScale)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.fs(6 * panel.barScale)

        ArchIcon { screenName: panel.modelData.name; barScale: panel.barScale }
        WorkspacesModule { id: workspaces; barScale: panel.barScale }
      }

      // The clock itself is the center anchor. Indicators grow left while
      // keyboard/weather grow right, so changing either side never nudges it.
      Item {
        id: centerGroup
        anchors.fill: parent

        Text {
          id: clockLabel
          anchors.centerIn: parent
          text: Qt.formatDateTime(ClockState.zonedDate(), "h:mm AP")
          color: Theme.text
          font.family: Theme.uiFamily
          font.bold: true
          font.pixelSize: Theme.fs(14 * panel.barScale)
        }

        Row {
          anchors.right: clockLabel.left
          anchors.rightMargin: Theme.fs(8 * panel.barScale)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.fs(3 * panel.barScale)

          RecordIcon { barScale: panel.barScale }
          ModeIndicators { screenName: panel.modelData.name; barScale: panel.barScale }
          UpdatesIcon { barScale: panel.barScale }
        }

        Row {
          anchors.left: clockLabel.right
          anchors.leftMargin: Theme.fs(8 * panel.barScale)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.fs(7 * panel.barScale)

          KeyboardLayoutWidget { barScale: panel.barScale }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: WeatherState.hasData
                  ? WeatherState.codeGlyph(WeatherState.current.code,
                                           WeatherState.current.isDay) : ""
            color: Theme.text
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(15 * panel.barScale)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: WeatherState.hasData
                  ? WeatherState.fmtTemp(WeatherState.current.temp) : "weather…"
            color: Theme.textDim
            font.family: Theme.uiFamily
            font.pixelSize: Theme.fs(12 * panel.barScale)
          }
        }

        // Clicking the centered clock keeps the dashboard behavior.
        MediaPanel {
          anchorItem: clockLabel
          ownerScreen: panel.modelData.name
        }

        DashboardPanel {
          anchorItem: clockLabel
          ownerScreen: panel.modelData.name
        }

        MouseArea {
          anchors.fill: clockLabel
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton
          onClicked: DashboardState.togglePanel(panel.modelData.name)
        }
      }

      Row {
        id: rightGroup
        anchors.right: parent.right
        anchors.rightMargin: Theme.fs(8 * panel.barScale)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.fs(2 * panel.barScale)

        SystemTrayWidget { parentWindow: panel; barScale: panel.barScale }
        AgentIcon { barScale: panel.barScale }
        WindowsVmIcon { barScale: panel.barScale }
        ClipboardIcon { screenName: panel.modelData.name; barScale: panel.barScale }
        BluetoothIcon { screenName: panel.modelData.name; barScale: panel.barScale }
        NetworkIcon { screenName: panel.modelData.name; barScale: panel.barScale }
        AudioIcon { screenName: panel.modelData.name; barScale: panel.barScale }
        DisplayIcon { screenName: panel.modelData.name; barScale: panel.barScale }

        IconButton {
          anchors.verticalCenter: parent.verticalCenter
          glyph: String.fromCodePoint(0xf0425) // md-power
          size: Theme.fs(28 * panel.barScale)
          glyphSize: Theme.fs(15 * panel.barScale)
          onClicked: powerMenu.running = true
        }

        Process {
          id: powerMenu
          command: ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/power-menu.sh"]
        }
      }
    }
  }
}

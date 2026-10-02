import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Scope {
  id: bar
  property bool barVisible: true

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
    function speedTest(): void {
      NetworkState.runSpeedTest(bar.focusedScreen())
    }
    // The lmenu "Share Wi-Fi as a QR code" rows: opens WifiQrOverlay on the
    // focused monitor without going through the network panel.
    function shareWifi(): void {
      NetworkState.showWifiQr(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "disk"
    function speedTest(): void {
      DiskState.open(bar.focusedScreen())
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
    // screensaver-lock keeps these entries when it wipes history on lock.
    function pinnedPreviews(): string {
      return ClipboardState.pinnedPreviews()
    }
  }

  // The clipboard QR is an overlay rather than a bar panel, so it has no
  // toggle target of its own on the bar: the lmenu Capture row calls this.
  IpcHandler {
    target: "clipboard-qr"
    function toggle(): void {
      ClipboardQrState.show(bar.focusedScreen())
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
    target: "app-keybinds"
    function neovim(): void {
      AppKeybindsState.togglePanel(bar.focusedScreen(), "neovim")
    }
    function herdr(): void {
      AppKeybindsState.togglePanel(bar.focusedScreen(), "herdr")
    }
  }

  IpcHandler {
    target: "theme"
    function toggle(): void {
      ThemeState.togglePanel(bar.focusedScreen())
    }
    // Called by the generator after it installs themes/.active/theme.json.
    // Needed because that install is an atomic rename, which kills the file
    // watcher in Theme.qml -- see the comment there.
    function reload(): void {
      Theme.reloadPalette()
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
    // Super+Space, via ~/.local/bin/webapp-current. Takes no argument: the
    // script leaves the URL in $XDG_RUNTIME_DIR/webapp-current-url and
    // WebAppState reads it from there. See the handoff comment in
    // WebAppState.qml.
    function installCurrent(): void {
      WebAppState.installCurrent(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "modes"
    function toggle(): void {
      ModesState.togglePanel(bar.focusedScreen())
    }
  }

  // Super+Shift+N and the lmenu "Night light schedule…" row.
  IpcHandler {
    target: "nightlight"
    function toggle(): void {
      NightLightState.togglePanel(bar.focusedScreen())
    }
  }

  // lmenu opens from a Hyprland global shortcut (hl.dsp.global("quickshell:lmenu")
  // in keybindings.lua) rather than `quickshell ipc call`, so the keypress
  // reaches the shell without starting a process. The IPC target is for scripts
  // that want to open it at a route: `quickshell ipc call lmenu summon themes`.
  GlobalShortcut {
    name: "lmenu"
    description: "lmenu root"
    onPressed: LmenuState.toggle(bar.focusedScreen(), "")
  }

  IpcHandler {
    target: "lmenu"
    function toggle(route: string): void {
      LmenuState.toggle(bar.focusedScreen(), route)
    }
    function summon(route: string): void {
      LmenuState.summon(bar.focusedScreen(), route)
    }
    function close(): void {
      LmenuState.close()
    }
  }

  Variants {
    model: Quickshell.screens

    LmenuPanel {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
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

  Variants {
    model: Quickshell.screens

    KeybindsPanel {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
      controller: AppKeybindsState
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

    NightLightPanel {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
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

    SpeedTestOverlay {
      required property var modelData
      output: modelData
    }
  }

  Variants {
    model: Quickshell.screens

    DiskSpeedOverlay {
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

      // The bar is pinned to the top edge; there is no way to move it.
      anchors {
        top: true
        left: true
        right: true
      }
      implicitHeight: Theme.barHeight

      // Content scale for the bar: the tallest chrome is the workspace cell at
      // 26 design px, so 1.25x gives 33px inside a 40px island -- about 3px of
      // padding above and below. Narrow bars scale down instead, so the three
      // island groups keep their separation on a rotated monitor. See
      // Theme.barScaleFor for why the curve is what it is.
      readonly property real barScale: Theme.barScaleFor(width)

      // The strip paints nothing of its own. Everything visible is a BarIsland
      // floating on it, which is what makes the bar read as capsules over the
      // wallpaper instead of as a slab across the top of the screen.
      color: "transparent"

      // The whole reserved strip still swallows clicks, gaps between islands
      // included, so a drag that overshoots an island edge cannot land on
      // whatever sits behind the bar.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
      }

      BarIsland {
        id: leftIsland
        anchors.left: parent.left
        anchors.leftMargin: Theme.barSideMargin
        anchors.verticalCenter: parent.verticalCenter
        moduleSpacing: Theme.fs(4 * panel.barScale)

        WorkspacesModule { id: workspaces; barScale: panel.barScale }
      }

      // The clock is the center anchor. Indicators grow left without nudging it.
      Item {
        id: centerGroup
        anchors.fill: parent

        // Distance from the clock to each side row.
        readonly property int rowMargin: Theme.fs(8 * panel.barScale)

        // Scaling the content down keeps the islands apart on narrow bars;
        // this shift is the backstop when scaling is not enough.
        //
        // Every term is a width or the x of something the offset does not
        // move. Deriving any of it from leadingRow.x or clockLabel.x would
        // feed the offset back into itself and cycle the binding.
        readonly property real clockBase: (width - clockLabel.width) / 2
        readonly property real leadingNeed:
          rowMargin + leadingRow.width + Theme.barIslandPadding
        readonly property real trailingNeed:
          rowMargin + Theme.barIslandPadding
        readonly property real minShift:
          leftIsland.x + leftIsland.width + Theme.barIslandGap
          - clockBase + leadingNeed
        readonly property real maxShift:
          rightGroup.x - Theme.barIslandGap
          - clockBase - clockLabel.width - trailingNeed
        // When even the clamp cannot satisfy both sides there is genuinely no
        // room, so split the shortfall rather than dumping all of it on one
        // neighbour.
        readonly property real collisionShift:
          minShift > maxShift ? (minShift + maxShift) / 2
                              : Math.min(Math.max(0, minShift), maxShift)

        // Drawn from the indicator row and clock rather than wrapping them in a
        // BarIsland, because the clock has to stay pinned to the screen centre.
        // A content-sized capsule would centre itself instead, and the time
        // would drift sideways every time a mode pill appeared.
        Rectangle {
          id: centerIsland
          anchors.verticalCenter: parent.verticalCenter
          x: leadingRow.x - Theme.barIslandPadding
          width: clockLabel.x + clockLabel.width + centerGroup.rowMargin
                 + Theme.barIslandPadding - x
          height: Theme.barIslandHeight
          radius: height / 2
          color: Theme.bgDeep
        }

        // Time over date, then the current conditions. One item, so the
        // centring and collision maths above treat the whole block as the clock.
        Row {
          id: clockLabel
          anchors.centerIn: parent
          // Zero whenever the bar is wide enough, which is every landscape
          // monitor. The clock only leaves true centre to avoid a collision.
          anchors.horizontalCenterOffset: centerGroup.collisionShift
          spacing: Theme.fs(14 * panel.barScale)

          Column {
            anchors.verticalCenter: parent.verticalCenter

            Text {
              text: Qt.formatDateTime(ClockState.zonedDate(), "hh:mm:ss AP")
              color: Theme.green
              font.family: Theme.glyphFamily
              font.bold: true
              font.pixelSize: Theme.fs(12 * panel.barScale)
            }

            Text {
              text: Qt.formatDateTime(ClockState.zonedDate(), "dddd, MMMM d")
              color: Theme.textDim
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(8 * panel.barScale)
            }
          }

          // Hidden until the first fetch lands, so the clock never shows a
          // placeholder temperature.
          Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: WeatherState.hasData
            spacing: Theme.fs(6 * panel.barScale)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: WeatherState.hasData
                    ? WeatherState.codeGlyph(WeatherState.current.code,
                                             WeatherState.current.isDay) : ""
              color: Theme.text
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(16 * panel.barScale)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: WeatherState.hasData
                    ? WeatherState.current.temp.toFixed(1) + "°F" : ""
              color: Theme.text
              font.family: Theme.glyphFamily
              font.bold: true
              font.pixelSize: Theme.fs(13 * panel.barScale)
            }
          }
        }

        MouseArea {
          id: clockClickGuard
          anchors.fill: clockLabel
          acceptedButtons: Qt.LeftButton
          onClicked: calendarPopup.visible = !calendarPopup.visible
        }

        CalendarPopup {
          id: calendarPopup
          anchorItem: clockLabel
        }

        Row {
          id: leadingRow
          anchors.right: clockLabel.left
          anchors.rightMargin: centerGroup.rowMargin
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.fs(3 * panel.barScale)

          RecordIcon { barScale: panel.barScale }
          ModeIndicators { screenName: panel.modelData.name; barScale: panel.barScale }
        }

        // The media panel anchors to the centered clock and opens through the
        // `media` IPC target. Left-clicking the clock opens the calendar.
        MediaPanel {
          anchorItem: clockLabel
          ownerScreen: panel.modelData.name
        }
      }

      Row {
        id: rightGroup
        anchors.right: parent.right
        anchors.rightMargin: Theme.barSideMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.barIslandGap

        BarIsland {
          id: trayIsland
          anchors.verticalCenter: parent.verticalCenter
          moduleSpacing: Theme.fs(2 * panel.barScale)

          AppLauncher { barScale: panel.barScale }
          WindowsVmIcon { barScale: panel.barScale }
          BluetoothIcon { screenName: panel.modelData.name; barScale: panel.barScale }
          NetworkIcon { screenName: panel.modelData.name; barScale: panel.barScale }
          AudioIcon { screenName: panel.modelData.name; barScale: panel.barScale }
          BatteryIcon { barScale: panel.barScale }
        }

        // Power gets a circular island of its own. It is the only destructive
        // control on the bar, so it does not share a capsule with the icons a
        // mis-aimed click would otherwise be one pixel away from.
        BarIsland {
          id: powerIsland
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: Theme.barIslandHeight

          IconButton {
            id: powerButton
            anchors.verticalCenter: parent.verticalCenter
            bordered: false
            glyph: String.fromCodePoint(0xf0425) // md-power
            size: Theme.fs(28 * panel.barScale)
            glyphSize: Theme.fs(15 * panel.barScale)
            onClicked: powerPopup.visible = !powerPopup.visible
          }
        }
      }

      PowerPopup {
        id: powerPopup
        anchorItem: powerButton
      }

      // Keep the clipboard and display panels available through their IPC
      // shortcuts after removing their bar icons.
      ClipboardPanel {
        anchorItem: trayIsland
        ownerScreen: panel.modelData.name
      }

      DisplayPanel {
        anchorItem: trayIsland
        ownerScreen: panel.modelData.name
      }
    }
  }
}

# Quickshell shell

Quickshell is the bar, the panels, the notification daemon, the clipboard
browser, the theme picker, and the on-screen displays. It is the only bar. There
are 95 QML files in `quickshell/.config/quickshell/`.

## Root

Hyprland starts `quickshell`, which loads `shell.qml`:

```qml
Scope {
  readonly property var batteryState: BatteryState
  Bar {}
  Variants {
    model: Quickshell.screens
    DesktopClock { required property var modelData; output: modelData }
  }
  Notifications.NotificationRoot {}
  VideoDownloadRoot {}
}
```

Five things: battery monitoring, the bar, one desktop clock per screen, the
notification service, and the browser-video progress service.

A second instance runs separately as `quickshell -c cava-visualizer`, configured
from `quickshell/.config/quickshell/cava-visualizer/`.

## Bar layout

One top-layer bar per screen. The bar strip itself is transparent and paints
nothing: everything you see is an **island** — a black stadium-shaped capsule
(`BarIsland.qml`) floating over the wallpaper, holding a group of **modules**.
The strip still reserves its full height, so windows tile below it and never
slide underneath a capsule.

Content scales with `barScale` (`Theme.barScaleFor`), capped at 1.25×, which is
what makes the tallest chrome (the 26 design-px workspace cell) sit at 33 px
inside a 40 px island. The reserved height is that island plus a 5 px gap above
and below.

Narrow bars scale down. If that still leaves too little room, the clock shifts
off centre (`centerGroup.collisionShift`) to keep the capsules apart.

Islands are spread to the two edges rather than clustered: workspaces hard left,
the clock centred, the tray and power hard right.

| Island | Holds |
| --- | --- |
| `leftIsland` | `WorkspacesModule` |
| `centerIsland` | recording and mode indicators, clock |
| `trayIsland` | launcher, agent, VM, Bluetooth, network, audio, battery when present |
| `powerIsland` | the power button, alone, circular |

An island is sized to its content, so it shrinks when a module hides itself —
the battery on a desktop, the VM icon when the container is down. Its colour is
`Theme.bgDeep`, not a hardcoded black, so a light palette still gets a legible
bar. Its radius is deliberately *not* `Theme.hyprRounding`: the capsule is the
design, and a theme setting rounding to 4 would flatten it back into a slab.

`powerIsland` is separate on purpose. Power is the only destructive control on
the bar, so it does not share a capsule with the icon a mis-aimed click would
otherwise be one pixel away from.

**Left** — `WorkspacesModule` has fixed cells for workspaces 1–10. Clicking one
switches to it.

**Centre** — the clock is the anchor. The indicator row grows left, so changing
it does not nudge the time. The clock opens the calendar.

| Position | Widget |
| --- | --- |
| left of the clock | `RecordIcon`, `ModeIndicators` |
| the anchor | the clock itself |

The `MediaPanel` anchors to the clock and opens through the `media` IPC target.

**Right** — `AppLauncher`, `AgentIcon`, `WindowsVmIcon`, `BluetoothIcon`,
`NetworkIcon`, `AudioIcon`, `BatteryIcon` when present, then the power button.

`tests/omakub-bar-layout.test.sh` asserts the bar still mounts this component
set, so adding or removing a widget means updating that list. It also asserts
the island structure: that the strip stays transparent, that the four islands
exist, that power stays out of the tray capsule, and that the reserved height
still clears the island on both sides.

## Bar interactions

- **Empty bar space**: inert. The bar is pinned to the top edge and cannot be
  moved.
- **Display**: Super+Ctrl+D opens the display panel.
- **Network**: opens the themed NetworkManager panel.
- **Bluetooth**: connected devices as hero cards, paired devices below, discovery
  folded behind a scan button. Pointer-driven; Escape closes.
- **Audio**: panel on left or middle click, mute on right click, 3% wheel steps.
- **Clipboard**: Super+Ctrl+V opens the cliphist browser.
- **Recording indicator**: only present while recording; clicking stops it.
- **Mode indicators**: pills for active night light, DND, stay-awake,
  automatic-screensaver-disabled, and error states. Clicking opens the modes
  panel. They show *observed* state, so an error appears instead of a false
  success.
- **Battery**: shows charge percentage and state; hidden when no laptop battery
  is present. Clicking opens the battery panel.
- **Windows VM icon**: appears while the container runs. Pulses amber while
  installation or startup waits for RDP, then goes solid accent when RDP is
  ready. Disappears when the VM stops.

## Desktop clock

`DesktopClock.qml` is a separate full-screen layer per output on the
**background** layer — above the wallpaper, below application windows. It has an
empty input mask and `ExclusionMode.Ignore`, so it is entirely click-through, and
it requests no keyboard focus. It draws in the bottom-right corner.

## Panels and their backends

| Panel | Backed by |
| --- | --- |
| Network | `scripts/network-control` over `nmcli`; Wi-Fi scan and connect, per-profile DNS and IPv4 overrides, and runtime-only `qrencode` Wi-Fi sharing |
| Bluetooth | `scripts/bluetooth-control` over `bluetoothctl` |
| Audio | Quickshell's PipeWire API |
| Media | Quickshell MPRIS; recent and pinned players; lyrics from `lrclib.net` |
| Display | Hyprland's monitor model, `ddcutil`, and `set-monitor-scale.sh` |
| Clipboard | `cliphist`, `wl-copy`, plus a local image preview index |
| Keybindings | live `hyprctl binds -j`; destructive entries are not invokable from the UI |
| Theme | the Hyprland theme generator |
| Wallpaper | the local/Wallhaven backend in `hypr-wallpaper-picker` |
| Web apps | the `webapp` shell backend |
| Modes | `desktop-mode` |

Secured Wi-Fi connections hand off to an interactive `nmtui` prompt, so the
password never crosses the panel boundary. The Wi-Fi QR is rendered at runtime
and never written to disk as a plaintext secret.

## IPC targets

Every panel is reachable over `quickshell ipc call <target> <function>`, which is
how the keybindings toggle them without spawning anything:

```text
audio      bar        bluetooth   clipboard   display
keybinds   media      modes       network     notifications
theme      videoDownload           visualizer
wallpaper  webapps
```

Example:

```bash
quickshell ipc call media toggle
quickshell ipc call notifications statusJson
```

## Theming

`Theme.qml` watches `~/.config/hypr/themes/.active/theme.json` and updates live —
no restart when you switch themes. It exposes the palette plus `Theme.fs()` for
font scaling (persisted through `gsettings`), a sans-serif UI family, and
JetBrainsMono Nerd Font for glyphs.

Widget code should read `Theme.*` rather than hardcoding colours. See
[Theming](Theming.md).

## Component map

Most widgets follow a three-file pattern: a singleton `XState.qml` holding data
and process calls, an `XIcon.qml` for the bar, and an `XPanel.qml` for the
dropdown.

| Area | Files |
| --- | --- |
| Bar shell | `Bar.qml`, `WorkspacesModule.qml`, `IconButton.qml`, `Card.qml` |
| Clock and calendar | `ClockState.qml`, `ClockWidget.qml`, `DesktopClock.qml`, `CalendarGrid.qml`, `CalendarPopup.qml`, `TimezonePopup.qml`, `DateTimeCard.qml` |
| System metrics (unmounted since the dashboard drawer was removed) | `SysState.qml`, `MediaTab.qml`, `PerfTab.qml`, `WorkspacesTab.qml`, `WeatherTab.qml`, `MetricCard.qml`, `Gauge.qml`, `HeroGauge.qml`, `ProfileCard.qml` |
| Network | `NetworkState/Icon/Panel.qml` |
| Audio and media | `AudioState/Icon/Panel.qml`, `AudioPanelContent.qml`, `VolumeSlider.qml`, `MediaState/Icon/Panel.qml`, `MediaPreviewCard.qml`, `LyricsState.qml`, `LyricsView.qml` |
| Visualiser | `CavaState.qml`, `CavaBars.qml`, `CavaEdgeVisualizer.qml`, `VisualizerState.qml` |
| Bluetooth | `BluetoothState/Icon/Panel/HeroCard/DeviceRow/Battery.qml` |
| Display | `DisplayState/Icon/Panel.qml` |
| Clipboard | `ClipboardState/Icon/Panel.qml` |
| Notifications | `notifications/` (see [Notifications](Notifications.md)), `NotifyState.qml`, `NotifyIcon.qml`, `DndIcon.qml` |
| Battery | `BatteryState.qml`, `battery/BatteryLogic.js`, `battery/BatteryConfig.qml`, `battery/config.json` |
| Modes | `ModesState.qml`, `ModesPanel.qml`, `ModeIndicators.qml` |
| Theme | `Theme.qml`, `ThemeState.qml`, `ThemePicker.qml`, `ThemePreview.qml`, `ThemeSlice.qml` |
| Wallpaper | `WallpaperState.qml` |
| Web apps | `WebAppState.qml`, `WebAppPanel.qml` |
| Capture | `RecordState.qml`, `RecordIcon.qml` |
| Updates | `UpdatesState.qml`, `UpdatesIcon.qml` |
| Video download | `VideoDownloadRoot/State/Overlay/Card.qml` |
| Windows VM | `WindowsVmState.qml`, `WindowsVmIcon.qml` |
| Keybindings | `KeybindsState.qml`, `KeybindsPanel.qml` |
| Misc | `SystemTrayWidget.qml`, `KeyboardLayoutWidget.qml`, `AgentIcon.qml`, `WeatherState.qml`, `WeatherMiniCard.qml` |

## Smoke tests

Several components ship a headless smoke config that loads them, waits a few
seconds, and quits:

```bash
QT_QPA_PLATFORM=offscreen quickshell -p quickshell/.config/quickshell/OmakubBarSmoke.qml
```

Available: `OmakubBarSmoke`, `NotificationSmoke`, `BatterySmoke` (requires
`BATTERY_SMOKE_TEST=1`), `BluetoothSmoke`,
`NetworkSmoke`, `ModesSmoke`, `UpdatesSmoke`,
`VideoDownloadSmoke`, `WindowsVmSmoke`, `ClockWidgetSmoke`, `AudioPanelSmoke`.

## Reloading

Quickshell watches its files and hot-reloads QML edits. When that is not enough:

```bash
quickshell log                       # concise service logs
quickshell kill && quickshell --daemonize
```

If the bar does not appear at all, check that the generated
`~/.config/hypr/themes/.active/theme.json` exists — see
[Troubleshooting](Troubleshooting.md#quickshell-bar-or-panels-do-not-appear).

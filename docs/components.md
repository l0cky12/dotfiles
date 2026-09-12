# Desktop components

## Quickshell: active shell and bar

Hyprland starts `quickshell`, which loads
`quickshell/.config/quickshell/shell.qml`. The root creates the bar, notification
service, and browser-video progress service.

### Bar layout

One top-layer bar is created per screen. Its active layout is:

| Area | Modules |
| --- | --- |
| Left | fixed workspace cells 1–10 |
| Center, left of clock | recording status, desktop-mode status, updates, battery (when present) |
| Center | clock |
| Center, right of clock | keyboard layout and weather |
| Right | system tray, agent, Windows VM, clipboard, Bluetooth, network, audio, display, power |

Workspace buttons switch to their numbered workspace. Other interactions include:

- Clock: dashboard. Also reachable over IPC via the `dashboard` target's
  `toggle` call.
- Media: media panel.
- Display: display panel; wheel adjusts DDC/CI brightness.
- Network: themed NetworkManager panel; secured Wi-Fi connections use an
  interactive `nmtui` prompt so the password never crosses the panel boundary.
- Bluetooth: enable/disable, scan, pair, connect, disconnect, trust, and forget
  devices. The list is keyboard navigable (arrows/Home/End/PageUp/PageDown to
  select, Enter for the primary action, `CTRL+T` trust, `CTRL+Delete` forget,
  `CTRL+S` scan, `CTRL+B` power, Escape to close) and sorts connected devices
  first.
- Audio: panel on left/middle click, mute on right click, 3% wheel adjustment.
  The panel keeps the master output controls and adds live output/input device
  switching, available PipeWire node descriptions, and per-application
  playback volume and mute controls capped at 100%. Empty device or application
  sections collapse, with a muted unavailable state when PipeWire has no useful
  nodes.
- Recording indicator: appears while recording and stops it when clicked.
- Desktop-mode indicators: active night light, DND, stay-awake,
  automatic-screensaver-disabled, and error states; click to open the modes panel.
- Clipboard: clipboard-history panel.
- Battery: charge percentage and state; hidden entirely when no laptop battery is present.
- Clock: calendar on left click, time-format cycle on right click, timezone cycle
  on middle click.

### Panels and data sources

| Panel | Implementation / external interfaces |
| --- | --- |
| Network | `network-control` over NetworkManager `nmcli`; Wi-Fi scan/connect, profile DNS/IPv4 changes, and runtime-only `qrencode` Wi-Fi sharing |
| Bluetooth | Hyprland script backend over `bluetoothctl` |
| Audio | Quickshell PipeWire API; default output/input switching and live per-application playback controls |
| Media | Quickshell MPRIS; recent/pinned players; lyrics from `lrclib.net` |
| Display | Hyprland monitor model, `ddcutil`, monitor-scale helper |
| Dashboard | `/proc`, `df`, shell commands, Open-Meteo weather API |
| Clipboard | `cliphist`, `wl-copy`, local image preview/index state |
| Keybindings | live `hyprctl binds -j`; destructive entries are not invoked from UI |
| Theme | Hyprland theme generator |
| Wallpaper | local/Wallhaven wallpaper backend |
| Web apps | shell backend creating/removing launchers |

IPC targets let keybindings toggle network, Bluetooth, display, media, clipboard,
dashboard, keybindings, theme, wallpaper, and web-app panels.

### Battery monitoring

`BatteryState.qml` reads the UPower display battery and reconciles its state at
most every 30 seconds. The state is inert on systems without a laptop battery.
While discharging, crossings at 20%, 10%, and 5% emit persistent critical
notifications through the existing `notify-send`/Quickshell notification path.
Each threshold fires once per discharge cycle. A charging sample makes the next
discharging sample a cold start, but suppression resets only after the charge
has risen by more than two percentage points or above the highest enabled
threshold, preventing charger flapping from replaying alerts. Thresholds are
configurable in `quickshell/.config/quickshell/battery/config.json`. Each
threshold accepts an
integer percentage from 0 through 100; 0 disables that threshold. Enabled
thresholds must be strictly descending (`warnPercent` > `severePercent` >
`criticalPercent`, ignoring disabled entries), or all three fall back to the
20/10/5 defaults with a warning.

Changing a threshold live re-arms that level at the current percentage, unless
an alert from a more-severe level has already fired in the same discharge cycle.

Run `bash tests/battery-alerts.test.sh` for configuration, wiring, and
notification-policy checks; its Node coverage lives in
`tests/battery-alerts.logic.test.js`. The optional Quickshell smoke fixture runs
with `BATTERY_SMOKE_TEST=1`, records commands at the notification Process
boundary, and never starts that Process or sends live battery notifications.

`quickshell/.config/quickshell/Theme.qml` watches
`~/.config/hypr/themes/.active/theme.json` and updates live. It uses a sans-serif
UI font and JetBrainsMono Nerd Font for glyphs, with font scaling persisted via
`gsettings`.

## Notifications

The active notification daemon is implemented below
`quickshell/.config/quickshell/notifications/`. It owns the standard
`org.freedesktop.Notifications` D-Bus interface and displays top-right cards.

Default policy from `config.json`:

| Setting | Value |
| --- | --- |
| History limit | 10 |
| Low urgency timeout | 5 seconds |
| Normal urgency timeout | 8 seconds |
| Ordinary maximum timeout | 30 seconds |
| Critical notifications | persistent |
| Card width | 380 pixels |
| Initial DND | disabled |

State, history, and cached images are stored under
`$XDG_STATE_HOME/hyprland-desktop/notifications`, with
`~/.local/state` as fallback. `notificationctl` provides the stable command-line
interface used by keybindings. DND bypasses are configured for selected system
apps such as battery monitoring, capture, night light, and web-app management.

The `swaync/` package is a retained rollback configuration. Its Hyprland
autostart line is commented and its generated CSS is maintained only by the
theme generator.

## Clipboard history

Two `wl-paste --watch` commands start from Hyprland autostart and pass text or
images to `hypr/.config/hypr/scripts/clipboard-store.sh`. The active UI is the
Quickshell clipboard panel, backed by `cliphist`. `cliphist/.config/cliphist/config`
sets a shared 200-entry maximum for text and images. The database is unencrypted
under `~/.cache/cliphist/db`; password-manager MIME markers and sensitive app
windows are excluded, and starting Hyprlock clears the live clipboard and
history.

Browser Copy URL writes to the real Wayland clipboard, so it enters this history
through the same watcher. Universal copy/cut/paste helpers adapt shortcuts for
terminal applications.

## Application launchers

Rofi is active. `SUPER+A` starts in the installed-applications view, while
`SUPER+SHIFT+A` opens a root menu for windows, applications, commands, reboot,
shutdown, and local development services. Its Development section can start or
stop MySQL, PostgreSQL, MariaDB, and Redis through Docker Compose. `Tab` and
`Shift+Tab` cycle the searchable modes, and
`SUPER+ALT+A` opens the separate web-app manager. Both Rofi views use generated
`rofi/.config/rofi/current-theme.rasi`, which imports the main Comet Glass layout
and current palette. The launcher uses Papirus icons, Nerd Font glyphs, fuzzy
matching, an approximately 42% width, and eight visible rows.

Rofi also drives the power menu, qalc-backed calculator, transcoding menus, and
emoji picker. The calculator has a compact layout over the generated palette;
the emoji picker imports the same palette and Comet Glass layout as the
application launcher, with a wider ten-row search view.

`wofi/` is a retained alternative configured for fuzzy `drun` search in a
Kitty-styled window. It is not bound or autostarted.

The optional `windows` package contributes a `Windows` desktop entry to the same
Rofi `drun` index. It calls `windows-vm launch`, the same backend used by
`SUPER+ALT+W`; no VM logic is duplicated in the launcher entry.

## Windows VM

The Windows integration uses Dockur Windows with KVM acceleration and a tracked
Compose template. TCP/UDP RDP on 3389 and the installation viewer on 8006 are
published only on `127.0.0.1`. `~/Windows` is mounted at `/shared`, becoming the
Windows `Shared` folder and `Z:` drive; the rest of the home directory is not
mounted. Both FreeRDP calls use `/cert:ignore`: certificate validation is
deliberately non-interactive for this loopback-only endpoint, preventing a
changed-certificate modal from dimming and blocking the current workspace.

FreeRDP opens fullscreen on the focused Hyprland display with dynamic
resolution, clipboard, sound, microphone, automatic reconnection, and a scale
derived from that monitor. A runtime lock prevents duplicate launcher sessions.
The existing Quickshell-backed `notify-send` path reports installation and
readiness progress, errors, and successful container lifecycle transitions.
`Windows VM started` is emitted after Compose starts a stopped container;
`Windows VM stopped` follows either `windows-vm stop` or the automatic stop after
a clean RDP exit. `--keep-alive`, readiness timeouts, and FreeRDP failures leave
the VM running and therefore do not emit the stop notification.

While the VM container is running, the bar shows a Windows icon. It pulses amber
while installation or startup is waiting for RDP, then becomes a solid accent
when RDP is ready. The icon disappears when the VM stops.

## Wallpaper

`SUPER+SHIFT+W` calls `~/.local/bin/hypr-wallpaper-picker` with no arguments,
which toggles the Quickshell cover-flow UI. The same tracked script at
`hypr/.local/bin/hypr-wallpaper-picker` implements the `index`, `search`, `apply`,
`activate`, `current`, `restore`, and `cleanup` operations used by the desktop.
The read-only `current` operation supplies the active image to Hyprlock. Successful
standalone and theme wallpaper applications atomically save the selected path
to `$XDG_STATE_HOME/hyprland-desktop/wallpaper/current`; autostart restores it.
Missing or stale state starts plain Hyprpaper without choosing a fallback image.

Search order is intentional:

1. Local JPEG/PNG filenames matching the query, on the first result page.
2. SFW Wallhaven results from `https://wallhaven.cc/api/v1/search`, sorted by
   relevance and requiring at least 1920×1080.
3. Additional Wallhaven pages when the UI requests them.

The backend caches previews, downloads the full selected image, validates it with
ImageMagick, restarts Hyprpaper, and applies the image in cover mode. By default,
it reads `~/Pictures/Wallpapers`. Standard Stow deployment of the tracked
`wallpaper/` package deploys its contents directly into `~/Pictures/Wallpapers`,
which is the picker's default directory.

Older `WallpaperSwitch.sh` and `WallpaperEffects.sh` scripts are retained but are
not used by the current binding.

## Lock screen and idle service

Hyprlock's entry point is `hypr/.config/hypr/hyprlock.conf`. It uses the
`hyprlock` PAM service, disables fingerprint authentication, imports generated
colors, and sources `layouts/hyprlock.conf`. That active layout contains a
large clock/date and a compact user/password card. Its colors, borders, radius,
opacity, scrim, shadow, and blur come from the active desktop theme. The
background reads the same persisted current-wallpaper state used by the picker
and theme tool; missing or stale state falls back to the active theme color.

Many alternate layouts and music/weather helpers are tracked. They are examples,
not active composition. Several assume `BAT0`, network access, extra fonts, or a
profile image, so inspect a layout before enabling it.

Hypridle supplies automatic lock/DPMS/suspend timing; see
[Hyprland](./hyprland.md#lock-idle-and-power-behavior).

## ASCII screensaver

The `screensaver/` package provides the `ttfx` renderer, per-monitor terminal
launcher, branding commands, and persistent automatic-off flag. The primary
Hypridle process launches it after 180 idle seconds without audio playback and
locks at 300 seconds. Manual force-launch ignores the automatic setting. See
[ASCII screensaver](./screensaver.md).

## Terminal and shell

Kitty is the Hyprland `terminal` setting. `kitty/.config/kitty/kitty.conf` selects JetBrainsMono Nerd
Font, 14-pixel window padding, background blur, powerline-style tabs, and includes
the generated `theme/current-theme.conf`. Remote control is allowed on a
per-process abstract Unix socket.

The optional `zsh/` package provides Oh My Zsh with Powerlevel10k, `git` and
`fzf-tab` plugins, fzf integrations, syntax highlighting, autosuggestions, eza
aliases, Neovim as `MANPAGER`, AI CLI aliases, and a Pokémon/Fastfetch greeting.
It also includes personal VPN and GAM paths that must be adapted without copying
private path details into shared documentation. Oh My Zsh itself is not tracked:
`zsh/.oh-my-zsh/` is ignored, because Oh My Zsh's own `.gitignore` excludes
`custom/` and therefore no tracked form of it could carry the Powerlevel10k theme
or the `fzf-tab` plugin that `.zshrc` depends on.

`fastfetch/` provides the normal and Pokémon-oriented display configurations; the
theme generator updates the configured accent color.

## Browser integration

The `browser` package supplies unpacked Manifest V3 extensions and Chrome Native
Messaging hosts.

### Copy URL

`ALT+SHIFT+L` gets the active tab URL and sends it to
`io.github.fhlkfds.copy_url`. `chromium-copy-url-host` validates the native
message, writes a non-empty URL with `wl-copy`, and sends a desktop notification.
Clipboard watchers record it normally.

### Download Video

`ALT+SHIFT+D` sends the active page URL to `com.omarchy.ytdlp`.
`chromium-ytdlp-host`:

1. accepts only HTTP(S) URLs;
2. prevents duplicate requests with a lock;
3. runs `yt-dlp --simulate` to detect supported media;
4. starts a detached real download under `$CHROMIUM_YTDLP_DIR` or `~/Videos`;
5. reports throttled progress to Quickshell's bottom-center OSD;
6. generates a square FFmpeg thumbnail; and
7. sends a completion notification whose action opens the file in mpv.

Unsupported pages and failed downloads generate critical notifications. Native
host manifests restrict each host to its exact extension ID.

Browser flag files load the extensions for Chromium, Chrome, Brave, and Edge
families. Absolute `/home/liam` paths mean the package is not account-portable as
checked in. The repair helper can inspect or repair command registration while the
browser is closed. Fixture tests live in `tests/browser-native-tools.test.sh`.

## Arch update indicator

The clock's hover tray shows every pending pacman and AUR package from
`arch-updates`. It refreshes every 90 minutes and after its click-only Kitty
update window closes. Pending updates use the active theme accent.

A failed repository or AUR check exits non-zero rather than reporting zero
updates, so the indicator keeps its last known counts, notes `Last check
failed` in the hover tray, and waits for the next 90-minute poll.

## Waybar: removed

The Waybar package was retired once Quickshell became the authoritative bar. It
had no startup command, no theme consumer that mattered, and its helper scripts
referenced an `open-terminal.sh` that never existed. The only script with a
consumer outside the package, `power-menu.sh`, now lives at
`hypr/.config/hypr/scripts/power-menu.sh` and still backs `SUPER+P`.

The rest is recoverable from Git history if it is ever wanted back.

## Noctalia: retained configuration

`noctalia/.config/noctalia/` contains settings and plugin data, but its Quickshell
startup line is commented. It includes user-specific monitor, location, and local
network state. Enabled plugin configuration includes calendar/clock, clipboard,
keybind, update, media-wallpaper, screen-toolkit, timer, and system-info features;
the assistant and DNS-switcher entries are disabled. Do not treat these settings
as part of the active shell without intentionally switching shells.

## XDG defaults

`xdg/.config/mimeapps.list` assigns Helium as the default HTTP/HTML handler,
Nautilus for directories, imv for images, mpv for video, Zathura for PDFs, and a
custom Kitty/Neovim desktop entry for text/code types. This matches the Hyprland
browser binding and autostart, which launch Helium. The desktop entry is tracked at
`xdg/.local/share/applications/nvim-kitty.desktop`. The MIME file also delegates
Packet Tracer file/protocol types and `t3code`/`claude-cli` URL schemes to
externally installed desktop entries; those applications are not supplied here.

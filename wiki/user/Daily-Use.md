# Daily use

Everyday recipes. Each one tells you the fast way (a keybinding), the menu way
(lmenu — the settings-and-actions menu opened with `Super+Shift+A`), and where
to read more. All keybindings are verified against the live config in
`hypr/.config/hypr/conf/keybindings.lua`.

## Change the wallpaper

Press `Super+Shift+W`. That runs `~/.local/bin/hypr-wallpaper-picker`
(`keybindings.lua`, line "wallpaper picker"). The wallpaper restorer reapplies
your last choice at every login, so the choice sticks.

- Menu way: lmenu → **Style → Background**.
- More: [Theming § Wallpapers](Theming.md).

## Switch the theme

Press `Super+Ctrl+Shift+Space`. This opens the fullscreen cover-flow theme
picker: type to filter, arrow keys to browse, and it applies only on `Enter`
or a click on the centre card (`quickshell/.config/quickshell/ThemePicker.qml`
— also reachable from the Display panel).

- Menu way: lmenu → **Style → Theme**.
- More: [Theming](Theming.md) — how palettes and the generator work.

## Connect to Wi-Fi

Press `Super+Ctrl+I` to open the network panel
(`quickshell/.config/quickshell/NetworkPanel.qml`). It has a Wi-Fi on/off
toggle and a scan; pick a network from the list. For anything the panel does
not cover (hidden networks, passwords for secured networks), the panel hands
over to `nmtui` — the terminal user interface for NetworkManager, the system
service that manages your connections.

- Menu way: lmenu → **Setup → Network → Manage connections** (same panel).
- Full management UI: `Super+Ctrl+W` opens the manage view directly.
- More: [Quickshell shell § Panels](Quickshell-Shell.md).

## Share your Wi-Fi as a QR code

While connected to Wi-Fi, open the network panel (`Super+Ctrl+I`) and press
the **Share Wi-Fi** button. A QR code appears — a phone scans it and joins the
same network without you ever reading out the password. On `main`, the code
shows inside the network panel itself; the centred fullscreen version of this
overlay is pending in PR #21's branch (`fix/centered-wifi-qr-overlay`, file
`WifiQrOverlay.qml`) and is not on main yet.

The same action is available in lmenu under **Trigger → Share → Share Wi-Fi as
a QR code**, which calls `~/.config/hypr/scripts/network-control qr`. That
script writes the QR to a file and deliberately never prints the password to
the screen.

- Requires `qrencode` installed and an active wireless connection (the menu
  row hides itself otherwise).
- More: [Scripts and CLIs](Scripts-and-CLIs.md).

## Notifications

Notifications are handled by Quickshell's own service
(`quickshell/.config/quickshell/notifications/`), with `notificationctl` as the
command-line control.

| Keys | Action |
|---|---|
| `Super+,` | Dismiss the newest notification. |
| `Super+Shift+,` | Dismiss all notifications. |
| `Super+Alt+,` | Invoke (activate) the newest notification's action. |
| `Super+Shift+Alt+,` | Show the notification history. |
| `Super+D` | Toggle do-not-disturb. |
| `Super+Ctrl+,` | Toggle do-not-disturb via the desktop-mode wrapper. |

- Menu way: lmenu → **Trigger → Toggle → Do not disturb**.
- More: [Notifications](Notifications.md).

## Screenshots and the capture toolkit

All capture keys are `Super+Shift` + a letter, chosen so they work on any
keyboard (`hypr/.config/hypr/scripts/capture/`):

| Keys | Action |
|---|---|
| `Super+Shift+S` | Screenshot (smart mode). Freezes the screen; drag for a region, click for the window under the pointer. |
| `Super+Alt+S` | Screenshot the focused monitor. |
| `Super+Alt+Ctrl+S` / `Super+Ctrl+Shift+S` | Screenshot the monitor after 5s / 10s. |
| `Super+Shift+R` | Start/stop a screen recording. |
| `Super+Shift+P` | Colour picker — click anywhere to grab a pixel's colour. |
| `Super+Shift+T` | Extract text from the screen (OCR — optical character recognition, turning pixels into text). |
| `Super+Ctrl+C` | Open the capture menu with all of the above. |
| `Super+Alt+C` | Toggle a webcam overlay; `Super+Alt+[` and `Super+Alt+]` resize it. |

- Menu way: lmenu → **Trigger → Capture**.
- More: [Troubleshooting § Capture failures](Troubleshooting.md).

## Lock, sleep, and desktop modes

| Keys | Action |
|---|---|
| `Super+L` | Lock the screen. |
| `Super+P` | Power menu (lock, suspend, reboot, shutdown). |
| `Super+Alt+M` | Desktop modes menu — stay awake, do-not-disturb, screensaver, and display sleep in one place. |
| `Super+Shift+I` | Toggle **stay awake** — blocks the idle timer that would lock or suspend the session. |
| `Super+Ctrl+Escape` | Start the ASCII screensaver on demand. |
| `Super+Ctrl+Shift+Escape` | Toggle the automatic screensaver. |

The idle behaviour (what happens when you walk away) is owned by Hypridle —
the idle daemon — configured in `hypr/.config/hypr/hypridle.conf`.

- Menu way: lmenu → **System** (lock, suspend, hibernate, logout, reboot,
  shutdown) and **Trigger → Toggle** (stay awake, screensaver).
- More: [Idle, lock, and desktop modes](Idle-Lock-and-Desktop-Modes.md).

## Clipboard history

Copy and cut are universal — they work across applications via
`scripts/universal-clipboard.sh`:

| Keys | Action |
|---|---|
| `Super+C` | Universal copy (application-aware). |
| `Super+X` | Universal cut. |
| `Super+V` | Universal paste. |
| `Super+Ctrl+V` | Open the clipboard history panel. |

`Ctrl+C` is deliberately *not* bound: terminals receive `Ctrl+Shift+C` for
copy instead, so shell interrupts keep working.

- Menu way: lmenu → **Trigger → Clipboard history**.
- More: [Keybindings § Clipboard](Keybindings.md).

## Other things you will do often

- **Open apps**: `Super+A` (launcher) or `Super+Shift+A` (lmenu → Apps).
- **Files**: `Super+E`; `Super+Shift+Alt+F` opens Files at the focused
  terminal's current directory.
- **Share a file across devices**: `Super+Ctrl+S` opens LocalSend
  (AirDrop-style sharing over the local network).
- **Reminders**: `Super+Ctrl+R` sets a countdown reminder, backed by systemd
  user timers (`menu/.local/bin/lmenu-reminder`).
- **Volume / brightness**: your keyboard's media keys work; on a desktop with
  no media keys use the audio panel (`Super+Ctrl+A`).

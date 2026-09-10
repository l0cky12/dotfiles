# Keybindings

All bindings in this file come from
`hypr/.config/hypr/conf/keybindings.lua` unless explicitly identified as browser
extension commands. The local `mod` value resolves to `SUPER`.

Each binding's Lua `description` flag also feeds the live Quickshell keybinding palette,
opened with `SUPER+K`.

## Session and general tools

| Keys | Action | Command / behavior |
| --- | --- | --- |
| `SUPER+Return` | terminal | `kitty` |
| `SUPER+SHIFT+Return` | drop-down terminal | `Dropterminal.sh kitty` |
| `SUPER+Q` | close active window | `killactive` |
| `CTRL+ALT+Delete` | close all windows | close every address returned by `hyprctl clients` |
| `SUPER+L` | lock screen | start Hyprlock if not already running |
| `SUPER+P` | power menu | `scripts/power-menu.sh`, launcher-neutral |
| `SUPER+ALT+P` | monitor profiles | themed Rofi menu; includes the next-profile cycle |
| `SUPER+K` | searchable bindings | Quickshell keybinding panel |
| `SUPER+I` | coding agent | `ai-agent` in Kitty, via `run-if-deployed.sh` |
| `SUPER+CTRL+T` | activity | floating `btop` in the configured terminal |
| `SUPER+ALT+T` | network speed test | fast.com transfers measured through kernel interface counters |
| `SUPER+SHIFT+G` | start Gaming VM | starts `Gaming-VM`, waits 15 seconds, then Looking Glass |

## Applications and panels

| Keys | Action | Command / behavior |
| --- | --- | --- |
| `SUPER+A` | application launcher | installed desktop applications; `Tab` cycles launcher modes |
| `SUPER+SHIFT+A` | quick search | windows, apps, commands, reboot, and shutdown; `Tab` cycles modes |
| `SUPER+ALT+A` | web-app manager | Quickshell web-app panel |
| `SUPER+W` | browser | `helium-browser` |
| `SUPER+ALT+W` | Windows VM | start/connect through `windows-vm launch` |
| `SUPER+CTRL+ALT+W` | stop Windows VM | graceful stop through `windows-vm stop` |
| `SUPER+SHIFT+ALT+W` | private browser window | XDG default browser's declared private action |
| `SUPER+S` | Spotify | `spotify` |
| `SUPER+O` | Obsidian | `obsidian` |
| `SUPER+R` | voice dictation | `hyprvoice toggle` |
| `SUPER+SHIFT+H` | Hermes | `hermes` |
| `SUPER+E` | Files | `nautilus` through `file_manager` |
| `SUPER+SHIFT+E` | Files | same as `SUPER+E` |
| `SUPER+SHIFT+ALT+F` | Files at terminal directory | `files-here.sh` |
| `SUPER+SHIFT+D` | Disks | `gnome-disks` through `disks` |
| `SUPER+U` | eject removable drives | `eject-drive.sh` picker; confirms, unmounts, and powers off the drive |
| `SUPER+CTRL+I` | network status panel | Quickshell IPC |
| `SUPER+CTRL+W` | network panel | Quickshell NetworkManager controls: Wi-Fi, DNS, IPv4 overrides, and Wi-Fi QR sharing |
| `SUPER+CTRL+A` | audio panel | Quickshell IPC |
| `SUPER+CTRL+B` | Bluetooth panel | Quickshell IPC |
| `SUPER+SHIFT+B` | power profile menu | Rofi picker over `powerprofilesctl` profiles |
| `SUPER+CTRL+D` | display panel | Quickshell IPC |
| `SUPER+CTRL+M` | media panel | Quickshell IPC |
| `SUPER+D` | toggle do-not-disturb | `notificationctl dnd-toggle` |

## Sharing, clipboard, emoji, calculator, and transcoding

| Keys | Action | Notes |
| --- | --- | --- |
| `SUPER+C` | universal copy | sends `CTRL+SHIFT+C` in terminals, `CTRL+C` elsewhere |
| `SUPER+X` | universal cut | terminal cut intentionally does nothing |
| `SUPER+V` | universal paste | sends terminal-appropriate shortcut |
| `SUPER+CTRL+V` | clipboard history | active Quickshell/cliphist panel |
| `SUPER+CTRL+S` | share | opens LocalSend; its window is floated and centered |
| `SUPER+ALT+E` | emoji menu | themed Rofi fuzzy search; copies the selected emoji |
| `SUPER+CTRL+Q` | calculator | themed Rofi prompt backed by `qalc`; Enter on the answer copies it |
| `SUPER+SHIFT+C` | calculator | alternate binding for the same calculator |
| `SUPER+CTRL+.` | transcode media | fuzzy picker over `~/Pictures` and `~/Videos`; copies the result as a file URI |

LocalSend and btop are optional applications; install them before using their
bindings. The transcoder's CLI and output behavior are documented in
[Scripts and command-line tools](./scripts.md#transcoding-before-sharing).

## Notifications

| Keys | Action |
| --- | --- |
| `SUPER+,` | dismiss newest notification |
| `SUPER+SHIFT+,` | dismiss all notifications |
| `SUPER+CTRL+,` | toggle do-not-disturb |
| `SUPER+ALT+,` | invoke the newest notification's default action |
| `SUPER+SHIFT+ALT+,` | open notification history |

These commands target the active Quickshell notification service through
`~/.local/bin/notificationctl`, not SwayNC.

## Capture

| Keys | Action | Capture command |
| --- | --- | --- |
| `SUPER+SHIFT+S` | smart screenshot | drag for region; click to snap window under pointer |
| `SUPER+ALT+S` | focused-monitor screenshot | `screenshot monitor` |
| `SUPER+ALT+CTRL+S` | screenshot monitor after 5 seconds | `--delay=5` |
| `SUPER+CTRL+SHIFT+S` | screenshot monitor after 10 seconds | `--delay=10` |
| `SUPER+ALT+C` | toggle webcam overlay | standalone preview; press again to close |
| `SUPER+ALT+[` / `SUPER+ALT+]` | show the webcam overlay smaller / larger | opens a missing overlay, then steps through three 16:9 presets |
| `SUPER+SHIFT+R` | toggle screen recording | `record toggle` |
| `SUPER+SHIFT+P` | color picker | `color` |
| `SUPER+SHIFT+T` | OCR / extract text | `ocr` |
| `SUPER+CTRL+C` | capture menu | mode chooser |

The implementation and optional features are described in
[Capture suite](./scripts.md#capture-suite).

## Themes, wallpaper, and night light

| Keys | Action |
| --- | --- |
| `SUPER+CTRL+SHIFT+Space` | open the same theme picker |
| `SUPER+SHIFT+W` | open wallpaper picker/search |
| `SUPER+CTRL+N` | toggle night light between 1000 K and 6500 K |
| `SUPER+CTRL+O` | open the desktop toggles menu |
| `SUPER+ALT+M` | open desktop modes panel |
| `SUPER+SHIFT+I` | toggle selective stay-awake |
| `SUPER+Backspace` | toggle window transparency on all workspaces |
| `SUPER+SHIFT+Backspace` | toggle gaps and borders on all workspaces |
| `SUPER+CTRL+Escape` | start the ASCII screensaver immediately |
| `SUPER+CTRL+SHIFT+Escape` | toggle automatic ASCII screensaver launch |
| `SUPER+CTRL+,` | toggle Quickshell Do Not Disturb |

## Workspaces

### Select a workspace

| Keys | Destination |
| --- | --- |
| `SUPER+1` … `SUPER+0` | workspaces 1 … 10 |
| `SUPER+ALT+1` … `SUPER+ALT+5` | workspaces 11 … 15 |
| `SUPER+TAB` / `SUPER+SHIFT+TAB` | next / previous open workspace |
| `SUPER+CTRL+TAB` | former workspace |
| `SUPER+wheel down` / `SUPER+wheel up` | next / previous open workspace |

### Move the active window

The number-row bindings use physical keycodes `code:10` through `code:19`, as
reported by the active keyboard for `1` through `0`. Window moves use Hyprland's
live Lua evaluator so they target the active window reliably on Hyprland 0.56.2.

| Keys | Action |
| --- | --- |
| `SUPER+SHIFT+1` … `SUPER+SHIFT+0` | move to workspace 1 … 10 and follow |
| `SUPER+CTRL+1` … `SUPER+CTRL+0` | move to workspace 1 … 10 without following |
| `SUPER+SHIFT+ALT+1` … `SUPER+SHIFT+ALT+4` | move to workspace 1 … 4 without following |
| `SUPER+SHIFT+[` / `SUPER+SHIFT+]` | move and follow to previous / next workspace |
| `SUPER+CTRL+[` / `SUPER+CTRL+]` | move silently to previous / next workspace |

Output placement for these numbered workspaces is profile-dependent; see
[Workspace mapping](./monitors.md#workspace-mapping).

## Window management

| Keys | Action |
| --- | --- |
| `SUPER+SHIFT+F` | true fullscreen (Hyprland mode 0) |
| `SUPER+CTRL+F` | maximize while retaining bar/gaps (mode 1) |
| `SUPER+T` | toggle the active window between floating and tiled |
| `SUPER+J` | toggle the next dwindle split between horizontal and vertical |
| `SUPER+Arrow` | move focus in that direction |
| `SUPER+CTRL+Arrow` | move window in that direction |
| `SUPER+SHIFT+Arrow` | swap window in that direction |
| `SUPER+SHIFT+ALT+Arrow` | move current workspace to directional monitor |
| `SUPER+Minus` / `SUPER+Equal` | resize horizontally by −/+100 pixels |
| `SUPER+SHIFT+Minus` / `SUPER+SHIFT+Equal` | resize vertically by −/+100 pixels |
| `SUPER+ALT+Minus` / `SUPER+ALT+Equal` | fine horizontal resize by −/+10 pixels |
| `SUPER+CTRL+Minus` / `SUPER+CTRL+Equal` | coarse horizontal resize by −/+300 pixels |
| `SUPER+ALT+Home` | save active window width for this session |
| `SUPER+Home` | restore saved width while preserving current height |
| `SUPER+Left mouse drag` | move window |
| `SUPER+SHIFT+Right mouse drag` | resize window |

## Desktop zoom

| Keys | Action |
| --- | --- |
| `SUPER+ALT+wheel down` | multiply zoom by 1.1 |
| `SUPER+ALT+wheel up` | multiply zoom by 0.9, clamped to 1 |
| `SUPER+ALT+SHIFT+wheel` in either direction | reset zoom to 1 |

These bindings query and update `cursor:zoom_factor` with `hyprctl` and `jq`.

## Media, volume, and brightness

| Key | Action | Primary command |
| --- | --- | --- |
| `XF86AudioRaiseVolume` | volume +5%, repeatable | `wpctl`, capped at 100% |
| `XF86AudioLowerVolume` | volume −5%, repeatable | `wpctl` |
| `XF86AudioMute` | toggle mute | `wpctl` |
| `XF86AudioPlay` | play/pause | `playerctl play-pause` |
| `XF86AudioPause` | pause | `playerctl pause` |
| `XF86AudioNext` | next track | `playerctl next` |
| `XF86AudioPrev` | previous track | `playerctl previous` |
| `XF86AudioStop` | stop | `playerctl stop` |
| `XF86MonBrightnessUp` | brightness +5%, repeatable | `brightnessctl` |
| `XF86MonBrightnessDown` | brightness −5%, repeatable | `brightnessctl` |

The same three volume keys are also registered later with `pactl`. The config
states that the earlier `wpctl` definitions shadow those duplicate fallback
bindings. Both sets remain in the file, so remove one set rather than expecting
both to execute.

## Browser extension shortcuts

These are Chromium extension commands, not Hyprland bindings:

| Keys | Action | Source |
| --- | --- | --- |
| `ALT+SHIFT+L` | copy current tab URL to Wayland clipboard | Copy URL extension |
| `ALT+SHIFT+D` | download media from current page with yt-dlp | Download Video extension |

Chromium must grant/register the command and find its native host. See
[Browser integration](./components.md#browser-integration) and the corresponding
[troubleshooting](./troubleshooting.md#browser-shortcuts).

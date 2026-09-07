# Scripts and command-line tools

## Active Hyprland helpers

These scripts are below `hypr/.config/hypr/scripts/`.

| Script | Invocation | Purpose and effects | Main dependencies |
| --- | --- | --- | --- |
| `Dropterminal.sh` | `SUPER+SHIFT+Return` | toggles a Kitty scratchpad on a special workspace | `hyprctl`, Kitty |
| `calculator.sh` | `SUPER+CTRL+Q`, `SUPER+SHIFT+C` | evaluates a `qalc` expression and copies the selected answer | Rofi, `qalc`, `wl-copy` |
| `quick-search.sh` | `SUPER+A`, `SUPER+SHIFT+A` | starts in apps or an Omakub-style root menu and uses `Tab` to cycle windows, apps, and commands; `quick-search-everything.sh` supplies category navigation plus confirmed reboot and shutdown | Rofi, `systemctl` |
| `docker-dev-env` | `SUPER+SHIFT+A` → Development → Docker environments | starts, stops, inspects, and tails logs for local MySQL, PostgreSQL, MariaDB, and Redis services | Docker Engine, Docker Compose, OpenSSL; optional notifications and Kitty |
| `transcode-menu.sh` | `SUPER+CTRL+.` | fuzzy media/format/size picker; delegates conversion and clipboard work to `transcode` | Rofi, `file`, `transcode` |
| `RofiEmoji.sh` | `SUPER+ALT+E` | fuzzy-searches emoji data with the active application-menu theme and copies the chosen glyph | Rofi, `wl-copy` |
| `universal-clipboard.sh` | `SUPER+C/X/V` | detects terminal classes and sends the correct copy/cut/paste shortcut | `hyprctl` |
| `power-profile.sh` | `SUPER+SHIFT+B` | lists, reports, sets, cycles, or intelligently toggles `powerprofilesctl` profiles; the bound action opens a Rofi picker | `power-profiles-daemon`; optional Rofi and notifications |
| `files-here.sh` | `SUPER+SHIFT+ALT+F` | discovers a focused terminal's current directory and opens Nautilus there | terminal APIs, `hyprctl`, Nautilus |
| `night-light.sh` | `SUPER+CTRL+N` | toggles Hyprsunset between 1000 K and 6500 K; delegates to `desktop-mode` when installed and otherwise controls Hyprsunset directly | `hyprctl`, `hyprsunset`; optional `desktop-mode` |
| `spotify-notify.sh` | autostart | watches Spotify metadata and sends track-change notifications | `playerctl`, `curl`, notification command |
| `clipboard-store.sh` | `wl-paste --watch` | stores text/images in cliphist | `cliphist` |
| `clipboard-wipe.sh` | manual | clears clipboard/history data | `wl-copy`, `cliphist` |

`hypr/.config/hypr/scripts/lib/terminals.sh` is sourced by clipboard and
file-manager helpers. It centralizes terminal-class detection and terminal-specific
current-directory queries; it is not a standalone command.

`window-width.sh` backs `SUPER+ALT+Home` and `SUPER+Home`. It saves one width in
the login session's runtime directory, then restores that width while retaining
the active window's current height.

`hypr/.config/hypr/scripts/bluetooth-control` is the fixture-testable backend for the
Quickshell Bluetooth widget. It reports adapter/device state as JSON — including
each device's class, trust flag, and battery level — and provides validated
power, scan (`SECONDS` or `off`), pair, connect, disconnect, trust, untrust, and
forget commands over `bluetoothctl`. `status` encodes the whole device list with
a single `jq` run and caches device classes under
`${XDG_CACHE_HOME:-~/.cache}/bluetooth-control/`, so the panel's poll stays
cheap; only connected devices are re-inspected on each poll.

`eject-drive.sh` opens a themed Rofi menu of mounted removable drives (label,
device, and size), asks for confirmation, unmounts every mounted filesystem on
the selected drive with `udisksctl`, powers the disk off, and reports the
result with a desktop notification that bypasses Do Not Disturb. It handles
partitioned sticks, multi-mountpoint nodes, and LUKS holders.
`--dry-run --fixture <lsblk-json-file>` prints the planned actions without
calling `udisksctl` or `notify-send`; `--fixture` implies `--dry-run`, so the
fixture path can never mutate system state. See
`tests/eject-drive.test.sh`.

`LayoutToggle.sh` can switch between master and dwindle layouts, but no current
binding invokes it. The older `Screenshot.sh`, `shot-copy.sh`, `shot-edit.sh`, and
`shot-save.sh` predate the active capture suite and are also not bound. `dnd.sh`
targets the retained SwayNC workflow; active DND uses `notificationctl` instead.

## Transcoding before sharing

`hypr/.local/bin/transcode` is the reusable backend for images and videos. Its
desktop frontend searches supported media below `~/Pictures` and `~/Videos`,
then calls the same CLI with `--copy --notify`.

```bash
transcode ~/Videos/demo.mov mp4 1080p
transcode --copy --notify ~/Pictures/photo.heic jpg medium
```

Images support JPG or PNG with `high`, `medium`, and `low` maximum widths of
3160, 2160, and 1080 pixels. Videos support MP4 or GIF with `4k`, `1080p`, and
`720p` bounding boxes. Neither path upscales. JPEG flattens transparency onto
white; MP4 uses H.264/AAC with fast-start metadata; GIF uses a generated palette.

Outputs stay beside their source and use the requested size label, such as
`photo-2160p.jpg` or `demo-1080p.mp4`. Existing names gain `-2`, `-3`, and so on.
`--copy` writes a percent-encoded, CRLF-terminated file URI to the Wayland
clipboard with MIME type `text/uri-list`; `--notify` reports the final state.

## Capture suite

Entry point: `hypr/.config/hypr/scripts/capture/capture.sh`.

It dispatches to `screenshot.sh`, `record.sh`, `ocr.sh`, `color.sh`, and `menu.sh`.
`select.sh` supplies transform-aware Hyprland geometry and frozen-screen region
selection; `common.sh` and `config.sh` are sourced libraries.

### Operations

| Command | Behavior | Outputs / modifications |
| --- | --- | --- |
| `capture.sh screenshot smart` | drag selects a region; a small click selects the smallest visible window under the pointer | saves/copies a PNG, then offers open/edit actions |
| `capture.sh screenshot window` | captures active window geometry | screenshot directory and clipboard |
| `capture.sh screenshot monitor [--delay=N]` | captures focused output, optionally delayed | screenshot directory and clipboard |
| `capture.sh record toggle` | starts/stops GPU screen recording with optional audio/webcam and post-processing | recording directory; runtime PID/state files |
| `capture.sh record webcam-toggle` | shows or hides a standalone webcam preview | mpv overlay and runtime PID/state files |
| `capture.sh record webcam-size smaller\|larger` | opens a missing overlay, then steps it through small, medium, and large presets | mpv JSON IPC with PID-scoped Hyprland fallback |
| `capture.sh ocr` | selects/freeze-captures, preprocesses, runs Tesseract, copies text | Wayland clipboard |
| `capture.sh color` | picks a screen color | Wayland clipboard and notification |
| `capture.sh menu` | interactive operation chooser | depends on selection |
| `capture.sh doctor` | reports command availability | no desktop mutation intended |

### Configuration

Defaults are in `capture/config.sh` and can be overridden through environment
variables before launch.

| Variable | Default / purpose |
| --- | --- |
| `SCREENSHOT_DIR` | `~/Pictures/screenshot` |
| `SCREENSHOT_EDITOR` | `satty` |
| `SCREENRECORD_DIR` | `~/Videos/screenrecording` |
| capture FPS | 60 |
| maximum recording dimensions | 3840×2160 |
| `OCR_LANGS` | `eng` |
| OCR page segmentation / engine / DPI | 6 / 1 / 300 |
| webcam mode | auto, 1280×720, medium preset |
| smart-click threshold | 20 pixels |

Recording uses `gpu-screen-recorder`, selects an available GPU codec, falls back
to CPU encoding when no hardware encoder supports the capture, stops with a
graceful signal, and can use FFmpeg for normalization/trimming. Selection and
screenshots use `hyprctl`, `jq`, `slurp`, `hyprpicker`, and `grim`; OCR also uses
Tesseract and ImageMagick. `satty`, mpv, and `v4l2-ctl` enable editing, playback,
and webcam discovery respectively.

## Monitor tools

### `auto-monitor-profile.sh`

Inputs are live JSON from `hyprctl -j monitors`. The KVM profile is recognized by
EDID description, because the KVM renumbers DisplayPort connectors on every
switch; the desktop profile still matches connector names. It copies profile
files to active `monitors.lua` and `workspaces.lua`, reloads Hyprland, reads the
loaded workspace rules, moves workspaces 1–15, verifies the result, and notifies.
Pass `--profile NAME` to apply a named profile.

It waits for the monitor set to settle, takes a `flock`, and exits without
changing anything when the layout and generated files already match the profile.
`--force` reapplies regardless. `--dry-run` reads monitor JSON from
`SIMULATED_MONITORS` or stdin and prints the resulting config without writing or
dispatching. `--verbose` mirrors the log to stderr. It has no polling mode;
reapplication is driven by `hypr-monitor-watch.py`. Logs go to
`journalctl -t hypr-monitor`. See [Monitors](./monitors.md).

This script modifies tracked/Stowed configuration and live compositor state. Test
changes with mocked `hyprctl` and temporary target files rather than invoking it
against an unrelated live session.

### `monitor-profile-menu.sh`

Opens the themed Rofi monitor-profile menu. It discovers paired profiles from
`monitor_profiles/`, marks the active pair, and delegates every change to
`auto-monitor-profile.sh`. The `Next profile` entry cycles through `desktop`,
`laptop`, `work`, and `presentation`; from any other profile it starts at
`desktop`. `--next --dry-run` exercises the same path with simulated monitor JSON.

### `set-monitor-scale.sh`

Accepts a monitor name and numeric scale, validates both, then atomically updates
the active monitor file and desktop profile. The Quickshell display panel applies
the resulting setting. It does not persist to laptop/KVM profiles.

### `hypr-monitor-watch.py`

Subscribes to Hyprland's `socket2` IPC and runs `auto-monitor-profile.sh` when a
monitor is added or removed, debouncing the burst a KVM switch produces. Started
from `conf/autostart.lua`; exits when Hyprland closes the socket. Entirely
user-level — it replaced a root udev dispatcher and a 15-second polling loop.

### `capture-monitor-profile.sh`

Snapshots the live monitor layout into `monitor_profiles/<profile>.monitors.lua`,
keyed by EDID description. Shows a diff and asks before writing, keeps a `.bak`,
and validates the generated Lua with `luac`. `--dry-run` previews, `--yes` skips
the prompt, `--with-workspaces` also snapshots workspace pinning and reports
which entries had to be inferred.

## YubiKey authentication

`security/.config/gnupg-conf/` contains example `gpg.conf` and
`gpg-agent.conf` templates with one-hour SSH-key caching. Copy them into
`~/.gnupg/` manually as described in that directory's `README.md`; interactive
Zsh sessions export `SSH_AUTH_SOCK` to the matching `gpg-agent` socket.

`security/.local/bin/yubikey-auth` manages the host-local PAM-U2F mapping and
repository-owned sudo/Hyprlock templates without placing credentials in Git.

| Command | Behavior |
| --- | --- |
| `yubikey-auth status` | reports tools, visible tokens, mapping presence, and deployed-template state |
| `yubikey-auth setup --enroll-fingerprint` | enrolls a YubiKey Bio fingerprint, creates the first mapping, backs up `/etc` targets, and stages sudo before Hyprlock |
| `yubikey-auth add --enroll-fingerprint` | appends another Bio credential to the existing user's single mapping line |
| `yubikey-auth add --mode pin` | registers a non-biometric FIDO2 key with PIN verification |
| `yubikey-auth setup\|add --dry-run` | detects and reports actions without changing the key, mapping, or PAM |

Automatic detection fails closed when several YubiKeys are connected; select
one explicitly with `--device`. Generated credentials are held in a mode-0700
temporary directory, validated before installation, and removed on exit.

## Wallpaper tools

| Tool | Purpose |
| --- | --- |
| `hypr/.local/bin/hypr-wallpaper-picker` | toggles the Quickshell panel; subcommands list/search/apply images, print the current image, and restore the last successful selection |
| `WallpaperSwitch.sh` | retained older image/video picker using Hyprpaper/mpvpaper and autostart edits |
| `WallpaperEffects.sh` | retained effect helper; not currently bound |

The active tool depends on Bash, `curl`, `jq`, ImageMagick, Hyprpaper,
Hyprland IPC, and desktop notifications. It honors `HYPR_WALLPAPER_DIR`,
`HYPR_WALLPAPER_RUNTIME_DIR`, and `HYPR_WALLPAPER_STATE_FILE`. Successful
selections are stored under `$XDG_STATE_HOME/hyprland-desktop/wallpaper/current`
and restored by Hyprland autostart. Its read-only `current` command validates and
prints that path for Hyprlock without changing the live wallpaper.

`hypr/.config/hypr/scripts/default-browser-private` resolves the XDG default
browser desktop entry and launches its declared private-window action. Known
Firefox/Chromium-family flags are used only when the entry lacks that action;
unknown browsers fail with a notification instead of opening a normal window.

## Theme tools

| Tool | Purpose |
| --- | --- |
| `hypr/.local/bin/theme` | convenience launcher for the theme CLI |
| `hypr/.config/hypr/theme/generate.py` | render all component outputs atomically from `colors.toml` |

Selection updates generated files and live applications while preserving the
current wallpaper. Pass `--wallpaper` to explicitly apply the selected theme's
wallpaper. Pass `--install-greeter` (optionally with `--dry-run`) to also copy
the rendered regreet CSS/TOML into `/etc/greetd/` via `sudo`; this is separate
from every other reload because it is the only case where the theme tool
needs root, so it is never run implicitly by the picker or keybindings. See
[Themes](./themes.md).

`system/greetd/install.sh` (dry-run by default; `--apply` to act) deploys
`system/greetd/config.toml` to `/etc/greetd/config.toml`, the greetd-level
config that points at the regreet greeter. See
[Installation](./installation.md#greetd-session-entrypoint).

## Notification and web-app tools

| Tool | Purpose and state |
| --- | --- |
| `hypr/.local/bin/notificationctl` | IPC client for dismiss, DND, action, history, and status operations against Quickshell |
| `modes/.local/bin/desktop-mode` | unified temporary-mode status, transitions, timed activation, diagnostics, and screensaver action |
| `screensaver/.local/bin/ascii-screensaver` | per-monitor launcher with terminal resolution and an event-socket spawn barrier |
| `screensaver/.local/bin/ascii-screensaver-render` | endless random `ttfx` carousel with keyboard/focus cleanup |
| `screensaver/.local/bin/toggle-screensaver` | persistent automatic-screensaver off flag and notification |
| `screensaver/.local/bin/screensaver-branding` | text, image, and reset logo workflows with forced preview |
| `screensaver/.local/bin/transcode-ascii` | ImageMagick PBM to Unicode braille/block converter |
| `screensaver/.local/bin/screensaver-lock` | stop renderers and screensaver terminals before Hyprlock |
| `hypr/.local/bin/webapp` | create/remove browser-style web application launchers |
| `hypr/.local/bin/webapp-launch` | launch a stored web app with the configured browser profile/options |

The Quickshell notification service owns state; the helper does not implement a
second notification daemon. The web-app tools write user application data and are
surfaced by `SUPER+SHIFT+A`.

## Browser native tools

| Tool | Input | Output / side effects |
| --- | --- | --- |
| `browser/.local/bin/chromium-copy-url-host` | length-framed native JSON with URL | Wayland clipboard and success/error notification |
| `browser/.local/bin/chromium-ytdlp-host` | length-framed native JSON or `--download URL` worker mode | video file, progress OSD, thumbnail, completion/failure notification |
| `browser/.local/bin/chromium-repair-download-video-shortcut` | browser profile and optional `--apply` | diagnostic report or repaired Chromium Preferences/command state |

The repair tool is intentionally a dry run unless `--apply` is supplied, and it
refuses unsafe live-profile editing when the browser is running. Browser fixture
coverage is in `tests/browser-native-tools.test.sh`.

## Package deployment guard

`hypr/.config/hypr/scripts/run-if-deployed.sh <package> <command> [args...]`
runs `~/.local/bin/<command>`, falls back to a `PATH` lookup, and otherwise sends
a desktop notification naming the Stow package that has not been deployed.

Hyprland discards `exec` output, so a binding pointing at an undeployed package's
entry point does nothing at all with no diagnostic. The `SUPER+I` coding-agent
binding and the four `desktop-mode` bindings route through this wrapper, as does
the desktop-mode daemon line in `conf/autostart.lua`. `hypridle.conf` guards its
`condition_cmd` the same way inline.

## Power menu

`hypr/.config/hypr/scripts/power-menu.sh` is a launcher-neutral
lock/logout/suspend/reboot/shutdown menu with confirmation prompts. It chooses
Fuzzel, then Rofi, Wofi, or Bemenu, and the `SUPER+P` binding invokes it through
`bash`.

It previously lived in the Waybar package. When Waybar was retired it was the
only script there with a consumer outside that package, so it moved here and the
rest were removed — recoverable from Git history if ever wanted.

## AI launcher

`ai/.local/bin/ai-agent` preserves the caller's working directory and launches
Claude, Codex, OpenCode, or T3 Code. Selection precedence is an explicit `--agent`, then
`AI_AGENT_DEFAULT`, then the configured value in `AI_AGENT_CONFIG` (defaulting to
`~/.config/ai-agent/config`). Shell aliases in `zsh/.zshrc` call this launcher.

## Windows VM

`windows/.local/bin/windows-vm` is the sole controller for the optional Dockur
Windows 11 VM. It supports `install`, `launch [--keep-alive]`, `status`, `stop`,
`logs`, and `remove [--purge-data]`. Mutating commands also accept `--dry-run`
immediately after the command name.

The tracked Compose template is under `windows/.local/share/windows-vm/`.
Installation writes machine-local settings and mode-0600 credentials beneath
`~/.config/windows`, stores the VM in `~/.windows`, and shares only `~/Windows`.
The password is decoded into a short-lived mode-0600 runtime environment file
and passed to FreeRDP through standard input rather than its process arguments.

Launch polling checks both the localhost RDP socket and a bounded FreeRDP
authentication probe. Both the probe and interactive client use `/cert:ignore`
because the endpoint is restricted to `127.0.0.1`; this prevents regenerated VM
certificates from opening a focus-blocking confirmation dialog. A clean RDP exit
stops the VM unless `--keep-alive` was used; a timeout or client failure
deliberately leaves it running for inspection.
Starting a stopped container sends a `Windows VM started` desktop notification
after Compose succeeds. Both the explicit `stop` command and the automatic stop
after a clean RDP exit send `Windows VM stopped` only after the stop succeeds.
`remove` preserves all data, while `remove --purge-data` requires typing the
exact storage path and never removes `~/Windows`.

## Hyprlock helper collection

Scripts below `hyprlock/.config/hyprlock/scripts/` provide battery status, Cava
visualization, MPRIS metadata/artwork/progress, player controls, stopwatch,
weather/location lookup, and alternate-layout switching. Most are referenced only
by inactive layouts. They may depend on `BAT0`, `playerctl`, `curl`, `ipinfo.io`,
`wttr.in`, ImageMagick, Cava, or extra assets. Read the chosen layout and helper
before enabling it.

`hyprlock_notify_widget.sh` can modify the active lock config and restart the lock
screen. It is not part of normal startup and should not be used as a read-only
preview command.

## Known script issues

- retained `WallpaperSwitch.sh` references a missing
  `~/.config/rofi/config-wallpaper.rasi`.
The older calculator mode scripts remain as unbound historical helpers.

# Scripts and CLIs

Two kinds of executable live here: entry points that land on your `PATH` at
`~/.local/bin`, and Hyprland helpers under `~/.config/hypr/scripts/` that
bindings call by absolute path.

## Commands on your PATH

| Command | Package | What it does |
| --- | --- | --- |
| `theme` | `hypr` | apply, list, validate, and cycle themes |
| `notificationctl` | `hypr` | dismiss, DND, invoke, history, status |
| `webapp`, `webapp-launch` | `hypr` | create, remove, and run web-app launchers |
| `transcode` | `hypr` | image and video conversion backend |
| `toggle` | `hypr` | facade for the toggles menu |
| `hypr-wallpaper-picker` | `hypr` | wallpaper panel and its index/search/apply backend |
| `lmenu`, `lmenu-reminder`, `lmenu-toggle-ratio` | `menu` | the data-driven Rofi menu and countdown reminders |
| `desktop-mode` | `modes` | temporary desktop modes and the expiry daemon |
| `ascii-screensaver`, `ascii-screensaver-render`, `toggle-screensaver`, `screensaver-branding`, `screensaver-lock`, `transcode-ascii`, `install-ttfx` | `screensaver` | the ASCII screensaver suite |
| `ai-agent` | `ai` | launch Claude Code, Codex, OpenCode, or T3 Code |
| `windows-vm` | `windows` | the Dockur Windows 11 controller |
| `yubikey-auth` | `security` | guarded YubiKey Bio PAM setup |
| `chromium-copy-url-host`, `chromium-ytdlp-host`, `chromium-repair-download-video-shortcut` | `browser` | Chrome native messaging hosts and a repair helper |

## lmenu

`SUPER+SHIFT+A`. A data-driven Rofi menu over
`menu/.config/lmenu/menu.jsonc` — 206 entries in a nested tree, parsed by
`lmenu-parse.py`.

```bash
lmenu                      # toggle the root menu
lmenu toggle [route]       # open at a route, or close it if already shown
lmenu summon [route]       # always open at a route
lmenu close
lmenu refresh              # discard cached state so the next open re-runs guards
lmenu --dry-run ROUTE      # print the rows a route would show, without rofi
lmenu --dry-run-display ROUTE
lmenu parent ROUTE
```

Inside the menu, Backspace goes up a level and closes lmenu at the root.
`Shift+Backspace` and `Ctrl+H` still delete a character in the search box.

A route is a dotted id (`style.theme`) or an alias (`themes`). Guards run
batched — one bash process per render — inside the parser, which is what keeps
a 206-entry tree responsive.

Top-level routes:

| Route | Contains |
| --- | --- |
| `apps` | installed applications |
| `development` | Docker dev environments: MySQL, PostgreSQL, MariaDB, Redis, info, stop-all |
| `learn` | keybindings, Hyprland, Arch, Neovim, Bash |
| `trigger` | emoji, reminders, capture, transcode, share, toggles, speed test, calculator, clipboard, hardware |
| `style` | theme, background, font, gaps, transparency, Hyprland settings, bar position/toggle/transparency |
| `system` | lock, logout, suspend, hibernate, reboot, shutdown, screensaver, screensaver branding |
| `install`, `remove`, `update`, `setup`, `about` | package and system management entries |

`lmenu` falls back to the repo-relative parser path when the config is not
stowed yet, so it works before the first `stow`.

### Reminders

```bash
lmenu-reminder set [DURATION MESSAGE...]   # prompts if given no arguments
lmenu-reminder list
lmenu-reminder clear
lmenu-reminder count
lmenu-reminder menu
lmenu-reminder fire NAME                   # what the timers call
```

`DURATION` is `45s`, `10m`, `2h`, `1h30m`, or a bare number meaning minutes.

Each reminder is a **transient systemd user timer**, so it survives the script
exiting and systemd cancels it. No state file is needed: the unit name carries
the due time and the unit description carries the message.

Bound to `SUPER+CTRL+R`, `SUPER+CTRL+ALT+R`, and `SUPER+CTRL+SHIFT+R`.

## Hyprland helpers

Under `hypr/.config/hypr/scripts/`.

| Script | Bound to | What it does |
| --- | --- | --- |
| `Dropterminal.sh` | `SUPER+SHIFT+Return` | Kitty scratchpad on a special workspace |
| `calculator.sh` | `SUPER+CTRL+Q`, `SUPER+SHIFT+C` | `qalc` behind Rofi; Enter copies the answer |
| `quick-search.sh` | `SUPER+A` | apps view; `Tab` cycles windows, apps, commands |
| `quick-search-everything.sh` | — | category navigation plus confirmed reboot and shutdown |
| `docker-dev-env` | lmenu → Development | start, stop, inspect, and tail local MySQL, PostgreSQL, MariaDB, Redis |
| `transcode-menu.sh` | `SUPER+CTRL+.` | fuzzy media/format/size picker; delegates to `transcode` |
| `RofiEmoji.sh` | `SUPER+ALT+E` | fuzzy emoji search, copies the glyph |
| `universal-clipboard.sh` | `SUPER+C/X/V` | detects terminal classes, sends the right shortcut |
| `power-menu.sh` | `SUPER+P`, bar power button | lock/logout/suspend/reboot/shutdown with confirmations |
| `power-profile.sh` | `SUPER+SHIFT+B` | list, report, set, cycle, or smart-toggle `powerprofilesctl` profiles |
| `files-here.sh` | `SUPER+SHIFT+ALT+F` | finds the focused terminal's cwd and opens Nautilus there |
| `eject-drive.sh` | `SUPER+U` | Rofi picker of mounted removable drives, then unmount and power off |
| `night-light.sh` | `SUPER+CTRL+N` | 1000 K ↔ 6500 K; delegates to `desktop-mode` when installed |
| `toggles-menu.sh` | `SUPER+CTRL+O` | the toggles menu |
| `toggle-transparency.sh`, `toggle-gaps.sh` | `SUPER+Backspace`, `SUPER+SHIFT+Backspace` | across all workspaces |
| `window-width.sh` | `SUPER+ALT+Home`, `SUPER+Home` | save one width in the login runtime dir, restore it keeping the current height |
| `close-all-windows.sh` | `CTRL+ALT+Delete` | closes every address from `hyprctl clients` |
| `btop-float.sh` | `SUPER+CTRL+T` | floating btop |
| `default-browser-private` | `SUPER+SHIFT+ALT+W` | resolves the XDG default browser and runs its declared private-window action |
| `spotify-notify.sh` | autostart | track-change notifications |
| `clipboard-store.sh` | `wl-paste --watch` | filters secrets and excluded apps, then stores in cliphist |
| `clipboard-wipe.sh` | manual | clears clipboard and history |
| `run-if-deployed.sh` | used by bindings | see [below](#the-deployment-guard) |
| `bluetooth-control` | Quickshell | JSON adapter/device state and validated control commands |
| `network-control` | Quickshell | `nmcli` wrapper: Wi-Fi, DNS, IPv4, QR |
| `arch-updates` | Quickshell | `count` (JSON) and `update` (Kitty window) |
| `set-monitor-scale.sh` | Quickshell | validated, atomic scale persistence |
| `auto-monitor-profile.sh`, `capture-monitor-profile.sh`, `monitor-profile-menu.sh`, `hypr-monitor-watch.py` | see [Monitors](Monitors-and-Workspaces.md) | |

`scripts/lib/terminals.sh` is a sourced library, not a command. It centralises
terminal-class detection and terminal-specific cwd queries for the clipboard and
file-manager helpers.

### Not bound to anything

`LayoutToggle.sh` (master ↔ dwindle) has no binding. `Screenshot.sh`,
`shot-copy.sh`, `shot-edit.sh`, and `shot-save.sh` predate the capture suite.
`dnd.sh` targets the retained SwayNC workflow; active DND uses `notificationctl`.
`WallpaperSwitch.sh` and `WallpaperEffects.sh` are the older wallpaper path.

### The deployment guard

```bash
run-if-deployed.sh <package> <command> [args...]
```

Runs `~/.local/bin/<command>`, falls back to a `PATH` lookup, and otherwise sends
a desktop notification naming the Stow package that has not been deployed.

This exists because Hyprland discards `exec` output. A binding pointing at an
undeployed package's entry point does nothing at all, with no diagnostic. The
`SUPER+I` coding-agent binding, the four `desktop-mode` bindings, and the
desktop-mode daemon autostart line all route through it. `hypridle.conf` guards
its `condition_cmd` the same way, inline.

## Capture suite

Entry point: `hypr/.config/hypr/scripts/capture/capture.sh`. It dispatches to
`screenshot.sh`, `record.sh`, `ocr.sh`, `color.sh`, and `menu.sh`. `select.sh`
supplies transform-aware Hyprland geometry and frozen-screen region selection;
`common.sh` and `config.sh` are sourced libraries.

| Command | Behaviour |
| --- | --- |
| `screenshot smart` | drag selects a region; a small click selects the smallest visible window under the pointer |
| `screenshot window` | active window geometry |
| `screenshot monitor [--delay=N]` | focused output, optionally delayed |
| `record toggle` | start/stop GPU recording with optional audio, webcam, and post-processing |
| `record webcam-toggle` | show or hide a standalone webcam preview |
| `record webcam-size smaller\|larger` | opens a missing overlay, then steps through three 16:9 presets |
| `ocr` | select, freeze-capture, preprocess, Tesseract, copy |
| `color` | pick a screen colour to the clipboard |
| `menu` | interactive chooser |
| `doctor` | report command availability; changes nothing |

Configuration defaults live in `capture/config.sh` and can be overridden by
environment variable before launch:

| Variable | Default |
| --- | --- |
| `SCREENSHOT_DIR` | `~/Pictures/screenshot` |
| `SCREENSHOT_EDITOR` | `satty` |
| `SCREENRECORD_DIR` | `~/Videos/screenrecording` |
| capture FPS | 60 |
| maximum recording size | 3840×2160 |
| `OCR_LANGS` | `eng` |
| OCR page segmentation / engine / DPI | 6 / 1 / 300 |
| webcam | auto, 1280×720, medium preset |
| smart-click threshold | 20 px |

Recording uses `gpu-screen-recorder`, picks an available GPU codec, falls back to
CPU encoding when no hardware encoder supports the capture, stops with a graceful
signal, and can use FFmpeg for normalisation and trimming.

## Transcoding

`hypr/.local/bin/transcode` is the reusable backend. `transcode-menu.sh` searches
supported media below `~/Pictures` and `~/Videos` and calls the same CLI with
`--copy --notify`.

```bash
transcode ~/Videos/demo.mov mp4 1080p
transcode --copy --notify ~/Pictures/photo.heic jpg medium
```

Images support JPG or PNG at `high`, `medium`, `low` — maximum widths of 3160,
2160, and 1080 px. Videos support MP4 or GIF at `4k`, `1080p`, `720p` bounding
boxes. Neither path upscales.

JPEG flattens transparency onto white. MP4 uses H.264/AAC with fast-start
metadata. GIF uses a generated palette.

Output stays beside the source, named with the size label — `photo-2160p.jpg`,
`demo-1080p.mp4`. Existing names gain `-2`, `-3`, and so on. `--copy` writes a
percent-encoded, CRLF-terminated file URI to the clipboard as `text/uri-list`.

## Wallpaper

`SUPER+SHIFT+W` calls `hypr-wallpaper-picker` with no arguments, which toggles
the Quickshell cover-flow panel. The same script implements the operations the
desktop uses:

| Subcommand | Effect |
| --- | --- |
| `index` | list local wallpapers |
| `search` | local matches first, then Wallhaven |
| `apply`, `activate` | download, validate, restart Hyprpaper, apply in cover mode |
| `current` | read-only; prints the active image for Hyprlock |
| `restore` | reapply the last successful selection; called from autostart |
| `cleanup` | prune cached previews |

Search order is deliberate: local JPEG/PNG filename matches on the first page,
then SFW Wallhaven results requiring at least 1920×1080 sorted by relevance, then
additional Wallhaven pages on request.

Successful applications atomically write
`$XDG_STATE_HOME/hyprland-desktop/wallpaper/current`. Missing or stale state
starts plain Hyprpaper rather than picking a fallback image.

Honours `HYPR_WALLPAPER_DIR`, `HYPR_WALLPAPER_RUNTIME_DIR`, and
`HYPR_WALLPAPER_STATE_FILE`.

## Web apps

`SUPER+ALT+A` opens the manager; the **WEB APPS** dashboard tile does the same.

```bash
webapp list
webapp install --name "YouTube" --url https://youtube.com/
webapp install --name "Local" --url localhost:8080/app --icon ~/pic.png
webapp remove youtube
webapp doctor
webapp launch youtube
```

Each app owns exactly three files, and the manager touches only these:

| | |
|---|---|
| metadata | `~/.local/share/webapps/apps/<id>.toml` |
| icon | `~/.local/share/webapps/icons/<id>.png` |
| launcher | `~/.local/share/applications/webapp-<id>.desktop` |

The metadata file is the ownership marker: an app is removable by this tool only
if it is listed there, so an unrelated `.desktop` file can never be deleted.

Worth knowing:

- **Browser**: `$WEBAPP_BROWSER` if set, otherwise the first of `brave`,
  `chromium`, `chromium-browser`, `google-chrome`, `google-chrome-stable`,
  `helium-browser` on `PATH`. Web apps share the normal profile, so logins work.
- **Window class**: Brave ignores `--class` for app-mode windows and derives its
  own, e.g. `brave-youtube.com__-Default`. That is recorded as `wm_class` in the
  metadata and is what a per-app Hyprland rule must match. It is never plain
  `brave-browser`, so the workspace-2 rule does not capture web apps.
- **Icons** are normalised to PNG, because gdk-pixbuf here has no SVG or WebP
  loader and Rofi could not otherwise render them. Discovery prefers a declared
  `apple-touch-icon` or a sized raster over an SVG favicon; with nothing found, a
  letter tile is generated in the active theme's accent colour.
- Only `http` and `https` are accepted. `file:`, `data:`, and `javascript:` are
  rejected. URLs never pass through a shell and never appear in an `Exec` line —
  the launcher receives only the app id.

## AI launcher

`ai-agent` preserves the caller's working directory and launches Claude Code,
Codex, OpenCode, or T3 Code. Selection precedence: `--agent`, then
`AI_AGENT_DEFAULT`, then the config file at `AI_AGENT_CONFIG` (default
`~/.config/ai-agent/config`, which sets `default_agent=t3code`).

Invalid names and unavailable executables fail clearly. The launcher never
silently switches to another agent.

After stowing `ai` and `zsh`:

```bash
ai                                 # the configured default
ai-claude / ai-codex / ai-opencode / ai-t3code
ai-agent --agent claude
ai-agent --agent codex -- --help
```

The aliases are only defined when their names are otherwise unused.

`SUPER+I` opens the configured default. T3 Code is pinned to workspace 4 by its
`t3code` window class, and autostarts there.

## Windows VM

`windows-vm` is the sole controller for the optional Dockur Windows 11 VM.

```bash
windows-vm install
windows-vm launch [--keep-alive]
windows-vm status
windows-vm stop
windows-vm logs
windows-vm remove [--purge-data]
```

Mutating commands accept `--dry-run` immediately after the command name.

RDP (3389/tcp+udp) and the install viewer (8006) publish on `127.0.0.1` only.
`~/Windows` is mounted at `/shared`, becoming the Windows `Shared` folder and
`Z:` drive; nothing else from the home directory is mounted. Persistent VM data
lives in `~/.windows`; credentials and resource settings stay host-local under
`~/.config/windows`, mode 0600, and are never in this repository.

Both FreeRDP calls use `/cert:ignore`. Certificate validation is deliberately
non-interactive for this loopback-only endpoint, so a regenerated VM certificate
cannot leave a hidden modal dimming and blocking another workspace.

FreeRDP opens fullscreen on the focused Hyprland display with dynamic resolution,
clipboard, sound, microphone, automatic reconnection, and a scale derived from
that monitor. A runtime lock prevents duplicate launcher sessions.

New installations use Dockur's OEM hook to ensure WinGet, then install
Sysinternals, Everything, Helium, and PuTTY. The transcript lands at
`C:\OEM\post-install.log` inside the VM.

`windows-vm remove` is non-destructive. Permanent deletion needs
`--purge-data` plus exact-path confirmation, and `~/Windows` is always preserved.

## Browser native tools

| Tool | Input | Output |
| --- | --- | --- |
| `chromium-copy-url-host` | length-framed native JSON with a URL | `wl-copy` plus a notification |
| `chromium-ytdlp-host` | native JSON, or `--download URL` in worker mode | video file, progress OSD, thumbnail, completion or failure notification |
| `chromium-repair-download-video-shortcut` | a browser profile path, optional `--apply` | diagnostic report, or repaired Chromium Preferences |

`ALT+SHIFT+L` copies the active tab URL. The clipboard watcher then records it in
history like any other copy.

`ALT+SHIFT+D` sends the active page URL to `chromium-ytdlp-host`, which:

1. accepts only HTTP(S) URLs;
2. prevents duplicate requests with a lock;
3. runs `yt-dlp --simulate` to detect supported media;
4. starts a detached real download under `$CHROMIUM_YTDLP_DIR` or `~/Videos`;
5. reports throttled progress to Quickshell's bottom-centre OSD;
6. generates a square FFmpeg thumbnail;
7. sends a completion notification whose action opens the file in mpv.

Playlists are disabled and format selection is left to yt-dlp. Unsupported pages
and failures produce critical notifications containing yt-dlp's error, truncated
to 240 characters. Native host manifests restrict each host to its exact
extension ID.

The repair helper is a dry run unless given `--apply`, refuses to write while the
browser's singleton socket is active, backs up `Preferences` with a timestamp,
and removes only obsolete Download Video registrations.

## Docker development environments

`SUPER+SHIFT+A` → Development → Docker environments, backed by
`scripts/docker-dev-env`. It starts, stops, inspects, and tails logs for local
MySQL, PostgreSQL, MariaDB, and Redis.

The Compose stack binds only to `127.0.0.1`: MySQL 3306, PostgreSQL 5432,
MariaDB 3307, Redis 6379. The first start writes generated credentials to
`$XDG_STATE_HOME/docker-dev-env/environment.env`, mode 0600. Stopping a service
or the whole stack keeps its named volume.

## Power menu

`scripts/power-menu.sh` is launcher-neutral: it picks Fuzzel, then Rofi, Wofi, or
Bemenu.

| Key | Action |
| --- | --- |
| `L` | lock |
| `E` | log out |
| `U` or `H` | suspend |
| `R` | reboot |
| `S` | shut down |

Mouse selection and arrows-plus-Enter also work. Logout, reboot, and shutdown
require confirmation. Suspend starts Hyprlock in the background, waits one
second, and then calls `systemctl suspend` — the delay avoids a known race where
the machine suspends before the lock surface is up.

The five-column icon row follows adi1090x's Rofi power-menu layout, keeping the
stable layout and the imported colours separate. Rofi was chosen over wlogout
because Rofi is already installed and already themed from `colors.toml`; wlogout
would add a package plus a second set of CSS and icon assets.

It used to live in the Waybar package. When Waybar was retired it was the only
script there with a consumer outside that package, so it moved here.

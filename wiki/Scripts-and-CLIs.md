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
| `disk-speedtest` | `hypr` | disk write, read, and random 4K benchmark behind the lmenu Disk Speed Test overlay |
| `toggle` | `hypr` | facade for the toggles menu |
| `hypr-wallpaper-picker` | `hypr` | wallpaper panel and its index/search/apply backend |
| `lmenu`, `lmenu-toggle-ratio` | `menu` | the Quickshell menu and Rofi fallback |
| `desktop-mode` | `modes` | temporary desktop modes and the expiry daemon |
| `ascii-screensaver`, `ascii-screensaver-render`, `toggle-screensaver`, `screensaver-branding`, `screensaver-lock`, `transcode-ascii`, `install-ttfx` | `screensaver` | the ASCII screensaver suite |
| `ai-agent` | `ai` | launch Claude Code, Codex, OpenCode, or T3 Code |
| `windows-vm` | `windows` | the Dockur Windows 11 controller |
| `yubikey-auth` | `security` | guarded YubiKey Bio PAM setup |
| `chromium-copy-url-host`, `chromium-ytdlp-host`, `chromium-repair-download-video-shortcut` | `browser` | Chrome native messaging hosts and a repair helper |

## lmenu

`SUPER+SHIFT+A` toggles a resident Quickshell menu built from
`menu/.config/lmenu/menu.jsonc` by `lmenu-parse.py`. Search includes reachable
submenus and shows breadcrumbs. An empty search shows the current menu's rows.
Apps, fonts, and timezones are searched inside their own provider menus.

Control the resident panel with `quickshell ipc call lmenu toggle`,
`quickshell ipc call lmenu summon <route>`, or `quickshell ipc call lmenu close`.
The standalone `lmenu` command retains the Rofi fallback:

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

In Quickshell, Backspace edits the query; with an empty query it goes up a
level, or closes the root menu. In the Rofi fallback, Backspace navigates and
`Shift+Backspace` or `Ctrl+H` deletes a character.

A route is a dotted id (`style.theme`) or an alias (`themes`). The parser runs
guards in parallel. Quickshell opens from its cached tree and refreshes in the
background; Rofi streams rows and resolves selections against that same view.

Top-level routes:

| Route | Contains |
| --- | --- |
| `apps` | installed applications |
| `development` | Docker dev environments: MySQL, PostgreSQL, MariaDB, Redis, info, stop-all |
| `learn` | keybindings, Hyprland, Arch, Neovim, Bash |
| `trigger` | emoji, capture, transcode, share, toggles, speed test, disk speed test, calculator, clipboard, hardware |
| `style` | theme, background, font, gaps, transparency, Hyprland settings, bar position/toggle/transparency |
| `system` | lock, logout, suspend, hibernate, reboot, shutdown, screensaver, screensaver branding |
| `install`, `remove`, `update`, `setup`, `about` | package and system management entries |

`lmenu` falls back to the repo-relative parser path when the config is not
stowed yet, so it works before the first `stow`.

### Default applications

Setup > Defaults picks the default browser, editor, terminal, file manager, and
coding agent. Each submenu lists only what is installed and ticks the current
choice. The helper behind it lives beside the parser, so it is not on `PATH`:

```bash
~/.config/lmenu/default-apps list browser        # id, label, 1 for the current one
~/.config/lmenu/default-apps set browser firefox.desktop
DEFAULT_APPS_DRY_RUN=1 ~/.config/lmenu/default-apps set agent codex
```

| Default | Offered | Recorded in |
| --- | --- | --- |
| browser | desktop entries in `WebBrowser` that handle `https` | `text/html` and the `http`, `https`, `about`, `unknown` handlers in `mimeapps.list` |
| editor | installed editors from a fixed list; GUI editors get their wait flag | `EDITOR` and `VISUAL` in `~/.config/default-apps/editor.zsh`, sourced by `.zshrc` |
| terminal | desktop entries in `TerminalEmulator` | `~/.config/xdg-terminals.list`, read by `xdg-terminal-exec` |
| file manager | desktop entries in `FileManager` | `inode/directory` in `mimeapps.list` |
| coding agent | `ai-agent` names whose executable is on `PATH`, plus installed web apps as `webapp:<id>` | `default_agent` in `~/.config/ai-agent/config` |

Desktop entries that are hidden, `Terminal=true`, or point at a missing program
are skipped. Files are rewritten in place, so a Stow symlink such as
`mimeapps.list` keeps pointing into the repository and the change shows up in
`git diff`. Every change reloads Hyprland (skipped outside a Hyprland session, in
a dry run, or with `DEFAULT_APPS_NO_RELOAD=1`). `SUPER+E` follows the file
manager: `conf/variables.lua` reads the `inode/directory` handler from
`mimeapps.list` at load and runs it through `gtk-launch`, falling back to
`nautilus`. `SUPER+Return` still runs `kitty`.

Existing desktop-specific files such as `hyprland-mimeapps.list` take precedence
when reading defaults. Browser and file-manager changes update these overrides
as well as the generic file, so the menu and launchers agree.

## Hyprland helpers

Under `hypr/.config/hypr/scripts/`.

| Script | Bound to | What it does |
| --- | --- | --- |
| `Dropterminal.sh` | `SUPER+SHIFT+Return` | Kitty scratchpad on a special workspace |
| `calculator.sh` | `SUPER+CTRL+Q`, `SUPER+SHIFT+C` | `qalc` behind Rofi; Enter copies the answer |
| `quick-search.sh` | `SUPER+A` | apps view; `Tab` cycles windows, apps, commands |
| `quick-search-everything.sh` | — | category navigation plus confirmed reboot and shutdown |
| `docker-dev-env` | lmenu → Development | start, stop, inspect, and tail local MySQL, PostgreSQL, MariaDB, Redis |
| `vm-preset` | lmenu → Development | create a blank Debian 13, Debian 13 + Docker, or Windows 11 VM, installed unattended |
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
| `voice-dictation` | `SUPER+R`, lmenu → Voice dictation | picks the dictation microphone, syncs it into Hyprvoice only when it changed, then toggles Hyprvoice |
| `spotify-notify.sh` | autostart | track-change notifications |
| `clipboard-store.sh` | `wl-paste --watch` | filters secrets and excluded apps, then stores in cliphist |
| `clipboard-wipe.sh` | manual | clears clipboard and history |
| `run-if-deployed.sh` | used by bindings | see [below](#the-deployment-guard) |
| `run-or-install` | used by bindings | see [below](#missing-programs) |
| `shell-reload.sh` | manual, `dots deploy` | reloads Hyprland, then stops both Quickshell instances and relaunches them with `--daemonize` |
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

### Missing programs

```bash
run-or-install [--dry-run] <command> [args...]
```

Bindings that launch a program by name go through this. When the command is on
`PATH` it is run straight away, after one `command -v`. Otherwise the wrapper
looks up the package that provides it:

1. `hypr/.config/hypr/conf/install-map.tsv`: command, package, and `repo` or
   `aur`, for AUR packages and names pacman cannot find
2. `pacman -F /usr/bin/<command>`, which needs the files database
   (`sudo pacman -Fy`)

It then shows a notification. With a package, it offers **Install** and
**Dismiss**; Install opens Kitty running `sudo pacman -S --needed <package>`,
or `yay` (or `paru`) for the AUR, and starts the program with its original
arguments once the install succeeds. You type the sudo password in that
terminal; nothing is installed any other way. With no package, or an AUR
package and no AUR helper, it only explains. A repeated press within 10 seconds
does not prompt again.

If the installation terminal is missing, the notification gives the install
command to run in another terminal or a TTY, without an Install button.

`--dry-run` prints the lookup result and the install command, and neither
notifies nor installs nor runs anything. `RUN_OR_INSTALL_MAP`,
`RUN_OR_INSTALL_TERMINAL`, and `RUN_OR_INSTALL_QUIET_SECONDS` override the map,
the terminal, and the quiet window.

## Capture suite

Entry point: `hypr/.config/hypr/scripts/capture/capture.sh`. It dispatches to
`screenshot.sh`, `record.sh`, `ocr.sh`, `qr.sh`, `color.sh`, and `menu.sh`. `select.sh`
supplies transform-aware Hyprland geometry and frozen-screen region selection;
`common.sh` and `config.sh` are sourced libraries.

| Command | Behaviour |
| --- | --- |
| `screenshot smart` | drag selects a region; a small click selects the smallest visible window under the pointer; copies the PNG and offers Edit/Save buttons |
| `screenshot window` | active window geometry |
| `screenshot monitor [--delay=N]` | focused output, optionally delayed |
| `record toggle` | start/stop GPU recording with optional audio, webcam, and post-processing |
| `record webcam-toggle` | show or hide a standalone webcam preview |
| `record webcam-size smaller\|larger` | opens a missing overlay, then steps through three 16:9 presets |
| `ocr` | select, freeze-capture, preprocess, Tesseract, copy |
| `qr` | select a region, decode QR symbols only, copy the value as sensitive clipboard content |
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

Screenshots stay temporary until **Save** writes them to `SCREENSHOT_DIR`.
**Edit** opens Satty with clipboard copy and file saving enabled. Dismissing
the notification removes the temporary image and leaves the clipboard copy.
`--save` saves immediately; `--copy` uses only the clipboard.
For default captures, clipboard, editor, and save failures retain the original
image and report its path. Each editing session reserves a unique output
filename; unused empty reservations are removed on exit. Custom editor
launchers must wait for their editor to finish reading the input before returning.

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

`SUPER+ALT+A` opens the manager.

```bash
webapp list
webapp install --name "YouTube" --url https://youtube.com/
webapp install --name "Local" --url localhost:8080/app --icon ~/pic.png
webapp edit youtube --name "YT" --url https://youtube.com/feed
webapp edit youtube --icon ~/pic.png
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

- **Browser**: `$WEBAPP_BROWSER` if set, otherwise the XDG default browser when
  it is Chromium-family, otherwise the first of `brave`, `chromium`,
  `chromium-browser`, `google-chrome`, `google-chrome-stable`, `helium-browser`
  on `PATH`. A Firefox default falls back to that list, since only Chromium
  browsers have an `--app=` mode; `webapp doctor` shows which rule won. Web apps
  share that browser's normal profile, so logins work.
- **Window class**: Brave ignores `--class` for app-mode windows and derives its
  own, e.g. `brave-youtube.com__-Default`; Helium and other derivatives keep
  Chromium's prefix, e.g. `chrome-youtube.com__-Default`. That is recorded as
  `wm_class` in the metadata and is what a per-app Hyprland rule must match. It
  is never plain `brave-browser`, so the workspace-2 rule does not capture web
  apps.
- **Icons** are normalised to PNG, because gdk-pixbuf here has no SVG or WebP
  loader and Rofi could not otherwise render them. Discovery prefers a declared
  `apple-touch-icon` or a sized raster over an SVG favicon; with nothing found, a
  letter tile is generated in the active theme's accent colour.
- Only `http` and `https` are accepted. `file:`, `data:`, and `javascript:` are
  rejected. URLs never pass through a shell and never appear in an `Exec` line —
  the launcher receives only the app id.

## AI launcher

`ai-agent` preserves the caller's working directory and launches Claude Code,
Codex, OpenCode, T3 Code, or an installed web app. A web app is selected as
`webapp:<id>`, using the id from `webapp list`, and runs through
`webapp-launch <id>`; it takes no agent arguments. Selection precedence: `--agent`, then
`AI_AGENT_DEFAULT`, then the config file at `AI_AGENT_CONFIG` (default
`~/.config/ai-agent/config`, which sets `default_agent=t3code`).

Invalid names and unavailable executables fail clearly. The launcher never
silently switches to another agent. Claude runs through `teamclaude run --`;
install and configure TeamClaude first and make `teamclaude` available on `PATH`.

After stowing `ai` and `zsh`:

```bash
ai                                 # the configured default
ai-claude / ai-codex / ai-opencode / ai-t3code
ai-agent --agent claude
ai-agent --agent codex -- --help
ai-agent --agent webapp:chatgpt    # a web app, by its id
```

The aliases are only defined when their names are otherwise unused.

Setup > Defaults > Coding agent in lmenu switches the default among the
installed agents and web apps. `SUPER+I` opens the configured default. T3 Code is pinned to workspace 4 by its
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

## Virtual machine presets

`SUPER+SHIFT+A` → Development → Virtual machines, backed by `scripts/vm-preset`
and the answer-file templates in `hypr/.config/hypr/vm-presets/`. Each preset
creates a new VM on `qemu:///system` and installs it without manual steps.

| Preset | Guest |
| --- | --- |
| `debian13` | Debian 13 server: standard utilities, OpenSSH, `qemu-guest-agent`, `sudo` |
| `debian13-docker` | the same, plus Docker Engine, Buildx, and the Compose plugin from Docker's apt repository, with the user in the `docker` group |
| `win11` | Windows 11 Pro, unactivated, with the user as a local administrator and no Microsoft account; nothing else added |

Each Debian VM gets 2 vCPUs, 4 GiB of RAM, a 60 GiB qcow2 disk in the `default` pool,
and the `default` NAT network. `VM_PRESET_VCPUS`, `VM_PRESET_MEMORY` (MiB), and
`VM_PRESET_DISK_GB` override them. Windows 11 VMs get 4 vCPUs, 6 GiB, a 100
GiB SATA disk, an e1000e NIC, UEFI, and an emulated TPM; a clone's disk cannot
be smaller than the base's.

1. Prerequisites are checked, and anything missing is listed in one
   notification.
2. Rofi asks for the VM name, pre-filled with the next free `<preset>-N`; the
   guest password, twice; and, when `~/.ssh/id_rsa.pub` exists, whether to
   install it. Installing the key turns off SSH password login in the guest.
3. The newest Debian 13 netinst in `$XDG_CACHE_HOME/vm-presets/` is reused.
   Otherwise it is downloaded and checked against `SHA512SUMS`, and against its
   signature when the Debian CD key is in your keyring.
   `vm-preset refresh-iso debian13` fetches a newer point release.
4. `virt-install` starts the install and the console opens in virt-manager.
   Closing the console does not stop the install; a notification says when it
   finishes.

The guest username is the host `$USER`. The root account stays locked and the
user gets sudo. The password is hashed with `openssl passwd -6` as soon as it is
read; only the hash reaches the preseed, which lives in a mode 0700 temporary
directory that is removed once the install starts. If `virt-install` fails, the
VM and its disk are removed. Each VM's creation log is
`$XDG_STATE_HOME/vm-presets/<name>.log`.

`vm-preset --dry-run create PRESET [--name NAME]` prints the `virt-install`
command and the rendered answer files, with the hash redacted, without calling
libvirt or the network.

### Windows 11

`win11` VMs are copy-on-write clones of a sysprepped base image, so only the
first one is slow.

1. Download the ISO from <https://www.microsoft.com/software-download/windows11>
   into `~/Resources/ISO` (`VM_PRESET_WIN11_ISO_DIR`). The newest `Win11*.iso`
   there is used in place, with no checksum check.
2. The first `create win11` builds `win11-base.qcow2` in the `default` pool:
   an offline unattended install, one automatic logon as the built-in
   Administrator with a random password, then `sysprep /generalize /oobe
   /shutdown /mode:vm`. This takes about 20–30 minutes. The `win11-base` VM is
   then undefined and only its disk is kept.
3. Each create, including the first, clones that disk with `backing_store` and
   boots it with an answer disc that sets the computer name (the VM name cut to
   15 characters) and creates the user as a local administrator. A clone is
   ready in a few minutes.

There is no SSH key prompt. Windows takes the password only in a reversible
encoding, so it sits on a 0644 answer disc in `$XDG_CACHE_HOME/vm-presets/`
until the clone's first reboot, when the disc is ejected and deleted. If that
reboot cannot be confirmed within 15 minutes, creation fails and removes the
incomplete clone. A clone disk must be at least as large as its base image. Device
encryption is turned off in the base because every clone gets a new TPM.

To rebuild the base from a newer ISO, delete every Windows 11 clone first,
since each depends on it, then run `virsh -c qemu:///system vol-delete
--pool default win11-base.qcow2`. If a base build is interrupted, delete the
`win11-base` VM and its disk in virt-manager. `VM_PRESET_WIN11_LANGUAGE`
(default `en-US`) must match the ISO's language; the time zone follows the host
for common US zones and London, otherwise UTC (`VM_PRESET_WIN11_TIMEZONE`).

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

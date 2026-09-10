# Troubleshooting

Start with the repository-specific checks: is the Stow link pointing at this
clone, is the component you are editing the *active* one, and do the generated
files exist? Then move on to ordinary Hyprland and Wayland diagnostics.

## Hyprland config changes do nothing

1. Confirm `~/.config/hypr/hyprland.lua` resolves into this repository:
   `readlink -f ~/.config/hypr/hyprland.lua`.
2. Check that all six required modules exist. `conf/decorations.lua`,
   `monitors.lua`, and `workspaces.lua` are generated — a fresh clone has none of
   them.
3. Run `theme set <slug>` if `decorations.lua` is missing.
4. Read Hyprland's config error output before reloading.
5. Remember the monitor watcher and the theme generator overwrite derived files.

If a command built from `scripts_dir` fails on a different account, replace the
hardcoded `/home/liam` in `conf/variables.lua`.

Two dispatcher gotchas under the Lua config: `hyprctl dispatch exec` and
`hyprctl keyword` do nothing. Use `hyprctl eval`.

`hl.env` changes — including the `PATH` prepend — take effect at **next login**,
not on `hyprctl reload`.

## Quickshell bar or panels do not appear

Check that `quickshell` is installed and `shell.qml` is deployed. Then check the
generated active theme:

```bash
ls ~/.config/hypr/themes/.active/theme.json   # missing → run `theme set <slug>`
quickshell log
```

Panel-specific failures usually mean a missing external command:

- network: `nmcli`, `nmtui`, `qrencode`, `curl`; profile changes may need a
  polkit prompt;
- display brightness: `ddcutil` and permission on the DDC/I²C device;
- clipboard: `cliphist`, `wl-paste`, `wl-copy`;
- keybinding palette: a responsive `hyprctl` socket;
- weather, lyrics, wallpaper: network access to the relevant public API;
- desktop modes: `desktop-mode doctor --json`. The panel deliberately reports an
  unavailable backend rather than claiming a toggle worked.

Editing SwayNC or Noctalia changes nothing you can see. Only Quickshell is
running.

## Notifications do not appear

```bash
notificationctl status --json
```

That tells you whether the service is reachable and whether DND is on. Then check
that no second daemon is competing for `org.freedesktop.Notifications` — SwayNC
should be stopped.

State lives under `$XDG_STATE_HOME/hyprland-desktop/notifications`. Critical
notifications are persistent by design; everything else follows `config.json`.

## Screensaver misses a monitor, or closes immediately

```bash
ascii-screensaver --dry-run
```

Every active output should have one planned spawn. The launcher focuses each
monitor before spawning and waits for that terminal's `openwindow` event, so
check that `socat` can open Hyprland's `.socket2.sock` and that the window class
is `io.github.fhlkfds.screensaver`.

If it closes without input, check `hyprctl activewindow -j` — focus has to stay
on the screensaver class. Pointer movement does not dismiss it, but focus loss
does.

## Browser shortcuts

### Copy URL or Download Video does nothing

1. Fully close and reopen the browser after changing flags or extension files.
2. On the browser's extension-shortcuts page, confirm `ALT+SHIFT+L` and
   `ALT+SHIFT+D` are assigned to the bundled extensions.
3. Confirm the browser launches with the checked-in `--load-extension` paths.
4. Confirm `NativeMessagingHosts/io.github.fhlkfds.copy_url.json` and
   `com.omarchy.ytdlp.json` exist under the real profile root.
5. Inspect those manifests for `/home/liam` paths if you are on another account.
6. Check the host executables are executable and that `jq`, `wl-copy`, `yt-dlp`,
   and `notify-send` resolve in their restricted `PATH`.

If an obsolete Download Video extension still owns the shortcut:

```bash
chromium-repair-download-video-shortcut ~/.config/BraveSoftware/Brave-Browser
```

Review the proposed stale registrations, fully quit the browser, then rerun with
`--apply`. It backs up `Preferences` and refuses to write while the browser's
singleton socket is live.

### Download Video says "unavailable" or "failed"

The notification body is yt-dlp's own error, truncated to 240 characters.
Reproduce it for the full output:

```bash
yt-dlp --no-playlist --simulate --verbose -- 'https://example.invalid/video-page'
```

Common causes: an outdated extractor, required authentication or cookies, DRM,
regional restriction, network failure, or a page with no supported media.

Also check that `$CHROMIUM_YTDLP_DIR` or `~/Videos` exists and is writable, that
only one worker holds `${XDG_RUNTIME_DIR:-/tmp}/chromium-ytdlp-${UID}.lock`, and
that FFmpeg's absence only costs you the thumbnail.

To stop a running worker without killing the browser, find it precisely first:

```bash
pgrep -af 'chromium-ytdlp-host.*--download'
kill <PID>
```

Do not use a broad pattern — it will take browser processes with it.

## Wallpaper picker shows no local results

It defaults to `~/Pictures/Wallpapers`. Create that directory and put JPEG or PNG
files in it; `stow --target="$HOME/Pictures/Wallpapers" wallpaper` deploys the
tracked assets straight there. Local matching is by filename.

Empty remote results need `curl`, `jq`, DNS, and a successful Wallhaven API
response. If the menu reports a Cisco Umbrella DNS block, allow-list
`wallhaven.cc`, `th.wallhaven.cc`, and `w.wallhaven.cc` and retry. Do not disable
TLS verification — the block-page address is not the Wallhaven API.

If selecting a result fails, check ImageMagick validation and Hyprpaper. Applying
a wallpaper restarts Hyprpaper, and an invalid download is rejected rather than
handed to it.

## Wrong monitor layout, or workspaces collapsed onto one screen

Ask the applier first:

```bash
~/.config/hypr/scripts/auto-monitor-profile.sh --dry-run
journalctl -t hypr-monitor -n 50
```

The dry run prints the selected profile, a desired-vs-actual table per monitor,
and whether the generated files still match.

Collapsed workspaces mean the `laptop` profile was applied while the externals
were connected — it pins 1–15 to `eDP-1`, which is disabled when docked. That
happens when detection fails. Confirm the EDID strings still match `KVM_DESCS`:

```bash
hyprctl monitors -j | jq -r '.[].description'
```

**Do not diagnose by connector name.** The KVM renumbers them on every switch;
that is the entire reason the profile matches on EDID.

If nothing reacts to a hotplug, the watcher is not running:

```bash
systemctl --user status hypr-monitor-watch.service
pgrep -af hypr-monitor-watch.py
```

Make durable corrections under `monitor_profiles/` with
`capture-monitor-profile.sh`. The active files are overwritten. The display
panel's scale helper persists only to the desktop profile.

## Launcher entries fail

| Symptom | Cause |
| --- | --- |
| calculator reports a missing command | install `libqalculate`, Rofi, `wl-clipboard` |
| HEIC transcode fails | install `libheif` for ImageMagick's HEIF delegate |
| LocalSend or btop binding does nothing | install `localsend` or `btop` |
| old wallpaper selector has a theme error | missing `config-wallpaper.rasi` |
| a binding silently does nothing | the owning Stow package is not deployed — bindings routed through `run-if-deployed.sh` will say so, others will not |

Rofi also needs the generated current theme. Run `theme set <slug>` rather than
inventing an empty `current-theme.rasi`.

## Windows VM will not start or connect

```bash
windows-vm status
windows-vm logs
```

Usual causes: an inactive Docker daemon, a login session that has not picked up
new `docker` group membership, inaccessible `/dev/kvm` or `/dev/net/tun`, or
ports 3389/8006 already in use. The helper never falls back to sudo and never
exposes either port beyond localhost.

During first installation, open `http://127.0.0.1:8006` to watch progress.
`launch` waits for an authenticated RDP endpoint instead of sleeping a fixed
interval. If readiness times out or FreeRDP errors, the VM stays running so its
logs and web console remain inspectable.

If an older session left a "Certificate for 127.0.0.1:3389 has changed" dialog
open, dismiss it once with Escape. Later launches will not create it.

## Capture failures

```bash
~/.config/hypr/scripts/capture/capture.sh doctor
```

The smart selector needs live Hyprland monitor and window JSON. Rotated or scaled
outputs depend particularly on `jq`, `slurp`, and the transform logic. Recording
needs `gpu-screen-recorder`; OCR needs Tesseract language data and ImageMagick;
editing needs Satty.

Check write permission and free space in `SCREENSHOT_DIR` and `SCREENRECORD_DIR`.
Runtime PID and state files under `$XDG_RUNTIME_DIR` can explain a stale "already
recording" state — inspect the file and the process before deleting anything.

## Lock or idle behaviour fails

- Confirm Hypridle and Hyprlock are installed and running.
- Confirm the generated `~/.config/hyprlock/colors.conf` exists.
- Run `hypr-wallpaper-picker current` and confirm it prints an existing image;
  missing state should fall back to the theme colour, not a black screen.
- Check Noto Sans and JetBrainsMono Nerd Font resolve through Fontconfig.
- Verify the `hyprlock` PAM service is installed correctly.
- For suspend, check `systemctl suspend` policy and inhibitors.
- Alternate Hyprlock layouts may assume `BAT0`, extra fonts, a profile image,
  playerctl, or network access that the active layout does not.

If the session locks when you expected stay-awake to hold it: stay-awake gates
the **idle lock listener only**. It does not inhibit DPMS, suspend, manual
locking, or before-sleep locking. The lock condition also fails toward locking
when `desktop-mode` is absent or its state is malformed. That is intentional.

## Update count looks wrong

The indicator refreshes every 15 minutes and after its own update window closes.
A `checkupdates` run that cannot reach the mirrors exits non-zero rather than
reporting zero, so the count holds its last known value, the hover tray says
`Last check failed`, and it retries after two minutes.

Reproduce directly:

```bash
~/.config/hypr/scripts/arch-updates          # prints JSON, exits non-zero on a failed sync
```

## Missing icons or wrong fonts

Install JetBrainsMono Nerd Font, Noto Sans, and Papirus, then check the exact
family names Fontconfig exposes. Empty squares in the bar or the lock-screen user
label are almost always a Nerd Font mismatch, not a QML bug.

## Shell startup is slow or noisy

The optional Zsh config runs Pokémon Color Scripts piped into Fastfetch on every
interactive shell and loads several plugin files. Missing commands produce
startup errors. Disable the greeting or the missing `source` lines in
`zsh/.zshrc`, and replace the personal GAM and VPN paths before reuse.

`source $ZSH/oh-my-zsh.sh` failing on every prompt means Oh My Zsh was never
installed. `zsh/.oh-my-zsh/` is gitignored by design — see
[Getting started](Getting-Started.md#oh-my-zsh-is-not-in-this-repository).

## Where the boundary is

This repository does not declare an Arch package list, a GPU-specific
environment, or a GTK/Qt/cursor theme. If a failure depends on one of those, the
required system setup is not determinable from these files. Use the compositor
and application logs to find it, then add the discovered dependency to the
repository rather than leaving it as undocumented machine state.

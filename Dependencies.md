# Dependencies

There is no package manifest or installer in this repository. These tables are
derived from executable names, config references, imports, and scripts. They are
not claimed to be an exhaustive Arch package list.

"Required" means required for the currently configured session, or for the named
feature. An application bound to a key is listed separately: Hyprland runs
without it, that feature does not.

If you want this installed for you, see
[Deploying with Ansible](Deploying-with-Ansible.md) — the playbook carries a
confirmed package list.

## Core desktop

| Command / package | Status | Used by |
| --- | --- | --- |
| Hyprland | required | compositor and IPC |
| Quickshell | required | bar, panels, notifications, OSDs |
| Hyprpaper | required for wallpaper | autostart, themes, picker |
| Hypridle | required for the idle policy | autostart |
| Hyprlock | required for locking | idle and `SUPER+L` |
| Hyprsunset | required for night light | autostart and `night-light.sh` |
| Kitty | configured terminal | bindings, panel helpers, the XDG editor entry |
| Rofi | configured launcher | app menu, lmenu, power menu, calculator, emoji |
| Python 3.11+ | required | theme generator (needs `tomllib`), wallpaper, web apps, `notificationctl` |
| `jq` | required | Hyprland JSON, native hosts, wallpaper, monitor tools |
| `wl-clipboard` | required | `wl-copy`, `wl-paste` |
| `cliphist` | required | clipboard watchers and panel |
| `libnotify` / `notify-send` | required | desktop feedback across most scripts |
| `curl` | required | wallpaper, lyrics, weather, speed test |
| `playerctl` | required | media bindings, Spotify notifier, lock helpers |
| `udiskie` | configured | removable-media automounting |
| PipeWire / WirePlumber | configured | `wpctl`, Quickshell audio |
| NetworkManager | configured | `nmcli`, `nmtui`, the network panel |
| `bluez-utils` | configured | `bluetoothctl` |
| `iputils` | configured | dashboard and network checks |
| `qrencode` | network panel | runtime-only Wi-Fi QR |
| polkit provider | configured | NetworkManager authorization for persistent DNS/IPv4 changes |
| `greetd` | display manager | login |
| `greetd-regreet` | themed GTK4 greeter | `[default_session]` |
| `greetd-tuigreet` | rescue greeter | manual fallback |

Also needed: a working Wayland session, a D-Bus user bus, a font stack, the
`hyprlock` PAM service, and ordinary core utilities (`bash`, `realpath`, `flock`,
`setsid`, `find`, `sed`).

## Bound applications

| Command | Reached by |
| --- | --- |
| `helium-browser` | `SUPER+W`, browser autostart, XDG HTTP/HTML default |
| `brave` | the browser-extension tooling |
| `nautilus` | `SUPER+E`, `files-here.sh` |
| `gnome-disks` | `SUPER+SHIFT+D` |
| `spotify` | `SUPER+S`, autostart, workspace rule |
| `obsidian` | `SUPER+O`, autostart, workspace rule |
| `virt-manager` | autostart, workspace rule |
| `hermes` | `SUPER+SHIFT+H`, autostart, workspace rule |
| `t3code` | `SUPER+I` default agent, autostart, workspace rule |
| `hyprvoice` | `SUPER+R` |
| `virsh`, `looking-glass-client` | `SUPER+SHIFT+G` |
| `windows-vm` | `SUPER+ALT+W`, `SUPER+CTRL+ALT+W` |
| `localsend` | `SUPER+CTRL+S` |
| `btop` | `SUPER+CTRL+T` |
| `imv`, `mpv`, Zathura, Neovim | XDG MIME handlers |
| Cisco Packet Tracer, T3 Code, Claude Code handlers | XDG file and URL handlers referenced but not supplied here |

## Per-feature

### Capture

| Command | For |
| --- | --- |
| `grim`, `slurp`, `hyprpicker` | screenshots, frozen selection, colour picking |
| `gpu-screen-recorder` | recording |
| FFmpeg | post-processing and browser thumbnails |
| ImageMagick (`magick`) | OCR preprocessing, image validation |
| Tesseract + language data | OCR |
| `satty` | screenshot editing |
| `v4l2-ctl` | webcam discovery |
| mpv | recording playback, webcam overlay |

`capture.sh doctor` reports the suite's own availability.

### Display and monitors

`ddcutil` for external brightness, `hyprctl` for discovery and profile
application, `systemd`/`loginctl` for suspend and pre-sleep locking. `luac` is
used by `capture-monitor-profile.sh` to validate generated Lua.

### Themes and wallpaper

Python 3.11+, plus Bash, `curl`, `jq`, ImageMagick, and Hyprpaper for the
wallpaper tool. The theme system can call Hyprland, Hyprpaper, Kitty, SwayNC, and
Quickshell to refresh running components.

### ASCII screensaver

Bash, `ttfx`, `xdg-terminal-exec`, `socat`, `jq`, Hypridle, Hyprland IPC,
Hyprlock, and one supported terminal (Kitty, Foot, Ghostty, or Alacritty).
ImageMagick 7 is needed only for PNG/SVG logo conversion.

`ttfx` is in neither the official repositories nor the AUR. `install-ttfx` tries
`paru` or `yay` first, then falls back to a locked Cargo build from
`omacom-io/ttfx` installed under `~/.local/bin`.

### Security keys

`pam-u2f` (including `pamu2fcfg`) and `libfido2`. Fingerprints enrol with
`fido2-token`, so `yubikey-manager` is not required. The SSH-agent path in the
GnuPG examples additionally needs `gnupg`.

### Browser tools

A Chromium-family browser for the extension runtime and native messaging, plus
`yt-dlp`, `jq`, FFmpeg (thumbnail), and mpv (the notification action). Quickshell
provides the progress OSD; without it, failure notifications still work.

### Transcoder and calculator

FFmpeg with `libx264`, ImageMagick, `libheif` for HEIC/HEIF, `file`, Rofi,
`wl-clipboard`, Python 3 for standards-compliant file URI encoding,
`libqalculate` (`qalc`), and `libnotify`.

### Docker development environments

Docker Engine, Docker Compose, and OpenSSL.

### Windows VM

Docker Engine, Docker Compose, FreeRDP 3, KVM, `jq`, `flock`, and `timeout`. It
prefers `sdl-freerdp3` and falls back to `xfreerdp3`. The host must expose
writable `/dev/kvm` and `/dev/net/tun` to the Docker user.

One-time setup is manual, because the helper never runs sudo:

```bash
sudo systemctl enable --now docker.service
sudo usermod -aG docker liam
```

Log out and back in, then confirm `docker info` works without sudo. Docker-group
membership is effectively root-equivalent.

### Update indicator

`checkupdates` from `pacman-contrib` for repository packages, and either `yay` or
`paru` for AUR packages.

## Shell

`zsh`, Oh My Zsh, `zsh-autosuggestions`, `zsh-syntax-highlighting`, `fzf`,
`fzf-tab`, `eza`, Powerlevel10k. Fastfetch and Pokémon Color Scripts for the
interactive greeting.

Oh My Zsh and the two `$ZSH_CUSTOM` pieces are not vendored here and cannot be —
see [Getting started](Getting-Started.md#oh-my-zsh-is-not-in-this-repository).

## Fonts and icons

| Asset | Used by |
| --- | --- |
| JetBrainsMono Nerd Font | Kitty, bar and panel glyphs, Rofi, lock screen |
| Noto Sans | Quickshell UI fallback, active Hyprlock clock and date |
| Papirus | Rofi icons |
| A Powerlevel10k-compatible glyph font | Zsh prompt |

Missing Nerd Font glyphs show as empty squares even when the command underneath
works fine.

## Optional and retained

| Component | Why it is optional |
| --- | --- |
| SwayNC | configuration retained; startup commented out |
| Wofi, Fuzzel, Bemenu | power-menu fallbacks; the Wofi config is retained |
| Noctalia | settings and plugins retained; startup commented out |
| PulseAudio `pactl` | duplicate fallback volume bindings; `wpctl` registers first and shadows them |
| Cava | the audio visualiser shell instance |
| mpvpaper | retained video-wallpaper paths |
| nwg-displays | wrote the original Lua monitor files; not required by the active loader |
| Fastfetch, Pokémon Color Scripts | the interactive Zsh greeting |

## Things this repository does not establish

No Arch package list, no GPU-specific environment, and no GTK, Qt, Kvantum, or
cursor theme for the interactive desktop. If a failure depends on one of those,
the required setup is not determinable from these files. Find it, then add it to
the repository rather than leaving it as undocumented machine state.

The one exception is regreet, which pins `Adwaita` and a font because it needs
concrete values.

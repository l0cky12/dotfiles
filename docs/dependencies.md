# Dependencies

There is no package manifest or installer in the repository. The tables below are
derived from executable names, configuration references, imports, and scripts;
they are intentionally not claimed to be an exhaustive Arch package list.

“Required” means required for the currently configured session or the named
active path. An application bound to a key is listed separately because Hyprland
can run without it, but that feature cannot.

## Core active desktop

| Command / package | Status | Used by |
| --- | --- | --- |
| Hyprland | required | compositor and IPC |
| Quickshell | required for configured shell | bar, panels, notifications, OSD |
| Hyprpaper | required for wallpaper path | autostart, themes, picker |
| Hypridle | required for configured idle policy | autostart |
| Hyprlock | required for lock behavior | idle and `SUPER+L` |
| Hyprsunset | required for night light | autostart and toggle script |
| Kitty | configured terminal | bindings, panel helpers, XDG editor entry |
| Rofi | configured launcher | app menu and helper menus |
| `jq` | required by multiple active scripts | Hyprland JSON, native hosts, wallpaper |
| `wl-clipboard` | required for clipboard flow | `wl-copy`, `wl-paste` |
| `cliphist` | required for history | startup watchers and panel |
| `libnotify` / `notify-send` | required by several scripts | desktop feedback |
| Python 3.11+ | required by generated/theme/backends | theme, wallpaper, web apps, notification helper |
| `ascii-screensaver` package | optional Hypridle action | `ttfx` terminal screensaver commands and assets |
| `desktop-mode` package | configured mode controls | night light, DND, selective stay-awake, mode panel |
| `curl` | active network helpers | wallpaper, lyrics, weather, art |
| `playerctl` | media integration | bindings and Spotify/lock helpers |
| `udiskie` | configured startup tool | removable media |
| PipeWire/WirePlumber tools | configured audio path | `wpctl`, Quickshell PipeWire |
| `upower` | required for battery widget | UPower daemon used by `Quickshell.Services.UPower`; without it the widget remains hidden |
| NetworkManager | configured network path | `nmcli`, `nmtui`, Network panel connection/DNS/IPv4 controls |
| `qrencode` | network-panel Wi-Fi sharing | renders the runtime-only Wi-Fi QR SVG; never stores a plaintext secret |
| `bluez-utils` | configured Bluetooth widget | `bluetoothctl` |
| `iputils` | dashboard/network checks | `ping` |
| polkit provider | NetworkManager authorization | persistent DNS and IPv4 profile changes when the active policy requires confirmation |
| `greetd` | display manager, already installed/enabled on this machine | login; `system/greetd/config.toml` |
| `greetd-regreet` | themed GTK4 greeter | `[default_session]` in `system/greetd/config.toml` |
| `greetd-tuigreet` | rescue greeter | manual fallback via `/etc/greetd/config.toml.pre-regreet`, see `greeter/README.md` |

The system also needs a working Wayland session, D-Bus user bus, font stack, PAM
Hyprlock service, and ordinary core utilities (`bash`, `sh`, `realpath`, `flock`,
`setsid`, `find`, `sed`, and similar).

## Configured applications

| Command | Role / binding |
| --- | --- |
| `helium-browser` | `SUPER+W`, browser autostart |
| `brave` | browser extensions |
| XDG default browser (currently Helium via `helium.desktop`) | `SUPER+SHIFT+ALT+W` private-window launcher |
| `nautilus` | `SUPER+E`, file-manager helpers |
| `gnome-disks` | `SUPER+SHIFT+D` |
| `spotify` | `SUPER+S`, autostart/workspace rule |
| `obsidian` | `SUPER+O`, autostart/workspace rule |
| `virt-manager` | autostart/workspace rule |
| `hermes` | `SUPER+SHIFT+H`, autostart/workspace rule |
| `hyprvoice` | `SUPER+R` |
| `virsh`, `looking-glass-client` | Gaming VM binding |
| `windows-vm` | `SUPER+ALT+W` launch and `SUPER+CTRL+ALT+W` stop; optional Dockur Windows 11 VM |
| `localsend` (LocalSend) | `SUPER+CTRL+S`, local-network sharing |
| `btop` | `SUPER+CTRL+T`, terminal activity monitor |
| Helium | XDG default HTTP/HTML handler |
| `imv`, `mpv`, Zathura, Neovim | XDG MIME handlers |
| Cisco Packet Tracer, T3 Code, Claude Code handlers | externally referenced XDG file/URL handlers |

Helium is the MIME default and Hyprland binding/autostart browser. Brave remains
supported by the browser-extension tooling.

## Feature-specific dependencies

### Network speed test

`network-speedtest` requires Bash, `curl`, `jq`, `awk` from Arch's `gawk`
package, and `ip` from `iproute2`.

```bash
paru -S --needed curl jq gawk iproute2
```

### Capture

| Command | Feature |
| --- | --- |
| `grim`, `slurp`, `hyprpicker` | screenshots, frozen selection, colors |
| `gpu-screen-recorder` | screen recording |
| FFmpeg | post-processing and browser thumbnails |
| ImageMagick (`magick`) | OCR preprocessing, image validation/manipulation |
| Tesseract + selected language data | OCR |
| `satty` | screenshot editing |
| `v4l2-ctl` | webcam discovery |
| mpv | recording/video playback |

Run `capture.sh doctor` for the suite's own availability report.

### Display and monitors

| Command | Feature |
| --- | --- |
| `ddcutil` | external-monitor brightness |
| `hyprctl` | output discovery, profile application, scale changes |
| `systemd`/`loginctl` | suspend and pre-sleep lock behavior |

### Security-key authentication

The optional YubiKey Bio PAM path requires `pam-u2f` (including `pamu2fcfg`) and
`libfido2`. Fingerprints can be enrolled with `fido2-token`, so the current
templates do not require `yubikey-manager`. They use a host-local
`/etc/u2f_mappings` file, and password authentication remains available. Stow
the `security` package to install the guarded `yubikey-auth` helper. The
package also ships example `gpg.conf`/`gpg-agent.conf` templates; using the
SSH-agent path additionally requires `gnupg`.

### ASCII screensaver

The screensaver requires Bash, `ttfx`, `xdg-terminal-exec`, `socat`, `jq`,
Hypridle, Hyprland IPC, Hyprlock, and the selected supported terminal (Kitty,
Foot, Ghostty, or Alacritty). ImageMagick 7 is required only for PNG/SVG logo
conversion. The included installer tries `paru` or `yay`, then builds `ttfx`
from source with Cargo when no package exists.

### Docker development environments

The Development menu requires Docker Engine, Docker Compose, and OpenSSL. Its
Compose stack binds only to `127.0.0.1`: MySQL uses port 3306, PostgreSQL 5432,
MariaDB 3307, and Redis 6379. The first start writes generated credentials to
`$XDG_STATE_HOME/docker-dev-env/environment.env` with mode 0600. Stopping a
service or the whole stack keeps its named volume.

### Windows VM

The optional `windows` Stow package requires Docker Engine, Docker Compose,
FreeRDP 3, KVM, `jq`, `flock`, and `timeout`. It prefers `sdl-freerdp3` and falls
back to `xfreerdp3`. The host must expose writable `/dev/kvm` and `/dev/net/tun`
to the user running Docker.

On this host the packages are installed, AMD-V and both devices are available,
but `docker.service` is disabled and the user is not in the `docker` group. The
helper diagnoses that state but never runs sudo. One-time setup is manual:

```bash
sudo systemctl enable --now docker.service
sudo usermod -aG docker liam
```

Log out and back in after changing group membership, then confirm `docker info`
works without sudo. Docker-group membership is effectively root-equivalent.

### Browser tools

| Command | Feature |
| --- | --- |
| Chromium-family browser | extension runtime/native messaging |
| yt-dlp | media detection and download |
| `jq` | native message JSON parsing |
| FFmpeg | completion thumbnail |
| mpv | notification action |
| Quickshell | progress OSD; failure notification still has fallback behavior |

### Transcoder and calculator

| Command / package | Feature |
| --- | --- |
| FFmpeg with `libx264` | MP4 and palette-based GIF conversion |
| ImageMagick (`magick`) | JPG/PNG conversion and resizing |
| `libheif` | optional HEIC/HEIF delegate for ImageMagick |
| `file` | selected-media detection |
| Rofi | file, format, size, expression, and result menus |
| `wl-clipboard` | `text/uri-list` outputs and calculator results |
| Python 3 | standards-compliant file URI encoding |
| `libqalculate` / `qalc` | calculator expression engine |
| `libnotify` / `notify-send` | success and failure feedback |

On Arch, the currently optional additions are installed separately rather than
by these dotfiles:

```bash
sudo pacman -S --needed btop libheif localsend pacman-contrib
```

The update indicator uses `checkupdates` from `pacman-contrib` for repository
packages and either `yay` or `paru` for AUR packages.

### Wallpaper and themes

The active wallpaper tool uses Bash, `curl`, `jq`, ImageMagick, Hyprpaper,
Quickshell IPC, and notifications. The theme system uses Python 3.11+ and
can call Hyprland, Hyprpaper, Kitty, SwayNC, and Quickshell to refresh running
components.

## Fonts and icon themes

| Asset | Referenced by |
| --- | --- |
| JetBrainsMono Nerd Font | Kitty, bar/panels, Rofi glyphs, lock screen |
| Noto Sans | Quickshell UI fallback and active Hyprlock clock/date |
| Papirus icons | Rofi |
| Powerlevel10k-compatible glyph font | Zsh prompt |

Missing Nerd Font glyphs typically appear as empty squares even when the command
itself works.

## Optional / retained stack

| Component | Why optional here |
| --- | --- |
| SwayNC | configuration retained; startup commented |
| Wofi, Fuzzel, Bemenu | fallback launchers for power menu; Wofi config retained |
| Noctalia | settings/plugins retained; startup commented |
| PulseAudio `pactl` | duplicate fallback volume bindings; `wpctl` is registered first |
| Fastfetch, Pokémon Color Scripts | interactive Zsh greeting |
| Oh My Zsh, Powerlevel10k, fzf-tab, eza, syntax highlighting/autosuggestions | optional tracked Zsh environment |
| Cava | inactive Hyprlock visualizer helper |
| mpvpaper | retained video-wallpaper paths |
| nwg-displays | origin of unsourced Lua monitor files, not required by active loader |

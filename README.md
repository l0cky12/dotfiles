# dotfiles

Personal Hyprland dotfiles for Arch Linux, managed with [GNU Stow](https://www.gnu.org/software/stow/).

**[Read the wiki](wiki/Home.md)** for the full reference: setup, architecture, the
complete keybinding list, where to customize each part, and how to provision a
whole machine with Ansible. This page is the feature tour.

## Setup

### Prerequisites

Install GNU Stow:

```bash
sudo pacman -S stow
```

Clone the repo into your home directory:

```bash
git clone <your-repo-url> ~/dotfiles
cd ~/dotfiles
```

> The repo must live at `~/dotfiles` for Stow to symlink correctly into `~`.

---

### Deploy with Stow

Most top-level directories are Stow packages. Run `stow <package>` to symlink its
contents into `~`.

> **`docs/`, `wiki/`, `tests/` and `system/` are not packages — never stow them.**
> `system/` holds root-owned `/etc` templates that `yubikey-auth` deploys;
> stowing it would create `~/greetd` and `~/pam.d`.

**Deploy the standard packages at once:**

```bash
stow ai browser cliphist fastfetch greeter hypr hyprlock kitty modes noctalia \
     quickshell rofi screensaver security ssh swaync systemd tmux windows \
     wallpaper wofi xdg zsh
```

**Or deploy packages individually:**

```bash
stow ai          # ~/.local/bin/ai-agent, ~/.config/ai-agent
stow screensaver # screensaver commands, terminal configs, and editable logo
stow modes       # ~/.local/bin/desktop-mode, temporary mode policy/config
stow security    # ~/.local/bin/yubikey-auth, safe YubiKey PAM setup/addition;
                 # ~/.config/gnupg-conf gpg/gpg-agent examples
stow ssh         # ~/.local/bin/sshpersist, SSH keepalive config fragment
stow tmux        # ~/.config/tmux/tmux.conf for persistent sessions
stow browser     # Chromium extensions, flags, and native messaging hosts
stow hypr        # ~/.config/hypr
stow hyprlock    # ~/.config/hyprlock
stow kitty       # ~/.config/kitty
stow rofi        # ~/.config/rofi
stow wofi        # ~/.config/wofi
stow swaync      # ~/.config/swaync
stow fastfetch   # ~/.config/fastfetch
stow noctalia    # ~/.config/noctalia
stow quickshell  # ~/.config/quickshell
stow windows     # Windows VM helper, Compose template, and application entry
stow cliphist    # ~/.config/cliphist
stow xdg         # ~/.config/mimeapps.list, ~/.local/share/applications
stow zsh         # ~/.zshrc, ~/.p10k.zsh (see Shell setup below)
```

## Persistent SSH sessions

The `ssh` and `tmux` packages provide reconnecting SSH sessions backed by tmux.
Install the required Arch packages without changing any configuration:

```bash
sudo pacman -S --needed autossh tmux
```

After stowing `ssh`, `tmux`, and optionally `zsh` for the `sshp` shortcut, add
this line near the beginning of `~/.ssh/config` (before broader `Host` blocks):

```sshconfig
Include ~/.config/ssh/conf.d/*.conf
```

That manual include keeps the existing `~/.ssh/config` under user control. Start
or return to a host-named remote session with `sshpersist <host>` or
`sshp <host>`. An optional second argument selects another safe session name:

```bash
sshpersist server.example.com
sshp server.example.com maintenance
```

`autossh -M 0` relies on SSH keepalives instead of a legacy monitor port. If a
plain SSH connection is already open, reattach its session with
`tmux attach -t <host>`; punctuation in the automatic host-derived session name
is replaced with underscores (for example, `server.example.com` becomes
`server_example_com`). The remote host also needs `tmux` installed.

The generated app-theme packages are optional. Deploy them without directory
folding so application-created files stay outside the Git checkout:

```bash
stow --no-folding neovim btop obsidian
```

Their package-level `.gitignore` files keep accidental app state untracked, but
do not prevent Stow from folding a missing target directory into one symlink.
Without `--no-folding`, a later `git clean -xfd` could therefore delete app
state written through that symlink.

## ASCII Screensaver

The `screensaver` package runs an original `ttfx` ASCII logo on each active
Hyprland monitor. Hypridle starts it after three idle minutes when no audio is
playing, then locks at 300 seconds.

```bash
ascii-screensaver force                 # manual fullscreen launch
ascii-screensaver --dry-run             # print planned monitor spawns
toggle-screensaver                      # enable/disable automatic launch
screensaver-branding text               # edit and preview the logo
screensaver-branding image logo.png     # convert and preview an image
```

See [the complete screensaver guide](docs/screensaver.md) for terminal support,
logo conversion, idle behavior, and recovery.

## Desktop Modes

The independent `modes` package unifies night light, Quickshell DND,
stay-awake, and automatic-screensaver state without owning lock, suspend, DPMS,
or authentication policy.

```bash
desktop-mode status
desktop-mode enable stay-awake --for 30m
desktop-mode toggle do-not-disturb
desktop-mode action screensaver
desktop-mode doctor --json
```

Open the Quickshell panel with `SUPER+ALT+M`. See the
[desktop modes guide](docs/desktop-modes.md) for boundaries, timers, recovery,
and all commands.

## Network speed test

`network-speedtest` resolves the active interface through `ip route`, runs eight
parallel fast.com transfers for five seconds in each direction, and calculates
Mbps from the interface's kernel byte counters. It prints the interface,
download speed, and upload speed to stdout. The Quickshell entry points stream
each one-second sample into a full-screen, themed gauge overlay.

`SUPER+ALT+T`, the Quickbar network panel, and lmenu run the overlay.
`SUPER+SHIFT+T` remains assigned to OCR. The tool is part of the `hypr` Stow
package. Press Escape to close the overlay; use Run again after a test finishes.

Install its Arch dependencies with:

```bash
paru -S --needed curl jq gawk iproute2
```

`gawk` provides `awk`.

The fast.com token is public and hardcoded. Netflix can rotate or restrict it,
which may make the API return HTTP 403. That is a known fragility of the
unofficial API, not a script failure.

## YubiKey authentication

The optional `security` package provides a guarded setup command for the
YubiKey Bio, sudo, and Hyprlock. It never stores the registered credential in
Git and keeps password authentication as the final fallback.

```bash
yubikey-auth status
yubikey-auth setup --enroll-fingerprint  # first key and PAM deployment
yubikey-auth add --enroll-fingerprint    # additional YubiKey Bio
yubikey-auth add --dry-run               # inspect without changing anything
```

After opening a new Zsh session, the conflict-safe shortcuts are `yubi`,
`yubi-status`, `yubi-setup`, and `yubi-add`. The last two include Bio
fingerprint enrollment automatically.

The command validates mappings, creates timestamped `/etc` backups, installs
sudo first, and waits for explicit confirmation after key/password testing
before installing Hyprlock PAM. See [installation and recovery](docs/installation.md#yubikey-authentication).

**Wallpapers** (optional — see the layout note in
[installation](docs/installation.md#optional-packages) before deploying):

```bash
stow --target="$HOME/Pictures/Wallpapers" wallpaper
```

**Remove a package:**

```bash
stow -D hypr
```

**Preview without making changes:**

```bash
stow --simulate hypr
```

---

## AI Agent Launcher

The standalone `ai` package provides one launcher for Claude Code, Codex,
OpenCode, and T3 Code. It does not install or authenticate any agent and has no Omarchy
dependency.

The default is configured in `ai/.config/ai-agent/config`:

```text
default_agent=t3code
```

Selection priority is `--agent`, then `AI_AGENT_DEFAULT`, then the config file.
Invalid names and unavailable executables fail clearly; the launcher never
silently switches to another agent.

After stowing both `ai` and `zsh`, these commands are available in a new shell:

```bash
ai                         # configured default
ai-claude                  # Claude Code directly
ai-codex                   # Codex directly
ai-opencode                # OpenCode directly
ai-t3code                  # T3 Code directly
ai-agent --agent claude    # one-invocation override
ai-agent --agent codex -- --help  # pass --help to the selected agent
```

The aliases are only defined when their names are otherwise unused. The
launcher preserves the current working directory and passes agent arguments
through unchanged.

`SUPER + I` opens the configured default. T3 Code is assigned to workspace 4
by its `t3code` window class. Change or remove that binding in
`hypr/.config/hypr/conf/keybindings.lua` to alter or disable it. It is not active
until the relevant packages are stowed and Hyprland is reloaded by the user.

---

## Windows VM

The optional `windows` package provides a Dockur Windows 11 VM managed through
one command:

```bash
windows-vm install
windows-vm launch
windows-vm launch --keep-alive
windows-vm status
windows-vm stop
windows-vm logs
windows-vm remove
```

`SUPER+ALT+W` starts or connects to it, and `SUPER+CTRL+ALT+W` stops it
gracefully. RDP and the installation web UI bind to localhost only; `~/Windows`
is the sole shared host directory. Persistent VM data lives in `~/.windows`,
while credentials and resource settings remain host-local under
`~/.config/windows` rather than in this repository. Successful container starts
and stops send desktop notifications; readiness, installation, and error states
continue to use the same notification path. Since RDP is loopback-only, FreeRDP
uses non-interactive certificate handling so a regenerated VM certificate cannot
leave a hidden modal dimming and blocking another window.

New Windows installations also use Dockur's OEM hook to ensure WinGet, then
install Sysinternals, Everything, Helium, and PuTTY. Its transcript is saved at
`C:\OEM\post-install.log` inside the VM.

---

## Theme System

This repo includes a **semantic, switchable theme system** with **23 themes**.

| Open with | What you get |
|---|---|
| **`SUPER + CTRL + SHIFT + SPACE`** | Fullscreen cover-flow picker — one large preview, skewed slices either side |
| **`SUPER + CTRL + D`** → THEME | The Display panel's launcher row, opens the same visual picker |
| `theme set <slug>` | The CLI, and what everything above ends up calling |

### How It Works

1. **`hypr/.config/hypr/themes/<slug>/colors.toml`** — One palette per theme. This is the single source of truth: semantic colour roles (`background`, `surface`, `accent`, `red`, …), a complete 16-colour ANSI terminal palette, and optional `[style]` overrides (rounding, border width, opacity, blur).
2. **`hypr/.config/hypr/theme/generate.py`** (+ `themelib.py`) — Validates the palette (including WCAG AA contrast checks), renders every application's config from `hypr/.config/hypr/theme/templates/*`, and installs it atomically. A broken theme leaves the previous one running.
3. **`quickshell/.config/quickshell/ThemePicker.qml`** — the fullscreen cover-flow
   picker, reached from `Super+Ctrl+Shift+Space` or the Display panel's THEME
   row. Every entry point is only a front-end: they both hand a slug
   to `theme set`, which stays the single source of truth for what is active.

### `theme` CLI

```bash
theme list              # list themes (active marked *)
theme index             # themes + wallpapers, human readable
theme index --json      # same as JSON; this is what the visual picker reads
theme validate --all    # check every palette
theme current           # print the active slug
theme mode              # print dark|light
theme set <slug>        # apply a theme
theme next              # cycle to the next theme
theme previous          # cycle to the previous theme
```

### Available Themes

**23 themes** — the 18 designed for this system, plus 5 carried over from
the previous `themes.json` so nothing that was in use was lost.

| Slug | Theme | Mode |
|---|---|---|
| `tokyo-night` | Tokyo Night | dark |
| `catppuccin` | Catppuccin Mocha | dark |
| `lumon` | Lumon | dark |
| `ethereal` | Ethereal | dark |
| `everforest` | Everforest | dark |
| `gruvbox` | Gruvbox | dark |
| `miasma` | Miasma | dark |
| `hackerman` | Hackerman | dark |
| `osaka-jade` | Osaka Jade | dark |
| `kanagawa` | Kanagawa | dark |
| `nord` | Nord | dark |
| `matte-black` | Matte Black | dark |
| `vantablack` | Vantablack | dark |
| `ristretto` | Ristretto | dark |
| `retro-82` | Retro 82 | dark |
| `flexoki-light` | Flexoki Light | light |
| `rose-pine` | Rosé Pine | dark |
| `catppuccin-latte` | Catppuccin Latte | light |

Carried over from the previous theme set:

| Slug | Theme | Mode |
|---|---|---|
| `windows-7` | Windows 7 Aero | dark |
| `cyberpunk-neon` | Cyberpunk Neon | dark |
| `monochrome-minimal` | Monochrome Minimal | dark |
| `solarized-dark` | Solarized Dark | dark |
| `warm-pastel` | Warm Pastel | dark |

### Visual Theme Picker

`SUPER + CTRL + SHIFT + SPACE` opens a fullscreen Quickshell overlay showing a
preview tile per theme. It runs inside the already-running shell process (over
`quickshell ipc call theme toggle`), so there is nothing to start.

```
type            filter by name
← →             previous / next theme
↑ ↓             move a row
Home / End      first / last result
Enter / click   apply the focused theme
Escape          clear the search, or close if it is already empty
```

Two things worth knowing:

- **Moving the selection never applies anything.** Only Enter or a click runs the
  backend, so you can browse the whole gallery for free.
- **The picker wears the theme you are currently using**, not the one under the
  cursor. Each tile paints itself from its own palette; the chrome around them
  follows the active theme.

Each tile is drawn in QML from the theme's palette — a simulated bar, a simulated
terminal showing the semantic colours, and the theme's wallpaper behind it if one
exists. No thumbnails are generated or cached, and no processes are spawned per
tile. A theme with no wallpaper (12 of the 23) falls back to a palette gradient;
drop an image at `wallpaper/theme/<name>.jpg` and it starts being used with no
config change.

### What Changes Per Theme

Each theme consistently updates:

- **Hyprland** — active/inactive border colours, rounding, gaps, opacity, shadow, blur
- **Quickshell** — shell palette via generated `themes/.active/theme.json`
- **Kitty** — 16-colour ANSI palette, foreground/background, selection, cursor
- **Rofi** — launcher colours via generated `current.rasi`
- **Zsh / Powerlevel10k** — prompt colours via generated `current-theme.zsh`
- **Hyprlock** — lock screen colours
- **Quickshell notifications** — cards, gradients, borders, countdown and radius
- **SwayNC** — rollback notification CSS (not the active backend)
- **Wofi** — launcher CSS
- **Noctalia** — shell colour scheme
- **Fastfetch** — section key colours
- **Neovim** — generated colorscheme, with a stable `current` alias
- **btop** — generated theme, with a stable `current` alias
- **Obsidian** — generated CSS snippet source for manually linked vault snippets
- **Wallpaper** — set via `hyprpaper` over `hyprctl` for the 10 themes that have
  an asset; the other 13 leave your current wallpaper alone rather than clearing it.
  `theme index` prints which is which

### Dependencies

The theme system requires:

- `python3` (3.11+, for `tomllib`)
- `rofi` — theme selection menu

Optional (for live reload or rollback):

- `hyprctl` — reloads Hyprland decorations
- `kitty` — live-applies colours to running terminals
- `swaync` / `swaync-client` — only needed when using the rollback backend

### Switching Manually

```bash
# Apply a specific theme
theme set tokyo-night

# Check the current theme
theme current
```

### First Run / Bootstrap

Generated config files (decorations, colours, themes) are gitignored. After `stow`, generate them once:

```bash
theme set <slug>
```

### Adding a New Theme

1. Create `hypr/.config/hypr/themes/<slug>/colors.toml` (copy `tokyo-night/colors.toml` for the format and required keys).
2. Run `theme set <slug>`.

Most applications consume generated output directly. Set btop's `color_theme`
to `"current"` once, and symlink then enable the generated Obsidian CSS snippet
in each vault as described in [Themes and appearance](docs/themes.md).

### Validation

```bash
theme validate --all      # every palette: required roles, 16 ANSI colours, contrast
theme validate <slug>     # just one
```

---

## Notifications

Notifications are served and rendered natively by the persistent Quickshell
process. Applications talk to `org.freedesktop.Notifications`; one service then
normalises the event, persists it, applies DND, and either places it in the
focused monitor's top-right stack or writes it silently to history.

```text
application -> Quickshell NotificationServer -> NotificationService
                                                |-> active/history state
                                                |-> per-output card stack
                                                `-> notifications IPC
```

The full-screen layer-shell surfaces use the overlay layer, request no keyboard
focus or exclusion zone, and have an input mask made only from the card stack.
Transparent space is therefore click-through. The active Quickshell bar is the
authoritative bar, so top notifications clear `Theme.barHeight` plus the normal
outer gap. Notifications without output metadata go to Hyprland's focused
monitor; a disconnected output is deterministically remapped to the current
focused monitor.

### Controls

| Binding | Action |
|---|---|
| `Super+,` | dismiss newest visible card |
| `Super+Shift+,` | dismiss all visible cards |
| `Super+Ctrl+,` | toggle persistent DND |
| `Super+Alt+,` | invoke/focus newest card |
| `Super+Shift+Alt+,` | replay the newest 10 history entries |

The bindings call `notificationctl`; they contain no notification logic.

```bash
notificationctl dismiss-one
notificationctl dismiss-all
notificationctl dnd-toggle
notificationctl dnd-on
notificationctl dnd-off
notificationctl invoke-latest
notificationctl history
notificationctl status
notificationctl status --json
```

Left click invokes the live default action, then falls back to matching
`desktop-entry`, app name, and icon against Hyprland window classes. Right click
or the hover close button dismisses. Hover pauses the deadline. Critical cards
remain until acted on; low and normal cards last at least 5 and 8 seconds, with
ordinary requests clamped to 30 seconds.

### State and configuration

User settings live in
`~/.config/quickshell/notifications/config.json`: position, history limit,
timeouts, 380 px card width, animation timing, border widths, debug logging and
the audited DND bypass allow-list. A bypass requires both an allow-listed app
name and an explicit local bypass hint; urgency alone never bypasses DND.

Runtime state is private and atomic under:

```text
~/.local/state/hyprland-desktop/notifications/
├── state.json       # persistent DND
├── active/          # cards restored after a shell restart
├── history/         # newest 10 by default
└── images/          # bounded copies owned by retained records
```

The card component is shared by live and replayed history. Native actions exist
only while the originating notification object is live; restored/history cards
correctly use app-focus fallback instead of claiming an expired action works.
Malformed JSON is skipped, filenames are validated, notification text is never
sent through a shell, writes use fsync plus rename, and orphan images are swept.

Theme roles are generated for every palette as `notifications.background`,
`text`, `bodyText`, `border1`, `border2`, `countdown`, and `close`. QML contains
no notification palette; corner radius follows the generated Hyprland rounding.
Per-side borders are configured as `[top, right, bottom, left]`, for example
`[2, 2, 2, 6]`.

### Debugging and validation

```bash
# Reload the already-running shell after changing QML
quickshell ipc call notifications statusJson
quickshell kill && quickshell --daemonize

# Observe concise service logs
quickshell log

# Send manual cases
notify-send "Test notification" "This is the body."
notify-send -u low "Low urgency" "At least five seconds"
notify-send -u critical "Critical" "Dismiss explicitly"

# Headless QML and unit checks from the repository root
QT_QPA_PLATFORM=offscreen quickshell -p quickshell/.config/quickshell/NotificationSmoke.qml
python3 -m unittest discover -s quickshell/.config/quickshell/notifications/tests -p 'test_*.py'
node quickshell/.config/quickshell/notifications/tests/notification_logic.test.js
theme validate --all
```

For rollback, stop Quickshell, start `swaync.service`, and restore the two former
comma bindings to `~/.config/hypr/scripts/dnd.sh`. The SwayNC package and theme
template remain in the repository; no notification data is shared between the
two backends.

---

## Web Apps

Turn a website into a first-class launcher. `SUPER + SHIFT + A` opens the manager
(also reachable from the **WEB APPS** tile on the dashboard, `SUPER + CTRL + A`).

```
Install > Name + URL > icon found automatically > Install
        > managed .desktop > Rofi / app menu > brave --app= > normal window
```

Each installed app owns exactly three files, and the manager will only ever
touch these:

| | |
|---|---|
| metadata | `~/.local/share/webapps/apps/<id>.toml` |
| icon | `~/.local/share/webapps/icons/<id>.png` |
| launcher | `~/.local/share/applications/webapp-<id>.desktop` |

The metadata file is the ownership marker: an app is removable by this tool only
if it is listed there, so an unrelated `.desktop` file can never be deleted.

### CLI

```bash
webapp list                 # installed web apps
webapp install --name "YouTube" --url https://youtube.com/
webapp install --name "Local" --url localhost:8080/app --icon ~/pic.png
webapp remove youtube
webapp doctor               # browser, tooling and orphan check
webapp launch youtube       # what the .desktop file runs
```

Notes worth knowing:

- **Browser**: the launch helper uses `$WEBAPP_BROWSER` if set, else the first of
  `brave`, `chromium`, `chromium-browser`, `google-chrome`,
  `google-chrome-stable`, `helium-browser` on `PATH`. Web apps share the normal
  browser profile, so existing logins just work.
- **Window class**: Brave ignores `--class` for app-mode windows and derives its
  own, e.g. `brave-youtube.com__-Default`. That is recorded as `wm_class` in the
  metadata and is what a per-app Hyprland rule has to match. Usefully it is never
  plain `brave-browser`, so the `workspace 2 silent` rule in
  `window_rules.lua` does not capture web apps.
- **Icons** are normalised to PNG, because gdk-pixbuf here has no SVG or WebP
  loader and Rofi could not otherwise render them. Discovery prefers a declared
  `apple-touch-icon` or sized raster over an SVG favicon; if nothing is found, a
  letter tile is generated in the active theme's accent colour.
- Only `http` and `https` are accepted. `file:`, `data:` and `javascript:` are
  rejected. URLs are never passed through a shell and never appear in an `Exec`
  line -- the launcher receives only the app id.

## Chromium Desktop Tools

The `browser` package installs two unpacked Manifest V3 extensions and their
native messaging hosts for Chromium, Chrome, Brave (including Origin), and
Microsoft Edge profiles:

| Shortcut | Toolbar action | Result |
|---|---|---|
| `Alt + Shift + L` | Copy URL | Copies the active tab URL with `wl-copy`; the existing `cliphist` watcher records it |
| `Alt + Shift + D` | Download Video | Sends the active page URL to `yt-dlp`, saves one video in `~/Videos`, and shows progress in the Quickshell OSD |

The browser owns both shortcuts; they are not Hyprland bindings. Browser flag
files load the extensions from `~/.local/share/chromium-tools/extensions/`, and
each browser profile authorizes only the extensions' pinned IDs to launch the
matching executable in `~/.local/bin/`.

Download Video accepts only HTTP(S) pages, disables playlists, and leaves format
selection to yt-dlp. Set `CHROMIUM_YTDLP_DIR` in the browser's environment to
override `~/Videos`. After a successful download, click the ten-second
notification to open the validated file in mpv. An unsupported page or failed
download produces a critical desktop notification containing yt-dlp's error.
Concurrent duplicate requests are ignored. Native-host connection or
request errors produce a Brave notification and leave a red `!` badge on the
Download Video extension, so the shortcut no longer fails silently.

After first installation, completely close and reopen the browser. Inspect or
change the browser-owned shortcuts at `brave://extensions/shortcuts` (or the
equivalent `chrome://extensions/shortcuts`). A shortcut already assigned to
another extension must be cleared there before it can be assigned to these
tools.

If an older unpacked Download Video extension still owns `Alt + Shift + D`,
preview the narrowly scoped profile repair while Brave is open:

```bash
chromium-repair-download-video-shortcut ~/.config/BraveSoftware/Brave-Browser
```

Then completely quit Brave and rerun it with `--apply`. The repair refuses to
write while Brave's singleton socket is active, creates a timestamped
`Preferences` backup, and removes only obsolete Download Video registrations.
The current pinned extension claims the shortcut on the next browser launch.

Validation from the repository root:

```bash
tests/browser-native-tools.test.sh
stow --simulate browser quickshell
```

The fixture suite uses mocked clipboard, downloader, notification, player, and
OSD commands; it never downloads media or changes the live clipboard.

## What's Included

| Package | Tool | Description |
|---|---|---|
| `hypr` | [Hyprland](https://hyprland.org/) | Wayland compositor — keybinds, decorations, autostart, monitor profiles, theme system |
| `browser` | Chromium tools | Copy URL and yt-dlp extensions with native desktop integration |
| `hyprlock` | [Hyprlock](https://github.com/hyprwm/hyprlock) | Lock screen with music widget, weather, and multiple layouts |
| `kitty` | [Kitty](https://sw.kovidgoyal.net/kitty/) | Terminal emulator with generated theme palette |
| `rofi` | [Rofi](https://github.com/davatorium/rofi) | App launcher with generated colour theme on comet-glass layout |
| `wofi` | [Wofi](https://hg.sr.ht/~scoopta/wofi) | Wayland-native app launcher with themed colors |
| `swaync` | [SwayNC](https://github.com/ErikReider/SwayNotificationCenter) | Optional rollback notification backend |
| `fastfetch` | [Fastfetch](https://github.com/fastfetch-cli/fastfetch) | System info with themed key colors |
| `noctalia` | Noctalia | Custom plugin system with themed color scheme |
| `zsh` | Zsh | Shell config — `.zshrc` and `.p10k.zsh`; Oh My Zsh itself is installed separately |
| `ssh` | autossh | Reconnecting SSH launcher and opt-in client keepalive fragment |
| `tmux` | tmux | Persistent remote-session defaults |

---

## Dependencies

**Core:**
- `hyprland`, `hyprlock`, `hypridle`
- `kitty`
- `rofi`, `wofi`
- `quickshell`
- `swaync` (optional rollback backend)
- `fastfetch`

**Shell:**
- `zsh`, `oh-my-zsh`
- `zsh-autosuggestions`, `zsh-syntax-highlighting`
- `fzf`, `fzf-tab`
- `eza` (ls replacement)
- `powerlevel10k`
- `autossh`, `tmux` (persistent SSH sessions)

Oh My Zsh and the two pieces `.zshrc` loads out of `$ZSH_CUSTOM` are **not
vendored in this repo** — Oh My Zsh's own `.gitignore` excludes `custom/`, so
nothing tracked here could ever carry them. Install them once:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
  ~/.oh-my-zsh/custom/themes/powerlevel10k
git clone --depth=1 https://github.com/Aloxaf/fzf-tab.git \
  ~/.oh-my-zsh/custom/plugins/fzf-tab
```

**Theme system:**
- `python3` (3.11+, for `tomllib`)
- `rofi`

**Utilities used in scripts:**
- `playerctl` — media control
- `mpv` — video wallpapers
- `doas` — privilege escalation (used in place of sudo)
- `grim`, `slurp` — screenshots
- `cliphist` / `wl-clipboard` — clipboard
- `yt-dlp`, `jq`, `ffmpeg`, `mpv`, `libnotify` — Chromium video download integration

Install AUR packages with your preferred helper (e.g. `paru` or `yay`).

---

## Wallpaper Licensing

Wallpapers in `wallpaper/theme/` are sourced from [Unsplash](https://unsplash.com/license) — free for commercial and non-commercial use (Unsplash License). Each is a unique image selected to match its theme's color palette.

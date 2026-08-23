# dotfiles

Personal Hyprland dotfiles for Arch Linux, managed with [GNU Stow](https://www.gnu.org/software/stow/).

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

Each top-level directory is a Stow package. Run `stow <package>` to symlink its contents into `~`.

**Deploy everything at once:**

```bash
stow fastfetch hypr hyprlock kitty noctalia rofi swaync Wallpapers wofi zsh
```

**Or deploy packages individually:**

```bash
stow hypr        # ~/.config/hypr
stow hyprlock    # ~/.config/hyprlock
stow kitty       # ~/.config/kitty
stow rofi        # ~/.config/rofi
stow wofi        # ~/.config/wofi
stow swaync      # ~/.config/swaync
stow fastfetch   # ~/.config/fastfetch
stow noctalia    # ~/.config/noctalia
stow zsh         # ~/.zshrc, ~/.p10k.zsh, ~/.oh-my-zsh
```

**Wallpapers** (optional — symlinks `~/Wallpapers`):

```bash
stow Wallpapers
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

## Theme System

This repo includes a **semantic, switchable theme system** with **18 themes**. Press **`SUPER + T`** for the Rofi selector, or use the `theme` CLI.

### How It Works

1. **`hypr/.config/hypr/themes/<slug>/colors.toml`** — One palette per theme. This is the single source of truth: semantic colour roles (`background`, `surface`, `accent`, `red`, …), a complete 16-colour ANSI terminal palette, and optional `[style]` overrides (rounding, border width, opacity, blur).
2. **`hypr/.config/hypr/theme/generate.py`** (+ `themelib.py`) — Validates the palette (including WCAG AA contrast checks), renders every application's config from `hypr/.config/hypr/theme/templates/*`, and installs it atomically. A broken theme leaves the previous one running.
3. **`hypr/.config/hypr/scripts/theme-switcher.sh`** — Rofi menu (Super+T) that lists themes and applies the selection.

### `theme` CLI

```bash
theme list              # list themes (active marked *)
theme current           # print the active slug
theme mode              # print dark|light
theme set <slug>        # apply a theme
theme next              # cycle to the next theme
theme previous          # cycle to the previous theme
```

### Available Themes

| Slug | Theme | Mode |
|---|---|---|
| tokyo-night | Tokyo Night | dark |
| catppuccin | Catppuccin Mocha | dark |
| lumon | Lumon | dark |
| ethereal | Ethereal | dark |
| everforest | Everforest | dark |
| gruvbox | Gruvbox Dark | dark |
| miasma | Miasma | dark |
| hackerman | Hackerman | dark |
| osaka-jade | Osaka Jade | dark |
| kanagawa | Kanagawa Wave | dark |
| nord | Nord | dark |
| matte-black | Matte Black | dark |
| vantablack | Vantablack | dark |
| ristretto | Ristretto | dark |
| retro-82 | Retro 82 | dark |
| flexoki-light | Flexoki Light | light |
| rose-pine | Rosé Pine | dark |
| catppuccin-latte | Catppuccin Latte | light |

### What Changes Per Theme

Each theme consistently updates:

- **Hyprland** — active/inactive border colours, rounding, gaps, opacity, shadow, blur
- **Waybar** — bar/module colours via generated `colors.css`
- **Quickshell** — shell palette via generated `themes/.active/theme.json`
- **Kitty** — 16-colour ANSI palette, foreground/background, selection, cursor
- **Rofi** — launcher colours via generated `current.rasi`
- **Zsh / Powerlevel10k** — prompt colours via generated `current-theme.zsh`
- **Hyprlock** — lock screen colours
- **SwayNC** — notification CSS
- **Wofi** — launcher CSS
- **Noctalia** — shell colour scheme
- **Fastfetch** — section key colours
- **Wallpaper** — theme-specific wallpaper (where configured)

### Dependencies

The theme system requires:

- `python3` (3.11+, for `tomllib`)
- `rofi` — theme selection menu

Optional (for live reload):

- `hyprctl` — reloads Hyprland decorations
- `kitty` — live-applies colours to running terminals
- `swaync` / `swaync-client` — reloads notification CSS

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

No per-application config changes are needed — every app is generated from the palette.

### Validation

```bash
python3 hypr/.config/hypr/theme/generate.py validate --all
```

---

## What's Included

| Package | Tool | Description |
|---|---|---|
| `hypr` | [Hyprland](https://hyprland.org/) | Wayland compositor — keybinds, decorations, autostart, monitor profiles, theme system |
| `hyprlock` | [Hyprlock](https://github.com/hyprwm/hyprlock) | Lock screen with music widget, weather, and multiple layouts |
| `kitty` | [Kitty](https://sw.kovidgoyal.net/kitty/) | Terminal emulator with generated theme palette |
| `rofi` | [Rofi](https://github.com/davatorium/rofi) | App launcher with generated colour theme on comet-glass layout |
| `wofi` | [Wofi](https://hg.sr.ht/~scoopta/wofi) | Wayland-native app launcher with themed colors |
| `swaync` | [SwayNC](https://github.com/ErikReider/SwayNotificationCenter) | Notification center with generated stylesheet |
| `fastfetch` | [Fastfetch](https://github.com/fastfetch-cli/fastfetch) | System info with themed key colors |
| `noctalia` | Noctalia | Custom plugin system with themed color scheme |
| `zsh` | Zsh | Shell config — Oh My Zsh, Powerlevel10k, fzf-tab, eza aliases |

---

## Dependencies

**Core:**
- `hyprland`, `hyprlock`, `hypridle`
- `kitty`
- `rofi`, `wofi`
- `swaync`
- `fastfetch`

**Shell:**
- `zsh`, `oh-my-zsh`
- `zsh-autosuggestions`, `zsh-syntax-highlighting`
- `fzf`, `fzf-tab`
- `eza` (ls replacement)
- `powerlevel10k`

**Theme system:**
- `python3` (3.11+, for `tomllib`)
- `rofi`

**Utilities used in scripts:**
- `playerctl` — media control
- `mpv` — video wallpapers
- `doas` — privilege escalation (used in place of sudo)
- `grim`, `slurp` — screenshots
- `cliphist` / `wl-clipboard` — clipboard

Install AUR packages with your preferred helper (e.g. `paru` or `yay`).

---

## Wallpaper Licensing

Wallpapers in `Wallpapers/theme/` are sourced from [Unsplash](https://unsplash.com/license) — free for commercial and non-commercial use (Unsplash License). Each is a unique image selected to match its theme's color palette.

Wallpapers in `Wallpapers/static/` and `Wallpapers/dynamic/` are sourced from various free wallpaper communities. If you are the copyright holder of any image and would like it removed, please open an issue.

# Theming

One TOML file per theme drives the entire desktop: compositor decorations,
shell, terminal, launcher, lock screen, notifications, prompt, and login screen.
There are 23 of them.

## Source of truth

```text
hypr/.config/hypr/themes/<slug>/colors.toml
```

Four sections:

**`[theme]`** — `name`, `slug`, `mode` (`dark` or `light`), `description`,
`family`, and an optional `wallpaper` name.

**`[colors]`** — semantic roles, not raw hexes scattered across configs:
`background`, `background_alt`, `surface`, `surface_alt`, `overlay`,
`foreground`, `foreground_bright`, `muted`, `disabled`, `accent`, `accent_alt`,
`red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `selection`, `border`,
`border_active`, `urgent`, `shadow`.

**`[ansi]`** — the full 16-colour terminal palette, normal and bright.

**`[style]`** — `rounding`, `border_width`, `surface_opacity`, `scrim_opacity`,
`shadow_opacity`, `blur`, `blur_size`, `blur_passes`.

## The generator

`hypr/.config/hypr/theme/generate.py`, with `themelib.py` alongside it. It
validates the palette — required roles present, all 16 ANSI colours defined, and
WCAG AA contrast checks — then renders every template into a staging directory.
Nothing moves into place until all of it passes, so **a broken theme leaves the
previous one running**.

Fifteen templates live in `hypr/.config/hypr/theme/templates/`:

| Template | Renders to |
| --- | --- |
| `hyprland-decorations.lua` | `hypr/.config/hypr/conf/decorations.lua` |
| `quickshell-theme.json` | `hypr/.config/hypr/themes/.active/theme.json` |
| `kitty-theme.conf` | `kitty/.config/kitty/theme/current-theme.conf` |
| `rofi-theme.rasi` | `rofi/.config/rofi/` palette and import files |
| `rofi-powermenu-theme.rasi` | `rofi/.config/rofi/powermenu/theme.rasi` |
| `hyprlock-colors.conf` | `hyprlock/.config/hyprlock/colors.conf` |
| `zsh-theme.zsh` | `~/.config/zsh/current-theme.zsh` |
| `swaync-style.css` | `swaync/.config/swaync/style.css` |
| `wofi-style.css` | `wofi/.config/wofi/style.css` |
| `noctalia-colors.json` | `noctalia/.config/noctalia/colors.json` and scheme data |
| `greeter-theme.css` | `greeter/.config/greeter/greeter.css` |
| `regreet-greeter.toml` | `greeter/.config/greeter/regreet.toml` |
| `neovim-theme.lua` | `neovim/.config/nvim/colors/<slug>.lua` and `current.lua` |
| `btop-theme.tpl` | `btop/.config/btop/themes/<slug>.theme` and `current.theme` |
| `obsidian-theme.css` | `obsidian/.config/obsidian/snippets/generated-theme.css` (link into each vault) |

Fastfetch's `keyColor` is also updated. Every one of these destinations is in
`.gitignore` — edit the palette or the template, never the output.

The Zsh target is the odd one: it is written directly into `~/.config/zsh/`
rather than through a tracked Stow path, and `.zshrc` sources it.

The optional Neovim and btop aliases let configuration use `current` once;
theme switches repoint the aliases and prune older generated slug files.
Obsidian requires a manual symlink from each vault's
`.obsidian/snippets/generated-theme.css` to the generated file, followed by
enabling the snippet in that vault's Appearance settings.

Deploy these optional packages with `stow --no-folding neovim btop obsidian`.
This keeps application-created state outside the checkout; a package-level
`.gitignore` does not by itself stop Stow from folding a missing target tree.

With `theme set <slug> --prefix <dir>`, optional-target deployment is detected
from the live XDG config tree (`$XDG_CONFIG_HOME`, or `~/.config`). Selected
outputs are still rendered only beneath `<dir>`, so the preview reports what a
live switch would target without writing those generated files to the live tree.

## The `theme` CLI

```bash
theme list                 # slugs, active one marked
theme index                # themes plus wallpapers, human readable
theme index --json         # the same data the visual picker reads
theme current              # active slug
theme mode                 # dark | light
theme validate <slug>      # one palette
theme validate --all       # every palette
theme set <slug>           # apply
theme next                 # cycle forward
theme previous             # cycle back
```

`theme` is a thin wrapper that resolves `~/.config/hypr/theme/generate.py`, and
falls back to the repo-relative path so it works before the first `stow`.

Useful flags on `set` and the cycle commands:

| Flag | Effect |
| --- | --- |
| `--wallpaper` | also apply the theme's wallpaper; **the default preserves yours** |
| `--no-reload` | render and install without touching running applications |
| `--prefix DIR` | render into `DIR` instead of `~/.config`; implies no state write and no reload |
| `--install-greeter` | also copy the rendered regreet files into `/etc/greetd/` via `sudo` |
| `--dry-run` | with `--install-greeter`, print the `sudo install` commands instead of running them |

`--prefix` is the safe way to inspect what a palette edit produces without
touching the live desktop.

## What happens when you apply a theme

`theme set` is not a pure renderer. On success it can:

- reload Hyprland so the new decoration values take effect;
- notify the Quickshell theme watcher, which repaints live;
- push colours into running Kitty windows over remote control;
- signal SwayNC if it happens to be running;
- leave generated output in place for anything that loads it later.

It does **not** change your wallpaper unless you pass `--wallpaper`.

`--install-greeter` is the only path that needs root, which is why it is opt-in
and never fires from the picker or a keybinding. See
[Security and login](Security-and-Login.md#the-login-screen).

## Choosing a theme

| Entry point | How |
| --- | --- |
| `SUPER+CTRL+SHIFT+SPACE` | fullscreen Quickshell cover-flow picker |
| `SUPER+CTRL+D` → THEME | the Display panel's launcher row, same picker |
| `theme set <slug>` | the CLI, and what both of the above call |

The picker runs inside the already-running shell over
`quickshell ipc call theme toggle`, so there is nothing to start.

```text
type            filter by name
← →             previous / next
↑ ↓             move a row
Home / End      first / last result
Enter / click   apply the focused theme
Escape          clear the search, or close if it is already empty
```

Two behaviours worth knowing:

- **Moving the selection applies nothing.** Only Enter or a click runs the
  backend, so browsing the gallery is free.
- **The picker wears your current theme**, not the one under the cursor. Each
  tile paints itself from its own palette; the chrome around them follows the
  active one.

Each tile is drawn in QML from the palette — a simulated bar, a simulated
terminal showing the semantic colours, and the theme's wallpaper behind it if one
exists. No thumbnails are generated or cached, and no process is spawned per
tile.

## Wallpapers

Ten of the 23 themes have a wallpaper asset. The other 13 leave your current
wallpaper alone rather than clearing it. `theme index` prints which is which.

Theme wallpapers resolve from user wallpaper locations before static repository
assets. Dropping an image at `wallpaper/theme/<name>.jpg` starts it being used
with no config change.

This is a separate path from the interactive Wallhaven picker on `SUPER+SHIFT+W`;
see [Scripts and CLIs](Scripts-and-CLIs.md#wallpaper).

## The 23 palettes

Eighteen were designed for this system:

| Slug | Name | Mode |
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
| `rose-pine` | Rosé Pine | dark |
| `flexoki-light` | Flexoki Light | light |
| `catppuccin-latte` | Catppuccin Latte | light |

Five were carried over from the previous `themes.json` so nothing in use was
lost: `windows-7`, `cyberpunk-neon`, `monochrome-minimal`, `solarized-dark`,
`warm-pastel`. All five declare dark mode.

## Adding a theme

1. Copy an existing directory under `hypr/.config/hypr/themes/`. `tokyo-night`
   is the reference for format and required keys.
2. Rename it and edit `colors.toml`. Keep every key the validator requires.
3. `theme validate <slug>`.
4. `theme set <slug>`, then look at the result — especially contrast in
   notifications, Rofi, Hyprlock, and the terminal ANSI colours.
5. Commit the palette. Do not commit generated output.

No per-application config changes are needed. Every app renders from the palette.

## Fonts, icons, cursors

| Asset | Used by |
| --- | --- |
| JetBrainsMono Nerd Font | Kitty, bar and panel glyphs, Rofi, lock screen |
| Noto Sans | Quickshell UI fallback, active Hyprlock clock and date |
| AlfaSlabOne, JetBrains Mono ExtraBold | referenced by the active Hyprlock layout |
| Papirus | Rofi icons |
| Powerlevel10k-compatible glyph font | Zsh prompt |

Hyprland sets XCursor and Hyprcursor size to 24, but no cursor *theme* is
tracked. GTK, Qt, and Kvantum theming for the interactive desktop are not managed
by this repository either.

The one exception is regreet: `regreet-greeter.toml` pins a fixed GTK theme, icon
theme, cursor name (`Adwaita`), and font, because regreet needs concrete values
and none of those are tracked per palette. Only
`application_prefer_dark_theme` follows the active theme's `mode`.

Empty squares in the bar almost always mean a Nerd Font mismatch, not a QML bug.

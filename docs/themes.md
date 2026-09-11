# Themes and appearance

## Source of truth

Each palette lives at:

```text
hypr/.config/hypr/themes/<name>/colors.toml
```

The TOML file contains semantic desktop colors, ANSI terminal colors, and style
values. `hypr/.config/hypr/theme/generate.py` is the renderer. Generated files
are listed in `.gitignore`; edit the palette or generator rather than the outputs.

## Included palettes

There are 23 tracked palettes:

```text
catppuccin          catppuccin-latte  cyberpunk-neon
ethereal            everforest        flexoki-light
gruvbox             hackerman         kanagawa
lumon               matte-black       miasma
monochrome-minimal  nord              osaka-jade
retro-82            ristretto         rose-pine
solarized-dark      tokyo-night       vantablack
warm-pastel         windows-7
```

`catppuccin-latte` and `flexoki-light` are light palettes; the remaining tracked
palettes declare dark mode.

## Generated targets

A theme selection renders coordinated output for:

| Component | Generated destination |
| --- | --- |
| Hyprland | `hypr/.config/hypr/conf/decorations.lua` |
| Quickshell | `hypr/.config/hypr/themes/.active/theme.json` |
| Kitty | `kitty/.config/kitty/theme/current-theme.conf` |
| Zsh | live `~/.config/zsh/current-theme.zsh` (not a tracked Stow path) |
| Rofi | current palette/import files below `rofi/.config/rofi/` |
| Hyprlock | `hyprlock/.config/hyprlock/colors.conf` |
| SwayNC | `swaync/.config/swaync/style.css` |
| Wofi | `wofi/.config/wofi/style.css` |
| Noctalia | generated colors/scheme data |
| Fastfetch | configured `keyColor` |
| Neovim | `neovim/.config/nvim/colors/<slug>.lua` plus stable `current.lua` alias |
| btop | `btop/.config/btop/themes/<slug>.theme` plus stable `current.theme` alias |
| Obsidian | `obsidian/.config/obsidian/snippets/generated-theme.css` (link into a vault and enable manually) |
| Greeter (regreet) | `greeter/.config/greeter/{greeter.css,regreet.toml}` -- a further, opt-in `theme set --install-greeter` root-owned copy is required to reach `/etc/greetd/`; see `greeter/README.md` |

The generator also synchronizes relevant Noctalia settings and scheme metadata.
Neovim, btop, and Obsidian are optional. Deploy them with `stow --no-folding
neovim btop obsidian` before running `theme set`; `--no-folding` keeps app state
out of the checkout. If an output directory is absent, the generator reports
`skipped (not deployed)` and continues. This repository does not currently track
a `btop.conf`, so set `color_theme = "current"` once in your own config. Neovim
can likewise use `:colorscheme current`; each theme set repoints both stable
aliases and removes superseded generated slug files.
`current.lua` and `current.theme` are reserved for those stable aliases. If
either name is already a regular file without the generator marker, the
generator treats it as user-owned, leaves it untouched, and prints a warning.

Obsidian only reads snippets inside a vault. For every vault that should follow
the generated palette, create this symlink (replace `<vault>` with its path),
then enable `generated-theme.css` in that vault's Settings > Appearance > CSS
snippets:

```bash
mkdir -p "<vault>/.obsidian/snippets"
ln -sfn "$HOME/.config/obsidian/snippets/generated-theme.css" \
  "<vault>/.obsidian/snippets/generated-theme.css"
```

The generator never searches for or changes vault files.

## Theme bootstrap

After Stowing the relevant packages, generate a complete active theme:

```bash
~/.config/hypr/themes/theme set tokyo-night
```

Useful CLI operations supported by `theme` include listing palettes, displaying
the current palette, validating palettes, setting a palette, and cycling to the
next or previous palette. Use the command's `--help` output for the exact current
syntax.

The Quickshell picker on `SUPER+T` or `SUPER+CTRL+SHIFT+Space` browses the same
palette directory and applies only the selected center item/Enter choice.

## Live application behavior

On selection, the theme system can:

- preserve the current wallpaper by default;
- apply the palette's wallpaper through Hyprpaper when passed `--wallpaper`;
- reload Hyprland so generated decoration values take effect;
- notify the Quickshell theme watcher;
- update running Kitty windows through remote control;
- signal SwayNC when it is running; and
- leave generated output ready for applications that load it later, including
  Neovim (`:colorscheme current`) and btop (`color_theme = "current"`).

This means `theme set` is not a purely read-only renderer, although it does not
change the wallpaper unless explicitly passed `--wallpaper`. Use its validation
operations when testing palette edits without wanting to change the live desktop.

## Wallpaper resolution

Theme wallpapers are resolved from user wallpaper locations before static
repository assets. The resolver supports theme-specific images and fallback
locations. This is separate from the interactive wallpaper picker's default
directory; see [Wallpaper](./components.md#wallpaper).

## Fonts, icons, and cursors

- Kitty and glyph-heavy desktop UI expect JetBrainsMono Nerd Font.
- The active Hyprlock layout also references AlfaSlabOne and a JetBrains Mono
  ExtraBold face.
- Rofi requests the Papirus icon theme.
- Quickshell uses a generic sans-serif UI font plus Nerd Font glyphs.
- Hyprland sets XCursor and Hyprcursor size to 24, but the cursor theme itself
  could not be determined from the tracked configuration.
- GTK/Qt theme selection is not defined by a dedicated tracked GTK, Qt, or
  Kvantum package for the interactive desktop. It could not be determined from
  this repository.
- The regreet greeter is the one exception: `regreet-greeter.toml` sets a
  fixed GTK theme/icon/cursor name (`Adwaita`) and font, since regreet needs
  *some* value and none of those are tracked per-palette elsewhere. Only
  `application_prefer_dark_theme` follows the active theme's `mode`.

## Adding or changing a palette

1. Copy an existing theme directory under `hypr/.config/hypr/themes/`.
2. Rename it and edit `colors.toml`, retaining every key the validator requires.
3. Use the theme tool's validation command.
4. Set the palette and inspect all generated components, especially contrast in
   notifications, Rofi, Hyprlock, and terminal ANSI colors.
5. Commit only the source palette or deliberate generator/template changes, not
   ignored generated output.

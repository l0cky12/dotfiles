# Hyprland

Version on this machine: **0.56.2**. The configuration is Lua, not hyprlang.

## Entry point

`hypr/.config/hypr/hyprland.lua`. Its module graph is in
[Architecture](Architecture.md#configuration-source-graph).

A complete parallel hyprlang graph (`hyprland.conf` plus `conf/*.conf`) is kept
as a rollback path from the migration. Hyprland loads the Lua tree, which has one
practical consequence worth remembering:

> `hyprctl dispatch exec` and `hyprctl keyword` are legacy dispatchers and do
> nothing under the Lua config. Use `hyprctl eval` instead.

It also means `nwg-displays` output written to `monitors.conf` has no effect.

## Variables

`hypr/.config/hypr/conf/variables.lua`:

| Variable | Value | Used by |
| --- | --- | --- |
| `scripts_dir` | `/home/liam/.config/hypr/scripts` | most bindings and autostart lines |
| `terminal` | `kitty` | `SUPER+Return`, btop float, drop-down terminal |
| `browser` | `brave` | **declared but unused** |
| `file_manager` | `nautilus` | `SUPER+E`, `SUPER+SHIFT+E` |
| `disks` | `gnome-disks` | `SUPER+SHIFT+D` |

`SUPER+W` and the browser autostart line both name `helium-browser` literally.
Changing `browser` alone does nothing.

## Input and gestures

Set in `hyprland.lua` itself:

- US keyboard layout; no variant, model, rules, or options are set.
- `follow_mouse = 1` — pointer focus follows the mouse.
- Global pointer `sensitivity = 0`.
- Touchpad natural scrolling off.
- Three-finger horizontal gesture switches workspace.
- A device block for `epic-mouse-v1` at sensitivity `-0.5`, which only applies if
  a device reports that Hyprland name.

Tap-to-click, key repeat rate, and keyboard options are not configured anywhere
in the repository. Their behaviour is whatever Hyprland defaults to, and this
repo does not establish what that is.

Cursor sizes are exported as 24 for both XCursor and Hyprcursor. No cursor theme
is selected.

Two workarounds are set with in-file notes explaining when to remove them:
`AQ_NO_ATOMIC=1` for an Aquamarine hotplug crash, and `no_hardware_cursors = 1`
for rotated-output glitches.

## Appearance

Appearance comes from generated `hypr/.config/hypr/conf/decorations.lua`. Its
durable inputs are the palette and `[style]` block in
`hypr/.config/hypr/themes/<slug>/colors.toml`.

Border width, rounding, opacity, shadow, and blur are all rendered from the
selected palette. Inner/outer/float gaps are deliberately held at 6/12/12 across
every theme by the template, so a palette switch never reflows your windows.

There are no separately tracked animation, layout, or `misc` blocks. Any value
not emitted by the generated decoration file is not established by this
repository.

## Startup

`hypr/.config/hypr/conf/autostart.lua` registers commands on `hyprland.start`.
`hl.exec_cmd()` starts them asynchronously, so this is a functional grouping, not
a serial timeline.

| Command | Purpose |
| --- | --- |
| `hypr-wallpaper-picker restore` | restore the last wallpaper and start Hyprpaper |
| two `wl-paste --watch` processes | capture text and image clipboard changes |
| `quickshell` | bar, panels, notifications, clipboard UI, OSDs |
| `quickshell -c cava-visualizer` | audio visualiser shell instance |
| `hypridle` | screensaver, lock, DPMS, and suspend policy |
| `desktop-mode daemon` | mode expiry and backend reconciliation |
| `spotify-notify.sh` | track-change notifications |
| `systemctl --user start hypr-monitor-watch.service` | monitor hotplug watcher |
| `udiskie --automount --notify --no-tray` | removable-media automounting |
| `[workspace 1 silent] kitty` | terminal |
| `[workspace 2 silent] helium-browser` | browser |
| `[workspace 3 silent] obsidian` | notes |
| `[workspace 4 silent] t3code` | coding-agent control surface |
| `[workspace 6 silent] virt-manager` | VM manager |
| `[workspace 6 silent] hermes` | |
| `[workspace 9 silent] spotify` | music |

SwayNC and Noctalia are not started here; both lines are commented out.

The Lua and hyprlang copies of this file are kept in sync. Adding a startup
program means adding it to both `conf/autostart.lua` and `conf/autostart.conf`.

## Window rules

`hypr/.config/hypr/conf/window_rules.lua`.

### General behaviour

| Rule | Match | Effect |
| --- | --- | --- |
| `float-modal` | `modal = true` | float and centre |
| `round-floating` | `float = true` | 10 px rounding, 2 px border |
| `dim-floating` | `float = true` | dim the content behind |
| `fullscreen-border` | `fullscreen = true` | gradient border |
| `localsend` | `org.localsend.localsend_app` | float and centre |
| `capture-webcam-overlay` | title `capture-webcam` | float and pin |
| `ascii-screensaver` | `io.github.fhlkfds.screensaver` | fullscreen, floating, slide animation |

### Workspace assignment

| Match | Workspace |
| --- | --- |
| `brave-browser`, `helium`, `firefox` | 2, silent |
| `obsidian`, `Obsidian` | 3, silent |
| `t3code` | 4, silent |
| `virt-manager` | 6, silent |
| `org.kde.neochat` | 7, silent |
| `Spotify`, `spotify` | 9, silent |

Applications that both autostart and have a rule are pinned in two places. Keep
them in agreement when you move one.

Note that the browser rule matches the exact classes above. Brave's app-mode
windows derive their own class (`brave-youtube.com__-Default` and similar), so
web apps installed with `webapp` are never captured by the workspace-2 rule.

## Workspaces

`SUPER+1` … `SUPER+0` select workspaces 1–10 and `SUPER+ALT+1` … `SUPER+ALT+5`
select 11–15. Every profile maps all 15 to outputs. See
[Monitors and workspaces](Monitors-and-Workspaces.md#workspace-mapping) and
[Keybindings](Keybindings.md#workspaces).

## Wallpaper and night light

`hyprpaper.conf` enables IPC and disables the splash. It preloads nothing — the
image comes from the picker or the theme tool.

`hyprsunset.conf` starts with an identity profile, so it does nothing until
asked. `SUPER+CTRL+N` runs `night-light.sh`, which switches between 1000 K and
6500 K. When the `modes` package is installed the script delegates to
`desktop-mode`; otherwise it drives Hyprsunset directly, so the binding never
depends on another Stow package being deployed.

A separate screen shader at `hypr/.config/hypr/shaders/night-light.frag` is
enabled at startup when `$XDG_STATE_HOME/hyprland-desktop/night-light-shader`
exists.

## Idle, lock, and power

Covered in full on
[Idle, lock, and desktop modes](Idle-Lock-and-Desktop-Modes.md). The summary:

| Idle | Action |
| --- | --- |
| 180 s | launch the ASCII screensaver, if enabled, unlocked, and no audio is playing |
| 300 s | lock, unless stay-awake is active |
| 1,200 s | DPMS off; restore on activity |
| 1,800 s | `systemctl suspend` |

Plus `before_sleep_cmd = loginctl lock-session`, an `after_sleep_cmd` that
re-enables DPMS, and `inhibit_sleep = 3`.

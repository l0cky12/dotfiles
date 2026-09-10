# Customization

The one rule: **edit the repository path, not the live symlink target.** Change
`hypr/.config/hypr/conf/keybindings.lua`, never `~/.config/hypr/conf/keybindings.lua`.
They resolve to the same bytes, but only one of them is what Git sees, and three
of the deployed files get overwritten by generators anyway.

## Where to change what

| I want to change… | Edit |
| --- | --- |
| terminal, file manager, disk utility | `hypr/.config/hypr/conf/variables.lua` |
| the browser | the literal `helium-browser` in `conf/keybindings.lua` **and** `conf/autostart.lua` (the `browser` variable is not used) |
| any keybinding, or the modifier | `hypr/.config/hypr/conf/keybindings.lua` |
| what starts at login | `hypr/.config/hypr/conf/autostart.lua` |
| which workspace an app opens on | `hypr/.config/hypr/conf/window_rules.lua`, and the autostart line if it has one |
| floating / rounding / dimming rules | `hypr/.config/hypr/conf/window_rules.lua` |
| keyboard layout, mouse, touchpad, gestures | `hypr/.config/hypr/hyprland.lua` |
| monitor arrangement or workspace pinning | `hypr/.config/hypr/monitor_profiles/` — never the active `monitors.lua` |
| idle, lock, DPMS, suspend timers | `hypr/.config/hypr/hypridle.conf` |
| the lock screen layout | `hypr/.config/hypr/hyprlock.conf` and `hyprlock/.config/hyprlock/layouts/` |
| colours, gaps, borders, rounding, opacity, blur | `hypr/.config/hypr/themes/<slug>/colors.toml` |
| an appearance rule that should apply to *every* theme | `hypr/.config/hypr/theme/templates/` or `generate.py` |
| the bar layout or a widget | QML under `quickshell/.config/quickshell/` |
| notification timeouts, size, history, DND bypass | `quickshell/.config/quickshell/notifications/config.json` |
| the launcher's structural layout | `rofi/.config/rofi/comet-glass.rasi` |
| the lmenu tree | `menu/.config/lmenu/menu.jsonc` |
| mode temperatures, durations, panel presets | `modes/.config/desktop-mode/config.toml` |
| the screensaver logo | `screensaver-branding text` / `image`, or `screensaver/.config/branding/screensaver.txt` |
| wallpaper search directory | `HYPR_WALLPAPER_DIR`, or the picker default |
| default applications per MIME type | `xdg/.config/mimeapps.list` |
| clipboard history size | `cliphist/.config/cliphist/config` |
| which AI CLI `SUPER+I` opens | `ai/.config/ai-agent/config` |

## Keybindings

Covered in full on [Keybindings](Keybindings.md#adding-your-own). The short
version: use the file's `bind()` / `exec()` / `package_exec()` helpers so the
`SUPER+K` palette gets a description, check for a duplicate key/modifier pair,
and route scripts through `cfg.scripts_dir`.

`scripts_dir` is currently the absolute path `/home/liam/.config/hypr/scripts`.
Make it account-portable before reusing this on another machine.

## Appearance

Two levels, and picking the wrong one is the most common mistake here.

**One theme should look different** → edit that theme's
`hypr/.config/hypr/themes/<slug>/colors.toml`. Semantic roles, the 16 ANSI
terminal colours, and an optional `[style]` block for rounding, border width,
opacity, and blur all live there.

**Every theme should change** → edit `hypr/.config/hypr/theme/templates/<app>` or
`generate.py`. There are 12 templates, one per output.

Then validate and regenerate:

```bash
theme validate <slug>
theme set <slug>
```

Never commit a change made only to a generated file. `decorations.lua`,
`current-theme.conf`, `colors.conf`, `style.css`, and the rest are all in
`.gitignore` and will be overwritten on the next `theme set`. See
[Theming](Theming.md).

The generator deliberately holds inner/outer/float gaps at 6/12/12 across all
themes, so switching palettes never reflows your windows. Change that in the
template if you want it to vary.

## Bar and panels

The active shell is Quickshell, and only Quickshell. Editing SwayNC or Noctalia
changes nothing you can see.

Widgets live as individual QML files under `quickshell/.config/quickshell/`, and
`Bar.qml` mounts them into three groups: `leftGroup`, the centre clock anchor,
and `rightGroup`. Colours should come from `Theme.qml` — which watches
`~/.config/hypr/themes/.active/theme.json` and updates live — rather than being
hardcoded per widget.

`tests/omakub-bar-layout.test.sh` asserts that the bar still mounts the expected
component set, so removing a widget means updating that list too.

Waybar was retired when Quickshell became the authoritative bar. Restoring it
from Git history would also mean restoring its theme template and generator
target, and deciding whether Quickshell should keep serving notifications and
panels — starting both unchanged gives you two top bars.

## Monitors and workspaces

`monitors.lua` and `workspaces.lua` are machine state, not configuration. The
applier rewrites them from a profile pair on every connected-output change, and
`nwg-displays` rewrites them too. They are untracked for exactly that reason.

Arrange your displays however you like, then capture the result:

```bash
~/.config/hypr/scripts/capture-monitor-profile.sh kvm --dry-run
~/.config/hypr/scripts/capture-monitor-profile.sh kvm
~/.config/hypr/scripts/auto-monitor-profile.sh --force
```

If you don't want dynamic profiles at all, disable the watcher
(`systemctl --user disable --now hypr-monitor-watch.service`) and maintain the
two active files by hand. Also remove the optional udev dispatcher under
`hypr/.config/hypr/udev/` if you ever installed it, so nothing reapplies a
profile behind your back. See [Monitors and workspaces](Monitors-and-Workspaces.md).

## Notifications

Policy lives in `quickshell/.config/quickshell/notifications/config.json`:
position, history limit, per-urgency timeouts, card width, animation timing,
border widths, debug logging, and the audited DND bypass allow-list.

Keybindings call `notificationctl`, not the QML. If you replace the internals,
preserve that interface. Switching back to SwayNC means changing those bindings
too — they will not reach SwayNC as written.

## Applications

`terminal`, `file_manager`, and `disks` are honoured as variables. `browser` is
declared but unused: `SUPER+W` and the autostart line both name `helium-browser`
literally, and `xdg/.config/mimeapps.list` names Helium as the HTTP/HTML handler.
Change all three if you switch browsers.

When you move an autostarted application to a different workspace, update both
the autostart line's requested workspace and its window rule if it has one.
`t3code`, for example, is pinned in both places.

## Applying changes

| Change | How it takes effect |
| --- | --- |
| Hyprland config | `hyprctl reload` in the live session |
| `hl.env` / `PATH` changes in `hyprland.lua` | next login only — `hyprctl reload` will not do it |
| Quickshell QML | hot-reloaded by its file watcher; restart only if that fails |
| theme palette | `theme validate <slug>`, then `theme set <slug>` |
| regreet CSS/TOML | `theme set <slug> --install-greeter`, then restart greetd from an unused TTY, or wait for the next login |
| Kitty theme | applied live to running windows over remote control |
| monitor profile | `auto-monitor-profile.sh --force`, after a `--dry-run` |
| browser extension or manifest | fully quit and reopen the browser; use the repair helper if the shortcut is stuck |
| systemd user unit | `systemctl --user daemon-reload` |

Reloads mutate the live desktop. Run them deliberately after validating the
files, not as part of a repo-only edit check — that is also what
[`AGENTS.md`](../AGENTS.md) requires.

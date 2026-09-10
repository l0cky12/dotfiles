# Keybindings

Every binding on this page comes from `hypr/.config/hypr/conf/keybindings.lua`
unless it is marked as a browser extension command. The file's local `mod`
resolves to `SUPER`.

**`SUPER+K` opens a live, searchable palette of these bindings.** It reads
`hyprctl binds -j`, so it shows what the compositor actually loaded, not a copy
of this table. Each binding's Lua `description` is what appears there.

## How the file is structured

Three small helpers wrap `hl.bind`, and using them is what keeps the palette
useful:

```lua
bind(keys, description, dispatcher, flags)          -- native dispatcher
exec(keys, description, command, flags)             -- shell command
package_exec(keys, description, package, command)   -- command from another Stow package
```

`package_exec` routes through `scripts/run-if-deployed.sh`. Hyprland discards
`exec` output, so a binding pointing at an undeployed package's entry point would
otherwise do nothing at all, silently. The wrapper sends a desktop notification
naming the package instead. The `SUPER+I` coding-agent binding and the four
`desktop-mode` bindings use it.

## Session and general

| Keys | Action | Behind it |
| --- | --- | --- |
| `SUPER+Return` | terminal | `kitty`, from `variables.lua` |
| `SUPER+SHIFT+Return` | drop-down terminal | `Dropterminal.sh kitty` — a Kitty scratchpad on a special workspace |
| `SUPER+Q` | close window | `hl.dsp.window.close()` |
| `CTRL+ALT+Delete` | close all windows | `close-all-windows.sh` |
| `SUPER+L` | lock | `screensaver-lock` if present, otherwise Hyprlock directly |
| `SUPER+P` | power menu | `power-menu.sh`, launcher-neutral |
| `SUPER+ALT+P` | monitor profiles | themed Rofi menu with a next-profile cycle |
| `SUPER+K` | keybinding palette | `quickshell ipc call keybinds toggle` |
| `SUPER+I` | coding agent | `ai-agent`, via `run-if-deployed.sh ai` |
| `SUPER+CTRL+T` | activity monitor | floating `btop` |
| `SUPER+SHIFT+G` | Gaming VM | starts `Gaming-VM` with virsh, waits 15 s, then Looking Glass |

## Applications

| Keys | Action | Command |
| --- | --- | --- |
| `SUPER+A` | application launcher | `quick-search.sh drun` |
| `SUPER+SHIFT+A` | lmenu root menu | `lmenu toggle` |
| `SUPER+ALT+A` | web-app manager | `quickshell ipc call webapps toggle` |
| `SUPER+W` | browser | `helium-browser` |
| `SUPER+SHIFT+ALT+W` | private browser window | `default-browser-private` |
| `SUPER+ALT+W` | Windows VM | `windows-vm launch` |
| `SUPER+CTRL+ALT+W` | stop Windows VM | `windows-vm stop` |
| `SUPER+E`, `SUPER+SHIFT+E` | files | `nautilus`, from `variables.lua` |
| `SUPER+SHIFT+ALT+F` | files at the terminal's cwd | `files-here.sh` |
| `SUPER+SHIFT+D` | disks | `gnome-disks` |
| `SUPER+U` | eject removable drives | `eject-drive.sh` |
| `SUPER+S` | Spotify | `spotify` |
| `SUPER+O` | Obsidian | `obsidian` |
| `SUPER+SHIFT+H` | Hermes | `hermes` |
| `SUPER+R` | voice dictation | `hyprvoice toggle` |
| `SUPER+CTRL+S` | LocalSend | `localsend`; its window is floated and centred by a rule |

`SUPER+W` calls `helium-browser` literally. The `browser` variable in
`variables.lua` says `brave` and is not used by this binding — changing it alone
does nothing.

## Panels

Every one of these is a Quickshell IPC call, so they toggle panels inside the
already-running shell rather than starting a process.

| Keys | Panel |
| --- | --- |
| `SUPER+CTRL+D` | display (also hosts the THEME launcher row) |
| `SUPER+CTRL+I` | network status |
| `SUPER+CTRL+W` | network management: Wi-Fi, DNS, IPv4, Wi-Fi QR |
| `SUPER+CTRL+A` | audio |
| `SUPER+CTRL+B` | Bluetooth |
| `SUPER+CTRL+M` | media |
| `SUPER+CTRL+V` | clipboard history |
| `SUPER+ALT+V` | audio visualiser |
| `SUPER+CTRL+SHIFT+SPACE` | theme picker |
| `SUPER+SHIFT+B` | power profile menu (Rofi, over `powerprofilesctl`) |

## Clipboard, calculator, emoji, transcode

| Keys | Action | Notes |
| --- | --- | --- |
| `SUPER+C` | universal copy | sends `CTRL+SHIFT+C` in terminals, `CTRL+C` elsewhere |
| `SUPER+X` | universal cut | terminal cut intentionally does nothing |
| `SUPER+V` | universal paste | terminal-appropriate shortcut |
| `SUPER+ALT+E` | emoji picker | themed Rofi fuzzy search, copies the glyph |
| `SUPER+CTRL+Q` | calculator | `qalc` behind Rofi; Enter on the answer copies it |
| `SUPER+SHIFT+C` | calculator | second binding for the same script |
| `SUPER+CTRL+.` | transcode media | fuzzy picker over `~/Pictures` and `~/Videos` |

## Notifications

| Keys | Action |
| --- | --- |
| `SUPER+,` | dismiss newest card |
| `SUPER+SHIFT+,` | dismiss all visible cards |
| `SUPER+CTRL+,` | toggle DND through `desktop-mode` |
| `SUPER+ALT+,` | invoke the newest card's default action |
| `SUPER+SHIFT+ALT+,` | replay notification history |
| `SUPER+D` | toggle DND through `notificationctl` directly |

`SUPER+CTRL+,` and `SUPER+D` reach the same state by different routes:
`SUPER+CTRL+,` goes through `desktop-mode`, which can also apply a timer;
`SUPER+D` calls `notificationctl dnd-toggle`.

## Capture

| Keys | Action |
| --- | --- |
| `SUPER+SHIFT+S` | smart screenshot — drag for a region, click for the window under the pointer |
| `SUPER+ALT+S` | screenshot the focused monitor |
| `SUPER+ALT+CTRL+S` | same, after 5 seconds |
| `SUPER+CTRL+SHIFT+S` | same, after 10 seconds |
| `SUPER+SHIFT+R` | toggle screen recording |
| `SUPER+SHIFT+P` | colour picker |
| `SUPER+SHIFT+T` | OCR the selection |
| `SUPER+CTRL+C` | capture mode chooser |
| `SUPER+ALT+C` | toggle the webcam overlay |
| `SUPER+ALT+[` / `SUPER+ALT+]` | webcam overlay smaller / larger; opens it if missing |

All of these dispatch to `scripts/capture/capture.sh`. See
[Scripts and CLIs](Scripts-and-CLIs.md#capture-suite).

## Appearance, modes, reminders

| Keys | Action |
| --- | --- |
| `SUPER+CTRL+SHIFT+SPACE` | theme picker |
| `SUPER+SHIFT+W` | wallpaper picker and Wallhaven search |
| `SUPER+CTRL+N` | night light, 1000 K ↔ 6500 K |
| `SUPER+CTRL+O` | toggles menu (night light, DND, stay-awake, and the rest) |
| `SUPER+ALT+M` | desktop modes panel |
| `SUPER+SHIFT+I` | toggle selective stay-awake |
| `SUPER+Backspace` | toggle window transparency everywhere |
| `SUPER+SHIFT+Backspace` | toggle gaps and borders everywhere |
| `SUPER+CTRL+Escape` | launch the ASCII screensaver now |
| `SUPER+CTRL+SHIFT+Escape` | toggle automatic screensaver launch |
| `SUPER+CTRL+R` | set a reminder |
| `SUPER+CTRL+ALT+R` | list pending reminders |
| `SUPER+CTRL+SHIFT+R` | clear all reminders |

Reminders are transient systemd user timers, so they outlive the launching
process and systemd cancels them.

## Workspaces

### Focus

| Keys | Destination |
| --- | --- |
| `SUPER+1` … `SUPER+0` | workspaces 1–10 |
| `SUPER+ALT+1` … `SUPER+ALT+5` | workspaces 11–15 |
| `SUPER+Tab` / `SUPER+SHIFT+Tab` | next / previous open workspace |
| `SUPER+CTRL+Tab` | the workspace you were on before |
| `SUPER+wheel down` / `SUPER+wheel up` | next / previous open workspace |

### Move the active window

| Keys | Action |
| --- | --- |
| `SUPER+SHIFT+1` … `SUPER+SHIFT+0` | move to 1–10 and follow |
| `SUPER+CTRL+1` … `SUPER+CTRL+0` | move to 1–10 without following |
| `SUPER+SHIFT+ALT+1` … `SUPER+SHIFT+ALT+4` | move to 1–4 without following |
| `SUPER+SHIFT+[` / `SUPER+SHIFT+]` | move and follow to previous / next |
| `SUPER+CTRL+[` / `SUPER+CTRL+]` | move silently to previous / next |

Two implementation details are worth knowing before you edit these.

The number row is bound by **physical keycode** — `code:10` through `code:19` for
`1` through `0`. And the move bindings do not use the native dispatcher directly;
they shell out to `hyprctl eval` so the dispatch happens at keypress time:

```lua
hyprctl eval 'hl.dispatch(hl.dsp.window.move({ workspace = 4, follow = true }))'
```

The comment in the file explains why: on Hyprland 0.56.2, a *bound* Lua window
dispatcher does not reliably act on the focused window. Focus bindings use the
native path and are unaffected.

## Window management

| Keys | Action |
| --- | --- |
| `SUPER+SHIFT+F` | true fullscreen |
| `SUPER+CTRL+F` | maximize, keeping the bar and gaps |
| `SUPER+T` | toggle floating / tiled |
| `SUPER+J` | next window opens to the right (`preselect r`) |
| `SUPER+SHIFT+V` | next window opens below (`preselect d`) |
| `SUPER+←↑↓→` | move focus |
| `SUPER+CTRL+←↑↓→` | move window |
| `SUPER+SHIFT+←↑↓→` | swap window |
| `SUPER+SHIFT+ALT+←↑↓→` | move the whole workspace to the monitor in that direction |
| `SUPER+minus` / `SUPER+equal` | horizontal resize, ∓100 px |
| `SUPER+SHIFT+minus` / `SUPER+SHIFT+equal` | vertical resize, ∓100 px |
| `SUPER+ALT+minus` / `SUPER+ALT+equal` | fine horizontal resize, ∓10 px |
| `SUPER+CTRL+minus` / `SUPER+CTRL+equal` | coarse horizontal resize, ∓300 px |
| `SUPER+ALT+Home` | save the active window's width for this session |
| `SUPER+Home` | restore that width, keeping the current height |
| `SUPER+left drag` | move window |
| `SUPER+SHIFT+right drag` | resize window |

`preselect` is a one-time dwindle override, so `SUPER+J` and `SUPER+SHIFT+V`
affect only the next window to open.

## Desktop zoom

| Keys | Action |
| --- | --- |
| `SUPER+ALT+wheel down` | zoom × 1.1 |
| `SUPER+ALT+wheel up` | zoom × 0.9, clamped at 1 |
| `SUPER+ALT+SHIFT+wheel` either way | reset to 1 |

These read `cursor:zoom_factor` with `hyprctl getoption -j`, do the arithmetic in
`jq`, and write it back with `hyprctl eval`.

## Media, volume, brightness

| Key | Action | Command |
| --- | --- | --- |
| `XF86AudioRaiseVolume` | +5%, repeatable | `wpctl set-volume -l 1.0`, capped at 100% |
| `XF86AudioLowerVolume` | −5%, repeatable | `wpctl` |
| `XF86AudioMute` | toggle mute | `wpctl` |
| `XF86AudioPlay` | play/pause | `playerctl play-pause` |
| `XF86AudioPause` | pause | `playerctl pause` |
| `XF86AudioNext` / `XF86AudioPrev` | next / previous track | `playerctl` |
| `XF86AudioStop` | stop | `playerctl stop` |
| `XF86MonBrightnessUp` / `Down` | ±5%, repeatable | `brightnessctl` |

The three volume keys are **registered twice**: once with `wpctl`, then again
with `pactl` and `locked = true`. The comment in the file says this order is
deliberate and that the earlier `wpctl` definitions shadow the `pactl`
fallbacks. If you want the PulseAudio path, delete the `wpctl` set rather than
expecting both to fire.

## Browser extension shortcuts

These belong to Chromium, not Hyprland. They will not appear in `SUPER+K`.

| Keys | Action |
| --- | --- |
| `ALT+SHIFT+L` | copy the active tab's URL to the Wayland clipboard |
| `ALT+SHIFT+D` | send the active page to yt-dlp |

Inspect or change them at `brave://extensions/shortcuts` (or the `chrome://`
equivalent). A shortcut already claimed by another extension must be cleared
there first. See [Troubleshooting](Troubleshooting.md#browser-shortcuts).

## Adding your own

Use `bind()` or `exec()` rather than raw `hl.bind`, so the palette gets a
description:

```lua
exec(mod .. " + N", "notes", "obsidian")
```

Check for a duplicate key/modifier pair first — the volume section shows that a
duplicate registration silently shadows the later one. Route script commands
through `cfg.scripts_dir`. If the command lives in another Stow package, use
`package_exec` so an undeployed package reports itself.

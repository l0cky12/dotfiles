# Fixing things

Symptom-first. Find what you are seeing, try the quick checks, then follow the
link into the technical [Troubleshooting](Troubleshooting.md) page.

> House rule of this wiki: where the repository does not establish a fact, we
> say so rather than guess. The same applies to your machine — check the
> referenced command or file before assuming.

## "My keybind does nothing"

1. Press `Super+K` and search for the action. The palette reads `hyprctl binds`
   live, so it shows what is *actually* bound right now. If your binding is
   missing there, the config you edited did not load.
2. Remember: this setup configures Hyprland in Lua
   (`~/.config/hypr/hyprland.lua`). `hyprctl dispatch` and `hyprctl keyword`
   are legacy dispatchers and do nothing under it — use `hyprctl eval`.
3. Some bindings belong to separate Stow packages and route through
   `run-if-deployed.sh`, which reports an undeployed package instead of
   failing silently. Run the underlying command in a terminal and read what it
   says.

→ [Troubleshooting](Troubleshooting.md)

## "The bar disappeared"

The bar is Quickshell; if the whole bar is gone, the shell likely exited or was
toggled off.

- Toggle it back: lmenu → **Trigger → Toggle → Menu bar** (this runs
  `~/.config/hypr/scripts/toggles-menu.sh bar`).
- Reload the shell: `quickshell ipc call shell reload` (lmenu → **Update →
  Config → Reload Quickshell**), or `pkill -x quickshell` if IPC itself is
  stuck.
- If only a *panel* is missing, the panel's backend may not be running — see
  the next symptom.

→ [Troubleshooting § Quickshell bar or panels do not appear](Troubleshooting.md)

## "A panel opens but shows nothing / errors"

Panels talk to system services (NetworkManager, PipeWire — the audio server —
and bluetoothd) through Quickshell backends. If the panel renders but is
empty, the underlying service is usually the problem.

- lmenu → **Update → Hardware** can restart audio, networking, and Bluetooth.
- Check the service itself: `systemctl status NetworkManager`, `systemctl
  --user status pipewire`.

→ [Quickshell shell](Quickshell-Shell.md)

## "Wi-Fi menu shows no networks"

- Is Wi-Fi switched on? The network panel (`Super+Ctrl+I`) has a Wi-Fi on/off
  toggle at the top.
- Trigger a scan from the panel.
- If the panel is fine but lmenu hides its Wi-Fi rows, the guard conditions
  failed: rows require `qrencode` installed and an active wireless connection.
  Check with `command -v qrencode` and `nmcli -t -f TYPE connection show
  --active`.
- Wireless still dead at the OS level is outside this repository — see
  [Dependencies](Dependencies.md) for what networking expects, and the Arch
  wiki for hardware-level issues.

→ [Troubleshooting](Troubleshooting.md)

## "Notifications never appear"

- Is do-not-disturb on? Toggle with `Super+D` or check lmenu → **Trigger →
  Toggle → Do not disturb**.
- The notification service lives inside Quickshell, so if the bar is gone the
  notifications are too. Fix the shell first.
- History still shows missed items: `Super+Shift+Alt+,` (or `notificationctl
  history`).

→ [Troubleshooting § Notifications do not appear](Troubleshooting.md)

## "My theme changes did nothing"

Themes are generated outputs. Editing a palette does nothing until the
generator re-runs; editing a generated file gets overwritten on the next
`theme set`. Edit the palette, then re-apply (`theme set "$(theme current)"`,
or lmenu → **Update → Theme → Regenerate theme output**).

→ [Theming](Theming.md)

## "Screenshots come out black / capture fails"

Capture tools need their helpers installed (grim, slurp, and friends — see
[Dependencies](Dependencies.md)). The capture menu (`Super+Ctrl+C`) surfaces
per-tool errors.

→ [Troubleshooting § Capture failures](Troubleshooting.md)

## "The lock screen or idle suspend behaves oddly"

Idle behaviour is a chain: Hypridle (timers) → screensaver / hyprlock →
desktop-mode state. Stay awake (`Super+Shift+I`) blocks the idle lock; check
that first.

→ [Troubleshooting § Lock or idle behaviour fails](Troubleshooting.md)

## "An app I installed is not in the launcher"

The launcher reads desktop entries; a package installed outside pacman/AUR
with no `.desktop` file will not appear. Install it through lmenu →
**Install** so the entries land correctly, or add the entry manually.

→ [Troubleshooting § Launcher entries fail](Troubleshooting.md)

## When nothing above helps

[Troubleshooting](Troubleshooting.md) is the full technical list, including
monitor layouts, browser tool helpers, and the boundaries of what this
repository is responsible for. Configuration questions are answered in
[Customization](Customization.md) ("I want to change X" → the file to edit).

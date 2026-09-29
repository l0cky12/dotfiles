# Desktop modes

The `modes/` package provides one original, user-local controller for temporary
desktop behavior. It centralizes CLI, keybinding, and Quickshell actions without
copying another distribution's commands, paths, state flags, UI, or branding.

## Boundaries

| Control | Effect | Persistence |
| --- | --- | --- |
| `night-light` | enables or disables the compositor's warm screen shader | persistent shader state; timer lasts the current login |
| `do-not-disturb` | suppresses Quickshell notification toasts; history is retained | current login |
| `stay-awake` | defers idle screensaver and idle lock listeners only | current login |
| `screensaver-auto` | permits the ASCII scheduler's idle launch | persistent user override |
| manual screensaver | immediately launches the scene | action, not a mode |

Stay-awake does **not** inhibit DPMS, suspend, hibernate, manual locking,
before-sleep locking, or general power management. Status-bar pills are a view
of observed state, not a separate control system.

## Setup and controls

Deploy source packages only when ready:

```bash
stow modes screensaver hypr quickshell
```

A new login starts `desktop-mode daemon`; the primary Hypridle process owns the
screensaver timeout. Night-light changes call `night-light.sh`, which reloads
Hyprland to apply the shader. The controller does not install software, write
system files, or restart services.

| Shortcut | Action |
| --- | --- |
| `SUPER+ALT+M` | open the focused-monitor modes panel |
| `SUPER+CTRL+N` | toggle night light |
| `SUPER+CTRL+,` | toggle DND |
| `SUPER+SHIFT+I` | toggle stay-awake |
| `SUPER+CTRL+ESCAPE` | launch the screensaver now |

```bash
desktop-mode list
desktop-mode status --json
desktop-mode enable stay-awake --for 30m
desktop-mode disable stay-awake
desktop-mode toggle night-light
desktop-mode disable screensaver-auto
desktop-mode enable screensaver-auto
desktop-mode reset --all
desktop-mode action screensaver
desktop-mode menu
desktop-mode doctor --json
```

`desktop-mode action screensaver` (or `ascii-screensaver force`) is the manual
launch command and ignores the automatic toggle. Automatic activation is
enabled with `desktop-mode enable screensaver-auto`; the primary Hypridle
configuration applies the 180-second delay and waits for active audio playback
to stop.

Durations are positive integers followed by `s`, `m`, or `h`. Timers apply only
to night light, DND, and stay-awake. Defaults expose 15-minute, 30-minute, and
one-hour presets and reject durations over 24 hours.

## State, reconciliation, and idle behavior

Private atomic state lives at
`$XDG_RUNTIME_DIR/hyprland-desktop/modes/state.json`. It survives a compositor
or Quickshell restart in the same login and disappears with the login runtime
directory. The daemon supervises expiry and restores desired DND state after
a backend restart. Night light follows the shader helper's persistent state.
A later helper request cancels an earlier mode timer, so its expiry cannot
undo a manual or scheduled change. Status reports desired and observed values
separately; the bar uses observed values and shows errors instead of false
success.

Hypridle's primary 660-second lock listener and the screensaver-only listener
ask `desktop-mode condition ...` before firing. While stay-awake is active,
both defer in five-second increments. When a timer expires while still idle,
the next retry is permitted. User activity resets the listeners normally.

The lock condition fails securely: an absent controller permits the existing
lock, and corrupt or missing optional configuration also permits locking. The
DPMS listener at 1,200 seconds, suspend listener at 1,800 seconds, and
before-sleep lock are unchanged and have no mode condition.

## Configuration

Edit `modes/.config/desktop-mode/config.toml`. It defines
maximum duration, panel presets, reconciliation interval, and argv arrays for
`notificationctl`, `ascii-screensaver`, and `night_light_command`. The retained
temperature settings are for compatibility; the shader uses fixed coefficients.
Unknown keys, invalid bounds, empty
commands, and NUL bytes are rejected. `DESKTOP_MODE_CONFIG` and
`DESKTOP_MODE_RUNTIME_DIR` provide fixture or user-local overrides.

Screensaver and lock inactivity are both defined in
`hypr/.config/hypr/hypridle.conf`. The toggle changes only
`$XDG_STATE_HOME/toggles/screensaver-off`.

## Diagnostics and recovery

```bash
desktop-mode doctor --json
desktop-mode status --json
ascii-screensaver --dry-run
toggle-screensaver status
screensaver-lock --dry-run
```

- `available=false` for DND means Quickshell IPC is not reachable.
- A night-light error means the shader helper or its Hyprland reload failed.
- A daemon warning means untimed operations work, but timed expiry is not
  supervised. Start `desktop-mode daemon` once for the current login.
- `desktop-mode reset --all` disables transient modes and restores automatic
  screensaver activation.
- `screensaver-lock --dry-run` prints the cleanup and lock handoff without changing state.
- For corrupt runtime state, stop the user daemon and remove only
  `$XDG_RUNTIME_DIR/hyprland-desktop/modes`, then restart it.

Rollback consists of removing the mode-specific autostart, keybinding, and
Hypridle condition lines and unstowing `modes`. Existing lock, DPMS, suspend,
notifications, and the night-light shader helper remain independently usable.

# Idle, lock, and desktop modes

Four systems overlap here, and keeping their boundaries straight is what makes
them predictable:

- **Hypridle** owns the timers.
- **Hyprlock** owns authentication.
- **The ASCII screensaver** is a visual layer with its own launcher and its own
  handoff to the lock.
- **`desktop-mode`** owns temporary state, and deliberately owns *nothing* about
  locking, DPMS, or suspend.

## Hypridle

`hypr/.config/hypr/hypridle.conf`. Four listeners:

| Timeout | Action | Condition |
| --- | --- | --- |
| 180 s | `ascii-screensaver idle` | `ascii-screensaver condition` — retries every 5 s while locked, disabled, already running, or while a PipeWire output stream is playing |
| 300 s | `loginctl lock-session` | `desktop-mode condition lock` — retries every 5 s while stay-awake is active |
| 1,200 s | DPMS off, restored on resume | none |
| 1,800 s | `systemctl suspend` | none |

Plus, in `general`:

- `lock_cmd` prefers `~/.local/bin/screensaver-lock`, falling back to
  `pidof hyprlock || hyprlock`. D-Bus lock requests — including the pre-suspend
  one below — therefore start exactly one Hyprlock instance.
- `before_sleep_cmd = loginctl lock-session`, so suspend is blocked until the
  session is actually locked.
- `after_sleep_cmd` re-enables DPMS after resume.
- `inhibit_sleep = 3`.

Both condition commands are guarded inline (`test -x ... &&`, or `test ! -x ... ||`)
so an undeployed package does not break the timer.

**Hypridle cannot cancel the 300-second lock when the screensaver is
dismissed.** Keyboard input resets both timers; dismissing by focus loss alone
does not. The comment at the top of the file says so explicitly.

## Hyprlock

`hypr/.config/hypr/hyprlock.conf` is the wrapper. It uses the `hyprlock` PAM
service, disables fingerprint authentication, imports the generated
`colors.conf`, and sources `layouts/hyprlock.conf` from the `hyprlock` package.

That active layout is a large clock and date plus a compact user/password card.
Colours, borders, radius, opacity, scrim, shadow, and blur all come from the
active theme. The background reads the same persisted current-wallpaper state the
picker and theme tool write; missing or stale state falls back to the theme's
colour rather than to a black screen.

Many alternate layouts and music/weather helpers are tracked under
`hyprlock/.config/hyprlock/layouts/`. They are examples, not active composition.
Several assume `BAT0`, network access, extra fonts, or a profile image — read one
before enabling it.

`SUPER+L` locks immediately.

## ASCII screensaver

The `screensaver` package opens one fullscreen terminal on every active Hyprland
monitor and runs a continuous sequence of random `ttfx` effects. A key press or
loss of focus closes it. Pointer movement is ignored.

```bash
ascii-screensaver force              # manual launch, ignores the automatic toggle
ascii-screensaver --dry-run          # print monitor focus and terminal spawns
toggle-screensaver                   # toggle automatic use
toggle-screensaver status
screensaver-branding text
screensaver-branding image logo.png
screensaver-branding reset
screensaver-lock --dry-run           # show the lock handoff without doing it
install-ttfx --dry-run
```

`SUPER+CTRL+Escape` force-launches. `SUPER+CTRL+SHIFT+Escape` toggles automatic
launch. Both actions are also in `lmenu`, under System and under Trigger →
Toggle.

The launcher uses the desktop-entry ID from `xdg-terminal-exec --print-id`.
Alacritty, Foot, Ghostty, and Kitty are supported; anything else produces a
notification and exits 1. Dedicated black, opaque, 18-point, zero-padding
terminal configs live under `screensaver/.config/ascii-screensaver/`.

It focuses each monitor before spawning, and waits for that terminal's
`openwindow` event on Hyprland's socket2 before continuing — that spawn barrier
is why every output reliably gets one.

The window class is `io.github.fhlkfds.screensaver`, matched by a window rule
that makes it fullscreen, floating, and slide-animated.

### The lock handoff

`screensaver-lock` terminates `ttfx`, waits up to one second for it to exit,
closes the screensaver terminals, then starts Hyprlock. Both `SUPER+L` and
Hypridle's `lock_cmd` go through it.

### The logo

Editable at `~/.config/branding/screensaver.txt`, whose Stow source is
`screensaver/.config/branding/screensaver.txt`. `reset` copies the repo default
from `screensaver/.local/share/ascii-screensaver/default-logo.txt`.

Image conversion defaults to 80 columns by 26 rows in Unicode braille. Override
with `--mode block`, `--width`, and `--height` after the image path. The
converter detects real alpha, normalises opaque light and dark backgrounds, trims
the image, writes through a temporary file, and rejects empty output. Every
branding command force-launches a preview afterwards.

### The persistent off flag

`$XDG_STATE_HOME/toggles/screensaver-off`, normally
`~/.local/state/toggles/screensaver-off`. This is the one mode override that
survives a logout, deliberately. Manual force-launch ignores it.

## Desktop modes

The `modes/` package is one user-local controller for temporary desktop
behaviour, shared by the CLI, the keybindings, and the Quickshell panel.

| Control | Effect | Persistence |
| --- | --- | --- |
| `night-light` | sets Hyprsunset to the configured warm or normal temperature | current login |
| `do-not-disturb` | suppresses Quickshell toasts; history is still recorded | current login |
| `stay-awake` | defers the idle screensaver and idle lock listeners **only** | current login |
| `screensaver-auto` | permits the scheduler's idle launch | persistent |
| manual screensaver | launches the scene now | an action, not a mode |

Stay-awake does **not** inhibit DPMS, suspend, hibernate, manual locking,
before-sleep locking, or general power management. The bar's pills are a view of
observed state, not a second control system.

### Commands

```bash
desktop-mode list
desktop-mode status --json
desktop-mode enable stay-awake --for 30m
desktop-mode disable stay-awake
desktop-mode toggle night-light
desktop-mode enable screensaver-auto
desktop-mode disable screensaver-auto
desktop-mode reset --all
desktop-mode action screensaver
desktop-mode menu
desktop-mode doctor --json
```

Durations are a positive integer followed by `s`, `m`, or `h`. Timers apply only
to night light, DND, and stay-awake. The defaults expose 15-minute, 30-minute,
and one-hour presets and reject anything over 24 hours.

| Shortcut | Action |
| --- | --- |
| `SUPER+ALT+M` | modes panel on the focused monitor |
| `SUPER+CTRL+N` | night light |
| `SUPER+CTRL+,` | DND |
| `SUPER+SHIFT+I` | stay-awake |
| `SUPER+CTRL+Escape` | screensaver now |
| `SUPER+CTRL+O` | the toggles menu |

### State and reconciliation

State is private and atomic at
`$XDG_RUNTIME_DIR/hyprland-desktop/modes/state.json`. It survives a compositor or
Quickshell restart within the same login, and disappears with the login runtime
directory.

The daemon supervises expiry and restores desired night-light and DND state after
a backend restart. `status` reports desired and observed values separately, which
is why the bar can show an error rather than a false success.

### Failing closed

The lock condition is written to fail *toward* locking:

- An absent `desktop-mode` binary permits the lock (`test ! -x ... ||`).
- Corrupt or missing optional configuration also permits locking.
- Malformed mode state in the CLI permits locking.

Weakening the security boundary is never the fallback.

### Configuration

`modes/.config/desktop-mode/config.toml` defines temperatures, maximum duration,
panel presets, the reconciliation interval, and argv arrays for `notificationctl`
and `ascii-screensaver`. Unknown keys, invalid bounds, empty commands, and NUL
bytes are rejected. `DESKTOP_MODE_CONFIG` and `DESKTOP_MODE_RUNTIME_DIR` provide
fixture and user-local overrides.

Screensaver and lock inactivity are *not* configured here — both live in
`hypr/.config/hypr/hypridle.conf`. The toggle only writes
`$XDG_STATE_HOME/toggles/screensaver-off`.

## Diagnostics

```bash
desktop-mode doctor --json
desktop-mode status --json
ascii-screensaver --dry-run
toggle-screensaver status
screensaver-lock --dry-run
```

- `available=false` for DND means Quickshell IPC is not reachable.
- A night-light error means Hyprsunset or its Hyprland IPC is unavailable.
- A daemon warning means untimed operations work but timed expiry is not
  supervised; start `desktop-mode daemon` once for this login.
- `desktop-mode reset --all` disables the transient modes and restores automatic
  screensaver activation.
- For corrupt runtime state, stop the daemon and remove only
  `$XDG_RUNTIME_DIR/hyprland-desktop/modes`, then restart it.

## Rolling it back

Remove the mode-specific autostart line, the keybindings, and the two Hypridle
`condition_cmd` lines, then `stow -D modes`. Lock, DPMS, suspend, notifications,
and Hyprsunset all remain independently usable — nothing in the package installs
software, writes system files, reloads Hyprland, or restarts services.

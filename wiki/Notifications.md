# Notifications

Notifications are served and rendered by the persistent Quickshell process.
Applications talk to `org.freedesktop.Notifications`; one service normalises the
event, persists it, applies DND, and either places it in the focused monitor's
top-right stack or writes it silently to history.

```text
application → Quickshell NotificationServer → NotificationService
                                              ├── active / history state
                                              ├── per-output card stack
                                              └── notifications IPC
```

SwayNC is a retained rollback backend. Its autostart line is commented out, and
no notification data is shared between the two.

## Surfaces

The full-screen layer-shell surfaces use the **overlay** layer, request no
keyboard focus and no exclusion zone, and have an input mask made only from the
card stack. Transparent space is therefore click-through.

The Quickshell bar is authoritative, so top-anchored notifications clear
`Theme.barHeight` plus the normal outer gap. Notifications with no output
metadata go to Hyprland's focused monitor, and a disconnected output is
deterministically remapped to the current focused monitor.

## Controls

| Binding | Action |
| --- | --- |
| `SUPER+,` | dismiss the newest visible card |
| `SUPER+SHIFT+,` | dismiss all visible cards |
| `SUPER+CTRL+,` | toggle persistent DND, through `desktop-mode` |
| `SUPER+ALT+,` | invoke or focus the newest card |
| `SUPER+SHIFT+ALT+,` | replay the newest 10 history entries |
| `SUPER+D` | toggle DND directly, through `notificationctl` |

The bindings contain no notification logic — they call `notificationctl`.

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

`notificationctl` is a Python wrapper around Quickshell IPC. Commands prefixed
with `_` are private and used by `NotificationPersistence.qml` for filesystem
work; they take JSON on stdin specifically so notification text is never parsed
by a shell.

## Card behaviour

Left click invokes the live default action. If there is no live action it falls
back to matching `desktop-entry`, then app name, then icon, against Hyprland
window classes — so clicking a restored or replayed card focuses the right
application instead of pretending an expired action still works.

Right click, or the hover close button, dismisses. Hovering pauses the deadline.

Critical cards stay until acted on. Low and normal cards last at least 5 and 8
seconds, and ordinary requests are clamped to 30 seconds.

## Configuration

`quickshell/.config/quickshell/notifications/config.json`:

| Setting | Default |
| --- | --- |
| `position` | `top-right` |
| `historyLimit` | 10 |
| `defaultDnd` | `false` |
| `lowTimeoutMs` | 5000 |
| `normalTimeoutMs` | 8000 |
| `ordinaryMaxTimeoutMs` | 30000 |
| `cardWidth` | 380 |
| `stackGap`, `sidePadding` | 8, 12 |
| `iconSize`, `iconGap`, `glyphGap`, `closeSize` | 40, 12, 8, 18 |
| `countdownHeight` | 2 |
| `animationMs`, `closeFadeMs` | 130, 100 |
| `borderWidths` | `[]` — per side, `[top, right, bottom, left]` |
| `debug` | `false` |
| `dndBypassApps` | `Do Not Disturb`, `Night Light`, `Capture`, `Battery`, `Web Apps` |

A DND bypass requires **both** an allow-listed app name **and** an explicit local
bypass hint. Urgency alone never bypasses DND.

## State

Private and atomic, under `$XDG_STATE_HOME/hyprland-desktop/notifications/`
(falling back to `~/.local/state`):

```text
state.json       persistent DND flag
active/          cards restored after a shell restart
history/         newest 10 by default
images/          bounded copies owned by retained records
```

The safety properties are deliberate: malformed JSON is skipped rather than
fatal, filenames are validated, notification text never goes through a shell,
writes use fsync plus rename, and orphaned images are swept.

## Theming

Theme roles are generated for every palette as `notifications.background`,
`text`, `bodyText`, `border1`, `border2`, `countdown`, and `close`. The QML
contains no notification palette of its own, and corner radius follows the
generated Hyprland rounding.

Per-side borders are configured as `[top, right, bottom, left]` — for example
`[2, 2, 2, 6]` for a thicker left edge.

## Implementation

`quickshell/.config/quickshell/notifications/`:

| File | Role |
| --- | --- |
| `NotificationRoot.qml` | mounted by `shell.qml`; wires the pieces together |
| `NotificationServer.qml` | owns the `org.freedesktop.Notifications` D-Bus name |
| `NotificationService.qml` | normalisation, DND, routing, lifetimes |
| `NotificationPersistence.qml` | state, history, and image files via `notificationctl` |
| `NotificationStack.qml`, `NotificationOverlay.qml` | per-output surface and layout |
| `NotificationCard.qml`, `NotificationActions.qml`, `NotificationBorder.qml` | the card itself |
| `NotificationConfig.qml` | reads `config.json` |
| `NotificationLogic.js` | pure logic, unit-tested from Node |
| `config.json` | user settings |
| `tests/` | Python and JavaScript unit tests |

The card component is shared by live and replayed history cards.

## Testing

```bash
notify-send "Test notification" "This is the body."
notify-send -u low "Low urgency" "At least five seconds"
notify-send -u critical "Critical" "Dismiss explicitly"

QT_QPA_PLATFORM=offscreen quickshell -p quickshell/.config/quickshell/NotificationSmoke.qml
python3 -m unittest discover -s quickshell/.config/quickshell/notifications/tests -p 'test_*.py'
node quickshell/.config/quickshell/notifications/tests/notification_logic.test.js
```

## Rolling back to SwayNC

Stop Quickshell, start `swaync.service`, and restore the two former comma
bindings to `~/.config/hypr/scripts/dnd.sh`. The SwayNC package and its theme
template are still in the repository. Bindings that call `notificationctl` will
not reach SwayNC as written.

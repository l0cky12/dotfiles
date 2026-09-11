# Features

One short walkthrough per major feature — what it is, how you touch it, and
where the deep-dive reference page lives. Every claim here points at a file in
the repository.

## The theme system

A **theme** is a palette file plus everything generated from it. You edit one
palette; a generator script produces the matching colours for the terminal,
kitty, rofi, Quickshell, and the rest. The `theme` command on your PATH applies
one:

```bash
theme set tokyo-night     # apply by slug
theme current             # show the active theme
```

There are 23 palettes shipped in `hypr/.config/hypr/themes/`. The fullscreen
cover-flow picker (`Super+Ctrl+Shift+Space`) and the lmenu **Style → Theme**
rows both end up calling the same `theme set`.

→ Deep dive: [Theming](Theming.md)

## The Quickshell bar and panels

Quickshell is a QML framework for building desktop shells; this setup uses it
for the top bar, the pop-up panels, the clock, and the media visualiser. The
bar (`quickshell/.config/quickshell/Bar.qml`) hosts icons; each icon toggles a
panel via Quickshell IPC (inter-process communication — how keybindings talk
to the running shell):

| Panel | Keybinding |
|---|---|
| Network | `Super+Ctrl+I` |
| Display | `Super+Ctrl+D` |
| Media | `Super+Ctrl+M` |
| Audio | `Super+Ctrl+A` |
| Bluetooth | `Super+Ctrl+B` |
| Clipboard history | `Super+Ctrl+V` |
| Keybindings palette | `Super+K` |
| Theme picker | `Super+Ctrl+Shift+Space` |
| Web app manager | `Super+Alt+A` |

Also on the shell: a **network speed test** overlay (`Super+Alt+T`, backed by
`SpeedTestOverlay.qml`), and — on the Wi-Fi QR branch, not yet on main — the
centred **Share Wi-Fi** QR overlay (`WifiQrOverlay.qml`).

Reload the shell after QML edits with `quickshell ipc call shell reload`
(lmenu → **Update → Config → Reload Quickshell**).

→ Deep dive: [Quickshell shell](Quickshell-Shell.md)

## Desktop modes

**Desktop modes** is the umbrella command (`~/.local/bin/desktop-mode`, Stow
package `modes/`) for session-wide states that interact with idle behaviour:

- **stay awake** — gate the idle lock (`Super+Shift+I`).
- **do-not-disturb** — silence notifications (`Super+Ctrl+,`).

The menu (`Super+Alt+M`) is the friendliest entry point. The system fails
closed: if state is ambiguous, idle locking stays on.

→ Deep dive: [Idle, lock, and desktop modes](Idle-Lock-and-Desktop-Modes.md)

## The notification system

Notifications come from Quickshell's own service rather than a separate daemon
like swaync (the previous one — a rollback path is documented). You get
pop-ups, a history (`Super+Shift+Alt+,`), per-notification actions
(`Super+Alt+,`), and do-not-disturb (`Super+D`). `notificationctl` is the
stable command-line facade; all policy lives in the QML service.

→ Deep dive: [Notifications](Notifications.md)

## lmenu, the menu

`Super+Shift+A` opens **lmenu** — the hub menu. Its tree is one declarative
file, `menu/.config/lmenu/menu.jsonc`: Apps, Development, Learn, Trigger
(capture, share, reminders), Toggle (night light, DND, bar, touchpad…), Style,
Setup, Install, Remove, Update, About, System. Rows can hide themselves when
their command is unavailable (a `when` guard), so the menu reflects your
machine. You can extend it from
`~/.config/lmenu/extensions/menu.jsonc` without touching the repo.

→ Deep dive: [Scripts and CLIs § lmenu](Scripts-and-CLIs.md)

## Scripts on your PATH

The Stow packages drop dozens of small commands into `~/.local/bin`, which
Hyprland's session PATH picks up (`conf/keybindings.lua` also prepends it at
login). Highlights:

- `theme` — apply and inspect themes.
- `lmenu` — the menu itself; `lmenu-reminder` — countdown reminders.
- `desktop-mode` — stay-awake / do-not-disturb state machine.
- `screensaver-lock`, `ascii-screensaver`, `toggle-screensaver` — the lock and
  screensaver pair.
- `hypr-wallpaper-picker` — the wallpaper UI.
- `network-control` — scan, connect, DNS, and Wi-Fi QR from the shell.

→ Deep dive: [Scripts and CLIs](Scripts-and-CLIs.md)

## Keybindings

Hyprland reads its bindings from `hypr/.config/hypr/conf/keybindings.lua` —
Lua, because this setup configures Hyprland through its Lua interface. The
searchable palette (`Super+K`) reads the *live* binding table (`hyprctl binds`)
at open time, so it never lies about what is bound.

→ Deep dive: [Keybindings](Keybindings.md)

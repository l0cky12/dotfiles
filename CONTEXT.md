# Context

Shared vocabulary for this repository. Glossary only: no implementation
details, no decisions, no plans. Those live in the wiki.

## Shell

**Shell** — the Quickshell process. It is the bar, the panels, the notification
daemon, the clipboard browser, the theme picker, and the on-screen displays.
There is exactly one. Waybar, SwayNC and Noctalia are retired; editing them
changes nothing visible.

**Bar** — the reserved strip along the top of each screen. The strip paints
nothing and is transparent; it reserves height so windows tile below it, and it
swallows clicks so nothing behind it can be hit by accident. "The bar" names the
strip, not the things drawn on it.

**Island** — a rounded black capsule floating on the bar, holding a group of
modules. An island is sized to its contents and shrinks when a module hides
itself. There are four, spread to the two edges rather than clustered.

**Module** — one widget inside an island: workspaces, the clock, a status icon.
A module draws no background of its own; the island it sits in carries the
contrast. A module may paint an accent pill over itself to signal state.

**Panel** — a popup opened from a module, anchored under it. Distinct from an
island: an island is always on screen, a panel appears on demand.

**Overlay** — a fullscreen layer that is not anchored to the bar at all: the
keybindings palette, the theme gallery, the clipboard QR.

## Theming

**Palette** — the colour set a theme defines. Lives in
`~/.config/hypr/themes/.active/theme.json`, watched live by `Theme.qml`.

**Role** — a named slot a palette fills (`background`, `accent`, `urgent`). QML
reads roles, never raw colours, so a palette switch repaints everything.

**Generated output** — a file written by a theme generator from a template.
Listed in `.gitignore` and the README. Edit the template or the generator, never
the output.

## Deployment

**Package** — a top-level directory that GNU Stow symlinks into `~`. Every
top-level directory except `docs/`, `wiki/`, `tests/` and `system/` is one.

**Package path** — the in-repo path of a file, such as
`hypr/.config/hypr/hyprland.conf`. The authoritative copy. The live path under
`~/.config` is a symlink to it and is never edited directly.

**Fixture test** — a test in `tests/` that exercises a script or QML component
against stand-in inputs, with no live Hyprland session and no system mutation.

**Smoke** — a `*Smoke.qml` fixture that loads QML headlessly under
`QT_QPA_PLATFORM=offscreen` and asserts on what it built.

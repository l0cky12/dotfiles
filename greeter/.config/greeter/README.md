# greeter

Themed regreet login screen. This package only holds the two files `theme set
<slug>` renders here; nothing in it is meant to be edited or committed.

## What's generated here, and what isn't

| File | Source | Tracked? |
| --- | --- | --- |
| `greeter.css` | `hypr/.config/hypr/theme/templates/greeter-theme.css` | no (gitignored) |
| `regreet.toml` | `hypr/.config/hypr/theme/templates/regreet-greeter.toml` | no (gitignored) |
| `README.md` (this file) | — | yes |
| `.gitkeep` | — | yes, so the directory exists before the first `theme set` |

Edit the templates or `hypr/.config/hypr/theme/generate.py`, never these two
generated files directly -- exactly the same rule as `hyprlock/colors.conf`,
`swaync/style.css` etc. See `docs/themes.md`.

## Setup

```bash
stow greeter hypr
theme set <slug>          # renders ~/.config/greeter/{greeter.css,regreet.toml}
```

That's as far as this package goes on its own: it puts themed files under your
own home directory. Nothing under `/etc` changes, and no display manager
behaviour changes, until you deliberately run the steps below.

## Getting these files onto the login screen

regreet reads `/etc/greetd/regreet.css` and `/etc/greetd/regreet.toml`, not
anything under `~/.config`. Getting the rendered files there is a root-owned
copy, not a symlink or bind mount -- deliberately, so a broken or half-written
home directory can never take out the login screen.

Two ways to do it, both plain `sudo install -m 644`, never touched
automatically by anything in this repo:

```bash
# One-off, after any `theme set`:
sudo install -m 644 ~/.config/greeter/greeter.css  /etc/greetd/regreet.css
sudo install -m 644 ~/.config/greeter/regreet.toml /etc/greetd/regreet.toml

# Or let the theme tool print/run the same two commands:
theme set <slug> --install-greeter             # prompts for sudo once
theme set <slug> --install-greeter --dry-run   # prints the commands, changes nothing
```

`--install-greeter` is **opt-in on purpose**. `theme set` is also invoked with
no terminal attached -- the Quickshell picker, `SUPER+T`/`SUPER+CTRL+SHIFT+SPACE`,
and `theme next`/`previous` -- where a sudo password prompt would just hang.
Leaving it off by default means every one of those existing entry points is
completely unaffected; the flag exists for you to run it yourself, from a
terminal, when you actually want the login screen updated.

**Restart-to-apply caveat:** regreet reads `regreet.css`/`regreet.toml` once,
at greeter startup, not live. Copying new files into `/etc/greetd/` restyles
the *next* time the greeter starts, not the one already on screen. Force it
immediately with `sudo systemctl restart greetd` -- but only from a TTY you are
not currently logged in through (see `system/greetd/README` notes in
`docs/installation.md`), since that kills whatever the greeter is currently
showing on its VT.

## Permissions: the `greeter` system user needs to read your home directory

`system/greetd/config.toml` points regreet's compositor at a config file
stowed under your own home directory
(`~/.config/hypr/conf/greeter/hyprland-greeter.conf`), not at a copy under
`/etc`. greetd runs that command as the dedicated `greeter` system user, whose
home directory is `/`, not yours -- so `greeter` needs read+execute access
through your home directory to reach that one file. Home directories are
normally `700`, which blocks that by default. Grant the minimum via ACLs
instead of loosening your umask:

```bash
sudo setfacl -m u:greeter:x  "$HOME"
sudo setfacl -m u:greeter:x  "$HOME/.config"
sudo setfacl -m u:greeter:x  "$HOME/.config/hypr"
sudo setfacl -m u:greeter:x  "$HOME/.config/hypr/conf"
sudo setfacl -m u:greeter:rx "$HOME/.config/hypr/conf/greeter"
sudo setfacl -m u:greeter:r  "$HOME/.config/hypr/conf/greeter/hyprland-greeter.conf"
```

Verify with `sudo -u greeter cat ~/.config/hypr/conf/greeter/hyprland-greeter.conf`
(run as root, substituting your real home path) before relying on it at boot.

## Known limitation: regreet's layout is fixed

regreet ships one built-in widget layout (see upstream
`src/gui/templates.rs`) -- CSS can only recolour and re-skin the existing
login card, clock badge, entry fields and buttons, not rearrange or replace
them. `greeter-theme.css` targets that fixed hierarchy (GTK's standard
`.suggested-action`/`.destructive-action` button classes, `entry`, `infobar` /
`infobar.error` for the failed-auth state, plus a few `#widget-name` selectors
taken from upstream's Relm4 template) and a few of those id selectors are a
best effort: the type/class rules are the ones this theme actually depends on.
This is a styling boundary, not a bug to work around here.

## Out of scope: a QML greeter

A future custom quickshell/QML greeter (matching the rest of this desktop's
look far more closely than GTK CSS ever can) is a real option, but a
substantially larger, separate project -- it would mean writing and
maintaining a full greetd-facing UI, not just a stylesheet. Not attempted here.

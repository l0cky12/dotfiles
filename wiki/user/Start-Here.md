# Start here

New to this desktop? This page is the short version. It assumes nothing and
explains every term the first time it appears. When you want the full detail,
each section links to a reference page in this wiki.

## What this desktop is

This is an Arch Linux desktop. Arch Linux is a distribution that gives you a
minimal system and expects you to add the pieces you want. The pieces here are
managed as *dotfiles* — plain configuration files kept in a Git repository at
`~/dotfiles` so they can be versioned and reproduced. GNU Stow is the tool that
symlinks those files into your home directory — editing the repository edits
your live desktop, because the file under `~/.config` is a link back into the
repository.

The graphical session itself is Hyprland — a *compositor*, the program that
draws windows, workspaces, and the screen you see — configured in Lua rather
than the more common Hyprland config language. On top of it sits Quickshell, a
framework for building desktop shells in QML, which draws this setup's bar,
pop-up panels, and notifications. The rest is a set of small shell and Python
scripts that the keybindings call.

One paragraph on how to read everything else: the repository also has a
complete reference wiki (the pages linked at the bottom of this page). This
user guide is the plain-English layer on top of it.

## What you get on first login

After deploying with Stow and logging in (see
[Getting started](Getting-Started.md) for those steps), a session starts with:

- A **bar** across the top of the screen, drawn by Quickshell
  (`quickshell/.config/quickshell/Bar.qml`). It shows workspaces, the clock, and
  icons for network, audio, Bluetooth, media, notifications, and more. Clicking
  an icon opens a **panel** — a pop-up window anchored to that icon.
- A **wallpaper** restored from your last choice by the wallpaper restorer
  started in `hypr/.config/hypr/conf/autostart.lua`.
- A **theme** already applied. Themes are generated from palette files by the
  `theme` command; a fresh clone is deliberately incomplete until you run
  `theme set <name>` once (see [Getting started](Getting-Started.md#bootstrap-the-generated-files)).
- **Notifications** handled by Quickshell's own notification service, not a
  separate daemon (see [Notifications](Notifications.md)).
- Applications **pinned to workspaces**: autostart puts apps on workspaces 1,
  2, 3, 4, 6, and 9 (`hypr/.config/hypr/conf/autostart.lua`).

## Two words you will see everywhere

- **Super** (also written `$mainMod` or the Windows key) is the modifier almost
  every keybinding starts with.
- **Workspace** is a virtual desktop. There are 15 here; you switch with
  `Super` + a number.

## The 10 essential keybindings

These all come from the live keybinding file
(`hypr/.config/hypr/conf/keybindings.lua`). Press `Super+K` at any time for a
searchable palette of every binding on the system.

| Keys | What it does |
|---|---|
| `Super+Return` | Open a terminal (kitty). |
| `Super+A` | Open the application launcher — type to search every installed app. |
| `Super+Shift+A` | Open **lmenu**, the big settings-and-actions menu (apps, toggles, themes, Wi-Fi, install, shutdown — everything is in there). |
| `Super+Q` | Close the focused window. |
| `Super+1` … `Super+0` | Jump to workspace 1–10. |
| `Super+arrow keys` | Move focus between windows. |
| `Super+Shift+arrow keys` | Swap the focused window with its neighbour. |
| `Super+K` | Open the searchable keybindings palette. |
| `Super+L` | Lock the screen (hyprlock, wrapped by `screensaver-lock`). |
| `Super+P` | Open the power menu (lock, suspend, reboot, shutdown). |

The full grouped list lives in [Keybindings](Keybindings.md), and for every
binding explained in plain English, see the [Keybindings guide](Keybindings-Guide.md).

## Your first 10 minutes

1. **Look at the bar.** Click each icon once. Every panel closes again with
   `Escape` or by clicking the icon.
2. **Open the keybindings palette** with `Super+K`. It reads the live config
   (`hyprctl binds`) when it opens, so it always matches what is actually
   bound.
3. **Open the menu** with `Super+Shift+A` and browse. The *Learn* section links
   the Hyprland and Arch wikis; *Trigger* holds screenshots, reminders, and
   sharing; *Style* holds themes and wallpapers.
4. **Change the wallpaper** with `Super+Shift+W` (the wallpaper picker).
5. **Pick a theme** with `Super+Ctrl+Shift+Space`. The theme picker is a
   fullscreen cover-flow: type to filter, arrows to browse, and it only
   applies when you press `Enter` — browsing costs nothing.
6. **Take a screenshot** with `Super+Shift+S`. Smart mode freezes the screen;
   drag to grab a region, or plain-click to grab the window under the pointer.
7. When in doubt, open **lmenu** (`Super+Shift+A`) — nearly every action in
   this guide is also a menu row there (`menu/.config/lmenu/menu.jsonc`).

## Where to go next

- [Daily use](user/Daily-Use.md) — recipes for the things you do every day.
- [Features](user/Features.md) — what each part of the desktop is.
- [Fixing things](user/Fixing-Things.md) — when something misbehaves.
- [Getting started](Getting-Started.md) — installing and deploying the dotfiles.
- [Keybindings](Keybindings.md) — every binding, grouped.
- [Troubleshooting](Troubleshooting.md) — technical diagnosis.

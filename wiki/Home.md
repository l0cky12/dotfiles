# dotfiles wiki

A GNU Stow-managed Hyprland desktop for Arch Linux. One compositor, one custom
Quickshell desktop shell, 23 switchable themes generated from a single palette
file each, and a set of shell/Python helpers that back the keybindings.

Everything here describes what is in this repository. Where the repository does
not establish a fact, the page says so rather than guessing at an upstream
default.

## Pages

| # | Page | What it covers |
|---|---|---|
| 1 | [Getting started](Getting-Started.md) | Clone, stow, bootstrap a theme, first login. |
| 2 | [Repository layout](Repository-Layout.md) | Every top-level directory, what it deploys, whether it is active. |
| 3 | [Architecture](Architecture.md) | Config source graph, runtime process graph, tracked vs generated. |
| 4 | [Keybindings](Keybindings.md) | The complete binding reference, grouped by task. |
| 5 | [Customization](Customization.md) | "I want to change X" → the exact file to edit. |
| 6 | [Theming](Theming.md) | The palette system, the generator, adding a theme. |
| 7 | [Hyprland](Hyprland.md) | Entry point, input, window rules, autostart. |
| 8 | [Monitors and workspaces](Monitors-and-Workspaces.md) | EDID-keyed profiles, the hotplug watcher, workspace pinning. |
| 9 | [Quickshell shell](Quickshell-Shell.md) | Bar, panels, IPC targets, the QML component map. |
| 10 | [Notifications](Notifications.md) | The Quickshell notification service, policy, state, `notificationctl`. |
| 11 | [Idle, lock, and desktop modes](Idle-Lock-and-Desktop-Modes.md) | Hypridle timers, Hyprlock, the ASCII screensaver, `desktop-mode`. |
| 12 | [Scripts and CLIs](Scripts-and-CLIs.md) | Every command this repo puts on your `PATH`. |
| 13 | [Security and login](Security-and-Login.md) | greetd/regreet, YubiKey PAM, what is deliberately not in Git. |
| 14 | [Dependencies](Dependencies.md) | What has to be installed, per feature. |
| 15 | [Testing and contributing](Testing-and-Contributing.md) | The fixture test suite and the repo's editing rules. |
| 16 | [Troubleshooting](Troubleshooting.md) | Symptom-first diagnosis. |
| 17 | [Deploying with Ansible](Deploying-with-Ansible.md) | Provisioning a whole machine with `arch-autodepoly`. |

## The 60-second version

The repository lives at `~/dotfiles`. Each top-level directory is a Stow package
whose contents mirror paths under `$HOME`, so `hypr/.config/hypr/hyprland.lua`
becomes `~/.config/hypr/hyprland.lua`.

```bash
sudo pacman -S stow
git clone <repository-url> ~/dotfiles
cd ~/dotfiles

stow hypr hyprlock quickshell rofi kitty cliphist menu modes screensaver \
     browser xdg windows security systemd greeter

theme set tokyo-night     # generates everything .gitignore excludes
```

Log out, log back in. Hyprland reads `~/.config/hypr/hyprland.lua`, which starts
Quickshell, Hypridle, the wallpaper restorer, the clipboard watchers, and the
applications pinned to workspaces 1, 2, 3, 4, 6, and 9.

## Three things that surprise people

1. **Hyprland is configured in Lua, not hyprlang.** `hyprland.lua` is the entry
   point on this machine. A parallel `hyprland.conf` graph still exists as a
   rollback path, but the Lua tree is what a fresh login loads. `hyprctl
   dispatch exec` and `hyprctl keyword` are legacy dispatchers and do nothing
   under it — use `hyprctl eval` instead.

2. **A fresh clone is deliberately incomplete.** Theme output, monitor state,
   and Oh My Zsh are all gitignored or untracked. `theme set <slug>` and
   `auto-monitor-profile.sh --force` materialise the first two; the three Oh My
   Zsh clones in [Getting started](Getting-Started.md) cover the third.

3. **Several paths hardcode `/home/liam`.** `conf/variables.lua`, the browser
   native-host manifests, and the greetd session command all contain it. See
   [Getting started](Getting-Started.md#account-and-machine-assumptions) before
   deploying under a different account.

## Related documents

- [`../README.md`](../README.md) — the feature-first tour, with the full theme
  list and the web-app / Windows VM / browser-tools sections.
- [`../docs/`](../docs/) — the original reference notes this wiki is built from.
- [`../AGENTS.md`](../AGENTS.md) — the editing rules for anyone, human or agent,
  changing files here.

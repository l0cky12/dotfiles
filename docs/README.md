# Dotfiles documentation

> These are the original reference notes. For task-oriented,
> cross-linked pages — including provisioning with Ansible — see the
> [wiki](../wiki/Home.md).

This repository is a GNU Stow-managed Hyprland desktop configuration. Its active
session is centered on Hyprland and a custom Quickshell desktop shell, with
Hyprpaper, Hypridle, Hyprlock, Rofi, Kitty, and a collection of shell/Python
helpers. It also retains alternative or legacy configurations for SwayNC, Wofi,
and Noctalia.

The configuration is personal and machine-aware rather than a distribution-ready
installer. In particular, several paths contain `/home/liam`, the monitor profiles
name specific outputs, and there is no package manifest. Read
[Installation](./installation.md) and [Dependencies](./dependencies.md) before
deploying it on another account or computer.

## Active desktop at a glance

```text
Hyprland
├── Quickshell
│   ├── top bar and workspaces
│   ├── dashboard and control panels
│   ├── notifications
│   ├── clipboard history
│   ├── browser-download progress OSD
│   └── desktop-mode controls and observed-state indicators
├── Rofi application launcher
├── Hyprpaper wallpaper service
├── Hypridle → Hyprlock / DPMS / suspend
├── Hypridle ASCII screensaver listener → fullscreen terminal renderers
├── desktop-mode daemon → timed night-light/DND/stay-awake reconciliation
├── Hyprsunset night light
├── Kitty terminal
├── profile-driven monitor configuration
└── scripts for capture, themes, wallpaper, clipboard, and browser tools
```

The active process list comes from
`hypr/.config/hypr/conf/autostart.lua`. SwayNC, Wofi, and Noctalia are present in
the repository but are not started by the current Hyprland config.

## Repository layout

Most top-level components are Stow packages whose contents mirror paths below
`$HOME`. `docs/`, `wiki/`, `tests/` and `system/` are not: `system/` holds
root-owned `/etc` templates deployed by `yubikey-auth`, never symlinked into
`$HOME`.

| Package | Main purpose |
| --- | --- |
| `hypr/` | Hyprland config, monitor profiles, scripts, capture suite, themes |
| `screensaver/` | ASCII renderer, terminal coordinator, idle scheduler, editable assets |
| `modes/` | temporary desktop-mode CLI, state, adapters, and expiry daemon |
| `quickshell/` | Active bar, panels, notification daemon, clipboard, OSD |
| `hyprlock/` | Lock-screen layouts, generated colors, lock helpers |
| `browser/` | Chromium extensions and native hosts for URL copy/video download |
| `rofi/`, `wofi/` | Active Rofi launcher and retained Wofi launcher config |
| `swaync/` | Retained alternative notification configuration |
| `kitty/` | Terminal configuration and generated theme include |
| `zsh/`, `fastfetch/`, `ai/` | Shell, prompt/startup display, AI CLI launcher |
| `cliphist/` | Clipboard-history limits |
| `noctalia/` | Retained Noctalia settings and plugin data |
| `xdg/` | MIME defaults and a Kitty/Neovim desktop entry |
| `wallpaper/` | Tracked wallpaper assets; stow into `~/Pictures/wallpapers` |
| `tests/` | Browser native-tool fixture tests |

## Documentation

- [Installation and deployment](./installation.md)
- [Architecture and configuration graph](./architecture.md)
- [Hyprland configuration](./hyprland.md)
- [ASCII screensaver](./screensaver.md)
- [Desktop modes and stay-awake](./desktop-modes.md)
- [Keybindings](./keybindings.md)
- [Monitors and workspaces](./monitors.md)
- [Desktop components](./components.md)
- [Scripts and command-line tools](./scripts.md)
- [Themes and appearance](./themes.md)
- [Dependencies](./dependencies.md)
- [Customization](./customization.md)
- [Troubleshooting](./troubleshooting.md)

## Intended audience

These notes assume basic Linux and shell knowledge. They are written both for the
repository owner and for someone adapting the files to a different Arch/Wayland
machine. Behaviors are described from the tracked files; where the repository does
not establish a fact, the documentation says so rather than substituting a
Hyprland default.

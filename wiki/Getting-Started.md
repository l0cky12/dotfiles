# Getting started

## What deployment means here

Every top-level directory except `docs/`, `tests/`, `wiki/`, and `system/` is a
GNU Stow package. Stow symlinks a package's contents into `$HOME`, preserving the
directory structure below the package root:

```text
hypr/.config/hypr/hyprland.lua   →   ~/.config/hypr/hyprland.lua
modes/.local/bin/desktop-mode    →   ~/.local/bin/desktop-mode
```

Because the deployed files are symlinks back into the clone, editing the
repository changes the live desktop immediately. You only re-run `stow` when a
package gains or loses files.

There is no `install.sh`, Makefile, or package manifest in this repository.
Installing Arch packages and configuring the system is manual — or handled by the
separate playbook described in [Deploying with Ansible](Deploying-with-Ansible.md).

## Prerequisites

```bash
sudo pacman -S stow
```

Read [Dependencies](Dependencies.md) first and install at least the applications
belonging to the packages you intend to deploy. Hyprland will start without most
of them, but the features bound to them will not.

## Clone

```bash
git clone <repository-url> ~/dotfiles
cd ~/dotfiles
```

The repository must live at `~/dotfiles`. The `wallpaper` package's alternate
target, the Ansible playbook, and several comments all assume that path.

## Before you stow

1. Back up or move anything already at `~/.config`, `~/.local/bin`, and
   `~/.local/share/applications`. Stow reports a conflict rather than merging.
2. Search the tree for `/home/liam` if you are deploying under another account.
   The important occurrences are listed [below](#account-and-machine-assumptions).
3. Look at [Monitors and workspaces](Monitors-and-Workspaces.md). The shipped
   profiles name specific Dell panels by EDID string.

Preview any selection before committing to it:

```bash
stow --simulate --verbose hypr quickshell
```

## Deploy

The active desktop needs these:

```bash
stow hypr hyprlock quickshell rofi kitty cliphist menu modes screensaver \
     browser xdg windows security systemd greeter
```

Optional shell and startup display:

```bash
stow zsh fastfetch ai
```

Retained alternatives, only if you intend to switch to them:

```bash
stow swaync wofi noctalia
```

Wallpapers are the one package that does not target `$HOME`. Its files sit at the
package root, so deploy it into the picker's default directory instead:

```bash
stow --target="$HOME/Pictures/Wallpapers" wallpaper
```

To remove a package: `stow -D hypr`.

> **Never stow `docs/`, `tests/`, `wiki/`, or `system/`.** `system/` holds
> root-owned `/etc` templates that `yubikey-auth` and `system/greetd/install.sh`
> deploy; stowing it would create `~/greetd` and `~/pam.d`.

## Oh My Zsh is not in this repository

It cannot be. Oh My Zsh's own `.gitignore` excludes `custom/`, so no submodule or
gitlink here could carry the Powerlevel10k theme or the `fzf-tab` plugin that
`.zshrc` loads from `$ZSH_CUSTOM`. `zsh/.oh-my-zsh/` is gitignored for the same
reason. Install all three before stowing `zsh`:

```bash
omz_installer="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
  --output "$omz_installer"
sha256sum "$omz_installer"
printf '%s\n' 'Compare this SHA-256 with a checksum obtained through a trusted channel.'
less "$omz_installer"  # Inspect the complete script before continuing.
sh "$omz_installer" "" --unattended
rm -f "$omz_installer"

(
# REQUIRED: fill these with reviewed 40-character commits from the linked
# upstream repositories. The placeholder values fail closed. Review each at
# https://github.com/romkatv/powerlevel10k/commit/<sha> and
# https://github.com/Aloxaf/fzf-tab/commit/<sha> before using it.
POWERLEVEL10K_PIN='<REPLACE_WITH_REVIEWED_40_CHARACTER_COMMIT_SHA>'
FZF_TAB_PIN='<REPLACE_WITH_REVIEWED_40_CHARACTER_COMMIT_SHA>'
: "${POWERLEVEL10K_PIN:?Set POWERLEVEL10K_PIN to a reviewed upstream commit}"
: "${FZF_TAB_PIN:?Set FZF_TAB_PIN to a reviewed upstream commit}"
[[ $POWERLEVEL10K_PIN =~ ^[0-9a-fA-F]{40}$ ]] || exit 1
[[ $FZF_TAB_PIN =~ ^[0-9a-fA-F]{40}$ ]] || exit 1
git clone --no-checkout https://github.com/romkatv/powerlevel10k.git \
  ~/.oh-my-zsh/custom/themes/powerlevel10k
git -C ~/.oh-my-zsh/custom/themes/powerlevel10k checkout --detach \
  "$POWERLEVEL10K_PIN"
git clone --no-checkout https://github.com/Aloxaf/fzf-tab.git \
  ~/.oh-my-zsh/custom/plugins/fzf-tab
git -C ~/.oh-my-zsh/custom/plugins/fzf-tab checkout --detach "$FZF_TAB_PIN"
)
```

`source $ZSH/oh-my-zsh.sh` failing on every prompt means this step was skipped.

## Bootstrap the generated files

A fresh clone is intentionally missing every generated file. Two commands
materialise them.

**Theme output** — Hyprland decorations, Kitty/Rofi/Hyprlock colours, the
Quickshell active palette, and the rest:

```bash
theme set tokyo-night
```

**Monitor and workspace state** — `monitors.lua` and `workspaces.lua` are
untracked machine state written from a profile:

```bash
~/.config/hypr/scripts/auto-monitor-profile.sh --force
```

Do not hand-write either set of outputs. Both are overwritten. Edit the palette
or the monitor profile instead. See [Theming](Theming.md) and
[Monitors and workspaces](Monitors-and-Workspaces.md).

## Enable the monitor hotplug watcher

The watcher is a systemd user unit, and stowing it does not enable it:

```bash
stow systemd
systemctl --user daemon-reload
systemctl --user enable --now hypr-monitor-watch.service
```

## Optional: Windows VM

Stow `windows` alongside `hypr`, then complete Docker access yourself. The helper
diagnoses missing setup but never calls sudo:

```bash
sudo systemctl enable --now docker.service
sudo usermod -aG docker liam
# log out and back in, then:
docker info
windows-vm install
```

Defaults on this machine are 8 GiB RAM, four CPU cores, and a 128 GiB disk. The
installer confirms resources and credentials before downloading anything.

## Optional: browser extensions

The `browser` package installs unpacked Manifest V3 extensions, flag files,
native-host manifests, and the native executables. The checked-in manifests use
absolute `/home/liam` paths, so another account has to update them before the
hosts resolve. Close the browser completely and reopen it after stowing. See
[Scripts and CLIs](Scripts-and-CLIs.md#browser-native-tools).

## Account and machine assumptions

These are not portable without review:

| Assumption | Where it appears |
| --- | --- |
| `/home/liam/.config/hypr/scripts` | `conf/variables.lua`, and therefore most bindings and autostart lines |
| `/home/liam/.config/hypr/conf/greeter/hyprland-greeter.conf` | `system/greetd/config.toml`'s `[default_session]`, plus an ACL grant for the `greeter` user |
| `~/Pictures/Wallpapers` | wallpaper picker default; override with `HYPR_WALLPAPER_DIR` |
| `/home/liam/.config/hypr/scripts/capture/capture.sh` | Quickshell recording state |
| `/home/liam` native-host paths | browser manifests and browser flag files |
| DP/eDP connector names and exact modes | monitor profiles |
| Personal VPN and GAM paths | `zsh/.zshrc` |
| Location, display, and network state | retained `noctalia/` settings |

No credentials or private keys are required by the active desktop. The repository
does carry personal path assumptions, so review it before publishing a fork.

## Updating

Edit repository paths, never the live symlink targets. Change
`hypr/.config/hypr/conf/keybindings.lua`, not `~/.config/hypr/conf/keybindings.lua`
— they are the same file, but only one of them is what Git sees.

How a change takes effect depends on the component; see
[Customization](Customization.md#applying-changes).

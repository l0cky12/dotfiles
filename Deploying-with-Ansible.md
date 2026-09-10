# Deploying with Ansible

Stowing this repository configures a desktop. It does not install one. The
companion playbook **`arch-autodepoly`** takes a fresh Arch Linux machine and
turns it into a working workstation: it creates the account, full-upgrades the
system, installs the packages this repo's scripts and bindings actually call,
builds the AUR and Cargo pieces, enables Docker and libvirt, clones *this* repo
and deploys every approved Stow package, themes the boot and login screens, then
hardens SSH, UFW, and fail2ban in an order designed so you cannot lock yourself
out halfway through.

| | |
|---|---|
| Repository | `github.com/fhlkfds/arch-autodepoly` |
| Local checkout | `~/Projects/arch-autodepoly` |
| Roles | `users`, `packages`, `boot`, `docker`, `dotfiles`, `greeter`, `ssh`, `ufw`, `fail2ban`, `verification` |
| Deploys | `github.com/fhlkfds/dotfiles`, branch `main`, into `/home/liam/dotfiles` |

Its package inventory was derived from this repository at commit
`e834654` on 2026-09-06, and it still clones `main` — so review what has changed
here before a later run.

> There is a second, older playbook at `~/hyprland-ansible-dotfiles`
> (`github.com/l0cky12/hyprland-ansible-dotfiles`, last commit 2026-07-02) that
> also deploys this repo. This page documents `arch-autodepoly`, which is the
> current one.

## How the pieces relate

```
  CONTROLLER                                 TARGET
  your machine                               the workstation being built
  ┌────────────────────────┐                 ┌────────────────────────────┐
  │ arch-autodepoly        │ ──── SSH ─────▶ │ pacman, yay, systemctl,    │
  │   site.yml             │                 │ /etc files, ...            │
  │   inventory/hosts.ini  │                 │                            │
  │   group_vars/all/      │                 │ git clone fhlkfds/dotfiles │
  └────────────────────────┘                 │        ↓                   │
                                             │ stow --no-folding × 22     │
                                             └────────────────────────────┘
```

Nothing is installed on the target beyond SSH and Python. The playbook clones
this dotfiles repository *onto the target* and runs Stow there.

## Prerequisites

### On the controller

```bash
sudo pacman -S --needed ansible git openssh
cd ~/Projects/arch-autodepoly
ansible-galaxy collection install -r requirements.yml
```

`requirements.yml` pins `ansible.posix >= 2.1.0` and
`community.general >= 13.0.0`.

### On the target

1. Arch Linux, installed and bootable, **x86_64**. The playbook asserts the
   architecture, because this repo's `install-ttfx` pins
   `x86_64-unknown-linux-musl`.
2. A `liam` account you can already SSH into. The playbook creates and
   normalizes that account, but it has to log in as somebody first.
3. Console access retained for the first run.

Python is *not* a prerequisite. A guarded `raw` task installs it before fact
gathering — see [The bootstrap](#the-python-bootstrap).

## Configure the vault

```bash
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
$EDITOR group_vars/all/vault.yml
ansible-vault encrypt group_vars/all/vault.yml
```

| Variable | Requirement |
| --- | --- |
| `vault_liam_password_hash` | A crypt(3)-compatible hash, never a plain password. `scripts/make-password-hash.py` generates one. Omit it and the password task is skipped, and the final report says so. |
| `vault_liam_authorized_key` | Your SSH public key. May be omitted only when a valid key already exists in `/home/liam/.ssh/authorized_keys`. |
| `vault_admin_ip` | **Required.** fail2ban will not start until this IP or CIDR is in `ignoreip`. For a remote target, use the public source address the host sees — not the target's own address. |

`group_vars/all/vault.yml` is gitignored. The playbook's top-level `README.md`
still refers to the older `group_vars/vault.yml` path; the loaded one is
`group_vars/all/`.

If the controller needs a specific private key for the fresh SSH checks, set
`ssh_validation_identity_file` **outside** the vault to its local path. Ansible
never copies or prints the private key.

## Inventory

```ini
[arch_workstation]
workstation ansible_host=192.168.122.122 ansible_user=liam
```

Test the connection by hand before invoking Ansible:

```bash
ssh liam@192.168.122.122
```

For a non-default port, add `-p PORT` to `ssh` and `ansible_port=PORT` to the
inventory.

## Run it

```bash
ansible-playbook --syntax-check site.yml
ansible-playbook site.yml --ask-become-pass --ask-vault-pass --check --diff
ansible-playbook site.yml --ask-become-pass --ask-vault-pass --diff
```

Expect **30–90 minutes** on the real run: a full system upgrade, AUR builds, and
a Rust binary compiled from source. It may reboot the target once, deliberately,
when a kernel upgrade replaces the running kernel's module tree.

Keep your current SSH session open and keep console access.

Check mode cannot prove AUR builds, Docker, a service restart, firewall
reachability, or a new SSH connection. The real run performs all of those.

### The Python bootstrap

The first play starts with `gather_facts: false`. A guarded `raw` task installs
the official `python` package with a full `pacman -Syu`, resets the connection,
and only then gathers facts. This is required on a minimal Arch host where
`/usr/bin/python3` does not exist yet, and check mode cannot avoid it — use a
real run with `--ask-become-pass`.

Two assertions follow immediately: the host must be `Archlinux`, and the
architecture must be `x86_64`.

### Tags

`users`, `packages`, `boot`, `docker`, `dotfiles`, `greeter`, `ssh`, `ufw`,
`fail2ban`, `verification`.

`users` also carries `always`, because every other role depends on the account
and group state existing.

Do not run `ufw` or `fail2ban` alone — both need the SSH role's discovered port
and its successful key check.

```bash
# redeploy just the dotfiles after pushing a change here
ansible-playbook site.yml --tags dotfiles --ask-become-pass --ask-vault-pass --diff
```

## What each role does

### `users`

Creates the `liam` group and the workstation groups (`wheel`, `video`, `audio`,
`input`, `storage`, `optical`, `lp`), creates the account with `/usr/bin/zsh` as
its shell, installs a validated sudoers rule, and asserts `wheel` membership.

It does **not** set the password here. That is the very last task of the last
play, because `update_password: always` rewrites `/etc/shadow` and would
invalidate the `--ask-become-pass` value Ansible is using for sudo. Anywhere
earlier and every subsequent `become` fails on a half-provisioned host.

### `packages`

The big one. Full `pacman -Syu`, then roughly 107 official packages and 12 AUR
packages, plus:

- **libvirt** enabled and started, `liam` added to the `libvirt` group, and the
  `qemu:///system` URI verified as the administrator — so `virt-manager`, which
  this repo autostarts on workspace 6, can actually connect.
- **tailscaled** enabled and started. The machine is *not* enrolled in a tailnet;
  run `sudo tailscale up` from the workstation when you are ready.
- A validated **doas** rule, because this repo's `.zshrc` aliases `sudo` to
  `doas`.
- **yay**, built from source as `liam` when absent.
- **Oh My Zsh, Powerlevel10k, and fzf-tab**, cloned from their upstream
  repositories with `force: false`. These cannot live in the dotfiles repo — see
  [Getting started](Getting-Started.md#oh-my-zsh-is-not-in-this-repository).
- **`ttfx`**, which is in neither the official repositories nor the AUR. The role
  follows this repo's `install-ttfx` route: build the upstream Git source with
  Cargo for `x86_64-unknown-linux-musl`, pinned to an inspected commit, then
  verify `~/.local/bin/ttfx` is static.
- **XDG user directories** and `~/.local/bin`.
- A **kernel-module check**: if the upgrade replaced the running kernel's module
  tree, the role reboots and re-verifies before any later role runs.

AUR failures are reported and skipped rather than halting the run, because a
PKGBUILD can break for reasons nothing in either repository can fix. Set
`aur_fail_hard: true` to make any missing AUR package stop the play.

### `boot`

Silences the boot console and installs the frieren GRUB theme.

This host boots a unified kernel image, so the cmdline is baked into the image
from `/etc/kernel/cmdline` — editing `/etc/default/grub` alone changes nothing.
The role writes both and rebuilds the UKI. Parameters apply at the next boot.

Set `boot_quiet: false` to keep the console verbose while debugging.

The `grub.cfg` backup goes to `/var/lib/arch-autodeploy/grub.cfg.previous`
rather than beside the file, because `/boot` is a vfat EFI partition that rejects
the colons in Ansible's timestamped backup names.

### `docker`

Installs Engine, Compose, and Buildx. Verifies the nftables control plane before
Docker creates NAT rules, adds `liam` to the root-equivalent `docker` group,
reconnects so the membership is live in the session, enables the service, and
runs a `hello-world` smoke test as `liam`.

This is what makes `windows-vm` and `docker-dev-env` usable without the manual
setup described in [Dependencies](Dependencies.md#windows-vm).

### `dotfiles`

The role that deploys this repository.

1. Clone or fast-forward `fhlkfds/dotfiles@main` into `~/dotfiles` as `liam`,
   with `force: false`. Local changes are never overwritten.
2. Run `roles/dotfiles/files/stow_manifest.py` to build a canonical manifest
   from the tracked package files, and record which targets need changing and
   which conflict.
3. Move **only conflicting** targets into `~/dotfiles-backup-<timestamp>/`,
   preserving relative paths, at mode 0700. A target that already points into
   `~/dotfiles` is left alone.
4. `stow --no-folding --target ~ <package>` for each of the 22 packages.
5. Rebuild the manifest and **assert** that every tracked package file resolves
   into the checkout.

`--no-folding` makes every managed file an individually verifiable symlink,
which is what lets step 5 be an assertion rather than a hope. A correct folded
directory link from an older Stow run is also accepted.

The 22 packages: `ai browser cliphist fastfetch greeter hypr hyprlock kitty menu
modes noctalia quickshell rofi screensaver security swaync systemd wallpaper
windows wofi xdg zsh`.

`docs`, `tests`, and `system` are excluded on purpose: `system` holds root-owned
greetd and PAM examples, and the playbook's login screen is SDDM rather than
greetd anyway. `wiki/` postdates the playbook's inventory, so it is simply not in
the list — which is the correct outcome, but add it to the excluded set
explicitly if you ever regenerate that list.

> **One divergence worth knowing.** The playbook stows `wallpaper` to `$HOME`
> like every other package, so its files land directly in the home directory.
> This repository's own instructions deploy it with
> `stow --target="$HOME/Pictures/wallpapers" wallpaper`, which is where the
> picker looks by default. If you want the picker to find them after an Ansible
> run, either re-stow that one package by hand or set `HYPR_WALLPAPER_DIR`.

### `greeter`

The login screen is SDDM with a theme from
[qylock](https://github.com/Darkkal44/qylock) (GPL-3.0), selected by
`sddm_theme` (default `star-rail`).

qylock's own `sddm.sh` is interactive, so the role does what that script does
instead of running it: copy `themes/<name>` into `/usr/share/sddm/themes/` and
write `[Theme] Current` into `/etc/sddm.conf.d/theme.conf` — the same path
qylock writes, so running the upstream script later replaces this file rather
than silently shadowing it.

The upstream repository is roughly 1.1 GB because every theme carries its own
video and image assets, so only the selected theme is fetched, with a blobless
sparse checkout — about 25 MB.

Some themes expect a font qylock cannot redistribute. The role reports where to
drop it, and the theme falls back to a default font until you do.

`sddm_display_server` defaults to `wayland`, which is why `weston` is installed
to host the greeter. Set it to `x11` and add `xorg-server` if a theme misbehaves.

The role also:

- Hides the uwsm-managed Hyprland session entry, so the greeter defaults to plain
  Hyprland.
- Runs `theme set <greeter_theme_slug>` (default `tokyo-night`) if no theme has
  ever been rendered. Nothing else in the playbook does, and skipping it would
  leave a fresh box with no theme at all. An existing choice always wins.
- Disables greetd before enabling SDDM, because `systemctl enable sddm` fails
  while greetd still owns the `display-manager.service` alias.

It never stops a running display manager, so switching on a live machine takes
effect at the next reboot.

**greetd is not force-removed.** `greetd`, `greetd-regreet`, and
`greetd-tuigreet` were dropped from `official_packages` when the login manager
changed, but a host that already has them keeps a working fallback:
`systemctl disable sddm && systemctl enable greetd`, then reboot. That is the
path back to this repository's own
[greetd/regreet login screen](Security-and-Login.md#the-login-screen).

### `ssh`, `ufw`, `fail2ban`

These run as separate plays with `serial: 1`, and the ordering is the whole
point.

`ssh` installs your authorized key, **refuses to disable password authentication
without one**, proves a fresh key-authenticated connection *before* hardening,
installs a validated drop-in at
`/etc/ssh/sshd_config.d/99-ansible-hardening.conf`, validates the whole config
with `sshd -t` before restarting, then proves a fresh connection again.

The firewall play will not start at all unless `admin_ips` is set and every entry
is a bare IPv4 address or CIDR. `ufw` rate-limits the discovered SSH port
*before* enabling the policy, sets deny-in / allow-out, opens LocalSend on
53317/tcp+udp for `localsend_source_ranges` only, then proves SSH again.

`fail2ban` refuses to run without the whitelist, installs an nftables-backed sshd
jail with `admin_ips` in `ignoreip`, validates the config before touching the
service, and asserts the jail is active.

SSH key login is proved four times in total: before password auth is disabled,
after the `sshd` restart, after UFW is enabled, and once more in verification.

### `verification`

Prints a pass/fail table followed by unedited command output for user and group
state, sudoers, doas, yay, every configured package, Docker, the effective SSH
policy plus a fresh key connection, UFW, fail2ban, and the key Stow links. A
failed assertion stops the play, so a PASS table only ever appears after every
check has succeeded.

The Stow assertion resolves seven canonical targets — `.zshrc`, `hyprland.lua`,
`shell.qml`, `kitty.conf`, `desktop-mode`, `ascii-screensaver`, and
`hypr-monitor-watch.service` — through direct or folded links and requires each
to land inside the checkout.

## The finished machine has no SSH server

`ssh_enabled` defaults to `false`. The `ssh` role installs and proves the
hardened `sshd` during the run, and then the **final task of the final play**
stops and disables it and removes its UFW allowance. Nothing listens on the SSH
port afterwards.

A remote run therefore works once, over the sshd that is already up, but cannot
open a new connection afterwards. Recover at the console:

```bash
systemctl enable --now sshd
ufw limit <port>/tcp
```

or run with `-e ssh_enabled=true` to leave it up.

Arch's `sshd.service` sets `KillMode=process`, so stopping the unit leaves the
established Ansible session intact and those final tasks still report back. This
host is not socket-activated, so disabling `sshd.service` is sufficient.

## Idempotency

```bash
scripts/prove-idempotency.sh inventory/hosts.ini --ask-become-pass --ask-vault-pass
```

Runs the playbook twice, saves both transcripts under `artifacts/`, and fails
unless the second recap reports `changed=0`, `unreachable=0`, and `failed=0`.

Pass `-e ssh_enabled=true` when you run it. Enabling sshd for the checks and
disabling it again is a change on every run **by design**, so the default would
never report zero.

Additional targeted tests: `tests/dotfiles-idempotency.yml`,
`tests/libvirt-connection.test.sh`, `tests/tailscale-install.test.sh`,
`tests/wallhaven-link.test.sh`.

## What the playbook deliberately leaves to you

Hardware enrollment and account authentication are untouched. It installs the
PAM U2F tools but does **not** enrol a YubiKey or deploy this repo's
`system/pam.d` examples — see
[Security and login](Security-and-Login.md#yubikey-authentication).

It also does not:

- authenticate Spotify, browsers, AI agents, VPNs, or the Windows VM;
- generate machine-specific monitor profiles (run
  `auto-monitor-profile.sh --force` and then
  [capture your layout](Monitors-and-Workspaces.md#changing-the-layout));
- enable the Stowed `hypr-monitor-watch.service` user unit — Stow places it, the
  playbook does not activate it, so run
  `systemctl --user enable --now hypr-monitor-watch.service` yourself;
- install the external GAM directory `.zshrc` references;
- install the Codex CLI, which has no exact official or AUR package in the
  checked repositories — the `ai` launcher will report it missing.

Only `docker.service`, `sddm.service`, `ufw.service`, `fail2ban.service`,
`libvirtd.service`, and `tailscaled.service` are left enabled. No desktop,
NetworkManager, or Wayland service is enabled by the playbook.

## Recovery

| Problem | Fix |
| --- | --- |
| Fresh key check failed | The firewall roles never ran. From a root console, remove `/etc/ssh/sshd_config.d/99-ansible-hardening.conf`, validate with `sshd -t`, restart `sshd.service`. |
| Locked out by UFW | `ufw disable` from the console. |
| fail2ban banning you | `systemctl disable --now fail2ban`; UFW stays up. |
| Stow conflict | Restore from the reported `~/dotfiles-backup-<timestamp>/` after `stow -D` on the owning package. |
| Quiet boot hides a failure | Edit the kernel cmdline from the bootloader for one boot, or set `boot_quiet: false` and rerun `--tags boot`. Both `/etc/kernel/cmdline` and `/etc/default/grub` are backed up in place. |
| SDDM misbehaving | `systemctl disable sddm && systemctl enable greetd`, then reboot. |

## Manual equivalent

`docs/LOCAL-SOP.md` in that repository translates the whole playbook into shell
commands for one PC acting as both controller and target — no SSH inventory, no
second machine, no Ansible at all. Its section numbering maps one-to-one onto the
roles above.

# Security and login

Everything with a security boundary lives in two places: the `security` Stow
package, and `system/` — which is **not** a Stow package, because its contents
belong in `/etc`.

## What is deliberately not in Git

- **The registered YubiKey credential.** It is machine-specific and lives in
  `/etc/u2f_mappings`, where it is readable before the user session or home
  directory is unlocked. Never commit it.
- **Windows VM credentials**, which stay at mode 0600 under `~/.config/windows`.
- **Docker dev-environment credentials**, generated on first start into
  `$XDG_STATE_HOME/docker-dev-env/environment.env` at mode 0600.
- **Clipboard history**, which is unencrypted at `~/.cache/cliphist/db`.
  `clipboard-store.sh` filters secrets and excluded applications before storing,
  and `clipboard-wipe.sh` clears it.
- **Wi-Fi passwords.** The network panel hands secured connections to an
  interactive `nmtui` prompt so the password never crosses the panel boundary,
  and the Wi-Fi QR is rendered at runtime rather than written to disk.

No credentials or private keys are required by the active desktop configuration.

## `system/` is not stowable

```text
system/
├── greetd/
│   ├── config.toml      greetd's own config, pointing at the regreet greeter
│   └── install.sh       dry-run-by-default installer
└── pam.d/
    ├── sudo
    ├── doas
    └── hyprlock
```

Stowing this directory would create `~/greetd` and `~/pam.d`, which is useless.
`system/greetd/install.sh` and `yubikey-auth` are what deploy these files.

## The login screen

greetd is the display manager, and is expected to already be installed and
enabled. `system/greetd/config.toml` only changes *which greeter* it launches.

`[default_session]` does not start your desktop directly. It starts a minimal,
throwaway Hyprland instance — configured by
`hypr/.config/hypr/conf/greeter/hyprland-greeter.conf`, which is stowed with the
`hypr` package and has no keybinds, no decorations, and no autostart beyond
regreet itself. That instance runs the regreet GTK4 greeter and exits. Once you
authenticate, regreet execs whichever session you picked from
`/usr/share/wayland-sessions/`, normally `hyprland.desktop`
(`Exec=/usr/bin/start-hyprland`).

That indirection is why `hyprland.lua` prepends `~/.local/bin` to `PATH`:
`start-hyprland` never sources `~/.zshrc`, so without it every Stow package's
entry point would be missing from a binding's environment.

### Deploying it

```bash
system/greetd/install.sh            # report only, changes nothing
system/greetd/install.sh --apply    # copy config.toml into /etc/greetd/
```

The installer also checks that the `greeter` system user and `hyprland.desktop`
exist, and backs up any existing `/etc/greetd/config.toml`.

**Do not restart greetd from inside the graphical session.** Let it take effect
at the next reboot, or restart it deliberately from a TTY you are not using.
`install.sh` prints the exact enable/restart command for the machine's current
state rather than running it.

`greetd-tuigreet` stays installed as the rescue path. If regreet fails to start,
restore `/etc/greetd/config.toml.pre-regreet` — written automatically by
`install.sh` the first time — and restart greetd.

### Theming the greeter

regreet reads `/etc/greetd/regreet.css` and `/etc/greetd/regreet.toml`, not
anything under `~/.config`. The theme system renders both into the `greeter`
package first:

```bash
stow greeter hypr
theme set <slug>          # renders ~/.config/greeter/{greeter.css,regreet.toml}
```

That is as far as the package goes on its own. Getting them onto the login
screen is a deliberate, root-owned copy — not a symlink or bind mount, so a
broken or half-written home directory can never take out the login screen:

```bash
theme set <slug> --install-greeter --dry-run   # print the sudo install commands
theme set <slug> --install-greeter             # run them
```

This is the only part of the theme system that needs root, which is why it is
opt-in and never fires from the picker or a keybinding.

The `greeter` package also needs a one-time ACL grant so the `greeter` system
user can read the stowed greeter Hyprland config out of your home directory. See
`greeter/.config/greeter/README.md`.

Both generated files are gitignored. Edit
`hypr/.config/hypr/theme/templates/greeter-theme.css` and
`regreet-greeter.toml` instead.

## YubiKey authentication

The `security` package provides `yubikey-auth`, a guarded setup command for the
YubiKey Bio, sudo, doas, and Hyprlock. It never stores the registered credential
in Git and keeps password authentication as the final fallback.

### Why both sudo and doas

`.zshrc` aliases `sudo` to `doas`. A PAM stack installed only to `/etc/pam.d/sudo`
would never be reached by the command actually typed, so both are deployed.

Both key rules use `sufficient`, so initial greetd login and password recovery
remain unchanged. The order per attempt is: enrolled fingerprint, then the FIDO
PIN, then the account password.

### Normal setup

```bash
stow security
yubikey-auth status
yubikey-auth setup --enroll-fingerprint
```

For an additional key, leave only the new one inserted:

```bash
yubikey-auth add --enroll-fingerprint
```

| Command | Behaviour |
| --- | --- |
| `status` | tools, visible tokens, mapping presence, deployed-template state |
| `setup --enroll-fingerprint` | enrol a fingerprint, create the first mapping, back up `/etc` targets, stage sudo before Hyprlock |
| `add --enroll-fingerprint` | append another Bio credential to the existing single mapping line |
| `add --mode pin` | register a non-biometric FIDO2 key with PIN verification |
| `setup\|add --dry-run` | detect and report without changing the key, the mapping, or PAM |

Use `--device /dev/hidrawN` when several keys are attached. Automatic detection
fails closed rather than guessing.

`setup` installs and tests sudo first, then waits for the exact confirmation
string `INSTALL HYPRLOCK` before deploying the lock-screen stack. Generated
credentials are held in a mode-0700 temporary directory, validated before
installation, and removed on exit.

Zsh aliases, defined only when the names are otherwise unused: `yubi`,
`yubi-status`, `yubi-setup`, `yubi-add`. The last two include fingerprint
enrollment.

### The relying-party identifier

The templates use `pam://Kelper`. Registration must use the same origin and app
ID, or the credential will not match.

### Manual recovery

If you need to do this by hand, keep a root shell open in a separate terminal
(`sudo -s`) throughout.

Locate the key and enrol a fingerprint if none is listed. These prompt locally
for the FIDO PIN — never paste that PIN into a shell command or a chat:

```bash
key_device=$(fido2-token -L | awk -F: '/Yubico YubiKey FIDO/ { print $1; exit }')
test -n "$key_device"
fido2-token -L -e "$key_device"

# only when no suitable fingerprint is listed
fido2-token -S -e "$key_device"
```

Generate and validate a user-verifying credential before touching PAM:

```bash
u2f_tmp=$(mktemp -p /tmp liam-u2f-mapping.XXXXXX)
chmod 600 "$u2f_tmp"
pamu2fcfg -u liam -o pam://Kelper -i pam://Kelper -V > "$u2f_tmp"
awk -F: 'NR == 1 && $1 == "liam" && NF == 2 && $2 ~ /,/ { ok = 1 } END { exit !(NR == 1 && ok) }' "$u2f_tmp"
sudo cp -a /etc/u2f_mappings /etc/u2f_mappings.pre-yubikey
sudo install -o root -g root -m0600 "$u2f_tmp" /etc/u2f_mappings
rm -f "$u2f_tmp"
```

Deploy and test both escalation stacks. Do **not** install the Hyprlock template
until the key path and the password path have both succeeded:

```bash
sudo cp -a /etc/pam.d/sudo /etc/pam.d/sudo.pre-yubikey
sudo install -o root -g root -m0644 system/pam.d/sudo /etc/pam.d/sudo
sudo cp -a /etc/pam.d/doas /etc/pam.d/doas.pre-yubikey
sudo install -o root -g root -m0644 system/pam.d/doas /etc/pam.d/doas

sudo -k;  sudo -v     # touch the inserted key
doas -L;  doas true   # touch the inserted key

# remove the key, then confirm the password still works for both
sudo -k;  sudo -v
doas -L;  doas true
```

Only then:

```bash
sudo cp -a /etc/pam.d/hyprlock /etc/pam.d/hyprlock.pre-yubikey
sudo install -o root -g root -m0644 system/pam.d/hyprlock /etc/pam.d/hyprlock
```

At the lock screen, press Enter on the empty input and use an enrolled finger.
Test the PIN fallback, then test the account password with the key removed. PAM
files are read on each attempt, so no greetd restart or reboot is needed. If any
path fails, restore the matching `.pre-yubikey` file from the retained root
shell.

Requires `pam-u2f` (including `pamu2fcfg`) and `libfido2`. Fingerprints are
enrolled with `fido2-token`, so `yubikey-manager` is not needed.

## GnuPG

`security/.config/gnupg-conf/` holds example `gpg.conf` and `gpg-agent.conf`
templates with one-hour SSH-key caching. Copy them into `~/.gnupg/` manually as
described in that directory's `README.md`. Interactive Zsh sessions export
`SSH_AUTH_SOCK` to the matching `gpg-agent` socket.

## Other boundaries worth knowing

- **Docker group membership is effectively root-equivalent.** `windows-vm` and
  `docker-dev-env` both need it, and both diagnose its absence rather than
  calling sudo themselves.
- **`.zshrc` aliases `sudo` to `doas`.** Anything you read here about `sudo`
  reaches the doas PAM stack on this machine.
- **The RDP endpoint is loopback-only**, which is the reason `/cert:ignore` is
  acceptable there and nowhere else.
- **Native messaging hosts are pinned to exact extension IDs**, so an arbitrary
  extension cannot invoke the clipboard or downloader executables.
- **The DND bypass list is audited.** It requires both an allow-listed app name
  and an explicit local hint; urgency alone never bypasses DND.

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
  `clipboard-store.sh` filters password-manager MIME markers and sensitive
  applications before storing, history is capped at 200 text/image entries,
  and the Hyprlock wrapper clears it on lock.
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

The `security` package provides `yubikey-auth`, a guarded setup command wiring
a FIDO2 key into sudo, doas, and optionally Hyprlock. It never stores the
registered credential in Git and keeps password authentication as the final
fallback.

### What the key can actually verify with

The mode is chosen from `fido2-token -I`, not from the USB product ID.
`product=0x0402` is the plain FIDO interface and is shared by keys that have no
fingerprint sensor, so keying off it sent sensorless hardware into Bio
enrollment and `fido_bio_dev_enroll_begin: FIDO_ERR_INVALID_COMMAND`.

| Mode | Registered with | Needed at each sign-in |
| --- | --- | --- |
| `touch` | neither flag | a touch |
| `bio` | `-V` | the key's own fingerprint |
| `pin` | `-N` | the key's FIDO PIN |
| `auto` | — | `bio` when the key reports `bioEnroll`, else `touch` |

`yubikey-auth status` prints a `verification:` line per token saying which of
these the hardware can offer. Requesting a mode the key cannot do fails with a
message naming the limit rather than a raw libfido2 error.

The key attached to this host reports `options: rk, up, noplat, clientPin,
credentialMgmtPreview` — no `bioEnroll`, no `uv` — so it resolves to `touch`.

### Why both sudo and doas

`.zshrc` aliases `sudo` to `doas`. A PAM stack installed only to `/etc/pam.d/sudo`
would never be reached by the command actually typed, so both are deployed.

Both key rules use `sufficient`, so initial greetd login and password recovery
remain unchanged. Enter the account password normally. To use the key, submit
an empty prompt, then touch it when prompted. The password is checked by the
usual system stack before success is returned.

### Normal setup

Open `SUPER+SHIFT+A` > Setup > Security > YubiKey for status, first-key setup,
additional-key setup, removal of the last registered key, prerequisites, and
this recovery guide. Each entry finishes with a ✅ or ❌ line and then waits
for Enter, so the output of a failed run stays on screen instead of the
window closing or leaving a bare shell.

```bash
stow security
yubikey-auth status
yubikey-auth setup
```

For an additional key, leave only the new one inserted:

```bash
yubikey-auth add
```

| Command | Behaviour |
| --- | --- |
| `status` | tools, visible tokens, per-token verification options, mapping presence, deployed-template state |
| `setup` | create the first mapping, back up `/etc` targets, deploy sudo and doas |
| `add` | append another credential to the existing single mapping line |
| `remove` | after confirmation, back up the mapping and remove its last credential; no key needs to be plugged in |
| `setup --with-hyprlock` | additionally deploy the lock-screen stack, behind the `INSTALL HYPRLOCK` checkpoint |
| `setup\|add --mode pin` | require the key's FIDO PIN at every authentication |
| `setup\|add --mode bio --enroll-fingerprint` | enrol and require a fingerprint on a key that has a sensor |
| `setup\|add\|remove --dry-run` | report without changing the key, the mapping, or PAM |

Use `--device /dev/hidrawN` when several keys are attached. Automatic detection
fails closed rather than guessing.

Generated credentials are held in a mode-0700 temporary directory, validated
before installation, and removed on exit.

Zsh aliases, defined only when the names are otherwise unused: `yubi`,
`yubi-status`, `yubi-setup`, `yubi-add`.

### Why Hyprlock is opt-in

A touch-only credential proves the key is plugged in, not who pressed it. On
sudo and doas that is a reasonable trade at a machine you are already sitting
at. On the lock screen it removes the lock: anyone walking up can tap the key
and get in. `setup` therefore leaves `/etc/pam.d/hyprlock` alone and prints how
to opt in, and `status` reports that state as `pam: password only` rather than
as an incomplete setup. `--with-hyprlock` is worth using once the credential
requires the key's own fingerprint or PIN.

If the key already has a FIDO PIN, registration may prompt for it once. That is
libfido2 unlocking the key to create the credential; `-N` is what would make
the credential itself PIN-protected, and touch mode does not pass it.

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
pamu2fcfg -u liam -o pam://Kelper -i pam://Kelper > "$u2f_tmp"
awk -F: 'NR == 1 && $1 == "liam" && NF == 2 && $2 ~ /,/ { ok = 1 } END { exit !(NR == 1 && ok) }' "$u2f_tmp"
sudo cp -a /etc/u2f_mappings /etc/u2f_mappings.pre-yubikey
sudo install -o root -g root -m0600 "$u2f_tmp" /etc/u2f_mappings
rm -f "$u2f_tmp"
```

Deploy and test both escalation stacks. The Hyprlock template is optional and
should stay uninstalled while the credential is touch-only:

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

Only if you have decided to accept a tap as enough to unlock the screen:

```bash
sudo cp -a /etc/pam.d/hyprlock /etc/pam.d/hyprlock.pre-yubikey
sudo install -o root -g root -m0644 system/pam.d/hyprlock /etc/pam.d/hyprlock
```

At the lock screen, press Enter on the empty input and touch the key, then test
the account password with the key removed. PAM files are read on each attempt,
so no greetd restart or reboot is needed. If any path fails, restore the
matching `.pre-yubikey` file from the retained root shell.

Requires `pam-u2f` (including `pamu2fcfg`) and `libfido2`. Fingerprints, on a
key that has a sensor, are enrolled with `fido2-token`, so `yubikey-manager` is
not needed.

## Host fingerprint sign-in

Two different things in this repository are called "fingerprint", and it is
worth keeping them apart:

| | Sensor | Enrolled by | Authenticated by |
| --- | --- | --- | --- |
| `yubikey-auth --enroll-fingerprint` | on a YubiKey Bio token, which the key attached here is not | `fido2-token -S -e` | `pam_u2f.so` with `userverification=1` |
| `fingerprint-auth` | built into the laptop | `fprintd-enroll` | Hyprlock's fprintd client; sudo/doas/greetd PAM |

`fingerprint-auth` is for the second. It applies to laptops with a reader — the
Goodix sensor in a Framework 13 power button — and reports that there is
nothing to do on any host without one, which is how the shared desktops in this
configuration see it.

```bash
fingerprint-auth status   # reader, tools, enrolled prints, Hyprlock wiring
fingerprint-auth setup    # install fprintd, enroll, configure Hyprlock and PAM
```

`Setup → Security → Fingerprint` in the Super+Shift+A menu runs `setup` in a
terminal that stays open, and the entry is hidden unless the command is on
`PATH`.

### Hyprlock and PAM

Hyprlock speaks to fprintd directly and runs the scan beside the password
field, so `setup` flips `auth { fingerprint:enabled }` in
`hypr/.config/hypr/hyprlock.conf`. It also installs the fingerprint PAM
templates for sudo, doas, and greetd. Setup pauses for escalation tests before
installing greetd. `--no-pam` leaves system PAM alone.

Prints live in `/var/lib/fprint/`, are host-local, and are never in Git — the
same boundary as `/etc/u2f_mappings`. Requires `fprintd`, which is in the
`optional` setup group. When it is missing on a host with a reader, `setup`
installs it through doas, or sudo when doas is absent, after pacman's own
confirmation prompt.

## GnuPG

`security/.config/gnupg-conf/` holds example `gpg.conf` and `gpg-agent.conf`
templates. The agent template uses five-minute GnuPG and SSH defaults, capped
at 30 and 15 minutes respectively, so short workflows remain usable without
leaving approvals available for an hour. Copy them into `~/.gnupg/` manually as
described in that directory's `README.md`. Interactive Zsh sessions export
`SSH_AUTH_SOCK` to the matching `gpg-agent` socket.

For software-backed SSH keys, add `KEYGRIP 0 confirm` to
`~/.gnupg/sshcontrol` to require Pinentry confirmation on every use while
retaining the global cache TTL. Smart-card keys continue to rely on their
hardware touch/PIN policy. Run `gpgconf --kill gpg-agent` before lock or logout
to flush approvals. As with the repository's manual `clipboard-wipe.sh`, this
is documented local policy rather than an automatic hook: lock routing lives in
`screensaver-lock` and Hypridle, outside the security package.

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

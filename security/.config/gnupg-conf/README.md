# GnuPG configuration examples

These files are templates, not a Stow-managed `~/.gnupg` path. Copy them only
when you want the SSH agent and cache behavior described below:

```sh
umask 077
install -d -m 700 ~/.gnupg
install -m 600 gpg-agent.conf ~/.gnupg/gpg-agent.conf
install -m 600 gpg.conf ~/.gnupg/gpg.conf
gpgconf --kill gpg-agent
```

`gpg-agent` starts lazily on the next GnuPG, SSH, or interactive Zsh request.
After it starts, list the SSH-compatible public keys with `ssh-add -L`.

The template caches GnuPG approvals for five minutes, capped at 30 minutes even
when use resets the shorter timer. SSH approvals use the same five-minute
default with a 15-minute cap. This is a middle ground: short related operations
do not prompt continuously, but an unattended same-session process gets a much
smaller reuse window than a session-long cache.

To let `gpg-agent` manage an OpenPGP authentication key (not needed for a
YubiKey/smartcard auth key, which gpg-agent exposes automatically), obtain its
keygrip with `gpg --list-keys --with-keygrip` — only the authentication-capable
(`[A]`) subkey's grip belongs here — then add this line to
`~/.gnupg/sshcontrol`:

```text
KEYGRIP 0 confirm
```

The zero keeps the global SSH TTL, rather than disabling caching, and `confirm`
requires Pinentry approval for every SSH use. `ssh-add -c` also requests this
flag when adding a key. Smart-card authentication keys are exposed implicitly
and retain their configured hardware touch/PIN policy.

When a host has access to many keys, use SSH `IdentitiesOnly yes` plus an
explicit `IdentityFile` or `IdentityAgent` entry so authentication does not
iterate every available key.

Flush all cached approvals before leaving a session unattended:

```sh
gpgconf --kill gpg-agent
```

For lock/logout automation, run that command immediately before the existing
lock entry points (`screensaver-lock` or `loginctl lock-session`) or session
termination. This repository leaves that as an explicit local policy, matching
the manual `clipboard-wipe.sh` precedent; the security package does not own a
lock hook. The agent starts lazily again when it is next needed.

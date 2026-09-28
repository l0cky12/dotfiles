# Optional shortcuts for the `security` Stow package. Never replace an existing
# command, function, or alias with the same name.
if (( $+commands[yubikey-auth] )); then
  whence -w yubi >/dev/null 2>&1 || alias yubi='yubikey-auth'
  whence -w yubi-status >/dev/null 2>&1 || alias yubi-status='yubikey-auth status'
  whence -w yubi-setup >/dev/null 2>&1 || alias yubi-setup='yubikey-auth setup'
  whence -w yubi-add >/dev/null 2>&1 || alias yubi-add='yubikey-auth add'
fi

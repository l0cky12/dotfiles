#!/usr/bin/env bash
# Deploys system/greetd/config.toml (this repo's source of truth) to
# /etc/greetd/config.toml so greetd launches regreet under a minimal Hyprland
# instance. Dry-run by default: prints every command it would run and exits.
# Pass --apply to actually copy anything or touch systemd state.
#
# This script never enables, starts, or restarts greetd -- see docs/installation.md
# for the approval-gated commands to run manually once this has been applied.
set -euo pipefail

PROGRAM=${0##*/}
script_path=$(readlink -f -- "${BASH_SOURCE[0]}")
script_dir=$(cd -- "$(dirname -- "$script_path")" && pwd)

ETC_ROOT=${GREETD_INSTALL_ETC_ROOT:-/etc}
CONFIG_SRC="$script_dir/config.toml"
CONFIG_DEST="$ETC_ROOT/greetd/config.toml"
BACKUP_DEST="$CONFIG_DEST.pre-regreet"
WAYLAND_SESSION=${GREETD_INSTALL_WAYLAND_SESSION:-/usr/share/wayland-sessions/hyprland.desktop}
GREETER_HYPR_CONF=${GREETD_INSTALL_GREETER_CONF:-/home/liam/.config/hypr/conf/greeter/hyprland-greeter.conf}

APPLY=false
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=true ;;
    -h|--help)
      cat <<EOF
Usage: $PROGRAM [--apply]

Without --apply (default): report what would change, touch nothing.
With --apply: copy config.toml into $CONFIG_DEST (root, mode 644), backing up
any existing file to $BACKUP_DEST the first time only.

Never enables, starts, or restarts greetd -- that stays a separate, explicit
step. See docs/installation.md.
EOF
      exit 0
      ;;
    *) printf '%s: unknown argument: %s\n' "$PROGRAM" "$arg" >&2; exit 2 ;;
  esac
done

note()  { printf '%s\n' "$*"; }
warn()  { printf '%s: warning: %s\n' "$PROGRAM" "$*" >&2; }
fail()  { printf '%s: error: %s\n' "$PROGRAM" "$*" >&2; exit 1; }

[[ -f "$CONFIG_SRC" ]] || fail "missing $CONFIG_SRC"

note "== checks =="

if getent passwd greeter >/dev/null 2>&1; then
  note "ok    greeter system user exists"
else
  warn "no 'greeter' system user found -- the greetd package normally creates one on install"
fi

if [[ -f "$WAYLAND_SESSION" ]]; then
  note "ok    $WAYLAND_SESSION exists"
else
  warn "$WAYLAND_SESSION not found -- confirm the Hyprland package installed its session file"
fi

if [[ -f "$GREETER_HYPR_CONF" ]]; then
  note "ok    $GREETER_HYPR_CONF exists (stow greeter + hypr first if this is missing)"
else
  warn "$GREETER_HYPR_CONF not found yet -- stow the 'hypr' package (it carries" \
       "conf/greeter/hyprland-greeter.conf) before greetd starts using this config,"
  warn "or set GREETD_INSTALL_GREETER_CONF if this machine's home directory differs"
fi

if command -v pacman >/dev/null 2>&1; then
  if pacman -Qi greetd-regreet >/dev/null 2>&1; then
    note "ok    greetd-regreet is installed"
  else
    warn "greetd-regreet is not installed -- 'sudo pacman -S greetd greetd-regreet greetd-tuigreet'"
  fi
fi

note ""
note "== plan =="
if [[ -f "$CONFIG_DEST" ]] && ! diff -q "$CONFIG_SRC" "$CONFIG_DEST" >/dev/null 2>&1; then
  if [[ -f "$BACKUP_DEST" ]]; then
    note "skip  $BACKUP_DEST already exists, leaving it as the pre-regreet backup"
  else
    note "would back up existing $CONFIG_DEST -> $BACKUP_DEST"
  fi
fi
note "would run: install -o root -g root -m 644 $CONFIG_SRC $CONFIG_DEST"

if [[ "$APPLY" != true ]]; then
  note ""
  note "Dry run only -- nothing changed. Re-run with --apply to install."
  exit 0
fi

note ""
note "== applying =="
if [[ -f "$CONFIG_DEST" ]] && ! diff -q "$CONFIG_SRC" "$CONFIG_DEST" >/dev/null 2>&1; then
  if [[ -f "$BACKUP_DEST" ]]; then
    note "skip  $BACKUP_DEST already exists, leaving it as the pre-regreet backup"
  else
    sudo cp -a "$CONFIG_DEST" "$BACKUP_DEST"
    note "backed up $CONFIG_DEST -> $BACKUP_DEST"
  fi
fi
sudo install -o root -g root -m 644 "$CONFIG_SRC" "$CONFIG_DEST"
note "installed $CONFIG_DEST"

note ""
note "== not run automatically =="
if systemctl is-enabled greetd >/dev/null 2>&1; then
  note "greetd.service is already enabled on this machine. The new config takes"
  note "effect on its next start. To apply now (this ends whatever session is"
  note "currently on greetd's VT -- switch to another VT first):"
  note "    sudo systemctl restart greetd"
else
  note "greetd.service is not enabled. To use it as the display manager:"
  note "    sudo systemctl enable greetd.service"
  note "Test it first without enabling, on its own VT:"
  note "    sudo systemctl start greetd"
fi
note ""
note "Rollback: restore the backup and restart/re-enable as above:"
note "    sudo cp -a $BACKUP_DEST $CONFIG_DEST"

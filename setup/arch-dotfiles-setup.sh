#!/usr/bin/env bash
# Post-archinstall setup for this repository. No reboot is ever performed.
set -Eeuo pipefail
IFS=$'\n\t'
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DRY_RUN=0; USER_NAME=""; SETUP_GROUPS=(core hyprland); HARDEN_SSH=0; CONFIG_UFW=0; CONFIG_DOCKER=0; CONFIG_IOMMU=0; YES=0
STAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="(stdout; dry-run is filesystem-immutable)"
say(){ printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"; }
run(){ if ((DRY_RUN)); then say "DRY-RUN: $*"; else "$@"; fi; }
confirm(){ ((YES)) && return 0; ((DRY_RUN)) && return 1; read -r -p "$1 [y/N] " a; [[ $a == y || $a == Y ]]; }
usage(){ cat <<EOF
Usage: $0 [--user NAME] [--group NAME ...] [--ssh-hardening] [--ufw] [--docker-forwarding] [--iommu] [--yes] [--dry-run]
Groups: core hyprland desktop-apps virtualization docker optional. Root invocation requires --user.
EOF
}
while (($#)); do case $1 in --user) USER_NAME=$2; shift 2;; --group) SETUP_GROUPS+=("$2"); shift 2;; --ssh-hardening) HARDEN_SSH=1; shift;; --ufw) CONFIG_UFW=1; shift;; --docker-forwarding) CONFIG_DOCKER=1; shift;; --iommu) CONFIG_IOMMU=1; shift;; --yes) YES=1; shift;; --dry-run) DRY_RUN=1; shift;; -h|--help) usage; exit 0;; *) usage >&2; exit 2;; esac; done
# Deliberately do not create logs or temporary files in dry-run mode.
if (( ! DRY_RUN )); then
  if [[ -w /var/log ]]; then LOG_DIR=/var/log/arch-dotfiles-setup; else LOG_DIR="${TMPDIR:-/tmp}/arch-dotfiles-setup"; fi
  mkdir -p "$LOG_DIR"; LOG_FILE="$LOG_DIR/setup-$STAMP.log"; exec > >(tee -a "$LOG_FILE") 2>&1
fi
if [[ $EUID -eq 0 ]]; then [[ -n $USER_NAME ]] || { say 'ERROR: root invocation requires --user'; exit 2; }; else USER_NAME=${USER_NAME:-${SUDO_USER:-$USER}}; fi
id "$USER_NAME" >/dev/null 2>&1 || { say "ERROR: unknown user $USER_NAME"; exit 2; }
HOME_DIR=${HOME_DIR_OVERRIDE:-$(getent passwd "$USER_NAME" | cut -d: -f6)}; [[ -d $HOME_DIR ]] || exit 2
# Deduplicate while preserving selection order.
declare -A seen=(); groups=(); for g in "${SETUP_GROUPS[@]}"; do [[ ${seen[$g]+x} ]] || { seen[$g]=1; groups+=("$g"); }; done
for g in "${groups[@]}"; do [[ -f "$ROOT/setup/manifests/$g.txt" ]] || { say "ERROR: unknown group $g"; exit 2; }; done
backup(){ local f=$1; [[ -e $f || -L $f ]] || return 0; local b="${f}.bak.${STAMP}"; run cp -a -- "$f" "$b"; say "Backup: $b"; }
pkgs=(); for g in "${groups[@]}"; do while read -r p; do [[ -z $p || $p == \#* ]] || pkgs+=("$p"); done < "$ROOT/setup/manifests/$g.txt"; done
run pacman -Syu --needed "${pkgs[@]}"
stow_packages=(hypr hyprlock kitty quickshell menu modes screensaver cliphist dots systemd rofi wofi swaync fastfetch zsh xdg)
if command -v stow >/dev/null; then
  for d in "${stow_packages[@]}"; do
    [[ -d $ROOT/$d ]] || continue
    # Back up every unmanaged conflict before Stow mutates anything. Include
    # regular files, symlinks, and directories (directory conflicts are not
    # reported by a file-only scan). A destination is backed up at most once.
    declare -A backed_up=()
    while IFS= read -r -d '' src; do
      rel=${src#"$ROOT/$d/"}; dst="$HOME_DIR/$rel"
      if [[ -e $dst || -L $dst ]]; then
        managed=0
        if [[ -L $dst ]]; then
          target=$(readlink -f -- "$dst" 2>/dev/null || true)
          [[ $target == "$src" ]] && managed=1
        fi
        if (( ! managed )) && [[ ! ${backed_up[$dst]+x} ]]; then
          backup "$dst"
          backed_up[$dst]=1
        fi
      fi
    done < <(find "$ROOT/$d" -mindepth 1 -print0)
    run stow --dir="$ROOT" --target="$HOME_DIR" --no-folding "$d"
  done
else say 'WARN: stow not installed; deployment skipped'; fi
if [[ ${groups[*]} == *optional* ]]; then say 'Optional group selected'; fi
if command -v yay >/dev/null; then :; else
  say 'yay not found; bootstrap is explicit and non-root.'
  if confirm 'Build yay from Arch User Repository using makepkg?'; then
    # shellcheck disable=SC2016 # $1 is expanded by the target user's shell.
    if ((DRY_RUN)); then say 'DRY-RUN: would clone and build yay as target user'; else tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; run git clone https://aur.archlinux.org/yay.git "$tmp/yay"; run chown -R "$USER_NAME":"$(id -gn "$USER_NAME")" "$tmp"; run runuser -u "$USER_NAME" -- bash -c 'cd -- "$1" && makepkg -si --needed' bash "$tmp/yay"; fi
  else say 'WARN: yay bootstrap declined'; fi
fi
if ((HARDEN_SSH)); then
  if confirm 'Apply SSH hardening (preserves keys and authorized_keys)?'; then backup /etc/ssh/sshd_config; run install -d -m 0755 /etc/ssh/sshd_config.d; run install -m 0644 "$ROOT/setup/ssh/hardening.conf" /etc/ssh/sshd_config.d/99-arch-dotfiles-hardening.conf; run sshd -t; fi
fi
if ((CONFIG_UFW)); then
  if confirm 'Configure UFW (deny incoming, allow outgoing, SSH port, TCP 53317)?'; then backup /etc/ufw/user.rules; backup /etc/ufw/user6.rules; run ufw default deny incoming; run ufw default allow outgoing; port=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}'); run ufw allow "${port:-22}/tcp"; run ufw allow 53317/tcp; run ufw --force enable; fi
fi
if ((CONFIG_DOCKER)) && confirm 'Apply Docker forwarding policy (DOCKER-USER allows established, denies other forwarding)?'; then
  # Replace our two rules at the head: Docker's terminal RETURN makes an
  # appended DROP unreachable. Repeated setup must not accumulate rules.
  while iptables -C DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; do
    run iptables -D DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    ((DRY_RUN)) && break
  done
  while iptables -C DOCKER-USER -j DROP 2>/dev/null; do
    run iptables -D DOCKER-USER -j DROP
    ((DRY_RUN)) && break
  done
  run iptables -I DOCKER-USER 1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  run iptables -I DOCKER-USER 2 -j DROP
fi
GRUB_FILE=${GRUB_FILE:-/etc/default/grub}
if ((CONFIG_IOMMU)) && [[ -f $GRUB_FILE ]]; then
  vendor=$(awk -F ': *' '/^vendor_id[[:space:]]*:/ {print $2}' "${CPU_INFO_FILE:-/proc/cpuinfo}" | sort -u)
  if [[ $vendor == AuthenticAMD || $vendor == GenuineIntel ]]; then
    param=iommu=pt
    [[ $vendor != GenuineIntel ]] || param='intel_iommu=on iommu=pt'
    old=$(< "$GRUB_FILE")
    new=$(GRUB_TEXT="$old" PARAM="$param" python3 -c 'import os,re; s=os.environ["GRUB_TEXT"]; q=os.environ["PARAM"]; m=re.search(r"^GRUB_CMDLINE_LINUX_DEFAULT=\"([^\"]*)\"",s,re.M); assert m; opts=m.group(1).split(); opts += [x for x in q.split() if x not in opts]; print(s[:m.start(1)]+" ".join(opts)+s[m.end(1):],end="")')
    diff=$(diff -u <(printf '%s\n' "$old") <(printf '%s\n' "$new") || true)
    if [[ -n $diff ]]; then printf '%s\n' "$diff"; else say 'GRUB already contains requested parameters; no change.'; fi
    if [[ -n $diff ]] && confirm 'Apply the exact GRUB diff above and regenerate GRUB config?'; then backup "$GRUB_FILE"; if ((DRY_RUN)); then say "DRY-RUN: would write $GRUB_FILE"; else printf '%s\n' "$new" > "$GRUB_FILE"; fi; run grub-mkconfig -o /boot/grub/grub.cfg; fi
  else
    say 'WARN: CPU vendor is ambiguous or unsupported; IOMMU skipped safely'
  fi
elif ((CONFIG_IOMMU)); then say 'WARN: /etc/default/grub absent; IOMMU skipped'; fi
say "Completed (no reboot). Log: $LOG_FILE"

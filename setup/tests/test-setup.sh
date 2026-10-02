#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
s="$root/setup/arch-dotfiles-setup.sh"
bash -n "$s"
user=${SUDO_USER:-${USER:-$(id -un)}}
[[ $(bash "$s" --help) == *'--dry-run'* ]]
[[ $(bash "$s" --user "$user" --dry-run --group nope >/dev/null 2>&1; printf '%s' "$?") != 0 ]]

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/home/.config/hypr" "$t/home/.config/kitty"
printf '# fixture directory\n' > "$t/home/.config/hypr/local.conf"
printf 'fixture\n' > "$t/home/.config/kitty/local.conf"
ln -s "$t/missing-target" "$t/home/.config/hypr/hyprland.lua" # broken symlink conflict
printf '#!/usr/bin/env bash\nexit 0\n' > "$t/bin/stow"
# shellcheck disable=SC2016 # This is the fixture's source, not this shell.
printf '#!/usr/bin/env bash\nif [[ $1 == -T ]]; then printf "port 2222\\n"; else exit 1; fi\n' > "$t/bin/sshd"
chmod +x "$t/bin/stow" "$t/bin/sshd"
printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet rootflags=subvol=@ cryptdevice=UUID=test:root"\nGRUB_DISABLE_OS_PROBER=false\n' > "$t/grub"
printf 'vendor_id : AuthenticAMD\n' > "$t/cpuinfo"

# The complete setup path is dry-run only: no pacman, Stow, firewall, Docker,
# SSH, GRUB, log, backup, or initramfs mutation may occur.
before=$(find "$t/home" -printf '%P|%y|%s\n' | sort)
out=$(PATH="$t/bin:$PATH" HOME_DIR_OVERRIDE="$t/home" GRUB_FILE="$t/grub" CPU_INFO_FILE="$t/cpuinfo" TMPDIR="$t/tmp" bash "$s" --user "$user" --dry-run --yes --group core --group core --ssh-hardening --ufw --docker-forwarding --iommu 2>&1)
after=$(find "$t/home" -printf '%P|%y|%s\n' | sort)
[[ "$before" == "$after" ]]
grep -q 'DRY-RUN: pacman' <<<"$out"
grep -q 'DRY-RUN: stow' <<<"$out"
for package in quickshell menu modes screensaver cliphist dots systemd; do
  grep -qx -- "$package" <<<"$out"
done
grep -q 'Backup: .*\.config/hypr' <<<"$out" # directory conflict
grep -q 'Backup: .*\.config/hypr/hyprland\.lua\.bak\.' <<<"$out" # broken symlink conflict
# Shared base directories are containers, not conflicts: never copied whole.
if grep -Eq 'Backup: .*/home/\.(config|local)\.bak\.' <<<"$out"; then exit 1; fi
# Active SSH port and required application port are both planned.
grep -q '2222/tcp' <<<"$out"
grep -q '53317/tcp' <<<"$out"
grep -q 'DOCKER-USER' <<<"$out"
grep -q 'DROP' <<<"$out"
grep -q 'rootflags=subvol=@ cryptdevice=UUID=test:root iommu=pt' <<<"$out"
if grep -q 'vfio\|mkinitcpio\|initramfs' <<<"$out"; then exit 1; fi

printf 'vendor_id : GenuineIntel\n' > "$t/cpuinfo"
# Intel is independent and idempotent: both parameters are appended once.
printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"\n' > "$t/grub"
out=$(PATH="$t/bin:$PATH" HOME_DIR_OVERRIDE="$t/home" GRUB_FILE="$t/grub" CPU_INFO_FILE="$t/cpuinfo" bash "$s" --user "$user" --dry-run --yes --iommu 2>&1)
grep -q 'GRUB already contains requested parameters' <<<"$out"
if grep -q '^+GRUB_CMDLINE_LINUX_DEFAULT=' <<<"$out"; then exit 1; fi

# Declining every prompt is safe and must not create backups or logs.
mkdir -p "$t/empty"
: > "$t/decline.out"
before=$(find "$t" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)
PATH="$t/bin:$PATH" HOME_DIR_OVERRIDE="$t/empty" TMPDIR="$t/tmp" GRUB_FILE="$t/missing-grub" bash "$s" --user "$user" --dry-run --ssh-hardening --ufw --docker-forwarding --iommu >"$t/decline.out" 2>&1 || true
after=$(find "$t" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)
[[ "$before" == "$after" ]]

# Safety-sensitive commands remain mandatory where requested; optional failures
# are warnings, and logging never contains secret/key material.
grep -q 'run sshd -t' "$s"
if ! command -v yay >/dev/null; then
  grep -q 'WARN: yay bootstrap declined' "$t/decline.out"
fi
if grep -Eqi 'BEGIN (OPENSSH|RSA) PRIVATE KEY|authorized_keys' "$t/decline.out"; then exit 1; fi
if command -v shellcheck >/dev/null 2>&1; then shellcheck "$s"; else printf 'shellcheck unavailable (not installed); skipped\n'; fi
printf 'setup tests passed\n'

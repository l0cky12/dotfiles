#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/hypr/.config/hypr/scripts/vm-preset"
templates="$repo_root/hypr/.config/hypr/vm-presets"
menu="$repo_root/menu/.config/lmenu/menu.jsonc"
test_root=$(mktemp -d -t vm-preset.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]"; }
assert_not_contains() { ! grep -Fq -- "$2" "$1" || fail "$1 contains [$2]"; }

password='correct horse S3cret!'
bin=$test_root/bin
calls=$test_root/calls
domains=$test_root/domains
injected=$test_root/injected
mirror=$test_root/mirror
mkdir -p "$bin" "$test_root/home/.ssh" "$test_root/tmp" "$injected" "$mirror" "$test_root/uuids"
: >"$calls"
printf 'debian13\ndebian13-docker-1\n' >"$domains"

# A tiny stand-in ISO and a SHA512SUMS that lists it among other images.
iso_name=debian-13.9.0-amd64-netinst.iso
printf 'fixture iso\n' >"$mirror/$iso_name"
{
  printf '%s  debian-edu-13.9.0-amd64-netinst.iso\n' "$(printf 'edu' | sha512sum | cut -d' ' -f1)"
  (cd "$mirror" && sha512sum "$iso_name")
} >"$mirror/SHA512SUMS"
printf 'signature\n' >"$mirror/SHA512SUMS.sign"

cat >"$bin/virsh" <<'SH'
#!/usr/bin/env bash
printf 'virsh %s\n' "$*" >>"$VM_TEST_CALLS"
[[ $1 == -c && $2 == qemu:///system ]] || exit 3
shift 2
domain=${2:-}
[[ $1 != domblklist ]] || domain=$3
[[ ! -f $VM_TEST_UUIDS/$domain ]] || domain=$(<"$VM_TEST_UUIDS/$domain")
case $1 in
  dominfo) grep -Fxq "$domain" "$VM_TEST_DOMAINS" ;;
  net-info) printf 'Name:           default\nActive:         %s\n' "${VM_TEST_NET:-yes}" ;;
  domblklist)
    printf ' Type   Device   Target   Source\n'
    printf ' file   disk     vda      /var/lib/libvirt/images/%s.qcow2\n' "$domain"
    printf ' file   cdrom    sda      /cache/netinst.iso\n'
    ;;
  destroy) ;;
  undefine)
    grep -Fxv "$domain" "$VM_TEST_DOMAINS" >"$VM_TEST_DOMAINS.tmp" || true
    mv "$VM_TEST_DOMAINS.tmp" "$VM_TEST_DOMAINS"
    ;;
  *) exit 4 ;;
esac
SH

cat >"$bin/virt-install" <<'SH'
#!/usr/bin/env bash
printf 'virt-install %s\n' "$*" >>"$VM_TEST_CALLS"
name= uuid=
while (($#)); do
  case $1 in
    --name) name=$2; shift ;;
    --uuid) uuid=$2; shift ;;
    --initrd-inject) cp -- "$2" "$VM_TEST_INJECTED/"; ls -l "$2" >>"$VM_TEST_INJECTED/modes" ;;
  esac
  shift
done
printf '%s\n' "$name" >>"$VM_TEST_DOMAINS"
[[ -z ${VM_TEST_COLLISION:-} ]] || exit 1
printf '%s\n' "$name" >"$VM_TEST_UUIDS/$uuid"
exit "${VM_TEST_INSTALL_EXIT:-0}"
SH

cat >"$bin/virt-manager" <<'SH'
#!/usr/bin/env bash
printf 'virt-manager %s\n' "$*" >>"$VM_TEST_CALLS"
SH

# Answers by prompt. VM_TEST_NAME unset accepts the pre-filled default;
# "__cancel__" presses Escape.
cat >"$bin/rofi" <<'SH'
#!/usr/bin/env bash
prompt= filter=
while (($#)); do
  case $1 in
    -p) prompt=$2; shift ;;
    -filter) filter=$2; shift ;;
  esac
  shift
done
cat >/dev/null
printf 'rofi %s\n' "$prompt" >>"$VM_TEST_CALLS"
case $prompt in
  'VM name') answer=${VM_TEST_NAME-$filter} ;;
  Password) answer=$VM_TEST_PASSWORD ;;
  Confirm) answer=${VM_TEST_CONFIRM-$VM_TEST_PASSWORD} ;;
  'Install host SSH key?') answer=${VM_TEST_SSH:-Yes} ;;
  *) exit 5 ;;
esac
[[ $answer == __cancel__ ]] && exit 1
printf '%s\n' "$answer"
SH

cat >"$bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf 'notify %s\n' "$*" >>"$VM_TEST_CALLS"
SH

# Serves files from the fixture mirror; VM_TEST_CORRUPT spoils the ISO.
cat >"$bin/curl" <<'SH'
#!/usr/bin/env bash
output= url=
while (($#)); do
  case $1 in
    -o) output=$2; shift ;;
    -*) ;;
    *) url=$1 ;;
  esac
  shift
done
printf 'curl %s\n' "$url" >>"$VM_TEST_CALLS"
file=$VM_TEST_MIRROR/${url##*/}
[[ -f $file ]] || exit 22
cp -- "$file" "$output"
if [[ -n ${VM_TEST_CORRUPT:-} && $output == *.iso ]]; then printf 'x' >>"$output"; fi
SH

cat >"$bin/gpg" <<'SH'
#!/usr/bin/env bash
case ${VM_TEST_GPG:-valid} in
  valid) printf '[GNUPG:] VALIDSIG 1111 2026-01-01 0 4 0 1 10 00 DF9B9C49EAA9298432589D76DA87E80D6294BE9B\n' ;;
  bad) printf '[GNUPG:] BADSIG DA87E80D6294BE9B Debian CD signing key\n'; exit 1 ;;
  nokey) printf '[GNUPG:] NO_PUBKEY DA87E80D6294BE9B\n'; exit 2 ;;
  malformed) printf '[GNUPG:] NODATA 1\n'; exit 2 ;;
  unexpected) printf '[GNUPG:] VALIDSIG 1111 2026-01-01 0 4 0 1 10 00 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n' ;;
  unknown) printf '[GNUPG:] NO_PUBKEY AAAAAAAAAAAAAAAA\n'; exit 2 ;;
esac
SH

cat >"$bin/systemctl" <<'SH'
#!/usr/bin/env bash
[[ $1 == is-active && $2 == --quiet ]] || exit 3
[[ " ${VM_TEST_UNITS-virtqemud.socket virtstoraged.socket} " == *" $3 "* ]]
SH

cat >"$bin/id" <<'SH'
#!/usr/bin/env bash
case $1 in
  -nG) printf '%s\n' "${VM_TEST_GROUPS-tester wheel libvirt}" ;;
  -un) printf 'tester\n' ;;
esac
SH
chmod +x "$bin"/*

run() {
  HOME="$test_root/home" USER=tester LANG=en_GB.UTF-8 TMPDIR="$test_root/tmp" \
    XDG_CONFIG_HOME="$test_root/home/.config" XDG_CACHE_HOME="$test_root/cache" \
    XDG_STATE_HOME="$test_root/state" VM_PRESET_TEMPLATES="$templates" \
    VM_PRESET_KEYMAP=gb VM_PRESET_TIMEZONE=Europe/London VM_PRESET_POLL_INTERVAL=0.05 \
    VM_PRESET_DEBIAN_CD="https://cd.example/iso-cd" \
    VIRSH="$bin/virsh" VIRT_INSTALL="${VIRT_INSTALL:-$bin/virt-install}" VIRT_MANAGER="$bin/virt-manager" \
    ROFI="$bin/rofi" NOTIFY_SEND="$bin/notify-send" CURL="$bin/curl" GPG="$bin/gpg" \
    SYSTEMCTL="$bin/systemctl" ID_COMMAND="$bin/id" \
    VM_TEST_CALLS="$calls" VM_TEST_DOMAINS="$domains" VM_TEST_INJECTED="$injected" \
    VM_TEST_UUIDS="$test_root/uuids" \
    VM_TEST_MIRROR="$mirror" VM_TEST_PASSWORD="${VM_TEST_PASSWORD-$password}" "$helper" "$@"
}

reset_calls() { : >"$calls"; rm -f "$injected"/*; }

# virt-manager is started detached, so its call can land just after the helper
# exits.
wait_for_call() {
  local _
  for _ in {1..40}; do
    grep -Fq -- "$1" "$calls" && return 0
    sleep 0.05
  done
  fail "no call matching [$1]"
}

# ---------------------------------------------------------------- list ---
list=$(run list)
[[ $list == *'debian13         Debian 13'* ]] || fail 'list is missing Debian 13'
[[ $list == *'debian13-docker  Debian 13 + Docker'* ]] || fail 'list is missing Debian 13 + Docker'

# ------------------------------------------------------------- dry run ---
run --dry-run create debian13 >"$test_root/dry-plain"
dry=$test_root/dry-plain
assert_contains "$dry" '--connect qemu:///system --name debian13-1 --osinfo debian13'
assert_contains "$dry" '--vcpus 2 --memory 4096 --disk size=60\,format=qcow2\,bus=virtio'
assert_contains "$dry" '--network network=default\,model=virtio'
assert_contains "$dry" '--noautoconsole --wait -1'
assert_contains "$dry" '# ISO: download the newest Debian 13 netinst from https://cd.example/iso-cd'
assert_contains "$dry" 'd-i passwd/user-password-crypted password <redacted-hash>'
assert_contains "$dry" 'd-i passwd/username string tester'
assert_contains "$dry" 'd-i passwd/root-login boolean false'
assert_contains "$dry" 'd-i debian-installer/locale string en_GB.UTF-8'
assert_contains "$dry" 'd-i keyboard-configuration/xkb-keymap select gb'
assert_contains "$dry" 'd-i time/zone string Europe/London'
assert_contains "$dry" 'd-i netcfg/hostname string debian13-1'
assert_contains "$dry" 'd-i pkgsel/include string sudo openssh-server qemu-guest-agent'
assert_contains "$dry" 'user=tester'
assert_contains "$dry" '# No extra steps for this preset.'
assert_not_contains "$dry" 'download.docker.com'
assert_not_contains "$dry" 'vm-preset-authorized_keys (from'
grep -Eq '@[A-Z_]+@' "$dry" && fail 'dry run left a placeholder unfilled'
[[ ! -s $calls ]] || fail 'dry run called an external tool'
[[ ! -e $test_root/state && ! -e $test_root/cache ]] || fail 'dry run created state or cache'
[[ -z $(ls -A "$test_root/tmp") ]] || fail 'dry run left answer files behind'

VM_PRESET_VCPUS=4 VM_PRESET_MEMORY=8192 VM_PRESET_DISK_GB=80 \
  run --dry-run create debian13 --name 'Lab_box.2' >"$test_root/dry-sized"
assert_contains "$test_root/dry-sized" '--name Lab_box.2'
assert_contains "$test_root/dry-sized" '--vcpus 4 --memory 8192 --disk size=80\,format=qcow2'
assert_contains "$test_root/dry-sized" 'd-i netcfg/hostname string lab-box-2'
VM_PRESET_VCPUS=zero run --dry-run create debian13 >/dev/null 2>&1 && fail 'a non-numeric vCPU count was accepted'
run --dry-run create debian13 --name '-bad' >/dev/null 2>&1 && fail 'an invalid VM name was accepted'
run --dry-run create windows11 >/dev/null 2>&1 && fail 'an unknown preset was accepted'

printf 'ssh-rsa AAAAfixture tester@host\n' >"$test_root/home/.ssh/id_rsa.pub"
run --dry-run create debian13-docker >"$test_root/dry-docker"
dry=$test_root/dry-docker
assert_contains "$dry" '--name debian13-docker-1'
assert_contains "$dry" 'https://download.docker.com/linux/debian'
assert_contains "$dry" 'Suites: trixie'
assert_contains "$dry" 'docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin'
# shellcheck disable=SC2016 # Literal guest shell code.
assert_contains "$dry" 'usermod -aG docker "$user"'
assert_contains "$dry" 'vm-preset-authorized_keys (from'
assert_contains "$dry" 'ssh-rsa AAAAfixture tester@host'
assert_contains "$dry" 'PasswordAuthentication no'
assert_contains "$dry" '--initrd-inject'
grep -Eq '@[A-Z_]+@' "$dry" && fail 'docker dry run left a placeholder unfilled'

# ------------------------------------------------------- prerequisites ---
set +e
VIRT_INSTALL=/nonexistent/virt-install VM_TEST_UNITS=virtqemud.socket VM_TEST_GROUPS='tester wheel' \
  run create debian13 >/dev/null 2>&1
status=$?
set -e
((status == 1)) || fail "missing prerequisites exited $status"
assert_contains "$calls" 'notify --urgency=critical Virtual machines Cannot create a VM. Missing: virt-install, membership in the libvirt group, virtstoraged (sudo systemctl start virtstoraged.socket).'
grep -Fq 'rofi' "$calls" && fail 'prompted despite missing prerequisites'
reset_calls

VM_TEST_NET=no run create debian13 >/dev/null 2>&1 && fail 'an inactive default network was accepted'
assert_contains "$calls" 'the libvirt default network (sudo virsh net-start default)'
reset_calls

VM_TEST_UNITS=libvirtd.service run --dry-run create debian13 >/dev/null ||
  fail 'dry run should not check prerequisites'

# ------------------------------------------------------------- create ----
VM_TEST_SSH=Yes run create debian13-docker >"$test_root/create.out" 2>&1 ||
  { cat "$test_root/create.out" >&2; fail 'create debian13-docker failed'; }
assert_contains "$calls" 'rofi VM name'
assert_contains "$calls" 'rofi Password'
assert_contains "$calls" 'rofi Confirm'
assert_contains "$calls" 'rofi Install host SSH key?'
assert_contains "$calls" 'virt-install --connect qemu:///system --name debian13-docker-2 '
assert_contains "$calls" "--location $test_root/cache/vm-presets/$iso_name"
wait_for_call 'virt-manager --connect qemu:///system --show-domain-console debian13-docker-2'
assert_contains "$calls" 'notify --urgency=normal Virtual machines debian13-docker-2 is installed. Log in as tester.'
assert_contains "$calls" "curl https://cd.example/iso-cd/$iso_name"
[[ -f $test_root/cache/vm-presets/$iso_name ]] || fail 'the ISO was not cached'
[[ $(stat -c '%a' "$test_root/cache/vm-presets/$iso_name") == 644 ]] || fail 'the ISO is not world-readable'
[[ -z $(find "$test_root/cache/vm-presets" -name '.download.*') ]] || fail 'the download directory was left behind'
[[ -z $(ls -A "$test_root/tmp") ]] || fail 'answer files were left behind'
grep -Fxq debian13-docker-2 "$domains" || fail 'the VM was not defined'
[[ -s $test_root/state/vm-presets/debian13-docker-2.log ]] || fail 'no creation log was written'

preseed=$injected/preseed.cfg
hash=$(sed -n 's/^d-i passwd\/user-password-crypted password //p' "$preseed")
[[ $hash == "\$6\$"* ]] || fail 'the preseed does not carry a SHA-512 crypt hash'
salt=$(cut -d'$' -f3 <<<"$hash")
[[ $(printf '%s\n' "$password" | openssl passwd -6 -salt "$salt" -stdin) == "$hash" ]] ||
  fail 'the preseed hash does not match the password'
# shellcheck disable=SC2016
assert_contains "$injected/vm-preset-late.sh" 'usermod -aG docker "$user"'
[[ $(grep -c '^apt-get install -y docker-ce ' "$injected/vm-preset-late.sh") == 1 ]] ||
  fail 'the Docker fragment was not rendered exactly once'
assert_contains "$injected/vm-preset-authorized_keys" 'ssh-rsa AAAAfixture tester@host'
grep -Eq '^-rw------- .*/preseed\.cfg$' "$injected/modes" || fail 'the preseed was not mode 0600'

# The password itself never lands anywhere.
grep -rFq -- "$password" "$test_root" && fail 'the password was written to disk'
grep -Fq -- "$password" "$test_root/create.out" && fail 'the password was printed'
reset_calls

# Second create reuses the cached ISO and honours "No" for the SSH key.
VM_TEST_SSH=No run create debian13 >/dev/null 2>&1 || fail 'create debian13 failed'
assert_contains "$calls" 'virt-install --connect qemu:///system --name debian13-1 '
grep -Fq 'curl ' "$calls" && fail 'a cached ISO was downloaded again'
[[ ! -e $injected/vm-preset-authorized_keys ]] || fail 'the SSH key was installed after answering No'
assert_contains "$injected/vm-preset-late.sh" '# No extra steps for this preset.'
reset_calls

# ------------------------------------------------------ refusals & cancel ---
VM_TEST_NAME=debian13 run create debian13 >/dev/null 2>&1 && fail 'an existing VM name was accepted'
assert_contains "$calls" 'A VM named debian13 already exists. Nothing was created.'
grep -Fq 'virt-install' "$calls" && fail 'virt-install ran for an existing name'
reset_calls

VM_TEST_NAME=__cancel__ run create debian13 >/dev/null 2>&1 || fail 'cancelling the name prompt was an error'
grep -Fq 'rofi Password' "$calls" && fail 'asked for a password after cancelling'
reset_calls

VM_TEST_CONFIRM='something else' run create debian13 >/dev/null 2>&1 && fail 'mismatched passwords were accepted'
assert_contains "$calls" 'The passwords did not match. Nothing was created.'
grep -Fq 'virt-install' "$calls" && fail 'virt-install ran after a password mismatch'
reset_calls

VM_TEST_PASSWORD='' VM_TEST_CONFIRM='' run create debian13 >/dev/null 2>&1 && fail 'an empty password was accepted'
assert_contains "$calls" 'The password cannot be empty. Nothing was created.'
reset_calls

# ------------------------------------------------------------- failure ---
VM_TEST_INSTALL_EXIT=1 run create debian13 >/dev/null 2>&1 && fail 'a failed install reported success'
failed_uuid=$(awk '/^virt-install / {for (i=1; i<=NF; i++) if ($i == "--uuid") print $(i+1)}' "$calls")
assert_contains "$calls" "virsh -c qemu:///system undefine $failed_uuid --nvram --storage vda"
grep -Fxq debian13-2 "$domains" && fail 'the failed VM was left defined'
grep -Fxq debian13 "$domains" || fail 'cleanup removed a VM it did not create'
assert_contains "$calls" 'notify --urgency=critical Virtual machines Creating debian13-2 failed.'
reset_calls

# Another creator can claim the requested name after the first availability
# check. Only our generated UUID may be opened or removed on failure.
VM_TEST_COLLISION=1 run create debian13 --name concurrent-vm >/dev/null 2>&1 && fail 'a name collision reported success'
grep -Fxq concurrent-vm "$domains" || fail 'cleanup removed a VM created by another process'
assert_not_contains "$calls" ' destroy '
assert_not_contains "$calls" ' undefine '
assert_not_contains "$calls" 'virt-manager '
reset_calls

# ---------------------------------------------------------------- lock ---
mkdir -p "$test_root/state/vm-presets"
exec 8>"$test_root/state/vm-presets/lock"
flock -n 8 || fail 'could not take the test lock'
run create debian13 >/dev/null 2>&1 && fail 'a second concurrent create was allowed'
assert_contains "$calls" 'VM creation already in progress.'
grep -Fq 'rofi' "$calls" && fail 'prompted while another creation held the lock'
exec 8>&-
reset_calls

# ------------------------------------------------------- ISO integrity ---
rm -f "$test_root/cache/vm-presets/"*.iso
VM_TEST_CORRUPT=1 run refresh-iso debian13 >/dev/null 2>&1 && fail 'a corrupt ISO was accepted'
[[ -z $(find "$test_root/cache/vm-presets" -name '*.iso') ]] || fail 'a corrupt ISO was kept'
[[ -z $(find "$test_root/cache/vm-presets" -name '.download.*') ]] || fail 'a failed download left its directory'
reset_calls

VM_TEST_GPG=bad run refresh-iso debian13 >/dev/null 2>&1 && fail 'a bad signature was accepted'
grep -Fq "curl https://cd.example/iso-cd/$iso_name" "$calls" && fail 'downloaded the ISO despite a bad signature'
reset_calls

for signature in malformed unexpected unknown; do
  VM_TEST_GPG=$signature run refresh-iso debian13 >/dev/null 2>&1 && fail "a $signature signature was accepted"
  assert_not_contains "$calls" "curl https://cd.example/iso-cd/$iso_name"
  reset_calls
done

VM_TEST_GPG=nokey run refresh-iso debian13 >/dev/null 2>&1 || fail 'a missing signing key should only warn'
assert_contains "$calls" 'Could not verify the Debian ISO signature'
[[ -f $test_root/cache/vm-presets/$iso_name ]] || fail 'refresh-iso did not cache the ISO'
reset_calls

run refresh-iso debian13 >/dev/null 2>&1 || fail 'refresh-iso with a current cache failed'
grep -Fq "curl https://cd.example/iso-cd/$iso_name" "$calls" && fail 'refresh-iso downloaded an ISO it already had'
reset_calls

# A cached filename is not proof of integrity, including during refresh.
printf 'truncated ISO' >"$test_root/cache/vm-presets/$iso_name"
run refresh-iso debian13 >/dev/null 2>&1 || fail 'refresh did not repair a corrupt cached ISO'
cmp "$mirror/$iso_name" "$test_root/cache/vm-presets/$iso_name" || fail 'refresh kept corrupt bytes'
reset_calls
printf 'truncated again' >"$test_root/cache/vm-presets/$iso_name"
run create debian13 --name repaired-cache >/dev/null 2>&1 || fail 'create did not repair a corrupt cached ISO'
assert_contains "$calls" "curl https://cd.example/iso-cd/$iso_name"
cmp "$mirror/$iso_name" "$test_root/cache/vm-presets/$iso_name" || fail 'create used corrupt bytes'
reset_calls

# ---------------------------------------------------------------- menu ---
grep -Fq '"id": "development.vms"' "$menu" || fail 'Virtual machines is missing from Development'
grep -Fq '"when": "command -v virt-install >/dev/null && command -v virsh >/dev/null"' "$menu" ||
  fail 'the Virtual machines submenu is not guarded on the libvirt tools'
grep -Fq 'vm-preset create debian13"' "$menu" || fail 'Debian 13 is not wired to the helper'
grep -Fq 'vm-preset create debian13-docker"' "$menu" || fail 'Debian 13 + Docker is not wired to the helper'
grep -Fq '"action": "virt-manager --connect qemu:///system"' "$menu" || fail 'virt-manager entry is missing'

printf 'ok: virtual machine presets\n'

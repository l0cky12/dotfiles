#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
compose_file="$repo_root/windows/.local/share/windows-vm/compose.yaml"
helper="$repo_root/windows/.local/bin/windows-vm"
readme="$repo_root/README.md"
test_root=$(mktemp -d -t vm-image-pin-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -Eq '^[[:space:]]*image:.*dockurr/windows:latest' "$compose_file" \
  && fail 'Compose still uses the mutable latest tag as its image'

image_default=$(sed -n 's/^[[:space:]]*image: "${WINDOWS_IMAGE:-\([^}]*\)}"[[:space:]]*$/\1/p' "$compose_file")
[[ -n "$image_default" ]] || fail 'Compose WINDOWS_IMAGE default is missing or unrecognized'

case "$image_default" in
  dockurr/windows@sha256:DIGEST)
    if [[ "${VM_IMAGE_PIN_REQUIRE_DIGEST:-0}" == 1 ]]; then
      fail 'Compose still ships the literal DIGEST placeholder'
    fi
    printf 'WARNING: Compose still ships the fail-closed DIGEST placeholder; run with VM_IMAGE_PIN_REQUIRE_DIGEST=1 for release enforcement.\n' >&2
    ;;
  dockurr/windows@sha256:*)
    digest=${image_default#dockurr/windows@sha256:}
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || fail 'Compose image digest is not 64 lowercase hexadecimal characters'
    ;;
  *) fail 'Compose WINDOWS_IMAGE default is not digest-pinned' ;;
esac

grep -Fq "docker image inspect dockurr/windows:latest --format '{{index .RepoDigests 0}}'" \
  "$compose_file" || fail 'Compose placeholder lacks the documented capture TODO'
grep -Fq "docker image inspect dockurr/windows:latest --format '{{index .RepoDigests 0}}'" \
  "$readme" || fail 'README lacks the exact digest capture command'

# Exercise the actual configuration writer, then simulate an upgrade from a
# pre-pin install. Launch must migrate :latest and reject the placeholder before
# it reaches Docker.
mkdir -p "$test_root/config" "$test_root/storage" "$test_root/share"
HOME="$test_root/home" \
WINDOWS_VM_CONFIG_DIR="$test_root/config" \
WINDOWS_VM_STORAGE_DIR="$test_root/storage" \
WINDOWS_VM_SHARE_DIR="$test_root/share" \
bash -c '
  source "$1" help >/dev/null
  host_locale() { printf "%s\n" en-US; }
  host_timezone() { printf "%s\n" UTC; }
  write_configuration 8G 4 128G fixture secret
' _ "$helper"
settings_file="$test_root/config/settings.env"
credentials_file="$test_root/config/credentials.env"
grep -Fq "WINDOWS_IMAGE=$image_default" "$settings_file" \
  || fail 'Generated settings do not use the Compose image default'
sed -i 's|^WINDOWS_IMAGE=.*|WINDOWS_IMAGE=dockurr/windows:latest|' "$settings_file"

set +e
HOME="$test_root/home" \
WINDOWS_VM_CONFIG_DIR="$test_root/config" \
WINDOWS_VM_DATA_DIR="$repo_root/windows/.local/share/windows-vm" \
"$helper" launch > "$test_root/launch.out" 2>&1
launch_status=$?
set -e
[[ "$launch_status" -ne 0 ]] || fail 'Launch accepted a migrated placeholder image'
grep -Fq "mutable WINDOWS_IMAGE value 'dockurr/windows:latest'" "$test_root/launch.out" \
  || fail 'Launch did not warn about the mutable generated setting'
grep -Fq "Invalid WINDOWS_IMAGE value '$image_default'" "$test_root/launch.out" \
  || fail 'Launch did not validate the migrated placeholder'
grep -Fq 'README.md, "Pin and verify the image digest"' "$test_root/launch.out" \
  || fail 'Launch error does not point to the README capture instructions'
grep -Fxq "WINDOWS_IMAGE=$image_default" "$settings_file" \
  || fail 'Launch did not rewrite the mutable generated setting'
[[ $(stat -c %a "$settings_file") == 600 ]] \
  || fail 'Migration did not preserve generated settings permissions'

# A valid digest must pass validation without changing the file.
valid_image="dockurr/windows@sha256:$(printf 'a%.0s' {1..64})"
sed -i "s|^WINDOWS_IMAGE=.*|WINDOWS_IMAGE=$valid_image|" "$settings_file"
before=$(sha256sum "$settings_file")
HOME="$test_root/home" WINDOWS_VM_CONFIG_DIR="$test_root/config" \
bash -c 'source "$1" help >/dev/null; prepare_windows_image' _ "$helper"
after=$(sha256sum "$settings_file")
[[ "$before" == "$after" ]] || fail 'Validation rewrote an already-valid digest setting'
[[ -r "$credentials_file" ]] || fail 'Configuration writer did not generate credentials'

printf 'ok: Windows VM image pin\n'

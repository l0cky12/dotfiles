#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
compose_file="$repo_root/windows/.local/share/windows-vm/compose.yaml"
helper="$repo_root/windows/.local/bin/windows-vm"
readme="$repo_root/README.md"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -Eq '^[[:space:]]*image:.*dockurr/windows:latest' "$compose_file" \
  && fail 'Compose still uses the mutable latest tag as its image'

image_default=$(sed -n 's/^[[:space:]]*image: "${WINDOWS_IMAGE:-\([^}]*\)}"[[:space:]]*$/\1/p' "$compose_file")
[[ -n "$image_default" ]] || fail 'Compose WINDOWS_IMAGE default is missing or unrecognized'

case "$image_default" in
  dockurr/windows@sha256:DIGEST) ;;
  dockurr/windows@sha256:*)
    digest=${image_default#dockurr/windows@sha256:}
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || fail 'Compose image digest is not 64 lowercase hexadecimal characters'
    ;;
  *) fail 'Compose WINDOWS_IMAGE default is not digest-pinned' ;;
esac

grep -Fq "docker image inspect dockurr/windows:latest --format '{{index .RepoDigests 0}}'" \
  "$compose_file" || fail 'Compose placeholder lacks the documented capture TODO'
grep -Fq "WINDOWS_IMAGE=$image_default" "$helper" \
  || fail 'Installer default does not match the Compose image default'
grep -Fq "docker image inspect dockurr/windows:latest --format '{{index .RepoDigests 0}}'" \
  "$readme" || fail 'README lacks the exact digest capture command'

printf 'ok: Windows VM image pin\n'

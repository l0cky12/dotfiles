#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config="$repo_root/security/.config/gnupg-conf/gpg-agent.conf"
test_root=$(mktemp -d -t agent-ttl-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

check_config() {
  local candidate=$1 line key value
  local -a matches=()
  local -A values=()
  local -A limits=(
    [default-cache-ttl]=300
    [max-cache-ttl]=1800
    [default-cache-ttl-ssh]=300
    [max-cache-ttl-ssh]=900
  )

  [[ -r $candidate ]] || return 1

  # GnuPG uses `key value` directives. Reject malformed active lines rather
  # than silently skipping them while enforcing the TTL contract.
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*$ || $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^[[:space:]]*[a-z0-9][a-z0-9-]*([[:space:]]+[^[:space:]]+)*[[:space:]]*$ ]] \
      || return 1
  done < "$candidate"

  for key in "${!limits[@]}"; do
    mapfile -t matches < <(awk -v key="$key" '$1 == key { print }' "$candidate")
    ((${#matches[@]} == 1)) || return 1
    read -r _ value extra <<< "${matches[0]}"
    [[ -z ${extra:-} && $value =~ ^[0-9]+$ ]] || return 1
    ((value > 0 && value <= limits[$key])) || return 1
    values[$key]=$value
  done

  ((values[default-cache-ttl] <= values[max-cache-ttl])) || return 1
  ((values[default-cache-ttl-ssh] <= values[max-cache-ttl-ssh])) || return 1
  # Explicit audit guard: no GnuPG default may ever drift above 30 minutes.
  ((values[default-cache-ttl] <= 1800)) || return 1
}

check_config "$config" || fail 'agent configuration violates the TTL contract'

# Prove the checker fails closed for absent, excessive, and malformed policy.
cp -- "$config" "$test_root/missing.conf"
sed -i '/^max-cache-ttl-ssh[[:space:]]/d' "$test_root/missing.conf"
! check_config "$test_root/missing.conf" || fail 'missing SSH maximum was accepted'

cp -- "$config" "$test_root/excessive.conf"
sed -i 's/^default-cache-ttl .*/default-cache-ttl 1801/' "$test_root/excessive.conf"
! check_config "$test_root/excessive.conf" || fail 'excessive GnuPG default was accepted'

cp -- "$config" "$test_root/malformed.conf"
printf '%s\n' 'max-cache-ttl-ssh = 900' >> "$test_root/malformed.conf"
! check_config "$test_root/malformed.conf" || fail 'malformed directive was accepted'

printf 'ok: gpg-agent TTL policy\n'

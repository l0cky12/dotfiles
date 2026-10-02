#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/hypr/.config/hypr/scripts/power-profile.sh"
test_root=$(mktemp -d -t power-profile-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "[$1] does not contain [$2]"
}

mkdir -p "$test_root/bin"
cat > "$test_root/bin/powerprofilesctl" <<'SH'
#!/usr/bin/env bash
case "$1" in
  list|get) printf '%s\n' "$*" >> "$POWER_CALLS" ;;
  set) printf '%s\n' "$*" >> "$POWER_CALLS" ;;
esac
case "$1" in
  list)
    printf '%s\n' \
      'performance:' \
      '    Driver: platform_profile' \
      '* balanced:' \
      '    Driver: placeholder-driver' \
      '  power-saver:' \
      '    Driver: platform_profile'
    ;;
  get) printf 'balanced\n' ;;
  set) printf 'ok\n' ;;
  *) printf 'ok\n' ;;
esac
SH
chmod +x "$test_root/bin/powerprofilesctl"
# No notification daemon (e.g. the shell is restarting): notify-send fails.
# A profile change that already succeeded must still exit 0.
printf '#!/bin/sh\nexit 1\n' > "$test_root/bin/notify-send"
chmod +x "$test_root/bin/notify-send"
export POWER_CALLS="$test_root/calls"
: > "$POWER_CALLS"

# get/status reads the fixture profile.
status=$(PATH="$test_root/bin:$PATH" "$script" status)
[[ "$status" == "balanced (power source unknown)" ]] || fail "status output was [$status]"
PATH="$test_root/bin:$PATH" "$script" get >/dev/null

# set calls powerprofilesctl with the profile.
PATH="$test_root/bin:$PATH" "$script" set balanced >/dev/null
assert_contains "$POWER_CALLS" 'set balanced'
: > "$POWER_CALLS"

# An unknown profile fails without reaching powerprofilesctl.
: > "$POWER_CALLS"
set +e
PATH="$test_root/bin:$PATH" "$script" set turbo >/dev/null 2>&1
invalid_status=$?
set -e
[[ "$invalid_status" -eq 2 ]] || fail 'invalid profile did not exit 2'
grep -q '^set ' "$POWER_CALLS" && fail 'invalid profile reached set'

# --dry-run prints the command and does not mutate state.
dry_run=$(PATH="$test_root/bin:$PATH" "$script" set performance --dry-run)
assert_contains <(printf '%s\n' "$dry_run") 'powerprofilesctl set performance'
grep -q '^set ' "$POWER_CALLS" && fail 'dry-run mutated state'

# cycle advances from the current profile (balanced -> power-saver).
PATH="$test_root/bin:$PATH" "$script" cycle >/dev/null
assert_contains "$POWER_CALLS" 'set power-saver'
: > "$POWER_CALLS"

# toggle with no power_supply sysfs falls back to balanced.
PATH="$test_root/bin:$PATH" "$script" toggle >/dev/null
assert_contains "$POWER_CALLS" 'set balanced'
: > "$POWER_CALLS"

# missing powerprofilesctl exits nonzero with the daemon hint.
shadow="$test_root/shadow-bin"
mkdir -p "$shadow"
set +e
missing=$(PATH="$shadow:/usr/bin" bash "$script" list 2>&1)
missing_status=$?
set -e
[[ "$missing_status" -eq 1 ]] || fail 'missing powerprofilesctl did not exit 1'
assert_contains <(printf '%s\n' "$missing") 'power-profiles-daemon'

printf 'ok: power-profile fixtures\n'

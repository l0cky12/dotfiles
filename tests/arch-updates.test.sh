#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

# The result cache is exercised on its own below; the counting assertions want a
# fresh check every time.
export ARCH_UPDATES_TTL=0

printf '#!/bin/sh\nprintf "core 1 -> 2\\nextra 1 -> 2\\n"\n' > "$fixture/checkupdates"
printf '#!/bin/sh\nprintf "aur-one 1 -> 2\\n"\n' > "$fixture/yay"
chmod +x "$fixture/checkupdates" "$fixture/yay"
# The stubs are only meaningful if the host's real checkupdates/yay/paru are out
# of reach, so the fixture is the entire PATH and supplies its own bash.
ln -s "$(command -v bash)" "$fixture/bash"

output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates")
[[ $output == '{"repo":2,"aur":1,"total":3,"repoPackages":["core","extra"],"aurPackages":["aur-one"]}' ]]

# Exit 2 is checkupdates reporting a clean system, not a failure.
printf '#!/bin/sh\nexit 2\n' > "$fixture/checkupdates"
printf '#!/bin/sh\nexit 1\n' > "$fixture/yay"
output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates")
[[ $output == '{"repo":0,"aur":0,"total":0,"repoPackages":[],"aurPackages":[]}' ]]

# An AUR helper that lists updates but exits non-zero still contributes a count.
printf '#!/bin/sh\nprintf "aur-one 1 -> 2\\n"\nexit 1\n' > "$fixture/yay"
output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates")
[[ $output == '{"repo":0,"aur":1,"total":1,"repoPackages":[],"aurPackages":["aur-one"]}' ]]

# AUR throttling must keep the last known widget values rather than claim that
# there are no updates.
printf '#!/bin/sh\nprintf "status 429: Rate limit reached\\n" >&2\nexit 1\n' > "$fixture/yay"
if output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates" 2>/dev/null); then
  printf 'FAIL: rate-limited AUR check reported success: %s\n' "$output" >&2
  exit 1
fi
[[ -z $output ]]

# A failed sync must not be reported as "zero updates"; the widget keeps its
# last known count when the script exits non-zero.
printf '#!/bin/sh\nexit 1\n' > "$fixture/checkupdates"
if output=$(PATH="$fixture" "$repo_root/hypr/.config/hypr/scripts/arch-updates" 2>/dev/null); then
  printf 'FAIL: failed sync reported success: %s\n' "$output" >&2
  exit 1
fi
[[ -z $output ]]

# --- update path -------------------------------------------------------------
# The terminal stub records its argv instead of launching anything, so the
# composed upgrade command can be asserted on a host that has neither an AUR
# helper nor apt.
script="$repo_root/hypr/.config/hypr/scripts/arch-updates"
mv "$fixture/yay" "$fixture/paru"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$ARCH_UPDATES_TEST_LOG"\n' > "$fixture/kitty"
chmod +x "$fixture/kitty"

run_update_stub() {
  rm -f "$fixture/update.log"
  ARCH_UPDATES_TEST_LOG="$fixture/update.log" PATH="$fixture" TERMINAL="" "$script" update
}

# Arch: the AUR helper is the upgrade command, and it wins over apt.
printf '#!/bin/sh\nexit 0\n' > "$fixture/apt"
chmod +x "$fixture/apt"
run_update_stub
grep -Fx 'aur' "$fixture/update.log" >/dev/null
grep -Fx "$fixture/paru" "$fixture/update.log" >/dev/null
grep -Fq 'aur) "$2" -Syu' "$fixture/update.log"
# The window must stay open on a read rather than exiting the moment yay does.
grep -Fq 'read -rp "Done. Press Enter to close. "' "$fixture/update.log"
# The upgrade's exit status has to survive, or the widget cannot tell a failed
# update from a clean one and wrongly zeroes its count.
grep -Fq 'exit $status' "$fixture/update.log"

# Cache invalidation must not turn a failed terminal run into widget success.
printf '#!/bin/sh\nexit 23\n' > "$fixture/failterm"
chmod +x "$fixture/failterm"
status=0
ARCH_UPDATES_TTL=600 ARCH_UPDATES_CACHE_DIR="$fixture/update-cache" \
  TERMINAL="$fixture/failterm" PATH="$fixture:$PATH" "$script" update || status=$?
[[ $status == 23 ]] || { printf 'FAIL: update exit status was lost\n' >&2; exit 1; }

# The inner shell must execute a helper whose path contains spaces literally.
mkdir "$fixture/with space"
printf '#!/bin/sh\nprintf "updated\\n" > "$ARCH_UPDATES_TEST_LOG"\n' > "$fixture/with space/yay"
printf '#!/bin/sh\nshift 2\n"$@" </dev/null\n' > "$fixture/exec-term"
chmod +x "$fixture/with space/yay" "$fixture/exec-term"
ARCH_UPDATES_TEST_LOG="$fixture/executed.log" TERMINAL="$fixture/exec-term" \
  PATH="$fixture/with space:$fixture:$PATH" "$script" update
grep -Fxq updated "$fixture/executed.log"

# Debian: with no AUR helper, apt takes over. This branch never runs on the
# Arch machines, so the stub is the only thing that will catch a typo in it.
rm "$fixture/paru"
run_update_stub
grep -Fx apt "$fixture/update.log" >/dev/null
grep -Fq 'apt) sudo apt update && sudo apt full-upgrade' "$fixture/update.log"

# Debian count uses apt's local upgrade listing, not Arch's checkupdates.
rm "$fixture/checkupdates"
ln -s "$(command -v awk)" "$fixture/awk"
printf '#!/bin/sh\nprintf "Listing...\\nalpha/stable 2.0 amd64 [upgradable]\\nbeta/stable 3.0 amd64 [upgradable]\\n"\n' > "$fixture/apt"
output=$(PATH="$fixture" "$script" count)
[[ $output == '{"repo":2,"aur":0,"total":2,"repoPackages":["alpha","beta"],"aurPackages":[]}' ]]

# $TERMINAL is preferred over the built-in candidate list.
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$ARCH_UPDATES_TEST_LOG"\n' > "$fixture/myterm"
chmod +x "$fixture/myterm"
rm -f "$fixture/update.log"
ARCH_UPDATES_TEST_LOG="$fixture/update.log" PATH="$fixture" TERMINAL=myterm \
  "$script" update
[[ -s $fixture/update.log ]]
rm "$fixture/myterm"

# No terminal emulator and no package manager are both reported as failures, so
# the widget can surface them instead of looking like a dead button.
mv "$fixture/kitty" "$fixture/kitty.off"
if PATH="$fixture" TERMINAL="" "$script" update 2>/dev/null; then
  printf 'FAIL: missing terminal reported success\n' >&2
  exit 1
fi
mv "$fixture/kitty.off" "$fixture/kitty"

rm "$fixture/apt"
if PATH="$fixture" TERMINAL="" "$script" update 2>/dev/null; then
  printf 'FAIL: missing package manager reported success\n' >&2
  exit 1
fi


# The cache is what stops several callers (the bar, lmenu, a prompt) from each
# querying the AUR. A repeat call inside the TTL must not reach the helper.
cache=$(mktemp -d)
trap 'rm -rf "$fixture" "$cache"' EXIT
calls="$cache/calls"
: > "$calls"
printf '#!/bin/sh\nprintf "checkupdates\\n" >> "%s"\nprintf "core 1 -> 2\\n"\n' "$calls" > "$fixture/checkupdates"
printf '#!/bin/sh\nprintf "yay\\n" >> "%s"\nprintf "aur-one 1 -> 2\\n"\n' "$calls" > "$fixture/yay"
rm -f "$fixture/paru"
chmod +x "$fixture/checkupdates" "$fixture/yay"

run_cached() {
  ARCH_UPDATES_TTL=600 ARCH_UPDATES_CACHE_DIR="$cache/store" PATH="$fixture:$PATH" \
    "$repo_root/hypr/.config/hypr/scripts/arch-updates"
}

first=$(run_cached)
[[ $first == '{"repo":1,"aur":1,"total":2,"repoPackages":["core"],"aurPackages":["aur-one"]}' ]]
[[ $(grep -c '^yay$' "$calls") == 1 ]]

second=$(run_cached)
[[ $second == "$first" ]]
if [[ $(grep -c '^yay$' "$calls") != 1 ]]; then
  printf 'FAIL: cached call still queried the AUR\n' >&2
  exit 1
fi

# An expired entry must fall through to a real check again.
printf '0' > "$cache/store/last-attempt"
third=$(run_cached)
[[ $third == "$first" ]]
[[ $(grep -c '^yay$' "$calls") == 2 ]]

# After a failure the cooldown reports an error rather than serving the last
# good payload, so the widget keeps showing its own stale count.
rm -rf "$cache/store"
: > "$calls"
printf '#!/bin/sh\nprintf "yay\\n" >> "%s"\nprintf "status 429: Rate limit reached\\n" >&2\nexit 1\n' "$calls" > "$fixture/yay"
chmod +x "$fixture/yay"
if run_cached >/dev/null 2>&1; then
  printf 'FAIL: rate-limited check reported success\n' >&2
  exit 1
fi
if run_cached >/dev/null 2>&1; then
  printf 'FAIL: throttled retry reported success\n' >&2
  exit 1
fi
if [[ $(grep -c '^yay$' "$calls") != 1 ]]; then
  printf 'FAIL: retry inside the cooldown queried the AUR again\n' >&2
  exit 1
fi

printf 'arch-updates: ok\n'

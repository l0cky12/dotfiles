#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

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

mv "$fixture/yay" "$fixture/paru"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$ARCH_UPDATES_TEST_LOG"\n' > "$fixture/kitty"
chmod +x "$fixture/kitty"
ARCH_UPDATES_TEST_LOG="$fixture/update.log" PATH="$fixture" \
  "$repo_root/hypr/.config/hypr/scripts/arch-updates" update
grep -Fx 'exec "$1" -Syu' "$fixture/update.log" >/dev/null
grep -Fx "$fixture/paru" "$fixture/update.log" >/dev/null

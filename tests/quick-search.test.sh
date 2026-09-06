#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scripts="$repo_root/hypr/.config/hypr/scripts"
everything="$scripts/quick-search-everything.sh"
theme="$repo_root/rofi/.config/rofi/everything.rasi"
test_root=$(mktemp -d -t quick-search-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

"$scripts/quick-search.sh" --dry-run everything >"$test_root/launcher.out"
grep -Fq 'Everything:' "$test_root/launcher.out" ||
  fail 'quick search does not register its Everything root menu'
grep -Fq 'drun\,window\,run' "$test_root/launcher.out" ||
  fail 'quick search does not expose apps, windows, and commands as switchable modes'
grep -Fq -- '-kb-mode-next Tab' "$test_root/launcher.out" ||
  fail 'Tab does not switch to the next launcher mode'
grep -Fq -- '-kb-mode-previous ISO_Left_Tab' "$test_root/launcher.out" ||
  fail 'Shift+Tab does not switch to the previous launcher mode'
grep -Fq -- "-kb-element-next ''" "$test_root/launcher.out" ||
  fail 'Tab is still assigned to element navigation'
grep -Fq -- "-kb-element-prev ''" "$test_root/launcher.out" ||
  fail 'Shift+Tab is still assigned to element navigation'
grep -Fq 'everything.rasi' "$test_root/launcher.out" ||
  fail 'Everything search does not use its compact menu theme'

grep -Fq 'width: 380px;' "$theme" || fail 'Everything menu is not narrow'
grep -Fq 'children: [ "inputbar", "listview" ];' "$theme" ||
  fail 'Everything menu is not a single vertical search list'
grep -Fq 'placeholder: "Go...";' "$theme" || fail 'Everything menu is missing its Go prompt'
grep -Fq 'mode-switcher {' "$theme" || fail 'Everything menu does not style its hidden mode switcher'

"$scripts/quick-search.sh" --dry-run drun >"$test_root/apps.out"
grep -Fq -- '-show drun' "$test_root/apps.out" ||
  fail 'application launcher does not start in app-only mode'

ROFI_RETV=0 "$everything" >"$test_root/everything.out"
for item in Apps Windows Commands Reboot Shutdown; do
  grep -Fq "$item" "$test_root/everything.out" || fail "Everything menu is missing $item"
done
grep -Fq '›' "$test_root/everything.out" || fail 'Everything menu rows are missing chevrons'

ROFI_RETV=1 "$everything" apps >"$test_root/apps-switch.out"
grep -aFq $'switch-mode\x1fdrun' "$test_root/apps-switch.out" ||
  fail 'Apps does not open the installed-application search mode'

ROFI_RETV=1 "$everything" reboot >"$test_root/confirm.out"
grep -Fq 'Confirm reboot' "$test_root/confirm.out" || fail 'reboot does not request confirmation'
grep -aFq $'data\x1freboot' "$test_root/confirm.out" || fail 'reboot confirmation loses its action state'

"$everything" --dry-run reboot >"$test_root/reboot.out"
grep -Fq '+ systemctl reboot' "$test_root/reboot.out" || fail 'reboot dry-run is incorrect'
"$everything" --dry-run shutdown >"$test_root/shutdown.out"
grep -Fq '+ systemctl poweroff' "$test_root/shutdown.out" || fail 'shutdown dry-run is incorrect'

QUICK_SEARCH_DRY_RUN=1 ROFI_RETV=1 ROFI_DATA=reboot \
  "$everything" confirm >"$test_root/confirmed-reboot.out"
grep -Fq '+ systemctl reboot' "$test_root/confirmed-reboot.out" ||
  fail 'confirmed reboot did not reach the safe action callback'

printf 'quick search fixtures: ok\n'

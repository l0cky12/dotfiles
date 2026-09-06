#!/usr/bin/env bash
#
# These tests grep for literal text inside config files: menu.jsonc holds
# "~/.local/bin/..." paths and keybinding.conf holds "$mainMod". Neither is
# shell syntax in this script, so tilde and dollar expansion warnings are noise.
# shellcheck disable=SC2088,SC2016
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
reminder="$repo_root/menu/.local/bin/lmenu-reminder"
menu="$repo_root/menu/.config/lmenu/menu.jsonc"
test_root=$(mktemp -d -t lmenu-reminder-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Durations. A bare number means minutes; zero is not a duration.
duration_of() {
  "$reminder" --dry-run set "$1" msg 2>/dev/null |
    grep -oE -- '--on-active=[0-9]+' | cut -d= -f2
}
[[ $(duration_of 45s) == 45 ]] || fail '45s is not 45 seconds'
[[ $(duration_of 10m) == 600 ]] || fail '10m is not 600 seconds'
[[ $(duration_of 2h) == 7200 ]] || fail '2h is not 7200 seconds'
[[ $(duration_of 1h30m) == 5400 ]] || fail '1h30m is not 5400 seconds'
[[ $(duration_of 10) == 600 ]] || fail 'a bare number is not read as minutes'
for bad in 0 0m abc 5x '' 10mm; do
  "$reminder" --dry-run set "$bad" msg >/dev/null 2>&1 &&
    fail "\"$bad\" was accepted as a duration"
done

# The name is everything after the duration, spaces and all.
# The dry run %q-quotes its argv, so spaces arrive as "\ "; normalise before
# matching so these assertions describe behaviour, not quoting.
"$reminder" --dry-run set 10m Take a long break 2>&1 |
  sed 's/\\ / /g' >"$test_root/set.out"
grep -Fq -- '--description=Take a long break' "$test_root/set.out" ||
  fail 'the reminder name is not carried in the unit description'
grep -Fq 'fire Take a long break' "$test_root/set.out" ||
  fail 'the fired reminder is not given its name'
# The unit name carries the due time, which is what listing reads back.
grep -qE -- '--unit=lmenu-reminder-[0-9]{10,}-[0-9a-f]{4}' "$test_root/set.out" ||
  fail 'the unit name does not carry a due timestamp'
# Firing must go back through this script, so the notification fallback applies.
grep -Fq 'lmenu-reminder fire' "$test_root/set.out" ||
  fail 'the timer does not fire through the script, so it cannot fall back off notify-send'
grep -Fq -- '--timer-property=RemainAfterElapse=no' "$test_root/set.out" ||
  fail 'fired reminders will not clean themselves up'

# A reminder that cannot notify is useless, and notify-send is not dependable:
# a libnotify upgrade can leave it exiting 127 without sending anything.
grep -Fq 'gdbus' "$reminder" ||
  fail 'there is no fallback when notify-send is broken'
grep -Fq 'org.freedesktop.Notifications' "$reminder" ||
  fail 'the fallback does not talk to the notification daemon'

# Listing with a stand-in systemctl, so no real timers are touched.
cat >"$test_root/fake-systemctl" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  *list-units*)
    printf '  lmenu-reminder-%s-aaaa.timer loaded active waiting Later thing\n' "$(( $(date +%s) + 3600 ))"
    printf '  lmenu-reminder-%s-bbbb.timer loaded active waiting Sooner thing\n' "$(( $(date +%s) + 60 ))"
    ;;
  *"-p Description"*)
    case "$*" in
      *aaaa*) printf 'Later thing\n' ;;
      *bbbb*) printf 'Sooner thing\n' ;;
    esac
    ;;
esac
FAKE
chmod +x "$test_root/fake-systemctl"

[[ $(SYSTEMCTL="$test_root/fake-systemctl" "$reminder" count) == 2 ]] ||
  fail 'pending reminders are not counted'

SYSTEMCTL="$test_root/fake-systemctl" "$reminder" --dry-run list >"$test_root/list.out"
[[ $(head -n 1 "$test_root/list.out") == *"Sooner thing"* ]] ||
  fail 'reminders are not listed soonest first'
grep -Fq 'in 1h 0m' "$test_root/list.out" ||
  fail 'remaining time is not shown in a readable form'

# Clearing stops the timers rather than deleting state by hand.
SYSTEMCTL="$test_root/fake-systemctl" "$reminder" --dry-run clear >"$test_root/clear.out"
grep -Fq 'stop' "$test_root/clear.out" || fail 'clearing does not stop the timers'
grep -Fq 'aaaa.timer' "$test_root/clear.out" || fail 'clearing misses a pending timer'

# The menu rows point at the CLI, and Clear only shows when something pends.
grep -Fq '~/.local/bin/lmenu-reminder set' "$menu" ||
  fail 'the menu does not offer setting a reminder'
grep -Fq '~/.local/bin/lmenu-reminder list' "$menu" ||
  fail 'the menu does not offer showing reminders'
grep -Fq 'lmenu-reminder count) -gt 0' "$menu" ||
  fail 'the clear row is not gated on there being something to clear'
grep -Fq 'UNRESOLVED' <(grep -A4 'trigger.reminder' "$menu") &&
  fail 'the reminder rows are still stubs'

# The keybindings the reminders are meant to be reachable from.
conf="$repo_root/hypr/.config/hypr/conf/keybinding.conf"
lua="$repo_root/hypr/.config/hypr/conf/keybindings.lua"
grep -Fq '$mainMod CTRL, R, set a reminder' "$conf" || fail 'Super+Ctrl+R does not set a reminder'
grep -Fq '$mainMod CTRL ALT, R, show reminders' "$conf" || fail 'Super+Ctrl+Alt+R does not show reminders'
grep -Fq '$mainMod CTRL SHIFT, R, clear all reminders' "$conf" || fail 'Super+Ctrl+Shift+R does not clear reminders'
grep -Fq '+ CTRL + R", "set a reminder"' "$lua" || fail 'the Lua config is missing the set binding'
grep -Fq '+ CTRL + ALT + R", "show reminders"' "$lua" || fail 'the Lua config is missing the show binding'
grep -Fq '+ CTRL + SHIFT + R", "clear all reminders"' "$lua" || fail 'the Lua config is missing the clear binding'

# The name is its own field: interactively it is a second prompt, and when it
# goes off the name is the headline rather than a generic word.
grep -Fq 'prompt_line "Name"' "$reminder" ||
  fail 'the name prompt is not labelled Name'
grep -Fq 'prompt_line "Time"' "$reminder" ||
  fail 'the time prompt is not labelled Time'
# Name is asked first, then Time.
[[ $(grep -n 'prompt_line "Name"' "$reminder" | cut -d: -f1) -lt \
   $(grep -n 'prompt_line "Time"' "$reminder" | cut -d: -f1) ]] ||
  fail 'the Time prompt comes before the Name prompt'
grep -Fq 'notify_user "${*:-Reminder}" "Reminder"' "$reminder" ||
  fail 'a fired reminder does not show its name as the notification title'

# Cancelling either prompt must abort rather than schedule something unnamed.
grep -Fq 'raw=$(prompt_line "Name"' "$reminder" ||
  fail 'the name prompt result is not captured in a way that preserves a cancel'
grep -Fq 'raw=$(prompt_line "Time"' "$reminder" ||
  fail 'the time prompt result is not captured in a way that preserves a cancel'

# The field name is carried by rofi's prompt widget, and the shared theme's
# "Search…" placeholder is cleared so the box is not mislabelled.
grep -Fq "placeholder: \"\"" "$reminder" ||
  fail 'the free-text prompts still show the shared Search placeholder'
lmenu_theme="$repo_root/rofi/.config/rofi/lmenu.rasi"
if command -v rofi >/dev/null; then
  rofi -theme "$lmenu_theme" -dump-theme 2>/dev/null |
    sed -n '/^[[:space:]]*inputbar {/,/^[[:space:]]*}/p' |
    grep -q '"prompt"' ||
    fail 'the theme draws no prompt widget, so Name and Time will not be shown'
fi

printf 'lmenu-reminder: ok\n'

#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scripts="$repo_root/hypr/.config/hypr/scripts"
transparency_toggle="$scripts/toggle-transparency.sh"
toggle_cli="$repo_root/hypr/.local/bin/toggle"
test_root=$(mktemp -d -t omakub-toggles-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s
' "$1" >&2
  exit 1
}

require_jq() {
  command -v jq >/dev/null 2>&1 || {
    printf 'skip: jq is not installed
'
    exit 0
  }
}

require_jq

mkdir -p "$test_root/bin" "$test_root/state/hyprland-desktop"

cat >"$test_root/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
case "$*" in
  'getoption general:gaps_out -j') printf '{"custom":"%s"}\n' "${CURRENT_GAPS_OUT:-12}" ;;
  'getoption general:gaps_in -j') printf '{"custom":"%s"}\n' "${CURRENT_GAPS_IN:-4}" ;;
  'getoption general:border_size -j') printf '{"int":%s}\n' "${CURRENT_BORDER_SIZE:-2}" ;;
  'getoption decoration:active_opacity -j') printf '{"float":%s}\n' "${CURRENT_ACTIVE_OPACITY:-1.0}" ;;
  'getoption decoration:inactive_opacity -j') printf '{"float":%s}\n' "${CURRENT_INACTIVE_OPACITY:-0.95}" ;;
  'getoption decoration:fullscreen_opacity -j') printf '{"float":%s}\n' "${CURRENT_FULLSCREEN_OPACITY:-1.0}" ;;
  'devices -j') printf '%s\n' '{"touchpads":[{"enabled":true}]}' ;;
  'getoption input:touchpad:enabled -j') printf '%s\n' '{"int":1}' ;;
  eval*) ;;
  *) printf 'unexpected hyprctl call: %s\n' "$*" >&2; exit 1 ;;
esac
SH

cat >"$test_root/bin/notificationctl" <<'SH'
#!/usr/bin/env bash
[[ $* == 'status --json' ]] && printf '%s\n' '{"dnd":true}'
SH

cat >"$test_root/bin/desktop-mode" <<'SH'
#!/usr/bin/env bash
[[ $* == 'status stay-awake --json' ]] && printf '%s\n' '{"observed":false}'
SH

cat >"$test_root/bin/toggle-screensaver" <<'SH'
#!/usr/bin/env bash
[[ $* == status ]] && printf '%s\n' 'screensaver: on'
SH

cat >"$test_root/bin/quickshell" <<'SH'
#!/usr/bin/env bash
[[ $* == 'ipc call bar statusJson' ]] && printf '%s\n' '{"visible":true}'
SH
chmod +x "$test_root/bin/"*

export HYPRCTL="$test_root/bin/hyprctl"
export HYPRCTL_LOG="$test_root/hyprctl.log"
export NOTIFICATIONCTL="$test_root/bin/notificationctl"
export DESKTOP_MODE_EXECUTABLE="$test_root/bin/desktop-mode"
export TOGGLE_SCREENSAVER_EXECUTABLE="$test_root/bin/toggle-screensaver"
export QUICKSHELL="$test_root/bin/quickshell"
export XDG_STATE_HOME="$test_root/state"

"$scripts/toggle-gaps.sh" --dry-run >"$test_root/gaps-off.out"
grep -Fq 'gaps_out\ =\ 0\,\ gaps_in\ =\ 0\,\ border_size\ =\ 0' "$test_root/gaps-off.out" ||
  fail 'gaps dry-run did not remove gaps globally'
grep -Fq 'save gap defaults: gaps_out=12 gaps_in=4 border_size=2' "$test_root/gaps-off.out" ||
  fail 'gaps dry-run did not preserve configured defaults'
grep -Fq 'hl.config' "$test_root/gaps-off.out" ||
  fail 'gaps dry-run did not use global Hyprland config'
if grep -Eq 'activeworkspace|workspacerules|workspace_rule' "$HYPRCTL_LOG" "$test_root/gaps-off.out"; then
  fail 'global gaps toggle still used a per-workspace rule'
fi

cat >"$test_root/state/hyprland-desktop/gaps-defaults.json" <<'JSON'
{"gaps_out":12,"gaps_in":6,"border_size":1}
JSON
CURRENT_GAPS_OUT=0 CURRENT_GAPS_IN=0 CURRENT_BORDER_SIZE=0 \
  "$scripts/toggle-gaps.sh" --dry-run >"$test_root/gaps-on.out"
grep -Fq 'gaps_out\ =\ 12\,\ gaps_in\ =\ 6\,\ border_size\ =\ 1' "$test_root/gaps-on.out" ||
  fail 'gaps dry-run did not restore saved global defaults'
[[ -f "$test_root/state/hyprland-desktop/gaps-defaults.json" ]] ||
  fail 'gaps dry-run changed the saved state'

CURRENT_GAPS_OUT=0 CURRENT_GAPS_IN=0 CURRENT_BORDER_SIZE=0 \
  "$scripts/toggle-gaps.sh"
[[ ! -e "$test_root/state/hyprland-desktop/gaps-defaults.json" ]] ||
  fail 'restoring gaps did not remove the saved state'

"$scripts/toggle-gaps.sh"
jq -e '.gaps_out == 12 and .gaps_in == 4 and .border_size == 2' \
  "$test_root/state/hyprland-desktop/gaps-defaults.json" >/dev/null ||
  fail 'disabling gaps did not save the current global defaults'
grep -Fq 'hl.config({ general = { gaps_out = 0, gaps_in = 0, border_size = 0 } })' \
  "$HYPRCTL_LOG" || fail 'disabling gaps did not apply global zero values'

CURRENT_GAPS_OUT=0 CURRENT_GAPS_IN=0 CURRENT_BORDER_SIZE=0 \
  "$scripts/toggle-gaps.sh"
[[ ! -e "$test_root/state/hyprland-desktop/gaps-defaults.json" ]] ||
  fail 'a complete gaps toggle cycle left stale state'

"$transparency_toggle" --dry-run >"$test_root/transparency-off.out"
grep -Fq 'active_opacity\ =\ 1\,\ inactive_opacity\ =\ 1\,\ fullscreen_opacity\ =\ 1' \
  "$test_root/transparency-off.out" || fail 'transparency dry-run did not make every window opaque'
grep -Fq 'save opacity defaults: active=1.0 inactive=0.95 fullscreen=1.0' \
  "$test_root/transparency-off.out" || fail 'transparency dry-run did not preserve configured opacity'

mkdir -p "$test_root/state/hyprland-desktop"
cat >"$test_root/state/hyprland-desktop/opacity-defaults.json" <<'JSON'
{"active":0.92,"inactive":0.86,"fullscreen":1}
JSON
"$transparency_toggle" --dry-run >"$test_root/transparency-on.out"
grep -Fq 'active_opacity\ =\ 0.92\,\ inactive_opacity\ =\ 0.86\,\ fullscreen_opacity\ =\ 1' \
  "$test_root/transparency-on.out" || fail 'transparency dry-run did not restore saved opacity'
[[ -f "$test_root/state/hyprland-desktop/opacity-defaults.json" ]] ||
  fail 'transparency dry-run changed the saved state'

"$transparency_toggle"
[[ ! -e "$test_root/state/hyprland-desktop/opacity-defaults.json" ]] ||
  fail 'restoring transparency did not remove the saved state'

"$transparency_toggle"
jq -e '.active == 1 and .inactive == 0.95 and .fullscreen == 1' \
  "$test_root/state/hyprland-desktop/opacity-defaults.json" >/dev/null ||
  fail 'disabling transparency did not save the current global opacity'
grep -Fq 'hl.config({ decoration = { active_opacity = 1, inactive_opacity = 1, fullscreen_opacity = 1 } })' \
  "$HYPRCTL_LOG" || fail 'disabling transparency did not make every window opaque'

CURRENT_ACTIVE_OPACITY=1 CURRENT_INACTIVE_OPACITY=1 CURRENT_FULLSCREEN_OPACITY=1 \
  "$transparency_toggle"
[[ ! -e "$test_root/state/hyprland-desktop/opacity-defaults.json" ]] ||
  fail 'a complete transparency toggle cycle left stale state'

if grep -Eq 'opacity.*override' \
  "$repo_root/hypr/.config/hypr/conf/window_rules.lua" \
  "$repo_root/hypr/.config/hypr/conf/windows-rules.conf"; then
  fail 'an application-specific rule can override the global transparency toggle'
fi

"$scripts/btop-float.sh" --dry-run >"$test_root/btop.out"
grep -Fq '\[float\]\ kitty\ -e\ btop' "$test_root/btop.out" ||
  fail 'btop dry-run did not preserve the floating launch rule'

touch "$test_root/state/hyprland-desktop/night-light-shader"
"$scripts/toggles-menu.sh" status >"$test_root/status.json"
jq -e '.nightlight == "on" and .dnd == "on" and .["stay-awake"] == "off" and
       .screensaver == "on" and .touchpad == "on" and .bar == "on"' \
  "$test_root/status.json" >/dev/null || fail 'toggle status was not valid state JSON'

"$scripts/toggles-menu.sh" --dry-run suspend >"$test_root/suspend.out"
grep -Fq '+ loginctl lock-session' "$test_root/suspend.out" ||
  fail 'suspend dry-run did not lock the session first'
grep -Fq '+ systemctl suspend' "$test_root/suspend.out" ||
  fail 'suspend dry-run did not include suspend'

"$scripts/toggles-menu.sh" --dry-run bar >"$test_root/bar.out"
grep -Fq 'ipc call bar toggle' "$test_root/bar.out" ||
  fail 'bar dry-run did not call the Quickshell bar IPC'

"$toggle_cli" status | jq -e '.nightlight == "on" and .bar == "on"' >/dev/null ||
  fail 'Stow-managed toggle CLI did not delegate to the toggle controller'

printf 'omakub toggle fixtures: ok\n'

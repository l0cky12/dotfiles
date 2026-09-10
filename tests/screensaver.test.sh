#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bin_root="$repo_root/screensaver/.local/bin"
test_root=$(mktemp -d -t screensaver-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$test_root/bin" "$test_root/state/toggles" "$test_root/config/branding"
cat >"$test_root/bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
SH
chmod +x "$test_root/bin/notify-send"

export PATH="$test_root/bin:$PATH"
export XDG_STATE_HOME="$test_root/state"
export XDG_CONFIG_HOME="$test_root/config"
export NOTIFY_LOG="$test_root/notify.log"
export SCREENSAVER_TERMINAL_ID=kitty.desktop
export SCREENSAVER_MONITORS_JSON='[{"name":"DP-1","focused":true},{"name":"HDMI-A-1","focused":false}]'
export SCREENSAVER_RENDERER="$bin_root/ascii-screensaver-render"

cat >"$test_root/bin/pw-dump" <<'SH'
#!/usr/bin/env bash
if [[ ${AUDIO_FIXTURE:-idle} == running ]]; then
  printf '%s\n' '[{"type":"PipeWire:Interface:Node","info":{"state":"running","props":{"media.class":"Stream/Output/Audio"}}}]'
else
  printf '%s\n' '[]'
fi
SH
chmod +x "$test_root/bin/pw-dump"

command -v jq >/dev/null 2>&1 || {
  printf 'skip: jq is not installed\n'
  exit 0
}

AUDIO_FIXTURE=running "$bin_root/ascii-screensaver" condition && fail 'playing audio did not inhibit the screensaver'
AUDIO_FIXTURE=idle "$bin_root/ascii-screensaver" condition || fail 'idle audio incorrectly inhibited the screensaver'

touch "$test_root/state/toggles/screensaver-off"
if "$bin_root/ascii-screensaver" --dry-run >"$test_root/disabled.out" 2>&1; then
  fail 'disabled automatic launch did not return 1'
fi
[[ ! -s $test_root/disabled.out ]] || fail 'disabled automatic launch printed output'

"$bin_root/ascii-screensaver" force --dry-run >"$test_root/force.out"
grep -Fq 'terminal=kitty' "$test_root/force.out" || fail 'Kitty desktop id was not resolved'
[[ $(grep -c '^monitor=' "$test_root/force.out") == 2 ]] || fail 'dry-run did not plan one spawn per monitor'
grep -Fq -- '--class=io.github.fhlkfds.screensaver' "$test_root/force.out" || fail 'dry-run omitted screensaver class'

"$bin_root/toggle-screensaver" on
[[ ! -e $test_root/state/toggles/screensaver-off ]] || fail 'toggle on left the off flag'
"$bin_root/toggle-screensaver" off
[[ -e $test_root/state/toggles/screensaver-off ]] || fail 'toggle off did not create the off flag'
"$bin_root/toggle-screensaver" status | grep -qx 'screensaver: off' || fail 'toggle status is wrong'

for id in Alacritty.desktop org.codeberg.dnkl.foot.desktop com.mitchellh.ghostty.desktop kitty.desktop; do
  SCREENSAVER_TERMINAL_ID=$id "$bin_root/ascii-screensaver" force --dry-run >"$test_root/$id.out"
done
grep -Fq -- '--config-file' "$test_root/Alacritty.desktop.out" || fail 'Alacritty config flag is missing'
grep -Fq -- '--config=' "$test_root/org.codeberg.dnkl.foot.desktop.out" || fail 'Foot config flag is missing'
grep -Fq -- '--config-file=' "$test_root/com.mitchellh.ghostty.desktop.out" || fail 'Ghostty config flag is missing'
grep -Fq -- '--override' "$test_root/kitty.desktop.out" || fail 'Kitty overrides are missing'

cat >"$test_root/bin/socat" <<'SH'
#!/usr/bin/env bash
printf 'socket-open\n' >>"$ORDER_LOG"
printf '%s\n' \
  'openwindow>>abc,1,io.github.fhlkfds.screensaver,one' \
  'openwindow>>def,1,io.github.fhlkfds.screensaver,two'
SH
cat >"$test_root/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >>"$ORDER_LOG"
SH
cat >"$test_root/bin/kitty" <<'SH'
#!/usr/bin/env bash
printf 'spawn %s\n' "$*" >>"$ORDER_LOG"
SH
chmod +x "$test_root/bin/socat" "$test_root/bin/hyprctl" "$test_root/bin/kitty"
export ORDER_LOG="$test_root/order.log"
export XDG_RUNTIME_DIR="$test_root/runtime"
export HYPRLAND_INSTANCE_SIGNATURE=test
mkdir -p "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE"
SCREENSAVER_TERMINAL_ID=kitty.desktop "$bin_root/ascii-screensaver" force
[[ $(grep -c '^spawn ' "$ORDER_LOG") == 2 ]] || fail 'event fixture did not spawn twice'
socket_line=$(grep -n '^exec {events}< ' "$bin_root/ascii-screensaver" | cut -d: -f1)
spawn_line=$(awk '/setsid/ && /command/ { print NR }' "$bin_root/ascii-screensaver")
((socket_line < spawn_line)) || fail 'event socket is not opened before terminal spawning'
grep -Fq 'hyprctl eval hl.dispatch(hl.dsp.focus({ monitor = "DP-1" }))' "$ORDER_LOG" || fail 'first monitor was not focused'
grep -Fq 'hyprctl eval hl.dispatch(hl.dsp.focus({ monitor = "HDMI-A-1" }))' "$ORDER_LOG" || fail 'second monitor was not focused'
[[ $(grep '^hyprctl ' "$ORDER_LOG" | tail -n1) == 'hyprctl eval hl.dispatch(hl.dsp.focus({ monitor = "DP-1" }))' ]] || fail 'original monitor was not restored'

"$bin_root/screensaver-lock" --dry-run >"$test_root/lock.out"
grep -Fq 'timeout 1s pidwait -x ttfx' "$test_root/lock.out" || fail 'lock cleanup does not wait for ttfx'
grep -Fq "pkill -f '[i]o.github.fhlkfds.screensaver'" "$test_root/lock.out" || fail 'lock cleanup omits terminal class'

grep -Fq -- '--random-effect --no-eol --no-restore-cursor' "$bin_root/ascii-screensaver-render" || fail 'renderer options changed'
grep -Fq "stty size" "$bin_root/ascii-screensaver-render" || fail 'renderer resize wait is missing'
grep -Fq "read -rsn1 -t 1" "$bin_root/ascii-screensaver-render" || fail 'renderer keyboard poll is missing'
grep -Fq "hl.config({ cursor = { invisible = true } })" "$bin_root/ascii-screensaver-render" || fail 'renderer does not hide the cursor through the Lua provider'
grep -Fq "hl.config({ cursor = { invisible = false } })" "$bin_root/ascii-screensaver-render" || fail 'renderer does not restore the cursor through the Lua provider'
if grep -Fq 'keyword cursor:invisible' "$bin_root/ascii-screensaver-render"; then
  fail 'renderer still uses the legacy config provider for cursor visibility'
fi

grep -Fq 'timeout = 180' "$repo_root/hypr/.config/hypr/hypridle.conf" || fail 'screensaver idle timeout is not three minutes'
grep -Fq 'ascii-screensaver" idle' "$repo_root/hypr/.config/hypr/hypridle.conf" || fail 'Hypridle does not use the audio-aware launch mode'
grep -Fq 'ascii-screensaver" condition' "$repo_root/hypr/.config/hypr/hypridle.conf" || fail 'Hypridle does not poll the audio-aware condition'
grep -Fq 'ascii-screensaver force' "$repo_root/hypr/.config/hypr/conf/keybindings.lua" || fail 'Lua config omits the manual screensaver binding'
grep -Fq 'toggle-screensaver' "$repo_root/hypr/.config/hypr/conf/keybindings.lua" || fail 'Lua config omits the screensaver toggle binding'
grep -Fq 'name = "ascii-screensaver"' "$repo_root/hypr/.config/hypr/conf/window_rules.lua" || fail 'Lua config omits the screensaver window rule'
grep -Fq 'windowrulev2 = fullscreen,class:^(io\.github\.fhlkfds\.screensaver)$' "$repo_root/hypr/.config/hypr/conf/windows-rules.conf" || fail 'legacy config omits the screensaver window rule'

printf 'screensaver fixtures: ok\n'

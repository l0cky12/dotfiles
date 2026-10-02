#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
night_light="$repo_root/hypr/.config/hypr/scripts/night-light.sh"
test_root=$(mktemp -d -t night-light-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

grep -Fq 'hl.dispatch(hl.dsp.exec_cmd(cfg.scripts_dir .. "/night-light.sh toggle"))' \
  "$repo_root/hypr/.config/hypr/conf/keybindings.lua" ||
  fail 'Lua keybinding does not dispatch the Hypr-owned wrapper'
grep -Fq '$scriptsDir/night-light.sh toggle' \
  "$repo_root/hypr/.config/hypr/conf/keybinding.conf" ||
  fail 'legacy keybinding does not use the Hypr-owned wrapper'
grep -Fq 'night-light-shader' "$repo_root/hypr/.config/hypr/hyprland.lua" ||
  fail 'Lua config does not read the shader state'
grep -Fq '#version 320 es' "$repo_root/hypr/.config/hypr/shaders/night-light.frag" ||
  fail 'night-light shader does not match the active GLES 3.2 renderer'
if grep -Rq '\[DEBUG-nightlight\]' "$repo_root/hypr/.config/hypr"; then
  fail 'temporary night-light instrumentation remains'
fi

mkdir -p "$test_root/bin"
cat >"$test_root/bin/hyprctl-fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NIGHT_LIGHT_FIXTURE_CALLS"
SH
chmod +x "$test_root/bin/hyprctl-fixture"

export NIGHT_LIGHT_STATE_FILE="$test_root/state/night-light-shader"
export NIGHT_LIGHT_HYPRCTL="$test_root/bin/hyprctl-fixture"
export NIGHT_LIGHT_FIXTURE_CALLS="$test_root/calls"
on_call="eval hl.config({ decoration = { screen_shader = [==[$HOME/.config/hypr/shaders/night-light.frag]==] } })"
off_call='eval hl.config({ decoration = { screen_shader = [==[]==] } })'

"$night_light" on
[[ -f "$NIGHT_LIGHT_STATE_FILE" ]] || fail 'on did not enable shader state'
[[ "$(<"$NIGHT_LIGHT_FIXTURE_CALLS")" == "$on_call" ]] || fail 'on did not apply the shader live'

: >"$NIGHT_LIGHT_FIXTURE_CALLS"
"$night_light" toggle
[[ ! -e "$NIGHT_LIGHT_STATE_FILE" ]] || fail 'toggle did not disable shader state'
[[ "$(<"$NIGHT_LIGHT_FIXTURE_CALLS")" == "$off_call" ]] || fail 'toggle off did not clear the shader live'

: >"$NIGHT_LIGHT_FIXTURE_CALLS"
"$night_light" toggle
[[ -f "$NIGHT_LIGHT_STATE_FILE" ]] || fail 'toggle did not enable shader state'
[[ "$(<"$NIGHT_LIGHT_FIXTURE_CALLS")" == "$on_call" ]] || fail 'toggle on did not apply the shader live'

[[ "$("$night_light" status)" == 'night-light: on (screen shader)' ]] ||
  fail 'status did not report enabled shader'

before=$(<"$NIGHT_LIGHT_STATE_FILE")
dry_run_output=$("$night_light" --dry-run off)
after=$(<"$NIGHT_LIGHT_STATE_FILE")
[[ "$before" == "$after" ]] || fail 'dry-run changed shader state'
[[ "$dry_run_output" == *'disable shader state'* && "$dry_run_output" == *'screen_shader'* ]] ||
  fail 'dry-run did not describe state and shader actions'
grep -Fq 'reload' "$NIGHT_LIGHT_FIXTURE_CALLS" && fail 'night light still does a full Hyprland reload'

printf 'ok: night-light shader fixtures\n'

#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/hypr/.config/hypr/scripts/voice-dictation"
menu="$repo_root/menu/.config/lmenu/menu.jsonc"
lua="$repo_root/hypr/.config/hypr/conf/keybindings.lua"
legacy="$repo_root/hypr/.config/hypr/conf/keybinding.conf"
test_root=$(mktemp -d -t voice-dictation-test.XXXXXX)
trap 'rm -rf "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

mkdir -p "$test_root/bin" "$test_root/hyprvoice"
cat >"$test_root/bin/wpctl" <<'SH'
#!/usr/bin/env bash
[[ $1 == inspect && $2 == @DEFAULT_AUDIO_SINK@ ]] || exit 2
cat <<'OUT'
id 103, type PipeWire:Interface:Node
  * device.id = "102"
OUT
SH
cat >"$test_root/bin/pw-dump" <<'SH'
#!/usr/bin/env bash
cat <<'JSON'
[{"type":"PipeWire:Interface:Node","info":{"props":{"media.class":"Audio/Source","node.name":"alsa_input.webcam","node.description":"Webcam","device.id":"50"}}},{"type":"PipeWire:Interface:Node","info":{"props":{"media.class":"Audio/Source","node.name":"bluez_input.airpods","node.description":"AirPods Pro","device.id":"102"}}}]
JSON
SH
cat >"$test_root/bin/hyprvoice" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$VOICE_DICTATION_CALLS"
SH
chmod +x "$test_root/bin/wpctl" "$test_root/bin/pw-dump" "$test_root/bin/hyprvoice"

config="$test_root/voice-dictation.json"
hyprvoice_config="$test_root/hyprvoice/config.toml"
calls="$test_root/calls"
cat >"$hyprvoice_config" <<'TOML'
[recording]
  device = "old-primary"
  sample_rate = 16000
  device = "old-duplicate"
TOML
export PATH="$test_root/bin:$PATH" VOICE_DICTATION_CONFIG="$config"
export HYPRVOICE_CONFIG="$hyprvoice_config" VOICE_DICTATION_CALLS="$calls"

"$script" use-default-output
[[ $("$script" resolve-source) == bluez_input.airpods ]] || fail 'default output does not resolve to its matching source'
"$script" toggle
[[ $(<"$calls") == toggle ]] || fail 'toggle did not invoke hyprvoice'
grep -Fq 'device = "bluez_input.airpods"' "$hyprvoice_config" || fail 'resolved source was not written to Hyprvoice recording config'
[[ $(grep -c '^[[:space:]]*device[[:space:]]*=' "$hyprvoice_config") == 1 ]] || fail 'Hyprvoice config has duplicate device keys'
python3 - "$hyprvoice_config" <<'PY' || fail 'Hyprvoice config is not valid TOML'
import sys
import tomllib

with open(sys.argv[1], 'rb') as config:
    assert tomllib.load(config)['recording']['device'] == 'bluez_input.airpods'
PY

"$script" use-source alsa_input.webcam
[[ $("$script" resolve-source) == alsa_input.webcam ]] || fail 'explicit source selection was not retained'
"$script" toggle --dry-run >"$test_root/dry-run"
grep -Fq 'action=would-toggle device=alsa_input.webcam' "$test_root/dry-run" || fail 'dry-run does not report the selected source'

if "$script" use-source 'bad;source' >/dev/null 2>&1; then
  fail 'unsafe source name was accepted'
fi

grep -Fq '"hyprvoice toggle"' "$lua" || fail 'Lua binding does not directly toggle Hyprvoice'
grep -Fq 'exec, hyprvoice toggle' "$legacy" || fail 'legacy binding does not directly toggle Hyprvoice'
grep -Fq 'setup.voice-dictation' "$menu" || fail 'Setup menu lacks voice dictation settings'

printf 'voice dictation: ok\n'

#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
state="$shell_dir/AudioState.qml"
panel="$shell_dir/AudioPanel.qml"
content="$shell_dir/AudioPanelContent.qml"
smoke="$shell_dir/AudioPanelSmoke.qml"
icon="$shell_dir/AudioIcon.qml"
test_root=$(mktemp -d -t audio-panel-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]"
}

assert_contains "$state" 'return list.concat(root.sinks).concat(root.sources).concat(root.streams)'
assert_contains "$state" 'n => n && n.audio && n.isStream && !n.isSink'
assert_contains "$state" 'Pipewire.preferredDefaultAudioSink = node'
assert_contains "$state" 'Pipewire.preferredDefaultAudioSource = node'
assert_contains "$state" 'node.audio.volume = Math.max(0, Math.min(1, fraction))'
assert_contains "$state" 'node.audio.muted = !node.audio.muted'
assert_contains "$state" 'DesktopEntries.heuristicLookup(lookup)'

assert_contains "$panel" 'Keys.onEscapePressed: panel.audio.panelVisible = false'
assert_contains "$panel" 'AudioPanelContent {'
assert_contains "$content" 'title: "MASTER OUTPUT"'
assert_contains "$content" 'text: "Devices"'
assert_contains "$content" 'text: "Applications"'
assert_contains "$content" 'VolumeSlider {'
assert_contains "$content" 'IconButton {'
assert_contains "$content" 'onClicked: root.audio.setSink(modelData)'
assert_contains "$content" 'onClicked: root.audio.setSource(modelData)'
assert_contains "$content" 'onClicked: root.audio.toggleStreamMute(modelData)'
assert_contains "$content" 'root.audio.deviceDescription(modelData)'
assert_contains "$content" 'root.audio.deviceName(modelData)'
assert_contains "$content" 'unavailableText: root.audio.available'

assert_contains "$icon" 'AudioState.stepVolume(wheel.angleDelta.y > 0 ? 0.03 : -0.03)'
assert_contains "$icon" 'AudioState.toggleMute()'

if grep -nE '"#[0-9a-fA-F]{3,8}"' "$state" "$panel" "$content" "$smoke"; then
  fail 'audio QML hardcodes a color instead of using Theme tokens'
fi

if command -v quickshell >/dev/null 2>&1; then
  smoke_log="$test_root/audio-smoke.log"
  QT_QPA_PLATFORM=offscreen timeout 30 quickshell -p "$smoke" >"$smoke_log" 2>&1 || true
  grep -Fq 'ok: AudioPanel fixture rendering' "$smoke_log" \
    || { sed -n '1,120p' "$smoke_log" >&2; fail 'AudioPanelSmoke.qml did not parse and render'; }
  if grep -Fq 'FAIL' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail 'AudioPanelSmoke.qml reported a failing assertion'
  fi
  printf 'ok: AudioPanelSmoke.qml (%s assertions)\n' \
    "$(grep -c '^.*ok   ' "$smoke_log" || true)"
else
  printf 'skip: quickshell is not installed, AudioPanelSmoke.qml not run\n'
fi

printf 'ok: audio-panel fixtures\n'

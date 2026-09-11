#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
state="$shell_dir/AudioState.qml"
helpers="$shell_dir/AudioHelpers.js"
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

if command -v node >/dev/null 2>&1; then
  node - "$helpers" <<'NODE'
const assert = require("node:assert/strict")
const helpers = require(process.argv[2])

assert.equal(helpers.deviceDetail({properties: {
  "device.description": "USB DAC",
  "node.description": "fallback",
  "port.alias": "undocumented"
}}), "USB DAC")
assert.equal(helpers.deviceDetail({properties: {
  "node.description": "Built-in Audio",
  "api.alsa.path": "pci-0000:00:1f.3"
}}), "Built-in Audio")
assert.equal(helpers.deviceDetail({properties: {
  "api.alsa.path": "pci-0000:00:1f.3"
}}), "pci-0000:00:1f.3")
assert.equal(helpers.deviceDetail({properties: {
  "card.profile.device": 0,
  "port.alias": "Line Out",
  "device.profile.name": "analog-stereo"
}}), "")

const audio = {}
assert.equal(helpers.isOutputDevice({audio, isSink: true, isStream: false}), true)
assert.equal(helpers.isOutputDevice({audio, isSink: true, isStream: true}), false)
assert.equal(helpers.isInputDevice({audio, isSink: false, isStream: false}), true)
assert.equal(helpers.isPlaybackStream({audio, isStream: true, isSink: false}), true)
assert.equal(helpers.isPlaybackStream({audio, isStream: true, isSink: true}), false)

assert.equal(helpers.deviceDescription(null), "Unknown")
assert.equal(helpers.deviceDescription({description: "Desk DAC", name: "raw"}), "Desk DAC")
assert.equal(helpers.deviceDescription({nickname: "Mic", name: "raw"}), "Mic")
assert.equal(helpers.streamLabel({properties: {"application.name": "Firefox"}}), "Firefox")
assert.equal(helpers.streamLabel({properties: {"application.process.binary": "mpv"}}), "mpv")
assert.equal(helpers.streamLabel({description: "Playback", properties: {}}), "Playback")

const entries = {
  byId(id) {
    return id === "org.example.Player" ? {name: "Player", icon: "player"} : null
  }
}
assert.equal(helpers.desktopEntryFor({properties: {
  "application.desktop-entry": "org.example.Player.desktop",
  "application.name": "Exact application name"
}}, entries).name, "Player")
assert.equal(helpers.desktopEntryFor({description: "Player", properties: {}}, entries), null)
assert.equal(helpers.desktopEntryFor({properties: {
  "application.desktop-entry": "org.example.Player"
}}, {
  byId(id) {
    return {name: id === "org.example.Player" ? "Exact ID" : "Fallback ID"}
  }
}).name, "Exact ID")

assert.equal(helpers.clampVolume(-0.2), 0)
assert.equal(helpers.clampVolume(0.42), 0.42)
assert.equal(helpers.clampVolume(1.5), 1)
assert.equal(helpers.volumePercent(1.5), 150)
assert.equal(helpers.volumePercent(0.555), 56)
console.log("ok: AudioHelpers.js executable assertions")
NODE
else
  printf 'skip: node is not installed, AudioHelpers.js assertions not run\n'
fi

if grep -nE '"#[0-9a-fA-F]{3,8}"' "$helpers" "$state" "$panel" "$content" "$smoke"; then
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

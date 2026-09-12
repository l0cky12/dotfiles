#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
assistant="$repo_root/noctalia/.config/noctalia/plugins/assistant-panel"
toolkit="$repo_root/noctalia/.config/noctalia/plugins/screen-toolkit"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]"
}

command -v node >/dev/null 2>&1 || fail 'node is required for the retention fixture'

# Persistence must require an explicit opt-in in both metadata and runtime code.
node - "$assistant/manifest.json" <<'JS'
const fs = require("fs");
const manifest = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const defaults = manifest.metadata.defaultSettings;
if (defaults.persistChatHistory !== false)
  throw new Error("chat persistence must default to false");
if (defaults.maxHistoryLength !== 20)
  throw new Error("persisted history must default to 20 messages");
JS
assert_contains "$assistant/Settings.qml" 'defaultValue: false'
assert_contains "$assistant/Main.qml" 'if (!persistChatHistory)'
assert_contains "$assistant/Main.qml" 'if (persistChatHistory)'

# Exercise the serializer: an oversized/legacy preference must still retain
# only the newest 20 entries.
node - "$assistant/ProviderLogic.js" <<'JS'
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(process.argv[2], "utf8")
  .replace(/^\.pragma library\s*/, "");
const context = {};
vm.createContext(context);
vm.runInContext(source, context);
const messages = Array.from({length: 30}, (_, id) => ({id}));
const saved = JSON.parse(context.prepareStateForSave(messages, "ai", 500, "draft", 5));
if (saved.messages.length !== 20 || saved.messages[0].id !== 10 || saved.messages[19].id !== 29)
  throw new Error("serializer did not retain exactly the newest 20 messages");
JS

# Clear-history removes the backing file, and QML corrects host/FileView modes.
assert_contains "$assistant/Main.qml" '["rm", "-f", "--", stateCachePath]'
assert_contains "$assistant/Main.qml" '["chmod", "0600", stateCachePath]'
assert_contains "$assistant/Settings.qml" '["chmod", "0600", settingsPath]'
assert_contains "$toolkit/Settings.qml" '["chmod", "0600", settingsPath]'

# Every shell helper that creates image/video files uses a user-only creation
# mask. Keep this list explicit so a non-writing picker/uploader is not confused
# with the scripts that own file creation.
file_writers=(
    annotate.sh capture.sh color-picker.sh lens-upload.sh measure.sh
    mirror-record.sh mirror-screenshot.sh ocr.sh record.sh
)
for name in "${file_writers[@]}"; do
    script="$toolkit/scripts/$name"
    grep -Eq '^umask 0?77$' "$script" || fail "$script does not set umask 077"
done

bash -n "$0" "$toolkit"/scripts/*.sh

printf 'plugin secret hygiene tests passed\n'

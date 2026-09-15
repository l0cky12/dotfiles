#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
widget="$repo_root/noctalia/.config/noctalia/plugins/arch-updater/BarWidget.qml"
manifest="$repo_root/noctalia/.config/noctalia/plugins/arch-updater/manifest.json"

awk '/mouse.button === Qt.LeftButton/,/else if/ { found = found || /mainInstance.update/ } END { exit !found }' "$widget"
grep -Fq '"updateCmd": "$HOME/.config/hypr/scripts/arch-updates update"' "$manifest"

printf 'arch updater widget: ok\n'

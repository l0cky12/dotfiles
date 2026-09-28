#!/usr/bin/env bash
# The bar's workspace strip has to read on light themes as well as dark ones:
# icons take their colour from theme roles, the bundled SVGs (which ship with a
# fixed light fill) are repainted with that colour, and a workspace is only
# shown while it is focused or has windows. Static checks only; no Hyprland
# state is used.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
qs="$repo_root/quickshell/.config/quickshell"
module="$qs/WorkspacesModule.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

grep -Fq 'readonly property bool isOccupied' "$module" \
  || fail 'workspace cells do not track whether a workspace has windows'
grep -Fq 'toplevels.values.length > 0' "$module" \
  || fail 'occupied state is not derived from the workspace toplevels'
grep -Fq 'visible: isFocused || isOccupied || Hyprland.focusedWorkspace === null' "$module" \
  || fail 'empty, unfocused workspaces are not hidden'

grep -Fq 'isFocused ? Theme.onAccent' "$module" \
  || fail 'focused icon does not use the on-accent role'
grep -Fq 'Theme.onAccent : Theme.text' "$module" \
  || fail 'unfocused icon does not use the primary text role'
! grep -Fq 'Theme.bgDeep' "$module" \
  || fail 'focused icon still uses bgDeep, which is light on light themes'

# The SVGs must be recoloured, not drawn with their baked-in fill.
grep -Fq 'data:image/svg+xml' "$module" \
  || fail 'svg icons are drawn with their baked-in fill'
grep -Fq "'fill=\"' + cell.iconColor + '\"'" "$module" \
  || fail 'svg fill is not replaced with the icon colour'

# Every bundled SVG the strip uses needs a hex fill for the repaint to hit.
while IFS= read -r svg; do
  [[ -f "$qs/$svg" ]] || fail "missing workspace icon $svg"
  grep -Eq 'fill="#[0-9a-fA-F]{3,8}"' "$qs/$svg" \
    || fail "$svg has no hex fill attribute to recolour"
done < <(grep -oE 'svg: "[^"]+"' "$module" | sed -E 's/svg: "([^"]+)"/\1/')

printf 'workspaces module: ok\n'

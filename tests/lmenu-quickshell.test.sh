#!/usr/bin/env bash
# The resident lmenu: the parser's dump document, the Quickshell state that
# navigates and searches it, and the wiring that opens it without a process.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
qs_root="$repo_root/quickshell/.config/quickshell"
parser="$repo_root/menu/.config/lmenu/lmenu-parse.py"
smoke="$qs_root/LmenuSmoke.qml"
test_root=$(mktemp -d -t lmenu-quickshell-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cat >"$test_root/menu.jsonc" <<'JSON'
[
  { "id": "s", "label": "Section" },
  { "id": "s.sub", "label": "Sub", "aliases": ["nested-menu"] },
  { "id": "s.sub.deep", "label": "Deep", "aliases": ["buried"],
    "description": "Two levels down", "action": "echo deep" },
  { "id": "s.gone", "label": "Gone", "when": "false" },
  { "id": "s.gone.child", "label": "Orphaned", "action": "true" },
  { "id": "s.dim", "label": "Dim", "disabled": "true" },
  { "id": "s.dim.child", "label": "Unreachable", "action": "true" },
  { "id": "s.fonts", "label": "Fonts", "provider": "fonts" },
  { "id": "s.leaf", "label": "Leaf", "checked": "true", "action": "echo leaf" },
  { "id": "link", "label": "Jump to Sub", "target": "nested-menu" }
]
JSON

# The dump is the whole reachable tree: pruned like browsing, links resolved
# to their canonical target, generated rows prefetched, aliases included.
LMENU_MENU="$test_root/menu.jsonc" LMENU_EXTENSIONS=/nonexistent \
  python3 "$parser" dump >"$test_root/dump.json"
python3 - "$test_root/dump.json" <<'PY' || fail 'the dump document is wrong'
import json, sys
doc = json.load(open(sys.argv[1]))
ids = [entry["id"] for entry in doc["entries"]]
assert ids == ["s", "s.sub", "s.sub.deep", "s.dim", "s.fonts", "s.leaf", "link"], ids
by_id = {entry["id"]: entry for entry in doc["entries"]}
assert by_id["link"]["kind"] == "link" and by_id["link"]["payload"] == "s.sub"
assert by_id["s.dim"]["disabled"] and not by_id["s.sub"]["disabled"]
assert by_id["s.leaf"]["checked"] and by_id["s.leaf"]["payload"] == "echo leaf"
assert by_id["s.sub.deep"]["search"] == "buried Two levels down"
assert by_id["s.sub.deep"]["parent"] == "s.sub"
assert not by_id["s.fonts"]["searchable"]
assert "s.fonts" in doc["providers"]
assert all(row["id"].startswith("s.fonts#") for row in doc["providers"]["s.fonts"])
assert doc["aliases"]["nested-menu"] == "s.sub"
PY

# A dimmed provider is unreachable, so its rows are not generated at all.
cat >"$test_root/dim-provider.jsonc" <<'JSON'
[ { "id": "f", "label": "Fonts", "provider": "fonts", "disabled": "true" } ]
JSON
LMENU_MENU="$test_root/dim-provider.jsonc" LMENU_EXTENSIONS=/nonexistent \
  python3 "$parser" dump >"$test_root/dim.json"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["providers"] == {}' \
  "$test_root/dim.json" || fail 'a dimmed provider still generated its rows'

# Super+Shift+A reaches the shell through a global shortcut, not a process.
grep -Fq 'hl.dsp.global("quickshell:lmenu")' "$repo_root/hypr/.config/hypr/conf/keybindings.lua" ||
  fail 'Super+Shift+A does not use the lmenu global shortcut'
grep -Fq 'name: "lmenu"' "$qs_root/Bar.qml" ||
  fail 'the bar does not register the lmenu global shortcut'
grep -Fq 'target: "lmenu"' "$qs_root/Bar.qml" || fail 'the bar has no lmenu IPC target'
grep -Fq 'LmenuPanel {' "$qs_root/Bar.qml" || fail 'the bar does not mount the lmenu panel'

if command -v quickshell >/dev/null 2>&1; then
  smoke_log="$test_root/smoke.log"
  LMENU_MENU="$test_root/menu.jsonc" LMENU_EXTENSIONS=/nonexistent LMENU_PARSER="$parser" \
    QT_QPA_PLATFORM=offscreen timeout 30 quickshell -p "$smoke" >"$smoke_log" 2>&1 || true
  if grep -Fq 'FAIL' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail 'LmenuSmoke.qml reported a failing assertion'
  fi
  grep -Fq 'ok: lmenu resident menu' "$smoke_log" || {
    sed -n '1,120p' "$smoke_log" >&2
    fail 'LmenuSmoke.qml did not finish'
  }
  # PanelWindow needs a Wayland backend. The fixture keeps the panel invisible
  # while checking that hundreds of rows fit within its viewport.
  if [[ -n ${WAYLAND_DISPLAY:-} ]]; then
    panel_log="$test_root/panel.log"
    timeout 30 quickshell -p "$qs_root/LmenuPanelSmoke.qml" >"$panel_log" 2>&1 || true
    grep -Fq 'ok: lmenu panel compiles' "$panel_log" || {
      sed -n '1,80p' "$panel_log" >&2
      fail 'LmenuPanel.qml does not compile'
    }
  else
    printf 'skip: no Wayland display; LmenuPanel.qml was not compiled\n'
  fi
else
  printf 'skip: quickshell is not installed; ran the parser checks only\n'
fi

printf 'lmenu quickshell: ok\n'

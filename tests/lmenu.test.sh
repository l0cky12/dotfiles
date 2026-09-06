#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
parser="$repo_root/menu/.config/lmenu/lmenu-parse.py"
menu="$repo_root/menu/.config/lmenu/menu.jsonc"
cli="$repo_root/menu/.local/bin/lmenu"
test_root=$(mktemp -d -t lmenu-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# The shipped menu must parse and every id must resolve to a real branch.
LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 "$parser" validate \
  >"$test_root/validate.out" 2>&1 ||
  fail 'the shipped menu does not parse'
grep -Fq 'ok:' "$test_root/validate.out" || fail 'validate did not report success'

# All eleven root sections are present.
LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 "$parser" rows '' \
  >"$test_root/root.out"
for section in Apps Development Learn Trigger Style Setup Install Remove Update About System; do
  grep -Pq "\t$section\t" "$test_root/root.out" ||
    fail "the root menu is missing the $section section"
done

# The dotted id is the tree: style.bar.position nests under style.bar.
LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 "$parser" rows style.bar \
  >"$test_root/bar.out"
grep -Fq 'style.bar.position' "$test_root/bar.out" ||
  fail 'style.bar.position is not a child of style.bar'
grep -Fq 'style.bar.toggle' "$test_root/bar.out" ||
  fail 'style.bar.toggle is not a child of style.bar'
grep -Fq 'style.theme' "$test_root/bar.out" &&
  fail 'style.theme leaked into the style.bar view'

# Aliases route, case-insensitively and with underscores folded to dashes.
[[ $(LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 "$parser" route Themes) == style.theme ]] ||
  fail 'the "Themes" alias does not route to style.theme'
[[ $(LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 "$parser" route system_info) == about ]] ||
  fail 'underscores are not folded when routing aliases'
[[ $(LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 "$parser" route '') == '' ]] ||
  fail 'an empty route does not resolve to the root'
[[ $(LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 "$parser" route nope.nope) == nope.nope ]] ||
  fail 'an unknown route does not fall back to a literal id'

# Guard batching: when hides, checked ticks, disabled dims and stays visible.
cat >"$test_root/guards.jsonc" <<'JSON'
[
  { "id": "g", "label": "Guards" },
  { "id": "g.shown", "label": "Shown", "when": "true", "action": "true" },
  { "id": "g.hidden", "label": "Hidden", "when": "false", "action": "true" },
  { "id": "g.ticked", "label": "Ticked", "checked": "true", "action": "true" },
  { "id": "g.dim", "label": "Dim", "disabled": "true", "action": "true" },
  { "id": "g.broken", "label": "Broken", "when": "if then fi ((", "action": "true" },
  { "id": "g.exits", "label": "Exits", "when": "exit 3", "action": "true" }
]
JSON
LMENU_MENU="$test_root/guards.jsonc" LMENU_EXTENSIONS=/nonexistent \
  python3 "$parser" rows g >"$test_root/guards.out"
grep -Fq 'Shown' "$test_root/guards.out" || fail 'a true "when" guard hid its row'
grep -Fq 'Hidden' "$test_root/guards.out" && fail 'a false "when" guard did not hide its row'
grep -Pq 'Ticked\t✓' "$test_root/guards.out" || fail 'a true "checked" guard did not tick its row'
grep -Pq 'Dim\t✓' "$test_root/guards.out" || fail 'a true "disabled" guard did not tick its row'
grep -Fq '#urgent:' "$test_root/guards.out" || fail 'disabled rows are not reported as urgent'
grep -Fq 'Broken' "$test_root/guards.out" &&
  fail 'a guard with a bash syntax error was treated as true'
grep -Fq 'Exits' "$test_root/guards.out" &&
  fail 'a guard exiting nonzero was treated as true'
# A broken guard must not abort the render: its siblings still came through.
grep -Fq 'Shown' "$test_root/guards.out" ||
  fail 'a broken guard aborted the whole render'

# A disabled row is not selectable.
[[ $(LMENU_MENU="$test_root/guards.jsonc" LMENU_EXTENSIONS=/nonexistent \
  python3 "$parser" resolve g g.dim | cut -f1) == disabled ]] ||
  fail 'a disabled row resolved to a runnable action'

# The overlay merges per key: same id keeps its position and its undeclared
# fields, a new id appends, and its parent comes from the dotted id.
cat >"$test_root/overlay.jsonc" <<'JSON'
// retitle one shipped row and add one of our own
[
  { "id": "g.shown", "label": "Renamed" },
  { "id": "g.extra", "label": "Extra", "action": "true" }
]
JSON
LMENU_MENU="$test_root/guards.jsonc" LMENU_EXTENSIONS="$test_root/overlay.jsonc" \
  python3 "$parser" rows g >"$test_root/overlay.out"
grep -Fq 'Renamed' "$test_root/overlay.out" || fail 'the overlay did not retitle a shipped row'
grep -Fq 'Extra' "$test_root/overlay.out" || fail 'the overlay did not add a new row'
[[ $(grep -c . "$test_root/overlay.out") -gt 0 ]] || fail 'the overlay emptied the view'
[[ $(head -n 1 "$test_root/overlay.out" | cut -f2) == Renamed ]] ||
  fail 'the retitled row lost its original position'
[[ $(grep -Fc 'g.extra' "$test_root/overlay.out") == 1 ]] ||
  fail 'the appended row is not in its inferred parent'
LMENU_MENU="$test_root/guards.jsonc" LMENU_EXTENSIONS="$test_root/overlay.jsonc" \
  python3 "$parser" resolve g g.shown >"$test_root/kept.out"
grep -Fq 'true' "$test_root/kept.out" ||
  fail 'the retitled row lost the action it did not redeclare'

# A broken overlay warns and falls back to the shipped menu.
printf '%s\n' '[ { "id": "g.shown"' >"$test_root/broken.jsonc"
LMENU_MENU="$test_root/guards.jsonc" LMENU_EXTENSIONS="$test_root/broken.jsonc" \
  python3 "$parser" rows g >"$test_root/broken.out" 2>"$test_root/broken.err"
grep -Fq 'ignoring broken extension file' "$test_root/broken.err" ||
  fail 'a broken overlay did not warn'
grep -Fq 'Shown' "$test_root/broken.out" ||
  fail 'a broken overlay did not fall back to the shipped menu'

# iconFont is accepted and discarded so Omarchy-shaped files parse cleanly.
printf '%s\n' '[ { "id": "x", "label": "X", "iconFont": "nerd", "action": "true" } ]' \
  >"$test_root/iconfont.jsonc"
LMENU_MENU="$test_root/iconfont.jsonc" LMENU_EXTENSIONS=/nonexistent \
  python3 "$parser" rows '' >/dev/null || fail 'iconFont was not accepted and discarded'

# The dry run resolves guards and names the kind of each row.
LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 "$parser" --dry-run system \
  >"$test_root/system.out"
grep -Fq 'Reboot' "$test_root/system.out" || fail 'the System menu is missing Reboot'
grep -Fq 'systemctl poweroff' "$test_root/system.out" ||
  fail 'the System menu does not shut down through systemctl'
grep -Fq 'omarchy' "$test_root/system.out" &&
  fail 'the System menu still calls an omarchy script'

# No action anywhere in the shipped menu may call an omarchy script.
grep -Fq 'omarchy-' "$menu" && fail 'the shipped menu still references omarchy scripts'

# The CLI resolves its own parser and dry-runs without launching rofi.
LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent LMENU_PARSER="$parser" \
  "$cli" --dry-run system >"$test_root/cli.out"
grep -Fq 'system.reboot' "$test_root/cli.out" ||
  fail 'the CLI dry run does not reach the System menu'

# The ratio toggle reads its ratio live rather than hard-coding one.
HYPRCTL="$test_root/fake-hyprctl" "$repo_root/menu/.local/bin/lmenu-toggle-ratio" status \
  >"$test_root/ratio.out"
grep -qx '0' "$test_root/ratio.out" || fail 'the ratio toggle does not report an off state'
cat >"$test_root/fake-hyprctl" <<'FAKE'
#!/usr/bin/env bash
printf '{"float": 0.55}\n'
FAKE
chmod +x "$test_root/fake-hyprctl"
HYPRCTL="$test_root/fake-hyprctl" \
  "$repo_root/menu/.local/bin/lmenu-toggle-ratio" --dry-run toggle >"$test_root/ratio2.out"
grep -Fq 'save master:mfact=0.55' "$test_root/ratio2.out" ||
  fail 'the ratio toggle does not read the live ratio before overriding it'

# Providers generate their own rows. The themes provider must strip the
# asterisk `theme list` uses to mark the active theme, and must tick exactly
# the theme `theme current` reports.
if [[ -x $HOME/.local/bin/theme ]]; then
  LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 "$parser" rows style.theme \
    >"$test_root/themes.out"
  grep -Pq '\tstyle\.theme#\*' "$test_root/themes.out" &&
    fail 'the themes provider kept the active-theme marker as a slug'
  current=$("$HOME/.local/bin/theme" current)
  grep -Pq "\t\Q$current\E\t✓" "$test_root/themes.out" ||
    fail 'the themes provider does not tick the active theme'
fi

# The fonts provider ticks whatever fc-match resolves to.
if command -v fc-match >/dev/null; then
  LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 "$parser" rows style.font \
    >"$test_root/fonts.out"
  [[ $(grep -Fc '✓' "$test_root/fonts.out") == 1 ]] ||
    fail 'the fonts provider does not tick exactly one family'
fi

# Install rows dim when the package is present; Remove rows hide when it is not.
LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 "$parser" --dry-run install.browser \
  >"$test_root/install.out"
grep -Pq 'Firefox\t' "$test_root/install.out" ||
  fail 'the Install menu dropped a row instead of dimming it'

# Rows must render as "icon  label" with no id leaking into the visible text.
# Tab is an IFS whitespace character, so a naive `IFS=$'\t' read` collapses the
# two tabs of an empty suffix and shifts the id into the suffix column - which
# both duplicated the label on screen and left the id empty, making unticked
# rows unselectable.
LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent LMENU_PARSER="$parser" \
  "$cli" --dry-run-display '' >"$test_root/display.out"
[[ $(grep -c . "$test_root/display.out") == 11 ]] ||
  fail 'the root menu does not render exactly eleven sections'
# A row may carry a suffix column, but only a chevron or a tick belongs there -
# never an id. Strip a trailing suffix, then require what is left to be a single
# "icon  label" pair.
while IFS= read -r rendered; do
  stripped=${rendered%%[[:space:]]*[›✓]}
  [[ $stripped == *"  "*"  "* ]] &&
    fail "row \"$rendered\" has an unexpected third column; an id leaked into the label"
done <"$test_root/display.out"
grep -Eq '^󰀻  Apps +›$' "$test_root/display.out" ||
  fail 'the Apps row does not render as an icon, a label and a chevron'
grep -Fq 'Apps  apps' "$test_root/display.out" &&
  fail 'the Apps row still repeats its id after its label'
grep -Fq 'Learn  learn' "$test_root/display.out" &&
  fail 'the Learn row still repeats its id after its label'

# A ticked row keeps its check mark, and an unticked row still yields its id
# (the same collapse previously left row_id empty on every unticked row).
LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent LMENU_PARSER="$parser" \
  "$cli" --dry-run-display trigger.toggle >"$test_root/toggle-display.out"
grep -Fq '✓' "$test_root/toggle-display.out" ||
  fail 'ticked toggle rows lost their check mark'
[[ $(LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 "$parser" \
  resolve '' apps | cut -f1) == provider ]] ||
  fail 'the Apps row does not resolve to its provider'

# Learn rows: the keybindings row reuses the Super+K palette, and every
# reference opens in the default browser via xdg-open rather than a hard-coded
# browser binary.
LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 "$parser" --dry-run learn \
  >"$test_root/learn.out"
grep -Pq 'Keybindings\t.*quickshell ipc call keybinds toggle' "$test_root/learn.out" ||
  fail 'the Learn keybindings row does not open the Super+K palette'
grep -Fq 'https://www.lazyvim.org/' "$test_root/learn.out" ||
  fail 'the Learn editor row does not open the LazyVim docs'
grep -Fq 'https://devhints.io/bash' "$test_root/learn.out" ||
  fail 'the Learn bash row does not open the devhints cheatsheet'
grep -Fq 'https://wiki.hypr.land/' "$test_root/learn.out" ||
  fail 'the Learn Hyprland row does not open the Hyprland wiki'
grep -Fq 'https://wiki.archlinux.org/' "$test_root/learn.out" ||
  fail 'the Learn Arch row does not open the Arch wiki'
while IFS= read -r learn_row; do
  [[ $learn_row == \#* ]] && continue
  case $learn_row in
    *"xdg-open http"*|*"quickshell ipc call keybinds toggle") ;;
    *) fail "Learn row \"$learn_row\" neither uses xdg-open nor the keybinds palette" ;;
  esac
done <"$test_root/learn.out"

# Every entry needs an icon. Nerd Font glyphs in the U+E000 private-use range
# do not survive every editing path, so the menu uses the U+F0000 plane and this
# guards against a glyph being silently dropped to an empty string again.
LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 - "$menu" <<'PYCHECK' ||
import json, pathlib, re, sys
src = pathlib.Path(sys.argv[1]).read_text()
stripped = "\n".join("" if l.lstrip().startswith("//") else l for l in src.splitlines())
data = json.loads(re.sub(r",(\s*[}\]])", r"\1", stripped))
missing = [e["id"] for e in data if not e.get("icon")]
if missing:
    print("entries with no icon: " + ", ".join(missing))
    sys.exit(1)
PYCHECK
  fail 'some menu entries lost their icon'

# Rows that descend get a chevron; rows reporting state get a tick, and a tick
# outranks a chevron. Suffixes are padded into a column of their own.
LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent LMENU_PARSER="$parser" \
  "$cli" --dry-run-display trigger >"$test_root/trigger.out"
grep -Eq '^.*  Capture +›$' "$test_root/trigger.out" ||
  fail 'the Capture submenu row has no chevron'
grep -q 'Emoji' "$test_root/trigger.out" || fail 'the Trigger menu lost its Emoji row'
grep -q 'Emoji.*›' "$test_root/trigger.out" &&
  fail 'a leaf row was given a chevron'

# Every chevron in a view must land in the same column.
awk '/›/ { print index($0, "›") }' "$test_root/trigger.out" | sort -u \
  >"$test_root/chevron-cols.out"
[[ $(grep -c . "$test_root/chevron-cols.out") == 1 ]] ||
  fail 'chevrons do not line up in a single column'

# A ticked row shows a tick, not a chevron, even though it also descends.
LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent LMENU_PARSER="$parser" \
  "$cli" --dry-run-display trigger.toggle >"$test_root/toggle-suffix.out"
grep -q '›' "$test_root/toggle-suffix.out" &&
  fail 'leaf toggle rows were given chevrons'

# The Trigger section keeps the requested order and its promoted rows.
mapfile -t trigger_order < <(sed -E 's/^[^ ]*  //; s/ +[›✓]$//' "$test_root/trigger.out")
[[ ${trigger_order[0]} == Emoji ]] || fail 'Emoji is not the first Trigger row'
[[ ${trigger_order[1]} == Reminder ]] || fail 'Reminder is not the second Trigger row'
[[ ${trigger_order[2]} == Capture ]] || fail 'Capture is not the third Trigger row'
[[ ${trigger_order[3]} == Transcode ]] || fail 'Transcode is not the fourth Trigger row'
[[ ${trigger_order[4]} == Share ]] || fail 'Share is not the fifth Trigger row'
[[ ${trigger_order[5]} == Toggle ]] || fail 'Toggle is not the sixth Trigger row'
[[ ${trigger_order[6]} == "Speed Test" ]] || fail 'Speed Test is not the seventh Trigger row'
grep -Fq '"action": "quickshell ipc call speedtest toggle"' "$menu" ||
  fail 'Speed Test does not launch the visual overlay'

# Transcode moved to the Trigger root, so it must no longer sit under Capture.
LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent python3 "$parser" rows trigger.capture \
  >"$test_root/capture.out"
grep -Fq 'trigger.capture.transcode' "$test_root/capture.out" &&
  fail 'Transcode is still duplicated inside Capture'

# The list theme exists, follows the palette and stays monospace, which is what
# makes the padded suffix column line up.
lmenu_theme="$repo_root/rofi/.config/rofi/lmenu.rasi"
[[ -f $lmenu_theme ]] || fail 'the lmenu list theme is missing'
grep -Fq '@theme "~/.config/rofi/current-theme.rasi"' "$lmenu_theme" ||
  fail 'the lmenu theme does not follow the generated palette'
grep -Fq 'JetBrainsMono Nerd Font' "$lmenu_theme" ||
  fail 'the lmenu theme is not monospace, so padded suffixes will not align'

# Rofi only renders -p when the inputbar contains the prompt widget. Without it
# every menu silently shows the entry placeholder instead of its title.
if command -v rofi >/dev/null; then
  rofi -theme "$lmenu_theme" -dump-theme 2>/dev/null |
    sed -n '/^[[:space:]]*inputbar {/,/^[[:space:]]*}/p' |
    grep -q '"prompt"' ||
    fail 'the inputbar has no prompt widget, so menu titles will not be shown'
fi
if command -v rofi >/dev/null; then
  rofi -theme "$lmenu_theme" -dump-theme >/dev/null 2>&1 ||
    fail 'rofi cannot parse the lmenu theme'
fi

# Backspace walks back up the tree. parent_route drives that, so check the
# mapping directly first.
parent_of() {
  LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent LMENU_PARSER="$parser" \
    "$cli" parent "$1"
}
[[ $(parent_of trigger.capture.record) == trigger.capture ]] ||
  fail 'a three-deep route does not step back one level'
[[ $(parent_of style.theme) == style ]] || fail 'a two-deep route does not step back to its section'
[[ -z $(parent_of trigger) ]] || fail 'a top-level section does not step back to the root'
[[ -z $(parent_of '') ]] || fail 'the root reports a parent'

# Drive the real navigation loop with a stand-in rofi, so the back behaviour is
# exercised rather than inferred. The stand-in records its arguments and exits
# with the status rofi uses for the custom-1 keybinding.
fake_rofi="$test_root/fake-rofi"
cat >"$fake_rofi" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_LOG"
cat >/dev/null
# Cap the rounds. Without this a navigation bug that never terminates - say
# the root failing to close - hangs the suite instead of failing it.
if (($(grep -c . "$FAKE_LOG") > 12)); then
  exit 1
fi
exit "${FAKE_EXIT:-10}"
FAKE
chmod +x "$fake_rofi"

run_menu() {
  local start=$1 exit_code=$2
  : >"$test_root/rofi.log"
  FAKE_LOG="$test_root/rofi.log" FAKE_EXIT="$exit_code" \
  XDG_STATE_HOME="$test_root/state" ROFI="$fake_rofi" \
  LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent LMENU_PARSER="$parser" \
    "$cli" summon "$start" >/dev/null 2>&1 || true
  grep -c . "$test_root/rofi.log"
}

# Backspace from three levels down walks up one view at a time, then closes.
[[ $(run_menu trigger.capture 10) == 3 ]] ||
  fail 'Backspace does not walk back up one level at a time'
grep -q -- '-p Capture' "$test_root/rofi.log" || fail 'the walk back did not start at Capture'
grep -q -- '-p Trigger' "$test_root/rofi.log" || fail 'the walk back did not pass through Trigger'
grep -q -- '-p Menu' "$test_root/rofi.log" || fail 'the walk back did not reach the root menu'

# Backspace at the root closes the menu instead of reopening it.
[[ $(run_menu '' 10) == 1 ]] || fail 'Backspace at the root does not close the menu'

# Development exposes built-in Docker environments from the Super+Shift+A root.
development_rows=$(LMENU_MENU="$menu" LMENU_EXTENSIONS=/nonexistent "$parser" rows development.docker)
grep -Fq $'MySQL' <<<"$development_rows" || fail 'Development is missing MySQL'
grep -Fq $'PostgreSQL' <<<"$development_rows" || fail 'Development is missing PostgreSQL'
grep -Fq $'MariaDB' <<<"$development_rows" || fail 'Development is missing MariaDB'
grep -Fq $'Redis' <<<"$development_rows" || fail 'Development is missing Redis'

# Escape still cancels outright, from any depth.
[[ $(run_menu trigger.capture 1) == 1 ]] || fail 'cancelling does not close the menu'

# Backspace must be rebound off character deletion, or rofi refuses the
# duplicate binding; Shift+Backspace and Ctrl+H keep deleting.
grep -q -- '-kb-custom-1 BackSpace' "$test_root/rofi.log" ||
  fail 'Backspace is not bound to the back action'
grep -q -- '-kb-remove-char-back Shift+BackSpace,Control+h' "$test_root/rofi.log" ||
  fail 'character deletion was not moved off plain Backspace'

printf 'ok\n'

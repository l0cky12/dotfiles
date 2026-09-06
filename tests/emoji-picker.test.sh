#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
picker="$repo_root/hypr/.config/hypr/scripts/RofiEmoji.sh"
theme="$repo_root/rofi/.config/rofi/emoji.rasi"
test_root=$(mktemp -d -t emoji-picker-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

"$picker" --dry-run >"$test_root/rows.out"

rows=$(grep -c . "$test_root/rows.out")
((rows > 1000)) || fail "only $rows emoji rows were generated"

# The grid shows the glyph alone: everything before the NUL must be one token.
awk -F'@' '$1 ~ /[[:space:]]/ { print; found = 1 } END { exit(found ? 0 : 1) }' \
  "$test_root/rows.out" >"$test_root/spaced.out" &&
  fail "$(grep -c . "$test_root/spaced.out") rows draw more than the glyph"

# Keywords survive as invisible search terms rather than being dropped.
grep -Fq '😀@meta|grinning face' "$test_root/rows.out" ||
  fail 'the grinning face row lost its meta search keywords'
grep -cFq '@meta|' "$test_root/rows.out" ||
  fail 'rows are missing the meta row option'
[[ $(grep -Fc '@meta|' "$test_root/rows.out") == "$rows" ]] ||
  fail 'not every row carries meta search terms'

# Selection maps by index, so the glyph list must stay in lockstep with the rows.
glyphs=$(sed -n '/^# # DATA # #$/,/^# # END DATA # #$/p' "$picker" |
  sed '1d;$d' | awk 'NF>=2{print $1}' | grep -c .)
[[ $glyphs == "$rows" ]] ||
  fail "the glyph list ($glyphs) and the row list ($rows) have drifted apart"

# The theme is a grid, keeps following the generated palette, and renders
# colour emoji.
grep -Eq '^\s*columns:\s*8;' "$theme" || fail 'the emoji theme is not an 8-column grid'
grep -Fq '@theme "~/.config/rofi/current-theme.rasi"' "$theme" ||
  fail 'the emoji theme no longer follows the generated palette'
grep -Fq 'Noto Color Emoji' "$theme" || fail 'the emoji theme does not use a colour emoji font'

# Rofi sizes a row from the element's own font. Setting the emoji font only on
# element-text leaves rows sized for the inherited UI font and clips every
# glyph to its top half, so assert the font is resolved on `element` itself.
if command -v rofi >/dev/null; then
  rofi -theme "$theme" -dump-theme >"$test_root/dump.rasi" 2>/dev/null
  sed -n '/^[[:space:]]*element {/,/^[[:space:]]*}/p' "$test_root/dump.rasi" |
    grep -Fq 'Noto Color Emoji' ||
    fail 'the emoji font is not set on element, so rows will clip the glyphs'
  sed -n '/^[[:space:]]*listview {/,/^[[:space:]]*}/p' "$test_root/dump.rasi" |
    grep -Eq 'columns:[[:space:]]*8;' ||
    fail 'the resolved theme is not an 8-column grid'
fi
grep -Fq 'placeholder: "Search emojis…";' "$theme" ||
  fail 'the emoji theme lost its search placeholder'
grep -Eq 'children:[[:space:]]*\[[[:space:]]*"element-text"[[:space:]]*\];' "$theme" ||
  fail 'grid cells are not text-only'

# A cell must be wide enough for a whole glyph. Rofi has no theme-level
# ellipsize control, so a glyph that does not fit is ellipsized away and the
# cell renders empty - which looks like the emoji simply vanished. Measure the
# glyph with the same Pango stack rofi uses, then check it against the width
# each column actually gets.
if python3 -c "import gi; gi.require_version('PangoCairo','1.0')" 2>/dev/null; then
  python3 - "$theme" <<'PYFIT' || fail 'emoji do not fit their grid cells; they will render blank'
import gi, re, sys, pathlib
gi.require_version('Pango', '1.0'); gi.require_version('PangoCairo', '1.0')
from gi.repository import Pango, PangoCairo
import cairo

theme = pathlib.Path(sys.argv[1]).read_text()

def prop(block, name, default=None):
    m = re.search(r'%s\s*\{(.*?)\}' % block, theme, re.S)
    if m:
        v = re.search(r'\b%s:\s*([^;]+);' % name, m.group(1))
        if v:
            return v.group(1).strip()
    return default

width = int(prop('window', 'width', '0px').rstrip('px'))
cols = int(prop('listview', 'columns', '1'))
gap = int(prop('listview', 'spacing', '0px').rstrip('px'))
font = prop('element', 'font', '').strip('"')
pad = prop('element', 'padding', '0px 0px').split()
pad_x = int(pad[-1].rstrip('px'))

# comet-glass.rasi: window padding 24px, element border 1px.
WIN_PAD, BORDER = 24, 1

surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, 300, 300)
layout = PangoCairo.create_layout(cairo.Context(surf))
layout.set_font_description(Pango.FontDescription(font))
widest = 0
for ch in "\U0001F600\U0001F92F\U0001F469\U0001F1FA":
    layout.set_text(ch, -1)
    widest = max(widest, layout.get_pixel_extents()[0].width)

column = (width - 2 * WIN_PAD - gap * (cols - 1)) / cols
content = column - 2 * pad_x - 2 * BORDER

# Rofi estimates row height from the GLOBAL font, not from element/element-text,
# so that is the one that has to be tall enough for a glyph.
global_font = ""
m = re.search(r'\*\s*\{(.*?)\}', theme, re.S)
if m:
    v = re.search(r'\bfont:\s*"([^"]+)"', m.group(1))
    if v:
        global_font = v.group(1)
layout.set_font_description(Pango.FontDescription(global_font or font))
layout.set_text("\U0001F600", -1)
row_text_h = layout.get_pixel_extents()[1].height

layout.set_font_description(Pango.FontDescription(font))
tallest = 0
for ch in "\U0001F600\U0001F92F\U0001F469":
    layout.set_text(ch, -1)
    tallest = max(tallest, layout.get_pixel_extents()[0].height)

print(f"font={font!r} global={global_font!r}")
print(f"  width : glyph={widest}px column={column:.1f}px content={content:.1f}px")
print(f"  height: glyph={tallest}px row_text={row_text_h}px")

failed = False
if content < widest:
    print(f"  cells are {widest - content:.1f}px too narrow")
    failed = True
if row_text_h < tallest:
    print(f"  rows are {tallest - row_text_h}px too short; glyphs will be clipped")
    failed = True
if failed:
    sys.exit(1)
PYFIT
fi

# rofi must be able to parse the theme.
if command -v rofi >/dev/null; then
  rofi -theme "$theme" -dump-theme >/dev/null 2>"$test_root/theme.err" ||
    fail "rofi cannot parse the emoji theme: $(head -n 2 "$test_root/theme.err")"
fi

printf 'emoji picker: ok\n'

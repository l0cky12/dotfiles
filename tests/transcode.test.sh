#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
transcode="$repo_root/hypr/.local/bin/transcode"
menu="$repo_root/hypr/.config/hypr/scripts/transcode-menu.sh"
test_root=$(mktemp -d -t transcode-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v magick >/dev/null 2>&1 || {
  printf 'skip: magick (imagemagick) is not installed\n'
  exit 0
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "expected [$1], got [$2]"
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]"
}

mkdir -p "$test_root/media" "$test_root/bin" "$test_root/runtime"

magick -size 400x200 xc:navy "$test_root/media/small image.png"
small_output=$("$transcode" "$test_root/media/small image.png" png low)
assert_eq 400x200 "$(magick identify -format '%wx%h' "$small_output")"

magick -size 1200x800 canvas:none -fill red \
  -draw 'rectangle 100,100 1100,700' "$test_root/media/alpha.png"
jpg_output=$("$transcode" "$test_root/media/alpha.png" jpg low)
assert_eq alpha-1080p.jpg "$(basename -- "$jpg_output")"
assert_eq 1080x720 "$(magick identify -format '%wx%h' "$jpg_output")"
[[ "$(magick identify -format '%[channels]' "$jpg_output")" != *a* ]] ||
  fail 'JPEG retained an alpha channel'

second_jpg=$("$transcode" "$test_root/media/alpha.png" jpg low)
assert_eq alpha-1080p-2.jpg "$(basename -- "$second_jpg")"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc2=size=320x180:rate=20:duration=1' \
  -f lavfi -i 'sine=frequency=440:duration=1' \
  -c:v libx264 -pix_fmt yuv420p -c:a aac "$test_root/media/demo source.mov"

mp4_output=$("$transcode" "$test_root/media/demo source.mov" mp4 720p)
assert_eq demo\ source-720p.mp4 "$(basename -- "$mp4_output")"
assert_eq 320x180 "$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height -of csv=s=x:p=0 "$mp4_output")"
assert_eq h264 "$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name -of default=nw=1:nk=1 "$mp4_output")"
assert_eq yuv420p "$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=pix_fmt -of default=nw=1:nk=1 "$mp4_output")"
assert_eq aac "$(ffprobe -v error -select_streams a:0 \
  -show_entries stream=codec_name -of default=nw=1:nk=1 "$mp4_output")"
python3 - "$mp4_output" <<'PY'
from pathlib import Path
import sys
data = Path(sys.argv[1]).read_bytes()
assert 0 <= data.find(b"moov") < data.find(b"mdat"), "MP4 is not fast-started"
PY

gif_output=$("$transcode" "$test_root/media/demo source.mov" gif 720p)
assert_eq gif "$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name -of default=nw=1:nk=1 "$gif_output")"
assert_eq 320x180 "$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height -of csv=s=x:p=0 "$gif_output")"

set +e
"$transcode" "$test_root/media/alpha.png" mp4 low >/dev/null 2>&1
status=$?
set -e
assert_eq 2 "$status"

cat > "$test_root/bin/wl-copy" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$TEST_CLIPBOARD_ARGS"
cat > "$TEST_CLIPBOARD_DATA"
[[ "${TEST_CLIPBOARD_FAIL:-0}" != 1 ]]
SH
cat > "$test_root/bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NOTIFY_CALLS"
SH
chmod +x "$test_root/bin/wl-copy" "$test_root/bin/notify-send"
export TEST_CLIPBOARD_ARGS="$test_root/clipboard-args"
export TEST_CLIPBOARD_DATA="$test_root/clipboard-data"
export NOTIFY_CALLS="$test_root/notify-calls"

magick -size 32x16 xc:red "$test_root/media/clip space 雪.png"
PATH="$test_root/bin:$PATH" "$transcode" --copy \
  "$test_root/media/clip space 雪.png" png high >/dev/null
assert_contains "$test_root/clipboard-args" '--type text/uri-list'
assert_contains "$test_root/clipboard-data" 'clip%20space%20%E9%9B%AA-3160p.png'

newline_input="$test_root/media/line
break.png"
magick -size 16x16 xc:blue "$newline_input"
PATH="$test_root/bin:$PATH" "$transcode" --copy "$newline_input" png low >/dev/null
assert_contains "$test_root/clipboard-data" 'line%0Abreak-1080p.png'

rm -f "$NOTIFY_CALLS"
PATH="$test_root/bin:$PATH" "$transcode" --notify \
  "$test_root/media/alpha.png" png high >/dev/null
assert_contains "$NOTIFY_CALLS" 'Transcode complete'
set +e
PATH="$test_root/bin:$PATH" "$transcode" --notify \
  "$test_root/media/alpha.png" mp4 low >/dev/null 2>&1
status=$?
set -e
assert_eq 2 "$status"
assert_contains "$NOTIFY_CALLS" 'Transcode failed'

set +e
TEST_CLIPBOARD_FAIL=1 PATH="$test_root/bin:$PATH" "$transcode" --copy \
  "$test_root/media/clip space 雪.png" png medium > "$test_root/copy-failed-path" 2>/dev/null
status=$?
set -e
assert_eq 5 "$status"
[[ -s "$(<"$test_root/copy-failed-path")" ]] || fail 'clipboard failure lost converted output'

cat > "$test_root/bin/rofi" <<'SH'
#!/usr/bin/env bash
count=0
[[ -f "$ROFI_STATE" ]] && count=$(<"$ROFI_STATE")
count=$((count + 1))
printf '%s' "$count" > "$ROFI_STATE"
cat >/dev/null
if [[ "$count" == "$ROFI_CANCEL_AT" ]]; then
  exit 1
fi
case "$count" in
  1) printf '000001\tPictures/pick.png\n' ;;
  2) printf 'jpg — transparency becomes white\n' ;;
  3) printf 'High — maximum width 3160 px\n' ;;
esac
SH
cat > "$test_root/bin/fake-transcode" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TRANSCODE_CALLS"
SH
chmod +x "$test_root/bin/rofi" "$test_root/bin/fake-transcode" "$test_root/bin/notify-send"
mkdir -p "$test_root/Pictures" "$test_root/Videos"
printf image > "$test_root/Pictures/pick.png"
export ROFI_STATE="$test_root/rofi-state"
export TRANSCODE_CALLS="$test_root/transcode-calls"
export NOTIFY_CALLS="$test_root/notify-calls"

for cancel_at in 1 2 3; do
  rm -f "$ROFI_STATE" "$TRANSCODE_CALLS" "$NOTIFY_CALLS"
  ROFI_CANCEL_AT="$cancel_at" PATH="$test_root/bin:$PATH" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    TRANSCODE_PICTURES_DIR="$test_root/Pictures" \
    TRANSCODE_VIDEOS_DIR="$test_root/Videos" \
    TRANSCODE_BIN="$test_root/bin/fake-transcode" \
    "$menu"
  [[ ! -e "$TRANSCODE_CALLS" ]] || fail "cancel stage $cancel_at invoked transcode"
  [[ ! -e "$NOTIFY_CALLS" ]] || fail "cancel stage $cancel_at sent a notification"
done

printf 'ok: transcode fixtures\n'

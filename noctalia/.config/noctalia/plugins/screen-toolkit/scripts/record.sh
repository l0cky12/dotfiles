#!/usr/bin/env bash
# record.sh <action> [args...]
#
# Actions:
#   thumb        <src> <thumbnail>        — extract mid-frame thumbnail
#   convert-mp4  <input> <output>         — finalize MP4: stream-copy (fast path)
#   convert-mp4  <input> <output> --recode — finalize MP4: re-encode audio to AAC 128k + faststart
#   convert-gif  <input> <output>         — convert MP4 → palette-optimized GIF at 15 fps
#   stop         <recorder-bin>           — send SIGINT to the named recorder process
#
# Exit codes:
#   1 — missing / invalid arguments
#   2 — input file not found
#   3 — missing dependency (ffmpeg, ffprobe, pkill)
#   4 — conversion or process command failed
#
# Used by: Record.qml
set -euo pipefail
umask 077
ACTION="${1:-}"
THUMB_OUT=""
PALETTE=""
cleanup() { [[ -z $PALETTE ]] || rm -f -- "$PALETTE"; }
trap cleanup EXIT
_require() {
    command -v "$1" >/dev/null 2>&1 \
        || { echo "ERROR: missing dependency: $1" >&2; exit 3; }
}
_thumb() {
    local src="$1"
    THUMB_OUT="$2"
    _require ffprobe
    _require ffmpeg
    local dur
    dur=$(ffprobe -v error \
        -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 \
        "$src" 2>/dev/null) || dur=""
    [[ -z "$dur" || "$dur" == "N/A" ]] && dur=1
    local mid
    mid=$(echo "$dur / 2" | bc -l 2>/dev/null) || mid="0.5"
    ffmpeg -y -ss "$mid" -i "$src" -frames:v 1 "$THUMB_OUT" 2>/dev/null
}
case "$ACTION" in
  start)
    BIN="${2:-}"
    REGION="${3:-}"
    TEMP_DIR="${4:-}"
    AUDIO_OUT="${5:-0}"
    AUDIO_IN="${6:-0}"
    CURSOR="${7:-0}"
    [[ "$BIN" == "wl-screenrec" || "$BIN" == "wf-recorder" ]] || exit 1
    [ -n "$REGION" ] && [ -d "$TEMP_DIR" ] || exit 1
    OUTPUT=$(mktemp -- "$TEMP_DIR/recording.XXXXXX.mp4")
    printf '%s\n' "$OUTPUT"
    recorder_cmd=("$BIN" -g "$REGION")
    if [[ "$BIN" == "wf-recorder" ]]; then
        if [[ "$AUDIO_OUT" == 1 ]]; then
            _require pactl
            recorder_cmd+=("-a=$(pactl get-default-sink).monitor")
        elif [[ "$AUDIO_IN" == 1 ]]; then
            _require pactl
            recorder_cmd+=("-a=$(pactl get-default-source)")
        fi
    else
        [[ "$CURSOR" == 1 ]] || recorder_cmd+=(--no-cursor)
        if [[ "$AUDIO_OUT" == 1 ]]; then
            _require pactl
            recorder_cmd+=(--audio --audio-device "$(pactl get-default-sink).monitor")
        elif [[ "$AUDIO_IN" == 1 ]]; then
            _require pactl
            recorder_cmd+=(--audio --audio-device "$(pactl get-default-source)")
        fi
    fi
    recorder_cmd+=(-f "$OUTPUT")
    "${recorder_cmd[@]}" >/dev/null 2>&1
    [ -s "$OUTPUT" ]
    ;;
  thumb)
    SRC="${2:-}"
    THUMB_OUT="${3:-}"
    [ -n "$SRC" ] || { echo "ERROR: thumb: missing <src>"           >&2; exit 1; }
    [ -f "$SRC" ] || { echo "ERROR: thumb: file not found: $SRC"   >&2; exit 2; }
    [ -n "$THUMB_OUT" ] || { echo "ERROR: thumb: missing <thumbnail>" >&2; exit 1; }
    _thumb "$SRC" "$THUMB_OUT"
    ;;
  convert-mp4)
    INPUT="${2:-}"
    OUTPUT="${3:-}"
    RECODE="${4:-}"
    THUMB_OUT="${5:-}"
    [ -n "$INPUT"  ] || { echo "ERROR: convert-mp4: missing <input>"          >&2; exit 1; }
    [ -n "$OUTPUT" ] || { echo "ERROR: convert-mp4: missing <output>"         >&2; exit 1; }
    [ -f "$INPUT"  ] || { echo "ERROR: convert-mp4: file not found: $INPUT"   >&2; exit 2; }
    _require ffmpeg
    if [ "$RECODE" = "--recode" ]; then
        ffmpeg -y -i "$INPUT" \
            -c:v copy -c:a aac -b:a 128k -movflags +faststart \
            "$OUTPUT" 2>/dev/null \
        || { echo "ERROR: convert-mp4: ffmpeg recode failed" >&2; exit 4; }
        rm -f "$INPUT"
    else
        mv "$INPUT" "$OUTPUT" \
        || { echo "ERROR: convert-mp4: mv failed" >&2; exit 4; }
    fi
    [ -n "$THUMB_OUT" ] || { echo "ERROR: convert-mp4: missing <thumbnail>" >&2; exit 1; }
    _thumb "$OUTPUT" "$THUMB_OUT"
    ;;
  convert-gif)
    INPUT="${2:-}"
    OUTPUT="${3:-}"
    THUMB_OUT="${4:-}"
    TEMP_DIR="${5:-}"
    [ -n "$INPUT"  ] || { echo "ERROR: convert-gif: missing <input>"          >&2; exit 1; }
    [ -n "$OUTPUT" ] || { echo "ERROR: convert-gif: missing <output>"         >&2; exit 1; }
    [ -f "$INPUT"  ] || { echo "ERROR: convert-gif: file not found: $INPUT"   >&2; exit 2; }
    [ -n "$THUMB_OUT" ] || { echo "ERROR: convert-gif: missing <thumbnail>" >&2; exit 1; }
    [ -d "$TEMP_DIR" ] || { echo "ERROR: convert-gif: invalid <temp-dir>" >&2; exit 1; }
    _require ffmpeg
    PALETTE=$(mktemp -- "$TEMP_DIR/record-palette.XXXXXX.png")
    ffmpeg -y -i "$INPUT" \
        -vf 'fps=15,scale=trunc(iw/2)*2:trunc(ih/2)*2:flags=lanczos,palettegen' \
        "$PALETTE" 2>/dev/null \
    || { echo "ERROR: convert-gif: palettegen pass failed" >&2; exit 4; }
    ffmpeg -y -i "$INPUT" -i "$PALETTE" \
        -lavfi 'fps=15,scale=trunc(iw/2)*2:trunc(ih/2)*2:flags=lanczos[x];[x][1:v]paletteuse' \
        "$OUTPUT" 2>/dev/null \
    || { echo "ERROR: convert-gif: paletteuse pass failed" >&2; exit 4; }
    rm -f -- "$INPUT"
    _thumb "$OUTPUT" "$THUMB_OUT"
    ;;
  stop)
    BIN="${2:-}"
    [ -n "$BIN" ] || { echo "ERROR: stop: missing <recorder-bin>" >&2; exit 1; }
    _require pkill
    pkill -INT "$BIN" 2>/dev/null || true
    ;;
  copy-uri)
    FILE="${2:-}"
    [ -n "$FILE" ] || exit 1
    printf 'file://%s\r\n' "$FILE" | wl-copy --type text/uri-list
    ;;
  save)
    SRC="${2:-}"
    DEST_DIR="${3:-}"
    DEST="${4:-}"
    [ -f "$SRC" ] && [ -n "$DEST_DIR" ] && [ -n "$DEST" ] || exit 1
    mkdir -p -- "$DEST_DIR"
    cp -- "$SRC" "$DEST"
    ;;
  *)
    echo "ERROR: unknown action '${ACTION}'. Expected: start | thumb | convert-mp4 | convert-gif | stop | copy-uri | save" >&2
    exit 1
    ;;
esac

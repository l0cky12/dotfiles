#!/usr/bin/env bash
# annotate.sh
# Usage:
#   annotate.sh save-overlay-auto <base> <overlay> <filename> <ss_dir> <pic_dir>
#   annotate.sh save-overlay      <base> <overlay> <dest>
#   annotate.sh save-auto         <base> <filename> <ss_dir> <pic_dir>
#   annotate.sh save              <base> <dest>
#   annotate.sh copy              <base> <overlay>
#   annotate.sh copy-zoom         <file>
#   annotate.sh share-flatten     <base> <overlay>

set -euo pipefail
umask 077

MODE="${1:-}"
TEMP_FILE=""
cleanup() { [[ -z $TEMP_FILE ]] || rm -f -- "$TEMP_FILE"; }
trap cleanup EXIT

case "$MODE" in
save-overlay-auto)
    BASE="$2"; OVERLAY="$3"; FILENAME="$4"; SS_DIR="$5"; PIC_DIR="$6"
    if   [ -d "$SS_DIR"  ]; then DEST="$SS_DIR"
    elif [ -d "$PIC_DIR" ]; then DEST="$PIC_DIR"
    else exit 1; fi
    magick "$BASE" "$OVERLAY" -composite "$DEST/$FILENAME" 2>/dev/null && \
    rm -f "$OVERLAY" && echo "$DEST/$FILENAME"
    ;;
save-overlay)
    BASE="$2"; OVERLAY="$3"; DEST="$4"
    magick "$BASE" "$OVERLAY" -composite "$DEST" 2>/dev/null && \
    rm -f "$OVERLAY" && echo "$DEST"
    ;;
save-auto)
    BASE="$2"; FILENAME="$3"; SS_DIR="$4"; PIC_DIR="$5"
    if   [ -d "$SS_DIR"  ]; then DEST="$SS_DIR"
    elif [ -d "$PIC_DIR" ]; then DEST="$PIC_DIR"
    else exit 1; fi
    cp "$BASE" "$DEST/$FILENAME" 2>/dev/null && echo "$DEST/$FILENAME"
    ;;
save)
    BASE="$2"; DEST="$3"
    mkdir -p "$(dirname "$DEST")" || exit 1
    cp "$BASE" "$DEST" 2>/dev/null && echo "$DEST"
    ;;
copy)
    BASE="$2"; OVERLAY="$3"
    TEMP_DIR="$4"
    TEMP_FILE=$(mktemp -- "$TEMP_DIR/annotated.XXXXXX.png")
    magick "$BASE" "$OVERLAY" -composite "$TEMP_FILE" 2>/dev/null && \
    wl-copy < "$TEMP_FILE" && rm -f -- "$OVERLAY"
    ;;
copy-zoom)
    wl-copy < "$2"
    ;;
share-flatten)
    BASE="$2"; OVERLAY="$3"; OUT="$4"
    magick "$BASE" "$OVERLAY" -composite "$OUT" 2>/dev/null && \
    rm -f -- "$OVERLAY"
    ;;
*)
    echo "Usage: annotate.sh <mode> ..." >&2
    exit 1
    ;;
esac

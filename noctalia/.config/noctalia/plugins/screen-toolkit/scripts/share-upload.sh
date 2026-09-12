#!/usr/bin/env bash
# share-upload.sh <file> [expiry] <temp_dir>
# api_key: read from stdin; if empty, falls back to uguu.se (anonymous, 3h, 128MB max)
# expiry:  1h | 1d | 7d | 30d | permanent (X02 only, default: 7d)
# Prints URL to stdout on success, exits non-zero on failure
# Exit codes:
#   1 — invalid arguments (no file given)
#   2 — file not found
#   3 — missing dependency
#   4 — upload request failed
#   5 — invalid or empty response
#   6 — file too large
# Used by: annotate (for now)

set -euo pipefail
umask 077

FILE="${1:-}"
EXPIRY="${2:-7d}"
TEMP_DIR="${3:-}"

UGUU_MAX_BYTES=$((128 * 1024 * 1024))  # 128 MB

[ -n "$FILE" ] || { echo "ERROR: no file given"         >&2; exit 1; }
[ -f "$FILE" ] || { echo "ERROR: file not found: $FILE" >&2; exit 2; }

command -v curl >/dev/null 2>&1 || { echo "ERROR: missing dependency: curl" >&2; exit 3; }

IFS= read -r API_KEY || true

# ── X02 (authenticated) ───────────────────────────────────────────────────────
if [ -n "$API_KEY" ]; then
    [ -d "$TEMP_DIR" ] || { echo "ERROR: invalid temporary directory" >&2; exit 1; }
    EXPIRY_FLAG=()
    if [ "$EXPIRY" != "permanent" ] && [ -n "$EXPIRY" ]; then
        EXPIRY_FLAG=(-F "expiry=${EXPIRY}")
    fi

    CURL_CONFIG=$(mktemp -- "$TEMP_DIR/x02-curl.XXXXXX.conf")
    cleanup() { rm -f -- "$CURL_CONFIG"; }
    trap cleanup EXIT
    API_KEY=${API_KEY//$'\r'/}
    API_KEY=${API_KEY//$'\n'/}
    API_KEY=${API_KEY//\\/\\\\}
    API_KEY=${API_KEY//\"/\\\"}
    printf 'header = "x-api-key: %s"\n' "$API_KEY" > "$CURL_CONFIG"
    chmod 0600 -- "$CURL_CONFIG"
    URL=$(curl -sS -f \
        -X POST "https://up.x02.me/api/upload" \
        -F "file=@${FILE}" \
        "${EXPIRY_FLAG[@]}" \
        --connect-timeout 20 \
        --max-time 120 \
        --config "$CURL_CONFIG" \
        2>/dev/null) \
        || { echo "ERROR: X02 upload request failed" >&2; exit 4; }
    cleanup

    if [ -n "$URL" ] && [[ "$URL" == http* ]]; then
        printf '%s\n' "$URL"
        exit 0
    fi

    echo "ERROR: X02: unexpected response: $URL" >&2
    exit 5
fi

# ── uguu.se (anonymous fallback) ──────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || { echo "ERROR: missing dependency: jq" >&2; exit 3; }

FILE_SIZE=$(stat -c%s "$FILE" 2>/dev/null || stat -f%z "$FILE" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -gt "$UGUU_MAX_BYTES" ]; then
    echo "ERROR: file too large for anonymous upload (128MB max). Add an X02 API key for larger files." >&2
    exit 6
fi

RESP=$(curl -sS -f -A 'Mozilla/5.0' \
    --connect-timeout 20 --max-time 60 \
    -F "files[]=@${FILE}" \
    'https://uguu.se/upload' 2>/dev/null) \
|| RESP=$(curl -sS -A 'Mozilla/5.0' \
    --connect-timeout 20 --max-time 60 \
    -F "files[]=@${FILE}" \
    'https://uguu.se/upload.php' 2>/dev/null) \
|| { echo "ERROR: uguu.se upload request failed" >&2; exit 4; }

URL=$(printf '%s' "$RESP" | jq -r '.files[0].url // empty' 2>/dev/null)

if [ -n "$URL" ] && [[ "$URL" == http* ]]; then
    printf '%s\n' "$URL"
    exit 0
fi

echo "ERROR: uguu.se: no valid URL in response" >&2
exit 5

#!/usr/bin/env bash
# =============================================================================
# capture/capture.sh — single entry point for the capture system
#
#   capture.sh screenshot [smart|region|window|monitor] [--copy|--save|--delay=N]
#   capture.sh record     [toggle|start|stop|status|menu] [...]
#   capture.sh ocr        [region|smart|window|monitor] [--lang=…] [--psm=…]
#   capture.sh qr         select and decode a QR code to the sensitive clipboard
#   capture.sh color      [--format=hex|rgb]
#   capture.sh menu
#   capture.sh doctor     report which backends are present
#
# Every Hyprland binding goes through here, so the keybindings stay readable and
# the individual backends can be reorganised without touching the config.
# =============================================================================
set -euo pipefail

_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

SUB="${1:-menu}"
shift || true

case "$SUB" in
  screenshot|shot) exec "$_dir/screenshot.sh" "$@" ;;
  record|rec)      exec "$_dir/record.sh" "$@" ;;
  ocr|text)        exec "$_dir/ocr.sh" "$@" ;;
  qr|qrcode)       exec "$_dir/qr.sh" "$@" ;;
  color|colour)    exec "$_dir/color.sh" "$@" ;;
  menu)            exec "$_dir/menu.sh" "$@" ;;
  select)          exec "$_dir/select.sh" "$@" ;;
  doctor)
    # shellcheck source=common.sh
    source "$_dir/common.sh"
    printf 'Capture dependencies\n\n'
    printf '%-24s %-10s %s\n' TOOL STATUS "USED FOR"
    check() {
      local cmd="$1" role="$2" state="MISSING"
      command -v "$cmd" >/dev/null 2>&1 && state="present"
      printf '%-24s %-10s %s\n' "$cmd" "$state" "$role"
    }
    check grim                "screenshots (required)"
    check slurp               "region selection (required)"
    check wl-copy             "clipboard (required)"
    check jq                  "geometry parsing (required)"
    check hyprctl             "window/monitor geometry (required)"
    check hyprpicker          "screen freeze + colour picker"
    check gpu-screen-recorder "screen recording"
    check ffmpeg              "recording post-process + thumbnails"
    check tesseract           "OCR"
    check zbarimg             "QR code decoding"
    check magick              "OCR preprocessing, colour fallback"
    check mpv                 "webcam overlay, video playback"
    check rofi                "capture menu"
    check notify-send         "notifications"
    check v4l2-ctl            "webcam detection"
    printf '\nscreenshots -> %s\nrecordings  -> %s\nOCR langs   -> %s\n' \
      "$SCREENSHOT_DIR" "$SCREENRECORD_DIR" "$OCR_LANGS"
    ;;
  *) printf 'capture.sh: unknown subcommand: %s\n' "$SUB" >&2; exit 2 ;;
esac

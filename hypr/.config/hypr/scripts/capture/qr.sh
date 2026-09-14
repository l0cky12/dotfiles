#!/usr/bin/env bash
# =============================================================================
# capture/qr.sh — decode a selected QR code into the sensitive clipboard
#
# The selected pixels exist only in a private runtime directory and are removed
# before exit. zbar is explicitly restricted to QR symbols: dense screens can
# otherwise produce false-positive linear barcodes. The decoded payload is
# never printed or notified; wl-copy's sensitive hint keeps it out of
# clipboard-history tools that honour the Wayland protocol metadata.
# =============================================================================
set -euo pipefail

_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
# shellcheck source=select.sh
source "$_dir/select.sh"

require_cmd grim || exit 1
require_cmd zbarimg zbar || exit 1
require_cmd wl-copy wl-clipboard || exit 1
require_cmd slurp || exit 1

# QR payloads can contain credentials. Keep both the directory and image owner
# readable only, even if the inherited runtime directory is more permissive.
umask 077
WORK=$(mktemp -d "$CAPTURE_RUNTIME/qr.XXXXXX") || {
  notify_error "Cannot create private QR capture directory"
  exit 1
}
cleanup() {
  capture_freeze_stop
  rm -rf -- "$WORK"
}
trap cleanup EXIT INT TERM HUP

capture_freeze_start
TARGET=$(capture_select region) || exit 0

SHOT="$WORK/selection.png"
grim -g "${TARGET#region:}" "$SHOT" || {
  notify_error "QR capture failed"
  exit 1
}
capture_freeze_stop

# Disable every decoder before enabling QR. Do not loosen this: a barcode from
# unrelated dense screen content is worse than a deliberate no-result here.
if ! PAYLOAD=$(zbarimg -q --raw -1 '-S*.enable=0' '-Sqrcode.enable=1' "$SHOT" 2>/dev/null); then
  notify_error "No QR code found in selection"
  exit 1
fi

# zbar terminates decoded lines with a newline. QR payloads themselves may
# legitimately contain newlines, so remove only the terminator it adds.
PAYLOAD="${PAYLOAD%$'\n'}"
[ -n "$PAYLOAD" ] || {
  notify_error "No QR code found in selection"
  exit 1
}

printf '%s' "$PAYLOAD" | wl-copy --sensitive

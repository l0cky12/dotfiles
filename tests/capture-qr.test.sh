#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
capture="$repo_root/hypr/.config/hypr/scripts/capture/capture.sh"
test_root=$(mktemp -d -t capture-qr-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$test_root/bin" "$test_root/runtime"
cat >"$test_root/bin/slurp" <<'SH'
#!/usr/bin/env bash
printf '10,20 300x200\n'
SH
cat >"$test_root/bin/grim" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$QR_GRIM_ARGS"
printf '%s' "${!#}" >"$QR_CAPTURE_PATH"
printf png >"${!#}"
SH
cat >"$test_root/bin/zbarimg" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$QR_ZBAR_ARGS"
[[ ${QR_ZBAR_STATUS:-0} == 0 ]] || exit "$QR_ZBAR_STATUS"
printf '%s\n' "${QR_ZBAR_PAYLOAD:-https://example.invalid/qr-fixture}"
SH
cat >"$test_root/bin/wl-copy" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$QR_WL_COPY_ARGS"
cat >"$QR_CLIPBOARD"
SH
cat >"$test_root/bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$QR_NOTIFICATIONS"
SH
chmod +x "$test_root/bin"/*

export PATH="$test_root/bin:$PATH"
export XDG_RUNTIME_DIR="$test_root/runtime"
export QR_GRIM_ARGS="$test_root/grim-args"
export QR_CAPTURE_PATH="$test_root/capture-path"
export QR_ZBAR_ARGS="$test_root/zbar-args"
export QR_WL_COPY_ARGS="$test_root/wl-copy-args"
export QR_CLIPBOARD="$test_root/clipboard"
export QR_NOTIFICATIONS="$test_root/notifications"

output=$("$capture" qr 2>"$test_root/stderr") || fail 'QR capture did not decode its fixture'
[[ -z $output && ! -s $test_root/stderr ]] || fail 'QR payload or decoder output escaped to stdout/stderr'
grep -Fx -- '-S*.enable=0' "$QR_ZBAR_ARGS" >/dev/null ||
  fail 'QR decoder did not disable all barcode symbologies'
grep -Fx -- '-Sqrcode.enable=1' "$QR_ZBAR_ARGS" >/dev/null ||
  fail 'QR decoder did not enable QR decoding explicitly'
grep -Fx -- '--sensitive' "$QR_WL_COPY_ARGS" >/dev/null ||
  fail 'decoded QR value was not marked sensitive for the clipboard'
[[ $(<"$QR_CLIPBOARD") == 'https://example.invalid/qr-fixture' ]] ||
  fail 'decoded QR payload was not copied exactly'
[[ ! -s $QR_NOTIFICATIONS ]] || fail 'successful QR decoding showed a notification'
capture_path=$(<"$QR_CAPTURE_PATH")
[[ ! -e $capture_path ]] || fail 'temporary QR capture was not removed'

: >"$QR_NOTIFICATIONS"
rm -f -- "$QR_CLIPBOARD"
if QR_ZBAR_STATUS=1 "$capture" qr >"$test_root/failure-stdout" 2>"$test_root/failure-stderr"; then
  fail 'QR capture accepted a selection with no QR code'
fi
[[ ! -s $test_root/failure-stdout && ! -s $test_root/failure-stderr ]] ||
  fail 'failed QR decoding leaked decoder output'
[[ ! -e $QR_CLIPBOARD ]] || fail 'failed QR decoding changed the clipboard'
grep -Fq 'No QR code found in selection' "$QR_NOTIFICATIONS" ||
  fail 'failed QR decoding did not provide a generic error'
grep -Fq 'https://example.invalid/qr-fixture' "$QR_NOTIFICATIONS" &&
  fail 'a QR payload leaked into an error notification'

printf 'ok: QR capture is QR-only, sensitive, silent, and temporary\n'

#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
record="$repo_root/hypr/.config/hypr/scripts/capture/record.sh"
test_root=$(mktemp -d -t webcam-resize-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$test_root/bin" "$test_root/runtime/hypr-capture"
cat > "$test_root/bin/webcam-ipc-fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\t%s\n' "$1" "$2" >> "$WEBCAM_IPC_CALLS"
[[ "${WEBCAM_IPC_FAIL:-0}" != 1 ]]
SH
cat > "$test_root/bin/hyprctl-fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WEBCAM_HYPRCTL_CALLS"
SH
cat > "$test_root/bin/mpv" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WEBCAM_MPV_CALLS"
mkdir -p "$CAPTURE_PROC_ROOT/$$"
printf 'mpv\0--title=capture-webcam\0' > "$CAPTURE_PROC_ROOT/$$/cmdline"
exec sleep 30
SH
cat > "$test_root/bin/notify-send" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$test_root/bin/webcam-ipc-fixture" "$test_root/bin/hyprctl-fixture" \
  "$test_root/bin/mpv" "$test_root/bin/notify-send"

capture_runtime="$test_root/runtime/hypr-capture"
export CAPTURE_PROC_ROOT="$test_root/proc"
mkdir -p "$CAPTURE_PROC_ROOT/$$"
printf 'mpv\0--title=capture-webcam\0' > "$CAPTURE_PROC_ROOT/$$/cmdline"
printf '%s\n' "$$" > "$capture_runtime/record.pid"
printf '%s\n' "$$" > "$capture_runtime/webcam.pid"
printf '%s\n' medium > "$capture_runtime/webcam.size"

export XDG_RUNTIME_DIR="$test_root/runtime"
export WEBCAM_IPC_HELPER="$test_root/bin/webcam-ipc-fixture"
export WEBCAM_IPC_CALLS="$test_root/ipc-calls"
export WEBCAM_HYPRCTL="$test_root/bin/hyprctl-fixture"
export WEBCAM_HYPRCTL_CALLS="$test_root/hyprctl-calls"
export WEBCAM_MPV_CALLS="$test_root/mpv-calls"
export WEBCAM_DEVICE="$test_root/video0"
export WEBCAM_STARTUP_DELAY=0.01
export PATH="$test_root/bin:$PATH"

"$record" webcam-size smaller
[[ "$(<"$capture_runtime/webcam.size")" == small ]] ||
  fail 'smaller did not select the small preset'
grep -Fq -- $'webcam.sock\t320x180-20-60' "$WEBCAM_IPC_CALLS" ||
  fail 'smaller did not send the small geometry'

before=$(wc -l < "$WEBCAM_IPC_CALLS")
"$record" webcam-size smaller
after=$(wc -l < "$WEBCAM_IPC_CALLS")
[[ "$before" -eq "$after" ]] || fail 'small preset stepped below its minimum'

"$record" webcam-size larger
[[ "$(<"$capture_runtime/webcam.size")" == medium ]] ||
  fail 'first larger step did not select medium'
"$record" webcam-size larger
[[ "$(<"$capture_runtime/webcam.size")" == large ]] ||
  fail 'second larger step did not select large'
grep -Fq -- $'webcam.sock\t480x270-20-60' "$WEBCAM_IPC_CALLS" ||
  fail 'larger did not send the medium geometry'
grep -Fq -- $'webcam.sock\t640x360-20-60' "$WEBCAM_IPC_CALLS" ||
  fail 'larger did not send the large geometry'

"$record" webcam-size smaller
[[ "$(<"$capture_runtime/webcam.size")" == medium ]] ||
  fail 'smaller did not step from large back to medium'

WEBCAM_IPC_FAIL=1 "$record" webcam-size smaller
[[ "$(<"$capture_runtime/webcam.size")" == small ]] ||
  fail 'Hyprland fallback did not update the size preset'
grep -Fq -- "dispatch hl.dsp.window.resize({ x = 320, y = 180, window = \"pid:$$\" })" \
  "$WEBCAM_HYPRCTL_CALLS" || fail 'failed IPC did not use the PID-scoped Hyprland fallback'

rm -f "$capture_runtime/record.pid"
before=$(wc -l < "$WEBCAM_IPC_CALLS")
printf '%s\n' medium > "$capture_runtime/webcam.size"
"$record" webcam-size larger
after=$(wc -l < "$WEBCAM_IPC_CALLS")
[[ "$after" -eq $((before + 1)) ]] || fail 'standalone overlay did not reach the IPC helper'
[[ "$(<"$capture_runtime/webcam.size")" == large ]] ||
  fail 'standalone overlay did not resize'

rm -f "$capture_runtime/webcam.pid" "$capture_runtime/webcam.size" "$capture_runtime/webcam.sock"
"$record" webcam-size larger
webcam_pid=$(<"$capture_runtime/webcam.pid")
[[ -d "/proc/$webcam_pid" ]] || fail 'resize did not start a missing overlay process'
[[ "$(<"$capture_runtime/webcam.size")" == large ]] ||
  fail 'resize did not apply the requested preset after starting the overlay'
grep -Fq -- "av://v4l2:$test_root/video0" "$WEBCAM_MPV_CALLS" ||
  fail 'resize did not open the configured device'
grep -Fq -- '--title=capture-webcam' "$WEBCAM_MPV_CALLS" ||
  fail 'resize did not use the overlay window title'

"$record" webcam-toggle
[[ ! -e "$capture_runtime/webcam.pid" ]] || fail 'webcam toggle did not clear the pidfile'

printf 'ok: webcam resize fixtures\n'

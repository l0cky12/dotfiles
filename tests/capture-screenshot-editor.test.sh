#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d -t capture-screenshot-editor.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/runtime"

printf '%s\n' '#!/usr/bin/env bash' 'printf "0,0 100x100\n"' >"$test_root/bin/slurp"
# shellcheck disable=SC2016 # Expansion happens when each mock runs.
printf '%s\n' '#!/usr/bin/env bash' 'if [[ ${!#} == - ]]; then printf "%s" "${CAPTURE_BYTES:-png}"; else printf "%s" "${CAPTURE_BYTES:-png}" > "${!#}"; fi' >"$test_root/bin/grim"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null; exit "${COPY_EXIT:-0}"' >"$test_root/bin/wl-copy"
cat >"$test_root/bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"$NOTIFY_ARGS"
if [[ $* == *'Screenshot ready'* ]]; then
  [[ ${EXPECT_UNSAVED:-0} != 1 || -z $(find "$SCREENSHOT_DIR" -name '*.png' -print 2>/dev/null) ]] || exit 1
  printf '%s\n' "${SHOT_ACTION-edit}"
fi
SH
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$test_root/bin/hyprpicker"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$test_root/bin/hyprctl"
# shellcheck disable=SC2016 # Expansion happens when each mock runs.
printf '%s\n' '#!/usr/bin/env bash' '[[ "$1" == --fork ]] && shift; exec "$@"' >"$test_root/bin/setsid"
# shellcheck disable=SC2016
cat >"$test_root/bin/satty" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$SATTY_ARGS"
while [[ -n ${EDIT_GATE:-} && ! -f $EDIT_GATE ]]; do sleep 0.01; done
[[ ${EDITOR_EXIT:-0} == 0 ]] || exit "$EDITOR_EXIT"
[[ ${EDIT_SAVE:-0} != 1 ]] || cat "$4" >"${!#}"
SH
chmod +x "$test_root/bin/"*

export PATH="$test_root/bin:$PATH"
export XDG_RUNTIME_DIR="$test_root/runtime"
export SCREENSHOT_DIR="$test_root/saved screenshots"
export SATTY_ARGS="$test_root/satty.args"
export NOTIFY_ARGS="$test_root/notify.args"
capture="$repo_root/hypr/.config/hypr/scripts/capture/capture.sh"
EXPECT_UNSAVED=1 "$capture" screenshot smart >/dev/null

grep -Fxq 'edit=Edit' "$NOTIFY_ARGS"
grep -Fxq 'save=Save' "$NOTIFY_ARGS" || { printf 'FAIL: screenshot notification has no Save button\n' >&2; exit 1; }
if grep -Fxq 'open=Open' "$NOTIFY_ARGS"; then
  printf 'FAIL: default screenshot notification still offers Open\n' >&2
  exit 1
fi
[[ -z $(find "$SCREENSHOT_DIR" -name '*.png' -print 2>/dev/null) ]]

mapfile -t args <"$test_root/satty.args"
[[ "${args[0]:-} ${args[1]:-} ${args[2]:-}" == '--copy-command wl-copy --filename' ]] || {
  printf 'FAIL: Satty editor arguments do not enable clipboard copy and filename input\n' >&2
  exit 1
}
[[ "${args[3]:-}" == "$test_root/runtime/hypr-capture/"*.png ]] || {
  printf 'FAIL: Satty did not receive the captured PNG\n' >&2
  exit 1
}
[[ ${args[4]:-} == --output-filename && ${args[5]:-} == "$SCREENSHOT_DIR/"*.png ]]
[[ ! -e ${args[3]} ]]

SHOT_ACTION=save "$capture" screenshot smart >/dev/null
saved=("$SCREENSHOT_DIR/"*.png)
[[ ${#saved[@]} == 1 && $(cat "${saved[0]}") == png ]]
SHOT_ACTION=save "$capture" screenshot smart >/dev/null
saved=("$SCREENSHOT_DIR/"*.png)
[[ ${#saved[@]} == 2 ]]
SHOT_ACTION='' "$capture" screenshot smart >/dev/null
[[ -z $(find "$test_root/runtime/hypr-capture" -name '*.png' -print) ]]
[[ $(sed -n '4p' "$SATTY_ARGS") == "${args[3]}" ]]

"$capture" screenshot region --save >/dev/null
saved=("$SCREENSHOT_DIR/"*.png)
[[ ${#saved[@]} == 3 ]]

"$capture" screenshot region --copy >/dev/null
saved=("$SCREENSHOT_DIR/"*.png)
[[ ${#saved[@]} == 3 ]]

printf blocked >"$test_root/blocked"
SCREENSHOT_DIR="$test_root/blocked/shots" SHOT_ACTION=save "$capture" screenshot smart >/dev/null
retained=("$test_root/runtime/hypr-capture/"*.png)
[[ ${#retained[@]} == 1 && $(cat "${retained[0]}") == png ]]
grep -Fq "Could not save screenshot; kept at ${retained[0]}" "$NOTIFY_ARGS"

# Failure recovery must leave the actual capture available, not just a cached
# notification image. Each case uses a separate runtime directory.
for failure in copy editor missing directory; do
  failure_runtime="$test_root/$failure-runtime"
  mkdir -p "$failure_runtime"
  failure_env=("XDG_RUNTIME_DIR=$failure_runtime")
  case $failure in
    copy) failure_env+=(COPY_EXIT=1 SHOT_ACTION=) ;;
    editor) failure_env+=(EDITOR_EXIT=1) ;;
    missing) failure_env+=(SCREENSHOT_EDITOR=missing-fixture-editor) ;;
    directory) failure_env+=("SCREENSHOT_DIR=$test_root/blocked/shots") ;;
  esac
  : >"$NOTIFY_ARGS"
  file=$(env "${failure_env[@]}" "$capture" screenshot region)
  [[ -s $file ]] || { printf 'FAIL: %s failure deleted the capture\n' "$failure" >&2; exit 1; }
  grep -Fq "kept at $file" "$NOTIFY_ARGS" || {
    printf 'FAIL: %s failure did not report the recovery path\n' "$failure" >&2; exit 1;
  }
done

"$capture" screenshot region --editor="$test_root/bin/satty --copy-command wl-copy --filename" >/dev/null
mapfile -t absolute_args <"$SATTY_ARGS"
[[ ${absolute_args[4]:-} == --output-filename ]] || {
  printf 'FAIL: absolute Satty path disables file saving\n' >&2; exit 1;
}
[[ ! -e ${absolute_args[5]} ]] || { printf 'FAIL: unused editor reservation remains\n' >&2; exit 1; }

# Hold two real capture-script invocations in their editor stubs. Both choose
# their filename before either writes it, with the same timestamp.
printf '#!/bin/sh\nprintf "2026-10-02_12-00-00\\n"\n' >"$test_root/bin/date"
chmod +x "$test_root/bin/date"
python3 - "$capture" "$test_root" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import time

capture, root = sys.argv[1], Path(sys.argv[2])
gate = root / 'edit-release'
args = [root / 'first.args', root / 'second.args']
edit_dir = root / 'overlapping editors'
jobs = []
try:
    for i, argv_file in enumerate(args):
        env = os.environ | {'SATTY_ARGS': str(argv_file), 'EDIT_GATE': str(gate),
                            'EDIT_SAVE': '1', 'CAPTURE_BYTES': str(i),
                            'SCREENSHOT_DIR': str(edit_dir)}
        jobs.append(subprocess.Popen([capture, 'screenshot', 'region'], env=env,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
    deadline = time.monotonic() + 5
    while not all(p.exists() and len(p.read_text().splitlines()) >= 6 for p in args):
        assert time.monotonic() < deadline, 'editors did not start'
        time.sleep(0.01)
    outputs = [Path(p.read_text().splitlines()[5]) for p in args]
    assert outputs[0] != outputs[1], 'overlapping editors share one output filename'
    assert all(p.exists() for p in outputs), 'editor output filenames were not reserved'
finally:
    gate.touch()
    for job in jobs:
        _, errors = job.communicate(timeout=5)
        assert job.returncode == 0, errors
assert [p.read_text() for p in outputs] == ['0', '1'], 'one editor overwrote the other image'
PY

# Recording shares the filename allocator. A failed start must remove its
# unused reservation without deleting partial output from a recorder.
cat >"$test_root/bin/gpu-screen-recorder" <<'SH'
#!/usr/bin/env bash
if [[ ${1:-} == --help ]]; then printf '%s\n' '-region'; exit 0; fi
[[ -z ${RECORDER_BYTES:-} ]] || printf '%s' "$RECORDER_BYTES" >"${!#}"
exit 1
SH
chmod +x "$test_root/bin/gpu-screen-recorder"
if SCREENRECORD_DIR="$test_root/recordings" "$capture" record start --audio=none --target=region >/dev/null; then
  printf 'FAIL: failed recorder was reported as started\n' >&2; exit 1
fi
[[ -z $(find "$test_root/recordings" -name '*.mp4' -print) ]] || {
  printf 'FAIL: failed recorder left an unused reservation\n' >&2; exit 1;
}
if SCREENRECORD_DIR="$test_root/recordings" RECORDER_BYTES=partial "$capture" record start --audio=none --target=region >/dev/null; then
  printf 'FAIL: failed partial recorder was reported as started\n' >&2; exit 1
fi
partial=("$test_root/recordings/"*.mp4)
[[ ${#partial[@]} == 1 && $(cat "${partial[0]}") == partial ]] || {
  printf 'FAIL: failed recorder deleted its partial output\n' >&2; exit 1;
}

python3 - "$repo_root" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory(prefix='notification-smoke.') as tmp:
    env = os.environ.copy()
    env.pop('WAYLAND_DISPLAY', None)
    env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
    # Use a private bus and temporary state, never the desktop.
    env.update(XDG_STATE_HOME=tmp+'/state', XDG_RUNTIME_DIR=tmp,
               QT_QPA_PLATFORM='offscreen')
    smoke = Path(sys.argv[1]) / 'quickshell/.config/quickshell/NotificationSmoke.qml'
    result = subprocess.run(['dbus-run-session', '--', 'timeout', '15', 'quickshell', '-p', str(smoke)],
                            env=env, capture_output=True, text=True, check=True)
    output = result.stdout + result.stderr
    assert 'ok: notification action rendering and invocation' in output and 'FAIL' not in output, output
PY

printf 'ok: screenshot Edit/Save buttons, deferred saving, cleanup, save failures, --copy/--save\n'

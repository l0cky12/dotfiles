#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d -t capture-screenshot-editor.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/runtime"

printf '%s\n' '#!/usr/bin/env bash' 'printf "0,0 100x100\n"' >"$test_root/bin/slurp"
# shellcheck disable=SC2016 # Expansion happens when each mock runs.
printf '%s\n' '#!/usr/bin/env bash' 'if [[ ${!#} == - ]]; then printf png; else printf png > "${!#}"; fi' >"$test_root/bin/grim"
printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' >"$test_root/bin/wl-copy"
cat >"$test_root/bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"$NOTIFY_ARGS"
if [[ $* == *'Screenshot ready'* ]]; then
  [[ ${EXPECT_UNSAVED:-0} != 1 || -z $(find "$SCREENSHOT_DIR" -name '*.png' -print 2>/dev/null) ]] || exit 1
  printf '%s\n' "${SHOT_ACTION-edit}"
fi
SH
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$test_root/bin/hyprpicker"
# shellcheck disable=SC2016 # Expansion happens when each mock runs.
printf '%s\n' '#!/usr/bin/env bash' '[[ "$1" == --fork ]] && shift; exec "$@"' >"$test_root/bin/setsid"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$@" > "$SATTY_ARGS"' >"$test_root/bin/satty"
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

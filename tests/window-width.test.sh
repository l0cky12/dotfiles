#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/hypr/.config/hypr/scripts/window-width.sh"
test_root=$(mktemp -d -t window-width-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s
' "$1" >&2
  exit 1
}

require_jq() {
  command -v jq >/dev/null 2>&1 || {
    printf 'skip: jq is not installed
'
    exit 0
  }
}

require_jq

mkdir -p "$test_root/bin" "$test_root/runtime"
cat > "$test_root/bin/hyprctl-fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HYPRCTL_CALLS"
if [[ "$*" == "-j activewindow" ]]; then
  if [[ "${ACTIVE_WINDOW:-yes}" == no ]]; then
    printf '{}\n'
  else
    jq -cn --argjson width "${ACTIVE_WIDTH:-1234}" \
      --argjson height "${ACTIVE_HEIGHT:-700}" \
      '{address:"0x123",size:[$width,$height]}'
  fi
fi
SH
chmod +x "$test_root/bin/hyprctl-fixture"

export HYPRCTL_CALLS="$test_root/calls"
export HYPR_WINDOW_WIDTH_HYPRCTL="$test_root/bin/hyprctl-fixture"
export HYPR_WINDOW_WIDTH_STATE_DIR="$test_root/runtime"

ACTIVE_WIDTH=1234 ACTIVE_HEIGHT=700 "$helper" save
[[ "$(<"$test_root/runtime/hypr-window-width")" == 1234 ]] ||
  fail 'save did not persist the active width'

ACTIVE_WIDTH=900 ACTIVE_HEIGHT=777 "$helper" restore
grep -Fq -- 'dispatch hl.dsp.window.resize({ x = 1234, y = 777 })' "$HYPRCTL_CALLS" ||
  fail 'restore did not preserve the current height'

printf 'not-a-width\n' > "$test_root/runtime/hypr-window-width"
set +e
"$helper" restore >/dev/null 2>&1
invalid_status=$?
set -e
[[ "$invalid_status" -ne 0 ]] || fail 'invalid saved width was accepted'

rm -f "$test_root/runtime/hypr-window-width"
set +e
"$helper" restore >/dev/null 2>&1
missing_status=$?
set -e
[[ "$missing_status" -ne 0 ]] || fail 'missing saved width was accepted'

set +e
ACTIVE_WINDOW=no "$helper" save >/dev/null 2>&1
window_status=$?
set -e
[[ "$window_status" -ne 0 ]] || fail 'missing active window was accepted'

printf 'ok: window-width fixtures\n'

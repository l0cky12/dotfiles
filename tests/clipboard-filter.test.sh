#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
store="$repo_root/hypr/.config/hypr/scripts/clipboard-store.sh"
lock="$repo_root/screensaver/.local/bin/screensaver-lock"
test_root=$(mktemp -d -t clipboard-filter-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || fail 'python3 is required for JSON fixtures'
real_jq=$(command -v jq || true)
jq_mode=stub

mkdir -p "$test_root/bin"
cat >"$test_root/bin/wl-paste" <<'SH'
#!/usr/bin/env bash
[[ ${CLIPBOARD_TYPES_STATUS:-0} == 0 ]] || exit "$CLIPBOARD_TYPES_STATUS"
printf '%s\n' "${CLIPBOARD_TYPES:-text/plain}"
SH
cat >"$test_root/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
[[ ${CLIPBOARD_WINDOW_STATUS:-0} == 0 ]] || exit "$CLIPBOARD_WINDOW_STATUS"
if [[ -v CLIPBOARD_WINDOW_JSON ]]; then
  printf '%s\n' "$CLIPBOARD_WINDOW_JSON"
else
  printf '%s\n' '{"class":"kitty","initialClass":"kitty","title":"shell","initialTitle":"shell"}'
fi
SH
if [[ -n $real_jq ]]; then
  jq_mode=real
  cat >"$test_root/bin/jq" <<'SH'
#!/usr/bin/env bash
if "$REAL_JQ" "$@"; then
  exit 0
else
  status=$?
  printf 'jq failed with status %d\n' "$status" >>"$JQ_FAILURE_LOG"
  exit "$status"
fi
SH
else
  printf 'WARNING: jq is not installed; using a fixture stub (jq error semantics are not covered)\n' >&2
  cat >"$test_root/bin/jq" <<'SH'
#!/usr/bin/env bash
python3 -c '
import json
import sys

data = json.load(sys.stdin)
values = [data.get(key, "") for key in ("class", "initialClass", "title", "initialTitle")]
if "type == \"object\"" in sys.argv[1]:
    valid = isinstance(data, dict) and all(value is None or value == "" for value in values)
    raise SystemExit(0 if valid else 1)
if not any(isinstance(value, str) and value for value in values):
    raise SystemExit(1)
print("\n".join(value if isinstance(value, str) else "" for value in values))
' "$*"
SH
fi
cat >"$test_root/bin/cliphist" <<'SH'
#!/usr/bin/env bash
[[ $1 == store ]] || exit 2
cat >>"$CLIPBOARD_STORE_LOG"
SH
chmod +x "$test_root/bin/wl-paste" "$test_root/bin/hyprctl" "$test_root/bin/jq" "$test_root/bin/cliphist"

export PATH="$test_root/bin:$PATH"
export CLIPBOARD_STORE_LOG="$test_root/stored"
export JQ_FAILURE_LOG="$test_root/jq-failures"
export REAL_JQ="$real_jq"

assert_filtered() {
  : >"$CLIPBOARD_STORE_LOG"
  printf 'top secret' | "$store"
  [[ ! -s $CLIPBOARD_STORE_LOG ]] || fail "$1 was retained"
}

: >"$CLIPBOARD_STORE_LOG"
printf 'ordinary text' | "$store"
[[ $(<"$CLIPBOARD_STORE_LOG") == 'ordinary text' ]] || fail 'ordinary clipboard content was not stored'

for mime in \
  x-kde-passwordManagerHint \
  application/x-kde-passwordManagerHint \
  application/x-bitwarden \
  application/x-keepassxc \
  application/x-1password; do
  CLIPBOARD_TYPES=$mime assert_filtered "password-manager MIME type $mime"
done

for identity in \
  'Bitwarden' \
  'org.keepassxc.KeePassXC' \
  'com.1password.1password' \
  'nngceckbapebfimnlniiiahkandclblb' \
  'oboonakemofpalcgghocfoadofidjkkk' \
  'aeblfdkhhhdcdjpifhhbdiojplfjncoa' \
  '446900e4-71c2-419f-a6a7-df9c091e268b' \
  'keepassxc-browser@keepassxc.org' \
  'd634138d-c276-4fc8-924b-40a0ea21d284'; do
  CLIPBOARD_WINDOW_JSON="{\"class\":\"browser\",\"title\":\"$identity\"}" \
    assert_filtered "sensitive app identifier $identity"
done

CLIPBOARD_TYPES_STATUS=1 assert_filtered 'failed MIME metadata query'
CLIPBOARD_WINDOW_STATUS=1 assert_filtered 'failed active-window metadata query'
CLIPBOARD_WINDOW_JSON='not-json' assert_filtered 'malformed active-window metadata'

: >"$CLIPBOARD_STORE_LOG"
: >"$JQ_FAILURE_LOG"
printf 'layer-shell copy' | CLIPBOARD_WINDOW_JSON='{}' "$store"
[[ $(<"$CLIPBOARD_STORE_LOG") == 'layer-shell copy' ]] ||
  fail 'clipboard content with no toplevel identity was not stored'
if [[ $jq_mode == real && ! -s $JQ_FAILURE_LOG ]]; then
  fail 'real jq did not exercise the missing-window-identity error path'
fi

grep -Eq '^max-items[[:space:]]+200$' "$repo_root/cliphist/.config/cliphist/config" ||
  fail 'cliphist history is not capped at 200 items'

python3 -c '
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    launcher = json.load(source)["appLauncher"]
store = "/home/liam/.config/hypr/scripts/clipboard-store.sh"
assert launcher["enableClipboardHistory"] is True
assert launcher["enableClipPreview"] is True
assert launcher["enableClipboardChips"] is True
assert launcher["clipboardWatchTextCommand"] == f"wl-paste --type text --watch {store}"
assert launcher["clipboardWatchImageCommand"] == f"wl-paste --type image --watch {store}"
' "$repo_root/noctalia/.config/noctalia/settings.json" ||
  fail 'Noctalia clipboard watchers do not use the filtered store path'

for autostart in \
  "$repo_root/hypr/.config/hypr/conf/autostart.lua" \
  "$repo_root/hypr/.config/hypr/conf/autostart.conf"; do
  [[ $(grep -c 'wl-paste .*--watch .*clipboard-store.sh' "$autostart") == 2 ]] ||
    fail "clipboard watchers bypass the filter in ${autostart#$repo_root/}"
  grep -Fq -- '--type text' "$autostart" || fail 'text clipboard watcher is missing'
  grep -Fq -- '--type image' "$autostart" || fail 'image clipboard watcher is missing'
done

for command_name in pkill timeout; do
  cat >"$test_root/bin/$command_name" <<'SH'
#!/usr/bin/env bash
exit 0
SH
done
cat >"$test_root/bin/pidof" <<'SH'
#!/usr/bin/env bash
exit 1
SH
cat >"$test_root/bin/hyprlock" <<'SH'
#!/usr/bin/env bash
printf 'hyprlock\n' >>"$CLIPBOARD_LOCK_LOG"
SH
mkdir -p "$test_root/home/.config/hypr/scripts"
cat >"$test_root/home/.config/hypr/scripts/clipboard-wipe.sh" <<'SH'
#!/usr/bin/env bash
printf 'wipe\n' >>"$CLIPBOARD_LOCK_LOG"
SH
chmod +x "$test_root/bin/pkill" "$test_root/bin/timeout" "$test_root/bin/pidof" \
  "$test_root/bin/hyprlock" "$test_root/home/.config/hypr/scripts/clipboard-wipe.sh"
export CLIPBOARD_LOCK_LOG="$test_root/lock-actions"
HOME="$test_root/home" "$lock"
[[ $(<"$CLIPBOARD_LOCK_LOG") == $'wipe\nhyprlock' ]] ||
  fail 'Hyprlock did not wipe clipboard history before locking'

if [[ $jq_mode == stub ]]; then
  printf 'degraded: jq-less subset passed; install jq to cover its error behavior\n'
fi
printf 'ok: clipboard filtering and retention fixtures\n'

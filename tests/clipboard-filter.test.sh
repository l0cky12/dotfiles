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

mkdir -p "$test_root/bin"
cat >"$test_root/bin/wl-paste" <<'SH'
#!/usr/bin/env bash
[[ ${CLIPBOARD_TYPES_STATUS:-0} == 0 ]] || exit "$CLIPBOARD_TYPES_STATUS"
printf '%s\n' "${CLIPBOARD_TYPES:-text/plain}"
SH
cat >"$test_root/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
[[ ${CLIPBOARD_WINDOW_STATUS:-0} == 0 ]] || exit "$CLIPBOARD_WINDOW_STATUS"
printf '%s\n' "${CLIPBOARD_WINDOW_JSON:-{\"class\":\"kitty\",\"initialClass\":\"kitty\",\"title\":\"shell\",\"initialTitle\":\"shell\"}}"
SH
cat >"$test_root/bin/jq" <<'SH'
#!/usr/bin/env bash
python3 -c '
import json
import sys

data = json.load(sys.stdin)
values = [data.get(key, "") for key in ("class", "initialClass", "title", "initialTitle")]
if not any(isinstance(value, str) and value for value in values):
    raise SystemExit(1)
print("\n".join(value if isinstance(value, str) else "" for value in values))
'
SH
cat >"$test_root/bin/cliphist" <<'SH'
#!/usr/bin/env bash
[[ $1 == store ]] || exit 2
cat >>"$CLIPBOARD_STORE_LOG"
SH
chmod +x "$test_root/bin/wl-paste" "$test_root/bin/hyprctl" "$test_root/bin/jq" "$test_root/bin/cliphist"

export PATH="$test_root/bin:$PATH"
export CLIPBOARD_STORE_LOG="$test_root/stored"

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
CLIPBOARD_WINDOW_JSON='{}' assert_filtered 'missing active-window identity'

grep -Eq '^max-items[[:space:]]+200$' "$repo_root/cliphist/.config/cliphist/config" ||
  fail 'cliphist history is not capped at 200 items'

python3 -c '
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    launcher = json.load(source)["appLauncher"]
assert launcher["enableClipboardHistory"] is False
assert launcher["clipboardWatchTextCommand"] == ""
assert launcher["clipboardWatchImageCommand"] == ""
' "$repo_root/noctalia/.config/noctalia/settings.json" ||
  fail 'Noctalia clipboard watchers are not disabled'

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
cat >"$test_root/bin/clipboard-wipe-fixture" <<'SH'
#!/usr/bin/env bash
printf 'wipe\n' >>"$CLIPBOARD_LOCK_LOG"
SH
chmod +x "$test_root/bin/pkill" "$test_root/bin/timeout" "$test_root/bin/pidof" \
  "$test_root/bin/hyprlock" "$test_root/bin/clipboard-wipe-fixture"
export CLIPBOARD_LOCK_LOG="$test_root/lock-actions"
CLIPBOARD_WIPE_EXECUTABLE="$test_root/bin/clipboard-wipe-fixture" "$lock"
[[ $(<"$CLIPBOARD_LOCK_LOG") == $'wipe\nhyprlock' ]] ||
  fail 'Hyprlock did not wipe clipboard history before locking'

printf 'ok: clipboard filtering and retention fixtures\n'

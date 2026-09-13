#!/usr/bin/env bash
# Fixture tests for webapp-current: the window class -> URL reconstruction, the
# handoff file, and the fall back to an empty form.
#
# Nothing here touches a live session. `hyprctl` and `quickshell` are replaced
# with fixtures, so the only real inputs are the JSON a focused window would
# produce and the class string inside it.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/hypr/.local/bin/webapp-current"
weblib_dir="$repo_root/hypr/.config/hypr/webapp"
test_root=$(mktemp -d -t webapp-current-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { printf 'skip: jq is not installed\n'; exit 0; }

bash -n "$script" || fail 'webapp-current does not parse'

mkdir -p "$test_root/bin" "$test_root/runtime"

# Reports whatever class the case under test put in $ACTIVE_CLASS. An empty
# value stands for "nothing is focused", which Hyprland answers with `{}`.
cat > "$test_root/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
case "$*" in
  '-j activewindow')
    if [[ -z ${ACTIVE_CLASS:-} ]]; then
      printf '%s\n' '{}'
    else
      printf '{"address":"0x1","class":"%s","initialClass":"%s","title":"fixture"}\n' \
        "$ACTIVE_CLASS" "$ACTIVE_CLASS"
    fi
    ;;
  *) exit 1 ;;
esac
SH
chmod +x "$test_root/bin/hyprctl"

cat > "$test_root/bin/quickshell" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$IPC_CALLS"
SH
chmod +x "$test_root/bin/quickshell"

export IPC_CALLS="$test_root/ipc.calls"
handoff="$test_root/runtime/webapp-current-url"

run() {
  ACTIVE_CLASS="$1" \
  HYPRCTL="$test_root/bin/hyprctl" \
  QUICKSHELL="$test_root/bin/quickshell" \
  XDG_RUNTIME_DIR="$test_root/runtime" \
    "$script" "${@:2}"
}

# ── class -> URL ────────────────────────────────────────────────────────────
# Every expectation is a class Chromium would actually build, per the format
# recorded in weblib.py (derived_wm_class).
while IFS='|' read -r class expected; do
  [[ -n $class ]] || continue
  actual=$(run "$class" --print) ||
    fail "no URL recovered from class $class"
  [[ $actual == "$expected" ]] ||
    fail "class $class produced $actual, expected $expected"
done <<'CASES'
brave-youtube.com__-Default|https://youtube.com/
brave-example.com__app-Default|https://example.com/app
brave-github.com__anthropics_claude-Default|https://github.com/anthropics/claude
brave-my-site.com__my-app-Default|https://my-site.com/my-app
chromium-mail.google.com__mail_u_0-Default|https://mail.google.com/mail/u/0
helium-localhost__dash-Default|https://localhost/dash
brave-example.com__a_b_c-Profile 1|https://example.com/a/b/c
CASES
printf 'ok: app-mode window classes reconstruct their URL\n'

# The parser is the inverse of weblib.derived_wm_class, so the two are checked
# against each other rather than against a hand-written class string.
while IFS='|' read -r url expected; do
  [[ -n $url ]] || continue
  class=$(python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import weblib
print(weblib.derived_wm_class(sys.argv[2]))
' "$weblib_dir" "$url") || fail "weblib could not derive a class for $url"
  actual=$(run "$class" --print) || fail "no URL recovered from derived class $class"
  [[ $actual == "$expected" ]] ||
    fail "round trip of $url via $class produced $actual, expected $expected"
done <<'CASES'
https://youtube.com/|https://youtube.com/
https://example.com/app|https://example.com/app
https://calendar.google.com/calendar/u/0/r|https://calendar.google.com/calendar/u/0/r
CASES
printf 'ok: reconstruction inverts weblib.derived_wm_class\n'

# Documented lossiness, asserted so it stays a known limitation rather than a
# surprise: the browser drops the query string before the class is built.
query_class=$(python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import weblib
print(weblib.derived_wm_class("https://example.com/app?tab=2#top"))
' "$weblib_dir")
[[ $(run "$query_class" --print) == https://example.com/app ]] ||
  fail 'query-string case no longer matches the documented behaviour'
printf 'ok: query string and fragment are dropped, as documented\n'

# ── refusals ────────────────────────────────────────────────────────────────
if run 'brave-__-Default' --print 2>"$test_root/nohost.err"; then
  fail 'an app-mode class with no host was accepted'
fi
grep -Fq 'no usable host' "$test_root/nohost.err" ||
  fail 'a hostless class did not explain itself'

if run 'brave-browser' --print 2>"$test_root/plain.err"; then
  fail '--print invented a URL for a plain browser window'
fi
grep -Fq 'not a web app window' "$test_root/plain.err" ||
  fail 'a plain browser window did not explain itself'

if run '' --print 2>"$test_root/nofocus.err"; then
  fail 'a missing focused window was accepted'
fi
grep -Fq 'no window is focused' "$test_root/nofocus.err" ||
  fail 'a missing focused window did not explain itself'
printf 'ok: unusable windows are refused with a reason\n'

# --print must never touch the shell or the handoff file.
[[ ! -s ${IPC_CALLS} ]] || fail '--print contacted the shell'
[[ ! -e $handoff ]] || fail '--print wrote the handoff file'
printf 'ok: --print is read-only\n'

# ── handoff ─────────────────────────────────────────────────────────────────
run 'brave-example.com__app-Default'
[[ $(cat "$handoff") == https://example.com/app ]] ||
  fail 'the handoff file does not hold the reconstructed URL'
mode=$(stat -c '%a' "$handoff")
[[ $mode == 600 ]] || fail "the handoff file is mode $mode, expected 600"
grep -Fqx 'ipc call webapps installCurrent' "$IPC_CALLS" ||
  fail 'the shell was not asked to open the install form'
printf 'ok: the URL reaches the shell through a 0600 handoff file\n'

# A plain browser window is not an error outside --print: the form still opens,
# and the stale URL from the previous case must not survive into it.
: > "$IPC_CALLS"
run 'brave-browser'
[[ -z $(cat "$handoff") ]] ||
  fail 'a plain browser window left the previous URL in the handoff file'
grep -Fqx 'ipc call webapps installCurrent' "$IPC_CALLS" ||
  fail 'a plain browser window did not open the install form'

: > "$IPC_CALLS"
run 'kitty'
[[ -z $(cat "$handoff") ]] || fail 'a non-browser window produced a URL'
grep -Fqx 'ipc call webapps installCurrent' "$IPC_CALLS" ||
  fail 'a non-browser window did not open the install form'
printf 'ok: windows with no URL open an empty form and clear the handoff\n'

# ── the two sides of the handoff agree on the path ──────────────────────────
grep -Fq 'webapp-current-url' "$repo_root/quickshell/.config/quickshell/WebAppState.qml" ||
  fail 'WebAppState no longer reads the handoff file webapp-current writes'
grep -Fq 'installCurrent' "$repo_root/quickshell/.config/quickshell/Bar.qml" ||
  fail 'the webapps IPC target no longer exposes installCurrent'
printf 'ok: script and shell agree on the handoff contract\n'

printf 'ok: webapp-current\n'

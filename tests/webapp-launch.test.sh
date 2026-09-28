#!/usr/bin/env bash
# Fixture tests for `webapp launch` and the webapp-launch helper: a menu click
# reaches the browser with the app's URL, and the launch path stays lean -- it
# must not import argparse or the network stack, which together were most of
# its startup time.
#
# The browser is a stub that records its arguments, and everything lives under
# a scratch XDG tree, so nothing here opens a window or touches the network.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
manager="$repo_root/hypr/.config/hypr/webapp/manager.py"
helper="$repo_root/hypr/.local/bin/webapp-launch"
test_root=$(mktemp -d -t webapp-launch-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

python3 -m py_compile "$manager" || fail 'manager.py does not compile'
bash -n "$helper" || fail 'webapp-launch has a syntax error'

mkdir -p "$test_root/bin" "$test_root/config" "$test_root/data" \
  "$test_root/cache" "$test_root/runtime"
browser_log="$test_root/browser.log"
cat > "$test_root/bin/brave" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "$browser_log.tmp" && mv "$browser_log.tmp" "$browser_log"
EOF
chmod +x "$test_root/bin/brave"

# A scratch XDG_CONFIG_HOME has no hypr/webapp/manager.py, so the helper falls
# back to the manager next to it in this checkout rather than the stowed one.
export XDG_CONFIG_HOME="$test_root/config"
export XDG_DATA_HOME="$test_root/data"
export XDG_CACHE_HOME="$test_root/cache"
export XDG_RUNTIME_DIR="$test_root/runtime"
export WEBAPP_BROWSER="$test_root/bin/brave"

webapp() { python3 "$manager" "$@"; }

webapp install --name Tube --url https://tube.example.com/watch --no-icon \
  --json >/dev/null

# ── the helper reaches the browser ──────────────────────────────────────────
"$helper" tube || fail 'webapp-launch exited non-zero'
for _ in $(seq 50); do
  [[ -f $browser_log ]] && break
  sleep 0.1
done
[[ -f $browser_log ]] || fail 'the browser was never started'
[[ $(<"$browser_log") == --app=https://tube.example.com/watch ]] ||
  fail "the browser got the wrong arguments: $(<"$browser_log")"
printf 'ok: webapp-launch opens the app URL in app mode\n'

# ── the fast path stays lean ────────────────────────────────────────────────
rm -f "$browser_log"
loaded=$(python3 -I -S - "$manager" <<'PY'
import runpy, sys
manager = sys.argv[1]
sys.argv = [manager, "launch", "tube"]
try:
    runpy.run_path(manager, run_name="__main__")
except SystemExit as exc:
    if exc.code:
        raise
heavy = ("argparse", "urllib.request", "http.client", "html.parser")
print(" ".join(m for m in heavy if m in sys.modules))
PY
) || fail 'launching through the fast path failed'
[[ -z $loaded ]] || fail "launch imported modules it does not need: $loaded"
printf 'ok: launch skips argparse and the network stack\n'

# ── everything else still takes the full parser ─────────────────────────────
out=$(webapp launch --print-command tube)
[[ $out == *'"--app=https://tube.example.com/watch"'* ]] ||
  fail "--print-command lost the URL: $out"
webapp launch --help | grep -q -- '--print-command' ||
  fail 'launch --help no longer reaches argparse'
printf 'ok: other launch forms still parse normally\n'

# ── failures are still reported ─────────────────────────────────────────────
# Called directly: through the helper this would raise a desktop notification.
if webapp launch nosuch 2>"$test_root/missing.err"; then
  fail 'launching an unknown id succeeded'
fi
grep -q '^error: ' "$test_root/missing.err" ||
  fail 'an unknown id did not produce an error message'
printf 'ok: an unknown id fails with a message\n'

# ── icon discovery still parses page heads ──────────────────────────────────
python3 - "$repo_root/hypr/.config/hypr/webapp" <<'PY' || fail 'icon link parsing regressed'
import sys
sys.path.insert(0, sys.argv[1])
import weblib
html = """<html><head>
<link rel="icon" href="/favicon.ico">
<link rel="apple-touch-icon" href="/touch.png">
<link rel="icon" sizes="512x512" href="/big.png">
<meta property="og:image" content="/banner.jpg">
</head><body></body></html>"""
got = sorted(weblib._icon_link_candidates(html), reverse=True)
want = [(512, "/big.png"), (180, "/touch.png"), (32, "/favicon.ico"),
        (16, "/banner.jpg")]
assert got == want, got
PY
printf 'ok: icon links are still ranked\n'

printf 'all webapp launch tests passed\n'

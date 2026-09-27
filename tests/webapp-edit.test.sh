#!/usr/bin/env bash
# Fixture tests for `webapp edit`: a name, URL or icon change rewrites the app's
# three files in place under the same id, and a launcher that is not ours is
# refused.
#
# Everything lives under a scratch XDG tree, and every icon is a local file, so
# nothing here touches the network or the real ~/.local/share.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
manager="$repo_root/hypr/.config/hypr/webapp/manager.py"
test_root=$(mktemp -d -t webapp-edit-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

python3 -m py_compile "$manager" || fail 'manager.py does not compile'

mkdir -p "$test_root/bin" "$test_root/data" "$test_root/cache" "$test_root/runtime"
# Only its name matters: the derived window class embeds the browser.
printf '#!/bin/sh\nexit 0\n' > "$test_root/bin/brave"
chmod +x "$test_root/bin/brave"

export XDG_DATA_HOME="$test_root/data"
export XDG_CACHE_HOME="$test_root/cache"
export XDG_RUNTIME_DIR="$test_root/runtime"
export WEBAPP_BROWSER="$test_root/bin/brave"

webapp() { python3 "$manager" "$@"; }
field() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }

# Two distinguishable 1x1 PNGs, so an icon swap is visible in the bytes.
png() {
  python3 - "$1" "$2" <<'PY'
import struct, sys, zlib
def chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
pixel = bytes([0, int(sys.argv[2]), 0, 0])
blob = (b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(pixel))
        + chunk(b"IEND", b""))
open(sys.argv[1], "wb").write(blob)
PY
}
png "$test_root/red.png" 200
png "$test_root/blue.png" 40

apps="$XDG_DATA_HOME/webapps/apps"
icons="$XDG_DATA_HOME/webapps/icons"
launcher="$XDG_DATA_HOME/applications/webapp-tube.desktop"

webapp install --name Tube --url https://tube.example.com/ \
  --icon "$test_root/red.png" --json >/dev/null
[[ -f $launcher ]] || fail 'install did not write the launcher'

# ── name and URL ────────────────────────────────────────────────────────────
out=$(webapp edit tube --name 'Tube Music' --url music.example.com/home --json)
[[ $(field id <<<"$out") == tube ]] || fail 'edit changed the id'
[[ $(field url <<<"$out") == https://music.example.com/home ]] ||
  fail 'edit did not normalise the new URL'
grep -Fxq 'Name=Tube Music' "$launcher" || fail 'the launcher still has the old name'
grep -Fxq 'Comment=music.example.com web app' "$launcher" ||
  fail 'the launcher still describes the old host'
grep -Fq 'name = "Tube Music"' "$apps/tube.toml" || fail 'the metadata kept the old name'
grep -Fq 'wm_class = "brave-music.example.com__home-Default"' "$apps/tube.toml" ||
  fail 'the window class was not re-derived from the new URL'
cmp -s "$test_root/red.png" "$icons/tube.png" || fail 'a name/URL edit touched the icon'
launchers=("$XDG_DATA_HOME"/applications/webapp-*.desktop)
[[ ${#launchers[@]} -eq 1 && ${launchers[0]} == "$launcher" ]] ||
  fail 'edit left a second launcher behind'
printf 'ok: name and URL are rewritten in place under the same id\n'

# ── icon ────────────────────────────────────────────────────────────────────
webapp edit tube --icon "$test_root/blue.png" --json >/dev/null
cmp -s "$test_root/blue.png" "$icons/tube.png" || fail 'the icon was not replaced'
grep -Fq 'icon_source = "user"' "$apps/tube.toml" || fail 'the icon source was not recorded'
grep -Fxq "Icon=$icons/tube.png" "$launcher" || fail 'the launcher points at the wrong icon'
grep -Fxq 'Name=Tube Music' "$launcher" || fail 'an icon-only edit changed the name'
printf 'ok: the icon is replaced and nothing else moves\n'

# Editing with the app's own icon (what the panel's preview holds) is harmless.
webapp edit tube --icon "$icons/tube.png" --json >/dev/null
cmp -s "$test_root/blue.png" "$icons/tube.png" || fail 're-using the current icon corrupted it'
printf 'ok: re-submitting the current icon is a no-op\n'

# ── refusals ────────────────────────────────────────────────────────────────
before=$(cat "$apps/tube.toml")
if webapp edit tube --url 'javascript:alert(1)' 2>"$test_root/scheme.err"; then
  fail 'a javascript: URL was accepted'
fi
if webapp edit tube --name '' 2>/dev/null; then
  fail 'an empty name was accepted'
fi
if webapp edit tube --icon "$test_root/missing.png" 2>/dev/null; then
  fail 'a missing icon file was accepted'
fi
[[ $(cat "$apps/tube.toml") == "$before" ]] || fail 'a refused edit still changed the metadata'
printf 'ok: invalid input is refused and changes nothing\n'

if webapp edit nope --name X 2>"$test_root/unknown.err"; then
  fail 'an unknown id was accepted'
fi
grep -Fq 'no web app' "$test_root/unknown.err" || fail 'an unknown id did not explain itself'

sed -i '/^X-Hypr-WebApp-ID=/d' "$launcher"
if webapp edit tube --name Other 2>"$test_root/owner.err"; then
  fail 'a launcher without our marker was rewritten'
fi
grep -Fq 'refusing to rewrite' "$test_root/owner.err" ||
  fail 'an unowned launcher did not explain itself'
grep -Fxq 'Name=Tube Music' "$launcher" || fail 'the unowned launcher was modified'
printf 'ok: unknown ids and unowned launchers are refused\n'

printf 'all webapp edit tests passed\n'

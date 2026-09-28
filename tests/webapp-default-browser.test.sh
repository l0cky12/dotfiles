#!/usr/bin/env bash
# Fixture tests for how web apps pick a browser: $WEBAPP_BROWSER, then the XDG
# default browser when it is Chromium-family, then the first built-in
# candidate. A default without an app mode (Firefox) falls back rather than
# opening a normal browser window.
#
# Every run is `env -i` with a scratch XDG tree and a PATH of stub browsers, so
# neither the real mimeapps.list nor the installed browsers can leak in.
# shellcheck disable=SC2016  # messages name $WEBAPP_BROWSER etc. literally
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
manager="$repo_root/hypr/.config/hypr/webapp/manager.py"
test_root=$(mktemp -d -t webapp-default-browser-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

python3 -m py_compile "$manager" || fail 'manager.py does not compile'
py=$(command -v python3)

config="$test_root/config"
sys_config="$test_root/etc"
data="$test_root/data"
sys_data="$test_root/share"
mkdir -p "$test_root/bin" "$test_root/home" "$test_root/cache" "$test_root/runtime" \
  "$config" "$sys_config" "$data/applications" "$sys_data/applications"
for browser in brave chromium helium-browser firefox; do
  printf '#!/bin/sh\nexit 0\n' > "$test_root/bin/$browser"
  chmod +x "$test_root/bin/$browser"
done

base_env=(
  "HOME=$test_root/home"
  "PATH=$test_root/bin"
  "XDG_CONFIG_HOME=$config"
  "XDG_CONFIG_DIRS=$sys_config"
  "XDG_DATA_HOME=$data"
  "XDG_DATA_DIRS=$sys_data"
  "XDG_CACHE_HOME=$test_root/cache"
  "XDG_RUNTIME_DIR=$test_root/runtime"
  "XDG_CURRENT_DESKTOP=Hyprland"
)
webapp() { env -i "${base_env[@]}" "$py" "$manager" "$@"; }

# The browser `launch` would run, as a bare executable name.
chosen() {
  env -i "${base_env[@]}" "$@" "$py" "$manager" launch --print-command tube |
    "$py" -c 'import json, os, sys; print(os.path.basename(json.load(sys.stdin)["command"][0]))'
}

entry() { # entry <dir> <desktop id> <Exec value>
  cat > "$1/$2" <<EOF
[Desktop Entry]
Type=Application
Name=${2%.desktop}
Exec=$3
Actions=new-window;

[Desktop Action new-window]
Name=New window
Exec=firefox --new-window
EOF
}

defaults() { # defaults <file> <https value> [<http value>]
  {
    printf '[Default Applications]\n'
    [[ -n $2 ]] && printf 'x-scheme-handler/https=%s\n' "$2"
    [[ -n ${3:-} ]] && printf 'x-scheme-handler/http=%s\n' "$3"
    printf '\n[Added Associations]\nx-scheme-handler/https=firefox.desktop;\n'
  } > "$1"
}

entry "$data/applications" helium.desktop 'helium-browser %U'
entry "$data/applications" chromium.desktop 'chromium %U'
entry "$data/applications" firefox.desktop 'firefox %u'

webapp install --name Tube --url https://tube.example.com/ --no-icon --json \
  >/dev/null 2>&1 || fail 'could not install the fixture app'

# ── no default configured ───────────────────────────────────────────────────
[[ $(chosen) == brave ]] || fail 'without a default the first candidate was not used'
webapp doctor 2>&1 | grep -Fq 'fallback: no default browser is set' ||
  fail 'doctor did not explain the fallback'
printf 'ok: no default browser falls back to the candidate list\n'

# ── a Chromium-family default wins ──────────────────────────────────────────
defaults "$config/mimeapps.list" helium.desktop
[[ $(chosen) == helium-browser ]] || fail "the default browser was ignored: $(chosen)"
webapp doctor 2>&1 | grep -Fq 'default browser (helium.desktop)' ||
  fail 'doctor did not name the default browser'
printf 'ok: a Chromium-family default browser is used, via its main Exec\n'

# Helium keeps Chromium's `chrome` prefix for app windows; only Brave uses its
# own name. The recorded class has to be what Hyprland will really see.
webapp install --name Chat --url https://chat.example.com/room --no-icon --json \
  >/dev/null 2>&1 || fail 'could not install under the Helium default'
grep -Fq 'wm_class = "chrome-chat.example.com__room-Default"' \
  "$data/webapps/apps/chat.toml" || fail 'a Helium app recorded the wrong window class'
grep -Fq 'wm_class = "brave-tube.example.com__-Default"' \
  "$data/webapps/apps/tube.toml" || fail 'a Brave app recorded the wrong window class'
printf 'ok: the recorded window class follows the chosen browser\n'

# ── a desktop-specific list outranks the plain one ──────────────────────────
defaults "$config/hyprland-mimeapps.list" chromium.desktop
[[ $(chosen) == chromium ]] || fail 'hyprland-mimeapps.list did not take precedence'
rm "$config/hyprland-mimeapps.list"
printf 'ok: $desktop-mimeapps.list is read first\n'

# ── a default without app mode falls back ───────────────────────────────────
defaults "$config/mimeapps.list" firefox.desktop
[[ $(chosen) == brave ]] || fail "a Firefox default was not replaced: $(chosen)"
webapp doctor 2>&1 | grep -Fq 'fallback: default browser firefox.desktop has no app mode' ||
  fail 'doctor did not explain why Firefox was skipped'
printf 'ok: a non-Chromium default falls back to a Chromium browser\n'

# ── entries that are not installed are skipped ──────────────────────────────
defaults "$config/mimeapps.list" 'gone.desktop;helium.desktop;'
[[ $(chosen) == helium-browser ]] || fail 'an uninstalled first entry was not skipped'
printf 'ok: uninstalled entries in the default list are skipped\n'

# ── system-wide lists and entries, and the http fallback ────────────────────
rm "$config/mimeapps.list"
entry "$sys_data/applications" sys-chromium.desktop '/usr/bin/env GDK_BACKEND=wayland chromium %U'
defaults "$sys_config/mimeapps.list" '' sys-chromium.desktop
[[ $(chosen) == chromium ]] ||
  fail 'a system http default behind an env wrapper was not found'
printf 'ok: system lists, the http handler and env wrappers are understood\n'

# ── a default whose program is missing falls back ───────────────────────────
rm "$sys_config/mimeapps.list"
entry "$data/applications" vivaldi.desktop 'vivaldi-stable %U'
defaults "$config/mimeapps.list" vivaldi.desktop
[[ $(chosen) == brave ]] || fail 'a default with no installed program was used'
webapp doctor 2>&1 | grep -Fq 'no default browser is set' ||
  fail 'doctor did not explain the lack of a usable default'
printf 'ok: a default whose program is not installed falls back\n'

# ── $WEBAPP_BROWSER still wins ──────────────────────────────────────────────
defaults "$config/mimeapps.list" helium.desktop
[[ $(chosen WEBAPP_BROWSER=chromium) == chromium ]] ||
  fail '$WEBAPP_BROWSER did not override the default browser'
printf 'ok: $WEBAPP_BROWSER overrides the default browser\n'

# Existing but unusable entries must not hide the next valid default.
entry "$data/applications" gone.desktop 'missing-browser %U'
defaults "$config/mimeapps.list" 'gone.desktop;helium.desktop;'
[[ $(chosen) == helium-browser ]] || fail 'a stale desktop file hid the next default'
entry "$data/applications" gone.desktop 'chromium %U'
printf '\n[Desktop Entry]\nHidden=true\nExec=chromium %%U\n' >"$data/applications/gone.desktop"
entry "$sys_data/applications" gone.desktop 'chromium %U'
[[ $(chosen) == helium-browser ]] || fail 'a hidden user entry did not mask the system entry'
entry "$data/applications" gone.desktop 'chromium %U'
sed -i '/Type=Application/a TryExec=missing-browser' "$data/applications/gone.desktop"
[[ $(chosen) == helium-browser ]] || fail 'an unavailable TryExec hid the next default'

printf 'all webapp default browser tests passed\n'

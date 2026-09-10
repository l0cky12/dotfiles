#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
picker="$repo_root/hypr/.local/bin/hypr-wallpaper-picker"
test_root="$(mktemp -d -t hypr-wallpaper-picker-test.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT

# shellcheck source=/dev/null
source "$picker"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

command -v jq >/dev/null 2>&1 || {
  printf 'skip: jq is not installed\n'
  exit 0
}


assert_eq() {
    [[ "$1" == "$2" ]] || fail "expected [$1], got [$2]"
}

assert_contains() {
    grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]"
}

assert_missing() {
    [[ ! -e "$1" ]] || fail "$1 should not exist"
}

default_wallpaper_dir="$test_root/Pictures/wallpapers"
mkdir -p "$default_wallpaper_dir"
printf fixture > "$default_wallpaper_dir/default.png"
env -u HYPR_WALLPAPER_DIR HOME="$test_root" "$picker" index > "$test_root/default-index.json"
jq -e --arg path "$default_wallpaper_dir/default.png" \
    '.items[] | select(.path == $path)' "$test_root/default-index.json" >/dev/null || \
    fail "default wallpaper directory was not ~/Pictures/wallpapers"

notify-send() {
    printf '%s\n' "$*" >> "$test_root/notifications"
}

wallpaper_dir="$test_root/wallpapers"
runtime_dir="$test_root/runtime"
state_file="$test_root/state/current"
mkdir -p "$wallpaper_dir/one" "$wallpaper_dir/two"
printf x > "$wallpaper_dir/b space.JPG"
printf x > "$wallpaper_dir/a-雪.png"
printf x > "$wallpaper_dir/ignored.jpeg"
printf x > "$wallpaper_dir/one/same.png"
printf x > "$wallpaper_dir/two/same.png"
printf x > "$wallpaper_dir/line
break.jpg"

list_wallpapers > "$test_root/index.json"
assert_eq 5 "$(jq '.items | length' "$test_root/index.json")"
assert_eq 2 "$(jq '[.items[] | select(.name == "same.png")] | length' "$test_root/index.json")"
jq -e '.items[] | select(.name == "line\nbreak.jpg")' "$test_root/index.json" >/dev/null || \
    fail "newline filename was not preserved in JSON"
if jq -e '.items[] | select(.name == "ignored.jpeg")' "$test_root/index.json" >/dev/null; then
    fail "unsupported JPEG was included"
fi

HYPR_WALLPAPER_DIR="$wallpaper_dir" "$picker" index > "$test_root/cli-index.json"
assert_eq 5 "$(jq '.items | length' "$test_root/cli-index.json")"

cat > "$test_root/wallhaven.json" <<'JSON'
{"data":[{"id":"abc123","path":"https://w.wallhaven.cc/full/ab/wallhaven-abc123.png","thumbs":{"large":"https://th.wallhaven.cc/lg/ab/abc123.jpg"},"resolution":"2560x1440"}],"meta":{"current_page":1,"last_page":2}}
JSON
printf preview > "$test_root/preview.jpg"
printf image > "$test_root/download.png"

dns_mode=allowed
getent() {
    if [[ "$dns_mode" == blocked ]]; then
        printf '146.112.61.104  STREAM %s\n' "$2"
    else
        printf '104.21.4.33  STREAM %s\n' "$2"
    fi
}

curl_mode=search
curl() {
    local output="" previous="" argument
    printf '%s\n' "$*" >> "$test_root/curl.log"
    for argument in "$@"; do
        [[ "$previous" == -o ]] && output="$argument"
        previous="$argument"
    done
    case "$curl_mode" in
        fail) return 1 ;;
        corrupt) printf broken > "$output" ;;
        download) cp "$test_root/download.png" "$output" ;;
        search)
            [[ "$*" == *api/v1/search* ]] && \
                cp "$test_root/wallhaven.json" "$output" || \
                cp "$test_root/preview.jpg" "$output"
            ;;
    esac
}

dns_mode=blocked
if search_wallhaven "space cats" 1 > /dev/null 2> "$test_root/dns-blocked.err"; then
    fail "Cisco-blocked search reported success"
fi
assert_contains "$test_root/dns-blocked.err" "Allow wallhaven.cc, th.wallhaven.cc, and w.wallhaven.cc"
assert_missing "$test_root/curl.log"
dns_mode=allowed

search_wallhaven "space cats" 1 > "$test_root/results.json"
assert_eq 1 "$(jq '.items | length' "$test_root/results.json")"
assert_eq abc123 "$(jq -r '.items[0].id' "$test_root/results.json")"
preview="$(jq -r '.items[0].wallpaper' "$test_root/results.json")"
[[ -s "$preview" ]] || fail "Wallhaven preview was not cached"
assert_contains "$test_root/curl.log" "q=space cats"
assert_contains "$test_root/curl.log" "page=1"
assert_contains "$test_root/curl.log" "categories=111"
assert_contains "$test_root/curl.log" "purity=100"
assert_contains "$test_root/curl.log" "sorting=relevance"
assert_contains "$test_root/curl.log" "atleast=1920x1080"

search_wallpapers "space" 1 > "$test_root/combined-results.json"
assert_eq 2 "$(jq '.items | length' "$test_root/combined-results.json")"
assert_eq local "$(jq -r '.items[0].kind' "$test_root/combined-results.json")"
assert_eq "b space.JPG" "$(jq -r '.items[0].name' "$test_root/combined-results.json")"
assert_eq wallhaven "$(jq -r '.items[1].kind' "$test_root/combined-results.json")"

search_wallpapers "space" 2 > "$test_root/page-two-results.json"
assert_eq 1 "$(jq '.items | length' "$test_root/page-two-results.json")"
assert_eq wallhaven "$(jq -r '.items[0].kind' "$test_root/page-two-results.json")"

magick_ok=1
magick() { ((magick_ok == 1)); }

dns_mode=blocked
if download_wallhaven blocked1 https://w.wallhaven.cc/full/bl/wallhaven-blocked1.png \
    > /dev/null 2> "$test_root/download-dns-blocked.err"; then
    fail "Cisco-blocked download reported success"
fi
assert_contains "$test_root/download-dns-blocked.err" "Allow wallhaven.cc, th.wallhaven.cc, and w.wallhaven.cc"
assert_missing "$wallpaper_dir/wallhaven-blocked1.png.part"
dns_mode=allowed

curl_mode=fail
if download_wallhaven abc123 https://w.wallhaven.cc/full/ab/wallhaven-abc123.png; then
    fail "failed download reported success"
fi
assert_missing "$wallpaper_dir/wallhaven-abc123.png.part"

curl_mode=corrupt
magick_ok=0
if download_wallhaven abc123 https://w.wallhaven.cc/full/ab/wallhaven-abc123.png; then
    fail "corrupt download reported success"
fi
assert_missing "$wallpaper_dir/wallhaven-abc123.png.part"
assert_missing "$wallpaper_dir/wallhaven-abc123.png"

curl_mode=download
magick_ok=1
downloaded="$(download_wallhaven abc123 https://w.wallhaven.cc/full/ab/wallhaven-abc123.png)"
assert_eq "$wallpaper_dir/wallhaven-abc123.png" "$downloaded"
[[ -s "$downloaded" ]] || fail "successful download was not installed"
list_wallpapers > "$test_root/index-after-download.json"
jq -e --arg path "$downloaded" '.items[] | select(.path == $path)' \
    "$test_root/index-after-download.json" >/dev/null || \
    fail "downloaded wallpaper was not added to the local index"

pkill() { return 0; }
pgrep() { return 1; }
hyprpaper() { return 0; }
hyprctl() { return 1; }
sleep() { return 0; }
if set_wallpaper "$downloaded"; then
    fail "failed hyprpaper application reported success"
fi
grep -Fq "hyprpaper failed to set the wallpaper" "$test_root/notifications" || \
    fail "application failure was not reported"

hyprctl() { return 0; }
set_wallpaper "$downloaded" || fail "successful mocked application failed"
jq -e --arg path "$(realpath -e -- "$downloaded")" '.path == $path' \
    "$state_file" >/dev/null || fail "successful application was not persisted"
assert_eq "$(realpath -e -- "$downloaded")" "$(current_wallpaper)"
assert_eq "$(realpath -e -- "$downloaded")" \
    "$(HYPR_WALLPAPER_STATE_FILE="$state_file" "$picker" current)"

printf '{broken json\n' > "$state_file"
if current_wallpaper; then
    fail "malformed wallpaper state reported a current image"
fi

printf '{"path":"%s"}\n' "$test_root/missing.jpg" > "$state_file"
if current_wallpaper; then
    fail "stale wallpaper state reported a current image"
fi

rm -f -- "$state_file"
if current_wallpaper; then
    fail "missing wallpaper state reported a current image"
fi

persist_wallpaper "$downloaded" || fail "wallpaper state fixture could not be restored"

applied_log="$test_root/applied"
apply_wallpaper() { printf '%s\n' "$1" >> "$applied_log"; }
restore_wallpaper || fail "saved wallpaper did not restore"
assert_contains "$applied_log" "$(realpath -e -- "$downloaded")"

rm -f -- "$state_file"
hyprpaper_started=0
ensure_hyprpaper_running() { hyprpaper_started=1; }
restore_wallpaper || fail "missing saved wallpaper did not fall back cleanly"
assert_eq 1 "$hyprpaper_started"

# Explicit theme wallpaper selection is another wallpaper setter. It must write
# the same state document so the most recent explicit choice wins at next login.
python3 - "$repo_root/hypr/.config/hypr/theme/generate.py" "$downloaded" \
    "$test_root/theme-state/current" <<'PY'
import importlib.util
import json
import sys
from pathlib import Path

module_path, wallpaper, state = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("theme_generate_fixture", module_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
module.WALLPAPER_STATE_FILE = state
module.tl.resolve_wallpaper = lambda _name: wallpaper
module.shutil.which = lambda _name: "/fixture"
module._pids_of = lambda _name: [1]
module._run = lambda *_args, **_kwargs: True

class Theme:
    wallpaper = "fixture"

result = module.apply_wallpaper(Theme())
assert result == wallpaper.name, result
assert json.loads(state.read_text()) == {"path": str(wallpaper.resolve())}

# Theme changes preserve the wallpaper unless the caller explicitly opts in.
captured = []
def capture(args):
    captured.append(args)
    return 0

module.cmd_set = capture
assert module.main(["set", "ethereal"]) == 0
assert captured.pop().wallpaper is False
assert module.main(["set", "ethereal", "--wallpaper"]) == 0
assert captured.pop().wallpaper is True
assert module.main(["set", "ethereal", "--no-wallpaper"]) == 0
assert captured.pop().wallpaper is False
assert module.main(["cycle", "next"]) == 0
assert captured.pop().wallpaper is False
assert module.main(["cycle", "next", "--wallpaper"]) == 0
assert captured.pop().wallpaper is True
PY

[[ -d "$runtime_dir" ]] || fail "search runtime directory was not created"
cleanup
assert_missing "$runtime_dir"

assert_contains "$repo_root/quickshell/.config/quickshell/ThemePicker.qml" \
    "property var controller: ThemeState"
assert_contains "$repo_root/quickshell/.config/quickshell/Bar.qml" \
    "controller: WallpaperState"
assert_contains "$repo_root/quickshell/.config/quickshell/WallpaperState.qml" \
    'root.mode !== "local"'
assert_contains "$repo_root/quickshell/.config/quickshell/WallpaperState.qml" \
    '"Search Wallhaven for “" + root.query.trim() + "”"'
assert_contains "$repo_root/quickshell/.config/quickshell/WallpaperState.qml" \
    'root.wallhavenQuery = root.query.trim()'

printf 'ok: hypr-wallpaper-picker fixtures\n'

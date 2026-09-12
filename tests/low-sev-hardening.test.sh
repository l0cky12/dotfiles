#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
location_script="$repo_root/hyprlock/.config/hyprlock/scripts/location.sh"
weather_script="$repo_root/hyprlock/.config/hyprlock/scripts/weather.sh"
wallpaper_script="$repo_root/hypr/.config/hypr/scripts/WallpaperSwitch.sh"
test_root="$(mktemp -d -t low-sev-hardening-test.XXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]"
}

if grep -Fq -- 'http://' "$location_script" "$weather_script"; then
  fail "plaintext HTTP URL remains in a Hyprlock helper"
fi

for script in "$location_script" "$weather_script"; do
  assert_contains "$script" "https://"
  assert_contains "$script" "--fail"
  assert_contains "$script" "--show-error"
  assert_contains "$script" "--location"
  assert_contains "$script" "--connect-timeout 5"
  assert_contains "$script" "--max-time 15"
  assert_contains "$script" "max_output_length="
done

assert_contains "$location_script" 'HYPRLOCK_ENABLE_LOCATION'
if grep -Eq '(^|[[:space:]|;])eval([[:space:]]|$)' "$wallpaper_script"; then
  fail "WallpaperSwitch.sh still invokes eval"
fi
assert_contains "$wallpaper_script" 'rofi_args=('
assert_contains "$wallpaper_script" 'menu | rofi "${rofi_args[@]}"'

stub_bin="$test_root/bin"
mkdir -p "$stub_bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >>"${CURL_LOG:?}"' \
  'case ${CURL_MODE:-valid} in' \
  '  empty) exit 0 ;;' \
  '  long) printf "%200s" "" | tr " " x; exit 0 ;;' \
  'esac' \
  'case $* in' \
  '  *ipinfo.io*) printf "{\"country\":\"US\",\"city\":\"Fixture City\"}\n" ;;' \
  '  *) printf "Clear +21C\n" ;;' \
  'esac' >"$stub_bin/curl"
chmod +x "$stub_bin/curl"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'IFS= read -r input || true' \
  '[[ $input == *'"'"'"country":"US","city":"Fixture City"'"'"'* ]] || exit 1' \
  'printf "US, Fixture City\n"' >"$stub_bin/jq"
chmod +x "$stub_bin/jq"

disabled_home="$test_root/disabled-home"
disabled_log="$test_root/disabled-curl.log"
mkdir -p "$disabled_home"
output=$(env -u HYPRLOCK_ENABLE_LOCATION HOME="$disabled_home" \
  PATH="$stub_bin:$PATH" CURL_LOG="$disabled_log" "$location_script")
[[ "$output" == "Location unavailable" ]] || fail "disabled location was not neutral"
[[ ! -e "$disabled_log" ]] || fail "disabled location invoked curl"

location_home="$test_root/location-home"
location_log="$test_root/location-curl.log"
mkdir -p "$location_home"
output=$(HOME="$location_home" PATH="$stub_bin:$PATH" CURL_LOG="$location_log" \
  HYPRLOCK_ENABLE_LOCATION=1 "$location_script")
[[ "$output" == "US, Fixture City" ]] || fail "enabled location fixture failed"
assert_contains "$location_log" "--connect-timeout 5 --max-time 15 https://ipinfo.io"

weather_home="$test_root/weather-home"
weather_log="$test_root/weather-curl.log"
mkdir -p "$weather_home"
output=$(HOME="$weather_home" PATH="$stub_bin:$PATH" CURL_LOG="$weather_log" \
  "$weather_script")
[[ "$output" == "Clear +21C" ]] || fail "weather fixture failed"
assert_contains "$weather_log" "--connect-timeout 5 --max-time 15 https://wttr.in?format=%c+%C+%t"

invalid_home="$test_root/invalid-home"
mkdir -p "$invalid_home"
output=$(HOME="$invalid_home" PATH="$stub_bin:$PATH" \
  CURL_LOG="$test_root/invalid-curl.log" CURL_MODE=long "$weather_script")
[[ "$output" == "Weather unavailable" ]] || fail "oversized weather output was accepted"
[[ ! -e "$invalid_home/.cache/wttr_cache.txt" ]] || fail "invalid weather response was cached"

wallpaper_bin="$test_root/wallpaper-bin"
wallpaper_home="$test_root/home with spaces"
rofi_log="$test_root/rofi.log"
mkdir -p "$wallpaper_bin" "$wallpaper_home/Pictures/wallpapers"
printf fixture >"$wallpaper_home/Pictures/wallpapers/fixture.png"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "<%s>\n" "$@" >"${ROFI_LOG:?}"' \
  'while IFS= read -r _; do :; done' >"$wallpaper_bin/rofi"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "Monitor HDMI-A-1" "height: 1080" "scale: 1" "focused: yes"' \
  >"$wallpaper_bin/hyprctl"
printf '%s\n' '#!/usr/bin/env bash' 'printf "20\n"' >"$wallpaper_bin/bc"
chmod +x "$wallpaper_bin/rofi" "$wallpaper_bin/hyprctl" "$wallpaper_bin/bc"

HOME="$wallpaper_home" PATH="$wallpaper_bin:$PATH" ROFI_LOG="$rofi_log" \
  "$wallpaper_script"
assert_contains "$rofi_log" "<$wallpaper_home/.config/rofi/config-wallpaper.rasi>"
assert_contains "$rofi_log" '<element-icon{size:20%;}>'

printf 'ok: low-severity script hardening\n'

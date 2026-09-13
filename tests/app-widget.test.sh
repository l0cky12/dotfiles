#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
launcher="$repo_root/hypr/.config/hypr/scripts/app-widget"
widget="$repo_root/quickshell/.config/quickshell/AppLauncher.qml"
config="$repo_root/quickshell/.config/quickshell/app-launcher.json"
smoke="$repo_root/quickshell/.config/quickshell/AppLauncherSmoke.qml"
test_root=$(mktemp -d -t app-widget-test.XXXXXX)
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$test_root/bin"
cat >"$test_root/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
if [[ $1 == -j && $2 == clients ]]; then
  printf '%s\n' "${APP_WIDGET_CLIENTS:-[]}"
else
  printf '%s\n' "$*" >>"$APP_WIDGET_CALLS"
fi
SH
cat >"$test_root/bin/gtk-launch" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$APP_WIDGET_LAUNCHES"
SH
chmod +x "$test_root/bin/hyprctl" "$test_root/bin/gtk-launch"

export PATH="$test_root/bin:$PATH"
export APP_WIDGET_CALLS="$test_root/calls"
export APP_WIDGET_LAUNCHES="$test_root/launches"

APP_WIDGET_CLIENTS='[{"address":"0xabc","class":"spotify"}]' \
  "$launcher" spotify spotify
[[ $(<"$test_root/calls") == 'dispatch focuswindow address:0xabc' ]] ||
  fail 'existing app window was not focused by address'
[[ ! -e $test_root/launches ]] || fail 'existing app was launched instead of focused'

: >"$test_root/calls"
APP_WIDGET_CLIENTS='[]' "$launcher" spotify spotify
[[ $(<"$test_root/launches") == 'spotify' ]] || fail 'closed app was not launched'
[[ ! -s $test_root/calls ]] || fail 'closed app attempted to focus a window'

APP_WIDGET_CLIENTS='[]' "$launcher" --dry-run spotify spotify >"$test_root/dry-run"
grep -Fq 'action=would-launch desktop_id=spotify' "$test_root/dry-run" ||
  fail 'dry-run does not report the launch path'

if "$launcher" 'spotify;bad' spotify >/dev/null 2>&1; then
  fail 'unsafe desktop id was accepted'
fi

grep -Fq 'FileView {' "$widget" || fail 'app widget has no watched configuration'
grep -Fq 'PopupWindow {' "$widget" || fail 'app widget has no hover name popup'
grep -Fq 'appLauncher.running = true' "$widget" || fail 'app widget click is not wired'
grep -Fq 'AppLauncher {' "$repo_root/quickshell/.config/quickshell/Bar.qml" ||
  fail 'bar does not mount the app launcher'
grep -Fq '"desktopId": "spotify"' "$config" || fail 'Spotify is not pinned by default'

if command -v quickshell >/dev/null 2>&1; then
  smoke_log="$test_root/smoke.log"
  QT_QPA_PLATFORM=offscreen timeout 30 quickshell -p "$smoke" >"$smoke_log" 2>&1 || true
  grep -Fq 'ok: App launcher configuration' "$smoke_log" || {
    sed -n '1,120p' "$smoke_log" >&2
    fail 'AppLauncherSmoke.qml did not load the configured app'
  }
  if grep -Fq 'FAIL:' "$smoke_log"; then
    grep -F 'FAIL:' "$smoke_log" >&2
    fail 'AppLauncherSmoke.qml reported a failing assertion'
  fi
fi

printf 'app widget: ok\n'

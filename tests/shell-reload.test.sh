#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d -t shell-reload-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin"
export RELOAD_CALLS="$test_root/calls" RELOAD_RUNNING="$test_root/running"

cat >"$test_root/bin/stub" <<'SH'
#!/usr/bin/env bash
case ${0##*/} in
  pgrep)
    case $2 in
      Hyprland) exit "${RELOAD_HYPRLAND_STATUS:-0}" ;;
      quickshell) [[ -e $RELOAD_RUNNING ]] ;;
      *) exit 2 ;;
    esac ;;
  pkill)
    printf 'pkill %s\n' "$*" >>"$RELOAD_CALLS"
    rm -f -- "$RELOAD_RUNNING" ;;
  hyprctl|quickshell)
    printf '%s %s\n' "${0##*/}" "$*" >>"$RELOAD_CALLS"
    exit "${RELOAD_COMMAND_STATUS:-0}" ;;
esac
SH
chmod +x "$test_root/bin/stub"
for name in pgrep pkill hyprctl quickshell; do
  ln -s stub "$test_root/bin/$name"
done
export PATH="$test_root/bin:/usr/bin:/bin"

touch "$RELOAD_RUNNING"
bash "$repo_root/hypr/.config/hypr/scripts/shell-reload.sh" >/dev/null
[[ $(cat "$RELOAD_CALLS") == $'hyprctl reload\npkill -x quickshell\nquickshell --daemonize' ]]

: >"$RELOAD_CALLS"
RELOAD_HYPRLAND_STATUS=1 bash "$repo_root/hypr/.config/hypr/scripts/shell-reload.sh" >/dev/null
[[ $(cat "$RELOAD_CALLS") == 'quickshell --daemonize' ]]

: >"$RELOAD_CALLS"
touch "$RELOAD_RUNNING"
if RELOAD_COMMAND_STATUS=1 bash "$repo_root/hypr/.config/hypr/scripts/shell-reload.sh" >/dev/null 2>&1; then
  printf 'FAIL: failed compositor reload reported success\n' >&2
  exit 1
fi
[[ $(cat "$RELOAD_CALLS") == 'hyprctl reload' ]]
[[ -e $RELOAD_RUNNING ]]

if RELOAD_HYPRLAND_STATUS=1 RELOAD_COMMAND_STATUS=1 bash "$repo_root/hypr/.config/hypr/scripts/shell-reload.sh" >/dev/null 2>&1; then
  printf 'FAIL: failed shell startup reported success\n' >&2
  exit 1
fi

printf 'ok: shell reload fixtures\n'

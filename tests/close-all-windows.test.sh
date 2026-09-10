#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/hypr/.config/hypr/scripts/close-all-windows.sh"
test_root=$(mktemp -d -t close-all-windows-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s
' "$1" >&2
  exit 1
}

require_jq() {
  command -v jq >/dev/null 2>&1 || {
    printf 'skip: jq is not installed
'
    exit 0
  }
}

require_jq

cat >"$test_root/hyprctl" <<'SH'
#!/usr/bin/env bash
case $1 in
  clients)
    printf '%s\n' '[{"address":"0xabc"},{"address":"0xdef"}]'
    ;;
  eval)
    printf '%s\n' "$2" >>"$CLOSE_LOG"
    ;;
  *) exit 2 ;;
esac
SH
chmod +x "$test_root/hyprctl"

export HYPRCTL="$test_root/hyprctl"
export CLOSE_LOG="$test_root/close.log"

"$script" --dry-run >"$test_root/dry-run.out"
[[ $(grep -c '^+' "$test_root/dry-run.out") == 2 ]] || fail 'dry run did not plan two closes'
grep -Fq 'address:0xabc' "$test_root/dry-run.out" || fail 'dry run omitted the first window'
grep -Fq 'address:0xdef' "$test_root/dry-run.out" || fail 'dry run omitted the second window'

"$script"
[[ $(wc -l <"$CLOSE_LOG") == 2 ]] || fail 'fixture did not close two windows'
grep -Fxq 'hl.dispatch(hl.dsp.window.close({ window = "address:0xabc" }))' "$CLOSE_LOG" || fail 'first Lua close expression is wrong'
grep -Fxq 'hl.dispatch(hl.dsp.window.close({ window = "address:0xdef" }))' "$CLOSE_LOG" || fail 'second Lua close expression is wrong'

printf 'close-all-windows fixtures: ok\n'

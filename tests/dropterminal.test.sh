#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d -t dropterminal-test.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
mkdir "$fixture/bin"
printf '0x1 DP-1\n' > "$fixture/address"

cat > "$fixture/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DROPTERMINAL_TEST_CALLS"
case $* in
  'activeworkspace -j') printf '{"id":1}\n' ;;
  'monitors -j') printf '[{"focused":true,"x":1000,"y":0,"width":1920,"height":1080,"scale":1,"name":"DP-2"}]\n' ;;
  'clients -j')
    if [[ -e $DROPTERMINAL_TEST_MOVED ]]; then
      printf '[{"address":"0x1","at":[1336,108],"size":[1248,702],"workspace":{"name":"1"}}]\n'
    else
      printf '[{"address":"0x1","at":[100,100],"size":[800,600],"workspace":{"name":"1"}}]\n'
    fi
    ;;
  dispatch*) [[ $* != *'window.move({ x = 1336'* ]] || : > "$DROPTERMINAL_TEST_MOVED" ;;
  *) printf 'unexpected hyprctl call: %s\n' "$*" >&2; exit 1 ;;
esac
SH
chmod +x "$fixture/bin/hyprctl"

DROPTERMINAL_ADDR_FILE="$fixture/address" DROPTERMINAL_TEST_MOVED="$fixture/moved" \
  DROPTERMINAL_TEST_CALLS="$fixture/calls" \
  PATH="$fixture/bin:$PATH" \
  "$repo_root/hypr/.config/hypr/scripts/Dropterminal.sh" kitty > "$fixture/output"
grep -Fq 'hl.dsp.window.move({ x = 1336, y = 108,' "$fixture/calls"
grep -Fq 'hl.dsp.window.move({ x = 1336, y = -42,' "$fixture/calls" || {
  printf 'FAIL: hide animation used geometry from before the monitor move\n' >&2
  exit 1
}
printf 'Dropterminal fixture: ok\n'

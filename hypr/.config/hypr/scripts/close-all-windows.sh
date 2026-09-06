#!/usr/bin/env bash
set -euo pipefail

hyprctl_command=${HYPRCTL:-hyprctl}
dry_run=0

case ${1:-} in
  '') ;;
  --dry-run) dry_run=1 ;;
  *) printf 'usage: %s [--dry-run]\n' "${0##*/}" >&2; exit 2 ;;
esac

clients=$($hyprctl_command clients -j)
jq -e 'type == "array" and all(.[]; (.address | type) == "string")' \
  <<<"$clients" >/dev/null
mapfile -t addresses < <(jq -r '.[].address' <<<"$clients")

close_expression() {
  local address=$1
  address=${address//\\/\\\\}
  address=${address//\"/\\\"}
  printf 'hl.dispatch(hl.dsp.window.close({ window = "address:%s" }))' "$address"
}

failed=0
for address in "${addresses[@]}"; do
  expression=$(close_expression "$address")
  if ((dry_run)); then
    printf '+ %q eval %q\n' "$hyprctl_command" "$expression"
  elif ! "$hyprctl_command" eval "$expression"; then
    # A window can disappear after the client snapshot. Keep closing the rest.
    failed=1
  fi
done

exit "$failed"

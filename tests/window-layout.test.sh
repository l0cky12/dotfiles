#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/hypr/.config/hypr/scripts/window-layout.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_dry() {
  HYPR_LAYOUT=$1 "$script" --dry-run "$2"
}

[[ $(run_dry dwindle cycle) == *$'next=master\nnotification=Window layout: Master'* ]] ||
  fail 'cycle must move Dwindle to Master and announce it'
[[ $(run_dry master cycle) == *$'next=scrolling\nnotification=Window layout: Scrolling'* ]] ||
  fail 'cycle must move Master to Scrolling and announce it'
[[ $(run_dry scrolling cycle) == *$'next=monocle\nnotification=Window layout: Monocle'* ]] ||
  fail 'cycle must move Scrolling to Monocle and announce it'
[[ $(run_dry monocle cycle) == *$'next=dwindle\nnotification=Window layout: Dwindle'* ]] ||
  fail 'cycle must return Monocle to Dwindle and announce it'
[[ $(run_dry dwindle split-horizontal) == *'layoutmsg=preselect r'* ]] ||
  fail 'horizontal split must preselect right in Dwindle'
[[ $(run_dry dwindle split-vertical) == *'layoutmsg=preselect d'* ]] ||
  fail 'vertical split must preselect down in Dwindle'
[[ $(run_dry master split-horizontal) == *$'result=unavailable\nnotification=Window layout: Master'* ]] ||
  fail 'split outside Dwindle must report the active layout'
grep -Fq 'org.freedesktop.Notifications.Notify' "$script" ||
  fail 'notification fallback must call the D-Bus notification service'

printf 'ok: layout cycling, Dwindle splits, and non-Dwindle notifications\n'

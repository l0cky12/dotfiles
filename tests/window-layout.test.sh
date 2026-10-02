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

# The live path must use the Lua dispatcher: hyprland.lua rejects the legacy
# `dispatch layoutmsg preselect r` string as a Lua syntax error.
stub_root=$(mktemp -d -t window-layout-test.XXXXXX)
trap 'rm -rf -- "$stub_root"' EXIT
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/calls"\n' "$stub_root" >"$stub_root/hyprctl"
chmod +x "$stub_root/hyprctl"
HYPR_LAYOUT=dwindle HYPRCTL="$stub_root/hyprctl" NOTIFY_SEND=true "$script" split-horizontal
[[ $(<"$stub_root/calls") == "dispatch hl.dsp.layout('preselect r')" ]] ||
  fail 'split-horizontal must dispatch hl.dsp.layout preselect through Lua'

printf 'ok: layout cycling, Dwindle splits, and non-Dwindle notifications\n'

#!/usr/bin/env bash
# Clipboard store filter, invoked by the wl-paste watchers in autostart.lua:
#
#   wl-paste --type text  --watch .../clipboard-store.sh
#   wl-paste --type image --watch .../clipboard-store.sh
#
# The clipboard content arrives on stdin and is passed straight through to
# `cliphist store` unless it should be skipped. This replaces `cliphist store`
# as the handler -- the watcher count is unchanged, and only this short-lived
# filter runs per clipboard change.

set -uo pipefail

# ---------------------------------------------------------------------------
# Case-insensitive fragments matched against the active window's class,
# initialClass, title, and initialTitle. The extension IDs cover Chromium and
# Firefox integrations for Bitwarden, KeePassXC-Browser, and 1Password.
# ---------------------------------------------------------------------------
SENSITIVE_APP_PATTERNS=(
  bitwarden
  keepassxc
  1password
  com.bitwarden.desktop
  org.keepassxc.keepassxc
  com.1password.1password
  nngceckbapebfimnlniiiahkandclblb
  oboonakemofpalcgghocfoadofidjkkk
  aeblfdkhhhdcdjpifhhbdiojplfjncoa
  446900e4-71c2-419f-a6a7-df9c091e268b
  keepassxc-browser@keepassxc.org
  d634138d-c276-4fc8-924b-40a0ea21d284
)

# cliphist has no application-exclusion rules, so all policy lives here. Refuse
# to store if either metadata query fails: retaining nothing is safer than
# silently bypassing the filter.
types=$(wl-paste --list-types 2>/dev/null) || exit 0
if grep -qiE '(^|/)(x-kde-passwordmanagerhint|x-(bitwarden|keepassxc|1password))$' <<<"$types"; then
  exit 0
fi

win=$(hyprctl -j activewindow 2>/dev/null) || exit 0
identity=$(jq -er '
  [.class, .initialClass, .title, .initialTitle] | map(. // "") |
  if any(.[]; length > 0) then join("\n") else error("missing window identity") end
' <<<"$win" 2>/dev/null) || exit 0
identity=${identity,,}
for pattern in "${SENSITIVE_APP_PATTERNS[@]}"; do
  [[ $identity == *"$pattern"* ]] && exit 0
done

exec cliphist store

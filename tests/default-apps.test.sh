#!/usr/bin/env bash
# default-apps offers only installed choices and rewrites each default in place.
# Everything runs against a fixture XDG tree and PATH; the real system is untouched.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/menu/.config/lmenu/default-apps"
parser="$repo_root/menu/.config/lmenu/lmenu-parse.py"
python=$(command -v python3)
test_root=$(mktemp -d -t default-apps-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

bin="$test_root/bin"
apps="$test_root/share/applications"
config="$test_root/config"
repo="$test_root/repo"
mkdir -p "$bin" "$apps" "$config/ai-agent" "$repo"

for program in brave firefox kitty thunar yazi nvim code-oss teamclaude codex; do
  printf '#!/bin/sh\n' >"$bin/$program"
  chmod +x "$bin/$program"
done
# One program under two names must be offered once.
ln -s code-oss "$bin/code"
# lmenu-parse.py runs the helper through its #!/usr/bin/env python3 line.
ln -s "$python" "$bin/python3"
# Records reloads instead of touching a compositor.
printf '#!/bin/sh\necho "$*" >>"%s/hyprctl.log"\n' "$test_root" >"$bin/hyprctl"
chmod +x "$bin/hyprctl"

desktop() {
  local name=$1
  shift
  { printf '[Desktop Entry]\nType=Application\n'; printf '%s\n' "$@"; } >"$apps/$name"
}
desktop brave-browser.desktop Name=Brave Exec='brave %U' 'Categories=Network;WebBrowser;' \
  'MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;'
desktop firefox.desktop Name=Firefox Exec='env MOZ_ENABLE_WAYLAND=1 firefox %u' \
  'Categories=Network;WebBrowser;' 'MimeType=x-scheme-handler/https;'
# A browser category without the https handler is not a web browser.
desktop javaws.desktop Name=OpenWebStart Exec='javaws %u' 'Categories=Network;WebBrowser;' \
  'MimeType=application/x-java-jnlp-file;'
# Left behind by an uninstalled package.
desktop helium.desktop Name=Helium Exec='helium-browser %U' 'Categories=Network;WebBrowser;' \
  'MimeType=x-scheme-handler/https;'
desktop kitty.desktop Name=kitty Exec=kitty 'Categories=System;TerminalEmulator;'
desktop kitty-open.desktop 'Name=kitty URL Launcher' Exec='kitty +open %U' NoDisplay=true \
  'Categories=System;TerminalEmulator;'
desktop thunar.desktop Name=Thunar Exec='thunar %U' 'Categories=System;FileManager;' \
  'MimeType=inode/directory;'
desktop yazi.desktop Name=Yazi Exec='yazi %u' Terminal=true 'Categories=System;FileManager;'
desktop org.gnome.Nautilus.desktop Name=Files Exec='nautilus --new-window %U' \
  'Categories=GNOME;FileManager;'

# mimeapps.list and the agent config are Stow symlinks into the repository.
cat >"$repo/mimeapps.list" <<'EOF'
[Default Applications]
text/html=helium.desktop
x-scheme-handler/https=helium.desktop
x-scheme-handler/https=stale.desktop

# --- File manager ---
inode/directory=org.gnome.Nautilus.desktop

[Added Associations]
text/html=brave-browser.desktop;
EOF
ln -s "$repo/mimeapps.list" "$config/mimeapps.list"
printf '# Supported values: claude, codex, opencode, t3code\ndefault_agent=t3code\n' \
  >"$repo/ai-config"
ln -s "$repo/ai-config" "$config/ai-agent/config"

run() {
  env -i HOME="$test_root" PATH="$bin" XDG_CONFIG_HOME="$config" \
    XDG_DATA_HOME="$test_root/share" XDG_DATA_DIRS="$test_root/none" \
    XDG_CURRENT_DESKTOP=Hyprland HYPRLAND_INSTANCE_SIGNATURE=fixture \
    DEFAULT_APPS_NO_NOTIFY=1 "$@"
}
helper() {
  run "$python" "$helper" "$@"
}

# Listing: installed, visible, runnable entries only, with the current ticked.
[[ $(helper list browser) == $'brave-browser.desktop\tBrave\t0\nfirefox.desktop\tFirefox\t0' ]] ||
  fail "browser list is wrong: $(helper list browser)"
[[ $(helper list terminal) == $'kitty.desktop\tkitty\t0' ]] ||
  fail 'terminal list should hold kitty alone'
[[ $(helper list file-manager) == $'thunar.desktop\tThunar\t0' ]] ||
  fail 'file-manager list should skip uninstalled and Terminal=true entries'
[[ $(helper list editor) == $'nvim\tNeovim\t0\ncode\tVisual Studio Code\t0' ]] ||
  fail "editor list is wrong: $(helper list editor)"
[[ $(helper list agent) == $'claude\tClaude Code\t0\ncodex\tCodex\t0' ]] ||
  fail 'agent list should offer only agents on PATH'

# A dry run writes nothing.
before=$(sha256sum "$repo/mimeapps.list" "$repo/ai-config")
out=$(run DEFAULT_APPS_DRY_RUN=1 "$python" "$helper" set browser firefox.desktop)
grep -Fq "would write $repo/mimeapps.list" <<<"$out" || fail 'dry run did not name the resolved target'
grep -Fxq 'x-scheme-handler/https=firefox.desktop' <<<"$out" || fail 'dry run did not show the change'
run DEFAULT_APPS_DRY_RUN=1 "$python" "$helper" set agent codex >/dev/null
run DEFAULT_APPS_DRY_RUN=1 "$python" "$helper" set editor nvim >/dev/null
[[ $(sha256sum "$repo/mimeapps.list" "$repo/ai-config") == "$before" ]] || fail 'dry run changed a file'
[[ ! -e $config/default-apps ]] || fail 'dry run created the editor file'
grep -Fxq 'dry-run: would run hyprctl reload' <<<"$out" || fail 'dry run did not report the reload'
[[ ! -e $test_root/hyprctl.log ]] || fail 'dry run reloaded Hyprland'

# Something not installed is refused.
if helper set browser helium.desktop 2>"$test_root/err"; then
  fail 'an uninstalled browser was accepted'
fi
grep -Fq 'not an installed browser' "$test_root/err" || fail 'refusal did not explain itself'
[[ ! -e $test_root/hyprctl.log ]] || fail 'a refused change reloaded Hyprland'

# Browser: every handler in [Default Applications], duplicates folded, the rest kept.
helper set browser firefox.desktop
[[ -L $config/mimeapps.list ]] || fail 'the mimeapps.list symlink was replaced'
cat >"$test_root/expected" <<'EOF'
[Default Applications]
text/html=firefox.desktop
x-scheme-handler/https=firefox.desktop
x-scheme-handler/http=firefox.desktop
x-scheme-handler/about=firefox.desktop
x-scheme-handler/unknown=firefox.desktop

# --- File manager ---
inode/directory=org.gnome.Nautilus.desktop

[Added Associations]
text/html=brave-browser.desktop;
EOF
diff -u "$test_root/expected" "$repo/mimeapps.list" || fail 'browser rewrite of mimeapps.list is wrong'
helper list browser | grep -Fxq $'firefox.desktop\tFirefox\t1' || fail 'firefox is not ticked'
[[ $(<"$test_root/hyprctl.log") == reload ]] || fail 'a change did not reload Hyprland once'
run DEFAULT_APPS_NO_RELOAD=1 "$python" "$helper" set browser firefox.desktop
[[ $(wc -l <"$test_root/hyprctl.log") == 1 ]] || fail 'DEFAULT_APPS_NO_RELOAD still reloaded'

# File manager replaces inode/directory in place.
helper set file-manager thunar.desktop
grep -Fxq 'inode/directory=thunar.desktop' "$repo/mimeapps.list" || fail 'inode/directory not set'
grep -Fq 'Nautilus' "$repo/mimeapps.list" && fail 'the old file manager is still listed'
grep -Fxq '# --- File manager ---' "$repo/mimeapps.list" || fail 'a comment was lost'

# SUPER+E launches the folder handler variables.lua reads from mimeapps.list.
file_manager() {
  XDG_CONFIG_HOME=$1 lua -e "package.path = '$repo_root/hypr/.config/hypr/?.lua'
    io.write(require('conf/variables').file_manager)"
}
if command -v lua >/dev/null; then
  [[ $(file_manager "$config") == 'gtk-launch thunar' ]] ||
    fail "SUPER+E does not follow the file manager: $(file_manager "$config")"
  [[ $(file_manager "$test_root/none") == nautilus ]] ||
    fail 'SUPER+E has no fallback without mimeapps.list'
fi

# A missing mimeapps.list is created with the section.
rm "$config/mimeapps.list"
helper set file-manager thunar.desktop
[[ $(<"$config/mimeapps.list") == $'[Default Applications]\ninode/directory=thunar.desktop' ]] ||
  fail 'a new mimeapps.list is wrong'

# Terminal: the chosen entry goes first, the others stay as fallbacks, and a
# desktop-specific list wins over the generic one.
printf 'foot.desktop\nkitty.desktop\n' >"$config/xdg-terminals.list"
helper set terminal kitty.desktop
[[ $(<"$config/xdg-terminals.list") == $'kitty.desktop\nfoot.desktop' ]] || fail 'terminal list order is wrong'
helper list terminal | grep -Fxq $'kitty.desktop\tkitty\t1' || fail 'kitty is not ticked'
printf 'foot.desktop\n' >"$config/hyprland-xdg-terminals.list"
helper list terminal | grep -Fxq $'kitty.desktop\tkitty\t0' ||
  fail 'the desktop-specific list was not read'
helper set terminal kitty.desktop
[[ $(<"$config/hyprland-xdg-terminals.list") == $'kitty.desktop\nfoot.desktop' ]] ||
  fail 'the desktop-specific list was not written'

# Editor: EDITOR and VISUAL, with the GUI wait flag, in a file zsh can source.
helper set editor code
[[ $(grep -c "^export \(EDITOR\|VISUAL\)='code --wait'$" "$config/default-apps/editor.zsh") == 2 ]] ||
  fail 'editor file does not set EDITOR and VISUAL'
[[ $(bash -c 'source "$1"; printf %s "$VISUAL"' _ "$config/default-apps/editor.zsh") == 'code --wait' ]] ||
  fail 'the editor file does not source cleanly'
helper list editor | grep -Fxq $'code\tVisual Studio Code\t1' || fail 'code is not ticked'

# Agent: one default_agent line, comments kept, symlink kept.
printf 'default_agent=codex\n' >>"$repo/ai-config"
helper set agent claude
[[ -L $config/ai-agent/config ]] || fail 'the agent config symlink was replaced'
[[ $(<"$repo/ai-config") == $'# Supported values: claude, codex, opencode, t3code\ndefault_agent=claude' ]] ||
  fail "agent config is wrong: $(<"$repo/ai-config")"

# Web apps: offered once webapp-launch is installed, as webapp:<id>, sorted by
# name. Metadata that does not parse, lacks a name, or whose id is not a slug
# matching its file name is skipped.
webapps="$test_root/share/webapps/apps"
mkdir -p "$webapps"
printf 'id = "chatgpt"\nname = "ChatGPT"\nurl = "https://chatgpt.com/"\n' >"$webapps/chatgpt.toml"
printf 'id = "claude-ai"\nname = "Claude"\nurl = "https://claude.ai/"\n' >"$webapps/claude-ai.toml"
printf 'id = "other"\nname = "Mismatch"\n' >"$webapps/mismatch.toml"
printf 'id = "Bad_Id"\nname = "Bad"\n' >"$webapps/Bad_Id.toml"
printf 'id = "noname"\n' >"$webapps/noname.toml"
printf 'not toml [\n' >"$webapps/broken.toml"
[[ $(helper list agent) == $'claude\tClaude Code\t1\ncodex\tCodex\t0' ]] ||
  fail 'web apps were offered without webapp-launch on PATH'
printf '#!/bin/sh\n' >"$bin/webapp-launch"
chmod +x "$bin/webapp-launch"
[[ $(helper list agent) == $'claude\tClaude Code\t1\ncodex\tCodex\t0\nwebapp:chatgpt\tChatGPT (web app)\t0\nwebapp:claude-ai\tClaude (web app)\t0' ]] ||
  fail "agent list with web apps is wrong: $(helper list agent)"
helper set agent webapp:chatgpt
grep -Fxq 'default_agent=webapp:chatgpt' "$repo/ai-config" || fail 'web app agent was not written'
[[ $(grep -c '^default_agent=' "$repo/ai-config") == 1 ]] || fail 'web app agent duplicated default_agent'
helper list agent | grep -Fxq $'webapp:chatgpt\tChatGPT (web app)\t1' || fail 'web app agent is not ticked'
for refused in webapp:other webapp:missing 'webapp:../x'; do
  if helper set agent "$refused" 2>/dev/null; then
    fail "an uninstalled web app agent was accepted: $refused"
  fi
done
grep -Fxq 'default_agent=webapp:chatgpt' "$repo/ai-config" || fail 'a refused web app changed the config'
helper set agent claude

# The lmenu providers render the helper's rows, tick the current one, and
# resolve a row to a quoted `set` command.
cat >"$test_root/menu.jsonc" <<'JSON'
[ { "id": "d", "label": "Defaults" },
  { "id": "d.agent", "label": "Coding agent", "provider": "default-agent" } ]
JSON
rows=$(run LMENU_MENU="$test_root/menu.jsonc" LMENU_EXTENSIONS=/nonexistent \
  "$python" "$parser" rows d.agent)
grep -Pq '\tClaude Code\t✓\td\.agent#claude\t' <<<"$rows" || fail 'the provider did not tick the current agent'
grep -Pq '\tCodex\t\td\.agent#codex\t' <<<"$rows" || fail 'the provider did not list codex'
[[ $(run LMENU_MENU="$test_root/menu.jsonc" LMENU_EXTENSIONS=/nonexistent \
  "$python" "$parser" resolve d.agent 'd.agent#codex') == "leaf	$helper set agent codex" ]] ||
  fail 'the provider row does not resolve to the helper'
grep -Pq '\tChatGPT \(web app\)\t\td\.agent#webapp:chatgpt\t' <<<"$rows" ||
  fail 'the provider did not list the web app agent'
[[ $(run LMENU_MENU="$test_root/menu.jsonc" LMENU_EXTENSIONS=/nonexistent \
  "$python" "$parser" resolve d.agent 'd.agent#webapp:chatgpt') == "leaf	$helper set agent webapp:chatgpt" ]] ||
  fail 'the web app agent row does not resolve to the helper'

# Desktop-specific defaults must agree with the menu and web-app launcher.
printf '[Default Applications]\nx-scheme-handler/https=firefox.desktop\n' >"$config/hyprland-mimeapps.list"
helper list browser | grep -Fxq $'firefox.desktop\tFirefox\t1' || fail 'desktop-specific default was not read'
helper set browser brave-browser.desktop
grep -Fxq 'x-scheme-handler/https=brave-browser.desktop' "$config/hyprland-mimeapps.list" ||
  fail 'desktop-specific default overrides the selected browser'
run "$python" - "$repo_root/hypr/.config/hypr/webapp" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import weblib
assert weblib.default_browser()[0] == "brave-browser.desktop"
PY
printf 'inode/directory=stale.desktop\n' >>"$config/hyprland-mimeapps.list"
helper set file-manager thunar.desktop
if command -v lua >/dev/null; then
  [[ $(XDG_CURRENT_DESKTOP=Hyprland file_manager "$config") == 'gtk-launch thunar' ]] ||
    fail 'SUPER+E ignored the selected desktop-specific file manager'
fi

# Evaluate only the editor source line, avoiding the rest of the live shell setup.
editor_source=$(grep 'source .*default-apps/editor.zsh' "$repo_root/zsh/.zshrc")
[[ $(run "$(command -v zsh)" -fc "$editor_source; print -r -- \"\$VISUAL\"") == 'code --wait' ]] ||
  fail 'zsh ignores the editor selected under XDG_CONFIG_HOME'

printf 'ok: default-apps\n'

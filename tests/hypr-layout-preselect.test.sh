#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
hypr_root="$repo_root/hypr/.config/hypr"
legacy_config="$hypr_root/hyprland.conf"
legacy_binds="$hypr_root/conf/keybinding.conf"
lua_config="$hypr_root/hyprland.lua"
lua_binds="$hypr_root/conf/keybindings.lua"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Parse the legacy general block instead of accepting an unrelated or commented
# `layout = dwindle` line elsewhere in the file.
awk '
  function braces(text, open_count, close_count) {
    open_count = gsub(/\{/, "{", text)
    close_count = gsub(/\}/, "}", text)
    return open_count - close_count
  }
  {
    line = $0
    sub(/#.*/, "", line)
    if (!in_general && line ~ /^[[:space:]]*general[[:space:]]*\{/) {
      in_general = 1
      depth = braces(line)
      next
    }
    if (in_general) {
      if (line ~ /^[[:space:]]*layout[[:space:]]*=[[:space:]]*dwindle[[:space:]]*$/) {
        found++
      } else if (line ~ /^[[:space:]]*layout[[:space:]]*=/) {
        wrong++
      }
      depth += braces(line)
      if (depth == 0) {
        in_general = 0
      }
    }
  }
  END { exit !(found == 1 && wrong == 0 && !in_general) }
' "$legacy_config" || fail 'legacy general block must declare layout = dwindle exactly once'

legacy_right='bindd = $mainMod, J, split horizontally (next window opens to the right), layoutmsg, preselect r'
legacy_down='bindd = $mainMod SHIFT, V, split vertically (next window opens below), layoutmsg, preselect d'
test "$(grep -Fxc 'source = ~/.config/hypr/conf/keybinding.conf' "$legacy_config")" -eq 1 ||
  fail 'legacy root config must source the tested keybinding file exactly once'
test "$(grep -Fxc -- "$legacy_right" "$legacy_binds")" -eq 1 ||
  fail 'legacy SUPER+J must dispatch unquoted layoutmsg preselect r exactly once'
test "$(grep -Fxc -- "$legacy_down" "$legacy_binds")" -eq 1 ||
  fail 'legacy SUPER+SHIFT+V must dispatch unquoted layoutmsg preselect d exactly once'

# Hyprland 0.55+ starts from Lua in this repository, so enforce the same
# declared-layout contract for the active graph as for the legacy graph.
awk '
  function braces(text, open_count, close_count) {
    open_count = gsub(/\{/, "{", text)
    close_count = gsub(/\}/, "}", text)
    return open_count - close_count
  }
  {
    line = $0
    sub(/--.*/, "", line)
    if (!in_general && line ~ /^[[:space:]]*general[[:space:]]*=[[:space:]]*\{/) {
      in_general = 1
      depth = braces(line)
      next
    }
    if (in_general) {
      if (line ~ /^[[:space:]]*layout[[:space:]]*=[[:space:]]*"dwindle"[[:space:]]*,?[[:space:]]*$/) {
        found++
      } else if (line ~ /^[[:space:]]*layout[[:space:]]*=/) {
        wrong++
      }
      depth += braces(line)
      if (depth == 0) {
        in_general = 0
      }
    }
  }
  END { exit !(found == 1 && wrong == 0 && !in_general) }
' "$lua_config" || fail 'Lua general config must declare layout = "dwindle" exactly once'

lua_right='bind(mod .. " + J", "split horizontally (next window opens to the right)", hl.dsp.layout("preselect r"))'
lua_down='bind(mod .. " + SHIFT + V", "split vertically (next window opens below)", hl.dsp.layout("preselect d"))'
test "$(grep -Fxc 'require("conf/keybindings")' "$lua_config")" -eq 1 ||
  fail 'Lua root config must require the tested keybindings module exactly once'
test "$(grep -Fxc -- "$lua_right" "$lua_binds")" -eq 1 ||
  fail 'Lua SUPER+J must dispatch preselect r exactly once'
test "$(grep -Fxc -- "$lua_down" "$lua_binds")" -eq 1 ||
  fail 'Lua SUPER+SHIFT+V must dispatch preselect d exactly once'

printf 'ok: dwindle layout and one-shot preselect bindings are explicit\n'

#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
hypr_root="$repo_root/hypr/.config/hypr"
test_root=$(mktemp -d -t hyprland-lua-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for cmd_name in luac lua Hyprland; do
  command -v "$cmd_name" >/dev/null 2>&1 || {
    printf 'skip: %s is not installed\n' "$cmd_name"
    exit 0
  }
done

while IFS= read -r -d '' file; do
  luac -p "$file"
done < <(find "$hypr_root" -type f -name '*.lua' -not -path '*/themes/.active/*' -print0)

lua - "$hypr_root" <<'LUA'
local hypr_root = assert(arg[1])
local captures = {}

local function stub()
    return setmetatable({}, {
        __index = function(self, key)
            local value = stub()
            rawset(self, key, value)
            return value
        end,
        __call = function()
            return { kind = "stub" }
        end,
    })
end

hl = stub()
hl.bind = function(keys, dispatcher, flags)
    table.insert(captures, {
        keys = keys,
        dispatcher = dispatcher,
        description = flags and flags.description or nil,
    })
end
hl.dsp.window.move = function(args)
    return { kind = "window.move", args = args }
end
hl.dsp.window.float = function(args)
    return { kind = "window.float", args = args }
end
hl.dsp.layout = function(action)
    return { kind = "layout", action = action }
end
hl.dsp.focus = function(args)
    return { kind = "focus", args = args }
end
hl.dsp.exec_cmd = function(command)
    return { kind = "exec_cmd", command = command }
end
local dispatched
hl.dispatch = function(dispatcher)
    dispatched = dispatcher
end

package.path = hypr_root .. "/?.lua;" .. package.path
dofile(hypr_root .. "/conf/keybindings.lua")

local number_keys = {
    "code:10", "code:11", "code:12", "code:13", "code:14",
    "code:15", "code:16", "code:17", "code:18", "code:19",
}
local function expect(keys, description, kind, workspace, follow)
    for _, capture in ipairs(captures) do
        local dispatcher = capture.dispatcher
        if type(dispatcher) == "function" then
            dispatched = nil
            dispatcher()
            dispatcher = dispatched
        end
        if capture.keys == keys and capture.description == description and
                dispatcher.kind == kind and dispatcher.args.workspace == workspace and
                dispatcher.args.follow == follow then
            return
        end
    end
    error("missing binding: " .. keys .. " -> " .. description)
end

local function expect_move(keys, description, workspace, follow)
    local expected = string.format(
        [[hyprctl eval 'hl.dispatch(hl.dsp.window.move({ workspace = %d, follow = %s }))']],
        workspace, follow and "true" or "false")
    for _, capture in ipairs(captures) do
        if capture.keys == keys and capture.description == description and
                capture.dispatcher.kind == "exec_cmd" and capture.dispatcher.command == expected then
            return
        end
    end
    error("missing move binding: " .. keys .. " -> " .. description)
end

local function expect_exec(keys, description, command)
    for _, capture in ipairs(captures) do
        if capture.keys == keys and capture.description == description and
                capture.dispatcher.kind == "exec_cmd" and capture.dispatcher.command == command then
            return
        end
    end
    error("missing exec binding: " .. keys .. " -> " .. description)
end

expect_exec("SUPER + CTRL + Escape", "start ASCII screensaver",
    "/home/liam/.config/hypr/scripts/run-if-deployed.sh screensaver ascii-screensaver force")
expect_exec("SUPER + CTRL + SHIFT + Escape", "toggle automatic ASCII screensaver",
    "/home/liam/.config/hypr/scripts/run-if-deployed.sh screensaver toggle-screensaver")
expect_exec("CTRL + ALT + Delete", "close all windows",
    "/home/liam/.config/hypr/scripts/close-all-windows.sh")
expect_exec("SUPER + A", "application launcher",
    "/home/liam/.config/hypr/scripts/quick-search.sh drun")
expect_exec("SUPER + SHIFT + A", "lmenu root", "$HOME/.local/bin/lmenu toggle")
expect_exec("SUPER + ALT + A", "web app manager",
    "quickshell ipc call webapps toggle")
expect_exec("SUPER + CTRL + T", "activity (btop, floating)",
    "/home/liam/.config/hypr/scripts/btop-float.sh")
expect_exec("SUPER + CTRL + SHIFT + G", "play temporary dotfiles history",
    "/home/liam/.config/hypr/scripts/gource-dotfiles.sh")
expect_exec("SUPER + SHIFT + Backspace", "toggle window gaps on all workspaces",
    "/home/liam/.config/hypr/scripts/toggle-gaps.sh")
expect_exec("SUPER + Backspace", "toggle window transparency on all workspaces",
    "/home/liam/.config/hypr/scripts/toggle-transparency.sh")
expect_exec("SUPER + CTRL + O", "toggle menu (night light, DND, stay awake, etc)",
    "/home/liam/.config/hypr/scripts/toggles-menu.sh")
expect_exec("SUPER + SHIFT + L", "cycle window layout",
    "/home/liam/.config/hypr/scripts/window-layout.sh cycle")

-- Tiling direction. `preselect` is a one-time override for the next window,
-- unlike `togglesplit`, which needs dwindle.preserve_split to do anything.
local function expect_layout(keys, description, action)
    for _, capture in ipairs(captures) do
        if capture.keys == keys and capture.description == description and
                capture.dispatcher.kind == "layout" and capture.dispatcher.action == action then
            return
        end
    end
    error("missing layout binding: " .. keys .. " -> " .. action)
end

expect_exec("SUPER + J", "split horizontally (next window opens to the right)",
    "/home/liam/.config/hypr/scripts/window-layout.sh split-horizontal")
expect_exec("SUPER + SHIFT + V", "split vertically (next window opens below)",
    "/home/liam/.config/hypr/scripts/window-layout.sh split-vertical")

local floating_toggle_found = false
for _, capture in ipairs(captures) do
    if capture.keys == "SUPER + T" and capture.description == "toggle window floating / tiling" and
            capture.dispatcher.kind == "window.float" and capture.dispatcher.args.action == "toggle" then
        floating_toggle_found = true
        break
    end
end
assert(floating_toggle_found, "missing native Lua floating toggle binding")

for workspace = 1, 10 do
    expect_move("SUPER + SHIFT + " .. number_keys[workspace], "move to workspace " .. workspace,
        workspace, true)
    expect_move("SUPER + CTRL + " .. number_keys[workspace], "move silently to workspace " .. workspace,
        workspace, false)
    expect("SUPER + " .. number_keys[workspace], "workspace " .. workspace,
        "focus", workspace, nil)
end
-- Workspaces 11-15 are reached by adding ALT to the same number keys, which
-- is how focus already reaches that bank. Plain "1".."5", not code:N.
for workspace = 11, 15 do
    expect("SUPER + ALT + " .. (workspace - 10), "workspace " .. workspace,
        "focus", workspace, nil)
    expect_move("SUPER + SHIFT + ALT + " .. (workspace - 10),
        "move to workspace " .. workspace, workspace, true)
    expect_move("SUPER + CTRL + ALT + " .. (workspace - 10),
        "move silently to workspace " .. workspace, workspace, false)
end
LUA

grep -Fqx 'bindd = $mainMod CTRL, Escape, start ASCII screensaver, exec, $scriptsDir/run-if-deployed.sh screensaver ascii-screensaver force' \
  "$hypr_root/conf/keybinding.conf" ||
  fail 'legacy screensaver binding does not use the screensaver package'

grep -Fqx 'bindd = $mainMod CTRL SHIFT, G, play temporary dotfiles history, exec, $scriptsDir/gource-dotfiles.sh' \
  "$hypr_root/conf/keybinding.conf" ||
  fail 'legacy Gource binding is missing or changed'

grep -Fqx 'bindd = $mainMod SHIFT, L, cycle window layout, exec, $scriptsDir/window-layout.sh cycle' \
  "$hypr_root/conf/keybinding.conf" ||
  fail 'legacy window-layout cycle binding is missing or changed'

grep -Fqx 'hl.window_rule({ match = { class = "^t3code$" }, workspace = "4 silent" })' \
  "$hypr_root/conf/window_rules.lua" ||
  fail 'Lua config does not assign T3 Code to workspace 4'
grep -Fqx 'windowrule = match:class ^t3code$, workspace 4 silent' \
  "$hypr_root/conf/windows-rules.conf" ||
  fail 'legacy config does not assign T3 Code to workspace 4'

mkdir -p "$test_root/config" "$test_root/home" "$test_root/runtime"
cp -a "$hypr_root/." "$test_root/config/hypr/"
rm -f "$test_root/config/hypr/hyprland.conf" \
  "$test_root/config/hypr/workspaces.conf"
XDG_RUNTIME_DIR="$test_root/runtime" \
  python3 "$hypr_root/theme/generate.py" set everforest \
    --prefix "$test_root/config" --no-reload >/dev/null
luac -p "$test_root/config/hypr/conf/decorations.lua"
HOME="$test_root/home" \
XDG_CONFIG_HOME="$test_root/config" \
XDG_RUNTIME_DIR="$test_root/runtime" \
  Hyprland --verify-config --config "$test_root/config/hypr/hyprland.lua" \
  >"$test_root/verify.log" 2>&1 || {
    sed -n '1,240p' "$test_root/verify.log" >&2
    fail 'Hyprland rejected the Lua config'
  }
grep -Fq 'config ok' "$test_root/verify.log" || fail 'config verification did not report success'
[[ ! -e "$test_root/config/hypr/hyprland.conf" ]] ||
  fail 'config verification regenerated hyprland.conf'

fixture_hypr="$test_root/profile-hypr"
mkdir -p "$fixture_hypr/monitor_profiles" "$test_root/bin" "$test_root/profile-runtime"
# The applier consults the ACPI lid state (lid closed forces the internal
# panel off); pin it to "open" so the host's real lid does not leak in.
export HYPR_LID_STATE="$test_root/no-such-lid-state"
cp "$hypr_root/monitor_profiles/"*.lua "$fixture_hypr/monitor_profiles/"
cp "$hypr_root/hyprland.lua" "$fixture_hypr/hyprland.lua"

cat >"$test_root/bin/hyprctl-fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HYPRCTL_CALLS"
case "$*" in
  '-j monitors')
    printf '%s\n' '[{"name":"DP-4","description":"","width":1280,"height":1024,"refreshRate":75.03,"x":0,"y":0,"scale":1.0,"transform":1},{"name":"HDMI-A-3","description":"","width":2560,"height":1080,"refreshRate":60.0,"x":1024,"y":0,"scale":1.0,"transform":0}]'
    ;;
  '-j workspacerules')
    printf '%s\n' '[{"workspaceString":"1","enabled":true,"monitor":"HDMI-A-3"},{"workspaceString":"6","enabled":true,"monitor":"DP-4"}]'
    ;;
  '-j workspaces')
    printf '%s\n' '[{"id":1,"monitor":"DP-4"},{"id":6,"monitor":"HDMI-A-3"}]'
    ;;
esac
SH
chmod +x "$test_root/bin/hyprctl-fixture"

export HYPRCTL_CALLS="$test_root/hyprctl.calls"
HYPR_DIR="$fixture_hypr" \
HYPRCTL="$test_root/bin/hyprctl-fixture" \
XDG_RUNTIME_DIR="$test_root/profile-runtime" \
HYPR_SKIP_SETTLE=1 \
  "$hypr_root/scripts/auto-monitor-profile.sh" --force

cmp "$fixture_hypr/monitors.lua" "$fixture_hypr/monitor_profiles/desktop.monitors.lua" ||
  fail 'desktop monitor profile was not copied to the Lua active file'
cmp "$fixture_hypr/workspaces.lua" "$fixture_hypr/monitor_profiles/desktop.workspaces.lua" ||
  fail 'desktop workspace profile was not copied to the Lua active file'
grep -Fq 'dispatch hl.dsp.workspace.move({ workspace = 1, monitor = "HDMI-A-3" })' "$HYPRCTL_CALLS" ||
  fail 'workspace migration did not use the Lua dispatcher'
grep -Fq 'dispatch hl.dsp.focus({ monitor = "HDMI-A-3" })' "$HYPRCTL_CALLS" ||
  fail 'desktop focus did not use the Lua dispatcher'

rm "$fixture_hypr/hyprland.lua"
: >"$HYPRCTL_CALLS"
if HYPR_DIR="$fixture_hypr" \
  HYPRCTL="$test_root/bin/hyprctl-fixture" \
  XDG_RUNTIME_DIR="$test_root/profile-runtime" \
  HYPR_SKIP_SETTLE=1 \
  "$hypr_root/scripts/auto-monitor-profile.sh" --force --verbose >"$test_root/missing-entrypoint.out" 2>&1; then
  fail 'monitor profile applied without its active Lua entrypoint'
fi
grep -Fq "missing active Lua config: $fixture_hypr/hyprland.lua" "$test_root/missing-entrypoint.out" ||
  fail 'missing Lua entrypoint was not reported'
! grep -Fq 'reload' "$HYPRCTL_CALLS" ||
  fail 'missing Lua entrypoint still triggered a Hyprland reload'
cp "$hypr_root/hyprland.lua" "$fixture_hypr/hyprland.lua"

HYPR_DIR="$fixture_hypr" "$hypr_root/scripts/set-monitor-scale.sh" HDMI-A-3 1.25 >/dev/null
for file in "$fixture_hypr/monitors.lua" "$fixture_hypr/monitor_profiles/desktop.monitors.lua"; do
  awk '
    /output = "HDMI-A-3"/ { target = 1 }
    target && /scale = 1.25/ { found = 1 }
    target && /^})/ { exit found ? 0 : 1 }
    END { if (!target || !found) exit 1 }
  ' "$file" || fail "scale was not persisted in $file"
  luac -p "$file"
done

: >"$HYPRCTL_CALLS"
desktop_monitors="$("$test_root/bin/hyprctl-fixture" -j monitors)"
: >"$HYPRCTL_CALLS"
HYPR_DIR="$fixture_hypr" \
HYPRCTL="$test_root/bin/hyprctl-fixture" \
XDG_RUNTIME_DIR="$test_root/profile-runtime" \
HYPR_SKIP_SETTLE=1 \
SIMULATED_MONITORS="$desktop_monitors" \
  "$hypr_root/scripts/auto-monitor-profile.sh" --force --dry-run >"$test_root/dry-run.out"
grep -Fq 'profile=desktop' "$test_root/dry-run.out" || fail 'dry-run did not report the selected profile'
! grep -Fq 'reload' "$HYPRCTL_CALLS" || fail 'dry-run contacted a mutating Hyprland command'


# ── KVM connector renumbering ───────────────────────────────────────────────
# The KVM re-enumerates DisplayPort connectors on every switch: the same three
# panels have been DP-5/DP-7/DP-9 and are now DP-6/DP-10/DP-12. Selecting the
# profile by connector name silently fell through to `laptop`, which pins every
# workspace to a disabled eDP-1 and collapses them onto one screen. Detection
# must key on the EDID description and be indifferent to the names.
kvm_monitors_json() {
  local a="$1" b="$2" c="$3"
  printf '%s' "[{\"name\":\"$a\",\"description\":\"Dell Inc. DELL P2214H KW14V42L3ACB\",\"width\":1920,\"height\":1080,\"refreshRate\":60.0,\"x\":2256,\"y\":0,\"scale\":1.0,\"transform\":1},"
  printf '%s' "{\"name\":\"$b\",\"description\":\"Dell Inc. DELL P2722H CTCS1M3\",\"width\":1920,\"height\":1080,\"refreshRate\":60.0,\"x\":3336,\"y\":0,\"scale\":1.0,\"transform\":0},"
  printf '%s\n' "{\"name\":\"$c\",\"description\":\"Dell Inc. DELL P2725H 21MG834\",\"width\":1920,\"height\":1080,\"refreshRate\":60.0,\"x\":5256,\"y\":0,\"scale\":1.0,\"transform\":0}]"
}

for names in "DP-5 DP-7 DP-9" "DP-6 DP-10 DP-12" "DP-13 DP-21 DP-99"; do
  read -r n1 n2 n3 <<<"$names"
  cat >"$test_root/bin/hyprctl-kvm" <<SH
#!/usr/bin/env bash
case "\$*" in
  '-j monitors') printf '%s\n' '$(kvm_monitors_json "$n1" "$n2" "$n3")' ;;
  '-j workspaces') printf '%s\n' '[]' ;;
esac
SH
  chmod +x "$test_root/bin/hyprctl-kvm"

  HYPR_DIR="$fixture_hypr" \
  HYPRCTL="$test_root/bin/hyprctl-kvm" \
  XDG_RUNTIME_DIR="$test_root/profile-runtime" \
  HYPR_SKIP_SETTLE=1 \
  SIMULATED_MONITORS="$(kvm_monitors_json "$n1" "$n2" "$n3")" \
    "$hypr_root/scripts/auto-monitor-profile.sh" --dry-run >"$test_root/kvm.out" 2>&1

  grep -Fq 'profile=kvm' "$test_root/kvm.out" ||
    fail "connector names '$names' did not resolve to the kvm profile"
done

# Geometry drift must be detected even though every monitor is present: that is
# the "monitors are all there but arranged wrong" failure.
cat >"$test_root/bin/hyprctl-kvm-drift" <<'SH'
#!/usr/bin/env bash
case "$*" in
  '-j monitors')
    printf '%s
' '[{"name":"DP-6","description":"Dell Inc. DELL P2214H KW14V42L3ACB","width":1920,"height":1080,"refreshRate":60.0,"x":0,"y":0,"scale":1.0,"transform":0},{"name":"DP-10","description":"Dell Inc. DELL P2722H CTCS1M3","width":1920,"height":1080,"refreshRate":60.0,"x":3336,"y":0,"scale":1.0,"transform":0},{"name":"DP-12","description":"Dell Inc. DELL P2725H 21MG834","width":1920,"height":1080,"refreshRate":60.0,"x":5256,"y":0,"scale":1.0,"transform":0}]'
    ;;
  '-j workspaces') printf '%s
' '[]' ;;
esac
SH
chmod +x "$test_root/bin/hyprctl-kvm-drift"

HYPR_DIR="$fixture_hypr" \
HYPRCTL="$test_root/bin/hyprctl-kvm-drift" \
XDG_RUNTIME_DIR="$test_root/profile-runtime" \
HYPR_SKIP_SETTLE=1 \
SIMULATED_MONITORS="$("$test_root/bin/hyprctl-kvm-drift" -j monitors)" \
  "$hypr_root/scripts/auto-monitor-profile.sh" --dry-run >"$test_root/drift.out" 2>&1
grep -Fq 'result=would-apply' "$test_root/drift.out" ||
  fail 'rotated/misplaced monitor was not detected as drift'

# A partial set must NOT select kvm -- applying mid-hotplug is how workspaces
# ended up collapsed onto one screen.
cat >"$test_root/bin/hyprctl-kvm-partial" <<'SH'
#!/usr/bin/env bash
case "$*" in
  '-j monitors')
    printf '%s
' '[{"name":"DP-6","description":"Dell Inc. DELL P2722H CTCS1M3","width":1920,"height":1080,"refreshRate":60.0,"x":3336,"y":0,"scale":1.0,"transform":0}]'
    ;;
  '-j workspaces') printf '%s
' '[]' ;;
esac
SH
chmod +x "$test_root/bin/hyprctl-kvm-partial"

HYPR_DIR="$fixture_hypr" \
HYPRCTL="$test_root/bin/hyprctl-kvm-partial" \
XDG_RUNTIME_DIR="$test_root/profile-runtime" \
HYPR_SKIP_SETTLE=1 \
SIMULATED_MONITORS="$("$test_root/bin/hyprctl-kvm-partial" -j monitors)" \
  "$hypr_root/scripts/auto-monitor-profile.sh" --dry-run >"$test_root/partial.out" 2>&1
! grep -Fq 'profile=kvm' "$test_root/partial.out" ||
  fail 'an incomplete KVM monitor set selected the kvm profile'
grep -Fq 'result=no-action' "$test_root/partial.out" ||
  fail 'an incomplete KVM monitor set did not leave the layout alone'
! grep -Fq 'profile=laptop' "$test_root/partial.out" ||
  fail 'losing one monitor fell back to laptop and would collapse workspaces'

# ── Manual profile menu and safe dry-run matrix ─────────────────────────────
laptop_monitors='[{"name":"eDP-1","description":"","width":2256,"height":1504,"refreshRate":60.0,"x":0,"y":0,"scale":1.0,"transform":0}]'
laptop_external_monitors='[{"name":"eDP-1","description":"","width":2256,"height":1504,"refreshRate":60.0,"x":0,"y":0,"scale":1.0,"transform":0},{"name":"DP-4","description":"","width":1280,"height":1024,"refreshRate":75.03,"x":0,"y":0,"scale":1.0,"transform":1},{"name":"HDMI-A-3","description":"","width":2560,"height":1080,"refreshRate":60.0,"x":1024,"y":0,"scale":1.0,"transform":0}]'

HYPR_DIR="$fixture_hypr" SIMULATED_MONITORS="$laptop_monitors" \
  "$hypr_root/scripts/auto-monitor-profile.sh" --profile laptop --dry-run >"$test_root/laptop-only.out"
grep -Fq 'profile=laptop' "$test_root/laptop-only.out" || fail 'laptop-only dry-run chose the wrong profile'
grep -Fq 'result=already-correct' "$test_root/laptop-only.out" ||
  grep -Fq 'result=would-apply' "$test_root/laptop-only.out" || fail 'laptop-only dry-run produced no result'

HYPR_DIR="$fixture_hypr" SIMULATED_MONITORS="$laptop_external_monitors" \
  "$hypr_root/scripts/auto-monitor-profile.sh" --profile desktop --dry-run >"$test_root/laptop-external.out"
grep -Fq 'profile=desktop' "$test_root/laptop-external.out" || fail 'external dry-run chose the wrong profile'
grep -Fq '=== monitors.lua ===' "$test_root/laptop-external.out" || fail 'dry-run did not print monitor config'
grep -Fq '=== workspaces.lua ===' "$test_root/laptop-external.out" || fail 'dry-run did not print workspace config'

if HYPR_DIR="$fixture_hypr" SIMULATED_MONITORS="$laptop_monitors" \
  "$hypr_root/scripts/auto-monitor-profile.sh" --profile desktop --dry-run >"$test_root/absent-output.out" 2>&1; then
  fail 'profile with no connected enabled output was accepted'
fi
grep -Fq 'result=refused-no-connected-output' "$test_root/absent-output.out" ||
  fail 'absent-output dry-run did not explain its refusal'

for step in 'desktop laptop' 'laptop work' 'work presentation' 'presentation desktop' 'kvm desktop'; do
  read -r current expected <<<"$step"
  cp "$fixture_hypr/monitor_profiles/$current.monitors.lua" "$fixture_hypr/monitors.lua"
  cp "$fixture_hypr/monitor_profiles/$current.workspaces.lua" "$fixture_hypr/workspaces.lua"
  HYPR_DIR="$fixture_hypr" SIMULATED_MONITORS="$laptop_external_monitors" \
    "$hypr_root/scripts/monitor-profile-menu.sh" --next --dry-run >"$test_root/cycle-$current.out"
  grep -Fq "profile=$expected" "$test_root/cycle-$current.out" ||
    fail "cycle from $current did not choose $expected"
done

cat >"$test_root/bin/rofi" <<'SH'
#!/usr/bin/env bash
tee "$ROFI_MENU" >/dev/null
exit 1
SH
chmod +x "$test_root/bin/rofi"
cp "$fixture_hypr/monitor_profiles/kvm.monitors.lua" "$fixture_hypr/monitors.lua"
cp "$fixture_hypr/monitor_profiles/kvm.workspaces.lua" "$fixture_hypr/workspaces.lua"
ROFI_MENU="$test_root/profile-menu.out" PATH="$test_root/bin:$PATH" HYPR_DIR="$fixture_hypr" \
  "$hypr_root/scripts/monitor-profile-menu.sh"
for profile in desktop kvm laptop presentation work; do
  grep -Eq "^[●○] $profile$" "$test_root/profile-menu.out" || fail "menu did not glob profile $profile"
done
grep -Fqx '● kvm' "$test_root/profile-menu.out" || fail 'menu did not mark the active profile'

# The menu owns a piped fixture once, then passes the captured value to the
# applier. A second read from this pipe would be empty.
cp "$fixture_hypr/monitor_profiles/laptop.monitors.lua" "$fixture_hypr/monitors.lua"
cp "$fixture_hypr/monitor_profiles/laptop.workspaces.lua" "$fixture_hypr/workspaces.lua"
printf '%s\n' "$laptop_external_monitors" | HYPR_DIR="$fixture_hypr" \
  "$hypr_root/scripts/monitor-profile-menu.sh" --next --dry-run >"$test_root/piped-once.out"
grep -Fq 'profile=work' "$test_root/piped-once.out" || fail 'piped monitor fixture was not captured once'

luac -p "$fixture_hypr/monitor_profiles/kvm.monitors.lua" \
      "$fixture_hypr/monitor_profiles/kvm.workspaces.lua"

printf 'ok: Hyprland Lua config and monitor fixtures\n'

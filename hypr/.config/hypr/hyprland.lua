-- Hyprland 0.55+ Lua configuration entry point.
-- Keep component behavior in the modules below so generated state can be
-- replaced atomically without rewriting this file.

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- ponytail: legacy DRM avoids Aquamarine's hotplug crash; remove after the page-flip bug is fixed.
hl.env("AQ_NO_ATOMIC", "1")

local home = assert(os.getenv("HOME"), "HOME is required")
local state_home = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
local night_light_state = io.open(state_home .. "/hyprland-desktop/night-light-shader", "r")
local night_light_enabled = night_light_state ~= nil
if night_light_state then
    night_light_state:close()
end

-- greetd -> start-hyprland never sources ~/.zshrc, so the session PATH has no
-- ~/.local/bin and every Stow package's entry point lives there. hl.env runs
-- before the display server initialises, so this takes effect at next login,
-- not on `hyprctl reload`.
local path = os.getenv("PATH")
if path and not path:find(home .. "/.local/bin", 1, true) then
    hl.env("PATH", home .. "/.local/bin:" .. path)
end

hl.config({
    decoration = {
        screen_shader = night_light_enabled
            and (home .. "/.config/hypr/shaders/night-light.frag")
            or "",
    },
    cursor = {
        -- ponytail: software cursor avoids rotated-output glitches; retry hardware cursors after an upstream fix.
        no_hardware_cursors = 1,
    },
    misc = {
        -- A theme switch rewrites conf/decorations.lua, and autoreload answers
        -- every such write with a full config re-parse on the compositor's main
        -- thread -- roughly a second of frozen screen and swallowed input. The
        -- theme generator applies its own changes with `hyprctl eval` in a few
        -- milliseconds instead (see theme/generate.py reload_apps), so nothing
        -- needs the file watcher. Cost: hand-edits to these files now want an
        -- explicit `hyprctl reload`.
        disable_autoreload = true,
    },
    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = false,
        },
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

hl.device({
    name = "epic-mouse-v1",
    sensitivity = -0.5,
})

require("conf/keybindings")
require("conf/window_rules")
require("conf/autostart")
require("conf/decorations")
require("monitors")
require("workspaces")

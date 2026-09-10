local cfg = require("conf/variables")
local mod = "SUPER"

local function bind(keys, description, dispatcher, flags)
    flags = flags or {}
    flags.description = description
    hl.bind(keys, dispatcher, flags)
end

local function exec(keys, description, command, flags)
    bind(keys, description, hl.dsp.exec_cmd(command), flags)
end

-- Entry points owned by a separate Stow package. Routed through
-- run-if-deployed.sh so an undeployed package reports itself instead of making
-- the keybinding silently do nothing.
local function package_exec(keys, description, package, command, flags)
    exec(keys, description,
        cfg.scripts_dir .. "/run-if-deployed.sh " .. package .. " " .. command, flags)
end

-- Core desktop and helper commands.
exec(mod .. " + Return", "terminal", cfg.terminal)
exec(mod .. " + SHIFT + Return", "drop-down terminal", cfg.scripts_dir .. "/Dropterminal.sh kitty")
bind(mod .. " + Q", "close window", hl.dsp.window.close())
exec("CTRL + ALT + Delete", "close all windows", cfg.scripts_dir .. "/close-all-windows.sh")
exec(mod .. " + L", "lock screen", [[if test -x "$HOME/.local/bin/screensaver-lock"; then "$HOME/.local/bin/screensaver-lock"; else pidof hyprlock || hyprlock --config "$HOME/.config/hypr/hyprlock.conf"; fi]])
exec(mod .. " + P", "power menu", "bash " .. cfg.scripts_dir .. "/power-menu.sh")
exec(mod .. " + ALT + P", "monitor profiles", cfg.scripts_dir .. "/monitor-profile-menu.sh")
exec(mod .. " + ALT + E", "emoji menu", cfg.scripts_dir .. "/RofiEmoji.sh")
exec(mod .. " + K", "keybindings", "quickshell ipc call keybinds toggle")
exec(mod .. " + I", "coding agent",
    cfg.scripts_dir .. "/run-if-deployed.sh ai ai-agent")

exec(mod .. " + C", "universal copy", cfg.scripts_dir .. "/universal-clipboard.sh copy")
exec(mod .. " + X", "universal cut", cfg.scripts_dir .. "/universal-clipboard.sh cut")
exec(mod .. " + V", "universal paste", cfg.scripts_dir .. "/universal-clipboard.sh paste")
exec(mod .. " + CTRL + V", "clipboard history", "quickshell ipc call clipboard toggle")
exec(mod .. " + ALT + V", "toggle audio visualizer", "quickshell ipc call visualizer toggle")
exec(mod .. " + SHIFT + C", "calculator", cfg.scripts_dir .. "/calculator.sh")
exec(mod .. " + CTRL + Q", "calculator", cfg.scripts_dir .. "/calculator.sh")
exec(mod .. " + CTRL + period", "transcode media", cfg.scripts_dir .. "/transcode-menu.sh")
exec(mod .. " + CTRL + S", "share with LocalSend", "localsend")
exec(mod .. " + CTRL + T", "activity (btop, floating)", cfg.scripts_dir .. "/btop-float.sh")
exec(mod .. " + ALT + T", "network speed test", "quickshell ipc call network speedTest")
exec(mod .. " + CTRL + I", "toggle network panel", "quickshell ipc call network toggle")
exec(mod .. " + CTRL + D", "toggle display panel", "quickshell ipc call display toggle")
exec(mod .. " + CTRL + M", "toggle media panel", "quickshell ipc call media toggle")
exec(mod .. " + CTRL + A", "toggle audio panel", "quickshell ipc call audio toggle")
exec(mod .. " + CTRL + B", "toggle Bluetooth panel", "quickshell ipc call bluetooth toggle")
exec(mod .. " + SHIFT + B", "power profile menu", cfg.scripts_dir .. "/power-profile.sh menu")
exec(mod .. " + CTRL + W", "manage Wi-Fi and network", "quickshell ipc call network manage")
exec(mod .. " + CTRL + SHIFT + SPACE", "theme picker", "quickshell ipc call theme toggle")
exec(mod .. " + Backspace", "toggle window transparency on all workspaces", cfg.scripts_dir .. "/toggle-transparency.sh")
exec(mod .. " + SHIFT + Backspace", "toggle window gaps on all workspaces", cfg.scripts_dir .. "/toggle-gaps.sh")
bind(mod .. " + CTRL + N", "night light", function()
    hl.dispatch(hl.dsp.exec_cmd(cfg.scripts_dir .. "/night-light.sh toggle"))
end)

exec(mod .. " + comma", "dismiss newest notification", "$HOME/.local/bin/notificationctl dismiss-one")
exec(mod .. " + SHIFT + comma", "dismiss all notifications", "$HOME/.local/bin/notificationctl dismiss-all")
package_exec(mod .. " + CTRL + comma", "toggle do not disturb", "modes", "desktop-mode toggle do-not-disturb")
exec(mod .. " + ALT + comma", "invoke newest notification", "$HOME/.local/bin/notificationctl invoke-latest")
exec(mod .. " + SHIFT + ALT + comma", "notification history", "$HOME/.local/bin/notificationctl history")
exec(mod .. " + D", "toggle do not disturb", "$HOME/.local/bin/notificationctl dnd-toggle")
package_exec(mod .. " + ALT + M", "desktop modes", "modes", "desktop-mode menu")
package_exec(mod .. " + SHIFT + I", "stay awake", "modes", "desktop-mode toggle stay-awake")
-- Countdown reminders. Backed by transient systemd user timers, so they
-- outlive the launching process and are cancelled by systemd.
exec(mod .. " + CTRL + R", "set a reminder", "$HOME/.local/bin/lmenu-reminder set")
exec(mod .. " + CTRL + ALT + R", "show reminders", "$HOME/.local/bin/lmenu-reminder list")
exec(mod .. " + CTRL + SHIFT + R", "clear all reminders", "$HOME/.local/bin/lmenu-reminder clear")
exec(mod .. " + CTRL + O", "toggle menu (night light, DND, stay awake, etc)", cfg.scripts_dir .. "/toggles-menu.sh")
package_exec(mod .. " + CTRL + Escape", "start ASCII screensaver", "screensaver", "ascii-screensaver force")
package_exec(mod .. " + CTRL + SHIFT + Escape", "toggle automatic ASCII screensaver", "screensaver", "toggle-screensaver")
exec(mod .. " + SHIFT + G", "start Gaming VM", [[bash -lc 'virsh -c qemu:///system start Gaming-VM && sleep 15 && looking-glass-client -F -f /dev/shm/looking-glass']])

-- Capture suite.
exec(mod .. " + SHIFT + S", "screenshot", cfg.scripts_dir .. "/capture/capture.sh screenshot smart")
exec(mod .. " + ALT + S", "screenshot focused monitor", cfg.scripts_dir .. "/capture/capture.sh screenshot monitor")
exec(mod .. " + ALT + CTRL + S", "screenshot monitor in 5s", cfg.scripts_dir .. "/capture/capture.sh screenshot monitor --delay=5")
exec(mod .. " + CTRL + SHIFT + S", "screenshot monitor in 10s", cfg.scripts_dir .. "/capture/capture.sh screenshot monitor --delay=10")
exec(mod .. " + SHIFT + R", "screen recording", cfg.scripts_dir .. "/capture/capture.sh record toggle")
exec(mod .. " + SHIFT + P", "colour picker", cfg.scripts_dir .. "/capture/capture.sh color")
exec(mod .. " + SHIFT + T", "extract text", cfg.scripts_dir .. "/capture/capture.sh ocr")
exec(mod .. " + CTRL + C", "capture menu", cfg.scripts_dir .. "/capture/capture.sh menu")
exec(mod .. " + ALT + C", "toggle webcam overlay", cfg.scripts_dir .. "/capture/capture.sh record webcam-toggle")
exec(mod .. " + ALT + bracketleft", "webcam overlay smaller", cfg.scripts_dir .. "/capture/capture.sh record webcam-size smaller")
exec(mod .. " + ALT + bracketright", "webcam overlay larger", cfg.scripts_dir .. "/capture/capture.sh record webcam-size larger")

-- Use the physical number-row keycodes reported by the active keyboard. Hyprland 0.56.2's
-- bound Lua window dispatcher does not act on the focused window reliably, so
-- execute the same dispatcher through the live evaluator at keypress time.
local number_row_keys = {
    "code:10", "code:11", "code:12", "code:13", "code:14",
    "code:15", "code:16", "code:17", "code:18", "code:19",
}

local function move_active_window_dispatcher(workspace, follow)
    local command = string.format(
        [[hyprctl eval 'hl.dispatch(hl.dsp.window.move({ workspace = %d, follow = %s }))']],
        workspace, follow and "true" or "false")
    return hl.dsp.exec_cmd(command)
end

for workspace = 1, 10 do
    bind(mod .. " + SHIFT + " .. number_row_keys[workspace], "move to workspace " .. workspace,
        move_active_window_dispatcher(workspace, true))
    bind(mod .. " + CTRL + " .. number_row_keys[workspace], "move silently to workspace " .. workspace,
        move_active_window_dispatcher(workspace, false))
end
bind(mod .. " + SHIFT + bracketleft", "move to previous workspace", hl.dsp.window.move({ workspace = "-1", follow = true }))
bind(mod .. " + SHIFT + bracketright", "move to next workspace", hl.dsp.window.move({ workspace = "+1", follow = true }))
bind(mod .. " + CTRL + bracketleft", "move silently to previous workspace", hl.dsp.window.move({ workspace = "-1", follow = false }))
bind(mod .. " + CTRL + bracketright", "move silently to next workspace", hl.dsp.window.move({ workspace = "+1", follow = false }))
for workspace = 1, 4 do
    bind(mod .. " + SHIFT + ALT + " .. number_row_keys[workspace], "move silently to workspace " .. workspace,
        move_active_window_dispatcher(workspace, false))
end

bind(mod .. " + SHIFT + F", "fullscreen (true)", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
bind(mod .. " + CTRL + F", "maximize (keep bar)", hl.dsp.window.fullscreen({ mode = "maximized" }))

-- Programs.
exec(mod .. " + E", "files", cfg.file_manager)
exec(mod .. " + SHIFT + E", "files", cfg.file_manager)
exec(mod .. " + SHIFT + ALT + F", "files here (terminal cwd)", cfg.scripts_dir .. "/files-here.sh")
exec(mod .. " + SHIFT + D", "disks", cfg.disks)
exec(mod .. " + U", "eject removable drives", cfg.scripts_dir .. "/eject-drive.sh")
exec(mod .. " + A", "application launcher", cfg.scripts_dir .. "/quick-search.sh drun")
exec(mod .. " + SHIFT + A", "lmenu root", "$HOME/.local/bin/lmenu toggle")
exec(mod .. " + ALT + A", "web app manager", "quickshell ipc call webapps toggle")
exec(mod .. " + W", "browser", "helium-browser")
exec(mod .. " + ALT + W", "Windows VM", "$HOME/.local/bin/windows-vm launch")
exec(mod .. " + CTRL + ALT + W", "stop Windows VM", "$HOME/.local/bin/windows-vm stop")
exec(mod .. " + SHIFT + ALT + W", "default browser private window", cfg.scripts_dir .. "/default-browser-private")
exec(mod .. " + S", "spotify", "spotify")
exec(mod .. " + O", "obsidian", "obsidian")
exec(mod .. " + R", "voice dictation", "hyprvoice toggle")
bind(mod .. " + T", "toggle window floating / tiling", hl.dsp.window.float({ action = "toggle" }))
exec(mod .. " + SHIFT + H", "hermes", "hermes")
exec(mod .. " + SHIFT + W", "wallpaper picker", "~/.local/bin/hypr-wallpaper-picker")

-- Workspace focus.
bind(mod .. " + Tab", "next workspace", hl.dsp.focus({ workspace = "e+1" }))
bind(mod .. " + SHIFT + Tab", "previous workspace", hl.dsp.focus({ workspace = "e-1" }))
bind(mod .. " + CTRL + Tab", "former workspace", hl.dsp.focus({ workspace = "previous" }))
bind(mod .. " + mouse_up", "previous workspace", hl.dsp.focus({ workspace = "e-1" }))
bind(mod .. " + mouse_down", "next workspace", hl.dsp.focus({ workspace = "e+1" }))
for workspace = 1, 10 do
    bind(mod .. " + " .. number_row_keys[workspace], "workspace " .. workspace,
        hl.dsp.focus({ workspace = workspace }))
end
for workspace = 11, 15 do
    bind(mod .. " + ALT + " .. (workspace - 10), "workspace " .. workspace, hl.dsp.focus({ workspace = workspace }))
end

-- Desktop zoom uses Lua evaluation while retaining getoption as a read-only query.
exec(mod .. " + ALT + mouse_down", "Zoom in", [[hyprctl -q eval "hl.config({ cursor = { zoom_factor = $(hyprctl getoption cursor:zoom_factor -j | jq '.float * 1.1') } })"]])
exec(mod .. " + ALT + mouse_up", "Zoom out", [[hyprctl -q eval "hl.config({ cursor = { zoom_factor = $(hyprctl getoption cursor:zoom_factor -j | jq '(.float * 0.9) | if . < 1 then 1 else . end') } })"]])
exec(mod .. " + ALT + SHIFT + mouse_down", "Reset zoom", [[hyprctl -q eval 'hl.config({ cursor = { zoom_factor = 1 } })']])
exec(mod .. " + ALT + SHIFT + mouse_up", "Reset zoom", [[hyprctl -q eval 'hl.config({ cursor = { zoom_factor = 1 } })']])

-- Audio, media, and brightness. Duplicate pactl bindings intentionally remain
-- after the primary wpctl bindings to preserve registration order.
exec("XF86AudioRaiseVolume", "volume up", "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+", { repeating = true })
exec("XF86AudioLowerVolume", "volume down", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-", { repeating = true })
exec("XF86AudioMute", "mute", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
exec("XF86AudioRaiseVolume", "volume up (pactl)", "pactl set-sink-volume @DEFAULT_SINK@ +5%", { repeating = true, locked = true })
exec("XF86AudioLowerVolume", "volume down (pactl)", "pactl set-sink-volume @DEFAULT_SINK@ -5%", { repeating = true, locked = true })
exec("XF86AudioMute", "mute (pactl)", "pactl set-sink-mute @DEFAULT_SINK@ toggle", { locked = true })
exec("XF86AudioPlay", "play / pause", "playerctl play-pause")
exec("XF86AudioPause", "pause", "playerctl pause")
exec("XF86AudioNext", "next track", "playerctl next")
exec("XF86AudioPrev", "previous track", "playerctl previous")
exec("XF86AudioStop", "stop playback", "playerctl stop")
exec("XF86MonBrightnessUp", "brightness up", "brightnessctl set +5%", { repeating = true })
exec("XF86MonBrightnessDown", "brightness down", "brightnessctl set 5%-", { repeating = true })

-- Laptop lid: the internal panel follows the lid. Locked so it still fires
-- while the screen is locked.
exec("switch:on:Lid Switch", "lid closed: disable internal display", cfg.scripts_dir .. "/lid-switch.sh close", { locked = true })
exec("switch:off:Lid Switch", "lid opened: enable internal display", cfg.scripts_dir .. "/lid-switch.sh open", { locked = true })

-- Resize, move, and focus.
-- Tiling direction for the next window to open. dwindle's `preselect` is a
-- one-time override, so each press affects only the next window.
-- Horizontal = the new window opens beside this one; vertical = below it.
bind(mod .. " + J", "split horizontally (next window opens to the right)", hl.dsp.layout("preselect r"))
bind(mod .. " + SHIFT + V", "split vertically (next window opens below)", hl.dsp.layout("preselect d"))
local resize_binds = {
    { mod .. " + minus", "expand window left", -100, 0 },
    { mod .. " + equal", "shrink window left", 100, 0 },
    { mod .. " + SHIFT + minus", "shrink window up", 0, -100 },
    { mod .. " + SHIFT + equal", "expand window down", 0, 100 },
    { mod .. " + ALT + minus", "expand window left (fine)", -10, 0 },
    { mod .. " + ALT + equal", "shrink window left (fine)", 10, 0 },
    { mod .. " + CTRL + minus", "expand window left (coarse)", -300, 0 },
    { mod .. " + CTRL + equal", "shrink window left (coarse)", 300, 0 },
}
for _, item in ipairs(resize_binds) do
    bind(item[1], item[2], hl.dsp.window.resize({ x = item[3], y = item[4], relative = true }), { repeating = true })
end

exec(mod .. " + ALT + Home", "save window width", cfg.scripts_dir .. "/window-width.sh save")
exec(mod .. " + Home", "restore saved window width", cfg.scripts_dir .. "/window-width.sh restore")

for _, direction in ipairs({ "l", "r", "u", "d" }) do
    local names = { l = "left", r = "right", u = "up", d = "down" }
    bind(mod .. " + CTRL + " .. names[direction], "move window " .. names[direction], hl.dsp.window.move({ direction = direction }))
    bind(mod .. " + SHIFT + " .. names[direction], "swap window " .. names[direction], hl.dsp.window.swap({ direction = direction }))
    bind(mod .. " + SHIFT + ALT + " .. names[direction], "move workspace to " .. names[direction] .. " monitor", hl.dsp.workspace.move({ monitor = direction }))
    bind(mod .. " + " .. names[direction], "focus " .. names[direction], hl.dsp.focus({ direction = direction }))
end

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + SHIFT + mouse:273", hl.dsp.window.resize(), { mouse = true })

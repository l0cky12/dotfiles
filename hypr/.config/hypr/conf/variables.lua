-- SUPER+E opens whatever mimeapps.list says handles folders, which lmenu's
-- Setup > Defaults > File manager sets. It is read when the config loads, so
-- that menu reloads Hyprland after a change.
local function folder_handler()
    local config_home = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")
    local file = io.open(config_home .. "/mimeapps.list", "r")
    if not file then
        return nil
    end
    local in_defaults, handler = false, nil
    for line in file:lines() do
        local section = line:match("^%s*(%[.-%])%s*$")
        if section then
            in_defaults = section == "[Default Applications]"
        elseif in_defaults and not handler then
            handler = line:match("^%s*inode/directory%s*=%s*([%w._-]+)%.desktop")
        end
    end
    file:close()
    return handler and ("gtk-launch " .. handler) or nil
end

return {
    scripts_dir = "/home/liam/.config/hypr/scripts",
    terminal = "kitty",
    browser = "brave",
    file_manager = folder_handler() or "nautilus",
    disks = "gnome-disks",
}

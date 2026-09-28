-- SUPER+E opens whatever mimeapps.list says handles folders, which lmenu's
-- Setup > Defaults > File manager sets. It is read when the config loads, so
-- that menu reloads Hyprland after a change.
local function folder_handler()
    local config_home = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")
    local names = {}
    for desktop in (os.getenv("XDG_CURRENT_DESKTOP") or ""):gmatch("[^:]+") do
        names[#names + 1] = desktop:lower() .. "-mimeapps.list"
    end
    names[#names + 1] = "mimeapps.list"
    for _, name in ipairs(names) do
        local file = io.open(config_home .. "/" .. name, "r")
        if file then
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
            if handler then return "gtk-launch " .. handler end
        end
    end
    return nil
end

return {
    scripts_dir = "/home/liam/.config/hypr/scripts",
    terminal = "kitty",
    browser = "brave",
    file_manager = folder_handler() or "nautilus",
    disks = "gnome-disks",
}

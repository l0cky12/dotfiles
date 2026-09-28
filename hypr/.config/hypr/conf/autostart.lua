local function start(command, rules)
    hl.exec_cmd(command, rules)
end

hl.on("hyprland.start", function()
    start("$HOME/.local/bin/hypr-wallpaper-picker restore")
    start("wl-paste --type text --watch $HOME/.config/hypr/scripts/clipboard-store.sh")
    start("wl-paste --type image --watch $HOME/.config/hypr/scripts/clipboard-store.sh")
    start("quickshell")
    start("$HOME/.config/hypr/scripts/hypridle-profile daemon")
    start("$HOME/.local/bin/desktop-mode daemon")
    start("~/.config/hypr/scripts/spotify-notify.sh")
    start("$HOME/.config/hypr/scripts/hypr-monitor-watch.py")
    -- Polkit needs an agent to ask for passwords, for example when fprintd
    -- enrolls a finger or NetworkManager saves a profile.
    -- hyprpolkitagent.service only starts with graphical-session.target, which
    -- a start-hyprland session never reaches, so without this those requests
    -- fail with "Not Authorized".
    start("systemctl --user start hyprpolkitagent.service")
    -- Night-light schedule (Super+Shift+N). Started, not enabled, for the same
    -- reason: it should only run inside a Hyprland session.
    start("systemctl --user start night-light-schedule.timer")
    start("helium-browser", { workspace = "2 silent" })
    start("spotify", { workspace = "9 silent" })
    start("virt-manager", { workspace = "6 silent" })
    start("hermes", { workspace = "6 silent" })
    start("obsidian", { workspace = "3 silent" })
    start("t3code", { workspace = "4 silent" })
    -- Workspace 1 comes up in herdr; quitting it drops back to a shell rather
    -- than closing the window, so the workspace always has a terminal.
    start("kitty zsh -c 'herdr; exec zsh'", { workspace = "1 silent" })
    start("udiskie --automount --notify --no-tray")
end)

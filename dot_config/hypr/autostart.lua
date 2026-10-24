-- Session autostart (the old exec-once list). Kept in its own module so the
-- test rig can load the rest of the config without starting any of this.
-- Quickshell (bar, wallpaper, rail, toasts, launcher) replaces waybar, hyprpaper and
-- mako; qs-supervise restarts it if it exits. ~/.local/bin is spelled out because it
-- is only on PATH in interactive shells (.bashrc).
hl.on("hyprland.start", function()
    hl.exec_cmd("~/.local/bin/qs-supervise")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("~/.local/bin/librepods --start-minimized")
    hl.exec_cmd("~/.local/bin/airpods-autoconnect")
    hl.exec_cmd("xremap ~/.config/xremap/config.yml")
end)

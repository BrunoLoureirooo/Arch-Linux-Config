-- Session autostart (the old exec-once list). Kept in its own module so the
-- test rig can load the rest of the config without starting any of this.
hl.on("hyprland.start", function()
    hl.exec_cmd("mako")
    hl.exec_cmd("waybar")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("~/.local/bin/librepods --start-minimized")
    hl.exec_cmd("~/.local/bin/airpods-autoconnect")
    hl.exec_cmd("sleep 1 && hyprpaper")
end)

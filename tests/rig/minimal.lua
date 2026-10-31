-- Minimal Hyprland Lua config for the headless test rig (tests/rig/nested-hypr.sh).
-- Two named monitors, no eye candy, one test bind loaded through `require`.

hl.monitor({ output = "DP-1",  mode = "1920x1080@60", position = "0x0",    scale = 1 })
hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "1920x0", scale = 1 })

hl.config({
    general    = { gaps_in = 0, gaps_out = 0, border_size = 1 },
    decoration = { rounding = 0, shadow = { enabled = false }, blur = { enabled = false } },
    animations = { enabled = false },
    misc       = { disable_hyprland_logo = true, disable_splash_rendering = true, force_default_wallpaper = 0,
                   disable_watchdog_warning = true }, -- rig starts Hyprland without start-hyprland
    xwayland   = { enabled = false },
    ecosystem  = { no_update_news = true, no_donation_nag = true },
})

-- Relative module next to this file: tests/rig/lib/rigbind.lua
require("lib.rigbind")

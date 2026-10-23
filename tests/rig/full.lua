-- Rig wrapper: loads the repo's real Hyprland config (dot_config/hypr) inside the
-- headless nested rig, minus everything that must never run there.
--   tests/rig/nested-hypr.sh start tests/rig/full.lua
--
-- * autostart.lua is never loaded: it would start waybar, mako, blueman-applet and
--   the librepods/airpods tools, which touch the real Bluetooth stack.
-- * colors comes from the chezmoi seed (create_colors.lua -> colors.lua).
-- * the rig's headless DP-1 stands in for the BenQ (left of eDP-1, at 0x0).
-- Exec binds (launchers, lid, headless, ...) are registered but tests never fire them.

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")
local hypr = here .. "/../../dot_config/hypr"
package.path = hypr .. "/?.lua;" .. package.path

package.loaded["autostart"] = true
package.loaded["colors"] = dofile(hypr .. "/create_colors.lua")

require("hyprland")

hl.monitor({ output = "DP-1", mode = "1920x1080@60", position = "0x0", scale = 1 })
hl.config({
    misc = { disable_hyprland_logo = true, disable_splash_rendering = true, force_default_wallpaper = 0,
             disable_watchdog_warning = true }, -- rig starts Hyprland without start-hyprland
    xwayland = { enabled = false },
    ecosystem = { no_update_news = true, no_donation_nag = true },
})

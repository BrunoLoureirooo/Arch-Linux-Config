-- Hyprland 0.56 Lua config. Port of the hyprlang hyprland.conf (kept next to
-- this file as the rollback copy; hyprland.lua wins when both exist).

-- Monitors -------------------------------------------------------------------
-- BenQ EX2510S = main monitor, physically to the LEFT of the laptop.
-- Matched by description (not DP-1) so it works whichever port it's plugged into.
hl.monitor({ output = "desc:BNQ BenQ EX2510S K8M02386019", mode = "1920x1080@144", position = "0x0", scale = 1 })
hl.monitor({ output = "eDP-1", mode = "1920x1080@144", position = "1920x0", scale = 1 })
-- Stale: nothing is connected to HDMI-A-1 (the BenQ is on DP-1). Left here in case
-- you re-add an HDMI display -- note it would collide with the BenQ at 0x0.
-- hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "0x0", scale = 1 })

-- Per-screen workspace pools (lib/pools.lua): the BenQ owns 1-5, the panel 11-15.
-- Workspace 1 (the startup workspace) is the BenQ's default, which makes it the
-- MAIN screen: that's where you begin. 11 is the panel's default, so it starts
-- inside its own pool (without it Hyprland opens a free id such as 6 there).
-- If a screen is unplugged Hyprland moves its workspaces onto the other one.
local pools = require("lib.pools")
local pool_monitors = { [0] = "desc:BNQ BenQ EX2510S K8M02386019", [1] = "eDP-1" }
for pool, monitor in pairs(pool_monitors) do
    for slot = 1, 5 do
        local id = pools.ws_id(pool, slot)
        hl.workspace_rule({ workspace = tostring(id), monitor = monitor, persistent = true, default = slot == 1 })
    end
end

-- Environment ----------------------------------------------------------------
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("WLR_DRM_NO_ATOMIC", "1")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("WLR_NO_HARDWARE_CURSORS", "1")
-- Dolphin outside Plasma: needed so file associations work (with archlinux-xdg-menu)
hl.env("XDG_MENU_PREFIX", "arch-")

-- Look and input -------------------------------------------------------------
-- colors.lua is generated (seeded by chezmoi from create_colors.lua, then
-- rewritten by rice-palette). If it is missing or broken, fall back to the seed
-- tokens instead of erroring, so the rest of this file (binds) still loads.
local ok, c = pcall(require, "colors")
if not ok or type(c) ~= "table" then
    c = { active = { "rgba(00f0ffff)", "rgba(ff2e88ff)" }, inactive = "rgba(1b1d30ff)" }
end

hl.config({
    general = {
        gaps_in = 3,
        gaps_out = 6,
        border_size = 1,
        col = {
            active_border = { colors = c.active, angle = 45 },
            inactive_border = c.inactive,
        },
        layout = "dwindle",
    },
    decoration = {
        rounding = 0,
        blur = { enabled = false },
        shadow = { enabled = false },
    },
    animations = { enabled = false },
    input = {
        kb_layout = "pt",
        touchpad = { natural_scroll = false },
    },
})

-- Binds ----------------------------------------------------------------------
-- Every window-manager bind is in binds.lua; the hardware binds stay here.
require("binds")

-- Headless mode: tap the HP hotkey = all displays dark + mouse/keyboard power cut.
-- Tap again to restore. locked so it still fires with the screens off.
hl.bind("XF86Launch2", hl.dsp.exec_cmd("/home/vyrus-extreme/.local/bin/headless"), { locked = true })

-- Lid switch. This machine doubles as a homeserver node, so it never suspends on
-- a lid close -- logind is set to ignore the switch in
-- /etc/systemd/logind.conf.d/10-headless.conf, and it lands here instead.
-- Closing only drops eDP-1 as an output, so no workspace or new window ends up on
-- a panel you cannot see; the externals are left lit and untouched. Deliberately
-- unrelated to headless mode above. locked so it fires with the screens off.
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("/home/vyrus-extreme/.local/bin/lid close"), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("/home/vyrus-extreme/.local/bin/lid open"), { locked = true })

require("autostart")

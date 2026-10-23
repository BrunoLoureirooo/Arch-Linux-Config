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

-- The one rule that makes the BenQ the MAIN screen: workspace 1 (the startup
-- workspace) lands there, so that's where you begin and where new windows go.
hl.workspace_rule({ workspace = "1", monitor = "desc:BNQ BenQ EX2510S K8M02386019", default = true })

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
local mainMod = "SUPER"
local terminal = "kitty"
local menu = "wofi --show drun"
local jb = "/home/vyrus-extreme/.local/share/JetBrains/Toolbox/scripts/"

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(terminal .. " -e yazi"))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd("firefox"))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("code"))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(jb .. "rider"))
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd(jb .. "idea"))

-- Focus and move (arrow keys + vim). Move, not swap, so that pushing past the
-- edge of a screen carries the window onto the next monitor.
local dirs = { left = "left", right = "right", up = "up", down = "down", H = "left", L = "right", K = "up", J = "down" }
for key, dir in pairs(dirs) do
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = dir }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }))
end

for i = 1, 9 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- Jump focus to the other monitor
hl.bind(mainMod .. " + Tab", hl.dsp.focus({ monitor = "+1" }))

hl.bind("Print", hl.dsp.exec_cmd('grim -g "$(slurp)" ~/Pictures/screenshot_$(date +%s).png'))

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

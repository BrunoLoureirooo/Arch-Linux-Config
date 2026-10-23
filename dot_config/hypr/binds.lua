-- Window-manager binds (spec section 6). Workspaces are per screen: each monitor
-- owns a pool of five ids (lib/pools.lua), and Ctrl+1..5 / the step keys act on
-- the pool of the monitor that has focus, never touching the other screen.
-- Lid and headless binds live in hyprland.lua.
local pools = require("lib.pools")

local M = {}
local assigned = {} -- session memory: extra monitors keep their pool by name

local function active_pool()
    local mon = hl.get_active_monitor()
    return mon, pools.pool_for(mon, assigned)
end

-- Pool of a monitor by name (used by tests/hypr/check_pools.sh).
function M.pool_of(name)
    return pools.pool_for(hl.get_monitor(name), assigned)
end

function M.focus_slot(slot)
    local _, pool = active_pool()
    hl.dispatch(hl.dsp.focus({ workspace = pools.ws_id(pool, slot) }))
end

function M.move_to_slot(slot)
    local _, pool = active_pool()
    hl.dispatch(hl.dsp.window.move({ workspace = pools.ws_id(pool, slot) }))
end

-- Previous/next slot on the focused screen; clamps at 1 and 5, never wraps.
function M.step(delta)
    local mon, pool = active_pool()
    local slot = pools.slot_of(mon.active_workspace.id, pool)
    hl.dispatch(hl.dsp.focus({ workspace = pools.ws_id(pool, pools.step(slot, delta)) }))
end

for n = 1, 5 do
    hl.bind("CTRL + " .. n, function() M.focus_slot(n) end, { description = "focus slot " .. n .. " on this screen" })
    hl.bind("CTRL + SHIFT + " .. n, function() M.move_to_slot(n) end, { description = "move window to slot " .. n })
end
hl.bind("CTRL + ALT + left", function() M.step(-1) end, { description = "previous slot" })
hl.bind("CTRL + ALT + right", function() M.step(1) end, { description = "next slot" })
hl.bind("mouse:275", function() M.step(-1) end, { description = "previous slot (mouse back)" })
hl.bind("mouse:276", function() M.step(1) end, { description = "next slot (mouse forward)" })

-- Focus and move windows (arrows + vim). Move, not swap, so pushing past the
-- edge of a screen carries the window onto the next monitor (BenQ is left).
local dirs = { left = "left", right = "right", up = "up", down = "down", H = "left", L = "right", K = "up", J = "down" }
for key, dir in pairs(dirs) do
    hl.bind("SUPER + ALT + " .. key, hl.dsp.focus({ direction = dir }))
    hl.bind("SUPER + ALT + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }))
end

hl.bind("SUPER + grave", hl.dsp.focus({ monitor = "+1" }), { description = "focus the other monitor" })
hl.bind("SUPER + Tab", hl.dsp.window.cycle_next(), { description = "cycle windows" })
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("qs ipc call launcher toggle"), { description = "launcher" })
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + CTRL + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind("SUPER + ALT + SPACE", hl.dsp.window.float({ action = "toggle" }))

local jb = "/home/vyrus-extreme/.local/share/JetBrains/Toolbox/scripts/"
local apps = { T = "kitty", F = "firefox", C = "code", E = "kitty -e yazi", R = jb .. "rider", I = jb .. "idea" }
for key, cmd in pairs(apps) do
    hl.bind("CTRL + ALT + " .. key, hl.dsp.exec_cmd(cmd))
end
hl.bind("CTRL + ALT + W", hl.dsp.exec_cmd("qs ipc call carousel toggle"), { description = "carousel" })
hl.bind("CTRL + ALT + SHIFT + Q",
    hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"),
    { description = "exit Hyprland" })

hl.bind("Print", hl.dsp.exec_cmd('grim -g "$(slurp)" ~/Pictures/screenshot_$(date +%s).png'))

return M

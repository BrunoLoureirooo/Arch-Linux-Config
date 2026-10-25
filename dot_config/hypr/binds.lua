-- Window-manager binds (spec section 6). Workspaces are per screen: each monitor
-- owns a pool of five ids (lib/pools.lua), and Ctrl+1..5 / the step keys act on
-- the pool of the monitor that has focus, never touching the other screen.
-- Lid and headless binds live in hyprland.lua.
local pools = require("lib.pools")

local M = {}
local assigned = {} -- session memory: extra monitors keep their pool by name

-- nil when no monitor is active (lid closed with no external screen, headless).
local function active_pool()
    local mon = hl.get_active_monitor()
    if not mon then return nil end
    return mon, pools.pool_for(mon, assigned)
end

-- Pool of a monitor by name (used by tests/hypr/check_pools.sh).
function M.pool_of(name)
    return pools.pool_for(hl.get_monitor(name), assigned)
end

function M.focus_slot(slot)
    local mon, pool = active_pool()
    if not mon then return end
    hl.dispatch(hl.dsp.focus({ workspace = pools.ws_id(pool, slot) }))
end

function M.move_to_slot(slot)
    local mon, pool = active_pool()
    if not mon then return end
    hl.dispatch(hl.dsp.window.move({ workspace = pools.ws_id(pool, slot) }))
end

-- Previous/next slot on the focused screen; clamps at 1 and 5, never wraps.
function M.step(delta)
    local mon, pool = active_pool()
    if not mon then return end
    local ws = mon.active_workspace
    local slot = ws and pools.slot_of(ws.id, pool) or 1
    hl.dispatch(hl.dsp.focus({ workspace = pools.ws_id(pool, pools.step(slot, delta)) }))
end

-- Same slot in the next/previous pool that has a workspace on the focused screen.
-- When a screen goes away (BenQ unplugged, lid closed) its pool moves onto the other
-- one; Ctrl+N and the step keys only reach the screen's own pool, this reaches the
-- moved one. No-op while the screen holds only one pool.
function M.hop_pool(delta)
    local mon, own = active_pool()
    if not mon or not mon.active_workspace then return end
    local ids = {}
    for _, w in ipairs(hl.get_workspaces() or {}) do
        if w.monitor and w.monitor.name == mon.name then ids[#ids + 1] = w.id end
    end
    local id = mon.active_workspace.id
    -- From the active workspace's pool (a moved one too); a non-slot id hops from slot 1.
    local cur = pools.pools_present({ id })[1] or own
    local slot = pools.slot_of(id, cur)
    local target = pools.hop(cur, pools.pools_present(ids), delta)
    if target == cur then return end
    hl.dispatch(hl.dsp.focus({ workspace = pools.ws_id(target, slot) }))
end

for n = 1, 5 do
    hl.bind("CTRL + " .. n, function() M.focus_slot(n) end, { description = "focus slot " .. n .. " on this screen" })
    hl.bind("CTRL + SHIFT + " .. n, function() M.move_to_slot(n) end, { description = "move window to slot " .. n })
end
hl.bind("CTRL + ALT + left", function() M.step(-1) end, { description = "previous slot" })
hl.bind("CTRL + ALT + right", function() M.step(1) end, { description = "next slot" })
hl.bind("CTRL + ALT + up", function() M.hop_pool(1) end, { description = "same slot, next pool on this screen" })
hl.bind("CTRL + ALT + down", function() M.hop_pool(-1) end, { description = "same slot, previous pool on this screen" })
hl.bind("mouse:275", function() M.step(-1) end, { description = "previous slot (mouse back)" })
hl.bind("mouse:276", function() M.step(1) end, { description = "next slot (mouse forward)" })

-- Focus and move windows (arrows + vim). Move, not swap, so pushing past the
-- edge of a screen carries the window onto the next monitor (BenQ is left).
local dirs = { left = "left", right = "right", up = "up", down = "down", H = "left", L = "right", K = "up", J = "down" }
for key, dir in pairs(dirs) do
    hl.bind("SUPER + ALT + " .. key, hl.dsp.focus({ direction = dir }))
    hl.bind("SUPER + ALT + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }))
end

-- Super + the key under Esc, by keycode (TLDE): on the pt layout that key's
-- keysym is backslash, not grave, so a "grave" bind would never fire.
hl.bind("SUPER + code:49", hl.dsp.focus({ monitor = "+1" }), { description = "focus the other monitor" })
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

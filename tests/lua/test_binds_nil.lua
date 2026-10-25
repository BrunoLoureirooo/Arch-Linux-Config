-- binds.lua pool actions must survive no active monitor (lid closed with no
-- external, headless mode) and a monitor without an active workspace.
-- Run from the repo root: lua tests/lua/test_binds_nil.lua (also under luajit).
package.path = "dot_config/hypr/?.lua;" .. package.path

local active -- what hl.get_active_monitor() returns
local workspaces -- what hl.get_workspaces() returns
local dispatched = {}
hl = {
    bind = function() end,
    dispatch = function(d) dispatched[#dispatched + 1] = d end,
    get_active_monitor = function() return active end,
    get_monitor = function() return active end,
    get_workspaces = function() return workspaces end,
    dsp = {
        focus = function(a) return { focus = a } end,
        exec_cmd = function(c) return { exec = c } end,
        window = {},
    },
}
for _, f in ipairs({ "move", "cycle_next", "close", "fullscreen", "float" }) do
    hl.dsp.window[f] = function(a) return { [f] = a or true } end
end

local M = dofile("dot_config/hypr/binds.lua")

local function no_error(what, fn, ...)
    local ok, err = pcall(fn, ...)
    assert(ok, what .. " raised: " .. tostring(err))
end

-- 1. no active monitor: nothing raises, nothing is dispatched
active = nil
no_error("focus_slot(3)", M.focus_slot, 3)
no_error("move_to_slot(3)", M.move_to_slot, 3)
no_error("step(1)", M.step, 1)
no_error("step(-1)", M.step, -1)
assert(#dispatched == 0, "no dispatch without a monitor, got " .. #dispatched)

-- 2. panel (pool 1) without an active workspace: step acts from slot 1
active = { name = "eDP-1", description = "", active_workspace = nil }
no_error("step(1) without workspace", M.step, 1)
assert(#dispatched == 1 and dispatched[1].focus.workspace == 12, "step(+1) from slot 1 -> 12")
no_error("step(-1) without workspace", M.step, -1)
assert(#dispatched == 2 and dispatched[2].focus.workspace == 11, "step(-1) clamps -> 11")

-- 3. pool hop (Ctrl+Alt+Up/Down): nil-safe, then same slot in the other present pool
dispatched = {}
active = nil
no_error("hop_pool(1) without a monitor", M.hop_pool, 1)
active = { name = "eDP-1", description = "", active_workspace = nil }
workspaces = nil
no_error("hop_pool(1) without workspace or list", M.hop_pool, 1)
assert(#dispatched == 0, "no hop dispatch without an active workspace")

local edp = { name = "eDP-1", description = "" }
local benq = { name = "DP-1", description = "BNQ BenQ EX2510S K8M02386019" }
active = { name = "eDP-1", description = "", active_workspace = { id = 13 } }
workspaces = nil
no_error("hop_pool(1) when get_workspaces returns nil", M.hop_pool, 1)
workspaces = { { id = 11, monitor = edp }, { id = 13, monitor = edp }, { id = 2, monitor = benq } }
no_error("hop_pool(1) with only its own pool on this monitor", M.hop_pool, 1)
assert(#dispatched == 0, "one pool on the monitor: hop is a no-op")
workspaces = { { id = 11, monitor = edp }, { id = 13, monitor = edp }, { id = 2, monitor = edp },
               { id = 3, monitor = edp }, { id = 6, monitor = edp }, { id = -98, monitor = edp },
               { id = 21, monitor = nil } }
no_error("hop_pool(1) with the BenQ pool migrated", M.hop_pool, 1)
assert(#dispatched == 1 and dispatched[1].focus.workspace == 3, "hop 13 -> slot 3 of pool 0")
active.active_workspace = { id = 3 }
no_error("hop_pool(-1) back", M.hop_pool, -1)
assert(#dispatched == 2 and dispatched[2].focus.workspace == 13, "hop 3 -> 13")
active.active_workspace = { id = 6 } -- not a pool slot: hops from the monitor's own pool, slot 1
no_error("hop_pool(1) from a non-slot workspace", M.hop_pool, 1)
assert(#dispatched == 3 and dispatched[3].focus.workspace == 1, "hop 6 -> 1")

print("ok")

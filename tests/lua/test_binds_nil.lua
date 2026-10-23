-- binds.lua pool actions must survive no active monitor (lid closed with no
-- external, headless mode) and a monitor without an active workspace.
-- Run from the repo root: lua tests/lua/test_binds_nil.lua (also under luajit).
package.path = "dot_config/hypr/?.lua;" .. package.path

local active -- what hl.get_active_monitor() returns
local dispatched = {}
hl = {
    bind = function() end,
    dispatch = function(d) dispatched[#dispatched + 1] = d end,
    get_active_monitor = function() return active end,
    get_monitor = function() return active end,
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

print("ok")

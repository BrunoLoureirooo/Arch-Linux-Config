-- autostart.lua: the exact session autostart list, in order, after the Quickshell
-- cutover (waybar, hyprpaper and mako replaced by qs-supervise).
-- Run from the repo root: lua tests/lua/test_autostart.lua (also under luajit).
local handlers = {}
local execs = {}
hl = {
    on = function(event, fn) handlers[#handlers + 1] = { event = event, fn = fn } end,
    exec_cmd = function(c) execs[#execs + 1] = c end,
}

dofile("dot_config/hypr/autostart.lua")

assert(#handlers == 1 and handlers[1].event == "hyprland.start", "one hyprland.start handler")
assert(#execs == 0, "nothing runs before the start event")
handlers[1].fn()

local want = {
    "~/.local/bin/qs-supervise",
    "blueman-applet",
    "~/.local/bin/librepods --start-minimized",
    "~/.local/bin/airpods-autoconnect",
    "xremap --watch=device ~/.config/xremap/config.yml",
}
local got = table.concat(execs, " | ")
assert(#execs == #want, "exec count " .. #execs .. ": " .. got)
for i, c in ipairs(want) do
    assert(execs[i] == c, "exec " .. i .. ": want '" .. c .. "', got '" .. tostring(execs[i]) .. "'")
end
for _, c in ipairs(execs) do
    for _, gone in ipairs({ "waybar", "hyprpaper", "mako" }) do
        assert(not c:find(gone, 1, true), "'" .. gone .. "' still started: " .. c)
    end
end
print("ok")

-- binds.lua registers the volume keys (wpctl), locked so they work on a locked or
-- dark screen; the volume steps also repeat while held. Nothing is executed: the
-- stubbed exec_cmd only records the command string.
-- Run from the repo root: lua tests/lua/test_media_keys.lua (also under luajit).
package.path = "dot_config/hypr/?.lua;" .. package.path

local binds = {}
local function auto()
    return setmetatable({}, { __index = function() return auto() end, __call = function() return auto() end })
end
hl = setmetatable({
    bind = function(key, action, opts) binds[key] = { action = action, opts = opts or {} } end,
    dsp = setmetatable({ exec_cmd = function(c) return { exec = c } end }, { __index = function() return auto() end }),
}, { __index = function() return auto() end })

dofile("dot_config/hypr/binds.lua")

local want = {
    XF86AudioRaiseVolume = { "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+", true },
    XF86AudioLowerVolume = { "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%-", true },
    XF86AudioMute = { "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", false },
    XF86AudioMicMute = { "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", false },
}
for key, w in pairs(want) do
    local b = binds[key]
    assert(b, key .. " is not bound")
    assert(type(b.action) == "table" and b.action.exec == w[1],
        key .. ": want exec '" .. w[1] .. "', got '" .. tostring(type(b.action) == "table" and b.action.exec) .. "'")
    assert(b.opts.locked == true, key .. " must be locked")
    assert((b.opts.repeating == true) == w[2], key .. ": repeating should be " .. tostring(w[2]))
end
for key in pairs(binds) do
    assert(not key:find("Brightness", 1, true), "no brightness binds (brightnessctl is not installed): " .. key)
end
print("ok")

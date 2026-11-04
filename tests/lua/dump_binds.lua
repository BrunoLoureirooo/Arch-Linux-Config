-- Prints one Hyprland bind key string per line, as recorded from hl.bind().
-- Runs binds.lua with a stubbed `hl`, so binds built in loops are included.
-- Usage (repo root): lua tests/lua/dump_binds.lua [path/to/binds.lua]
-- Its require("lib.pools") is resolved next to the given binds.lua.
local path = arg[1] or "dot_config/hypr/binds.lua"
local dir = path:match("^(.*)/[^/]*$") or "."
package.path = dir .. "/?.lua;" .. package.path

-- Any hl.dsp.* / hl.* function we do not know returns an empty table, so new
-- dispatchers in binds.lua do not break the dump.
local function auto()
    return setmetatable({}, {
        __index = function() return auto() end,
        __call = function() return auto() end,
    })
end

local keys = {}
hl = setmetatable({
    bind = function(k) keys[#keys + 1] = k end,
}, { __index = function() return auto() end })

dofile(path)
for _, k in ipairs(keys) do print(k) end

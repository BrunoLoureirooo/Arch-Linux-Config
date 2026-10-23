package.path = "dot_config/hypr/lib/?.lua;" .. package.path
local pools = require("pools")

assert(pools.ws_id(0, 1) == 1, "ws_id(0,1)")
assert(pools.ws_id(0, 5) == 5, "ws_id(0,5)")
assert(pools.ws_id(1, 1) == 11, "ws_id(1,1)")
assert(pools.ws_id(1, 5) == 15, "ws_id(1,5)")

local benq = {name = "DP-1", description = "BNQ BenQ EX2510S K8M02386019"}
local panel = {name = "eDP-1", description = "Chimei Innolux Corporation 0x1609"}
local assigned = {}
assert(pools.pool_for(benq, assigned) == 0, "BenQ is pool 0")
assert(pools.pool_for(panel, assigned) == 1, "eDP-1 is pool 1")

local fresh = {}
local hdmi = {name = "HDMI-A-1", description = "X"}
assert(pools.pool_for(hdmi, fresh) == 2, "first unknown monitor is pool 2")
assert(pools.pool_for({name = "DP-3", description = "Y"}, fresh) == 3, "second unknown is pool 3")
assert(pools.pool_for(hdmi, fresh) == 2, "unknown monitor keeps its pool")

assert(pools.slot_of(13, 1) == 3, "slot_of(13,1)")
assert(pools.slot_of(3, 0) == 3, "slot_of(3,0)")
assert(pools.slot_of(13, 0) == 1, "slot_of foreign id falls back to 1")
assert(pools.slot_of(15, 1) == 5, "slot_of(15,1)")

assert(pools.step(5, 1) == 5, "step clamps high")
assert(pools.step(1, -1) == 1, "step clamps low")
assert(pools.step(3, 1) == 4, "step up")
assert(pools.step(3, -1) == 2, "step down")
print("ok")

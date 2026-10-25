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

-- pools_present: sorted, de-duplicated pool numbers of the pool-slot ids in the list;
-- ids outside a slot range (6, 10, 16) and special workspaces (negative) are ignored.
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
assert(same(pools.pools_present({ 13, 11, 3, 1, 12 }), { 0, 1 }), "pools_present sorts and dedups")
assert(same(pools.pools_present({ 22, 15 }), { 1, 2 }), "pools_present extra pool")
assert(same(pools.pools_present({ 6, 10, 16, -98 }), {}), "pools_present ignores non-slot ids")
assert(same(pools.pools_present({}), {}), "pools_present empty")

-- hop: next/previous present pool, wrapping; the current pool when it is the only one.
assert(pools.hop(1, { 0, 1 }, 1) == 0, "hop +1 wraps 1 -> 0")
assert(pools.hop(1, { 0, 1 }, -1) == 0, "hop -1 1 -> 0")
assert(pools.hop(0, { 0, 1 }, 1) == 1, "hop +1 0 -> 1")
assert(pools.hop(0, { 0, 1, 2 }, -1) == 2, "hop -1 wraps 0 -> 2")
assert(pools.hop(1, { 0, 1, 2 }, 1) == 2, "hop +1 1 -> 2")
assert(pools.hop(2, { 0, 1, 2 }, 1) == 0, "hop +1 wraps 2 -> 0")
assert(pools.hop(1, { 1 }, 1) == 1, "hop with one pool is a no-op")
assert(pools.hop(1, {}, -1) == 1, "hop with no pools is a no-op")
assert(pools.hop(1, { 0, 2 }, 1) == 2, "hop from an absent pool goes to the next present one")
assert(pools.hop(1, { 0, 2 }, -1) == 0, "hop -1 from an absent pool")
print("ok")

-- Per-screen workspace pools: pool N owns workspace ids N*10+1 .. N*10+5.
-- Pure arithmetic, no hl.* calls.
local M = {}

local SLOTS = 5

function M.ws_id(pool, slot)
  return pool * 10 + slot
end

-- BenQ is pool 0, built-in panel pool 1, anything else gets the next free
-- pool from 2 up, remembered by name in `assigned`.
function M.pool_for(mon, assigned)
  if (mon.description or ""):sub(1, 8) == "BNQ BenQ" then return 0 end
  if mon.name == "eDP-1" then return 1 end
  if not assigned[mon.name] then
    local n = 0
    for _ in pairs(assigned) do n = n + 1 end
    assigned[mon.name] = 2 + n
  end
  return assigned[mon.name]
end

-- Slot 1..5 of a workspace id within the pool; 1 if the id is not in that pool.
function M.slot_of(workspace_id, pool)
  local slot = workspace_id - pool * 10
  if slot < 1 or slot > SLOTS then return 1 end
  return slot
end

function M.step(slot, delta)
  return math.max(1, math.min(SLOTS, slot + delta))
end

return M

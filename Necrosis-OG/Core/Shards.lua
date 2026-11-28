-- Necrosis OG: a Warlock add-on for World of Warcraft: Forever.
-- Copyright (C) 2026 reckhou
-- A remake of Necrosis LdC (Infernal, Lomig and Nyx).
-- Original sphere skins by Eliah. Includes high-resolution artwork from
-- Necrosis Classic, with thanks to kricklen, and to urnati for the artwork
-- update in 7.2.
--
-- This program is free software. You can redistribute it and modify it
-- under the terms of the GNU General Public License as published by the
-- Free Software Foundation, either version 2 of the License or any later version.
--
-- This program is distributed in the hope that it will be useful, but WITHOUT ANY
-- WARRANTY, including the implied warranties of MERCHANTABILITY and FITNESS FOR
-- A PARTICULAR PURPOSE. See the GNU General Public License for details.
--
-- You should have received a copy of the GNU General Public License with this
-- program. If you did not, see <https://www.gnu.org/licenses/>.
--
-- SPDX-License-Identifier: GPL-2.0-or-later

-- soul shard rules
local _, ns = ...
local Core = ns.Core
local isNumber = Core.IsNumber

Core.SHARD_LIMIT_FALLBACK, Core.SHARD_LIMIT_MAX = 16, 32

Core.SHARD_PULSE, Core.SHARD_PULSE_DIM = 2, 0.15

Core.SHARD_LIMIT_HOLD = 5

Core.SHARD_COMBAT_WAIT = 15
Core.SHARD_DESTROY_GAP = 3
Core.SHARD_COUNT_EVERY = 0.25

Core.SHARD_READY_LEAD = 0.05

function Core.ShardWaitLeft(secondsSinceCombat, secondsSinceDelete)
    local left, total = 0, 0
    if type(secondsSinceCombat) == "number" and Core.SHARD_COMBAT_WAIT - secondsSinceCombat > left then
        left, total = Core.SHARD_COMBAT_WAIT - secondsSinceCombat, Core.SHARD_COMBAT_WAIT
    end
    if type(secondsSinceDelete) == "number" and Core.SHARD_DESTROY_GAP - secondsSinceDelete > left then
        left, total = Core.SHARD_DESTROY_GAP - secondsSinceDelete, Core.SHARD_DESTROY_GAP
    end
    return left, total
end

function Core.ShardAutoAllowed(inCombat, secondsSinceCombat, secondsSinceDelete)
    if inCombat then return false end
    return (Core.ShardWaitLeft(secondsSinceCombat, secondsSinceDelete)) <= 0
end

function Core.ShardLimit(limit, capacity)
    local floor = math.min(capacity or 0, Core.SHARD_LIMIT_MAX)
    if not isNumber(limit) or limit < 0 or limit == math.huge then
        limit = floor > 0 and floor or Core.SHARD_LIMIT_FALLBACK
    end
    return math.max(floor, math.min(Core.SHARD_LIMIT_MAX, math.floor(limit))), floor, Core.SHARD_LIMIT_MAX
end

-- which shard to destory, the last ones over limit
function Core.ShardsToDestroy(slots, total, limit)
    local extra = math.min(#slots, math.max(0, (isNumber(total) and total or 0) - Core.ShardLimit(limit)))
    local chosen = {}
    for i = #slots - extra + 1, #slots do chosen[#chosen + 1] = slots[i] end
    return chosen
end

-- pair shards with free slot in soul bag
function Core.ShardMoves(shards, freeSlots)
    local moves = {}
    for i = 1, math.min(#shards, #freeSlots) do moves[i] = { from = shards[i], to = freeSlots[i] } end
    return moves
end

local function sharesBit(a, b)
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then return true end
        a, b = math.floor(a / 2), math.floor(b / 2)
    end
    return false
end

function Core.IsSoulBag(bagFamily, shardFamily)
    if not isNumber(bagFamily) or not isNumber(shardFamily) or bagFamily <= 0 or shardFamily <= 0 then return false end
    return sharesBit(math.floor(bagFamily), math.floor(shardFamily))
end

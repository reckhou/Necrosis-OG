-- Necrosis OG: a Warlock add-on for World of Warcraft: Forever.
-- Copyright (C) 2026 reckhou
-- A remake of Necrosis LdC 1.5.2a (Infernal, Lomig and Nyx).
-- Original sphere skins by Eliah. Includes high-resolution artwork from
-- Necrosis Classic 7.5, with the 128 x 128 artwork update credited to urnati.
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

-- demo mode helpers
local _, ns = ...
local Core = ns.Core

Core.DEMO = {
    tick = 0.25,
    pause = 4,
    stoneCooldowns = { healthstone = 20, soulstone = 8 },
    controls = { { key = "banish", length = 12 }, { key = "fear", length = 8 }, { key = "enslaveDemon", length = 16 } },
    focusLengths = { banish = 12, seduction = 9, fear = 7, curseOfRecklessness = 14, curseOfWeakness = 11, deathCoil = 6 },
    focusOutOfRange = "deathCoil",
    enemyTargetStep = 3,
    enemies = {
        { portrait = "voidwalker", health = 85, threat = 100,
            slots = { bane = 14, corruption = 10, immolate = 8, siphonLife = 12, demonicBrand = 15, curse = 16 } },
        { portrait = "felhunter", health = 47, threat = 64, target = true, slots = { bane = 9, corruption = 13, curse = 7 } },
        { portrait = "succubus", health = 18, threat = 30, slots = { corruption = 6, immolate = 11 } },
    },
    procs = { "shadowTrance", "decimation", "amplifyCurse", "antiFear" },
    procStep = 2.5,
    sacrificeStep = 3,
    reminderStep = 2.5,
    reminderSizes = { 3, 4, 3, 2, 4, 3 },
    missingStep = 2.5,
    missingSets = { { 1, 2, 3, 4, 5, 6 }, { 2, 3, 5, 6 }, { 3, 6 }, { 6 }, {}, { 1, 3, 4 }, { 1, 2, 4, 6 } },
    shardStep = 0.5,
    threatStep = 0.25, threatPerStep = 5,
}

function Core.DemoBounce(step, top)
    if top <= 0 then return 0 end
    local at = step % (2 * top)
    return at <= top and at or 2 * top - at
end

function Core.DemoProcsOn(step, keys)
    local count = #keys
    local on = {}
    for i, key in ipairs(keys) do
        if (step - (i - 1)) % (2 * count) < count then on[key] = true end
    end
    return on
end

function Core.DemoRemindersOn(step, keys, sizes)
    local count = #keys
    local on = {}
    if count == 0 or #sizes == 0 then return on end
    local size = math.min(sizes[step % #sizes + 1], count)
    local newest = step % count
    for back = 0, size - 1 do on[keys[(newest - back) % count + 1]] = true end
    return on
end

-- pick the first known family that is missing in demo, return its place
function Core.DemoMissingNext(demoSet, allFamilies, knownFamilies)
    if type(demoSet) ~= "table" or type(allFamilies) ~= "table" or type(knownFamilies) ~= "table" then return nil end
    local missing = {}
    for _, index in ipairs(demoSet) do
        local family = allFamilies[index]
        if family and family.key then missing[family.key] = true end
    end
    for place, family in ipairs(knownFamilies) do
        if missing[family.key] then return place end
    end
    return nil
end

-- color at x on the points list { x, r, g, b }, blend like game curve
function Core.ColourAt(points, x)
    local first, last = points[1], points[#points]
    if x <= first[1] then return first[2], first[3], first[4] end
    if x >= last[1] then return last[2], last[3], last[4] end
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        if x <= b[1] then
            local t = (x - a[1]) / (b[1] - a[1])
            return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
        end
    end
    return last[2], last[3], last[4]
end

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

-- rules for soulstone target list
local _, ns = ...
local Core = ns.Core

-- full name with surname or realm
function Core.FullName(name, second, surnames)
    if type(name) ~= "string" or name == "" then return nil end
    if type(second) ~= "string" or second == "" then return name end
    return name .. (surnames and " " or "-") .. second
end

function Core.SamePlayer(a, b)
    if type(a) ~= "string" or type(b) ~= "string" or a == "" or b == "" then return false end
    if a == b then return true end
    local short, long = a, b
    if #short > #long then short, long = long, short end
    if string.find(short, "[ %-]") then return false end
    local after = string.sub(long, #short + 1, #short + 1)
    return string.sub(long, 1, #short) == short and (after == " " or after == "-")
end

function Core.ListsPlayer(names, name)
    for _, listed in ipairs(names) do
        if Core.SamePlayer(listed, name) then return true end
    end
    return false
end

Core.SOULSTONE_REVIVERS = { PRIEST = true, PALADIN = true, SHAMAN = true, DRUID = true }
Core.SOULSTONE_ROWS = 20

-- who to show in the list, healer and tank first
function Core.SoulstoneCandidates(members, isRaid)
    local assigned = false
    for _, member in ipairs(members) do
        if member.role == "TANK" or member.role == "HEALER" then assigned = true end
    end
    local tanks, healers, revivers = {}, {}, {}
    for _, member in ipairs(members) do
        if member.role == "TANK" or (isRaid and member.mainTank == true and member.role ~= "HEALER") then
            tanks[#tanks + 1] = member
        elseif assigned then
            if member.role == "HEALER" then healers[#healers + 1] = member end
        elseif Core.SOULSTONE_REVIVERS[member.class] == true then
            revivers[#revivers + 1] = member
        end
    end
    local function ByName(a, b) return string.lower(a.name or "") < string.lower(b.name or "") end
    local list = {}
    for _, group in ipairs({ tanks, healers, revivers }) do
        table.sort(group, ByName)
        for _, member in ipairs(group) do
            if #list < Core.SOULSTONE_ROWS then list[#list + 1] = member end
        end
    end
    return list
end

function Core.SoulstoneFooters(listed, previous, current)
    local before, now
    if previous and not Core.ListsPlayer(listed, previous) then before = previous end
    if current and not Core.ListsPlayer(listed, current) and not (before and Core.SamePlayer(before, current)) then
        now = current
    end
    return before, now
end

-- macro text of one row
function Core.SoulstoneShortcutMacro(items, firstId, name, how)
    local text = ""
    local unit = "[@target,help,nodead] "
    if how == "self" then
        text = "/target player"
        unit = "[@player] "
    elseif how ~= "target" then
        if type(name) ~= "string" or name == "" then return nil end
        text = "/cleartarget\n/targetexact " .. name
    end
    local order, seen = {}, {}
    if firstId then order[1], seen[firstId] = firstId, true end
    for i = #items, 1, -1 do
        if not seen[items[i]] then order[#order + 1], seen[items[i]] = items[i], true end
    end
    for _, id in ipairs(order) do
        local longer = (text == "" and "" or text .. "\n") .. "/use " .. unit .. "item:" .. id
        if #longer > Core.MACRO_LIMIT then break end
        text = longer
    end
    return text
end

function Core.SoulstoneMismatchWarning(inGroup, previous, castTarget, fromShortcut)
    if not inGroup or fromShortcut or type(previous) ~= "string" or previous == "" then return false end
    if type(castTarget) ~= "string" or castTarget == "" then return false end
    return not Core.SamePlayer(previous, castTarget)
end

Core.SOULSTONE_SHORTCUT_CLICK = [[
    if button ~= "RightButton" or IsModifierKeyDown() or not self:GetAttribute("ssShortcut") then return end
    local frame = self:GetFrameRef("shortcut")
    if frame:IsShown() then
        frame:Hide()
    else
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOM", self, "TOP", 0, 8)
        frame:Show()
    end
    return false
]]

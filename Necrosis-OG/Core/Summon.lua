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

-- rules of the summon queue
local _, ns = ...
local Core = ns.Core

Core.SUMMON_HELPERS = 2
Core.SUMMON_ROWS = 20
Core.SUMMON_OFFER_SECONDS = 120
Core.SUMMON_TIMEOUT = 600
Core.SUMMON_MINE_SECONDS = 120
Core.SUMMON_NONE_SECONDS = 10
Core.SUMMON_SHARD_SECONDS = 30

Core.SUMMON_STATUS = { none = 0, pending = 1, accepted = 2, declined = 3 }
local MAP_DUNGEON = 4
Core.SUMMON_MAP_DUNGEON = MAP_DUNGEON

function Core.FoldWidth(text)
    text = string.gsub(text, "\239\188([\144-\153])", function(c) return string.char(string.byte(c) - 96) end)
    text = string.gsub(text, "\239\188([\161-\186])", function(c) return string.char(string.byte(c) - 96) end)
    text = string.gsub(text, "\239\189([\129-\154])", function(c) return string.char(string.byte(c) - 32) end)
    text = string.gsub(text, "\239\188\140", ",")
    return string.lower(text)
end

-- request words, one per line
function Core.SummonWords(text)
    local words = {}
    if type(text) ~= "string" then return words end
    for word in string.gmatch(Core.FoldWidth(text), "[^,;%s]+") do words[#words + 1] = word end
    return words
end

local function Escape(word) return (string.gsub(word, "%p", "%%%0")) end

-- if chat message is asking for summon
function Core.SummonMatches(message, words)
    if type(message) ~= "string" then return false end
    local line = Core.FoldWidth(message)
    for _, word in ipairs(words) do
        if string.find(word, "[\128-\255]") then
            if string.find(line, word, 1, true) then return true end
        elseif string.find(line, "%f[%w]" .. Escape(word) .. "%f[%W]") then
            return true
        end
    end
    return false
end

function Core.NewSummonQueue()
    return { entries = {}, mine = {} }
end

local function Id(member) return member.guid or member.name end

function Core.SummonFind(queue, member)
    for i, entry in ipairs(queue.entries) do
        if member.guid and entry.guid then
            if entry.guid == member.guid then return entry, i end
        elseif Core.SamePlayer(entry.name, member.name) then
            return entry, i
        end
    end
    return nil
end

local function Add(queue, member, state, now)
    local entry = { guid = member.guid, name = member.name, class = member.class, zone = member.zone,
        state = state, addedAt = now }
    queue.entries[#queue.entries + 1] = entry
    return entry
end

function Core.SummonRetryable(entry) return entry.state == "declined" or entry.state == "expired" end

-- add player to queue, true when he start waiting
function Core.SummonRequest(queue, member, now)
    local entry, index = Core.SummonFind(queue, member)
    if entry then
        if not Core.SummonRetryable(entry) then return false end
        table.remove(queue.entries, index)
    end
    Add(queue, member, "waiting", now)
    return true
end

function Core.SummonClicked(queue, member, now)
    queue.mine[Id(member)] = now
end

local function Mine(queue, member, now)
    local at = queue.mine[Id(member)]
    return at ~= nil and now - at <= Core.SUMMON_MINE_SECONDS
end

function Core.SummonStatus(queue, member, status, now)
    local S = Core.SUMMON_STATUS
    local entry = Core.SummonFind(queue, member)
    if status == S.pending then
        if entry and entry.state == "offered" and not entry.noneAt then return false end
        entry = entry or Add(queue, member, "offered", now)
        entry.state, entry.offeredAt, entry.endsAt = "offered", now, now + Core.SUMMON_OFFER_SECONDS
        entry.noneAt, entry.closedAt = nil, nil
        entry.byOther = not Mine(queue, member, now)
        entry.wasAway = member.visible ~= true
        return true
    end
    if not entry then return false end
    if status == S.accepted then
        if entry.state == "accepted" then return false end
        entry.state, entry.noneAt = "accepted", nil
        entry.offeredAt = entry.offeredAt or now
        entry.endsAt = entry.endsAt or now + Core.SUMMON_OFFER_SECONDS
        return true
    elseif status == S.declined then
        if entry.state == "declined" then return false end
        entry.state, entry.closedAt, entry.noneAt = "declined", now, nil
        return true
    elseif status == S.none and entry.state == "offered" then
        entry.noneAt = entry.noneAt or now
    end
    return false
end

function Core.SummonDismiss(queue, entry)
    for i, listed in ipairs(queue.entries) do
        if listed == entry then
            table.remove(queue.entries, i)
            return true
        end
    end
    return false
end

-- update queue by time, remove who already arrived
function Core.SummonTick(queue, now, member)
    local changed = false
    for i = #queue.entries, 1, -1 do
        local entry = queue.entries[i]
        local now_ = member(entry)
        local remove = now_ == nil
        local state = entry.state
        if now_ then
            entry.zone, entry.class = now_.zone or entry.zone, now_.class or entry.class
            local offline = now_.online == false
            if offline ~= (entry.offline == true) then entry.offline, changed = offline, true end
            local summoned = state == "offered" or state == "accepted" or state == "expired"
            if summoned and now_.visible ~= true then entry.wasAway = true end
            if state == "accepted" and now_.phased then
                entry.state, entry.clearAt = "shard", now + Core.SUMMON_SHARD_SECONDS
            elseif summoned and now_.visible == true and (state == "accepted" or entry.wasAway) then
                remove = true
            elseif state == "offered" and (now >= entry.endsAt
                or (entry.noneAt and now - entry.noneAt >= Core.SUMMON_NONE_SECONDS)) then
                entry.state, entry.closedAt = "expired", now
            elseif state == "accepted" and now >= entry.endsAt then
                entry.state, entry.closedAt = "expired", now
            elseif state == "shard" and now >= entry.clearAt then
                remove = true
            elseif state == "waiting" and now - entry.addedAt >= Core.SUMMON_TIMEOUT then
                remove = true
            elseif Core.SummonRetryable(entry) and now - (entry.closedAt or now) >= Core.SUMMON_TIMEOUT then
                remove = true
            end
        end
        if remove then
            table.remove(queue.entries, i)
            changed = true
        elseif entry.state ~= state then
            changed = true
        end
    end
    return changed
end

function Core.SummonLists(queue)
    local waiting, summoned = {}, {}
    for _, entry in ipairs(queue.entries) do
        if entry.state == "waiting" then waiting[#waiting + 1] = entry else summoned[#summoned + 1] = entry end
    end
    return waiting, summoned
end

-- who to summon next
function Core.SummonNext(waiting, summoned, canCast)
    for _, entry in ipairs(waiting) do
        if canCast(entry) then return entry end
    end
    for _, entry in ipairs(summoned) do
        if Core.SummonRetryable(entry) and canCast(entry) then return entry end
    end
    return nil
end

-- reason why this member cannot be summoned
function Core.SummonBlocked(me, member)
    if member.online == false then return "SUMMON_OFFLINE" end
    if member.dead == true then return "SUMMON_DEAD" end
    if me.inInstance == false and member.inDungeon == true then return "SUMMON_IN_INSTANCE" end
    if me.inInstance == true then
        if member.inDungeon == false then return "SUMMON_OTHER_INSTANCE" end
        if me.instance and member.instance and me.instance ~= member.instance then return "SUMMON_OTHER_INSTANCE" end
    end
    return nil
end

function Core.SummonAway(members, queue)
    local away = {}
    for _, member in ipairs(members) do
        if member.visible ~= true and not Core.SummonFind(queue, member) then away[#away + 1] = member end
    end
    table.sort(away, function(a, b) return a.name:lower() < b.name:lower() end)
    return away
end

function Core.SummonHelpers(members)
    local count = 0
    for _, member in ipairs(members) do
        if member.visible == true and member.online ~= false and member.dead ~= true then count = count + 1 end
    end
    return count
end

function Core.SummonClock(seconds)
    seconds = math.max(0, math.ceil(seconds or 0))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- macro text to summon the unit
function Core.SummonMacro(unit, spellName)
    if type(unit) ~= "string" or type(spellName) ~= "string" then return nil end
    local test = "[@" .. unit .. ",group,nocombat] "
    return "/target " .. test .. "\n/cast " .. test .. spellName
end

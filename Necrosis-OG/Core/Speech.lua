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

-- speech rules
local _, ns = ...
local Core = ns.Core

Core.SPEECH_SUBJECTS = { "imp", "voidwalker", "succubus", "incubus", "felhunter", "inferno", "ritualOfDoom",
    "soulstone", "ritualOfSummoning", "mount" }
Core.SPEECH_MAX = 100
Core.SPEECH_COOLDOWN = 5

local function TextSet(text, key)
    local emote, line = rawget(text, key .. "EMOTE"), rawget(text, key .. "LINE")
    if emote == nil and line == nil then return nil end
    return { emote = emote or "", line = line or "" }
end

function Core.SpeechSets(subject, saved, text)
    local sets = {}
    local own = type(saved) == "table" and saved[subject]
    if type(own) == "table" then
        for i = 1, math.min(#own, Core.SPEECH_MAX) do
            local set = type(own[i]) == "table" and own[i] or {}
            sets[i] = { emote = tostring(set.emote or ""), line = tostring(set.line or "") }
        end
        return sets
    end
    for i = 1, Core.SPEECH_MAX do
        local set = TextSet(text, "SPEECH_" .. string.upper(subject) .. "_" .. i .. "_")
        if not set then break end
        sets[i] = set
    end
    return sets
end

function Core.PresetName(set, limit, empty)
    local text = (set.line ~= "" and set.line) or set.emote
    if text == "" then return empty end
    if #text <= limit then return text end
    local cut = limit
    while cut > 0 and string.byte(text, cut + 1) and string.byte(text, cut + 1) >= 128 and string.byte(text, cut + 1) < 192 do
        cut = cut - 1
    end
    return string.sub(text, 1, cut) .. "..."
end

-- pick random set, not same with last one if can
function Core.PickSpeech(sets, last, random)
    local usable = {}
    for i, set in ipairs(sets) do
        if set.emote ~= "" or set.line ~= "" then usable[#usable + 1] = i end
    end
    if #usable == 0 then return nil end
    if #usable > 1 then
        for n = #usable, 1, -1 do if usable[n] == last then table.remove(usable, n) end end
    end
    return usable[random(#usable)]
end

-- replace <player>, <target> and <pet> in the line
function Core.FillSpeech(text, names, fallback)
    local function Name(key)
        local value = names[key]
        if type(value) ~= "string" or value == "" then return fallback[key] end
        return value
    end
    text = string.gsub(text, "<player>", function() return Name("player") end)
    text = string.gsub(text, "<target>", function() return Name("target") end)
    text = string.gsub(text, "<pet>", function() return Name("pet") end)
    return text
end

Core.SPEECH_PROMO_CHANCE = 0.1

function Core.SpeechPromo(subject, text)
    return TextSet(text, "SPEECH_" .. string.upper(subject) .. "_PROMO_")
end

function Core.ChoosePromo(promo, random)
    return promo ~= nil and random() < Core.SPEECH_PROMO_CHANCE
end

-- party channel fall back to say when not in group
function Core.SpeechChannel(choice, inGroup)
    if choice == "YELL" then return "YELL" end
    if choice == "PARTY" and inGroup then return "PARTY" end
    return "SAY"
end

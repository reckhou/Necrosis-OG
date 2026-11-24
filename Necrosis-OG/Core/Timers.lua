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

-- rules of timer and enemy list, not use game api
local _, ns = ...
local Core = ns.Core
local isNumber = Core.IsNumber

Core.TIMER_GAP = 6 -- px between row
Core.TIMER_WARN_BEFORE = 3 -- sec before control end, play warn sound
Core.TIMER_RESIST_WINDOW = 1.5 -- sec after cast that resist text remove timer

Core.TIMER_LISTS = { "focus", "multi" }

Core.TIMER_LIST_SETTINGS = { "timers.focusOn", "timers.focusOff", "timers.controlOn", "timers.multiOn", "timers.grow",
    "timers.trackOff", "timers.trackOrder", "timers.plateReminder.on" }

Core.MISSING_SETTINGS = { "timers.trackOff", "timers.trackOrder", "timers.targetReminder", "timers.plateReminder" }

Core.BAR_HIGHLIGHT_SETTINGS = { "timers.trackOff", "timers.trackOrder", "timers.barHighlight", "timers.wrackHelper" }

Core.SACRIFICE_SETTINGS = { "alerts.sacrificeOn", "alerts.sacrificeAt", "procBar.on" }
Core.SACRIFICE_THRESHOLDS = { 10, 20, 30, 40, 50 }

function Core.SacrificeThresholdOrDefault(value)
    for _, each in ipairs(Core.SACRIFICE_THRESHOLDS) do
        if value == each then return value end
    end
    return Core.DEFAULTS.alerts.sacrificeAt
end

function Core.SacrificeCurvePoints(percent)
    return { { 0, 1 }, { Core.SacrificeThresholdOrDefault(percent) / 100, 0 } }
end

Core.TARGET_OFFSET_MIN, Core.TARGET_OFFSET_MAX = -1000, 1000

function Core.ClampTargetOffset(value, fallback)
    return Core.ClampValue(value, Core.TARGET_OFFSET_MIN, Core.TARGET_OFFSET_MAX, 1, fallback or 0)
end

Core.PLATE_OFFSET_MIN, Core.PLATE_OFFSET_MAX, Core.PLATE_OFFSET_STEP = -100, 100, 1

function Core.ClampPlateOffset(value, fallback)
    return Core.ClampValue(value, Core.PLATE_OFFSET_MIN, Core.PLATE_OFFSET_MAX, Core.PLATE_OFFSET_STEP, fallback or 0)
end

Core.STYLED_LISTS = { multi = true }

function Core.TimerScale(timers, key)
    local scales = type(timers) == "table" and timers.scales
    return Core.ClampScale(type(scales) == "table" and scales[key] or nil)
end

-- cut the name to max char and add "..."
function Core.ShortName(name, max)
    if type(name) ~= "string" then return name end
    local count = 0
    for i = 1, #name do
        local byte = name:byte(i)
        if byte < 128 or byte >= 192 then
            count = count + 1
            if count > max then return name:sub(1, i - 1) .. "..." end
        end
    end
    return name
end

-- multi enemy list
Core.MULTI_LINES = 8
Core.MULTI_NAME_CHARS = 14
Core.MULTI_WIDTH = 206
Core.MULTI_HEAD = 20
Core.MULTI_HEALTH_BAR = 16
Core.MULTI_HEALTH_WIDTH = 30
Core.MULTI_THREAT_WIDTH = 42
Core.MULTI_THREAT_ICON = 14

Core.THREAT_ICON = "Interface\\Icons\\Spell_Nature_Reincarnation"
Core.MULTI_ICON = 28 -- debuff icon size
Core.ENEMY_TIME_SIZE = 14
Core.MULTI_ICON_GAP = 3
Core.MULTI_ROW_GAP = 2
Core.MULTI_BLOCK = Core.MULTI_HEAD + Core.MULTI_ROW_GAP + Core.MULTI_ICON
Core.MULTI_TARGET_SCALE = 1.08
Core.MULTI_TARGET_MARK_SIZE = 19
Core.MULTI_ROW = 18

Core.ROW_BACKDROP = { 0, 0, 0, 0.35 }
Core.ROW_TARGET_TINT = { 0.6, 0.25, 1, 0.6 }
Core.MULTI_INTERVAL = 0.5

Core.FLASH_SECONDS, Core.FLASH_LOW, Core.FOCUS_DIM = 1, 0.5, 0.35

-- line keep this sec after nameplate is gone
Core.MULTI_FROZEN_SECONDS = 30

Core.EARLY_CAST_SECONDS = 5

-- health color from red to yellow to green, { fraction, r, g, b }
Core.HEALTH_COLOUR_POINTS = { { 0, 1, 0, 0 }, { 0.5, 1, 1, 0 }, { 1, 0, 1, 0 } }

Core.FLASH_LEAD_SECONDS = 5

Core.FLASH_LEAD_BY_SPELL = { baneOfAgony = 2, baneOfDoom = 0, corruption = 4, siphonLife = 2 }

Core.FLASH_LEAD_BY_FAMILY = { bane = 2, corruption = 4, siphonLife = 2 }

Core.LATENCY_STEP = 0.05
Core.LATENCY_MAX = 1
Core.LATENCY_CHECK_SECONDS = 10

function Core.LatencySeconds(ms)
    if type(ms) ~= "number" or ms ~= ms or ms <= 0 then return 0 end
    local steps = math.ceil(math.min(ms / 1000, Core.LATENCY_MAX) / Core.LATENCY_STEP - 1e-9)
    return steps * Core.LATENCY_STEP
end

function Core.AddLatency(lead, latency)
    if lead <= 0 then return lead end
    return lead + (latency or 0)
end

function Core.FlashLead(family, spellKey)
    local lead = spellKey and Core.FLASH_LEAD_BY_SPELL[spellKey]
    if lead == nil and family then lead = Core.FLASH_LEAD_BY_FAMILY[family] end
    if lead == nil then lead = Core.FLASH_LEAD_SECONDS end
    return lead
end

Core.FLASH_TEXT_COLOUR = { 1, 0.35, 0.2 }
Core.FLASH_FAR_SECONDS = 86400

Core.MISSING_FLASH_STEP = 0.15

function Core.FlashFactor(time, phase)
    local part = (time / Core.FLASH_SECONDS + (phase or 0)) % 1
    local down = part < 0.5 and part * 2 or (1 - part) * 2
    return 1 - (1 - Core.FLASH_LOW) * down
end

-- curve point of time text colour, { sec left, r, g, b, alpha }
function Core.TimeFlashPoints(lead)
    lead = lead or Core.FLASH_LEAD_SECONDS
    if lead <= 0 then return { { 0, 1, 1, 1, 1 }, { Core.FLASH_FAR_SECONDS, 1, 1, 1, 1 } } end
    local low = Core.FLASH_LOW
    local half = Core.FLASH_SECONDS / 2
    local colour = Core.FLASH_TEXT_COLOUR
    local function point(x, opacity)
        local white = math.min(1, x / lead)
        local function mix(c) return c + (1 - c) * white end
        return { x, mix(colour[1]), mix(colour[2]), mix(colour[3]), opacity }
    end
    local points = {}
    for step = 0, math.floor(lead / half + 1e-9) do
        points[#points + 1] = point(step * half, step % 2 == 0 and 1 or low)
    end
    local last = points[#points]
    if last[1] < lead - 1e-9 then points[#points + 1] = point(lead, 1) else last[5] = 1 end
    points[#points + 1] = { Core.FLASH_FAR_SECONDS, 1, 1, 1, 1 }
    return points
end

Core.MULTI_SKIP_TYPES = { [11] = true }

-- target go first, then sort by nameplate index, max to MULTI_LINES
function Core.OrderNameplates(candidates)
    local ordered = {}
    for _, candidate in ipairs(candidates) do ordered[#ordered + 1] = candidate end
    table.sort(ordered, function(a, b)
        if a.target ~= b.target then return a.target == true end
        return a.index < b.index
    end)
    for i = #ordered, Core.MULTI_LINES + 1, -1 do ordered[i] = nil end
    return ordered
end

function Core.RowChain(down, controls, lines)
    local chain = {}
    local first, second = controls, lines
    if not down then first, second = lines, controls end
    for _, row in ipairs(first) do chain[#chain + 1] = row end
    for _, row in ipairs(second) do chain[#chain + 1] = row end
    return chain
end

function Core.NameplateIndex(unit)
    if type(unit) ~= "string" then return nil end
    local number = string.match(unit, "^nameplate(%d+)$")
    return number and tonumber(number) or nil
end

Core.DURATION_WORDS = {
    { word = "sec", seconds = 1 }, { word = "sek", seconds = 1 }, { word = "seg", seconds = 1 },
    { word = "s", seconds = 1, whole = true },
    { word = "min", seconds = 60 },
    { word = "сек", seconds = 1 }, { word = "мин", seconds = 60 },
    { word = "초", seconds = 1 }, { word = "분", seconds = 60 },
    { word = "秒", seconds = 1 }, { word = "分钟", seconds = 60 }, { word = "分鐘", seconds = 60 },
}

local function LowerASCII(text) return (string.gsub(text, "[A-Z]", string.lower)) end
local function IsLatin(word) return string.find(word, "[\128-\255]") == nil end

function Core.AddDurationWord(format, seconds)
    if type(format) ~= "string" or not isNumber(seconds) then return end
    local word = string.gsub(format, "%%[%d%.]*[dfF]", "")
    word = LowerASCII((string.gsub(string.gsub(word, "\194\160", ""), "[ \t\r\n%.:]", "")))
    if word == "" then return end
    for _, entry in ipairs(Core.DURATION_WORDS) do
        if entry.word == word then return end
    end
    local latin = IsLatin(word)
    if latin and string.find(word, "[^a-z]") then return end
    table.insert(Core.DURATION_WORDS, { word = word, seconds = seconds, whole = latin and #word < 3 or nil })
end

local SPACES = { "\194\160", "\226\128\175", "\226\128\137", "\226\128\139" }

local function SkipSpaces(text, at)
    while true do
        local plain = string.match(text, "^[ \t\r\n]+", at)
        if plain then
            at = at + #plain
        else
            local moved = false
            for _, space in ipairs(SPACES) do
                if string.sub(text, at, at + #space - 1) == space then at, moved = at + #space, true; break end
            end
            if not moved then return at end
        end
    end
end

local function UnitAt(text, at)
    local lower = LowerASCII(string.sub(text, at, at + 23))
    local letters = string.match(lower, "^[a-z]*")
    for _, entry in ipairs(Core.DURATION_WORDS) do
        local word = entry.word
        if IsLatin(word) then
            if (entry.whole and letters == word) or (not entry.whole and string.sub(letters, 1, #word) == word) then
                return entry.seconds
            end
        elseif string.sub(lower, 1, #word) == word then
            return entry.seconds
        end
    end
    return nil
end

-- get spell lengths from description, in sec
function Core.DurationsIn(description)
    local found = {}
    if type(description) ~= "string" then return found end
    for number, after in string.gmatch(description, "(%d+[%.,]?%d*)()") do
        local unit = UnitAt(description, SkipSpaces(description, after))
        local value = unit and tonumber((string.gsub(string.gsub(number, ",", "."), "%.$", "")))
        if value and value > 0 then found[#found + 1] = value * unit end
    end
    return found
end

function Core.ParseSpellLength(description)
    return Core.DurationsIn(description)[1]
end

function Core.ParseDebuffLength(description)
    local best
    for _, seconds in ipairs(Core.DurationsIn(description)) do
        if not best or seconds > best then best = seconds end
    end
    return best
end

function Core.ControlSpellKeys()
    local keys = {}
    for _, key in ipairs(Core.CONTROL_SPELLS) do
        for _, id in ipairs(Core.SPELLS[key]) do keys[id] = key end
    end
    return keys
end

Core.CUSTOM_TIMER_MAX = 3600

function Core.CustomTimerLength(seconds)
    if not isNumber(seconds) then return nil end
    seconds = math.floor(seconds)
    if seconds < 1 or seconds > Core.CUSTOM_TIMER_MAX then return nil end
    return seconds
end

-- split /nog args, "timer 200 Pull" -> "timer", "200 Pull"
function Core.SplitCommand(message)
    if type(message) ~= "string" then return "", "" end
    local command, rest = message:match("^%s*(%S*)%s*(.-)%s*$")
    return (command or ""):lower(), rest or ""
end

function Core.ParseTimerCommand(rest)
    if type(rest) ~= "string" then return nil, nil end
    local seconds, name = rest:match("^(%d+)%s*(.-)%s*$")
    if not seconds then return nil, nil end
    return Core.CustomTimerLength(tonumber(seconds)), name ~= "" and name or nil
end

function Core.TimerText(remaining)
    if not isNumber(remaining) or remaining < 0 then remaining = 0 end
    local seconds = math.ceil(remaining)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

Core.TIMER_TEXT_RULES = {
    { threshold = 0, step = 1, rounding = "Up", format = "%d:%02d",
        components = { { div = 60, step = 1, rounding = "Down" }, { mod = 60, step = 1, rounding = "Down" } } },
}

Core.RESIST_TEXTS = { MISS = true, RESIST = true, IMMUNE = true, EVADE = true }

function Core.IsResist(action, school)
    return Core.RESIST_TEXTS[action] == true and school ~= 1
end

function Core.IsImmuneText(action, school)
    return action == "IMMUNE" and school ~= 1
end

function Core.SortTimers(timers)
    table.sort(timers, function(a, b)
        local endA, endB = a.start + a.length, b.start + b.length
        if endA ~= endB then return endA < endB end
        return a.order < b.order
    end)
    return timers
end

Core.ALERT_SIZE = 62

Core.CONTROL_ICON_SCALE = Core.ALERT_SIZE / Core.BUTTON_SIZE

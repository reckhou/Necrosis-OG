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

-- timers and texts the game draw by itself
local _, ns = ...
local Core = ns.Core

local Durations = {}
ns.Durations = Durations

local function EnumValue(enum, name, fallback)
    if type(enum) == "table" and enum[name] ~= nil then return enum[name] end
    return fallback
end

-- call method if exist, true when it ran
local function Call(object, method, ...)
    if not object then return false end
    local ok, fn = pcall(function() return object[method] end)
    if not ok or type(fn) ~= "function" then return false end
    return (pcall(fn, object, ...))
end

local ROUNDING = { Nearest = 0, Up = 1, Down = 2 }

local function Rounding(name)
    return EnumValue(Enum and Enum.NumericRuleFormatRounding, name, ROUNDING[name])
end

local function Breakpoint(rule)
    local copy = { threshold = rule.threshold, step = rule.step, format = rule.format }
    if rule.rounding then copy.rounding = Rounding(rule.rounding) end
    if rule.components then
        copy.components = {}
        for i, part in ipairs(rule.components) do
            copy.components[i] = { div = part.div, mod = part.mod, step = part.step,
                rounding = part.rounding and Rounding(part.rounding) or nil }
        end
    end
    return copy
end

local RULES = { timer = Core.TIMER_TEXT_RULES, cooldown = Core.COOLDOWN_TEXT_RULES, aura = Core.AURA_TEXT_RULES }
local formatters = {}

-- formatter for "timer" (0:07) or "cooldown" (7, 2m) text
local function Formatter(kind)
    if formatters[kind] ~= nil then return formatters[kind] or nil end
    local util = C_StringUtil
    local ok, formatter = pcall(util and util.CreateNumericRuleFormatter)
    local fine = ok and formatter ~= nil
    if fine then
        for _, rule in ipairs(RULES[kind]) do
            if not Call(formatter, "AddBreakpoint", Breakpoint(rule)) then fine = false end
        end
    end
    if not fine then
        ok, formatter = pcall(util and util.CreateSecondsFormatter)
        if not ok then formatter = nil end
    end
    formatters[kind] = formatter or false
    return formatter
end

Durations.Formatter = Formatter

function Durations.New()
    local util = C_DurationUtil
    local ok, duration = pcall(util and util.CreateDuration)
    return ok and duration or nil
end

function Durations.Set(duration, start, length)
    return Call(duration, "SetTimeFromStart", start, length)
end

function Durations.SetEnd(duration, ending, length)
    return Call(duration, "SetTimeFromEnd", ending, length)
end

-- status bar run down from full to empty
function Durations.Bar(statusBar, duration)
    local interpolation = EnumValue(Enum and Enum.StatusBarInterpolation, "Immediate", 0)
    local direction = EnumValue(Enum and Enum.StatusBarTimerDirection, "RemainingTime", 1)
    return Call(statusBar, "SetTimerDuration", duration, interpolation, direction)
end

-- bind time left text to font string
function Durations.Text(fontString, kind, zeroText)
    local util = C_DurationUtil
    local ok, binding = pcall(util and util.CreateDurationTextBinding)
    if not ok or not binding then return nil end
    Call(binding, "SetFontString", fontString)
    local formatter = Formatter(kind)
    if formatter then Call(binding, "SetFormatter", formatter) end
    Call(binding, "SetZeroDurationText", zeroText)
    Call(binding, "SetExpiredText", zeroText)
    Call(binding, "SetUpdateInterval", 0.1)
    Call(binding, "SetEnabled", false)
    return binding
end

function Durations.ShowText(binding, duration)
    if not binding then return end
    Call(binding, "SetDuration", duration)
    Call(binding, "SetEnabled", true)
    Call(binding, "UpdateFontString")
end

function Durations.HideText(binding, fontString)
    Call(binding, "SetEnabled", false)
    if fontString then fontString:SetText("") end
end

-- color curve from points { x, r, g, b [, a] }, nil if game refuse
function Durations.ColourCurve(points)
    local ok, curve = pcall(function()
        local made = C_CurveUtil.CreateColorCurve()
        for _, p in ipairs(points) do made:AddPoint(p[1], CreateColor(p[2], p[3], p[4], p[5] or 1)) end
        return made
    end)
    return ok and curve or nil
end

function Durations.SetCurvePoints(curve, points)
    return (pcall(function()
        curve:ClearPoints()
        for _, p in ipairs(points) do curve:AddPoint(p[1], CreateColor(p[2], p[3], p[4], p[5] or 1)) end
    end))
end

function Durations.RemainingProperty()
    return EnumValue(Enum and Enum.DurationTextBindingProperty, "RemainingDuration", 0)
end

function Durations.ColourText(binding, points)
    local curve = Durations.ColourCurve(points)
    return curve ~= nil and Call(binding, "SetTextColorCurve", curve, Durations.RemainingProperty())
end

function Durations.ColourByLength(holder, length)
    local key = length or 0
    if holder.colouredFor == key then return end
    holder.colouredFor = Durations.ColourText(holder.binding, Core.CooldownTextPoints(length)) and key or nil
end

-- dark cooldown swipe on the frame, no number
function Durations.NewSwipe(frame, options)
    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, frame, "CooldownFrameTemplate")
    if not ok then
        if options.optional then return nil end
        cooldown = CreateFrame("Cooldown", nil, frame)
    end
    cooldown:ClearAllPoints()
    if options.place then
        options.place(cooldown)
    else
        local size = options.size or Core.BUTTON_SIZE
        cooldown:SetPoint("CENTER", frame, "CENTER", 0, 0)
        cooldown:SetSize(size * Core.SWIPE_WIDTH, size * Core.SWIPE_HEIGHT)
    end
    if options.level then cooldown:SetFrameLevel(frame:GetFrameLevel() + options.level) end
    local shape = options.shape or "ring"
    if shape == "ring" then pcall(cooldown.SetSwipeTexture, cooldown, Core.UiTexture("Swipe")) end
    if shape == "mask" then pcall(cooldown.SetSwipeTexture, cooldown, Core.UiTexture("Mask")) end
    pcall(cooldown.SetSwipeColor, cooldown, 0, 0, 0, 0.7)
    pcall(cooldown.SetUseCircularEdge, cooldown, shape ~= "square")
    pcall(cooldown.SetDrawEdge, cooldown, true)
    pcall(cooldown.SetHideCountdownNumbers, cooldown, true)
    if options.reverse then pcall(cooldown.SetReverse, cooldown, true) end
    return cooldown
end

local TIME_FONT = "SystemFont_Shadow_Small2_Outline"

function Durations.TimeFont(size)
    return ns.Media.Font(TIME_FONT, size)
end

function Durations.NewTimeText(frame, above, font)
    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(((above and above:GetFrameLevel()) or frame:GetFrameLevel()) + 1)
    local text = overlay:CreateFontString(nil, "OVERLAY", font or Durations.TimeFont())
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetTextColor(1, 1, 1)
    return text, overlay
end

-- call callback(key) once when key's time come
function Durations.NewSchedule(callback)
    local timer = C_Timer
    local ok, map = pcall(timer and timer.NewTimedSignalMap, callback)
    if not ok then map = nil end
    local schedule = {}
    function schedule.At(key, time) Call(map, "SignalAt", key, time) end
    function schedule.Cancel(key) Call(map, "CancelSignal", key) end
    return schedule
end

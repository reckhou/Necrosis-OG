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

-- control timers like fear and banish
local _, ns = ...
local Core, Text = ns.Core, ns.Text
local Durations = ns.Durations

local Timers = {}
ns.Timers = Timers

local SOUND_PATH = Core.MEDIA_PATH .. "Sounds\\"
local END_SOUNDS = { enslaveDemon = "EnslaveDemonEnd-En.mp3" }
local WARNING_SOUND = 8959
local COLOURS = { control = { 0.9, 0.5, 0.1 } }

local lists = {}
local controlKeys = Core.ControlSpellKeys()
local lengths = {}
local lastSent
local targetSerial = 0
local order = 0
local running = {}
local ends, warnings

local IsSecret, Plain, SpellName = ns.Game.IsSecret, ns.Game.Plain, ns.Game.SpellName

-- sound and yellow line before control end
local function Warn(timer)
    if not ns.db.timers.warnSound or not ns.db.timers.controlOn or ns.db.procBar.on == false then return end
    if type(PlaySound) == "function" and not ns.Silent() then
        pcall(PlaySound, type(SOUNDKIT) == "table" and SOUNDKIT.RAID_WARNING or WARNING_SOUND)
    end
    local target = timer.target
    local text
    if not IsSecret(target) and type(target) == "string" and target ~= "" then
        text = string.format(Text.TIMER_ENDING_ON, timer.name, target, Core.TIMER_WARN_BEFORE)
    else
        text = string.format(Text.TIMER_ENDING, timer.name, Core.TIMER_WARN_BEFORE)
    end
    ns.Banner(text, 1.0, 0.82, 0.0)
end

local function PlayEndSound(key)
    local file = END_SOUNDS[key]
    if not file or ns.db.timers.sounds[key] == false or ns.db.procBar.on == false or ns.Silent() or type(PlaySoundFile) ~= "function" then return end
    pcall(PlaySoundFile, SOUND_PATH .. file, "Master")
end

local function Scale(key) return Core.TimerScale(ns.db.timers, key) / 100 end

local host

function Timers.SetHost(given) host = given end

local function Host() return host and host.Frame() or nil end
local function HostWidth() return host and host.Width() or 0 end

-- one control row, icon then bar with name and time
local function NewBar(frame)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetSize(HostWidth(), Core.MULTI_ROW)
    bar.backdrop = bar:CreateTexture(nil, "BACKGROUND")
    bar.backdrop:SetAllPoints()
    bar.backdrop:SetColorTexture(unpack(Core.ROW_BACKDROP))
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetSize(Core.MULTI_ROW, Core.MULTI_ROW)
    bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
    bar.status = CreateFrame("StatusBar", nil, bar)
    bar.status:SetSize(HostWidth() - Core.MULTI_ROW - 2, Core.MULTI_ROW)
    bar.status:SetPoint("LEFT", bar.icon, "RIGHT", 2, 0)
    bar.fill = bar.status:CreateTexture(nil, "ARTWORK")
    ns.Media.DressBar(bar.fill)
    bar.status:SetStatusBarTexture(bar.fill)
    bar.status:SetStatusBarColor(unpack(COLOURS.control))
    bar.background = bar.status:CreateTexture(nil, "BACKGROUND")
    bar.background:SetAllPoints()
    bar.background:SetColorTexture(0, 0, 0, 0.5)
    bar.name = bar.status:CreateFontString(nil, "OVERLAY", ns.Media.Font("GameFontHighlightSmall", nil, true))
    bar.name:SetPoint("LEFT", bar.status, "LEFT", 3, 0)
    bar.name:SetPoint("RIGHT", bar.status, "RIGHT", -34, 0)
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)
    bar.name:SetNonSpaceWrap(false)
    bar.name:SetMaxLines(1)
    bar.time = bar.status:CreateFontString(nil, "OVERLAY", ns.Media.Font("GameFontHighlightSmall", nil, true))
    bar.time:SetPoint("RIGHT", bar.status, "RIGHT", -3, 0)
    bar.span = Durations.New()
    bar.binding = Durations.Text(bar.time, "timer", Core.TimerText(0))
    bar:Hide()
    return bar
end

local function Ordered(list)
    local shown = {}
    for _, timer in pairs(list.timers) do shown[#shown + 1] = timer end
    table.sort(shown, function(a, b) return a.order < b.order end)
    return shown
end

local function SetName(fontString, timer)
    local label = timer.target
    if label == nil or (not IsSecret(label) and (type(label) ~= "string" or label == "")) then label = timer.name end
    if not pcall(fontString.SetText, fontString, label) then fontString:SetText(timer.name) end
end

-- draw rows and ask the list to stack them
local function Draw(list)
    local frame = Host()
    local on = ns.db.timers.controlOn ~= false
    local shown = (frame and on) and Ordered(list) or {}
    local width = frame and HostWidth() or 0
    for i, timer in ipairs(shown) do
        local bar = list.bars[i] or NewBar(frame)
        list.bars[i] = bar
        bar:SetSize(width, Core.MULTI_ROW)
        bar.status:SetSize(width - Core.MULTI_ROW - 2, Core.MULTI_ROW)
        bar.icon:SetTexture(timer.icon)
        Durations.Set(bar.span, timer.start, timer.length)
        Durations.Bar(bar.status, bar.span)
        Durations.ColourByLength(bar, timer.length)
        Durations.ShowText(bar.binding, bar.span)
        SetName(bar.name, timer)
        bar:Show()
    end
    for i = #shown + 1, #list.bars do
        Durations.HideText(list.bars[i].binding)
        list.bars[i]:Hide()
    end
    list.rows = {}
    for i = 1, #shown do list.rows[i] = list.bars[i] end
    if frame then host.Layout(list.rows) end
    return #shown
end

local function Forget(timer)
    running[timer.order] = nil
    ends.Cancel(timer.order)
    warnings.Cancel(timer.order)
end

-- end the timers ran out and redraw
local function Update()
    local now = GetTime()
    for _, list in pairs(lists) do
        for key, timer in pairs(list.timers) do
            if timer.start + timer.length - now <= 0 then
                Forget(timer)
                list.timers[key] = nil
                PlayEndSound(key)
            end
        end
        Draw(list)
    end
end

Timers.Update = Update

local function Running(id)
    local entry = running[id]
    if not entry then return nil end
    local list = lists[entry.list]
    local timer = list.timers[entry.key]
    if not timer or timer.order ~= id then
        running[id] = nil
        return nil
    end
    return timer, list, entry.key
end

local function OnEnd(id)
    local timer, list, key = Running(id)
    if not timer then return end
    Forget(timer)
    list.timers[key] = nil
    PlayEndSound(key)
    Draw(list)
end

local function OnWarning(id)
    local timer = Running(id)
    if not timer or timer.warned then return end
    timer.warned = true
    Warn(timer)
end

local function Start(listKey, key, timer)
    order = order + 1
    timer.order = order
    local old = lists[listKey].timers[key]
    if old then Forget(old) end
    lists[listKey].timers[key] = timer
    running[order] = { list = listKey, key = key }
    local finish = timer.start + timer.length
    ends.At(order, finish)
    if listKey == "control" and timer.length > Core.TIMER_WARN_BEFORE then
        warnings.At(order, finish - Core.TIMER_WARN_BEFORE)
    end
    Update()
end

local function Stop(listKey, key)
    local timer = lists[listKey].timers[key]
    if timer then
        Forget(timer)
        lists[listKey].timers[key] = nil
        Update()
    end
end

-- effect length from spell description
local function LengthOf(spellID)
    if lengths[spellID] == nil then
        lengths[spellID] = Core.ParseSpellLength(Plain(C_Spell.GetSpellDescription, spellID))
    end
    return lengths[spellID]
end

local function StartControl(key, spellID, cast)
    local length = LengthOf(spellID)
    local name = SpellName(spellID) or tostring(spellID)
    if not length then return end
    Start("control", key, { name = name, icon = Plain(C_Spell.GetSpellTexture, spellID), start = GetTime(),
        length = length, target = cast and cast.target, guid = cast and cast.guid, serial = cast and cast.serial })
end

-- guid of spell target when it is current target
local function TargetGuid(targetName)
    if IsSecret(targetName) or type(targetName) ~= "string" or targetName == "" then return nil end
    if Plain(UnitName, "target") ~= targetName then return nil end
    return Plain(UnitGUID, "target")
end

-- resist or immune text after cast, remove the timer
local function OnTargetCombat(action, school)
    if IsSecret(action) or IsSecret(school) or not Core.IsResist(action, school) then return end
    local now = GetTime()
    for key, timer in pairs(lists.control.timers) do
        if timer.serial == targetSerial and now - timer.start <= Core.TIMER_RESIST_WINDOW then
            Stop("control", key)
            ns.Fire(ns.onControlFailed, key, action, timer.name)
        end
    end
end

local function OnUnitDied(guid)
    if IsSecret(guid) or type(guid) ~= "string" then return end
    for key, timer in pairs(lists.control.timers) do
        if timer.guid == guid then Stop("control", key) end
    end
end

local handlers = {}

handlers.UNIT_SPELLCAST_SENT = function(unit, target, _, spellID)
    if unit ~= "player" or IsSecret(spellID) then return end
    lastSent = { spellID = spellID, target = target, guid = TargetGuid(target), serial = targetSerial }
end

handlers.UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
    if (unit ~= "player" and unit ~= "pet") or IsSecret(spellID) or type(spellID) ~= "number" then return end
    local key = controlKeys[spellID]
    if unit == "pet" then
        if key and Core.PET_CONTROL_SPELLS[key] then
            local ok, target = pcall(UnitName, "pettarget")
            StartControl(key, spellID, { target = ok and target or nil, guid = Plain(UnitGUID, "pettarget") })
        end
        return
    end
    local cast = (lastSent and lastSent.spellID == spellID) and lastSent or nil
    if key and not Core.PET_CONTROL_SPELLS[key] then StartControl(key, spellID, cast) end
end

handlers.PLAYER_TARGET_CHANGED = function() targetSerial = targetSerial + 1 end
handlers.UNIT_DIED = function(guid) OnUnitDied(guid) end

table.insert(ns.onPetSpells, function() controlKeys = Core.ControlSpellKeys() end)

local function Create()
    lists.control = { key = "control", bars = {}, rows = {}, timers = {} }
    ends = Durations.NewSchedule(OnEnd)
    warnings = Durations.NewSchedule(OnWarning)

    local events = CreateFrame("Frame")
    local UNIT_EVENTS = { UNIT_SPELLCAST_SENT = { "player" }, UNIT_SPELLCAST_SUCCEEDED = { "player", "pet" } }
    for name in pairs(handlers) do
        local units = UNIT_EVENTS[name]
        if units then events:RegisterUnitEvent(name, unpack(units)) else events:RegisterEvent(name) end
    end
    events:SetScript("OnEvent", function(_, event, ...) handlers[event](...) end)
    local combat = CreateFrame("Frame")
    combat:RegisterUnitEvent("UNIT_COMBAT", "target")
    combat:SetScript("OnEvent", function(_, _, _, action, _, _, school) OnTargetCombat(action, school) end)
end

local CUSTOM_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"

-- start custom row with name for sec
function Timers.StartCustom(name, seconds)
    if not lists.control then return false end
    local length = Core.CustomTimerLength(seconds)
    if type(name) ~= "string" or name == "" or not length then return false end
    Start("control", "custom:" .. name, { name = name, icon = CUSTOM_ICON, start = GetTime(), length = length })
    return true
end

-- global for player to call
function NecrosisOG_Timer(name, seconds)
    if not Timers.StartCustom(name, tonumber(seconds)) then ns.Print(Text.CUSTOM_TIMER_USAGE) end
end

local function StartDemoControl(def, now)
    local spellID = Core.SPELLS[def.key][1]
    Start("control", def.key, { name = SpellName(spellID) or tostring(spellID),
        icon = Plain(C_Spell.GetSpellTexture, spellID), start = now, length = def.length,
        target = string.format(Text.DEMO_ENEMY, 1), demo = true })
end

table.insert(ns.onDemoData, function(on)
    if not lists.control then return end
    if on then
        for _, def in ipairs(Core.DEMO.controls) do
            ns.DemoEvery(def.length + Core.DEMO.pause, function(now) StartDemoControl(def, now) end)
        end
        return
    end
    for key, timer in pairs(lists.control.timers) do
        if timer.demo then
            Forget(timer)
            lists.control.timers[key] = nil
        end
    end
    Update()
end)

table.insert(ns.onSphere, Create)

function Timers.SetScale(key, scale)
    if not Core.ToSet(Core.TIMER_LISTS)[key] then return end
    local old = Scale(key)
    ns.db.timers.scales[key] = Core.ClampScale(scale)
    if host and host.Rescale then host.Rescale(key, old) end
end

function Timers.Refresh()
    if lists.control then Update() end
end

-- shown control rows by cast order
function Timers.Rows() return lists.control and lists.control.rows or {} end

Timers.Lists = function() return lists end

ns.OnSetting(Core.TIMER_LIST_SETTINGS, function() Timers.Refresh() end)

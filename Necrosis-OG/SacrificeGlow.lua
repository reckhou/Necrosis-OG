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

-- glow on action bar for voidwalker sacrifice when health is low
local _, ns = ...
local Core, Game = ns.Core, ns.Game
local Plain, IsSecret = Game.Plain, Game.IsSecret

local SacrificeGlow = {}
ns.SacrificeGlow = SacrificeGlow

local BUTTONS_PER_BAR = 12
local PET_SLOTS = 10
local FALLBACK_BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
    "MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local UNITS = { "player", "pet" }

local glows = {}
local shown = {}
local curve, curveFor
local scanPending = false
local demoLit = false

local function SwitchedOn() return ns.db.alerts.sacrificeOn ~= false and ns.db.procBar.on ~= false end

local function SacrificeName() return Game.SpellName(Core.SPELLS.sacrifice[1]) end

local function IsSacrifice(id)
    if type(id) ~= "number" or IsSecret(id) then return false end
    for _, each in ipairs(Core.SPELLS.sacrifice) do
        if each == id then return true end
    end
    local name = SacrificeName()
    return name ~= nil and Game.SpellName(id) == name
end

local function ActionText(slot)
    local reader = C_ActionBar and C_ActionBar.GetActionText or GetActionText
    return type(reader) == "function" and Plain(reader, slot) or nil
end

local function SlotIsSacrifice(slot)
    if type(slot) ~= "number" or IsSecret(slot) then return false end
    local ok, kind, id, sub = pcall(GetActionInfo, slot)
    if not ok or IsSecret(kind) or IsSecret(id) or IsSecret(sub) then return false end
    if kind == "spell" or (kind == "macro" and sub == "spell") then
        if IsSacrifice(id) then return true end
    end
    return kind == "macro" and ActionText(slot) == Core.PET_MACROS.sacrifice
end

-- all button on bars that cast sacrifice
local function SacrificeButtons()
    local found = {}
    local names = ActionButtonUtil and ActionButtonUtil.ActionBarButtonNames or FALLBACK_BARS
    for _, prefix in ipairs(names) do
        for i = 1, BUTTONS_PER_BAR do
            local button = _G[prefix .. i]
            if type(button) == "table" and button.GetName and SlotIsSacrifice(button.action) then
                found[#found + 1] = button
            end
        end
    end
    for i = 1, PET_SLOTS do
        local button = _G["PetActionButton" .. i]
        if type(button) == "table" and button.GetName then
            local ok, spellID = pcall(function() return select(7, GetPetActionInfo(i)) end)
            if ok and IsSacrifice(spellID) then found[#found + 1] = button end
        end
    end
    return found
end

local function NewAlert(button)
    local width, height = button:GetSize()
    local alert = CreateFrame("Frame", nil, button, "ActionButtonSpellAlertTemplate")
    alert:EnableMouse(false)
    alert:SetSize(width * Core.BAR_GLOW_SIZE, height * Core.BAR_GLOW_SIZE)
    alert:SetPoint("CENTER", button, "CENTER", 0, 0)
    alert:SetAlpha(0)
    alert:Hide()
    return alert
end

local function NewGlow(button)
    return { button = button, player = NewAlert(button), pet = NewAlert(button) }
end

local function Play(alert)
    local loop = alert.ProcLoop
    if loop and not loop:IsPlaying() then loop:Play() end
end

-- step curve, 1 under the health limit and 0 above
local function Curve()
    local at = Core.SacrificeThresholdOrDefault(ns.db.alerts.sacrificeAt)
    if curveFor ~= at then
        local ok, made = pcall(function()
            local new = C_CurveUtil.CreateCurve()
            new:SetType(Enum.LuaCurveType.Step)
            for _, point in ipairs(Core.SacrificeCurvePoints(at)) do new:AddPoint(point[1], point[2]) end
            return new
        end)
        curve, curveFor = ok and made or nil, at
    end
    return curve
end

local function WriteAlpha(alert, unit, made)
    alert:SetAlpha(UnitHealthPercent(unit, true, made))
end

local function SetFromHealth(alert, unit)
    local made = Curve()
    if not (made and pcall(WriteAlpha, alert, unit, made)) then alert:SetAlpha(0) end
end

local function DemonReady()
    if Plain(UnitExists, "pet") ~= true or Plain(UnitIsDead, "pet") == true then return false end
    return Core.HighestKnown(Core.SPELLS.sacrifice, ns.PetKnows) ~= nil
end

local function UnitWanted(unit, ready)
    if unit == "pet" then return ready end
    return ready and Plain(UnitIsDeadOrGhost, "player") ~= true
end

-- glow show only when voidwalker is out and health is low
local function Refresh()
    local on = SwitchedOn()
    local demo = ns.demoData == true
    local ready = on and not demo and DemonReady()
    for _, glow in ipairs(shown) do
        for _, unit in ipairs(UNITS) do
            local alert = glow[unit]
            if demo then
                local lit = on and unit == "player" and demoLit
                alert:SetAlpha(lit and 1 or 0)
                alert:SetShown(lit)
                if lit then Play(alert) end
            elseif UnitWanted(unit, ready) then
                SetFromHealth(alert, unit)
                alert:Show()
                Play(alert)
            else
                alert:SetAlpha(0)
                alert:Hide()
            end
        end
    end
end

local function OnHealth(unit)
    if ns.demoData or not SwitchedOn() then return end
    for _, glow in ipairs(shown) do
        local alert = glow[unit]
        if alert and alert:IsShown() then SetFromHealth(alert, unit) end
    end
end

local function Scan()
    scanPending = false
    local wanted = {}
    for _, button in ipairs(SacrificeButtons()) do
        local id = button:GetName() or tostring(button)
        local glow = glows[id]
        if not glow then
            local ok, made = pcall(NewGlow, button)
            if ok then
                glow = made
                glows[id] = glow
            end
        end
        if glow then wanted[glow] = true end
    end
    for _, glow in ipairs(shown) do
        if not wanted[glow] then
            glow.player:Hide()
            glow.pet:Hide()
        end
    end
    shown = {}
    for glow in pairs(wanted) do shown[#shown + 1] = glow end
    Refresh()
end

local function ScanSoon()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0, Scan)
end

function SacrificeGlow.Shown() return shown end
function SacrificeGlow.DemoLit() return demoLit end

local function OnDemoData(on)
    demoLit = false
    if on then
        ns.DemoEvery(Core.DEMO.sacrificeStep, function()
            demoLit = not demoLit
            Refresh()
        end)
    end
    Refresh()
end

table.insert(ns.onSphere, function()
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
        "UPDATE_BONUS_ACTIONBAR", "PET_BAR_UPDATE", "UPDATE_MACROS", "PLAYER_DEAD", "PLAYER_ALIVE",
        "PLAYER_UNGHOST" }) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do
        events:RegisterUnitEvent(event, "player", "pet")
    end
    local petAlive
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            if unit == "pet" then
                local alive = Plain(UnitIsDead, "pet") == false
                if alive ~= petAlive then
                    petAlive = alive
                    Refresh()
                    return
                end
            end
            OnHealth(unit)
        elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
            Refresh()
        else
            ScanSoon()
        end
    end)
    table.insert(ns.onSpellsChanged, function()
        petAlive = Plain(UnitIsDead, "pet") == false
        ScanSoon()
    end)
    table.insert(ns.onDemoData, OnDemoData)
    ns.OnSetting(Core.SACRIFICE_SETTINGS, Refresh)
    Scan()
end)

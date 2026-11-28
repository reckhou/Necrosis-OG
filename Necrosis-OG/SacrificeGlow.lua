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

-- glow on action bar for voidwalker sacrifice when health is low
local _, ns = ...
local Core, Game = ns.Core, ns.Game
local Plain, IsSecret = Game.Plain, Game.IsSecret

local SacrificeGlow = {}
ns.SacrificeGlow = SacrificeGlow

local UNITS = { "player", "pet" }

local glows = {}
local shown = {}
local curves = {}
local FUNNEL_RANKS = Core.ToSet(Core.SPELLS.healthFunnel)
local scanPending = false
local demoLit = false
local previewKeys = {}

local function SwitchedOn(key)
    return ns.db.alerts.glows.on ~= false and ns.db.alerts[key .. "On"] ~= false
end

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

local function SlotSpell(slot)
    if type(slot) ~= "number" or IsSecret(slot) then return false end
    local ok, kind, id, sub = pcall(GetActionInfo, slot)
    if not ok or IsSecret(kind) or IsSecret(id) or IsSecret(sub) then return false end
    if kind == "spell" or (kind == "macro" and sub == "spell") then
        if FUNNEL_RANKS[id] then return "healthFunnel" end
        if IsSacrifice(id) then return "sacrifice" end
    end
    if kind == "macro" and ActionText(slot) == Core.PET_MACROS.sacrifice then return "sacrifice" end
end

-- all button on bars which cast sacrifice or health funnel
local function HealthButtons()
    local found = {}
    for _, button in ipairs(ns.ActionButtons.Bar()) do
        local key = SlotSpell(ns.ActionButtons.Slot(button))
        if key then found[button] = key end
    end
    for _, pet in ipairs(ns.ActionButtons.Pet()) do
        local ok, spellID = pcall(function() return select(7, GetPetActionInfo(pet.index)) end)
        if ok and IsSacrifice(spellID) then found[pet.button] = "sacrifice" end
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
local function Curve(key)
    local setting = key .. "At"
    local at = Core.SacrificeThresholdOrDefault(ns.db.alerts[setting], Core.DEFAULTS.alerts[setting])
    if curves[at] == nil then
        local ok, made = pcall(function()
            local new = C_CurveUtil.CreateCurve()
            new:SetType(Enum.LuaCurveType.Step)
            for _, point in ipairs(Core.SacrificeCurvePoints(at)) do new:AddPoint(point[1], point[2]) end
            return new
        end)
        curves[at] = ok and made or false
    end
    return curves[at]
end

local function WriteAlpha(alert, unit, made)
    alert:SetAlpha(UnitHealthPercent(unit, true, made))
end

local function SetFromHealth(alert, unit, made)
    if not (made and pcall(WriteAlpha, alert, unit, made)) then alert:SetAlpha(0) end
end

-- glow show only when voidwalker is out and health is low
local function Refresh()
    local demo = ns.demoData == true
    local pet = not demo and Plain(UnitExists, "pet") == true and Plain(UnitIsDead, "pet") == false
    local alive = Plain(UnitIsDeadOrGhost, "player") == false
    local sacrifice = pet and Core.HighestKnown(Core.SPELLS.sacrifice, ns.PetKnows)
    local funnel = pet and alive and Core.HighestKnown(Core.SPELLS.healthFunnel, ns.Buttons.IsKnown)
    for _, glow in ipairs(shown) do
        local on = SwitchedOn(glow.key)
        local healing = glow.key == "healthFunnel"
        glow.curve = on and Curve(glow.key)
        for _, unit in ipairs(UNITS) do
            local alert = glow[unit]
            local wanted = (healing and funnel and unit == "pet") or (not healing and sacrifice and (unit == "pet" or alive))
            if demo or previewKeys[glow.key] then
                local lit = on and (not demo or demoLit) and unit == (healing and "pet" or "player")
                alert:SetAlpha(lit and 1 or 0)
                alert:SetShown(lit)
                if lit then Play(alert) end
            elseif on and wanted then
                SetFromHealth(alert, unit, glow.curve)
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
    if ns.demoData or ns.db.alerts.glows.on == false then return end
    for _, glow in ipairs(shown) do
        if not previewKeys[glow.key] then
            local alert = glow[unit]
            if alert and alert:IsShown() then SetFromHealth(alert, unit, glow.curve) end
        end
    end
end

local function Scan()
    scanPending = false
    local wanted = {}
    for button, key in pairs(HealthButtons()) do
        local id = button:GetName() or tostring(button)
        local glow = glows[id]
        if not glow then
            local ok, made = pcall(NewGlow, button)
            if ok then
                glow = made
                glows[id] = glow
            end
        end
        if glow then
            glow.key = key
            wanted[glow] = true
        end
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

function SacrificeGlow.SetPreview(keys)
    previewKeys = keys or {}
    Refresh()
end

local function OnDemoData(on)
    demoLit = false
    if on then
        previewKeys = {}
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
    ns.ActionButtons.OnChange(ScanSoon)
    ns.OnSetting(Core.SACRIFICE_SETTINGS, Refresh)
    Scan()
end)

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

-- anti fear alert, show the icon on proc bar when target can not be feared
local _, ns = ...
local Core, Text = ns.Core, ns.Text

local Alerts = {}
ns.Alerts = Alerts

local active = nil -- "immune", "type" or nil
local check

local IsSecret, Plain = ns.Game.IsSecret, ns.Game.Plain

local function KnownFearSpell()
    return Core.PickSpell({ "howlOfTerror", "deathCoil", "fear" }, ns.Buttons.IsKnown)
end

-- round icon inside silver ring, use spell icon or the pictrue in Media\UI
function Alerts.DressIcon(frame, size, spellIDs, picture)
    local inset = size * Core.MENU_ICON_INSET / Core.MENU_ITEM_SIZE
    frame.texture = frame:CreateTexture(nil, "ARTWORK")
    frame.texture:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    frame.texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    if picture then
        frame.texture:SetTexture(Core.UiTexture(picture))
    else
        for _, id in ipairs(spellIDs) do
            local texture = Plain(C_Spell.GetSpellTexture, id)
            if texture then
                frame.texture:SetTexture(texture)
                break
            end
        end
    end
    local mask = frame:CreateMaskTexture()
    mask:SetTexture(Core.UiTexture("Mask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(frame.texture)
    frame.texture:AddMaskTexture(mask)
    frame.ring = frame:CreateTexture(nil, "OVERLAY")
    frame.ring:SetAllPoints()
    frame.ring:SetTexture(Core.UiTexture("Ring-01"))
end

local function Refresh()
    if ns.ProcAlerts then ns.ProcAlerts.SetActive("antiFear", active ~= nil) end
    if active ~= nil and not check then
        check = C_Timer.NewTicker(Core.TARGET_CHECK_EVERY, function() Alerts.CheckTarget() end)
    elseif active == nil and check then
        check:Cancel()
        check = nil
    end
end

local function Hide()
    if active == nil then return end
    active = nil
    Refresh()
end

local function Show(reason)
    if not ns.db.alerts.antiFearOn then return end
    local first = active == nil
    if not first and reason == "type" then return end
    active = reason
    Refresh()
end

-- target is still exist, alive and enemy
local function TargetStillValid()
    if Plain(UnitExists, "target") == false then return false end
    if Plain(UnitIsDead, "target") == true then return false end
    if Plain(UnitCanAttack, "player", "target") == false then return false end
    return true
end

function Alerts.CheckTarget()
    if active ~= nil and not TargetStillValid() then Hide() end
end

local function OnControlFailed(key, action, spellName)
    if not Core.IsFearImmune(key, action) then return end
    Show("immune")
end

-- target is undead or mechanical npc
local function CheckCreatureType()
    if Plain(UnitExists, "target") ~= true or not TargetStillValid() then return end
    if Plain(UnitIsPlayer, "target") ~= false then return end
    local ok, typeName, typeID = pcall(UnitCreatureType, "target")
    if not ok or IsSecret(typeName) or IsSecret(typeID) or type(typeID) ~= "number" then return end
    if not Core.FEAR_IMMUNE_TYPES[typeID] or type(typeName) ~= "string" then return end
    local spellID = KnownFearSpell()
    if not spellID then return end
    Show("type")
end

local function OnTargetChanged()
    Hide()
    CheckCreatureType()
end

local function Create()
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:SetScript("OnEvent", OnTargetChanged)
    local unit = CreateFrame("Frame")
    for _, event in ipairs(Core.TARGET_UNIT_EVENTS) do unit:RegisterUnitEvent(event, "target") end
    unit:SetScript("OnEvent", Alerts.CheckTarget)
    table.insert(ns.onControlFailed, OnControlFailed)
end

table.insert(ns.onSphere, Create)

function Alerts.Refresh()
    if not ns.db.alerts.antiFearOn then active = nil end
    Refresh()
    if ns.ProcAlerts then ns.ProcAlerts.Refresh() end
end

Alerts.Active = function() return active end

ns.OnSetting("alerts", function(path)
    if not Core.PathUnder(path, "alerts.sounds") then Alerts.Refresh() end
end)

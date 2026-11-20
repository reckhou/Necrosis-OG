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

-- the sphere, show shard count and threat ring
local _, ns = ...
local Core, Text = ns.Core, ns.Text

local Sphere = {}
ns.Sphere = Sphere

local frame, fill, glow, countText, ring, needle
local GLOW_ALPHA = 0.4
local lastCount = 0
local layoutPending = false
local warnedThisFight = false
local demoShards, demoThreat

local IsSecret, InCombat = ns.Game.IsSecret, ns.Game.InCombat

local function ApplyLayout()
    local saved = ns.db.sphere
    frame:ClearAllPoints()
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    frame:SetScale(Core.ClampSphereScale(saved.scale) / 100)
end

-- apply layout now, or wait after combat
function Sphere.RequestLayout()
    if not frame then return end
    if InCombat() then
        layoutPending = true
        return false
    end
    layoutPending = false
    ApplyLayout()
    return true
end

local function SavePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    local saved = ns.db.sphere
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

function Sphere.UpdateShards()
    if not frame then return end
    local ok, count = pcall(C_Item.GetItemCount, Core.SOUL_SHARD_ITEM)
    if not ok or IsSecret(count) or type(count) ~= "number" then count = lastCount end
    lastCount = count
    count = demoShards or count
    fill:SetTexture(Core.ShardTexture(ns.db.skin, count))
    glow:SetTexture(Core.ShardTexture(ns.db.skin, count))
    local limit = ns.Shards and ns.Shards.ShownLimit() or nil
    local text, low = Core.ShardCountText(count, ns.db.sphere.lowShards, limit)
    countText:SetText(text)
    if low then countText:SetTextColor(1, 0.2, 0.2) else countText:SetTextColor(1, 1, 1) end
    countText:SetShown(ns.db.sphere.showCount == true)
end

local function ThreatPercent()
    if not UnitExists("target") then return 0 end
    local ok, _, _, scaled = pcall(UnitDetailedThreatSituation, "player", "target")
    if not ok or IsSecret(scaled) then return 0 end
    return Core.ThreatPercent(scaled)
end

local shownPercent

-- redraw threat ring only when percent changed
function Sphere.UpdateThreat()
    if not ring then return end
    local combat = InCombat()
    if not combat and demoThreat == nil then
        ring:Hide()
        shownPercent = nil
        return
    end
    local percent = combat and ThreatPercent() or demoThreat
    if percent == shownPercent then return end
    shownPercent = percent
    local r, g, b = Core.ThreatColor(percent)
    local alpha = Core.ThreatAlpha(percent)
    for _, segment in ipairs(ring.segments) do segment:SetVertexColor(r, g, b, alpha) end
    local x, y, angle = Core.NeedleOffset(Core.SPHERE_SIZE, percent)
    needle:ClearAllPoints()
    needle:SetPoint("CENTER", ring, "CENTER", x, y)
    needle:SetRotation(angle)
    ring:Show()
end

local function CreateRing()
    ring = CreateFrame("Frame", nil, frame)
    local size = Core.SPHERE_SIZE + Core.RING_THICKNESS * 2 + 20
    ring:SetSize(size, size)
    ring:SetPoint("CENTER", frame, "CENTER", 0, 0)
    ring:SetFrameLevel(frame:GetFrameLevel() + 2)
    ring.segments = {}
    for i, place in ipairs(Core.RingSegments(Core.SPHERE_SIZE)) do
        local segment = ring:CreateTexture(nil, "OVERLAY", nil, 0)
        segment:SetTexture("Interface\\Buttons\\WHITE8X8")
        segment:SetSize(Core.RING_SEGMENT_WIDTH, Core.RING_SEGMENT_HEIGHT)
        segment:SetPoint("CENTER", ring, "CENTER", place.x, place.y)
        segment:SetRotation(place.rotation)
        ring.segments[i] = segment
    end
    needle = ring:CreateTexture(nil, "OVERLAY", nil, 7)
    needle:SetTexture("Interface\\Buttons\\WHITE8X8")
    needle:SetSize(10, Core.RING_SEGMENT_HEIGHT)
    needle:SetVertexColor(1, 1, 1, 1)
    local elapsed = 0
    ring:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.2 then
            elapsed = 0
            Sphere.UpdateThreat()
        end
    end)
    ring:Hide()
end

local function Create()
    frame = CreateFrame("Button", "NecrosisOGSphere", UIParent)
    frame:SetSize(Core.SPHERE_SIZE, Core.SPHERE_SIZE)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("RightButtonUp")

    fill = frame:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    glow = frame:CreateTexture(nil, "ARTWORK")
    glow:SetAllPoints()
    glow:SetBlendMode("ADD")
    glow:SetAlpha(GLOW_ALPHA)
    glow:Hide()

    countText = frame:CreateFontString(nil, "OVERLAY", ns.Media.Font("GameFontNormalSmall"))
    countText:SetPoint("CENTER", frame, "CENTER", 0, 0)

    frame:SetScript("OnDragStart", function(self)
        if ns.db.locked then return end
        if InCombat() then
            if not warnedThisFight then
                warnedThisFight = true
                ns.Print(Text.NO_MOVE_IN_COMBAT)
            end
            return
        end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:SetScript("OnClick", function(_, button)
        if button == "RightButton" then ns.SettingsWindow.Toggle() end
    end)

    CreateRing()
    ApplyLayout()
end

local handlers = {}

handlers.BAG_UPDATE_DELAYED = function() Sphere.UpdateShards() end

handlers.PLAYER_REGEN_DISABLED = function() Sphere.UpdateThreat() end

handlers.PLAYER_REGEN_ENABLED = function()
    warnedThisFight = false
    if layoutPending then Sphere.RequestLayout() end
    Sphere.UpdateThreat()
end

handlers.PLAYER_TARGET_CHANGED = function() Sphere.UpdateThreat() end
handlers.UNIT_THREAT_SITUATION_UPDATE = function() Sphere.UpdateThreat() end
handlers.UNIT_THREAT_LIST_UPDATE = function() Sphere.UpdateThreat() end

local UNIT_EVENTS = { UNIT_THREAT_SITUATION_UPDATE = "player" }

local events = CreateFrame("Frame")

-- warlock only
local function IsWarlock()
    local ok, _, class = pcall(UnitClass, "player")
    return ok and class == "WARLOCK"
end

events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event, ...)
    if event ~= "PLAYER_ENTERING_WORLD" then
        handlers[event](...)
        return
    end
    if not frame then
        if not ns.db or not IsWarlock() then
            self:UnregisterAllEvents()
            return
        end
        Create()
        for name in pairs(handlers) do
            if UNIT_EVENTS[name] then self:RegisterUnitEvent(name, UNIT_EVENTS[name]) else self:RegisterEvent(name) end
        end
        ns.Fire(ns.onSphere, frame)
        ns.SetPlacing(not ns.db.locked)
    end
    Sphere.UpdateShards()
    Sphere.UpdateThreat()
end)

table.insert(ns.onDemoData, function(on)
    if not frame then return end
    if not on then
        demoShards, demoThreat = nil, nil
        Sphere.UpdateShards()
        Sphere.UpdateThreat()
        return
    end
    local shardStep, threatStep = 0, 0
    ns.DemoEvery(Core.DEMO.shardStep, function()
        demoShards = Core.DemoBounce(shardStep, Core.SHARD_COUNT_MAX)
        shardStep = shardStep + 1
        Sphere.UpdateShards()
    end)
    local per = Core.DEMO.threatPerStep
    ns.DemoEvery(Core.DEMO.threatStep, function()
        demoThreat = Core.DemoBounce(threatStep, math.floor(100 / per)) * per
        threatStep = threatStep + 1
        Sphere.UpdateThreat()
    end)
end)

function Sphere.ResetPositions()
    local saved, defaults = ns.db.sphere, Core.DEFAULTS.sphere
    saved.point, saved.relativePoint, saved.x, saved.y = defaults.point, defaults.relativePoint, defaults.x, defaults.y
    saved.scale = defaults.scale
    ns.Fire(ns.onRecall)
    if frame then Sphere.RequestLayout() end
end

-- delete all settings and reload ui
function Sphere.ResetAll()
    if InCombat() then
        ns.Print(Text.RESET_IN_COMBAT)
        return
    end
    NecrosisOGDB = {}
    local reload = (C_UI and C_UI.Reload) or ReloadUI
    reload()
end

-- return false if must wait combat end
function Sphere.SetScale(scale)
    ns.db.sphere.scale = Core.ClampSphereScale(scale)
    return Sphere.RequestLayout() ~= false
end

function Sphere.LayoutPending() return layoutPending end

-- light up when mouse over
function Sphere.SetHighlight(on)
    if glow then glow:SetShown(on == true) end
end

Sphere.Frame = function() return frame, fill, countText, ring, needle, glow end

ns.OnSetting({ "sphere.showCount", "sphere.lowShards", "skin" }, function() Sphere.UpdateShards() end)

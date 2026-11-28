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

-- the sphere, show shard count and threat ring
local _, ns = ...
local Core, Text = ns.Core, ns.Text

local Sphere = {}
ns.Sphere = Sphere

local frame, fill, glow, arrivalFlash, countText, ring, needle
local GLOW_ALPHA = 0.4
local lastCount = 0
local knownCount
local heldCount
local shownTexture
local flashRemaining = 0
local flashDriver
local layoutPending = false
local warnedThisFight = false

local demoShards, demoThreat

local IsSecret, InCombat = ns.Game.IsSecret, ns.Game.InCombat

local function ApplyLayout()
    local saved = ns.db.sphere
    frame:ClearAllPoints()
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    frame:SetScale(Core.SphereFrameScale(saved.scale))
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

local previewShown = false

function Sphere.SetPreviewShown(shown)
    previewShown = shown
    countText:SetShown(ns.db.sphere.showCount == true and not shown)
end

local function ApplyShards(count)
    shownTexture = Core.ShardTexture(ns.db.skin, count)
    fill:SetTexture(shownTexture)
    glow:SetTexture(shownTexture)
    local threshold = Core.ClampThreshold(ns.db.sphere.lowShards)
    local limit = ns.Shards and ns.Shards.Limit() or Core.ShardLimit(ns.db.buttons.shardLimit)
    local shownLimit = ns.Shards and ns.Shards.ShownLimit(limit) or nil
    local text = Core.ShardCountText(count, threshold, shownLimit)
    local ratio = 0
    if count >= threshold then
        ratio = count >= limit and 1 or (count - threshold) / (limit - threshold)
    end
    countText:SetText(text)
    countText:SetTextColor(Core.TitleColourAt(ratio))
    Sphere.SetPreviewShown(previewShown)
end

function Sphere.Flash()
    if not arrivalFlash or not shownTexture or not ns.AnimationsOn() then return end
    arrivalFlash:SetTexture(shownTexture)
    arrivalFlash:SetAlpha(0.85)
    arrivalFlash:Show()
    flashRemaining = Core.ORB_FLASH_SECONDS
    if not flashDriver then flashDriver = CreateFrame("Frame", nil, frame) end
    flashDriver:SetScript("OnUpdate", function(self, delta)
        if not ns.AnimationsOn() then
            flashRemaining = 0
            arrivalFlash:SetAlpha(0)
            arrivalFlash:Hide()
            self:SetScript("OnUpdate", nil)
            return
        end
        flashRemaining = flashRemaining - (delta or 0) * ns.AnimationSpeed()
        if flashRemaining <= 0 then
            flashRemaining = 0
            arrivalFlash:SetAlpha(0)
            arrivalFlash:Hide()
            self:SetScript("OnUpdate", nil)
            return
        end
        arrivalFlash:SetAlpha(0.85 * (flashRemaining / Core.ORB_FLASH_SECONDS))
    end)
end

function Sphere.UpdateShards(immediate)
    if not frame then return end
    local ok, count = pcall(C_Item.GetItemCount, Core.SOUL_SHARD_ITEM)
    if not ok or IsSecret(count) or type(count) ~= "number" then count = lastCount end
    lastCount = count
    if demoShards ~= nil then
        ApplyShards(demoShards)
        return
    end
    local prev = knownCount
    knownCount = count
    local gained = prev ~= nil and Core.OrbGain(prev, count) or 0
    if not immediate and gained > 0 and ns.Orbs then
        local targetCount, held = count, heldCount or prev
        if ns.Orbs.Launch(gained, function()
            if demoShards ~= nil then return end
            if heldCount then
                local landed = math.max(heldCount, math.min(targetCount, knownCount))
                heldCount = landed < knownCount and landed or nil
                ApplyShards(landed)
            end
            Sphere.Flash()
        end) then
            heldCount = held
            return
        end
    end
    if count ~= prev then heldCount = nil end
    ApplyShards(heldCount or count)
end

local function ThreatSituation()
    if not UnitExists("target") then return 0, false end
    local ok, isTanking, _, scaled = pcall(UnitDetailedThreatSituation, "player", "target")
    if not ok then return 0, false end
    local percent = IsSecret(scaled) and 0 or Core.ThreatPercent(scaled)
    local aggro = not IsSecret(isTanking) and isTanking == true
    return percent, aggro
end

local shownPercent
local goalPercent
local hasAggro = false
local flashElapsed = 0

local function DrawSegments(percent, tint, flashAlpha)
    local r, g, b = Core.ThreatColor(percent)
    if tint and tint > 0 then r, g, b = Core.ThreatFlashColor(r, g, b, tint) end
    local alpha = Core.ThreatAlpha(percent) * (flashAlpha or 1)
    for _, segment in ipairs(ring.segments) do segment:SetVertexColor(r, g, b, alpha) end
end

local function DrawThreat(percent, tint, flashAlpha)
    shownPercent = percent
    DrawSegments(percent, tint, flashAlpha)
    local x, y, angle = Core.NeedleOffset(Core.SPHERE_SIZE, percent)
    needle:ClearAllPoints()
    needle:SetPoint("CENTER", ring, "CENTER", x, y)
    needle:SetRotation(angle)
end

-- read threat again, needle glide to new value
function Sphere.UpdateThreat(snap)
    if not ring then return end
    local combat = InCombat()
    if not ns.db.sphere.showThreat or (not combat and demoThreat == nil) then
        ring:Hide()
        shownPercent, goalPercent, hasAggro, flashElapsed = nil, nil, false, 0
        return
    end
    local aggro
    if combat then
        goalPercent, aggro = ThreatSituation()
    else
        goalPercent, aggro = demoThreat, demoThreat >= 100
    end
    if aggro ~= hasAggro then
        hasAggro = aggro
        flashElapsed = 0
        if not aggro and shownPercent ~= nil then DrawSegments(shownPercent, 0, 1) end
    end
    local tint = hasAggro and Core.ThreatFlashTint(flashElapsed) or 0
    local flashAlpha = hasAggro and Core.ThreatFlashAlpha(flashElapsed) or 1
    if goalPercent ~= shownPercent and (snap or shownPercent == nil or not ns.AnimationsOn()) then
        DrawThreat(goalPercent, tint, flashAlpha)
    end
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
        if hasAggro then flashElapsed = flashElapsed + delta end
        local tint = hasAggro and Core.ThreatFlashTint(flashElapsed) or 0
        local flashAlpha = hasAggro and Core.ThreatFlashAlpha(flashElapsed) or 1
        if goalPercent ~= nil and shownPercent ~= goalPercent then
            DrawThreat(Core.ThreatEase(shownPercent, goalPercent, delta, ns.AnimationSpeed()), tint, flashAlpha)
        elseif hasAggro and shownPercent ~= nil then
            DrawSegments(shownPercent, tint, flashAlpha)
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
    arrivalFlash = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    arrivalFlash:SetAllPoints()
    arrivalFlash:SetBlendMode("ADD")
    arrivalFlash:SetAlpha(0)
    arrivalFlash:Hide()

    countText = frame:CreateFontString(nil, "OVERLAY", ns.Media.Font("GameFontNormalSmall", nil, true))
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
    ns.Sounds.Button(frame)

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
    Sphere.UpdateShards(true)
    Sphere.UpdateThreat()
end)

table.insert(ns.onDemoData, function(on)
    if not frame then return end
    if not on then
        demoShards, demoThreat, heldCount = nil, nil, nil
        if ns.Orbs then ns.Orbs.Clear() end
        Sphere.UpdateShards(true)
        Sphere.UpdateThreat()
        return
    end
    local shardStep, prevDemo = 0, nil
    ns.DemoEvery(Core.DEMO.shardStep, function()
        local nextCount = Core.DemoBounce(shardStep, Core.SHARD_COUNT_MAX)
        if prevDemo ~= nil and nextCount < prevDemo and ns.Orbs and ns.Orbs.ActiveCount() > 0 then return end
        local gained = prevDemo ~= nil and nextCount > prevDemo
        prevDemo = nextCount
        shardStep = shardStep + 1
        if gained and ns.Orbs and ns.Orbs.DemoOrigin then
            local ox, oy = ns.Orbs.DemoOrigin()
            if ox and ns.Orbs.Launch(1, function()
                if demoShards == nil then return end
                demoShards = nextCount
                ApplyShards(nextCount)
                Sphere.Flash()
            end, ox, oy) then
                return
            end
        end
        demoShards = nextCount
        Sphere.UpdateShards(true)
    end)
    local levels, index = Core.DEMO.threatLevels, 1
    ns.DemoEvery(Core.DEMO.threatStep, function()
        demoThreat = levels[index]
        Sphere.UpdateThreat(index == 1)
        index = index % #levels + 1
    end)
end)

function Sphere.ResetPositions()
    local saved, defaults = ns.db.sphere, Core.DEFAULTS.sphere
    saved.point, saved.relativePoint, saved.x, saved.y = defaults.point, defaults.relativePoint, defaults.x, defaults.y
    saved.scale = defaults.scale
    ns.Fire(ns.onRecall)
    if frame then Sphere.RequestLayout() end
end

local resetPending = false

function Sphere.ResetAll()
    if InCombat() then
        ns.Print(Text.RESET_IN_COMBAT)
        return
    end
    resetPending = true
end

local leaving = CreateFrame("Frame")
leaving:RegisterEvent("PLAYER_LOGOUT")
leaving:SetScript("OnEvent", function()
    if resetPending then NecrosisOGDB = {} end
end)

-- return false if must wait combat end
function Sphere.SetScale(scale)
    local saved = ns.db.sphere
    local newScale = Core.ClampSphereScale(scale)
    local ratio = Core.ClampSphereScale(saved.scale) / newScale
    local half = Core.SPHERE_SIZE / 2
    local anchorX = (saved.point:find("RIGHT") and half) or (saved.point:find("LEFT") and -half) or 0
    local anchorY = (saved.point:find("TOP") and half) or (saved.point:find("BOTTOM") and -half) or 0
    saved.x = anchorX + (saved.x - anchorX) * ratio
    saved.y = anchorY + (saved.y - anchorY) * ratio
    saved.scale = newScale
    return Sphere.RequestLayout() ~= false
end

function Sphere.LayoutPending() return layoutPending end

-- light up when mouse over
function Sphere.SetHighlight(on)
    if glow then glow:SetShown(on == true) end
end

Sphere.Frame = function() return frame, fill, countText, ring, needle, glow, arrivalFlash end

ns.OnSetting({ "sphere.showCount", "sphere.lowShards", "skin" }, function() Sphere.UpdateShards(true) end)
ns.OnSetting("sphere.showThreat", function() Sphere.UpdateThreat() end)

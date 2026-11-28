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

-- soul orbs fly into sphere when you get new shard
local _, ns = ...
local Core = ns.Core

local Orbs = {}
ns.Orbs = Orbs

local IsSecret, Plain = ns.Game.IsSecret, ns.Game.Plain

local ORB_TEXTURE = "Interface\\AddOns\\Necrosis-OG\\Media\\UI\\SoulOrb"

local overlay
local live = {}
local texPool = {}

local function ScreenSize()
    if not UIParent then return 1024, 768 end
    local w = Plain(UIParent.GetWidth, UIParent)
    local h = Plain(UIParent.GetHeight, UIParent)
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
    return 1024, 768
end

local function SphereCentre()
    local sphereFrame = ns.Sphere and ns.Sphere.Frame and ns.Sphere.Frame()
    if not sphereFrame or not UIParent then return nil, nil end
    local shown = Plain(sphereFrame.IsShown, sphereFrame)
    if shown ~= true then return nil, nil end
    if type(sphereFrame.GetCenter) ~= "function" then return nil, nil end
    local ok, cx, cy = pcall(sphereFrame.GetCenter, sphereFrame)
    if not ok or IsSecret(cx) or IsSecret(cy) or type(cx) ~= "number" or type(cy) ~= "number" then
        return nil, nil
    end
    local fScale = Plain(sphereFrame.GetEffectiveScale, sphereFrame)
    local pScale = Plain(UIParent.GetEffectiveScale, UIParent)
    if type(fScale) == "number" and type(pScale) == "number" and pScale > 0 then
        cx = cx * fScale / pScale
        cy = cy * fScale / pScale
    end
    return cx, cy
end

local function EnsureOverlay()
    if overlay then return overlay end
    overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("HIGH")
    if overlay.EnableMouse then overlay:EnableMouse(false) end
    return overlay
end

local function AcquireTexture()
    local tex = table.remove(texPool)
    if not tex then
        tex = EnsureOverlay():CreateTexture(nil, "OVERLAY")
        tex:SetTexture(ORB_TEXTURE)
        if tex.SetBlendMode then tex:SetBlendMode("ADD") end
    end
    tex:SetVertexColor(Core.ORB_COLOR[1], Core.ORB_COLOR[2], Core.ORB_COLOR[3])
    return tex
end

local function ReleaseOrb(orb)
    if orb.head then
        orb.head:Hide()
        texPool[#texPool + 1] = orb.head
        orb.head = nil
    end
    if orb.trails then
        for i = 1, #orb.trails do
            local t = orb.trails[i]
            t:Hide()
            texPool[#texPool + 1] = t
        end
        orb.trails = nil
    end
end

local function PlaceTexture(tex, x, y, size, alpha)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", overlay, "BOTTOMLEFT", x, y)
    tex:SetSize(size, size)
    tex:SetAlpha(alpha)
    tex:Show()
end

local function HideTrails(orb)
    if not orb.trails then return end
    for i = 1, #orb.trails do orb.trails[i]:Hide() end
end

local function AnimationEnabled()
    return ns.demoData or (ns.AnimationsOn() and ns.db.sphere.soulOrbsAnimation)
end

local function StepDriver(_, delta)
    local destX, destY = SphereCentre()
    local dt = (delta or 0) * ns.AnimationSpeed() * Core.ORB_SPEED_SCALE
    for i = #live, 1, -1 do
        local orb = live[i]
        if destX and destY then orb.destX, orb.destY = destX, destY end
        local visible, x, y, scale, alpha, arrived = Core.OrbStep(orb, dt)
        if arrived then
            ReleaseOrb(orb)
            table.remove(live, i)
            if orb.burst and not orb.burst.landed then
                orb.burst.landed = true
                if orb.burst.onArrive then orb.burst.onArrive() end
            end
        elseif not visible then
            orb.head:Hide()
            HideTrails(orb)
        else
            local size = Core.ORB_SIZE * scale
            PlaceTexture(orb.head, x, y, size, alpha)
            for k = 1, #orb.trails do
                local tVis, tx, ty, tScale, tAlpha = Core.OrbPosition(orb, orb.age - k * Core.ORB_TRAIL_STEP)
                if tVis and tAlpha > 0.02 then
                    local fade = (1 - k / (#orb.trails + 1)) * 0.45 * tAlpha
                    local shrink = 1 - 0.12 * k
                    PlaceTexture(orb.trails[k], tx, ty, Core.ORB_SIZE * tScale * shrink, fade)
                else
                    orb.trails[k]:Hide()
                end
            end
        end
    end
    if #live == 0 and overlay then
        overlay:SetScript("OnUpdate", nil)
    end
end

-- launch orbs, onArrive run when first one land. false when skip
function Orbs.Launch(shardsGained, onArrive, originX, originY)
    if not AnimationEnabled() then return false end
    if type(shardsGained) ~= "number" or shardsGained <= 0 then return false end
    local destX, destY = SphereCentre()
    if not destX or not destY then return false end
    local screenW, screenH = ScreenSize()
    local startX, startY = originX, originY
    if type(startX) ~= "number" or type(startY) ~= "number" then
        startX, startY = Core.OrbOrigin(screenW, screenH)
    end
    EnsureOverlay()
    local bursts = math.min(math.floor(shardsGained), Core.ORB_MAX_BURSTS)
    for b = 1, bursts do
        local burst = { landed = false, onArrive = (b == bursts) and onArrive or nil }
        for i = 1, Core.ORB_COUNT do
            local ringX, ringY, c1x, c1y, c2x, c2y = Core.OrbControlPoints(i, Core.ORB_COUNT, startX, startY, destX, destY, screenH)
            local trails = {}
            for k = 1, Core.ORB_TRAIL_COUNT do trails[k] = AcquireTexture() end
            live[#live + 1] = {
                startX = startX,
                startY = startY,
                ringX = ringX,
                ringY = ringY,
                c1x = c1x,
                c1y = c1y,
                c2x = c2x,
                c2y = c2y,
                destX = destX,
                destY = destY,
                bloomDur = Core.ORB_BLOOM_SECONDS,
                flightDur = Core.ORB_FLIGHT_SECONDS + (math.random() * 2 - 1) * Core.ORB_FLIGHT_JITTER,
                delay = (b - 1) * 0.12 + (i - 1) * Core.ORB_STAGGER,
                age = 0,
                head = AcquireTexture(),
                trails = trails,
                burst = burst,
            }
        end
    end
    if #live > 0 then
        overlay:SetScript("OnUpdate", StepDriver)
    end
    return true
end

function Orbs.DemoOrigin()
    local destX, destY = SphereCentre()
    if not destX or not destY then return nil, nil end
    local w, h = ScreenSize()
    local ox = destX - 140
    if ox < 60 then ox = destX + 140 end
    local oy = math.min(h - 60, math.max(60, destY + 130))
    return math.min(w - 60, math.max(60, ox)), oy
end

-- stop all flying orbs now
function Orbs.Clear()
    local pending = {}
    for i = #live, 1, -1 do
        local orb = live[i]
        if orb.burst and not orb.burst.landed and orb.burst.onArrive then
            orb.burst.landed = true
            pending[#pending + 1] = orb.burst.onArrive
        end
        ReleaseOrb(orb)
        live[i] = nil
    end
    if overlay then overlay:SetScript("OnUpdate", nil) end
    for i = 1, #pending do pending[i]() end
end

function Orbs.ActiveCount()
    return #live
end

ns.OnSetting({ "animation.on", "sphere.soulOrbsAnimation" }, function()
    if not AnimationEnabled() then Orbs.Clear() end
end)

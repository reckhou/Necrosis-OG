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

-- reminder bar and proc bar
local _, ns = ...
local Core, Text = ns.Core, ns.Text

local Bars = {}
ns.Bars = Bars

local bars = {}

local InCombat = ns.Game.InCombat

local function Animate() return ns.AnimationsOn() end
local function Saved(bar) return ns.db[bar.spec.saved] end

-- add alpha animation to group
local function AlphaStep(group, from, to, seconds)
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(from)
    alpha:SetToAlpha(to)
    alpha:SetDuration(seconds)
    return alpha
end

Bars.AlphaStep = AlphaStep

local function ScaleStep(group, from, to, seconds)
    local scale = group:CreateAnimation("Scale")
    scale:SetScaleFrom(from, from)
    scale:SetScaleTo(to, to)
    scale:SetDuration(seconds)
    scale:SetSmoothing("OUT")
    return scale
end

Bars.ScaleStep = ScaleStep

local function Anchor(item, dx)
    item.face:ClearAllPoints()
    item.face:SetPoint("CENTER", item.button, "CENTER", dx or 0, 0)
end

-- slow glow pulse when icon wait
local function StartPulse(item)
    local face = item.face
    face.pulse:Stop()
    face.glow:SetAlpha(1)
    if not item.hovered then face.pulse:Play() end
    if item.bar.spec.pulseIcon then ns.Rings.SetGlowLift(face, not item.hovered and "pulse" or nil) end
end

local function NewFace(bar, item)
    local face = CreateFrame("Frame", nil, bar.frame)
    face:SetSize(Core.BUTTON_SIZE, Core.BUTTON_SIZE)
    face:SetFrameStrata(bar.spec.strata or "MEDIUM")
    item.face = face
    Anchor(item)
    face.glow = ns.Rings.NewGlow(face)

    face.appear = face:CreateAnimationGroup()
    AlphaStep(face.appear, 0, 1, Core.BAR_APPEAR)
    ScaleStep(face.appear, Core.BAR_GROW_FROM, 1, Core.BAR_APPEAR)

    face.go = face:CreateAnimationGroup()
    face.go:SetToFinalAlpha(true)
    AlphaStep(face.go, 1, 0, Core.BAR_GO)
    ScaleStep(face.go, 1, Core.BAR_GROW_FROM, Core.BAR_GO)
    face.go:SetScript("OnFinished", function() if not item.wasShown then face:Hide() end end)

    face.slide = face:CreateAnimationGroup()
    face.slide.move = face.slide:CreateAnimation("Translation")
    face.slide.move:SetDuration(Core.BAR_SLIDE)
    face.slide.move:SetSmoothing("OUT")
    face.slide:SetScript("OnFinished", function() Anchor(item) end)

    face.fade = face:CreateAnimationGroup()
    face.fade:SetToFinalAlpha(true)
    AlphaStep(face.fade, 1, 0, Core.BAR_FADE)

    face.pulse = face.glow:CreateAnimationGroup()
    face.pulse:SetLooping("BOUNCE")
    AlphaStep(face.pulse, 1, Core.BAR_PULSE_DIM, Core.BAR_PULSE)

    for _, group in ipairs({ face.appear, face.go, face.slide, face.fade }) do ns.PopUpAnimation(group) end

    face:Hide()
    return face
end

local function Appear(item)
    local face = item.face
    face.go:Stop()
    face.appear:Stop()
    Anchor(item)
    face:Show()
    face:SetAlpha(item.faded and 0 or 1)
    if Animate() and not item.faded then face.appear:Play() end
    StartPulse(item)
end

local function Go(item)
    local face = item.face
    face.pulse:Stop()
    ns.Rings.SetGlowLift(face, nil)
    face.slide:Stop()
    if Animate() and face:IsShown() and not item.faded then
        face.go:Play()
    else
        face:Hide()
    end
end

-- face slide from old place to the button
local function Slide(item, dx)
    local face = item.face
    face.slide:Stop()
    if not Animate() then return Anchor(item) end
    Anchor(item, dx)
    face.slide.move:SetOffset(-dx, 0)
    face.slide:Play()
end

-- play animation for icon appear, go or moved
function Bars.Sync(bar)
    for _, item in ipairs(bar.items) do
        local shown = item.button:IsShown() == true
        local x
        if bar.spec.secure then x = item.button:GetAttribute("slotx") else x = item.slotx end
        if shown and not item.wasShown then
            item.wasShown = true
            Appear(item)
        elseif not shown and item.wasShown then
            item.wasShown = false
            Go(item)
        elseif shown and type(item.lastX) == "number" and type(x) == "number" and x ~= item.lastX then
            Slide(item, item.lastX - x)
        end
        item.lastX = shown and x or nil
    end
end

-- fade out icon but keep its slot
function Bars.SetFaded(item, faded)
    faded = faded == true
    if item.faded == faded then return end
    item.faded = faded
    local face = item.face
    if faded then
        face.appear:Stop()
        if Animate() and face:IsShown() then face.fade:Play() else face:SetAlpha(0) end
    else
        face.fade:Stop()
        face:SetAlpha(1)
        if Animate() and face:IsShown() then face.appear:Play() end
    end
end

function Bars.SetRing(item, key)
    ns.Rings.SetGlowKey(item.face.glow, key)
    ns.Rings.SetKey(item.face, key)
end

local warnedDrag = false

local function ApplyPlace(bar)
    local saved = Saved(bar)
    bar.frame:ClearAllPoints()
    bar.frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
end

local function DragStart(bar)
    if ns.db.locked and not ns.placing then return end
    if bar.spec.secure and InCombat() then
        if not warnedDrag then
            warnedDrag = true
            ns.Print(Text.NO_MOVE_IN_COMBAT)
        end
        return
    end
    bar.dragging = true
    bar.frame:StartMoving()
end

-- save center of bar in screen pixel
local function DragStop(bar)
    if not bar.dragging then return end
    bar.dragging = false
    bar.frame:StopMovingOrSizing()
    if bar.frame.SetUserPlaced then pcall(bar.frame.SetUserPlaced, bar.frame, false) end
    local x, y = bar.frame:GetCenter()
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local saved = Saved(bar)
    saved.point, saved.relativePoint, saved.x, saved.y = "CENTER", "BOTTOMLEFT", x, y
    ApplyPlace(bar)
end

local function NewOutline(bar)
    local outline = CreateFrame("Frame", nil, UIParent)
    outline:SetFrameStrata("HIGH")
    outline:SetPoint("CENTER", bar.frame, "CENTER", 0, 0)
    outline:SetSize(1, 1)
    outline.back = outline:CreateTexture(nil, "BACKGROUND")
    outline.back:SetAllPoints()
    outline.back:SetColorTexture(0.45, 0.15, 0.55, 0.35)
    outline.label = outline:CreateFontString(nil, "OVERLAY", ns.Media.Font("GameFontNormalSmall"))
    outline.label:SetPoint("BOTTOM", outline, "TOP", 0, 2)
    outline.label:SetText(Text[bar.spec.label])
    outline:EnableMouse(true)
    outline:SetMovable(true)
    outline:RegisterForDrag("LeftButton")
    outline:SetScript("OnDragStart", function() DragStart(bar) end)
    outline:SetScript("OnDragStop", function() DragStop(bar) end)
    outline:Hide()
    return outline
end

-- spec: name, saved, label, secure ...
function Bars.New(spec)
    local bar = { spec = spec, items = {}, byKey = {}, step = Core.BUTTON_SIZE }
    local frame
    if spec.secure then
        frame = CreateFrame("Frame", spec.name, UIParent, "SecureHandlerStateTemplate")
        frame:SetAttribute("layout", Core.BAR_LAYOUT)
        frame:HookScript("OnAttributeChanged", function(_, name) if name == "serial" then Bars.Sync(bar) end end)
    else
        frame = CreateFrame("Frame", spec.name, UIParent)
    end
    frame:SetSize(1, 1)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    bar.frame = frame
    bar.outline = NewOutline(bar)
    bars[#bars + 1] = bar
    return bar
end

function Bars.AddItem(bar, key, button)
    local item = { key = key, bar = bar, button = button, ready = false, wanted = false, faded = false }
    bar.items[#bar.items + 1] = item
    bar.byKey[key] = item
    local face = NewFace(bar, item)
    if button.icon then
        button.icon:SetParent(face)
        button.icon:ClearAllPoints()
        button.icon:SetAllPoints(face)
        face.icon = button.icon
    end
    if bar.spec.noClicks then
        ns.Rings.Attach(face, button, nil, { mouse = false })
        button:Hide()
        return item
    end
    ns.Rings.Attach(face, button)
    button:HookScript("OnEnter", function()
        item.hovered = true
        face.pulse:Stop()
        face.glow:SetAlpha(1)
        ns.Rings.SetGlowLift(face, nil)
    end)
    button:HookScript("OnLeave", function()
        item.hovered = false
        if face:IsShown() then StartPulse(item) end
    end)
    if bar.spec.secure then
        SecureHandlerSetFrameRef(bar.frame, "slot" .. #bar.items, button)
        SecureHandlerSetFrameRef(bar.frame, key, button)
    end
    button:Hide()
    return item
end

function Bars.ApplyOpacity(saved)
    for _, bar in ipairs(bars) do
        if bar.spec.saved == saved then bar.frame:SetAlpha(Core.ClampOpacity(ns.db[saved].opacity) / 100) end
    end
end

function Bars.Apply(bar)
    Bars.ApplyOpacity(bar.spec.saved)
    if bar.spec.secure and InCombat() then return false end
    bar.laidOutFor = nil
    local saved = Saved(bar)
    local scale = Core.BarIconScale(saved.scale)
    bar.step = Core.BarStep(saved.scale, saved.spacing)
    for _, item in ipairs(bar.items) do
        item.button:SetScale(scale)
        item.face:SetScale(scale)
    end
    ApplyPlace(bar)
    local width, height = #bar.items * bar.step * scale, Core.BUTTON_SIZE * scale
    bar.frame:SetSize(width, height)
    bar.outline:SetSize(width, height)
    if bar.spec.secure then
        bar.frame:SetAttribute("count", #bar.items)
        bar.frame:SetAttribute("step", bar.step)
    end
    return true
end

-- show ready icons centered and play changes
function Bars.Layout(bar)
    if bar.spec.secure then
        if InCombat() then
            bar.laidOutFor = nil
            return false
        end
        local changed = not bar.laidOutFor
        for _, item in ipairs(bar.items) do
            local ready, wanted = item.ready == true, item.wanted == true
            if changed or item.laidReady ~= ready or item.laidWanted ~= wanted then
                changed = true
                item.laidReady, item.laidWanted = ready, wanted
            end
        end
        if changed then
            bar.laidOutFor = true
            for _, item in ipairs(bar.items) do
                item.button:SetAttribute("ready", item.laidReady)
                item.button:SetAttribute("wanted", item.laidWanted)
            end
            bar.frame:Execute(Core.BAR_LAYOUT)
        end
    else
        local shown = {}
        for _, item in ipairs(bar.items) do
            if item.ready and item.wanted then shown[#shown + 1] = item else item.button:Hide() end
        end
        for i, item in ipairs(shown) do
            item.slotx = Core.BarOffset(i, #shown, bar.step)
            item.button:ClearAllPoints()
            item.button:SetPoint("CENTER", bar.frame, "CENTER", item.slotx, 0)
            item.button:Show()
        end
    end
    Bars.Sync(bar)
    return true
end

function Bars.AddDriver(bar, state)
    bar.frame:SetAttribute("_onstate-" .. state, Core.BAR_DRIVER_SNIPPETS[state])
    RegisterStateDriver(bar.frame, state, Core.BAR_DRIVERS[state])
end

table.insert(ns.onPlacing, function(on)
    for _, bar in ipairs(bars) do bar.outline:SetShown(on == true) end
end)

table.insert(ns.onRecall, function()
    for _, bar in ipairs(bars) do
        local saved, default = Saved(bar), Core.DEFAULTS[bar.spec.saved]
        saved.point, saved.relativePoint, saved.x, saved.y = default.point, default.relativePoint, default.x, default.y
        if not (bar.spec.secure and InCombat()) then ApplyPlace(bar) end
    end
end)

Bars.All = function() return bars end

for _, saved in ipairs({ "procBar", "reminderBar" }) do
    ns.OnSetting(saved .. ".opacity", function() Bars.ApplyOpacity(saved) end)
end

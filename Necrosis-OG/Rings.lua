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

-- ring effect for round buttons, tint by icon color when hover or pressing
local _, ns = ...
local Core = ns.Core

local Rings = {}
ns.Rings = Rings

local function NewLayers(frame, add)
    local tint = frame:CreateTexture(nil, "OVERLAY", nil, 6)
    tint:SetAllPoints(frame)
    tint:SetBlendMode(add and "ADD" or "BLEND")
    local shine = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    shine:SetAllPoints(frame)
    shine:SetBlendMode("ADD")
    return { tint = tint, shine = shine }
end

local function Paint(layers, look, key)
    layers.tint:SetTexture(Core.UiTexture("RingTint-" .. look))
    layers.shine:SetTexture(Core.UiTexture("RingShine-" .. look))
    layers.tint:SetVertexColor(Core.RingColour(key))
end

local function ShowLayers(layers, shown)
    layers.tint:SetShown(shown)
    layers.shine:SetShown(shown)
end

local function Copy(icon, lift)
    local atlas = icon.GetAtlas and icon:GetAtlas()
    if type(atlas) == "string" and atlas ~= "" then
        lift:SetAtlas(atlas)
    else
        lift:SetTexture(icon:GetTexture())
    end
    lift:SetDesaturated(icon.IsDesaturated and icon:IsDesaturated() == true)
end

local function NewLift(visual, icon)
    local lift = visual:CreateTexture(nil, "ARTWORK", nil, 1)
    lift:SetAllPoints(icon)
    lift:SetBlendMode("ADD")
    lift:SetAlpha(Core.RING_ICON_LIFT)
    local mask = visual:CreateMaskTexture()
    mask:SetTexture(Core.UiTexture("Mask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    lift:AddMaskTexture(mask)
    lift:Hide()
    return lift
end

-- presed first then hover, else nothing show
local function Update(fx)
    local look = (fx.pressed and "Pressed") or (fx.over and "Hover") or nil
    if look then Paint(fx.layers, look, fx.key) end
    ShowLayers(fx.layers, look ~= nil)
    if not fx.icon then return end
    if look == "Hover" then
        Copy(fx.icon, fx.lift)
        fx.lift:Show()
    else
        fx.lift:Hide()
    end
    local dim = (look == "Pressed" and Core.RING_ICON_PRESSED or 1) * (fx.dim or 1)
    fx.icon:SetVertexColor(dim, dim, dim)
end

function Rings.SetDim(visual, value)
    local fx = visual.ringFx
    if not fx or not fx.icon then return false end
    fx.dim = value
    Update(fx)
    return true
end

-- visual is frame for draw, listener is frame who get mouse, key is color key of Core.RING_TINT
-- options.icon = false will not touch icon, options.mouse = false no hover and press
function Rings.Attach(visual, listener, key, options)
    options = options or {}
    local fx = { key = key, over = false, pressed = false }
    local frame = CreateFrame("Frame", nil, visual)
    frame:SetAllPoints(visual)
    frame:SetFrameLevel(visual:GetFrameLevel() + 3)
    fx.frame = frame
    fx.layers = NewLayers(frame)
    ShowLayers(fx.layers, false)
    visual.ringFx = fx
    local icon = options.icon
    if icon == nil then icon = visual.icon end
    if icon then Rings.SetIcon(visual, icon) end
    if options.mouse == false then return fx end
    listener:HookScript("OnEnter", function() fx.over = true; Update(fx) end)
    listener:HookScript("OnLeave", function() fx.over = false; Update(fx) end)
    listener:HookScript("OnMouseDown", function() fx.pressed = true; Update(fx) end)
    listener:HookScript("OnMouseUp", function() fx.pressed = false; Update(fx) end)
    listener:HookScript("OnHide", function() fx.over, fx.pressed = false, false; Update(fx) end)
    return fx
end

function Rings.SetIcon(visual, icon)
    local fx = visual.ringFx
    if not fx or fx.icon then return end
    fx.icon = icon
    fx.lift = NewLift(visual, icon)
    fx.glowLift = NewLift(visual, icon)
    fx.glowPulse = fx.glowLift:CreateAnimationGroup()
    fx.glowPulse:SetLooping("BOUNCE")
    local fade = fx.glowPulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(Core.BAR_PULSE_DIM)
    fade:SetDuration(Core.BAR_PULSE)
    if type(hooksecurefunc) == "function" then
        local function Follow() if fx.glowLift:IsShown() then Copy(icon, fx.glowLift) end end
        pcall(hooksecurefunc, icon, "SetTexture", Follow)
        pcall(hooksecurefunc, icon, "SetAtlas", Follow)
    end
end

-- mode can be "pulse", "still", or nil to hide it
function Rings.SetGlowLift(visual, mode)
    local fx = visual.ringFx
    if not fx or not fx.glowLift then return end
    fx.glowPulse:Stop()
    if mode == nil then
        fx.glowLift:Hide()
        return
    end
    Copy(fx.icon, fx.glowLift)
    fx.glowLift:Show()
    if mode == "pulse" then fx.glowPulse:Play() end
end

function Rings.SetKey(visual, key)
    local fx = visual.ringFx
    if not fx or fx.key == key then return end
    fx.key = key
    if fx.over or fx.pressed then Update(fx) end
end

-- ring which always lit, it under teh hover ring
function Rings.NewGlow(parent, key, add)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:SetFrameLevel(parent:GetFrameLevel() + 2)
    frame.layers = NewLayers(frame, add)
    frame.key = key
    Paint(frame.layers, "Lit", key)
    return frame
end

function Rings.SetGlowKey(frame, key)
    if frame.key == key then return end
    frame.key = key
    Paint(frame.layers, "Lit", key)
end

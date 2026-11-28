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

-- bar layout math
local _, ns = ...
local Core = ns.Core
local Clamp = Core.ClampValue

Core.BAR_SPACING_MIN, Core.BAR_SPACING_MAX, Core.BAR_SPACING_STEP = 0, 40, 1

Core.OPACITY_MIN, Core.OPACITY_MAX, Core.OPACITY_STEP = 20, 100, 5

function Core.ClampOpacity(value)
    return Clamp(value, Core.OPACITY_MIN, Core.OPACITY_MAX, Core.OPACITY_STEP, Core.OPACITY_MAX)
end

function Core.ClampBarSpacing(value)
    return Clamp(value, Core.BAR_SPACING_MIN, Core.BAR_SPACING_MAX, Core.BAR_SPACING_STEP, Core.DEFAULTS.reminderBar.spacing)
end

function Core.BarIconScale(scale) return Core.CONTROL_ICON_SCALE * Core.ClampScale(scale) / 100 end

-- distance between icon centers
function Core.BarStep(scale, spacing)
    return Core.BUTTON_SIZE + Core.ClampBarSpacing(spacing) / Core.BarIconScale(scale)
end

-- x offset of i-th icon from center, whole group keep centered
function Core.BarOffset(i, n, step) return (i - (n + 1) / 2) * step end

Core.BAR_LAYOUT = [[
    local count = self:GetAttribute("count") or 0
    local step = self:GetAttribute("step") or 0
    local shown = newtable()
    local n = 0
    for i = 1, count do
        local slot = self:GetFrameRef("slot" .. i)
        if slot:GetAttribute("ready") and (slot:GetAttribute("wanted") or slot:GetAttribute("forced")) then
            n = n + 1
            shown[n] = slot
        else
            slot:Hide()
        end
    end
    for i = 1, n do
        local x = (i - (n + 1) / 2) * step
        local slot = shown[i]
        slot:ClearAllPoints()
        slot:SetPoint("CENTER", self, "CENTER", x, 0)
        slot:SetAttribute("slotx", x)
        slot:Show()
    end
    self:SetAttribute("serial", (self:GetAttribute("serial") or 0) + 1)
]]

Core.BAR_DRIVERS = {
    demon = "[combat,@pet,noexists,nomounted][combat,@pet,dead,nomounted] gone; ok",
    breath = "[combat,swimming] swim; dry",
    soulLink = "[nocombat] out; [@pet,exists,nodead] pet; nopet",
}
Core.BAR_DRIVER_SNIPPETS = {
    demon = [[
        local slot = self:GetFrameRef("demon")
        slot:SetAttribute("forced", newstate == "gone" and not IsMounted() and not UnitIsDead("player"))
        self:RunAttribute("layout")
    ]],
    breath = [[
        local slot = self:GetFrameRef("unendingBreath")
        slot:SetAttribute("forced", newstate == "swim")
        self:RunAttribute("layout")
    ]],
    soulLink = [[
        local slot = self:GetFrameRef("soulLink")
        local before = self:GetAttribute("petstate")
        slot:SetAttribute("forced", newstate == "pet" and (before == "nopet" or slot:GetAttribute("forced") == true))
        self:SetAttribute("petstate", newstate)
        self:RunAttribute("layout")
    ]],
}

Core.BAR_APPEAR, Core.BAR_GO, Core.BAR_SLIDE, Core.BAR_FADE = 0.25, 0.2, 0.2, 0.3
Core.BAR_GROW_FROM = 0.6
Core.BAR_PULSE, Core.BAR_PULSE_DIM = 1.2, 0.25

Core.MENU_OPEN, Core.MENU_CLOSE, Core.MENU_GROW_FROM = 0.1, 0.075, 0.6

Core.ANIM_SPEED_MIN, Core.ANIM_SPEED_MAX, Core.ANIM_SPEED_STEP = 0.3, 3, 0.1

function Core.ClampAnimSpeed(value)
    return Clamp(value, Core.ANIM_SPEED_MIN, Core.ANIM_SPEED_MAX, Core.ANIM_SPEED_STEP, Core.DEFAULTS.animation.speed)
end

Core.ALERT_BLINK = 0.4

Core.DECIMATION_RATIO = 0.75

Core.ALERT_TIME_SIZE = 15
Core.PROC_BUFFS = { shadowTrance = { 17941 }, decimation = { 63165, 63167 } }

Core.PROC_LENGTH_GUESS = { shadowTrance = 10 }

Core.FEAR_SPELLS = { fear = true, howlOfTerror = true, deathCoil = true }

Core.FEAR_IMMUNE_TYPES = { [6] = true, [9] = true }

Core.CONTROL_TARGET_TYPES = { banish = { [3] = true, [4] = true }, seduction = { [7] = true } }

Core.TARGET_CHECK_EVERY = 1

Core.TARGET_UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_FLAGS", "UNIT_FACTION", "UNIT_TARGETABLE_CHANGED" }

function Core.IsFearImmune(spellKey, action)
    return Core.FEAR_SPELLS[spellKey] == true and action == "IMMUNE"
end

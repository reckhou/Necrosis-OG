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

-- fade the buttons round sphere when mouse is away
local _, ns = ...
local Core = ns.Core
local Buttons = ns.Buttons

local AutoHide = {}
ns.AutoHide = AutoHide

local entries = {}
local menus, windows = {}, {}
local sphereOver = false
local combat = ns.Game.InCombat()

local driver = CreateFrame("Frame")

local function AnyVisible(list)
    for _, frame in ipairs(list) do
        if frame:IsVisible() then return true end
    end
    return false
end

-- check every button again and set opacity
local function Update(dt)
    if #entries == 0 then return end
    local saved = ns.db.sphere.autoHide
    local speed = ns.AnimationsOn() and ns.AnimationSpeed() or nil
    local state = {
        on = saved.on == true,
        free = ns.db.buttons.free == true,
        fadedAlpha = saved.fadedAlpha,
        combat = combat,
        combatShow = saved.combatShow ~= false,
        demo = ns.demo == true,
        placing = ns.placing == true,
        settings = AnyVisible(windows),
        menu = AnyVisible(menus),
        sphereOver = sphereOver,
        ringOver = false,
    }
    for _, entry in ipairs(entries) do
        if next(entry.mice) then state.ringOver = true end
    end
    local floor = Core.ClampFadedAlpha(state.fadedAlpha, state.free)
    local busy = false
    for _, entry in ipairs(entries) do
        state.over = next(entry.mice) ~= nil
        local held = Core.AutoHideHeld(state)
        if held or not state.on then
            entry.idle = 0
        else
            entry.idle = math.min(Core.AUTO_HIDE.delay, entry.idle + dt)
        end
        state.idle = entry.idle
        local target = Core.AutoHideTarget(state)
        local alpha = Core.AutoHideStep(entry.alpha, target, floor, dt, speed)
        if alpha ~= entry.alpha then
            entry.alpha = alpha
            entry.frame:SetAlpha(alpha)
        end
        if alpha ~= target or (state.on and not held and entry.idle < Core.AUTO_HIDE.delay) then busy = true end
    end
    driver:SetScript("OnUpdate", busy and AutoHide.Tick or nil)
end

function AutoHide.Tick(_, elapsed) Update(elapsed or 0) end

local function Changed() Update(0) end

local function Watch(list, frame)
    list[#list + 1] = frame
    frame:HookScript("OnShow", Changed)
    frame:HookScript("OnHide", Changed)
    Changed()
end

-- while spell menu is open every button show
function AutoHide.AddMenu(menu) Watch(menus, menu) end

function AutoHide.AddWindow(window) Watch(windows, window) end

-- tell when mouse come in or leave the frame
local function Hover(frame, over)
    local function Leave() over(false); Changed() end
    frame:HookScript("OnEnter", function() over(true); Changed() end)
    frame:HookScript("OnLeave", Leave)
    frame:HookScript("OnHide", Leave)
end

Buttons.OnCreate(function()
    Hover(Buttons.SphereButton(), function(on) sphereOver = on end)
    for _, slot in ipairs(Core.BUTTON_SLOTS) do
        local frame = Buttons.SlotFrame(slot)
        if frame then
            local entry = { frame = frame, mice = {}, alpha = 1, idle = 0 }
            entries[#entries + 1] = entry
            local areas = { frame }
            if slot == "weaponStone" then areas = { (Buttons.Stone("firestone")), (Buttons.Stone("spellstone")) } end
            for _, area in ipairs(areas) do
                Hover(area, function(on) entry.mice[area] = on or nil end)
            end
        end
    end
    Changed()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    combat = event == "PLAYER_REGEN_DISABLED"
    Changed()
end)

table.insert(ns.onPlacing, Changed)
table.insert(ns.onDemo, Changed)
ns.OnSetting({ "sphere.autoHide", "buttons.free", "animation" }, Changed)

AutoHide.Driver = function() return driver end

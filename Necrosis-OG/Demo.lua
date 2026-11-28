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

-- demo mode, show all buttons with fake data
local _, ns = ...
local Core = ns.Core
local InCombat = ns.Game.InCombat

ns.demo = false
ns.demoData = false
ns.onDemo = {}
ns.onDemoData = {}

function ns.SoundsOn() return ns.db.soundsOn ~= false end
function ns.Silent() return ns.demoData == true or not ns.SoundsOn() end

local clock
local repeats = {}
local onces = {}

local function Now() return GetTime() end

local function Tick()
    if not ns.demoData then return end
    local now = Now()
    for _, entry in ipairs(repeats) do
        if now >= entry.nextAt then
            entry.nextAt = now + entry.every
            entry.fn(now)
            if not ns.demoData then return end
        end
    end
    local due, kept = {}, {}
    for _, entry in ipairs(onces) do
        if now >= entry.at then due[#due + 1] = entry else kept[#kept + 1] = entry end
    end
    onces = kept
    table.sort(due, function(a, b) return a.at < b.at end)
    for _, entry in ipairs(due) do
        if not ns.demoData then return end
        entry.fn(now)
    end
end

-- call fn now, then every few sec while demo running
function ns.DemoEvery(seconds, fn)
    if not ns.demoData then return end
    repeats[#repeats + 1] = { every = seconds, nextAt = Now() + seconds, fn = fn }
    fn(Now())
end

function ns.DemoAt(time, fn)
    if not ns.demoData then return end
    onces[#onces + 1] = { at = time, fn = fn }
end

local function SetData(on)
    if ns.demoData == on then return end
    ns.demoData = on
    if on then
        clock = C_Timer.NewTicker(Core.DEMO.tick, Tick)
    else
        if clock then clock:Cancel() end
        clock = nil
        repeats, onces = {}, {}
    end
    ns.Fire(ns.onDemoData, on)
end

local function SetButtons(on)
    if ns.demo == on then return end
    ns.demo = on
    ns.Fire(ns.onDemo, on)
end

-- start or stop the demo, out of combat only
function ns.SetDemo(on)
    if InCombat() then return end
    if on == true then
        SetButtons(true)
        SetData(true)
    else
        SetData(false)
        SetButtons(false)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        SetData(false)
    elseif not ns.demoData then
        SetButtons(false)
    end
end)

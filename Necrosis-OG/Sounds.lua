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

-- interface sounds, all from the game
local _, ns = ...

local Sounds = {}
ns.Sounds = Sounds

local InCombat = ns.Game.InCombat

local KINDS = {
    click = { "IG_MAINMENU_OPTION", 852, 1 },
    checkOn = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856, 1 },
    checkOff = { "IG_MAINMENU_OPTION_CHECKBOX_OFF", 857, 1 },
    tab = { "IG_CHARACTER_INFO_TAB", 841, 1 },
    menuClose = { "IG_ABILITY_CLOSE", 835, 2 },
    menuOpen = { "IG_ABILITY_OPEN", 834, 3 },
    windowClose = { "IG_CHARACTER_INFO_CLOSE", 840, 4 },
    windowOpen = { "IG_CHARACTER_INFO_OPEN", 839, 5 },
    cancel = { "IG_MAINMENU_CLOSE", 851, 6 },
    ask = { "IG_MAINMENU_OPEN", 850, 7 },
    yes = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856, 8 },
}

local waiting

function Sounds.Enabled()
    return ns.db ~= nil and ns.SoundsOn()
end

local function Flush()
    local kind = waiting
    waiting = nil
    if not kind or type(PlaySound) ~= "function" then return end
    local def = KINDS[kind]
    pcall(PlaySound, type(SOUNDKIT) == "table" and SOUNDKIT[def[1]] or def[2])
end

function Sounds.Play(kind)
    if not Sounds.Enabled() then return end
    if not waiting then
        waiting = kind
        C_Timer.After(0, Flush)
    elseif KINDS[kind][3] > KINDS[waiting][3] then
        waiting = kind
    end
end

-- click sound for a button
function Sounds.Button(button, kind)
    button:HookScript("PostClick", function() Sounds.Play(kind or "click") end)
end

function Sounds.Check(box)
    box:HookScript("PostClick", function(self) Sounds.Play(self:GetChecked() and "checkOn" or "checkOff") end)
end

-- play sound when frame open and close
local function Watch(frame, openKind, closeKind, quietInCombat)
    frame:HookScript("OnShow", function(self)
        if self.nogWithInterface then
            self.nogWithInterface = nil
            return
        end
        self.nogHushed = nil
        Sounds.Play(openKind)
    end)
    frame:HookScript("OnHide", function(self)
        if self:IsShown() then
            self.nogWithInterface = true
            return
        end
        local hushed = self.nogHushed
        self.nogHushed = nil
        if hushed or (quietInCombat and InCombat()) then return end
        Sounds.Play(closeKind)
    end)
end

function Sounds.Window(frame) Watch(frame, "windowOpen", "windowClose", true) end
function Sounds.Menu(frame) Watch(frame, "menuOpen", "menuClose", false) end

function Sounds.Dialog(frame) Watch(frame, "ask", "cancel", true) end

-- next time the frame close with no sound
function Sounds.Hush(frame) frame.nogHushed = true end

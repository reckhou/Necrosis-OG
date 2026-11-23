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

-- action bar and pet buttons
local _, ns = ...

local ActionButtons = {}
ns.ActionButtons = ActionButtons

local BUTTONS_PER_BAR = 12
local PET_SLOTS = 10
local FALLBACK_BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
    "MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local PET_BARS = { "PetActionButton", "BT4PetButton" }
local LIBRARY = "LibActionButton-1.0"
local CALLBACKS = { "OnButtonCreated", "OnButtonUpdate" }

local listeners = {}
local watched
local Watch

local function IsButton(button) return type(button) == "table" and type(button.GetName) == "function" end

local function Library()
    local stub = _G.LibStub
    if not stub then return nil end
    local ok, lib = pcall(stub, LIBRARY, true)
    return ok and type(lib) == "table" and lib or nil
end

local function LibraryButtons()
    local lib = Library()
    if not (lib and type(lib.GetAllButtons) == "function") then return {} end
    Watch()
    local ok, set = pcall(lib.GetAllButtons, lib)
    if not ok or type(set) ~= "table" then return {} end
    local list = {}
    for button in pairs(set) do
        if IsButton(button) then list[#list + 1] = button end
    end
    table.sort(list, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end)
    return list
end

local function Visible(button)
    if type(button.IsVisible) ~= "function" then return true end
    local ok, on = pcall(button.IsVisible, button)
    return not ok or on ~= false
end

-- get visible blizzard buttons and bartender buttons
function ActionButtons.Bar()
    local extra = LibraryButtons()
    local names = ActionButtonUtil and ActionButtonUtil.ActionBarButtonNames or FALLBACK_BARS
    local found = {}
    for _, prefix in ipairs(names) do
        for i = 1, BUTTONS_PER_BAR do
            local button = _G[prefix .. i]
            if IsButton(button) and (#extra == 0 or Visible(button)) then found[#found + 1] = button end
        end
    end
    for _, button in ipairs(extra) do found[#found + 1] = button end
    return found
end

-- get pet buttons with their slot number
function ActionButtons.Pet()
    local found = {}
    for _, prefix in ipairs(PET_BARS) do
        for i = 1, PET_SLOTS do
            local button = _G[prefix .. i]
            if IsButton(button) then found[#found + 1] = { button = button, index = i } end
        end
    end
    return found
end

function ActionButtons.IsLibrary(button)
    local lib = Library()
    return lib ~= nil and type(lib.buttonRegistry) == "table" and lib.buttonRegistry[button] ~= nil
end

local function Changed(_, button)
    for _, fn in ipairs(listeners) do fn(button) end
end

function Watch()
    local lib = Library()
    if not lib or lib == watched or type(lib.RegisterCallback) ~= "function" then return end
    watched = lib
    for _, name in ipairs(CALLBACKS) do pcall(lib.RegisterCallback, ActionButtons, name, Changed) end
end

ActionButtons.Watch = Watch

-- call fn when library button change
function ActionButtons.OnChange(fn)
    listeners[#listeners + 1] = fn
    Watch()
end

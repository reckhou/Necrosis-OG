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

-- action bar and pet buttons
local _, ns = ...
local ActionButtons = {}
ns.ActionButtons = ActionButtons

local BUTTONS_PER_BAR = 12
local PET_SLOTS = 10
local FALLBACK_BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
    "MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local LIBRARIES = { "LibActionButton-1.0", "LibActionButton-1.0-ElvUI" }
local ELLESMERE_BARS = { "MainBar", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8", "Bar9", "Bar10" }
local ELLESMERE_BAR_SET = {}
for _, key in ipairs(ELLESMERE_BARS) do ELLESMERE_BAR_SET[key] = true end
local watched, listeners = {}, {}

local function IsButton(button) return type(button) == "table" and type(button.GetName) == "function" end

local function Changed(_, button)
    for _, fn in ipairs(listeners) do fn(button) end
end

local function Library(name)
    if not _G.LibStub then return end
    local ok, lib = pcall(_G.LibStub, name, true)
    if ok and type(lib) == "table" then return lib end
end

local function DominosController()
    return _G.Dominos and _G.Dominos.ActionButtons
end

local function Ellesmere()
    local mod = _G.EllesmereUI and _G.EllesmereUI._ModuleNS and _G.EllesmereUI._ModuleNS.EllesmereUIActionBars
    if type(mod) == "table" then return mod end
    if not _G.__EUISTANDALONE_ACTIONBARS_INERT then
        local standalone = _G.EUICoreStandaloneActionBars and _G.EUICoreStandaloneActionBars._ModuleNS
            and _G.EUICoreStandaloneActionBars._ModuleNS.EUIStandaloneActionBars
        if type(standalone) == "table" then return standalone end
    end
end

local function WatchLibrary(lib)
    if watched[lib] or type(lib.RegisterCallback) ~= "function" then return end
    lib.RegisterCallback(ActionButtons, "OnButtonCreated", Changed)
    lib.RegisterCallback(ActionButtons, "OnButtonUpdate", Changed)
    watched[lib] = true
end

local function WatchDominos(controller)
    if watched[controller] or type(controller.OnActionChanged) ~= "function" then return end
    hooksecurefunc(controller, "OnActionChanged", function(_, name) Changed(nil, _G[name]) end)
    if type(_G.Dominos.RegisterCallback) == "function" then
        _G.Dominos.RegisterCallback(ActionButtons, "LAYOUT_LOADED", Changed)
    end
    watched[controller] = true
end

local function WatchEllesmereBars()
    for _, key in ipairs(ELLESMERE_BARS) do
        local bar = _G["EABBar_" .. key]
        if type(bar) == "table" and not watched[bar] and type(bar.HookScript) == "function" then
            bar:HookScript("OnAttributeChanged", function(_, name)
                if name == "state-page" then Changed() end
            end)
            watched[bar] = true
        end
    end
end

local function WatchEllesmere(mod)
    WatchEllesmereBars()
    if type(hooksecurefunc) ~= "function" then return end
    if type(mod.EAB) == "table" and not watched[mod.EAB] and type(mod.EAB.FinishSetup) == "function" then
        hooksecurefunc(mod.EAB, "FinishSetup", function()
            WatchEllesmereBars()
            Changed()
        end)
        watched[mod.EAB] = true
    end
    if not watched[mod] and type(mod.BuildBarButtons) == "function" then
        hooksecurefunc(mod, "BuildBarButtons", function()
            WatchEllesmereBars()
            Changed()
        end)
        watched[mod] = true
    end
end

function ActionButtons.Watch()
    for _, name in ipairs(LIBRARIES) do
        local lib = Library(name)
        if lib then WatchLibrary(lib) end
    end
    local controller = DominosController()
    if controller then WatchDominos(controller) end
    local mod = Ellesmere()
    if mod then WatchEllesmere(mod) end
end

-- call fn when action bar button change
function ActionButtons.OnChange(fn)
    listeners[#listeners + 1] = fn
    ActionButtons.Watch()
end

function ActionButtons.IsLibrary(button)
    for _, name in ipairs(LIBRARIES) do
        local lib = Library(name)
        if lib and lib.buttonRegistry and lib.buttonRegistry[button] then return true end
    end
    return false
end

-- get bar key and module if button is from ellesmere ui
function ActionButtons.EllesmereBar(button)
    local mod = Ellesmere()
    local bars = mod and mod.barButtons
    if type(bars) ~= "table" then return nil end
    if type(button.GetParent) == "function" then
        local ok, parent = pcall(button.GetParent, button)
        local key = ok and type(parent) == "table" and parent._barKey
        if key and ELLESMERE_BAR_SET[key] then return key, mod end
    end
    for _, key in ipairs(ELLESMERE_BARS) do
        local list = bars[key]
        if type(list) == "table" then
            for _, each in pairs(list) do
                if each == button then return key, mod end
            end
        end
    end
end

-- get current action slot number of button
function ActionButtons.Slot(button)
    local controller = DominosController()
    if controller and controller.buttons and type(controller.buttons[button]) == "number" then
        return controller.buttons[button]
    end
    if ActionButtons.EllesmereBar(button) and type(button.GetAttribute) == "function" then
        local ok, slot = pcall(button.GetAttribute, button, "action")
        if ok and type(slot) == "number" then return slot end
    end
    return button.action
end

local function Visible(button)
    if type(button.IsVisible) ~= "function" then return true end
    local ok, on = pcall(button.IsVisible, button)
    return not ok or on ~= false
end

-- get visible blizzard buttons and action bar addon buttons
function ActionButtons.Bar()
    ActionButtons.Watch()
    local extra, seen = {}, {}
    local function Collect(button)
        if IsButton(button) and not seen[button] then
            seen[button] = true
            extra[#extra + 1] = button
        end
    end
    for _, name in ipairs(LIBRARIES) do
        local lib = Library(name)
        if lib and type(lib.GetAllButtons) == "function" then
            local ok, set = pcall(lib.GetAllButtons, lib)
            if ok and type(set) == "table" then
                for button in pairs(set) do Collect(button) end
            end
        end
    end
    local controller = DominosController()
    if controller and type(controller.buttons) == "table" then
        for button in pairs(controller.buttons) do Collect(button) end
    end
    local mod = Ellesmere()
    if mod and type(mod.barButtons) == "table" then
        for _, key in ipairs(ELLESMERE_BARS) do
            local list = mod.barButtons[key]
            if type(list) == "table" then
                for _, button in pairs(list) do Collect(button) end
            end
        end
    end
    table.sort(extra, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end)

    local names = ActionButtonUtil and ActionButtonUtil.ActionBarButtonNames or FALLBACK_BARS
    local found = {}
    for _, prefix in ipairs(names) do
        for i = 1, BUTTONS_PER_BAR do
            local button = _G[prefix .. i]
            if IsButton(button) and not seen[button] and (#extra == 0 or Visible(button)) then
                seen[button] = true
                found[#found + 1] = button
            end
        end
    end
    for _, button in ipairs(extra) do found[#found + 1] = button end
    return found
end

-- get pet buttons with their slot number
function ActionButtons.Pet()
    local found, seen = {}, {}
    local function Collect(button, index)
        if IsButton(button) and not seen[button] then
            seen[button] = true
            found[#found + 1] = { button = button, index = index }
        end
    end
    for i = 1, PET_SLOTS do
        Collect(PetActionBar and PetActionBar.actionButtons and PetActionBar.actionButtons[i], i)
        Collect(_G["PetActionButton" .. i], i)
        Collect(_G["BT4PetButton" .. i], i)
    end
    return found
end

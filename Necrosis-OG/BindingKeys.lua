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

-- show key of our macro on action bar slot
local _, ns = ...
local Core, Game = ns.Core, ns.Game
local Plain, IsSecret = Game.Plain, Game.IsSecret

local BindingKeys = {}
ns.BindingKeys = BindingKeys

local BUTTONS_PER_BAR = 12
local FALLBACK_BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
    "MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local FLASH = 0.12
local LIMIT = 2

local buttons = {}
local hooked = {}
local changed = {}
local pushed = {}
local down = {}

-- find all action bar button of blizzard
local function FindButtons()
    local names = ActionButtonUtil and ActionButtonUtil.ActionBarButtonNames or FALLBACK_BARS
    local found = {}
    for _, prefix in ipairs(names) do
        for i = 1, BUTTONS_PER_BAR do
            local button = _G[prefix .. i]
            if type(button) == "table" and button.GetName then found[#found + 1] = button end
        end
    end
    return found
end

local function ActionText(slot)
    local reader = C_ActionBar and C_ActionBar.GetActionText or GetActionText
    return type(reader) == "function" and Plain(reader, slot) or nil
end

local function MacroKey(button)
    local slot = button.action
    if type(slot) ~= "number" or IsSecret(slot) then return nil end
    local ok, kind = pcall(GetActionInfo, slot)
    if not ok or IsSecret(kind) or kind ~= "macro" then return nil end
    local name = ActionText(slot)
    if type(name) ~= "string" then return nil end
    return Core.MacroKeyOfName(name)
end

-- show necrosis key on the slot that have our macro
local function ShowKey(button)
    local hotkey = button.HotKey
    local key = hotkey and MacroKey(button)
    if not key then return end
    local bound = GetBindingKey(ns.Bindings.Command(key))
    if not bound then return end
    local text = GetBindingText(bound, 1)
    if type(text) ~= "string" or text == "" then return end
    hotkey:SetText(text)
    hotkey:Show()
    changed[button] = true
end

local function Refresh()
    buttons = FindButtons()
    for _, button in ipairs(buttons) do
        if not hooked[button] and type(button.UpdateHotkeys) == "function" then
            hooked[button] = true
            hooksecurefunc(button, "UpdateHotkeys", function() ShowKey(button) end)
        end
        if MacroKey(button) then
            ShowKey(button)
        elseif changed[button] then
            changed[button] = nil
            if type(button.UpdateHotkeys) == "function" then pcall(button.UpdateHotkeys, button, button.buttonType) end
        end
    end
end

BindingKeys.Refresh = Refresh

-- fake the pressed look on slot while key is down
local function SetPushed(key, on)
    for _, button in ipairs(buttons) do
        if MacroKey(button) == key and button.GetButtonState and button.SetButtonState then
            local state = button:GetButtonState()
            if on and state == "NORMAL" then
                pcall(button.SetButtonState, button, "PUSHED")
                pushed[button] = true
            elseif not on and pushed[button] then
                pushed[button] = nil
                if state == "PUSHED" then pcall(button.SetButtonState, button, "NORMAL") end
            end
        end
    end
end

local function After(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) end
end

function BindingKeys.Press(key, isDown)
    if isDown then
        local token = {}
        down[key] = token
        SetPushed(key, true)
        After(LIMIT, function()
            if down[key] == token then
                down[key] = nil
                SetPushed(key, false)
            end
        end)
    elseif down[key] then
        down[key] = nil
        SetPushed(key, false)
    else
        SetPushed(key, true)
        After(FLASH, function() if not down[key] then SetPushed(key, false) end end)
    end
end

table.insert(ns.onSphere, function()
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
        "UPDATE_BONUS_ACTIONBAR", "UPDATE_BINDINGS", "UPDATE_MACROS" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function() After(0, Refresh) end)
    Refresh()
end)

BindingKeys.Pushed = function(button) return pushed[button] == true end

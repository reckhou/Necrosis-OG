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

-- key binding actions
local _, ns = ...
local Core, Text, Buttons, Stones = ns.Core, ns.Text, ns.Buttons, ns.Stones
local SpellName, InCombat = ns.Game.SpellName, ns.Game.InCombat
local Bindings = {}
ns.Bindings = Bindings

local entries = {
    { key = "fear", spell = "fear", macro = true },
    { key = "banish", spell = "banish", macro = true },
    { key = "sacrifice", spell = "sacrifice", macro = true },
    { key = "seduction", spell = "seduction", macro = true },
    { key = "enslaveDemon", spell = "enslaveDemon", macro = true },
    { key = "curseOfWeakness", spell = "curseOfWeakness", macro = true },
    { key = "baneOfAgony", spell = "baneOfAgony", macro = true },
    { key = "curseOfExhaustion", spell = "curseOfExhaustion", macro = true },
    { key = "healthstone", label = "BIND_HEALTHSTONE" },
    { key = "hearthstone", label = "ACT_HEARTHSTONE" },
    { key = "soulstone", label = "BIND_SOULSTONE" },
    { key = "mount", label = "BIND_MOUNT" },
    { key = "lifeTap", spell = "lifeTap" },
    { key = "shadowWard", spell = "shadowWard" },
    { key = "lastBane", label = "BIND_LAST_BANE" },
}
local buttons = {}

local function Name(key) return "NecrosisOGBinding_" .. key end

function Bindings.Command(key) return "CLICK " .. Name(key) .. ":LeftButton" end

local function NameBindings()
    BINDING_HEADER_NECROSISOG = Text.SETTINGS_TITLE
    for _, entry in ipairs(entries) do
        local label = entry.label and Text[entry.label]
            or SpellName(Core.SPELLS[entry.spell][1])
        _G["BINDING_NAME_CLICK " .. Name(entry.key) .. ":LeftButton"] = label
    end
end

NameBindings()
table.insert(ns.onLoad, NameBindings)

-- macro for use the stone, limit is max chars
local function StoneMacro(kind, limit)
    local stone = Stones.Definition(kind)
    local held = Stones.State()
    local id = Core.HighestKnown(Core.SPELLS[stone.create], Buttons.IsKnown)
    local spell = id and SpellName(id)
    local createLine = not held[kind] and spell and ("/cast " .. spell) or nil
    local selfOnly = stone.onFriend and Stones.TargetIsNotPlayer()
    return Core.BoundMacro(Stones.List(kind), stone.onFriend, held[kind] and held[kind].id, createLine, limit, selfOnly)
end

Bindings.StoneMacro = StoneMacro

Buttons.OnCreate(function()
    for _, entry in ipairs(entries) do
        local button = CreateFrame("Button", Name(entry.key), UIParent, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetAttribute("useOnKeyDown", false)
        button:Hide()
        buttons[entry.key] = button
    end
    local tradeButton = CreateFrame("Button", "NecrosisOGHealthstoneTrade", UIParent, "SecureActionButtonTemplate")
    tradeButton:RegisterForClicks("AnyUp")
    tradeButton:SetAttribute("useOnKeyDown", false)
    tradeButton:SetAttribute("type1", "trade")
    tradeButton:Hide()
    Buttons.SetTradeAction(tradeButton, true)
    local handlers = {}
    Buttons.SetTradeAction(buttons.healthstone)
    handlers.healthstone = function(button, mouse) Buttons.PrepareTrade(button, mouse, true) end
    handlers.soulstone = function(button)
        if not InCombat() then
            button:SetAttribute("macrotext1", StoneMacro("soulstone"))
            if ns.SoulstoneShortcut and ns.SoulstoneShortcut.HoldFarUse(button, "target", "macrotext1") then return end
        end
        local held = Stones.State()
        if held.soulstone and ns.Speech then ns.Speech.Speak("soulstone", "friend") end
    end
    buttons.soulstone:SetScript("PostClick", function(self)
        if ns.SoulstoneShortcut then ns.SoulstoneShortcut.ReleaseFarUse(self) end
    end)
    handlers.hearthstone = function()
        local subject = ns.Mount.HearthSpeechSubject()
        if subject and ns.Speech then ns.Speech.Speak(subject) end
    end
    handlers.mount = function()
        if ns.Mount.WillSummon() and ns.Speech then
            ns.Speech.Speak("mount")
        end
    end
    for key, button in pairs(buttons) do
        button:SetScript("PreClick", function(self, mouse, isDown)
            if ns.BindingKeys then ns.BindingKeys.Press(key, isDown == true) end
            if isDown then return end
            if handlers[key] then handlers[key](self, mouse) end
        end)
    end
end)

Buttons.OnRefresh(function()
    for _, entry in ipairs(entries) do
        local button, key = buttons[entry.key], entry.key
        local actions
        if key == "healthstone" or key == "soulstone" then
            actions = { type1 = "macro", spell1 = false, macrotext1 = StoneMacro(key) }
        elseif entry.macro then
            local body = Buttons.MacroBody(key)
            actions = body and { type1 = "macro", spell1 = false, macrotext1 = body } or Buttons.CastActions(nil)
        elseif key == "hearthstone" then
            actions = { type1 = "item", item1 = "item:" .. Core.HEARTHSTONE_ITEM }
        elseif key == "mount" then
            -- mount button pick, second press dismount
            actions = { type1 = "macro", spell1 = false, macrotext1 = ns.Mount.Macro() }
        else
            local spellKey = entry.spell
            if key == "lastBane" then
                local saved = ns.db.buttons.lastBane
                if Core.IsBaneKey(saved) then spellKey = saved end
            end
            local id = spellKey and Core.HighestKnown(Core.SPELLS[spellKey], Buttons.IsKnown)
            actions = Buttons.CastActions(id)
        end
        Buttons.SetActions(button, actions)
    end
end)

Bindings.Button = function(key) return buttons[key] end

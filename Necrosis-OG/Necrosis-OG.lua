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

-- entry point of addon
local addonName, ns = ...
local Core, Text = ns.Core, ns.Text

-- print chat line with addon name prefix
function ns.Print(message)
    print(ns.Prefixed(message))
end

function ns.Prefixed(message)
    return Core.Gradient(Text.CHAT_PREFIX, Core.GRADIENT_TITLE) .. " " .. message
end

-- show line at top of screen with r, g, b color
function ns.Banner(message, red, green, blue)
    if not UIErrorsFrame then return end
    pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, ns.Prefixed(message), red, green, blue, 1.0)
end

function ns.TooltipsOn()
    return not (ns.db and ns.db.tooltips == false)
end

function ns.Version()
    return C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
end

-- run all functions of list, by the order they added
function ns.Fire(list, ...)
    local handler = type(geterrorhandler) == "function" and geterrorhandler() or nil
    if not handler then
        for _, fn in ipairs(list) do fn(...) end
        return
    end
    local count = select("#", ...)
    if count == 0 then
        for _, fn in ipairs(list) do xpcall(fn, handler) end
        return
    end
    local args, current = { ... }, nil
    local function Run() return current(unpack(args, 1, count)) end
    for _, fn in ipairs(list) do
        current = fn
        xpcall(Run, handler)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        self:UnregisterEvent("ADDON_LOADED")
        if Core.IsNewSettings(NecrosisOGDB) then
            NecrosisOGDB = Core.NewSettings()
        else
            NecrosisOGDB = Core.ApplyDefaults(NecrosisOGDB, Core.DEFAULTS)
        end
        ns.db = NecrosisOGDB
        ns.Fire(ns.onLoad, ns.db)
    end
end)

ns.onLoad = {}

ns.onSphere = {}

ns.onControlFailed = {}

ns.placing = false

ns.onPlacing = {}

ns.onRecall = {}

ns.onPetSpells = {}

ns.onSpellsChanged = {}

function ns.PetBank()
    return type(Enum) == "table" and type(Enum.SpellBookSpellBank) == "table" and Enum.SpellBookSpellBank.Pet or 1
end

local IsSecret, Plain, SpellName = ns.Game.IsSecret, ns.Game.Plain, ns.Game.SpellName

-- check spell in current pet book
function ns.PetKnows(spellID)
    return Plain(C_SpellBook.IsSpellKnown, spellID, ns.PetBank()) == true
end

-- read control spell ids from pet spellbook
function ns.LearnPetSpells()
    local book = C_SpellBook
    if type(book) ~= "table" or type(book.HasPetSpells) ~= "function" or type(book.GetSpellBookItemInfo) ~= "function" then
        return false
    end
    local count = Plain(book.HasPetSpells)
    if type(count) ~= "number" then return false end
    local items, bank = {}, ns.PetBank()
    for slot = 1, count do
        local got, info = pcall(book.GetSpellBookItemInfo, slot, bank)
        if got and type(info) == "table" and not IsSecret(info.spellID) and not IsSecret(info.name) then
            items[#items + 1] = { id = info.spellID, name = info.name }
        end
    end
    local added = false
    for key in pairs(Core.PET_CONTROL_SPELLS) do
        local got, name = pcall(C_Spell.GetSpellName, Core.SPELLS[key][1])
        if got and not IsSecret(name) and Core.LearnSpellIds(key, name, items) then added = true end
    end
    if added then
        ns.Fire(ns.onPetSpells)
    end
    return added
end

local petEvents = CreateFrame("Frame")
petEvents:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_PET" and unit ~= "player" then return end
    ns.LearnPetSpells()
    ns.Fire(ns.onSpellsChanged)
end)

table.insert(ns.onSphere, function()
    petEvents:RegisterEvent("SPELLS_CHANGED")
    petEvents:RegisterUnitEvent("UNIT_PET", "player")
end)

local popUps = {}

function ns.AnimationsOn()
    local saved = ns.db and ns.db.animation
    return type(saved) ~= "table" or saved.on ~= false
end

function ns.AnimationSpeed()
    local saved = ns.db and ns.db.animation
    return Core.ClampAnimSpeed(type(saved) == "table" and saved.speed or nil)
end

local function ApplySpeed(group)
    if type(group.SetAnimationSpeedMultiplier) == "function" then group:SetAnimationSpeedMultiplier(ns.AnimationSpeed()) end
end

-- play animation group at chosen speed
function ns.PopUpAnimation(group)
    popUps[#popUps + 1] = group
    ApplySpeed(group)
    return group
end

function ns.SetAnimationsOn(on)
    ns.db.animation.on = on == true
end

function ns.SetAnimationSpeed(value)
    ns.db.animation.speed = Core.ClampAnimSpeed(value)
    for _, group in ipairs(popUps) do ApplySpeed(group) end
end

function ns.SetPlacing(on)
    on = on == true and #ns.onPlacing > 0
    if ns.placing == on then return end
    ns.placing = on
    ns.Fire(ns.onPlacing, on)
end

local settingListeners = {}

-- fn(path, value) run when setting under prefix changed
function ns.OnSetting(prefix, fn)
    if type(prefix) == "table" then
        for _, each in ipairs(prefix) do ns.OnSetting(each, fn) end
        return
    end
    settingListeners[#settingListeners + 1] = { prefix = prefix, fn = fn }
end

-- write value to path in saved table then run listeners
function ns.SetSetting(path, value)
    local keys = Core.SplitPath(path)
    local holder = ns.db
    for i = 1, #keys - 1 do
        if type(holder[keys[i]]) ~= "table" then holder[keys[i]] = {} end
        holder = holder[keys[i]]
    end
    holder[keys[#keys]] = value
    local heard = {}
    for _, listener in ipairs(settingListeners) do
        if Core.PathUnder(path, listener.prefix) then heard[#heard + 1] = listener.fn end
    end
    ns.Fire(heard, path, value)
end

local ALERT_NAMES = {
    antiFear = function() return string.format(Text.SET_ANTI_FEAR, SpellName(Core.SPELLS.fear[1]) or "") end,
    shadowTrance = function() return SpellName(Core.SHADOW_TRANCE_ID) or Text.SET_SHADOW_TRANCE end,
    decimation = function() return Text.SET_DECIMATION end,
    amplifyCurse = function() return SpellName(Core.SPELLS.amplifyCurse[1]) or Text.SET_AMPLIFY_CURSE end,
}

function ns.AlertName(key) return ALERT_NAMES[key]() end

function ns.SetLocked(on)
    ns.db.locked = on == true
    ns.SetPlacing(not ns.db.locked)
end

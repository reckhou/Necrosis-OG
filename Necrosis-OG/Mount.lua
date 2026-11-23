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

-- mount button, left click summon random favourite mount and right click use hearthstone
local _, ns = ...
local Core, Text = ns.Core, ns.Text
local Buttons = ns.Buttons
local IsSecret, Plain, SpellName, InCombat = ns.Game.IsSecret, ns.Game.Plain, ns.Game.SpellName, ns.Game.InCombat

local Mount = {}
ns.Mount = Mount

local button
local pick   -- mount for next click
local ridden -- mount ride now
local pool = {}
local reroll -- summon happen, pick other mount next refresh

local function Mounted() return Plain(IsMounted) == true end

local function MountInfo(mountID)
    local journal = C_MountJournal
    if not journal or type(journal.GetMountInfoByID) ~= "function" then return nil end
    local ok, _, spellID, icon, active, usable, _, favourite, _, _, hidden, collected =
        pcall(journal.GetMountInfoByID, mountID)
    if not ok then return nil end
    for _, value in ipairs({ spellID, icon, active, usable, favourite, hidden, collected }) do
        if IsSecret(value) then return nil end
    end
    if type(spellID) ~= "number" then return nil end
    return { mountID = mountID, spellID = spellID, icon = icon, active = active == true, usable = usable == true,
        favourite = favourite == true, hidden = hidden == true, collected = collected == true }
end

-- whole mount collection
local function ReadCollection()
    local list = {}
    local ids = C_MountJournal and Plain(C_MountJournal.GetMountIDs)
    if type(ids) ~= "table" then return list end
    for _, id in ipairs(ids) do
        local mount = MountInfo(id)
        if mount then list[#list + 1] = mount end
    end
    return list
end

local function ActiveMount(collection)
    for _, mount in ipairs(collection) do
        if mount.active then return mount end
    end
    return nil
end

-- read collection and pick next mount
local function Choose()
    local collection = ReadCollection()
    local id = Core.PickSpell({ "felsteed", "dreadsteed" }, Buttons.IsKnown)
    local bookSteed = id and { spellID = id, icon = Plain(C_Spell.GetSpellTexture, id),
        usable = Plain(IsIndoors) ~= true and Plain(C_Spell.IsSpellUsable, id) ~= false }
    pool = Core.MountPool(collection, bookSteed)
    if Mounted() then
        ridden = ActiveMount(collection) or ridden or pick
    else
        ridden = nil
    end
    local keep = pick and not reroll and Core.MountInPool(pool, pick.spellID)
    if keep then
        pick = keep
    else
        local avoid = (ridden and ridden.spellID) or (pick and pick.spellID)
        pick = Core.NextMount(pool, avoid, math.random)
    end
    reroll = false
end

local function Wear()
    local mounted = Mounted()
    local shown = mounted and ridden or pick
    if shown and shown.icon then
        Buttons.ShowRing(button, true)
        button.icon:SetTexture(shown.icon)
        button.icon:SetTexCoord(0, 1, 0, 1)
    else
        Buttons.ShowRing(button, false)
        button.icon:SetTexture(Core.UiTexture("MountButton-01"))
        button.icon:SetTexCoord(0, 1, 0, 1)
    end
    local grey = shown == nil or (not mounted and not Mount.WillSummon())
    button.icon:SetDesaturated(grey and not ns.demo)
    ns.Rings.ShowGlow(button.lit, mounted)
end

local function GlobalCooldownLength()
    local info = Plain(C_Spell.GetSpellCooldown, Core.GLOBAL_COOLDOWN_SPELL)
    local length = type(info) == "table" and info.duration
    if type(length) == "number" and not IsSecret(length) and length > 0 and length <= 2 then return length end
    return Core.MOUNT_SWIPE
end

-- mount cast in sec, use global cooldown for instant cast
local function CastLength(spellID)
    local info = Plain(C_Spell.GetSpellInfo, spellID)
    local ms = type(info) == "table" and info.castTime
    if type(ms) == "number" and not IsSecret(ms) and ms > 0 then return ms / 1000 end
    return GlobalCooldownLength()
end

local function ClearSwipe()
    pcall(button.cooldown.SetCooldown, button.cooldown, 0, 0)
end

local function IsMountSpell(spellID)
    if type(spellID) ~= "number" or IsSecret(spellID) then return false end
    if (pick and pick.spellID == spellID) or Core.MountInPool(pool, spellID) or Core.SteedRank(spellID) then return true end
    local journal = C_MountJournal
    return journal ~= nil and type(journal.GetMountFromSpell) == "function"
        and Plain(journal.GetMountFromSpell, spellID) ~= nil
end

-- can use hearthstone now, and the note for the tooltip
local function HearthState()
    local count = Plain(C_Item.GetItemCount, Core.HEARTHSTONE_ITEM)
    if count == 0 then return false, Text.TIP_HEARTH_NONE end
    if not count then return false end
    local ok, start, duration, enabled = pcall(C_Container.GetItemCooldown, Core.HEARTHSTONE_ITEM)
    if not ok or IsSecret(start) or IsSecret(duration) or IsSecret(enabled) then return false end
    if type(start) ~= "number" or type(duration) ~= "number" then return false end
    local left = Core.CooldownLeft(start, duration, GetTime())
    if left > 0 then return false, string.format(Text.TIP_HEARTH_COOLING, Core.TimerText(left)) end
    return enabled == 1 and not InCombat()
end

function Mount.HearthSpeechSubject()
    if HearthState() then return "hearthstone" end
end

local function Tooltip(tooltip)
    local mounted = Mounted()
    local shown = mounted and ridden or pick
    Buttons.SpellTooltip(tooltip, shown and shown.spellID, Core.SPELLS.felsteed[1])
    ns.Tips.Click(tooltip, "left", mounted and Text.ACT_DISMOUNT or (pick and Text.ACT_MOUNT))
    ns.Tips.Click(tooltip, "right", Text.ACT_HEARTHSTONE)
    if not mounted and pick then
        ns.Tips.Note(tooltip, pick.favourite and Text.TIP_MOUNT_FAVOURITE or Text.TIP_MOUNT_NO_FAVOURITE)
    end
    local _, hearthNote = HearthState()
    ns.Tips.Note(tooltip, hearthNote)
end

-- macro for left click, key binding use it too
function Mount.Macro()
    return Core.MountMacro(pick and SpellName(pick.spellID))
end

-- pick can be summon here and now, hide answer count as usable
local function PickUsable()
    if pick.mountID and C_MountJournal and type(C_MountJournal.GetMountUsabilityByID) == "function" then
        local ok, usable = pcall(C_MountJournal.GetMountUsabilityByID, pick.mountID, true)
        if ok and usable ~= nil and not IsSecret(usable) then return usable == true end
    end
    if Plain(IsIndoors) == true then return false end
    return Plain(C_Spell.IsSpellUsable, pick.spellID) ~= false
end

function Mount.WillSummon()
    if pick == nil or Mounted() or InCombat() then return false end
    return PickUsable()
end

Buttons.OnCreate(function(sphere)
    button = Buttons.NewSecureButton("NecrosisOGMountButton", sphere, Core.BUTTON_SIZE)
    button:SetScale(Core.BUTTON_SCALE)
    button.icon:SetTexture(Core.UiTexture("MountButton-01"))
    ns.Rings.Attach(button, button, "MountButton")
    button.tooltip = Tooltip
    button.speechSubject = function(mouse)
        if mouse == "RightButton" then return Mount.HearthSpeechSubject() end
        if Mount.WillSummon() then return "mount", nil end
    end
    Buttons.AddSlot("mount", button)
    button.lit = ns.Rings.NewGlow(button, "MountButton")
    ns.Rings.ShowGlow(button.lit, false)
    button.cooldown = ns.Durations.NewSwipe(button, { level = 4 })

    local casts = CreateFrame("Frame")
    casts:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    casts:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    casts:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    casts:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
    casts:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    casts:SetScript("OnEvent", function(_, event, _, a, b, c)
        if event == "UNIT_SPELLCAST_SENT" then
            if ns.demo or not IsMountSpell(c) then return end
            pcall(button.cooldown.SetCooldown, button.cooldown, GetTime(), CastLength(c))
        elseif event == "UNIT_SPELLCAST_START" then
            if ns.demo or not IsMountSpell(b) then return end
            local ok, _, _, _, from, to = pcall(UnitCastingInfo, "player")
            if ok and type(from) == "number" and type(to) == "number" and not IsSecret(from) and not IsSecret(to)
                and to > from then
                pcall(button.cooldown.SetCooldown, button.cooldown, from / 1000, (to - from) / 1000)
            end
        else
            if IsMountSpell(b) then ClearSwipe() end
        end
    end)

    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    events:RegisterEvent("NEW_MOUNT_ADDED")
    events:RegisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED")
    events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    local wearOnly = { PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true, ZONE_CHANGED_INDOORS = true,
        ZONE_CHANGED = true, SPELL_UPDATE_USABLE = true }
    for event in pairs(wearOnly) do events:RegisterEvent(event) end
    events:SetScript("OnEvent", function(_, event)
        if wearOnly[event] then
            Wear()
            return
        end
        if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
            if Mounted() then
                local collection = ReadCollection()
                ridden = ActiveMount(collection) or pick
                reroll = true
            else
                ridden = nil
            end
            Wear()
            if reroll then Buttons.Refresh() end
            return
        end
        Wear()
        Buttons.Refresh()
    end)
end)

-- watch for favourite mount changes
local hooked

local function HookFavourites()
    if hooked or not C_MountJournal or type(C_MountJournal.SetIsFavorite) ~= "function" then return end
    hooked = true
    hooksecurefunc(C_MountJournal, "SetIsFavorite", function()
        if not InCombat() then Buttons.Refresh() end
    end)
end

Buttons.OnRefresh(function()
    HookFavourites()
    Choose()
    Buttons.SetActions(button, { ["type*"] = "macro", ["macrotext*"] = Mount.Macro(), ["spell*"] = false,
        type2 = "item", item2 = "item:" .. Core.HEARTHSTONE_ITEM })
    Wear()
    button.wanted = pick ~= nil or Buttons.DemoMode()
end)

Mount.Button = function() return button end
Mount.Pick = function() return pick end

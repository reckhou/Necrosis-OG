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

-- stones in bags, learned ranks, weapon enchant and cooldown
local _, ns = ...
local Core, Text = ns.Core, ns.Text
local Stones = { changed = {} }
ns.Stones = Stones
local IsSecret, Plain = ns.Game.IsSecret, ns.Game.Plain
local STONES = {
    healthstone = { list = Core.HEALTHSTONES, create = "createHealthstone", art = "HealthstoneButton",
        name = "NecrosisOGHealthstoneButton", noStone = "NO_HEALTHSTONE", alwaysUse = true },
    soulstone = { list = Core.SOULSTONES, create = "createSoulstone", art = "SoulstoneButton",
        name = "NecrosisOGSoulstoneButton", noStone = "NO_SOULSTONE", onFriend = true, alwaysUse = true },
    firestone = { list = Core.FIRESTONES, create = "createFirestone", art = "FirestoneButton",
        name = "NecrosisOGFirestoneButton", noStone = "NO_FIRESTONE", onWeapon = true },
    spellstone = { list = Core.SPELLSTONES, create = "createSpellstone", art = "SpellstoneButton",
        name = "NecrosisOGSpellstoneButton", noStone = "NO_SPELLSTONE", onWeapon = true },
}
Stones.KINDS = { "firestone", "spellstone", "healthstone", "soulstone" }

-- item ids of the stone kind, include learned ones
local function StoneList(kind)
    local list = {}
    for _, id in ipairs(STONES[kind].list) do list[#list + 1] = id end
    local learned = ns.db and ns.db.buttons.learnedStones[kind]
    if type(learned) == "table" then
        for _, id in ipairs(learned) do if type(id) == "number" then list[#list + 1] = id end end
    end
    return list
end

local function BuildStoneLists()
    for kind, stone in pairs(STONES) do
        local list = StoneList(kind)
        stone.items = Core.ToSet(list)
        stone.useMacro = Core.UseMacro(list, stone.onFriend)
        stone.selfMacro = stone.onFriend and Core.UseMacro(list, true, true) or nil
        if stone.onWeapon then stone.useMacro = stone.useMacro .. "\n/use " .. Core.MAIN_HAND_SLOT end
    end
end

local CREATE_SPELLS = {}
for kind, stone in pairs(STONES) do
    for _, id in ipairs(Core.SPELLS[stone.create]) do CREATE_SPELLS[id] = kind end
end

local held = {}
local equipped = {}
local bagItems = {}
local awaiting = {}

local function ScanBags()
    local found, items = {}, {}
    local lastBag = type(NUM_BAG_SLOTS) == "number" and NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        local count = Plain(C_Container.GetContainerNumSlots, bag)
        if type(count) == "number" then
            for slot = 1, count do
                local id = Plain(C_Container.GetContainerItemID, bag, slot)
                if type(id) == "number" then
                    items[id] = true
                    for kind, stone in pairs(STONES) do
                        if stone.items[id] and not found[kind] then found[kind] = { id = id, bag = bag, slot = slot } end
                    end
                end
            end
        end
    end
    return found, items
end

-- new item after Create cast is that stone, save it
local function LearnNewStone(kind, items)
    local started = awaiting[kind]
    if not started then return false end
    if held[kind] then
        awaiting[kind] = nil
        return false
    end
    local learned = false
    for id in pairs(items) do
        if not bagItems[id] then
            table.insert(ns.db.buttons.learnedStones[kind], id)
            learned = true
        end
    end
    if learned or GetTime() - started > 5 then awaiting[kind] = nil end
    return learned
end

-- if weapon has temp enchant and the sec left
local function ReadEnchant(slotName, slotNumber)
    local slot = Enum and Enum.WeaponSlot and Enum.WeaponSlot[slotName] or slotNumber
    local enchants = Plain(C_Item and C_Item.GetWeaponEnchantInfo, slot)
    local ok, has, left = pcall(Core.TempEnchant, enchants)
    if not ok then return false, nil end
    return has, left
end

local enchantSpan = {}

local function AttributedKind()
    local saved = ns.db.buttons.weaponStone
    if saved == "firestone" or saved == "spellstone" then return saved end
    local known = ns.Buttons and ns.Buttons.IsKnown or function() return false end
    return Stones.WeaponKind(known) or "firestone"
end

local hasMainHand = false

local function ReadEquipped()
    local found = {}
    enchantSpan = {}
    hasMainHand = type(Plain(GetInventoryItemID, "player", Core.MAIN_HAND_SLOT)) == "number"
    local has, left = ReadEnchant("MainHand", 0)
    if has then
        local kind = AttributedKind()
        found[kind] = true
        if left then
            local start, length, ending = Core.EnchantSpan(left, GetTime())
            enchantSpan[kind] = { start = start, length = length, ending = ending }
        end
    end
    return found
end

-- stone in bags, else last one seen
local function CooldownItem(kind)
    if held[kind] then return held[kind].id end
    local saved = ns.db.buttons[kind]
    if type(saved) == "number" and saved > 0 then return saved end
    return nil
end

function Stones.Refresh()
    local found, items = ScanBags()
    local learned = false
    held = found
    for kind in pairs(STONES) do
        if LearnNewStone(kind, items) then learned = true end
    end
    if learned then
        BuildStoneLists()
        found, items = ScanBags()
    end
    held = found
    equipped = ReadEquipped()
    for kind, stone in pairs(held) do ns.db.buttons[kind] = stone.id end
    bagItems = items
    ns.Fire(Stones.changed)
end

function Stones.State() return held, equipped end

function Stones.HasMainHandWeapon() return hasMainHand end
function Stones.MainHandEnchanted() return equipped.firestone == true or equipped.spellstone == true end

-- which stone the weapon reminder put on
function Stones.WeaponKind(isKnown)
    local function Learned(kind) return Core.HighestKnown(Core.SPELLS[STONES[kind].create], isKnown) ~= nil end
    local saved = ns.db.buttons.weaponStone
    if (saved == "firestone" or saved == "spellstone") and Learned(saved) then return saved end
    if Learned("spellstone") then return "spellstone" end
    if Learned("firestone") then return "firestone" end
    return nil
end

function Stones.NoteApplied(kind)
    if STONES[kind] and STONES[kind].onWeapon then ns.db.buttons.weaponStone = kind end
end

function Stones.Definition(kind) return STONES[kind] end
function Stones.List(kind) return StoneList(kind) end

function Stones.TargetIsNotPlayer()
    return Plain(UnitExists, "target") == true and Plain(UnitIsPlayer, "target") == false
end

-- use macro of stone for current target
function Stones.UseMacro(kind)
    local stone = STONES[kind]
    if stone.selfMacro and Stones.TargetIsNotPlayer() then return stone.selfMacro end
    return stone.useMacro
end

local function GameCooldown(kind)
    local id = CooldownItem(kind)
    if not id then return nil end
    local ok, start, duration = pcall(C_Container.GetItemCooldown, id)
    if not ok then return nil end
    return start, duration, IsSecret(start) or IsSecret(duration)
end

-- return start, length, hidden and enchant end
function Stones.Cooldown(kind)
    local span = enchantSpan[kind]
    if span and span.ending > GetTime() then
        return span.start, span.length, false, span.ending
    end
    local start, duration, hidden = GameCooldown(kind)
    if kind ~= "soulstone" or hidden then return start, duration, hidden end
    local left = start ~= nil and Core.CooldownLeft(start, duration, GetTime()) or 0
    local cooling, seconds, length = Stones.SoulstoneCoolingBySave()
    if cooling and seconds > left then return GetTime() + seconds - length, length, false end
    return start, duration, false
end

local function RememberSoulstoneLength()
    local _, duration, hidden = GameCooldown("soulstone")
    if not hidden and type(duration) == "number" and duration > 60 then ns.db.buttons.soulstoneLength = duration end
end

-- check saved soulstone use time if cooldown still runing
function Stones.SoulstoneCoolingBySave()
    local at, length = ns.db.buttons.soulstoneAt, ns.db.buttons.soulstoneLength
    if type(length) ~= "number" or length <= 0 then length = Core.SOULSTONE_COOLDOWN end
    if type(at) ~= "number" or at <= 0 then return false, 0, length end
    local left = at + length - ((GetServerTime and GetServerTime()) or time())
    return left > 0, math.max(0, left), length
end

function Stones.EnchantSpan(kind)
    local span = enchantSpan[kind]
    if not span or span.ending <= GetTime() then return nil end
    return span.start, span.length, CooldownItem(kind)
end

local events = CreateFrame("Frame")

local pendingSoulstone
events:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4)
    if event == "UNIT_SPELLCAST_SENT" then
        if unit == "player" and not IsSecret(arg4) and arg4 == Core.SOULSTONE_USE_SPELL then
            pendingSoulstone = (not IsSecret(arg2) and type(arg2) == "string") and arg2 or ""
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local spellID = arg3
        if unit == "player" and not IsSecret(spellID) and CREATE_SPELLS[spellID] then
            awaiting[CREATE_SPELLS[spellID]] = GetTime()
        end
        if unit == "player" and not IsSecret(spellID) and spellID == Core.SOULSTONE_USE_SPELL then
            ns.db.buttons.soulstoneTarget = pendingSoulstone or ""
            ns.db.buttons.soulstoneAt = (GetServerTime and GetServerTime()) or time()
            pendingSoulstone = nil
        end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        RememberSoulstoneLength()
        ns.Fire(Stones.changed)
    elseif event ~= "UNIT_INVENTORY_CHANGED" or unit == "player" then
        Stones.Refresh()
    end
end)

table.insert(ns.onLoad, BuildStoneLists)
table.insert(ns.onSphere, function()
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_COOLDOWN" }) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({ "UNIT_INVENTORY_CHANGED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" }) do
        events:RegisterUnitEvent(event, "player")
    end
    Stones.Refresh()
end)

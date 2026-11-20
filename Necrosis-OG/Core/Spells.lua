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

-- spell data and rules
local _, ns = ...
local Core = ns.Core

Core.SPELLS = {
    createHealthstone = { 6201, 6202, 5699, 11729, 11730 },
    createSoulstone = { 693, 20752, 20755, 20756, 20757 },
    felDomination = { 18708 },
    healthFunnel = { 755, 3698, 3699, 3700, 11693, 11694, 11695 }, senseDemons = { 5500 },
    lifeTap = { 1454, 1455, 1456, 11687, 11688, 11689 },
    drainSoul = { 1120, 8288, 8289, 11675 },
    drainMana = { 5138, 6226, 11703, 11704 },
    soulLink = { 19028 }, demonicSacrifice = { 18788 },
    demonicPact = { 425464 },
    imp = { 688 }, voidwalker = { 697 }, succubus = { 712 }, incubus = { 713 }, felhunter = { 691 },
    inferno = { 1122 }, ritualOfDoom = { 18540 },
    demonSkin = { 687, 696 },
    demonArmor = { 706, 1086, 11733, 11734, 11735 },
    unendingBreath = { 5697 },
    detectInvisibility = { 132, 2970, 11743 },
    eyeOfKilrogg = { 126 },
    ritualOfSummoning = { 698 },
    shadowWard = { 6229, 11739, 11740 },
    banish = { 710, 18647 },
    enslaveDemon = { 1098, 11725, 11726 },
    fear = { 5782, 6213, 6215 },
    deathCoil = { 6789, 17925, 17926 },
    howlOfTerror = { 5484, 17928 },
    seduction = { 6358 },
    createFirestone = { 6366, 17951, 17952, 17953 },
    createSpellstone = { 2362, 17727, 17728 },
    felsteed = { 5784 }, dreadsteed = { 23161 },
    shadowBolt = { 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307 },
    soulFire = { 6353, 17924 },
    amplifyCurse = { 18288 },
    curseOfWeakness = { 702, 1108, 6205, 7646, 11707, 11708 },
    curseOfRecklessness = { 704, 7658, 7659, 11717 },
    curseOfTongues = { 1714, 11719 },
    curseOfExhaustion = { 18223 },
    curseOfElements = { 440892, 1311676, 1311677, 1311680 },
    baneOfAgony = { 980, 1014, 6217, 11711, 11712, 11713 },
    baneOfDoom = { 603 },
    baneOfHavoc = { 1225228 },
    corruption = { 172, 6222, 6223, 7648, 11671, 11672, 25311 },
    immolate = { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309 },
    siphonLife = { 18265, 18879, 18880, 18881 },
}

Core.CURSE_KEYS = { "curseOfWeakness", "baneOfAgony", "curseOfTongues", "curseOfExhaustion", "curseOfElements",
    "curseOfRecklessness", "baneOfDoom" }
Core.CURSE_IDS = {}
for _, key in ipairs(Core.CURSE_KEYS) do
    for _, id in ipairs(Core.SPELLS[key]) do Core.CURSE_IDS[#Core.CURSE_IDS + 1] = id end
end

Core.PLAIN_CURSE_KEYS = { "curseOfWeakness", "curseOfTongues", "curseOfExhaustion", "curseOfElements", "curseOfRecklessness" }
Core.BANE_KEYS = { "baneOfAgony", "baneOfDoom" }

-- set of all rank ids of spells by keys
function Core.SpellIdSet(keys)
    local set = {}
    for _, key in ipairs(keys) do
        for _, id in ipairs(Core.SPELLS[key]) do set[id] = true end
    end
    return set
end

Core.FOCUS_ICONS = {
    { key = "banish", spell = "banish", row = 1, fit = "banish", switch = "banish" },
    { key = "seduction", spell = "seduction", row = 1, fit = "seduction", pet = true, switch = "seduction" },
    { key = "fear", spell = "fear", row = 1, fit = "fear", switch = "fear" },
    { key = "curseOfRecklessness", spell = "curseOfRecklessness", row = 1, fit = "fear", rankOne = true, switch = "fear" },
    { key = "curseOfWeakness", spell = "curseOfWeakness", row = 1, fit = "fear", rankOne = true, switch = "fear" },
    { key = "deathCoil", spell = "deathCoil", row = 1, fit = "fear", switch = "deathCoil" },
}

Core.FOCUS_SWITCHES = { "banish", "seduction", "fear", "deathCoil" }

function Core.FocusIconOn(key, off)
    local def = Core.FOCUS_ICON_BY_KEY[key]
    if not def then return false end
    return not (type(off) == "table" and off[def.switch] == true)
end

Core.FOCUS_ROW_COUNT = 1

Core.FOCUS_ICON, Core.FOCUS_ICON_GAP = 40, -4
Core.FOCUS_HANDLE = 18 -- px high

Core.FOCUS_TIME_SIZE = 16

Core.FOCUS_RANGE_ALPHA, Core.FOCUS_RANGE_SECONDS = 0.5, 0.2
Core.FOCUS_ICON_BY_KEY = {}
for _, def in ipairs(Core.FOCUS_ICONS) do Core.FOCUS_ICON_BY_KEY[def.key] = def end

Core.FOCUS_MAX_PER_ROW = 0
do
    local counts = {}
    for _, def in ipairs(Core.FOCUS_ICONS) do
        counts[def.row] = (counts[def.row] or 0) + 1
        Core.FOCUS_MAX_PER_ROW = math.max(Core.FOCUS_MAX_PER_ROW, counts[def.row])
    end
end

-- key -> { col, row } for each shown icon
function Core.FocusLayout(shown)
    local places, cols = {}, {}
    for _, def in ipairs(Core.FOCUS_ICONS) do
        if shown[def.key] then
            local col = cols[def.row] or 0
            places[def.key] = { col = col, row = def.row - 1 }
            cols[def.row] = col + 1
        end
    end
    return places
end

function Core.FocusIconIds(def) return Core.SpellIdSet({ def.spell }) end

-- spell id to cast, rank 1 or highest known rank
function Core.FocusIconSpell(def, isKnown, everything)
    local ranks = Core.SPELLS[def.spell]
    local highest = Core.HighestKnown(ranks, isKnown)
    if not highest and not everything then return nil end
    if def.rankOne then return ranks[1] end
    return highest or ranks[#ranks]
end

function Core.FocusIconOfSpell(spellID)
    for _, def in ipairs(Core.FOCUS_ICONS) do
        if Core.FocusIconIds(def)[spellID] then return def.key end
    end
    return nil
end

function Core.FocusIconFits(key, typeID)
    local def = Core.FOCUS_ICON_BY_KEY[key]
    local fit = def and def.fit
    if fit == "banish" or fit == "seduction" then return Core.CONTROL_TARGET_TYPES[fit][typeID] == true end
    if fit == "fear" then return Core.FEAR_IMMUNE_TYPES[typeID] ~= true end
    return true
end

Core.ENEMY_SLOTS = {
    { key = "bane", keys = Core.BANE_KEYS },
    { key = "corruption", keys = { "corruption" } },
    { key = "immolate", keys = { "immolate" } },
    { key = "siphonLife", keys = { "siphonLife" } },
    { key = "curse", keys = Core.PLAIN_CURSE_KEYS },
}

-- the columns which charactor knows a spell for
function Core.EnemySlotsKnown(isKnown, everything, off)
    local slots = {}
    for _, slot in ipairs(Core.ENEMY_SLOTS) do
        local known = everything
        for _, key in ipairs(slot.keys) do
            if Core.HighestKnown(Core.SPELLS[key], isKnown) then known = true end
        end
        if known and not (off and off[slot.key]) then slots[#slots + 1] = slot end
    end
    return slots
end

function Core.EnemySlotOfSpell(spellID)
    for _, slot in ipairs(Core.ENEMY_SLOTS) do
        if Core.SpellIdSet(slot.keys)[spellID] then return slot.key end
    end
    return nil
end

function Core.EnemySlotSpellKey(slotKey, spellID)
    for _, slot in ipairs(Core.ENEMY_SLOTS) do
        if slot.key == slotKey then
            for _, key in ipairs(slot.keys) do
                for _, id in ipairs(Core.SPELLS[key]) do
                    if id == spellID then return key end
                end
            end
        end
    end
    return nil
end

Core.FOCUS_MACRO_KEYS = { "fear", "banish", "enslaveDemon" }
Core.FOCUS_MACROS = { fear = "NOG Fear", banish = "NOG Banish", enslaveDemon = "NOG Subjugate" }

Core.STONE_MACRO_KEYS = { "healthstone" }
Core.STONE_MACROS = { healthstone = "NOG Healthstone" }
Core.STONE_MACRO_SPELLS = { healthstone = "createHealthstone" }

-- macro text for cast on focus
function Core.FocusMacroBody(spellName, focus)
    local lines = { "#showtooltip" }
    if focus then lines[#lines + 1] = "/focus [harm]" end
    lines[#lines + 1] = "/cast " .. spellName
    return table.concat(lines, "\n")
end

Core.CONTROL_BUTTON_KEYS = { "armour", "healthstone", "soulLink", "demon", "sacrifice", "weaponStone", "soulstone",
    "unendingBreath" }

Core.SOULLINK_AURAS = { 25228, 19028 }
Core.SACRIFICE_AURAS = { 18789, 18790, 18791, 18792 }
Core.DEMON_SUMMON_KEYS = { "imp", "voidwalker", "succubus", "incubus", "felhunter" }
Core.CONTROL_BUTTONS = {
    armour = { spells = { "demonSkin", "demonArmor" }, art = "Armor", picture = "-01", missing = "buff" },
    healthstone = { spells = { "createHealthstone" }, art = "HealthstoneButton", picture = "-02",
        missing = "stone", stone = "healthstone" },
    soulLink = { spells = { "soulLink" }, art = "Ring", gameIcon = true, missing = "buff",
        auras = Core.SOULLINK_AURAS, needsPet = true },
    demon = { spells = Core.DEMON_SUMMON_KEYS, art = "PetMenuButton", picture = "-01",
        missing = "demon", label = "SET_ALERT_DEMON" },
    sacrifice = { spells = { "demonicSacrifice" }, art = "Ring", gameIcon = true, missing = "buff",
        auras = Core.SACRIFICE_AURAS, learned = "sacAuras", needsPet = true, requires = "demonicPact" },
    weaponStone = { spells = { "createFirestone", "createSpellstone" }, art = "FirestoneButton", picture = "-02",
        missing = "enchant", label = "SET_ALERT_WEAPON_STONE" },
    soulstone = { spells = { "createSoulstone" }, art = "SoulstoneButton", picture = "-02",
        missing = "soulstoneReady", label = "SET_ALERT_SOULSTONE" },
    unendingBreath = { spells = { "unendingBreath" }, art = "Ring", gameIcon = true, missing = "breath", alwaysShow = true },
}

function Core.DemonAgainMacro(dominationName, demonName, keep)
    return Core.DemonSummonMacro(dominationName, demonName, true, keep)
end

-- fel domination then summon, in one click
function Core.DemonSummonMacro(dominationName, demonName, combatOnly, keep)
    if not demonName then return nil end
    if not dominationName then return "/cast " .. demonName end
    local when = combatOnly and " [combat]" or ""
    local stop = keep and "" or ("/stopcasting" .. when .. "\n")
    return "/cast" .. when .. " " .. dominationName .. "\n" .. stop .. "/cast " .. demonName
end

Core.KEEP_SUMMON = [[
    local keep = self:GetAttribute("summonkeep")
    if keep then self:SetAttribute("macrotext2", keep) end
    local owner = self:GetFrameRef("owner")
    local ownerKeep = owner and owner:GetAttribute("summonkeep")
    if ownerKeep then owner:SetAttribute("macrotext2", ownerKeep) end
]]

function Core.DemonPickerOffset(i)
    local reminderHalf = Core.BUTTON_SIZE / 2 * Core.CONTROL_ICON_SCALE / Core.BUTTON_SCALE
    return reminderHalf + Core.MENU_ITEM_SIZE / 2 + (i - 1) * Core.MENU_ITEM_STEP
end

function Core.DemonArt(key)
    for _, entry in ipairs(Core.DEMON_MENU) do
        if entry.demon and entry.keys[1] == key then return entry.art end
    end
    return nil
end

-- if the no demon alert show
function Core.NoDemonAlert(state)
    if state.petOut or state.dead or state.mounted or state.onTaxi then return false end
    if state.sacrificed and not state.pact then return false end
    return true
end

-- demon to summon, last one or best learned
function Core.DemonToSummon(known, last, sacrificedKey, avoidSacrificed)
    local avoid = avoidSacrificed and sacrificedKey ~= "" and sacrificedKey or nil
    if known[last] and last ~= avoid then return last end
    for i = #Core.DEMON_SUMMON_KEYS, 1, -1 do
        local key = Core.DEMON_SUMMON_KEYS[i]
        if known[key] and key ~= avoid then return key end
    end
    return nil
end

Core.CONTROL_SPELLS = { "banish", "fear", "enslaveDemon", "deathCoil", "howlOfTerror", "seduction" }
Core.PET_CONTROL_SPELLS = { seduction = true }

function Core.LearnSpellIds(key, name, items)
    local ranks = Core.SPELLS[key]
    if not ranks or type(name) ~= "string" or name == "" then return false end
    local added = false
    for _, item in ipairs(items or {}) do
        if item.name == name and type(item.id) == "number" then
            local known = false
            for _, id in ipairs(ranks) do if id == item.id then known = true end end
            if not known then
                ranks[#ranks + 1] = item.id
                added = true
            end
        end
    end
    return added
end

Core.SOULSTONE_USE_SPELL = 20707

Core.SOULSTONE_COOLDOWN = 1800

Core.HEALTHSTONES = { 5512, 5511, 5509, 5510, 9421, 19004, 19005, 19006, 19007, 19008, 19009, 19010, 19011, 19012, 19013 }
Core.SOULSTONES = { 5232, 16892, 16893, 16895, 16896 }

Core.FIRESTONES = { 1254, 13699, 13700, 13701 }
Core.SPELLSTONES = { 5522, 13602, 13603 }
Core.MAIN_HAND_SLOT = 16

function Core.StoneTarget(onFriend, selfOnly)
    if selfOnly then return "[@player] " end
    return onFriend and "[@target,help,nodead][@player] " or ""
end

-- one /use line per item id
function Core.UseMacro(items, onFriend, selfOnly)
    local target = Core.StoneTarget(onFriend, selfOnly)
    local lines = {}
    for i, id in ipairs(items) do lines[i] = "/use " .. target .. "item:" .. id end
    return table.concat(lines, "\n")
end

Core.MACRO_LIMIT = 255

function Core.BoundMacro(items, onFriend, firstId, createLine, limit, selfOnly)
    limit = limit or Core.MACRO_LIMIT
    local target = Core.StoneTarget(onFriend, selfOnly)
    local order, seen = {}, {}
    if firstId then order[1], seen[firstId] = firstId, true end
    for i = #items, 1, -1 do
        if not seen[items[i]] then order[#order + 1], seen[items[i]] = items[i], true end
    end
    local lines, length = {}, 0
    local function Add(line)
        local cost = #line + (#lines > 0 and 1 or 0)
        if length + cost > limit then return end
        lines[#lines + 1] = line
        length = length + cost
    end
    if createLine then Add(createLine) end
    for _, id in ipairs(order) do Add("/use " .. target .. "item:" .. id) end
    return table.concat(lines, "\n")
end

function Core.ToSet(list)
    local set = {}
    for _, value in ipairs(list) do set[value] = true end
    return set
end

function Core.HighestKnown(ranks, isKnown)
    for i = #ranks, 1, -1 do
        if isKnown(ranks[i]) then return ranks[i] end
    end
    return nil
end

-- highest known rank of last known spell, and its key
function Core.PickSpell(keys, isKnown)
    for i = #keys, 1, -1 do
        local id = Core.HighestKnown(Core.SPELLS[keys[i]] or {}, isKnown)
        if id then return id, keys[i] end
    end
    return nil, nil
end

function Core.CurseKey(spellID)
    for _, key in ipairs(Core.CURSE_KEYS) do
        for _, id in ipairs(Core.SPELLS[key]) do
            if id == spellID then return key end
        end
    end
    return nil
end

function Core.UtilityKey(spellID)
    for _, entry in ipairs(Core.UTILITY_MENU) do
        for _, key in ipairs(entry.keys) do
            for _, id in ipairs(Core.SPELLS[key] or {}) do
                if id == spellID then return Core.MenuEntryId(entry) end
            end
        end
    end
    return nil
end

function Core.IsBaneKey(key)
    for _, bane in ipairs(Core.BANE_KEYS) do
        if bane == key then return true end
    end
    return false
end

function Core.CanTradeTo(exists, isPlayer, isFriend, isSelf)
    return exists == true and isPlayer == true and isFriend == true and isSelf == false
end

function Core.DemonKey(spellID)
    for _, entry in ipairs(Core.DEMON_MENU) do
        if entry.demon then
            for _, id in ipairs(Core.SPELLS[entry.keys[1]]) do
                if id == spellID then return entry.keys[1] end
            end
        end
    end
    return nil
end

Core.DEMON_MENU = {
    { keys = { "imp" }, art = "Imp", demon = true },
    { keys = { "voidwalker" }, art = "Voidwalker", demon = true },
    { keys = { "succubus" }, art = "Succubus", demon = true },
    { keys = { "incubus" }, art = "Inccubus", demon = true },
    { keys = { "felhunter" }, art = "Felhunter", demon = true },
    { keys = { "inferno" }, art = "Infernal", demon = true },
    { keys = { "ritualOfDoom" }, art = "Doomguard", demon = true },
    { keys = { "felDomination" }, art = "Ring", gameIcon = true },
    { keys = { "healthFunnel" }, art = "Ring", gameIcon = true },
    { keys = { "senseDemons" }, art = "Ring", gameIcon = true },
    { keys = { "soulLink" }, art = "Ring", gameIcon = true },
    { keys = { "demonicSacrifice" }, art = "Ring", gameIcon = true },
    { keys = { "enslaveDemon" }, art = "Enslave" },
}
Core.UTILITY_MENU = {
    { keys = { "demonSkin", "demonArmor" }, art = "Armor" },
    { keys = { "unendingBreath" }, art = "Aqua" },
    { keys = { "detectInvisibility" }, art = "Invisible" },
    { keys = { "eyeOfKilrogg" }, art = "Kilrogg" },
    { keys = { "ritualOfSummoning" }, art = "TP" },
    { keys = { "shadowWard" }, art = "ShadowProtection" },
    { keys = { "banish" }, art = "Banish" },
    { keys = { "lifeTap" }, art = "Ring", gameIcon = true },
    { keys = { "drainSoul" }, art = "Ring", gameIcon = true },
    { keys = { "drainMana" }, art = "Ring", gameIcon = true },
    { keys = { "howlOfTerror" }, art = "Ring", gameIcon = true },
    { keys = { "fear" }, art = "Ring", gameIcon = true },
}

Core.CURSE_MENU = {
    { keys = { "amplifyCurse" }, art = "Ring", gameIcon = true },
    { keys = { "curseOfWeakness" }, art = "Weakness" },
    { keys = { "baneOfAgony" }, art = "Agony" },
    { keys = { "curseOfTongues" }, art = "Tongues" },
    { keys = { "curseOfExhaustion" }, art = "Exhaust" },
    { keys = { "curseOfElements" }, art = "Elements" },
    { keys = { "curseOfRecklessness" }, art = "Reckless" },
    { keys = { "baneOfDoom" }, art = "Doom" },
    { keys = { "baneOfHavoc" }, art = "Ring", gameIcon = true },
}

function Core.UiTexture(name)
    return Core.MEDIA_PATH .. "UI\\" .. name
end

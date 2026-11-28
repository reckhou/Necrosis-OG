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

-- say the speech line when click summon, soulstone, ritual or steed
local _, ns = ...
local Core, Text = ns.Core, ns.Text

local Speech = {}
ns.Speech = Speech

local last = {}
local queue = {}
local spokeAt = {}
local ritualClick, ritualCast
local RITUAL = "ritualOfSummoning"

local IsSecret, Plain = ns.Game.IsSecret, ns.Game.Plain

local function TargetName(kind)
    if kind == "friend" then
        if Plain(UnitExists, "target") == true and Plain(UnitCanAssist, "player", "target") == true
            and Plain(UnitIsDeadOrGhost, "target") == false and not ns.Stones.TargetIsNotPlayer() then
            return Plain(UnitName, "target")
        end
        return Plain(UnitName, "player")
    elseif kind == "target" then
        return Plain(UnitName, "target")
    end
    return nil
end

local sending, blocked = false, false
local blockedHere = {}
local toldOnce = false

local function Send(text, chatType)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if type(send) ~= "function" then return false end
    sending, blocked = true, false
    local ok = pcall(send, text, chatType)
    sending = false
    return ok and not blocked
end

local SLASH = { SAY = "/s ", YELL = "/y ", PARTY = "/p ", RAID = "/ra ", EMOTE = "/e " }

local function ToChatBox(text, chatType)
    local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
    if type(open) ~= "function" then return end
    pcall(open, (SLASH[chatType] or "") .. text)
    if not toldOnce then
        toldOnce = true
        ns.Print(Text.SPEECH_PRESS_ENTER)
    end
end

-- true when player is casting or channeling
local function IsCasting()
    for _, fn in ipairs({ UnitCastingInfo or false, UnitChannelInfo or false }) do
        if fn and Plain(fn, "player") ~= nil then return true end
    end
    return false
end

-- player is moving or fall, cast not possible
local function CannotCastNow(subject)
    local speed = Plain(GetUnitSpeed, "player")
    return Core.SpeechBlocked(subject, {
        moving = type(speed) == "number" and speed > 0,
        falling = Plain(IsFalling) == true,
        mounted = Plain(IsMounted) == true,
    })
end

local function SpellUnusable(subject)
    if not (C_Spell and C_Spell.IsSpellUsable) then return false end
    return Core.SpeechSpellUnusable(subject, function(id) return Plain(C_Spell.IsSpellUsable, id) end)
end

-- take next speech preset from shuffled list
local function NextSet(subject, sets)
    local order = queue[subject]
    if not order or #order == 0 then
        order = Core.SpeechOrder(sets, last[subject], math.random)
        queue[subject] = order
    end
    local index = table.remove(order, 1)
    if not index then return nil end
    last[subject] = index
    return sets[index]
end

local function Announce(subject, targetName)
    local settings = ns.db.speech
    if not settings.on or settings.off[subject] then
        return
    end
    local inGroup, inRaid = Plain(IsInGroup) == true, Plain(IsInRaid) == true
    local ritual = subject == RITUAL
    if ritual and not (inGroup or inRaid) then return end
    local channel = Core.SpeechChannel(ritual and "PARTY" or settings.channel, inGroup, inRaid)
    local source = ritual and RITUAL or "click"
    local now = GetTime()
    if spokeAt[subject] and now - spokeAt[subject] < Core.SpeechCooldown(subject) then
        return
    end
    local set = NextSet(subject, Core.SpeechSets(subject, settings.sets, Text))
    if not set then return end
    spokeAt[subject] = now
    local names = { player = Plain(UnitName, "player"), target = targetName,
        pet = settings.petNames[subject] }
    local fallback = { player = "", target = Text.SPEECH_NO_TARGET, pet = Text.SPEECH_NO_PET }
    local emote = set.emote ~= "" and Core.FillSpeech(set.emote, names, fallback) or nil
    local line = set.line ~= "" and Core.FillSpeech(set.line, names, fallback) or nil
    if ritual then
        local emoteSent = not emote or Send(emote, "EMOTE")
        if line and (blockedHere[source] or not Send(line, channel)) then
            blockedHere[source] = true
            ToChatBox(line, channel)
        elseif not emoteSent then
            ToChatBox(emote, "EMOTE")
        end
        return
    end
    if blockedHere[source] then
        if line then ToChatBox(line, channel) else ToChatBox(emote, "EMOTE") end
        return
    end
    local emoteSent = not emote or Send(emote, "EMOTE")
    local lineSent = not line or Send(line, channel)
    if not (emoteSent and lineSent) then
        blockedHere[source] = true
        if line and not lineSent then ToChatBox(line, channel) elseif emote then ToChatBox(emote, "EMOTE") end
    end
end

-- speak line for subject, ritual wait untill the cast really start
function Speech.Speak(subject, targetKind, targetName)
    if subject == RITUAL then
        ritualClick = { at = GetTime(), name = targetName, fallback = TargetName(targetKind) }
    elseif not (IsCasting() or CannotCastNow(subject) or SpellUnusable(subject)) then
        Announce(subject, targetName or TargetName(targetKind))
    end
end

local function IsRitual(spellID)
    return not IsSecret(spellID) and spellID == Core.SPELLS[RITUAL][1]
end

local function TakeRitualClick(target, castGUID)
    local click = ritualClick
    ritualClick = nil
    if not click or GetTime() - click.at > 1 then return nil end
    if IsSecret(target) or target == "" then target = nil end
    return { guid = not IsSecret(castGUID) and castGUID or nil, name = click.name or target or click.fallback }
end

local function RitualEvent(event, guid, spellID)
    local cast = ritualCast
    local sameCast = cast and cast.guid and not IsSecret(guid) and guid == cast.guid
    local sameSpell = IsRitual(spellID)
    if event == "UNIT_SPELLCAST_START" then
        if not (sameCast or sameSpell) then return end
        cast = cast or TakeRitualClick(nil, guid)
        if not cast then return end
        cast.started = true
        if not IsSecret(guid) and guid then cast.guid = guid end
        ritualCast = cast
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        if not (sameCast or (cast and cast.started and sameSpell)) then return end
        ritualCast = nil
        Announce(RITUAL, cast.name)
    elseif sameCast or (sameSpell and cast and not cast.guid) then
        ritualCast = nil
    end
end

function Speech.Reset()
    last, spokeAt, queue = {}, {}, {}
    ritualClick, ritualCast = nil, nil
end

local function OwnSets(subject)
    queue[subject] = nil
    local saved = ns.db.speech.sets
    if type(saved[subject]) ~= "table" then saved[subject] = Core.SpeechSets(subject, nil, Text) end
    return saved[subject]
end

-- settings page change a preset
function Speech.SetText(subject, index, field, text)
    local sets = OwnSets(subject)
    if type(sets[index]) ~= "table" then return end
    sets[index][field] = (string.gsub(tostring(text or ""), "[\r\n]+", " "))
end

function Speech.AddSet(subject)
    local sets = OwnSets(subject)
    if #sets >= Core.SPEECH_MAX then return nil end
    sets[#sets + 1] = { emote = "", line = "" }
    return #sets
end

function Speech.DeleteSet(subject, index)
    local sets = OwnSets(subject)
    if sets[index] then table.remove(sets, index) end
    last[subject] = nil
    queue[subject] = nil
end

function Speech.Restore(subject)
    ns.db.speech.sets[subject] = nil
    queue[subject] = nil
    last[subject] = nil
end

local function RememberPet()
    local key = ns.db.buttons.lastDemon
    local name = Plain(UnitName, "pet")
    if type(key) == "string" and key ~= "" and type(name) == "string" and name ~= "" then
        ns.db.speech.petNames[key] = name
    end
end

local addonName = ...
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit, ...)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if unit == addonName then
            if sending then blocked = true end
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        blockedHere = {}
        ritualClick, ritualCast = nil, nil
        return
    end
    if IsSecret(unit) or unit ~= "player" then return end
    if event == "UNIT_PET" then
        if C_Timer and C_Timer.After then C_Timer.After(0.5, RememberPet) else RememberPet() end
    elseif event == "UNIT_SPELLCAST_SENT" then
        local target, guid, spellID = ...
        if IsRitual(spellID) then
            local click = TakeRitualClick(target, guid)
            if not (ritualCast and ritualCast.started) then ritualCast = click end
        end
    else
        RitualEvent(event, ...)
    end
end)

table.insert(ns.onSphere, function()
    events:RegisterUnitEvent("UNIT_PET", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    events:RegisterEvent("ADDON_ACTION_BLOCKED")
    events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
end)

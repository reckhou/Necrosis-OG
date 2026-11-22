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

-- say the speech line when click summon, soulstone, ritual or steed
local _, ns = ...
local Core, Text = ns.Core, ns.Text

local Speech = {}
ns.Speech = Speech

local last = {}
local spokeAt = {}

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
local blockedHere = false
local toldOnce = false

local function Send(text, chatType)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if type(send) ~= "function" then return false end
    sending, blocked = true, false
    local ok = pcall(send, text, chatType)
    sending = false
    return ok and not blocked
end

local SLASH = { SAY = "/s ", YELL = "/y ", PARTY = "/p ", EMOTE = "/e " }

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

-- speak line for subject, targetKind is nil, "target" or "friend"
function Speech.Speak(subject, targetKind)
    local settings = ns.db.speech
    if not settings.on then
        return
    end
    local now = GetTime()
    if spokeAt[subject] and now - spokeAt[subject] < Core.SpeechCooldown(subject) then
        return
    end
    if IsCasting() or CannotCastNow(subject) then
        return
    end
    local set = Core.SpeechPromo(subject, Text)
    if not Core.ChoosePromo(set, math.random) then
        local sets = Core.SpeechSets(subject, settings.sets, Text)
        local index = Core.PickSpeech(sets, last[subject], math.random)
        if not index then return end
        last[subject] = index
        set = sets[index]
    end
    spokeAt[subject] = now
    local names = { player = Plain(UnitName, "player"), target = TargetName(targetKind), pet = settings.petNames[subject] }
    local fallback = { player = "", target = Text.SPEECH_NO_TARGET, pet = Text.SPEECH_NO_PET }
    local emote = set.emote ~= "" and Core.FillSpeech(set.emote, names, fallback) or nil
    local line = set.line ~= "" and Core.FillSpeech(set.line, names, fallback) or nil
    local channel = Core.SpeechChannel(settings.channel, Plain(IsInGroup) == true)
    if blockedHere then
        if line then ToChatBox(line, channel) else ToChatBox(emote, "EMOTE") end
        return
    end
    local emoteSent = not emote or Send(emote, "EMOTE")
    local lineSent = not line or Send(line, channel)
    if not (emoteSent and lineSent) then
        blockedHere = true
        if line and not lineSent then ToChatBox(line, channel) elseif emote then ToChatBox(emote, "EMOTE") end
    end
end

function Speech.Reset() last, spokeAt = {}, {} end

local function OwnSets(subject)
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
end

function Speech.Restore(subject) ns.db.speech.sets[subject] = nil end

local function RememberPet()
    local key = ns.db.buttons.lastDemon
    local name = Plain(UnitName, "pet")
    if type(key) == "string" and key ~= "" and type(name) == "string" and name ~= "" then
        ns.db.speech.petNames[key] = name
    end
end

local addonName = ...
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if unit == addonName then
            if sending then blocked = true end
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        blockedHere = false
        return
    end
    if unit ~= "player" then return end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, RememberPet) else RememberPet() end
end)

table.insert(ns.onSphere, function()
    events:RegisterUnitEvent("UNIT_PET", "player")
    events:RegisterEvent("ADDON_ACTION_BLOCKED")
    events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
end)

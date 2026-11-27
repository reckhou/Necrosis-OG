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

-- speech rules
local _, ns = ...
local Core = ns.Core

Core.SPEECH_SUBJECTS = { "imp", "voidwalker", "succubus", "incubus", "felhunter", "inferno", "ritualOfDoom",
    "soulstone", "ritualOfSummoning", "mount", "hearthstone" }
Core.SPEECH_MAX = 100

Core.SPEECH_COOLDOWN = 60
Core.SPEECH_COOLDOWNS = { ritualOfSummoning = 3, mount = 90 }

function Core.SpeechCooldown(subject)
    return Core.SPEECH_COOLDOWNS[subject] or Core.SPEECH_COOLDOWN
end

Core.SPEECH_NEEDS_STILL = { imp = true, voidwalker = true, succubus = true, incubus = true, felhunter = true,
    inferno = true, ritualOfDoom = true, ritualOfSummoning = true, hearthstone = true }

Core.SPEECH_NEEDS_SPELL = { imp = true, voidwalker = true, succubus = true, incubus = true, felhunter = true,
    inferno = true, ritualOfDoom = true, ritualOfSummoning = true }

-- true when no spell rank can cast
function Core.SpeechSpellUnusable(subject, usable)
    local ids = Core.SPEECH_NEEDS_SPELL[subject] and Core.SPELLS[subject]
    if not ids then return false end
    for _, id in ipairs(ids) do
        if usable(id) ~= false then return false end
    end
    return true
end

function Core.SpeechBlocked(subject, state)
    if not Core.SPEECH_NEEDS_STILL[subject] then return false end
    return state.moving == true or state.falling == true or state.mounted == true
end

local function TextSet(text, key)
    local emote, line = rawget(text, key .. "EMOTE"), rawget(text, key .. "LINE")
    if emote == nil and line == nil then return nil end
    return { emote = emote or "", line = line or "" }
end

function Core.SpeechSets(subject, saved, text)
    local sets = {}
    local own = type(saved) == "table" and saved[subject]
    if type(own) == "table" then
        for i = 1, math.min(#own, Core.SPEECH_MAX) do
            local set = type(own[i]) == "table" and own[i] or {}
            sets[i] = { emote = tostring(set.emote or ""), line = tostring(set.line or "") }
        end
        return sets
    end
    for i = 1, Core.SPEECH_MAX do
        local set = TextSet(text, "SPEECH_" .. string.upper(subject) .. "_" .. i .. "_")
        if not set then break end
        sets[i] = set
    end
    return sets
end

function Core.PresetName(set, limit, empty)
    local text = (set.line ~= "" and set.line) or set.emote
    if text == "" then return empty end
    if #text <= limit then return text end
    local cut = limit
    while cut > 0 and string.byte(text, cut + 1) and string.byte(text, cut + 1) >= 128 and string.byte(text, cut + 1) < 192 do
        cut = cut - 1
    end
    return string.sub(text, 1, cut) .. "..."
end

-- shuffle sets, keep last pick out of first place
function Core.SpeechOrder(sets, last, random)
    local order = {}
    for i, set in ipairs(sets) do
        if set.emote ~= "" or set.line ~= "" then order[#order + 1] = i end
    end
    for n = #order, 2, -1 do
        local pick = random(n)
        order[n], order[pick] = order[pick], order[n]
    end
    if #order > 1 and order[1] == last then order[1], order[2] = order[2], order[1] end
    return order
end

-- replace <player>, <target> and <pet> in the line
function Core.FillSpeech(text, names, fallback)
    local function Name(key)
        local value = names[key]
        if type(value) ~= "string" or value == "" then return fallback[key] end
        return value
    end
    text = string.gsub(text, "<player>", function() return Name("player") end)
    text = string.gsub(text, "<target>", function() return Name("target") end)
    text = string.gsub(text, "<pet>", function() return Name("pet") end)
    return text
end

Core.SPEECH_PROMO_CHANCE = 0.1

function Core.SpeechPromo(subject, text)
    return TextSet(text, "SPEECH_" .. string.upper(subject) .. "_PROMO_")
end

function Core.ChoosePromo(promo, random)
    return promo ~= nil and random() < Core.SPEECH_PROMO_CHANCE
end

-- party channel go raid when in raid, say when not in group
function Core.SpeechChannel(choice, inGroup, inRaid)
    if choice == "YELL" then return "YELL" end
    if choice == "PARTY" then
        if inRaid then return "RAID" end
        if inGroup then return "PARTY" end
    end
    return "SAY"
end

Core.SPEECH_OLD_DEFAULTS = {
    imp = {
        { emote = "snaps their fingers, and a puff of brimstone curls into a small, grinning shape.",
          line = "<pet>, out of the Twisting Nether and into the light. Try not to set the party on fire." },
        { emote = "drags a squealing imp out of a crack in the air by its ear.",
          line = "Stop squirming, <pet>. You serve <player> now." },
        { emote = "sighs and summons the loudest imp in the Nether.",
          line = "Yes, <pet>, I can hear you. The whole zone can hear you." },
        { emote = "rolls up their sleeves as an imp tumbles out of a green flame.",
          line = "Firebolts, <pet>. Not commentary." },
        { emote = "holds a tiny contract up to the light and squints at the fine print.",
          line = "<pet>, it says here you work for soul shards. It says nothing about complaining." },
        { emote = "summons an imp that at once demands a tea break.",
          line = "No, <pet>, the Burning Legion does not have a pension scheme." },
    },
    voidwalker = {
        { emote = "shrugs as a hulking shadow drifts out of nowhere.",
          line = "Big, blue and expendable. Hello again, <pet>." },
        { emote = "tears open a seam in the world, and the Void spills out.",
          line = "Rise, <pet>. Stand between me and harm." },
        { emote = "chains a mass of living shadow to their will.",
          line = "Pull that one off me, <pet>. And that one. And that one." },
        { emote = "mutters, \"Who needs a warrior?\"",
          line = "Our tank has arrived. Its name is <pet>, and it never complains." },
        { emote = "summons a voidwalker, which sighs louder than the warrior.",
          line = "Cheer up, <pet>. Someone has to stand in the fire, and it isn't me." },
    },
    succubus = {
        { emote = "rolls their eyes as the succubus cracks her whip at the party.",
          line = "<pet>! Not the party. The ENEMY." },
        { emote = "whispers a forbidden name from the Twisting Nether.",
          line = "Mistress <pet>, finest of the Legion. Play nicely." },
        { emote = "calls softly, and the scent of brimstone and perfume fills the air.",
          line = "Come, <pet>. Someone here needs your attention." },
        { emote = "offers a soul shard and a wicked grin.",
          line = "<pet>, lash them until they beg." },
        { emote = "snaps their fingers, and a winged shadow lands beside them.",
          line = "Don't look her in the eyes. <pet> belongs to <player>." },
    },
    incubus = {
        { emote = "rolls their eyes as the incubus winks at the healer.",
          line = "<pet>! Stop flirting with the healer." },
        { emote = "whispers a forbidden name from the Twisting Nether.",
          line = "<pet>, charmer of the Legion. Mind your manners." },
        { emote = "offers a soul shard to a grinning incubus.",
          line = "<pet>, lash them until they beg." },
        { emote = "cracks an unseen whip as a tall, horned figure steps out of the flames.",
          line = "<pet>, charm them, then make them suffer." },
        { emote = "calls softly, and a smouldering incubus bows low.",
          line = "Come, <pet>. Someone here needs your attention." },
    },
    felhunter = {
        { emote = "opens a rift, and a felhunter pours through, sniffing hungrily.",
          line = "Feast on their magic, <pet>. Leave the bones for me." },
        { emote = "summons a hound of the Legion, bred to hunt magic.",
          line = "Hunt, <pet>. Spell Lock anything that chants." },
        { emote = "whistles sharply, and a felhunter bounds out of the shadows.",
          line = "<pet>! Here, boy! Who's a good hound?" },
        { emote = "wipes felhunter drool off their robes.",
          line = "<pet>, we have talked about licking the mage." },
        { emote = "throws a mage's spellbook, and the felhunter fetches it back in pieces.",
          line = "Who ate the Polymorph? Was it you, <pet>? Yes it was!" },
    },
    inferno = {
        { emote = "screams a word of power into the sky.",
          line = "COME TO ME, CREATURE OF FIRE AND NIGHTMARE!" },
        { emote = "calls down a burning stone from the Twisting Nether.",
          line = "The Legion sends its regards!" },
        { emote = "offers an Infernal Stone to the burning sky.",
          line = "Fire of Kil'jaeden, answer <player>!" },
        { emote = "points at the ground as the sky turns green.",
          line = "Stand clear! I cannot promise it lands on the enemy." },
        { emote = "raises their arms as green fire tears through the clouds.",
          line = "Fall, Infernal! Burn this land in the name of <player>!" },
    },
    ritualOfDoom = {
        { emote = "places a Demonic Figurine in the centre of the circle.",
          line = "It is perfectly safe. Mostly. For me." },
        { emote = "chants as the ground cracks beneath the circle.",
          line = "Come, Doomguard! Feast on whoever was slowest to leave!" },
        { emote = "smiles sweetly at the other participants.",
          line = "Thank you for your sacrifice. Truly. I mean it." },
        { emote = "begins a dark ritual and eyes the party nervously.",
          line = "Hold hands, everyone. One of you will not be leaving." },
        { emote = "calls upon the lords of the Burning Legion.",
          line = "By the will of Kil'jaeden and the blood of the willing... and the unwilling!" },
    },
    soulstone = {
        { emote = "binds a fragment of <target>'s soul into a violet stone.",
          line = "<target> is soulstoned. Die whenever you like." },
        { emote = "whispers over a crystal, and <target>'s soul is captured.",
          line = "If we wipe, <target> gets up first. No pressure." },
        { emote = "binds <target>'s soul to a shard of the Nether.",
          line = "<target> may now die heroically. After the boss, please." },
        { emote = "hands <target> a soulstone with a receipt attached.",
          line = "<target>, this soul comes with a thirty-minute warranty. No refunds." },
        { emote = "tucks <target>'s soul into a stone and gives it a little shake.",
          line = "Sounds healthy. Go on, <target>, die bravely." },
    },
    ritualOfSummoning = {
        { emote = "stares at the party expectantly while <target>'s portal shimmers.",
          line = "Portal for <target> is up. Please click it before I age another year." },
        { emote = "looks at the party, then at the portal for <target>, then back at the party.",
          line = "It is a portal, not a decoration. Click it so <target> can join us." },
        { emote = "whispers to the portal, \"Bring me <target>, and hurry.\"",
          line = "Summoning <target>. If they arrive inside out, it was not my fault." },
        { emote = "draws a little arrow on the ground pointing at <target>'s portal.",
          line = "Click here. Yes, here. The big purple swirl. <target> is waiting." },
        { emote = "pokes the nearest party member towards the portal for <target>.",
          line = "You. Yes, you. Click the portal so <target> can stop walking." },
        { emote = "counts the party on their fingers while <target>'s portal hums.",
          line = "I need two clickers for <target>. Not one. Not zero. Two." },
    },
    mount = {
        { emote = "pats the neck of a horse wreathed in fel flame.",
          line = "Easy now. Don't eat the paladin's horse this time." },
        { emote = "stamps on the ground, and a burning horse rises from the shadows.",
          line = "To me, steed of the Nether!" },
        { emote = "grins as a dark horse claws its way out of the ground.",
          line = "My ride is here. It bites." },
        { emote = "whistles, and a steed of the Nether trots up looking smug.",
          line = "Yes, you are faster than the paladin's horse. Stop gloating." },
        { emote = "offers a carrot to a steed made of fel fire. The carrot is now ash.",
          line = "Never mind. It prefers souls anyway." },
    },
    hearthstone = {
        { emote = "cups a glowing stone in one hand.",
          line = "One room at the inn, please. The imp can sleep outside." },
        { emote = "brushes the brimstone off a well-worn Hearthstone.",
          line = "If anyone asks, you summoned me here after I left." },
        { emote = "holds a warm stone to one ear and listens.",
          line = "Last orders already? I'd better hurry." },
    },
}

local function SameSets(own, old)
    if type(own) ~= "table" or #own ~= #old then return false end
    for i, set in ipairs(old) do
        local mine = own[i]
        if type(mine) ~= "table" or mine.emote ~= set.emote or mine.line ~= set.line then return false end
    end
    return true
end

function Core.DropOldSpeechDefaults(sets)
    local cleared = {}
    if type(sets) ~= "table" then return cleared end
    for subject, old in pairs(Core.SPEECH_OLD_DEFAULTS) do
        if SameSets(sets[subject], old) then
            sets[subject] = nil
            cleared[#cleared + 1] = subject
        end
    end
    return cleared
end

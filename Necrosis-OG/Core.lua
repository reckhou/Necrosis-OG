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

-- core logic, no wow api so can test it outside game
local _, ns = ...
local Core = {}
ns.Core = Core

Core.DEFAULTS = {
    version = 27,
    locked = false,
    tooltips = true,
    skin = "Rose",
    font = "friz",
    textSize = 100,
    barTexture = "blizzard",
    sphere = {
        point = "CENTER", relativePoint = "CENTER", x = 0, y = -200,
        scale = 120,
        showCount = true,
        lowShards = 3,
        rotation = 180,
        spacing = 1,
        distance = 1,
        buttonSize = 1.1,
        clicks = { left = "demonSkin", middle = "unendingBreath", ctrlLeft = "eyeOfKilrogg", shiftLeft = "ritualOfSummoning" },
    },
    buttons = {
        weaponStone = "",
        sacAuras = {},
        lastDemon = "",
        lastCurse = "",
        lastBane = "",
        lastUtility = "",
        healthstone = 0,
        soulstone = 0,
        soulstoneTarget = "",
        soulstoneLength = 0,
        soulstoneAt = 0,
        shardLimit = 16,
        autoDestroy = false,
        show = { firestone = true, spellstone = true, healthstone = true, soulstone = true, utility = true,
            mount = true, demons = true, curses = true, shards = true },
        firestone = 0, spellstone = 0,
        learnedStones = { healthstone = {}, soulstone = {}, firestone = {}, spellstone = {} },
        menuDirection = { demons = "up", utility = "up", curses = "up" },
        menuOffset = { demons = { x = 0, y = 0 }, utility = { x = 0, y = 0 }, curses = { x = 0, y = 0 } },
        menuCloses = true,
        autoFocus = true,
        menuOrder = { demons = {}, utility = {}, curses = {} },
        menuOff = { demons = {}, utility = {}, curses = {} },
        ringOrder = {},
        free = false,
        places = {},
    },
    timers = {
        warnSound = true,
        sounds = { enslaveDemon = true },
        controlOn = true,
        scales = { focus = 100, multi = 100 },
        grow = { multi = "down" },
        focus = { point = "BOTTOMLEFT", relativePoint = "CENTER", x = 100, y = -235 },
        multi = { point = "BOTTOMLEFT", relativePoint = "CENTER", x = -320, y = -235 },
        focusOn = true,
        multiOn = true,
        trackOff = {},
        trackOrder = {},
        targetReminder = { on = false, scale = 120, opacity = 65, x = 159, y = -166 },
        plateReminder = { on = true, scale = 100, opacity = 50, x = 0, y = -10 },
        barHighlight = { on = true },
        focusOff = {},
        plateSettings = {},
        lastInSlot = {},
    },
    alerts = {
        antiFearOn = true,
        sounds = { antiFear = true, shadowTrance = true, decimation = true, amplifyCurse = true, unendingBreath = true,
            soulstone = true },
        shadowTranceOn = true, decimationOn = true, amplifyCurseOn = true,
        sacrificeOn = true, sacrificeAt = 30,
        lengths = {},
    },
    controlButtons = {
        armour = { on = true, safeHide = "narrow" }, healthstone = { on = true, safeHide = "narrow" },
        soulLink = { on = true, safeHide = "narrow" }, demon = { on = true, safeHide = "narrow" },
        sacrifice = { on = true, safeHide = "narrow" }, weaponStone = { on = true, safeHide = "narrow" },
        soulstone = { on = true, safeHide = "narrow" }, unendingBreath = { on = true },
    },
    reminderBar = { on = true, point = "CENTER", relativePoint = "CENTER", x = 0, y = -110, scale = 100, spacing = 0, opacity = 100 },
    procBar = { on = true, point = "CENTER", relativePoint = "CENTER", x = 0, y = 70, scale = 100, spacing = 0, opacity = 100 },
    animation = { on = true, speed = 1 },
    speech = { on = true, channel = "SAY", sets = {}, petNames = {}, off = {} },
    settingsWindow = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 100, y = -100 },
}

Core.FIRST_RUN = {
    menuOrder = {
        demons = { "healthFunnel", "imp", "voidwalker", "succubus", "incubus", "felhunter", "inferno", "ritualOfDoom",
            "soulLink", "demonicSacrifice", "enslaveDemon", "senseDemons", "felDomination" },
        utility = { "demonSkin", "unendingBreath", "detectInvisibility", "eyeOfKilrogg", "ritualOfSummoning",
            "shadowWard", "lifeTap", "drainSoul", "drainMana", "banish", "fear", "howlOfTerror" },
        curses = { "curseOfElements", "baneOfAgony", "baneOfHavoc", "curseOfRecklessness", "curseOfWeakness",
            "curseOfTongues", "curseOfExhaustion", "baneOfDoom", "amplifyCurse" },
    },
    menuOff = {
        demons = { "soulLink", "senseDemons" },
        utility = { "lifeTap", "drainSoul", "drainMana", "banish", "fear", "howlOfTerror" },
        curses = {},
    },
    trackOff = { "immolate" },
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, inner in pairs(value) do result[key] = copy(inner) end
    return result
end

Core.Copy = copy

-- "timers.focusOff.banish" -> { "timers", "focusOff", "banish" }
function Core.SplitPath(path)
    local keys = {}
    for key in string.gmatch(path, "[^%.]+") do keys[#keys + 1] = key end
    return keys
end

function Core.PathUnder(path, prefix)
    if prefix == "" or path == prefix then return true end
    return string.sub(path, 1, #prefix + 1) == prefix .. "."
end

-- fill missing or wrong type value from defaults
function Core.ApplyDefaults(saved, defaults)
    if type(saved) ~= "table" then return copy(defaults) end
    for key, default in pairs(defaults) do
        local value = saved[key]
        if type(value) ~= type(default) then
            saved[key] = copy(default)
        elseif type(default) == "table" then
            Core.ApplyDefaults(value, default)
        end
    end
    return saved
end

-- round saved field to the step
local function RoundField(table_, key, step)
    if type(table_) == "table" and Core.IsNumber(table_[key]) then table_[key] = Core.RoundToStep(table_[key], step) end
end

-- one step for each old version, take table from N to N + 1
Core.MIGRATIONS = {
    -- 25 -> 26: size sliders have new step, so round saved values
    [25] = function(saved)
        RoundField(saved.sphere, "scale", Core.SCALE_STEP)
        RoundField(saved.sphere, "buttonSize", Core.BUTTON_SIZE_STEP)
        RoundField(saved.sphere, "distance", Core.DISTANCE_STEP)
        if type(saved.timers) == "table" then
            RoundField(saved.timers.scales, "focus", Core.SCALE_STEP)
            RoundField(saved.timers.scales, "multi", Core.SCALE_STEP)
            RoundField(saved.timers.targetReminder, "scale", Core.SCALE_STEP)
            RoundField(saved.timers.plateReminder, "scale", Core.SCALE_STEP)
        end
        RoundField(saved.reminderBar, "scale", Core.SCALE_STEP)
        RoundField(saved.procBar, "scale", Core.SCALE_STEP)
    end,
    [26] = function(saved)
        if type(saved.speech) == "table" then Core.DropOldSpeechDefaults(saved.speech.sets) end
    end,
}

-- bring old saved table to the newest version, run before ApplyDefaults
function Core.Migrate(saved)
    if type(saved) ~= "table" or not Core.IsNumber(saved.version) then return saved end
    while saved.version < Core.DEFAULTS.version do
        local step = Core.MIGRATIONS[saved.version]
        if step then step(saved) end
        saved.version = saved.version + 1
    end
    return saved
end

-- settings for new charactor
function Core.NewSettings()
    local db = copy(Core.DEFAULTS)
    for menu, order in pairs(Core.FIRST_RUN.menuOrder) do db.buttons.menuOrder[menu] = copy(order) end
    for menu, keys in pairs(Core.FIRST_RUN.menuOff) do
        for _, key in ipairs(keys) do db.buttons.menuOff[menu][key] = true end
    end
    for _, key in ipairs(Core.FIRST_RUN.trackOff) do db.timers.trackOff[key] = true end
    db.welcomed = false
    return db
end

function Core.IsNewSettings(saved)
    return type(saved) ~= "table" or next(saved) == nil
end

Core.MEDIA_PATH = "Interface\\AddOns\\Necrosis-OG\\Media\\"

Core.SKIN_LIST = { "Rose", "Bleu", "Orange", "Turquoise", "Violet1", "Violet2", "666", "X" }
Core.SKINS = {}
for _, skin in ipairs(Core.SKIN_LIST) do Core.SKINS[skin] = true end
Core.DEFAULT_SKIN = "Rose"
Core.SHARD_TEXTURE_MAX = 32

function Core.SkinOrDefault(skin)
    if Core.SKINS[skin] then return skin end
    return Core.DEFAULT_SKIN
end

Core.FONT_LIST = {
    { key = "friz", file = "Fonts\\FRIZQT__.TTF", text = "SET_FONT_FRIZ" },
    { key = "arialNarrow", file = "Fonts\\ARIALN.TTF", text = "SET_FONT_ARIAL_NARROW" },
    { key = "morpheus", file = "Fonts\\MORPHEUS.ttf", text = "SET_FONT_MORPHEUS" },
    { key = "skurri", file = "Fonts\\skurri.ttf", text = "SET_FONT_SKURRI" },
    { key = "nimrod", file = "Fonts\\NIM_____.ttf", text = "SET_FONT_NIMROD" },
    { key = "mok", file = "Fonts\\K_Pagetext.TTF", text = "SET_FONT_MOK" },
    { key = "f2002", file = "Fonts\\2002.ttf", text = "SET_FONT_2002" },
    { key = "f2002Bold", file = "Fonts\\2002B.ttf", text = "SET_FONT_2002_BOLD" },
    { key = "arHei", file = "Fonts\\ARHei.ttf", text = "SET_FONT_AR_HEI" },
    { key = "arKai", file = "Fonts\\ARKai_T.ttf", text = "SET_FONT_AR_KAI" },
    { key = "arKaiCombat", file = "Fonts\\ARKai_C.ttf", text = "SET_FONT_AR_KAI_COMBAT" },
}

Core.BAR_TEXTURE_LIST = {
    { key = "blizzard", file = "Interface\\TargetingFrame\\UI-StatusBar", text = "SET_BAR_BLIZZARD" },
    { key = "skills", file = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar", text = "SET_BAR_SKILLS" },
    { key = "raid", file = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill", text = "SET_BAR_RAID" },
    { key = "target", file = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill", text = "SET_BAR_TARGET" },
    { key = "professions", file = "Interface\\Spellbook\\Professions-Progress-Fill", text = "SET_BAR_PROFESSIONS" },
    { key = "archaeology", file = "Interface\\Archeology\\Arch-Progress-Fill", text = "SET_BAR_ARCHAEOLOGY" },
    { key = "solid", file = "Interface\\Buttons\\WHITE8X8", solid = true, text = "SET_BAR_SOLID" },
}

Core.LSM_PREFIX = "lsm:"
Core.TEXT_SIZES = { 80, 90, 100, 115, 130 }

function Core.MediaEntry(list, key)
    for _, entry in ipairs(list) do
        if entry.key == key then return entry end
    end
end

function Core.LsmName(key)
    if type(key) ~= "string" or string.sub(key, 1, #Core.LSM_PREFIX) ~= Core.LSM_PREFIX then return nil end
    local name = string.sub(key, #Core.LSM_PREFIX + 1)
    return name ~= "" and name or nil
end

-- normalize path for compare: lower case, one slash type, no extension
function Core.SamePath(path)
    if type(path) ~= "string" then return nil end
    path = string.gsub(string.lower(path), "/", "\\")
    path = string.gsub(path, "\\+", "\\")
    return (string.gsub(path, "%.[%a%d]+$", ""))
end

function Core.MediaChoices(list, lsm, label, works)
    local choices, seen = {}, {}
    for _, entry in ipairs(list) do
        if not works or works(entry) then
            choices[#choices + 1] = { entry.key, label(entry) }
            seen[Core.SamePath(entry.file)] = true
        end
    end
    if type(lsm) ~= "table" then return choices end
    local names = {}
    for name, file in pairs(lsm) do
        if type(name) == "string" and type(file) == "string" then names[#names + 1] = name end
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    for _, name in ipairs(names) do
        local path = Core.SamePath(lsm[name])
        if not seen[path] then
            seen[path] = true
            choices[#choices + 1] = { Core.LSM_PREFIX .. name, name }
        end
    end
    return choices
end

function Core.TextSizeOrDefault(value)
    for _, size in ipairs(Core.TEXT_SIZES) do
        if size == value then return value end
    end
    return Core.DEFAULTS.textSize
end

function Core.ScaledFontSize(size, percent)
    return math.max(6, math.floor(size * Core.TextSizeOrDefault(percent) / 100 + 0.5))
end

-- sphere texture for shard count
function Core.ShardTexture(skin, count)
    local index = 0
    if type(count) == "number" and count == count then
        index = math.max(0, math.min(Core.SHARD_TEXTURE_MAX, math.floor(count)))
    end
    return Core.MEDIA_PATH .. "Skins\\" .. Core.SkinOrDefault(skin) .. "\\Shard" .. index
end

Core.SOUL_SHARD_ITEM = 6265
Core.HEARTHSTONE_ITEM = 6948
Core.SPHERE_SIZE = 58
Core.SCALE_MIN, Core.SCALE_MAX, Core.SCALE_STEP = 50, 200, 10
Core.SHARD_COUNT_MAX = 32

local function isNumber(value) return type(value) == "number" and value == value end
Core.IsNumber = isNumber

function Core.ClampScale(scale, fallback)
    if not isNumber(scale) then return fallback or 100 end
    return Core.RoundToStep(math.max(Core.SCALE_MIN, math.min(Core.SCALE_MAX, scale)), Core.SCALE_STEP)
end

function Core.ClampSphereScale(scale) return Core.ClampScale(scale, Core.DEFAULTS.sphere.scale) end

function Core.ClampThreshold(threshold)
    if not isNumber(threshold) then return Core.DEFAULTS.sphere.lowShards end
    return math.max(0, math.min(Core.SHARD_COUNT_MAX, math.floor(threshold)))
end

-- count text like "07" and if it is red
function Core.ShardCountText(count, threshold, limit)
    if not isNumber(count) then count = 0 end
    count = math.max(0, math.floor(count))
    local text = (count < 10) and ("0" .. count) or tostring(count)
    local red = count < Core.ClampThreshold(threshold)
    if limit ~= nil then
        limit = Core.ClampShardLimit(limit)
        text = text .. "/" .. ((limit < 10) and ("0" .. limit) or tostring(limit))
        red = red or count > limit
    end
    return text, red
end

Core.ALERT_KEYS = { "shadowTrance", "decimation", "amplifyCurse", "antiFear" }

Core.BREATH_TIMER = "BREATH"

Core.BREATH_SOUND_GAP = 30
Core.MIRROR_TIMER_SLOTS = 3

Core.SAFE_LEVELS = { "off", "narrow", "wide" }

Core.SAFE_AREA_GRACE = 30

function Core.SafeLevelOrDefault(value)
    for _, level in ipairs(Core.SAFE_LEVELS) do
        if level == value then return value end
    end
    return "narrow"
end

-- if reminder should hide in safe area now
function Core.SafeAreaHides(level, state)
    if level ~= "narrow" and level ~= "wide" then return false end
    if type(state) ~= "table" or state.inCombat or state.instance then return false end
    if Core.SafeAreaGraceLeft(state.secondsSinceCombat) > 0 then return false end
    if state.resting == true or state.zoneType == "sanctuary" then return true end
    return level == "wide" and state.zoneType == "friendly"
end

function Core.TravelHides(key, state)
    local def = Core.CONTROL_BUTTONS[key]
    if (def and def.alwaysShow) or type(state) ~= "table" then return false end
    return state.mounted == true or state.flying == true or state.onTaxi == true
end

function Core.SafeAreaGraceLeft(secondsSinceCombat)
    if type(secondsSinceCombat) ~= "number" then return 0 end
    return math.max(0, Core.SAFE_AREA_GRACE - secondsSinceCombat)
end

Core.SHADOW_TRANCE_ID = 17941

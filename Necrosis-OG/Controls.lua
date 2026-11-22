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

-- reminders, armor, healthstone, soul link, demon, stones, soulstone and breath
local _, ns = ...
local Core, Text = ns.Core, ns.Text
local Buttons = ns.Buttons
local Bars = ns.Bars

local Controls = {}
ns.Controls = Controls

local NAMES = { armour = "NecrosisOGArmourButton", healthstone = "NecrosisOGHealthstoneAlertButton",
    soulLink = "NecrosisOGSoulLinkAlertButton", demon = "NecrosisOGDemonAlertButton",
    sacrifice = "NecrosisOGSacrificeAlertButton", weaponStone = "NecrosisOGWeaponStoneAlertButton",
    soulstone = "NecrosisOGSoulstoneAlertButton", unendingBreath = "NecrosisOGBreathAlertButton" }

local TITLES = { healthstone = "TIP_ALERT_HEALTHSTONE_TITLE", soulstone = "TIP_ALERT_SOULSTONE_TITLE",
    demon = "TIP_DEMONS_TITLE" }
local TIPS = { armour = "TIP_ALERT_NOT_ON", healthstone = "TIP_ALERT_HEALTHSTONE", soulLink = "TIP_ALERT_NOT_ON",
    demon = "TIP_ALERT_DEMON", sacrifice = "TIP_ALERT_NOT_ON", weaponStone = "TIP_ALERT_WEAPON_STONE",
    soulstone = "TIP_ALERT_SOULSTONE", unendingBreath = "TIP_ALERT_BREATH" }
local CLICKS = { armour = "ACT_CAST", healthstone = "ACT_CREATE", soulLink = "ACT_CAST",
    sacrifice = "ACT_CAST", soulstone = "ACT_USE_FRIEND", unendingBreath = "ACT_CAST_SELF" }
local Tips = ns.Tips
local SOUND = 8959
local buttons = {}
local bar

local function Saved(key) return ns.db.controlButtons[key] end

local IsSecret, Plain, SpellName, InCombat = ns.Game.IsSecret, ns.Game.Plain, ns.Game.SpellName, ns.Game.InCombat

local function Tooltip(tooltip, key, button)
    local def = Core.CONTROL_BUTTONS[key]
    local title = (TITLES[key] and Text[TITLES[key]]) or (def.label and Text[def.label]) or SpellName(button.spellID)
        or SpellName(Core.SPELLS[def.spells[#def.spells]][1]) or ""
    Tips.Title(tooltip, title)
    Tips.Line(tooltip, Text[TIPS[key]])
    if key == "demon" then
        Tips.Click(tooltip, "left", Text.ACT_CHOOSE_DEMON)
        if button.spellID then
            Tips.Click(tooltip, "right", SpellName(button.spellID) or "?")
            local domination = Core.HighestKnown(Core.SPELLS.felDomination, Buttons.IsKnown)
            if domination then
                Tips.Note(tooltip, string.format(Text.TIP_DOMINATION_IN_COMBAT, SpellName(domination) or "?"))
            end
        end
    elseif key == "weaponStone" then
        Tips.Click(tooltip, "any", button.useKind and Text.ACT_PUT_ON or Text.ACT_CREATE)
    elseif key == "soulstone" then
        Tips.Click(tooltip, "any", button.useKind and Text.ACT_USE_FRIEND or Text.ACT_CREATE)
    else
        Tips.Click(tooltip, "any", Text[CLICKS[key]])
    end
end

local function DemonPicture(item, art)
    item.face.icon:SetTexture(Core.UiTexture(art .. "-01"))
    Bars.SetRing(item, art)
end

local function Create(key, header)
    local def = Core.CONTROL_BUTTONS[key]
    local button = Buttons.NewSecureButton(NAMES[key], bar.frame, Core.BUTTON_SIZE)
    button.key = key
    button:SetFrameStrata("MEDIUM")
    local item = Bars.AddItem(bar, key, button)
    button.item = item
    if def.gameIcon then
        Buttons.DressRing(item.face, Core.MENU_ICON_INSET * Core.BUTTON_SIZE / Core.MENU_ITEM_SIZE, def.art)
    else
        item.face.icon:SetTexture(Core.UiTexture(def.art .. def.picture))
    end
    Bars.SetRing(item, def.gameIcon and def.spells[1] or def.art)
    button.tooltip = function(tooltip) Tooltip(tooltip, key, button) end
    if def.missing == "soulstoneReady" then
        button.onPreClick = function(self, mouse)
            if (mouse == "LeftButton" or mouse == "RightButton") and self.useKind and not InCombat() then
                local macro = ns.Stones.UseMacro("soulstone")
                self:SetAttribute("macrotext1", macro)
                self:SetAttribute("macrotext2", macro)
            end
        end
        button.speechSubject = function(mouse)
            if (mouse == "LeftButton" or mouse == "RightButton") and button.useKind then return "soulstone", "friend" end
        end
    elseif def.missing == "enchant" then
        button.onPreClick = function(self) if self.useKind then ns.Stones.NoteApplied(self.useKind) end end
    elseif def.missing == "demon" then
        ns.Menus.AttachDemonPicker(button, header)
        button:HookScript("OnAttributeChanged", function(_, name, value)
            if name == "againart" and type(value) == "string" then
                DemonPicture(item, value)
                button.demonKey = Core.DemonKeyOfArt(value) or button.demonKey
            end
        end)
        button.speechSubject = function(mouse)
            if mouse == "RightButton" and button.spellID then return button.demonKey, nil end
        end
    end
    buttons[key] = button
end

local inCombat = false
local castInFight = {}

local auraIdsCache = {}

local function AuraIds(def)
    if auraIdsCache[def] then return auraIdsCache[def] end
    local ids = {}
    if def.auras then
        for _, id in ipairs(def.auras) do ids[#ids + 1] = id end
    else
        for _, spell in ipairs(def.spells) do
            for _, id in ipairs(Core.SPELLS[spell]) do ids[#ids + 1] = id end
        end
    end
    local learned = def.learned and ns.db.buttons[def.learned]
    if type(learned) == "table" then
        for id in pairs(learned) do ids[#ids + 1] = id end
    end
    auraIdsCache[def] = ids
    return ids
end

-- true, false or nil when it hidden
local function BuffOn(def)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    for _, id in ipairs(AuraIds(def)) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if not ok or IsSecret(aura) then return nil end
        if type(aura) == "table" then return true end
    end
    return false
end

local function SacrificeOn() return BuffOn(Core.CONTROL_BUTTONS.sacrifice) end
local function PactLearned() return Buttons.IsKnown(Core.SPELLS.demonicPact[1]) end

-- living demon is out, nil when hidden
local function PetOut()
    local pet = Plain(UnitExists, "pet")
    if pet ~= true then return pet end
    local dead = Plain(UnitIsDead, "pet")
    if dead == nil then return nil end
    return not dead
end

local petWasOut

-- if no demon reminder show
local function DemonMissing()
    local pet = PetOut()
    if buttons.demon then buttons.demon.state = { petOut = pet } end
    if pet == nil then return nil end
    if pet then return false end
    local pact = PactLearned()
    local sacrificed = SacrificeOn()
    if sacrificed == nil and not pact then return nil end
    local state = { petOut = false, dead = Plain(UnitIsDeadOrGhost, "player") == true,
        mounted = Plain(IsMounted) == true, onTaxi = Plain(UnitOnTaxi, "player") == true,
        sacrificed = sacrificed == true, pact = pact }
    if buttons.demon then buttons.demon.state = state end
    return Core.NoDemonAlert(state)
end

local UpdateShown

local soulstoneCheckFor

local function CheckSoulstoneAt(left)
    local due = GetTime() + left
    if soulstoneCheckFor and math.abs(soulstoneCheckFor - due) < 2 then return end
    soulstoneCheckFor = due
    C_Timer.After(left + 1, function() UpdateShown() end)
end

-- true when soulstone cooldown over, nil if hidden
local function SoulstoneLeft()
    local start, duration, hidden = ns.Stones.Cooldown("soulstone")
    if hidden then return nil end
    return start ~= nil and Core.CooldownLeft(start, duration, GetTime()) or 0
end

local function SoulstoneReady()
    if Plain(UnitIsDeadOrGhost, "player") == true then return false end
    local soul = C_UnitAuras and Plain(C_UnitAuras.GetPlayerAuraBySpellID, Core.SOULSTONE_USE_SPELL)
    if type(soul) == "table" then return false end
    local left = SoulstoneLeft()
    if left == nil then return nil end
    if left > 0 then
        CheckSoulstoneAt(left)
        return false
    end
    return true
end

local SOULSTONE_SOUND = Core.MEDIA_PATH .. "Sounds\\SoulstoneEnd-En.mp3"
local soulstoneCooling = false

-- play sound and message when switch on
local function SoulstoneReadySound()
    if ns.db.alerts.sounds.soulstone == false then return end
    if type(PlaySoundFile) == "function" then pcall(PlaySoundFile, SOULSTONE_SOUND, "Master") end
    ns.Banner(Text.SOULSTONE_READY, 1.0, 0.82, 0.0)
end

Controls.SoulstoneReadySound = SoulstoneReadySound

local function WatchSoulstone()
    local left = SoulstoneLeft()
    if left == nil then return end
    if left > 0 then
        soulstoneCooling = true
        CheckSoulstoneAt(left)
        return
    end
    if not soulstoneCooling then return end
    soulstoneCooling = false
    SoulstoneReadySound()
end

Controls.WatchSoulstone = WatchSoulstone

local BREATH_CHECK = 0.5

local breath = { on = false, scale = nil, paused = false, progress = nil, still = false }
local breathTicker
local breathSounded = false

local function HasBreathBuff()
    if InCombat() or type(C_UnitAuras) ~= "table" then return false end
    for _, id in ipairs(Core.SPELLS.unendingBreath) do
        if Plain(C_UnitAuras.GetPlayerAuraBySpellID, id) ~= nil then return true end
    end
    return false
end

local function BreathFalling()
    return breath.on and not breath.paused and not breath.still
        and (type(breath.scale) ~= "number" or breath.scale < 0) and not HasBreathBuff()
end

local ReadBreathBar

-- show breath reminder when breath bar falling
local function UpdateBreath()
    if breath.on and not breathTicker and C_Timer and C_Timer.NewTicker then
        breathTicker = C_Timer.NewTicker(BREATH_CHECK, ReadBreathBar)
    elseif not breath.on and breathTicker then
        breathTicker:Cancel()
        breathTicker = nil
    end
    UpdateShown()
end

function ReadBreathBar()
    local progress = Plain(GetMirrorTimerProgress, Core.BREATH_TIMER)
    if type(progress) ~= "number" then
        breath.progress, breath.still = nil, false
    else
        breath.still = type(breath.progress) == "number" and progress >= breath.progress
        breath.progress = progress
    end
    UpdateBreath()
end

local function ResetBreathReads() breath.progress, breath.still = nil, false end

local function IsPaused(paused)
    if IsSecret(paused) then return false end
    return paused == true or (type(paused) == "number" and paused ~= 0)
end

local function OnMirrorTimer(event, name, ...)
    if IsSecret(name) or name ~= Core.BREATH_TIMER then return end
    if event == "MIRROR_TIMER_START" then
        local _, _, scale, paused = ...
        breath.on, breath.paused = true, IsPaused(paused)
        breath.scale = (not IsSecret(scale) and type(scale) == "number") and scale or nil
    elseif event == "MIRROR_TIMER_PAUSE" then
        breath.paused = IsPaused((...))
    else
        breath.on = false
    end
    ResetBreathReads()
    UpdateBreath()
end

-- check breath bar after reload
local function CheckBreathNow()
    if type(GetMirrorTimerInfo) ~= "function" then return end
    for index = 1, Core.MIRROR_TIMER_SLOTS do
        local ok, name, value, maxValue, scale, paused = pcall(GetMirrorTimerInfo, index)
        if ok and not IsSecret(name) and name == Core.BREATH_TIMER then
            OnMirrorTimer("MIRROR_TIMER_START", name, value, maxValue, scale, paused)
        end
    end
end

local breathSoundAt

local function BreathSound()
    if ns.db.alerts.sounds.unendingBreath == false or ns.Silent() or type(PlaySound) ~= "function" then return end
    local now = GetTime()
    if breathSoundAt and now - breathSoundAt < Core.BREATH_SOUND_GAP then return end
    breathSoundAt = now
    pcall(PlaySound, type(SOUNDKIT) == "table" and SOUNDKIT.RAID_WARNING or SOUND)
end

-- if the thing icon warns is missing, nil when hidden
local function Missing(key)
    local def = Core.CONTROL_BUTTONS[key]
    if def.missing == "soulstoneReady" then
        return SoulstoneReady()
    elseif def.missing == "stone" then
        local held = ns.Stones.State()
        return held[def.stone] == nil
    elseif def.missing == "enchant" then
        if not ns.Stones.HasMainHandWeapon() then return false end
        return not ns.Stones.MainHandEnchanted()
    elseif def.missing == "demon" then
        return DemonMissing()
    end
    if Plain(UnitIsDeadOrGhost, "player") == true then return false end
    if def.missing == "breath" then return BreathFalling() == true end
    if def.needsPet then
        local pet = PetOut()
        if pet == nil then return nil end
        if not pet then return false end
    end
    local on = BuffOn(def)
    if on == nil then return nil end
    return not on
end

local lastCombatEnd
local graceCheckFor

local function SafeState(combat)
    return { resting = Plain(IsResting) == true,
        zoneType = (C_PvP and C_PvP.GetZonePVPInfo) and Plain(C_PvP.GetZonePVPInfo) or nil,
        instance = Plain(IsInInstance) ~= false,
        inCombat = combat,
        secondsSinceCombat = lastCombatEnd and (GetTime() - lastCombatEnd) or nil }
end

-- set check at end of grace period
local function CheckGraceEnd(state)
    local left = Core.SafeAreaGraceLeft(state.secondsSinceCombat)
    if left <= 0 then return end
    local due = GetTime() + left
    if graceCheckFor and math.abs(graceCheckFor - due) < 2 then return end
    graceCheckFor = due
    C_Timer.After(left + 0.5, function() UpdateShown() end)
end

local RECHECK_TRIES = 5

local recheckLeft, recheckDue = RECHECK_TRIES, false

local function Recheck()
    if recheckDue or recheckLeft <= 0 then return end
    recheckLeft = recheckLeft - 1
    recheckDue = true
    C_Timer.After(1, function()
        recheckDue = false
        UpdateShown()
    end)
end

local SHOWN_IN_COMBAT = { demon = true, unendingBreath = true }

local TRAVEL = {}
local demoStep = 0
local READY = {}

-- update which icons show
function UpdateShown()
    if not bar then return end
    WatchSoulstone()
    local combat = inCombat or InCombat()
    petWasOut = PetOut()
    local hidden = false
    local wanted = {}
    local safe = not combat and SafeState(false) or nil
    if safe then CheckGraceEnd(safe) end
    local travel
    if not (ns.placing == true or Buttons.DemoMode()) then
        travel = TRAVEL
        travel.mounted, travel.flying = Plain(IsMounted) == true, Plain(IsFlying) == true
        travel.onTaxi = Plain(UnitOnTaxi, "player") == true
    end
    local demoOn
    if Buttons.DemoMode() and not ns.placing then
        for i = #READY, 1, -1 do READY[i] = nil end
        for _, key in ipairs(Core.CONTROL_BUTTON_KEYS) do
            if buttons[key].ready == true then READY[#READY + 1] = key end
        end
        demoOn = Core.DemoRemindersOn(demoStep, READY, Core.DEMO.reminderSizes)
    end
    for _, key in ipairs(Core.CONTROL_BUTTON_KEYS) do
        local button = buttons[key]
        local want
        if button.ready ~= true then
            want = false
            button.why = "not ready (switched off or not learned)"
        elseif demoOn then
            want = demoOn[key] == true
            button.why = "demo"
        elseif ns.placing == true then
            want = true
            button.why = "unlocked"
        elseif Core.TravelHides(key, travel) then
            want = false
            button.why = "mounted or flying"
        elseif safe and Core.SafeAreaHides(Saved(key).safeHide, safe) then
            want = false
            button.why = "safe area"
        else
            local missing = Missing(key)
            button.why = missing == nil and "hidden by the game" or (missing and "missing" or "not missing")
            if combat and SHOWN_IN_COMBAT[key] then
                want = missing ~= false
            elseif combat and key == "soulLink" and button:GetAttribute("forced") == true then
                want = missing ~= false and not castInFight[key]
            elseif combat then
                want = button.showing ~= false and missing ~= false and not castInFight[key]
            elseif missing == nil then
                want = button.showing ~= false
                hidden = true
            else
                want = missing
            end
        end
        wanted[key] = want
        if not combat then
            button.showing = want
            button.item.wanted = want
        end
        button.faded = not want
        button:SetAlpha(want and 1 or 0)
    end
    if not combat then Bars.Layout(bar) end
    for _, key in ipairs(Core.CONTROL_BUTTON_KEYS) do
        Bars.SetFaded(buttons[key].item, combat and not wanted[key])
    end
    local breathSeen = wanted.unendingBreath and buttons.unendingBreath:IsShown() and not ns.placing and not Buttons.DemoMode()
    if breathSeen and not breathSounded then BreathSound() end
    breathSounded = breathSeen and true or false
    if hidden then Recheck() end
end

local armedHeld = {}

-- spell to cast, first learned one
local function ChooseSpell(def)
    if def.missing == "enchant" then
        local kind = ns.Stones.WeaponKind(Buttons.IsKnown)
        if not kind then return nil, nil, nil end
        local create = ns.Stones.Definition(kind).create
        return Core.HighestKnown(Core.SPELLS[create], Buttons.IsKnown), create, kind
    elseif def.missing ~= "demon" then
        return Core.PickSpell(def.spells, Buttons.IsKnown)
    end
    local known = {}
    for _, key in ipairs(def.spells) do known[key] = Core.HighestKnown(Core.SPELLS[key], Buttons.IsKnown) ~= nil end
    local key = Core.DemonToSummon(known, ns.db.buttons.lastDemon, "", false)
    if not key then return nil, nil end
    return Core.HighestKnown(Core.SPELLS[key], Buttons.IsKnown), key
end

-- what click do, cast spell or use stone
local function ActionsFor(button, def, id, spell, kind)
    button.useKind = nil
    if def.missing == "soulstoneReady" then
        armedHeld.soulstone = ns.Stones.State().soulstone ~= nil
        if armedHeld.soulstone then
            button.useKind = "soulstone"
            return { type1 = "macro", macrotext1 = ns.Stones.UseMacro("soulstone"), spell1 = false, type2 = false,
                macrotext2 = false }
        end
        local actions = Buttons.CastActions(spell, id)
        actions.type2, actions.macrotext2 = false, false
        return actions
    end
    if def.missing == "demon" then
        local domination = Core.HighestKnown(Core.SPELLS.felDomination, Buttons.IsKnown)
        local dominationName = domination and SpellName(domination)
        local demonName = id and SpellName(id)
        return Buttons.SummonActions(button, { type1 = false, spell1 = false, macrotext1 = false },
            Core.DemonAgainMacro(dominationName, demonName), Core.DemonAgainMacro(dominationName, demonName, true))
    end
    if def.missing == "enchant" then
        local held = ns.Stones.State()
        armedHeld.firestone, armedHeld.spellstone = held.firestone ~= nil, held.spellstone ~= nil
        local use = kind and (held[kind] and kind or (held[kind == "firestone" and "spellstone" or "firestone"]
            and (kind == "firestone" and "spellstone" or "firestone")))
        if use then
            button.useKind = use
            return { type1 = "macro", macrotext1 = ns.Stones.Definition(use).useMacro, spell1 = false }
        end
    end
    local actions = Buttons.CastActions(spell, id)
    actions.type2, actions.macrotext2 = false, false
    if def.missing == "breath" then
        actions.unit1 = id and "player" or false
    end
    return actions
end

-- right click same as left click
local function MirrorRight(actions)
    for _, name in ipairs({ "type", "spell", "macrotext", "unit" }) do
        local left = actions[name .. "1"]
        if left == nil then left = false end
        actions[name .. "2"] = left
    end
    return actions
end

local function Refresh()
    if not bar then return end
    for _, key in ipairs(Core.CONTROL_BUTTON_KEYS) do
        local def = Core.CONTROL_BUTTONS[key]
        local button, saved = buttons[key], Saved(key)
        local item = button.item
        local id, spell, kind = ChooseSpell(def)
        button.spellID = id
        if def.missing == "demon" then button.demonKey = spell end
        local actions = ActionsFor(button, def, id, spell, kind)
        if def.missing ~= "demon" then MirrorRight(actions) end
        Buttons.SetActions(button, actions)
        if def.gameIcon then
            item.face.icon:SetTexture(Plain(C_Spell.GetSpellTexture, id or Core.SPELLS[def.spells[1]][1]))
        elseif def.missing == "demon" then
            DemonPicture(item, (spell and Core.DemonArt(spell)) or def.art)
        elseif def.missing == "enchant" then
            local art = ns.Stones.Definition(kind or "firestone").art
            item.face.icon:SetTexture(Core.UiTexture(art .. def.picture))
            Bars.SetRing(item, art)
        end
        item.face.icon:SetDesaturated(id == nil and not ns.demo)
        local required = not def.requires or Core.HighestKnown(Core.SPELLS[def.requires], Buttons.IsKnown) ~= nil
        button.ready = saved.on ~= false and ((id ~= nil and required) or ns.placing == true or Buttons.DemoMode())
        item.ready = button.ready
    end
    Bars.Apply(bar)
    UpdateShown()
end

local function KeyOfSpell(spellID)
    if IsSecret(spellID) or type(spellID) ~= "number" then return nil end
    for _, key in ipairs(Core.CONTROL_BUTTON_KEYS) do
        for _, spell in ipairs(Core.CONTROL_BUTTONS[key].spells) do
            for _, id in ipairs(Core.SPELLS[spell]) do
                if id == spellID then return key end
            end
        end
    end
    return nil
end

local function LearnSacrifice()
    if InCombat() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    local known = Core.ToSet(AuraIds(Core.CONTROL_BUTTONS.sacrifice))
    for _, ids in pairs(Core.SPELLS) do
        for _, id in ipairs(ids) do known[id] = true end
    end
    for _, id in ipairs(Core.SOULLINK_AURAS) do known[id] = true end
    known[Core.SOULSTONE_USE_SPELL] = true
    local now = GetTime()
    pcall(function()
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then return end
            local id, duration, expires = aura.spellId, aura.duration, aura.expirationTime
            if not (IsSecret(id) or IsSecret(duration) or IsSecret(expires)) and type(id) == "number"
                and type(duration) == "number" and type(expires) == "number" and duration >= 1800
                and math.abs(expires - duration - now) < 5 and not known[id] then
                ns.db.buttons.sacAuras[id] = true
                auraIdsCache = {}
            end
        end
    end)
end

local SACRIFICE_SPELLS = Core.ToSet(Core.SPELLS.demonicSacrifice)

Buttons.OnCreate(function(_, header)
    bar = Bars.New({ name = "NecrosisOGReminderBar", saved = "reminderBar", label = "BAR_REMINDERS", secure = true })
    for _, key in ipairs(Core.CONTROL_BUTTON_KEYS) do Create(key, header) end
    Bars.AddDriver(bar, "demon")
    Bars.AddDriver(bar, "breath")
    Bars.AddDriver(bar, "soulLink")
    bar.frame:HookScript("OnAttributeChanged", function(_, name)
        if name == "serial" and (inCombat or InCombat()) then UpdateShown() end
    end)
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    events:RegisterUnitEvent("UNIT_AURA", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    events:RegisterUnitEvent("UNIT_PET", "player")
    events:RegisterUnitEvent("UNIT_HEALTH", "pet")
    for _, event in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_MOUNT_DISPLAY_CHANGED",
        "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED",
        "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, _, _, spellID)
        if event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
            lastCombatEnd = GetTime()
            castInFight = {}
            recheckLeft = RECHECK_TRIES
        elseif event == "UNIT_HEALTH" then
            if PetOut() == petWasOut then return end
        elseif event == "UNIT_PET" then
            if (inCombat or InCombat()) and PetOut() ~= false then castInFight.soulLink = nil end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if not IsSecret(spellID) and SACRIFICE_SPELLS[spellID] then C_Timer.After(0.5, LearnSacrifice) end
            local key = KeyOfSpell(spellID)
            if not key then return end
            if inCombat or InCombat() then castInFight[key] = true end
        end
        UpdateShown()
    end)
    local water = CreateFrame("Frame")
    for _, event in ipairs({ "MIRROR_TIMER_START", "MIRROR_TIMER_STOP", "MIRROR_TIMER_PAUSE" }) do water:RegisterEvent(event) end
    water:SetScript("OnEvent", function(_, event, ...) OnMirrorTimer(event, ...) end)
    CheckBreathNow()
    for _, delay in ipairs({ 2, 5 }) do C_Timer.After(delay, function() UpdateShown() end) end
    table.insert(ns.Stones.changed, function()
        local held = ns.Stones.State()
        for _, kind in ipairs({ "firestone", "spellstone", "soulstone" }) do
            if armedHeld[kind] ~= (held[kind] ~= nil) then Buttons.Refresh() break end
        end
        UpdateShown()
    end)
    table.insert(ns.onPlacing, function() Buttons.Refresh() end)
end)

Buttons.OnRefresh(Refresh)

-- demo move the window of reminder one place every few second
table.insert(ns.onDemoData, function(on)
    if not on then return end
    local step = 0
    ns.DemoEvery(Core.DEMO.reminderStep, function()
        demoStep = step
        step = step + 1
        UpdateShown()
    end)
end)

table.insert(ns.onDemo, function(on)
    if not on then demoStep = 0 end
end)

Controls.Button = function(key) return buttons[key] end
Controls.Bar = function() return bar end
Controls.Breath = function() return breath end

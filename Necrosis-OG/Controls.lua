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

local function StoneShiftDown()
    return IsShiftKeyDown() and not IsControlKeyDown() and not Plain(IsAltKeyDown)
end

local function WeaponStonePicture(button)
    local kind = (StoneShiftDown() and button.shiftKind) or button.stoneKind or "firestone"
    if kind == button.shownStoneKind then return end
    button.shownStoneKind = kind
    local def = ns.Stones.Definition(kind)
    local held = ns.Stones.State()[kind]
    local icon = held and C_Item and Plain(C_Item.GetItemIconByID, held.id)
    if not icon then
        local id = Core.PickSpell({ def.create }, Buttons.IsKnown) or Core.SPELLS[def.create][1]
        icon = Plain(C_Spell.GetSpellTexture, id)
    end
    button.item.face.icon:SetTexture(icon or Core.UiTexture(def.art .. "-02"))
    button.item.face.icon:SetTexCoord(0, 1, 0, 1)
    Bars.SetRing(button.item, def.art)
end

local function StoneActionText(kind, use)
    if not kind then return end
    local name = kind == "firestone" and Text.SET_BUTTON_FIRESTONE or Text.SET_BUTTON_SPELLSTONE
    return string.format(use and Text.ACT_APPLY_STONE or Text.ACT_CREATE_STONE, name)
end

local function ReminderTitle(key, button)
    local def = Core.CONTROL_BUTTONS[key]
    return (TITLES[key] and Text[TITLES[key]]) or (def.label and Text[def.label]) or SpellName(button.spellID)
        or SpellName(Core.SPELLS[def.spells[#def.spells]][1]) or ""
end

local dismissedUntil = {}

local function DismissClick(mouse)
    return mouse == "RightButton" and IsControlKeyDown() and not IsShiftKeyDown() and not Plain(IsAltKeyDown)
end

local function Dismiss(key, button)
    local due = GetTime() + Core.REMINDER_DISMISS_SECONDS
    dismissedUntil[key] = due
    ns.Print(string.format(Text.REMINDER_DISMISSED, ReminderTitle(key, button), Core.REMINDER_DISMISS_SECONDS / 60))
    Buttons.Refresh()
    C_Timer.After(Core.REMINDER_DISMISS_SECONDS, function()
        if dismissedUntil[key] == due and GetTime() >= due then
            dismissedUntil[key] = nil
            Buttons.Refresh()
        end
    end)
end

local function Tooltip(tooltip, key, button)
    Tips.Title(tooltip, ReminderTitle(key, button))
    Tips.Line(tooltip, key == "demon" and button.guiding and Text.TIP_GUIDED_DEMON or Text[TIPS[key]])
    if key == "demon" then
        Tips.Click(tooltip, "left", Text.ACT_CHOOSE_DEMON)
        if button.spellID then Tips.Click(tooltip, "right", SpellName(button.spellID) or "?") end
        Tips.Click(tooltip, "ctrlRight", string.format(Text.ACT_REMINDER_DISMISS, Core.REMINDER_DISMISS_SECONDS / 60))
        if button.spellID then
            local buff, risky = Controls.SacrificeInfo(button.demonKey)
            if risky and buff then Tips.Note(tooltip, string.format(Text.TIP_SACRIFICE_RISK, buff)) end
            local domination = Core.HighestKnown(Core.SPELLS.felDomination, Buttons.IsKnown)
            if domination then
                Tips.Note(tooltip, string.format(Text.TIP_DOMINATION_IN_COMBAT, SpellName(domination) or "?"))
            end
        end
    elseif key == "weaponStone" then
        Tips.Click(tooltip, "any", StoneActionText(button.stoneKind, button.useKind))
        Tips.Click(tooltip, "shift", StoneActionText(button.shiftKind, button.shiftUse))
    elseif key == "soulstone" and button:GetAttribute("ssShortcut") then
        Tips.Click(tooltip, "left", Text.ACT_USE_FRIEND)
        Tips.Click(tooltip, "right", Text.ACT_SOULSTONE_TARGET)
    elseif key == "soulstone" then
        Tips.Click(tooltip, "any", button.useKind and Text.ACT_USE_FRIEND or Text.ACT_CREATE)
    else
        Tips.Click(tooltip, "any", Text[CLICKS[key]])
    end
    if key ~= "demon" and not Core.CONTROL_BUTTONS[key].alwaysShow then
        Tips.Click(tooltip, "ctrlRight", string.format(Text.ACT_REMINDER_DISMISS, Core.REMINDER_DISMISS_SECONDS / 60))
    end
end

local function DemonPicture(item, demonKey)
    local id = demonKey and Core.SPELLS[demonKey] and (Core.PickSpell({ demonKey }, Buttons.IsKnown) or Core.SPELLS[demonKey][1])
    local icon = id and Plain(C_Spell.GetSpellTexture, id)
    if icon then
        item.face.icon:SetTexture(icon)
        item.face.icon:SetTexCoord(0, 1, 0, 1)
        Bars.SetRing(item, demonKey)
    else
        item.face.icon:SetTexture(Core.UiTexture((demonKey or "PetMenuButton") .. "-01"))
        Bars.SetRing(item, demonKey or "PetMenuButton")
    end
end

local function Create(key, header)
    local def = Core.CONTROL_BUTTONS[key]
    local button = Buttons.NewSecureButton(NAMES[key], bar.frame, Core.BUTTON_SIZE)
    button.key = key
    button:SetAttribute("ctrl-type2", "")
    button:SetScript("PreClick", function(self, mouse)
        if not DismissClick(mouse) then Buttons.PreClick(self, mouse) end
    end)
    button:SetScript("PostClick", function(self, mouse)
        if DismissClick(mouse) then
            if not def.alwaysShow then Dismiss(key, self) end
        else
            Buttons.PostClick(self, mouse)
        end
    end)
    ns.Sounds.Button(button)
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
        local function Uses(self, mouse)
            return mouse == "LeftButton" or (mouse == "RightButton" and not self:GetAttribute("ssShortcut"))
        end
        button.onPreClick = function(self, mouse)
            if Uses(self, mouse) and self.useKind and not InCombat() then
                local macro = ns.Stones.UseMacro("soulstone")
                self:SetAttribute("macrotext1", macro)
                if not self:GetAttribute("ssShortcut") then self:SetAttribute("macrotext2", macro) end
                if ns.SoulstoneShortcut then
                    ns.SoulstoneShortcut.HoldFarUse(self, "target", "macrotext1", "macrotext2")
                end
            end
        end
        button.speechSubject = function(mouse)
            if Uses(button, mouse) and button.useKind
                and not (ns.SoulstoneShortcut and ns.SoulstoneShortcut.WouldHold("target")) then
                return "soulstone", "friend"
            end
        end
        if ns.SoulstoneShortcut then ns.SoulstoneShortcut.Attach(button, header) end
        if ns.RangeCover then ns.RangeCover.AddSoulstone(button, item.face) end
    elseif def.missing == "enchant" then
        button.onPreClick = function(self, mouse)
            if mouse ~= "LeftButton" and mouse ~= "RightButton" then return end
            local use = self.useKind
            if StoneShiftDown() and self.shiftKind then use = self.shiftUse end
            if use then ns.Stones.NoteApplied(use) end
        end
    elseif def.missing == "demon" then
        ns.Menus.AttachDemonPicker(button, header)
        button:HookScript("OnAttributeChanged", function(_, name, value)
            if name == "againart" and type(value) == "string" then
                DemonPicture(item, value)
                button.demonKey = (Core.SPELLS[value] and value) or Core.DemonKeyOfArt(value) or button.demonKey
            end
        end)
        button.summonKey = function(mouse)
            if mouse == "RightButton" and button.spellID then return button.demonKey end
        end
        button.speechSubject = button.summonKey
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
        if type(aura) == "table" then return true, id end
    end
    return false
end

local function SacrificeOn() return BuffOn(Core.CONTROL_BUTTONS.sacrifice) end
local function PactLearned() return Buttons.IsKnown(Core.SPELLS.demonicPact[1]) end

function Controls.SacrificeInfo(key)
    local _, aura = SacrificeOn()
    if not aura then return end
    return SpellName(aura) or SpellName(Core.SPELLS.demonicSacrifice[1]), Core.SacrificeRisk(key, aura, PactLearned(), ns.db.buttons.sacAuraDemons)
end

local function Preferred(which)
    local key = Saved("sacrifice")[which]
    if not Buttons.IsKnown(Core.SPELLS.demonicSacrifice[1]) then return end
    for _, demon in ipairs(Core.DEMON_SUMMON_KEYS) do
        if demon == key and Buttons.IsKnown(Core.SPELLS[demon][1]) then return demon end
    end
end

local PET_FAMILY = { [23] = "imp", [16] = "voidwalker", [17] = "succubus", [15] = "felhunter" }

local function PetFamily()
    local ok, _, family = pcall(UnitCreatureFamily, "pet")
    if not ok or IsSecret(family) then return end
    if PET_FAMILY[family] then return PET_FAMILY[family] end
    if Core.HighestKnown(Core.SPELLS.seduction, ns.PetKnows) then return "succubus" end
end

local function PreferredPetOut(key)
    return PetFamily() == (key == "incubus" and "succubus" or key)
end

local function PetOut()
    local pet = Plain(UnitExists, "pet")
    if pet ~= true then return pet end
    local dead = Plain(UnitIsDead, "pet")
    if dead == nil then return nil end
    return not dead
end

function Controls.SacrificeReplaceInfo()
    local _, aura = SacrificeOn()
    if not aura or PetOut() == false then return end
    return SpellName(aura) or SpellName(Core.SPELLS.demonicSacrifice[1]),
        Core.SacrificeReplaceRisk(aura, PetFamily(), ns.db.buttons.sacAuraDemons)
end

local petWasOut

-- if no demon reminder show
local function DemonMissing()
    local pet = PetOut()
    if buttons.demon then buttons.demon.state = { petOut = pet } end
    if pet == nil then return nil end
    if pet then
        local preferred = Preferred("preferred")
        return preferred ~= nil and not InCombat() and Plain(UnitIsDeadOrGhost, "player") == false
            and SacrificeOn() == false and not PreferredPetOut(preferred)
    end
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

-- soulstone cooldown in sec, nil when hidden
local function SoulstoneLeft()
    local start, duration, hidden = ns.Stones.Cooldown("soulstone")
    if hidden then return nil end
    return start ~= nil and Core.CooldownLeft(start, duration, GetTime()) or 0
end

local SOULSTONE_SOUND = "SoulstoneEnd"
local soulstoneAnnouncementPending = false

-- play sound and message when switch on
local function SoulstoneReadySound()
    if ns.db.alerts.sounds.soulstone == false or ns.db.reminderBar.on == false then return end
    if ns.SoundsOn() and type(PlaySoundFile) == "function" then
        pcall(PlaySoundFile, Core.SoundPath(SOULSTONE_SOUND), "Master")
    end
    ns.Banner(Text.SOULSTONE_READY, 1.0, 0.82, 0.0)
end

Controls.SoulstoneReadySound = SoulstoneReadySound

-- ready when cooldown and soulstone buff both gone
local function WatchSoulstone()
    local dead = Plain(UnitIsDeadOrGhost, "player") == true
    local left = SoulstoneLeft()
    if left and left > 0 then
        soulstoneAnnouncementPending = true
        CheckSoulstoneAt(left)
        return false
    end
    if dead then return false end
    local buff = BuffOn(Core.CONTROL_BUTTONS.soulstone)
    if buff then return false end
    if left == nil or buff == nil then return nil end
    if soulstoneAnnouncementPending then
        soulstoneAnnouncementPending = false
        SoulstoneReadySound()
    end
    return true
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
    if ns.db.alerts.sounds.unendingBreath == false or ns.db.reminderBar.on == false or ns.Silent() or type(PlaySound) ~= "function" then return end
    local now = GetTime()
    if breathSoundAt and now - breathSoundAt < Core.BREATH_SOUND_GAP then return end
    breathSoundAt = now
    pcall(PlaySound, type(SOUNDKIT) == "table" and SOUNDKIT.RAID_WARNING or SOUND)
end

-- if the thing icon warns is missing, nil when hidden
local function Missing(key, soulstoneReady)
    local def = Core.CONTROL_BUTTONS[key]
    if def.missing == "soulstoneReady" then
        return soulstoneReady
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
    if key == "sacrifice" then
        local preferred = Preferred("preferred")
        if preferred and not PreferredPetOut(preferred) then return false end
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

function UpdateShown()
    if not bar then return end
    local soulstoneReady = WatchSoulstone()
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
    if Buttons.DemoMode() then
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
        elseif safe and not Core.CONTROL_BUTTONS[key].alwaysShow and Core.SafeAreaHides(ns.db.reminderBar.hideInCities, safe) then
            want = false
            button.why = "safe area"
        else
            local missing = Missing(key, soulstoneReady)
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

-- spell to cast, demon reminder also look at sacrifice buff
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
    local _, aura = SacrificeOn()
    local pact = PactLearned()
    local avoid = Core.SacrificedDemon(aura, ns.db.buttons.sacAuraDemons)
    if pact and aura and not avoid then return nil end
    local preferred
    if not aura then preferred = Preferred("preferred")
    elseif pact then preferred = Preferred("keep") end
    local key = Core.DemonToSummon(known, preferred or ns.db.buttons.lastDemon, avoid, pact)
    if not key then return nil, nil end
    return Core.HighestKnown(Core.SPELLS[key], Buttons.IsKnown), key
end

-- what click do, cast spell or use stone
local function ActionsFor(button, def, id)
    button.useKind = nil
    if def.missing == "soulstoneReady" then
        armedHeld.soulstone = ns.Stones.State().soulstone ~= nil
        if armedHeld.soulstone then
            button.useKind = "soulstone"
            return { type1 = "macro", macrotext1 = ns.Stones.UseMacro("soulstone"), spell1 = false, type2 = false,
                macrotext2 = false }
        end
        local actions = Buttons.CastActions(id)
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
    local actions = Buttons.CastActions(id)
    actions.type2, actions.macrotext2 = false, false
    if def.missing == "breath" then
        actions.unit1 = id and "player" or false
    end
    return actions
end

local function MirrorRight(actions)
    for _, name in ipairs({ "type", "spell", "macrotext", "unit" }) do
        local left = actions[name .. "1"]
        if left == nil then left = false end
        actions[name .. "2"] = left
    end
    return actions
end

local function WeaponStoneActions(button, id, kind)
    local held = ns.Stones.State()
    armedHeld.firestone, armedHeld.spellstone = held.firestone ~= nil, held.spellstone ~= nil
    local other = kind and (kind == "firestone" and "spellstone" or "firestone")
    local use = kind and held[kind] and kind
    button.stoneKind, button.useKind = kind, use
    local actions = use and { type1 = "macro", macrotext1 = ns.Stones.UseMacro(use), spell1 = false }
        or Buttons.CastActions(id)
    local create = other and ns.Stones.Definition(other).create
    local alternateID = create and Core.HighestKnown(Core.SPELLS[create], Buttons.IsKnown)
    button.shiftUse = other and held[other] and other
    button.shiftKind = (button.shiftUse or alternateID) and other or nil
    local shifted = button.shiftUse and { type1 = "macro", macrotext1 = ns.Stones.UseMacro(other) }
        or Buttons.CastActions(alternateID)
    for _, attr in ipairs({ "type", "spell", "macrotext" }) do
        actions["shift-" .. attr .. "1"] = shifted[attr .. "1"] or false
        actions["shift-" .. attr .. "2"] = shifted[attr .. "1"] or false
    end
    return actions
end

local armedSacrifice

local function Refresh()
    if not bar then return end
    armedSacrifice = select(2, SacrificeOn())
    local now = GetTime()
    for _, key in ipairs(Core.CONTROL_BUTTON_KEYS) do
        local def = Core.CONTROL_BUTTONS[key]
        local button, saved = buttons[key], Saved(key)
        local item = button.item
        local id, spell, kind = ChooseSpell(def)
        button.spellID = id
        if def.missing == "demon" then
            local avoid = PactLearned() and armedSacrifice
                and (Core.SacrificedDemon(armedSacrifice, ns.db.buttons.sacAuraDemons) or "unknown")
            button:SetAttribute("avoidDemon", avoid or nil)
            button.demonKey = spell
            button.guiding = Preferred("preferred") ~= nil or (PactLearned() and Preferred("keep") ~= nil)
        end
        local actions = def.missing == "enchant" and WeaponStoneActions(button, id, kind)
            or ActionsFor(button, def, id)
        local armed = def.missing == "soulstoneReady" and ns.SoulstoneShortcut ~= nil and ns.SoulstoneShortcut.Armed()
        if def.missing == "soulstoneReady" then actions.ssShortcut = armed end
        if armed then
            actions.type2, actions.spell2, actions.macrotext2 = false, false, false
        elseif def.missing ~= "demon" then
            MirrorRight(actions)
        end
        Buttons.SetActions(button, actions)
        if def.missing == "demon" then
            local demonKey = spell or def.spells[1]
            local icon = Plain(C_Spell.GetSpellTexture, id or Core.SPELLS[demonKey][1])
            item.face.icon:SetTexture(icon or Core.UiTexture(((spell and Core.DemonArt(spell)) or "PetMenuButton") .. "-01"))
            item.face.icon:SetTexCoord(0, 1, 0, 1)
            Bars.SetRing(item, spell or "PetMenuButton")
        elseif def.missing == "enchant" then
            WeaponStonePicture(button)
            Tips.Redraw(button)
        elseif def.gameIcon then
            item.face.icon:SetTexture(Plain(C_Spell.GetSpellTexture, id or Core.SPELLS[def.spells[1]][1]))
        end
        item.face.icon:SetDesaturated(id == nil and not ns.demo)
        local required = not def.requires or Core.HighestKnown(Core.SPELLS[def.requires], Buttons.IsKnown) ~= nil
        if key == "sacrifice" and Preferred("preferred") then required = true end
        local available = id ~= nil or (key == "demon" and Core.PickSpell(def.spells, Buttons.IsKnown) ~= nil)
        button.ready = saved.on ~= false and ns.db.reminderBar.on ~= false
            and (ns.placing == true or (dismissedUntil[key] or 0) <= now)
            and ((available and required) or ns.placing == true or Buttons.DemoMode())
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

local function LearnSacrifice(family)
    if InCombat() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    local known = Core.ToSet(Core.SACRIFICE_AURAS)
    for _, ids in pairs(Core.SPELLS) do
        for _, id in ipairs(ids) do known[id] = true end
    end
    for _, id in ipairs(Core.SOULLINK_AURAS) do known[id] = true end
    for _, id in ipairs(Core.SOULSTONE_AURAS) do known[id] = true end
    local now = GetTime()
    local ok, found = pcall(function()
        local candidate
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            local id, duration, expires = aura.spellId, aura.duration, aura.expirationTime
            if IsSecret(id) or Core.SACRIFICE_DEMON[id] then return end
            if not (IsSecret(duration) or IsSecret(expires)) and type(id) == "number"
                and type(duration) == "number" and type(expires) == "number" and duration >= 1800
                and math.abs(expires - duration - now) < 5 and not known[id] then
                if candidate then return end
                candidate = id
            end
        end
        return candidate
    end)
    if ok and found then
        ns.db.buttons.sacAuras[found] = true
        if family then ns.db.buttons.sacAuraDemons[found] = family end
        auraIdsCache = {}
        Refresh()
    end
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
    events:RegisterEvent("MODIFIER_STATE_CHANGED")
    events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    events:RegisterUnitEvent("UNIT_AURA", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    events:RegisterUnitEvent("UNIT_PET", "player")
    events:RegisterUnitEvent("UNIT_HEALTH", "pet")
    for _, event in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_MOUNT_DISPLAY_CHANGED",
        "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED",
        "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        events:RegisterEvent(event)
    end
    local sacrificeCast, sacrificeFamily
    events:SetScript("OnEvent", function(_, event, _, cast, spellID, sentID)
        if event == "MODIFIER_STATE_CHANGED" then
            WeaponStonePicture(buttons.weaponStone)
            return
        elseif event == "UNIT_SPELLCAST_SENT" then
            if not InCombat() and not IsSecret(sentID) and SACRIFICE_SPELLS[sentID] then
                sacrificeCast, sacrificeFamily = spellID, PetFamily()
            end
            return
        end
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
            if not IsSecret(spellID) and SACRIFICE_SPELLS[spellID] then
                local family = not IsSecret(cast) and not IsSecret(sacrificeCast) and cast == sacrificeCast and sacrificeFamily
                sacrificeCast, sacrificeFamily = nil, nil
                C_Timer.After(0.5, function() LearnSacrifice(family) end)
            end
            local key = KeyOfSpell(spellID)
            if not key then return end
            if inCombat or InCombat() then castInFight[key] = true end
        end
        local auraChanged = event == "UNIT_AURA" or event == "ADDON_RESTRICTION_STATE_CHANGED"
            or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED"
        if auraChanged and not InCombat() and select(2, SacrificeOn()) ~= armedSacrifice then
            Refresh()
        else
            UpdateShown()
        end
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
ns.OnSetting("reminderBar.hideInCities", function() UpdateShown() end)

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

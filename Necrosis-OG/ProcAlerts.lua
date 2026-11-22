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

-- proc alerts icon and sound, shadow trance, decimation, amplify curse
local _, ns = ...
local Core, Text = ns.Core, ns.Text
local Bars = ns.Bars

local ProcAlerts = {}
ns.ProcAlerts = ProcAlerts

local SOUND_PATH = Core.MEDIA_PATH .. "Sounds\\"
local WARNING_SOUND = 8959
local CHECK_EVERY = 0.2

local PROCS = {
    { key = "shadowTrance", spells = "shadowBolt", icons = { Core.SHADOW_TRANCE_ID, Core.SPELLS.shadowBolt[1] },
        sound = "ShadowTrance-En.mp3", glows = true, buff = Core.PROC_BUFFS.shadowTrance },
    { key = "decimation", spells = "soulFire", icons = { Core.SPELLS.soulFire[1] }, glows = true,
        buff = Core.PROC_BUFFS.decimation },
    { key = "amplifyCurse", spells = "amplifyCurse", icons = { Core.SPELLS.amplifyCurse[1] } },
    { key = "antiFear", picture = "AntiFearImmune-01", ring = "AntiFearImmune", sound = "Fear-En.mp3" },
}
ProcAlerts.PROCS = PROCS
local BY_KEY = {}
for _, proc in ipairs(PROCS) do BY_KEY[proc.key] = proc end

local bar
local icons = {}
local active = {}
local demoOn = {}
local usual = {}
local glowSeen = {}
local reading
local amplifyEnd
local AMPLIFY = Core.ToSet(Core.SPELLS.amplifyCurse)
local GLOW_SPELLS = {}
for _, proc in ipairs(PROCS) do
    if proc.glows then
        for _, id in ipairs(Core.SPELLS[proc.spells]) do GLOW_SPELLS[id] = proc end
    end
end

local IsSecret, Plain, SpellName = ns.Game.IsSecret, ns.Game.Plain, ns.Game.SpellName

local knownRank = {}

local function Known(key)
    if knownRank[key] == nil then knownRank[key] = Core.HighestKnown(Core.SPELLS[key], ns.Buttons.IsKnown) or false end
    return knownRank[key] or nil
end

local function ReadCastTime(info) return info.castTime end

-- cast time in ms, nil when unknow or hidden
local function CastTime(spellID)
    local info = Plain(C_Spell.GetSpellInfo, spellID)
    if type(info) ~= "table" then return nil end
    local ok, time = pcall(ReadCastTime, info)
    if not ok or IsSecret(time) or type(time) ~= "number" then return nil end
    return time
end

local function PlayAlertSound(proc)
    if ns.db.alerts.sounds[proc.key] == false then return end
    if proc.sound then
        if type(PlaySoundFile) == "function" then pcall(PlaySoundFile, SOUND_PATH .. proc.sound, "Master") end
    elseif type(PlaySound) == "function" then
        pcall(PlaySound, type(SOUNDKIT) == "table" and SOUNDKIT.RAID_WARNING or WARNING_SOUND)
    end
end

local DEMO_LENGTH = #Core.DEMO.procs * Core.DEMO.procStep

-- sweep and number over the icon
local function AddTime(item)
    local face = item.face
    local swipe = ns.Durations.NewSwipe(face, { optional = true, reverse = true, shape = "mask", level = 4,
        place = function(cooldown) cooldown:SetAllPoints(face.texture) end })
    local text = ns.Durations.NewTimeText(face, swipe, ns.Durations.TimeFont(Core.ALERT_TIME_SIZE))
    item.time = { swipe = swipe, text = text, span = ns.Durations.New(),
        binding = ns.Durations.Text(text, "cooldown", "") }
    ns.Durations.ColourText(item.time.binding, Core.TimeFlashPoints())
end

local function HideTime(key)
    local time = icons[key] and icons[key].time
    if not time then return end
    if time.swipe then pcall(time.swipe.SetCooldown, time.swipe, 0, 0) end
    ns.Durations.HideText(time.binding, time.text)
end

local function ShowTime(key, start, length)
    local time = icons[key] and icons[key].time
    if not time then return end
    if not (start and length and length > 0) then return HideTime(key) end
    if time.swipe then pcall(time.swipe.SetCooldown, time.swipe, start, length) end
    ns.Durations.Set(time.span, start, length)
    ns.Durations.ShowText(time.binding, time.span)
end

local function ReadAura(aura) return aura.duration, aura.expirationTime end

-- start and length of proc buff, nil if hidden
local function ReadBuff(proc)
    local auras = C_UnitAuras
    if not proc.buff or type(auras) ~= "table" then return nil end
    local aura
    for _, id in ipairs(proc.buff) do
        aura = Plain(auras.GetPlayerAuraBySpellID, id)
        if type(aura) == "table" then break end
    end
    if type(aura) ~= "table" then return nil end
    local ok, length, ending = pcall(ReadAura, aura)
    if not ok or IsSecret(length) or IsSecret(ending) then return nil end
    if type(length) ~= "number" or type(ending) ~= "number" or length <= 0 then return nil end
    return ending - length, length
end

local function TimeFromBuff(proc)
    local start, length = ReadBuff(proc)
    if not start then return false end
    ns.db.alerts.lengths[proc.key] = length
    ShowTime(proc.key, start, length)
    return true
end

-- time of proc from buff, else from now
local function StartProcTime(proc)
    if TimeFromBuff(proc) then return end
    ShowTime(proc.key, GetTime(), ns.db.alerts.lengths[proc.key] or Core.PROC_LENGTH_GUESS[proc.key])
end

-- if icon can show, switch on, demo or placing
local function SwitchedOn(key) return ns.db.alerts[key .. "On"] ~= false end

local function RefreshAll()
    if not bar then return end
    for _, proc in ipairs(PROCS) do
        local item = icons[proc.key]
        item.ready = SwitchedOn(proc.key)
        item.wanted = (active[proc.key] or demoOn[proc.key] or ns.placing) == true
    end
    Bars.Layout(bar)
    if ns.BarHighlight then
        local glowing = {}
        for _, proc in ipairs(PROCS) do
            glowing[proc.key] = active[proc.key] and SwitchedOn(proc.key) and not glowSeen[proc.key] or nil
        end
        ns.BarHighlight.SetProcs(glowing)
    end
end

local function SetActive(proc, on, silent)
    if (active[proc.key] == true) == on then return end
    active[proc.key] = on or nil
    if on and not silent and SwitchedOn(proc.key) then PlayAlertSound(proc) end
    if on and proc.buff then StartProcTime(proc) end
    if not on and not demoOn[proc.key] then HideTime(proc.key) end
    RefreshAll()
end

local TIPS = {
    shadowTrance = function()
        return string.format(Text.TIP_PROC_SHADOW_TRANCE, SpellName(Core.SPELLS.shadowBolt[1]) or "?")
    end,
    decimation = function()
        return string.format(Text.TIP_PROC_DECIMATION, SpellName(Core.SPELLS.soulFire[1]) or "?")
    end,
    amplifyCurse = function()
        local names = {}
        for i, key in ipairs(Core.AMPLIFY_LIST) do names[i] = SpellName(Core.SPELLS[key][1]) or "?" end
        return string.format(Text.TIP_PROC_AMPLIFY_CURSE, names[1], names[2], names[3])
    end,
    antiFear = function()
        return ns.Alerts.Active() == "type" and Text.TIP_ANTI_FEAR_TYPE or Text.TIP_ANTI_FEAR_IMMUNE
    end,
}

local function CreateIcon(proc)
    local frame = CreateFrame("Frame", "NecrosisOGProc" .. proc.key, bar.frame)
    frame:SetSize(Core.BUTTON_SIZE, Core.BUTTON_SIZE)
    frame:SetMouseMotionEnabled(true)
    frame:SetMouseClickEnabled(false)
    ns.Tips.Attach(frame, function(tooltip)
        ns.Tips.Title(tooltip, ns.AlertName(proc.key))
        ns.Tips.Line(tooltip, TIPS[proc.key]())
    end)
    local item = Bars.AddItem(bar, proc.key, frame)
    ns.Alerts.DressIcon(item.face, Core.BUTTON_SIZE, proc.icons, proc.picture)
    ns.Rings.SetIcon(item.face, item.face.texture)
    Bars.SetRing(item, proc.ring or proc.key)
    icons[proc.key] = item
    if proc.key ~= "antiFear" then AddTime(item) end
end

-- check cast times for each proc
function ProcAlerts.Check(silent)
    silent = silent == true
    if not glowSeen.shadowTrance and SwitchedOn("shadowTrance") then
        local bolt = Known("shadowBolt")
        local boltTime = bolt and CastTime(bolt)
        if boltTime ~= nil then SetActive(BY_KEY.shadowTrance, boltTime == 0, silent) end
    end
    if not glowSeen.decimation and SwitchedOn("decimation") then
        local fire = Known("soulFire")
        local fireTime = fire and CastTime(fire)
        if fireTime ~= nil then
            if not usual[fire] or fireTime > usual[fire] then usual[fire] = fireTime end
            SetActive(BY_KEY.decimation, fireTime > 0 and fireTime < usual[fire] * Core.DECIMATION_RATIO, silent)
        end
    end
end

-- read cast times 5 times per sec while need
local function UpdateReading()
    local needed = false
    for _, proc in ipairs(PROCS) do
        if proc.glows and not glowSeen[proc.key] and SwitchedOn(proc.key) and Known(proc.spells) then needed = true end
    end
    if needed and not reading and C_Timer and C_Timer.NewTicker then
        reading = C_Timer.NewTicker(CHECK_EVERY, ProcAlerts.Check)
    elseif not needed and reading then
        reading:Cancel()
        reading = nil
    end
end

-- game make spell glow or stop
local function OnGlow(spellID, on)
    if IsSecret(spellID) or type(spellID) ~= "number" then return end
    local proc = GLOW_SPELLS[spellID]
    if not proc then return end
    if not glowSeen[proc.key] then
        if not on then return end
        glowSeen[proc.key] = true
        UpdateReading()
        RefreshAll()
    end
    SetActive(proc, on)
end

local function CheckGlowsNow()
    local overlay = C_SpellActivationOverlay
    if type(overlay) ~= "table" then return end
    for id in pairs(GLOW_SPELLS) do
        if ns.Buttons.IsKnown(id) and Plain(overlay.IsSpellOverlayed, id) == true then OnGlow(id, true) end
    end
end

local function EndAmplify()
    amplifyEnd.Cancel(1)
    SetActive(BY_KEY.amplifyCurse, false)
end

-- amplify curse show from cast until curse cast
local function OnPlayerSpell(spellID)
    if IsSecret(spellID) or type(spellID) ~= "number" then return end
    if AMPLIFY[spellID] then
        local length = Core.ParseSpellLength(Plain(C_Spell.GetSpellDescription, spellID))
        if length then amplifyEnd.At(1, GetTime() + length) else amplifyEnd.Cancel(1) end
        SetActive(BY_KEY.amplifyCurse, true)
        ShowTime("amplifyCurse", GetTime(), length)
    elseif Core.AMPLIFY_IDS[spellID] and active.amplifyCurse then
        EndAmplify()
    end
end

local function OnEvent(_, event, ...)
    local arg1, _, arg3 = ...
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        OnGlow(arg1, true)
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        OnGlow(arg1, false)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnPlayerSpell(arg3)
    elseif event == "PLAYER_REGEN_ENABLED" then
        for _, proc in ipairs(PROCS) do
            if proc.buff and active[proc.key] then TimeFromBuff(proc) end
        end
    end
end

local function Create()
    bar = Bars.New({ name = "NecrosisOGProcBar", saved = "procBar", label = "BAR_PROCS", strata = "HIGH", pulseIcon = true,
        noClicks = true })
    for _, proc in ipairs(PROCS) do CreateIcon(proc) end
    Bars.Apply(bar)
    RefreshAll()
    amplifyEnd = ns.Durations.NewSchedule(function() EndAmplify() end)
    local events = CreateFrame("Frame")
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    events:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    events:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", OnEvent)
    CheckGlowsNow()
    UpdateReading()
    table.insert(ns.onPlacing, RefreshAll)
    table.insert(ns.onSpellsChanged, function()
        for key in pairs(knownRank) do knownRank[key] = nil end
        UpdateReading()
    end)
end

table.insert(ns.onSphere, Create)

-- anti fear warn on or off
function ProcAlerts.SetActive(key, on)
    if BY_KEY[key] then SetActive(BY_KEY[key], on) end
end

table.insert(ns.onDemoData, function(on)
    if not bar then return end
    for key in pairs(demoOn) do
        demoOn[key] = nil
        if not active[key] then HideTime(key) end
    end
    if on then
        local step = 0
        ns.DemoEvery(Core.DEMO.procStep, function()
            local shown = Core.DemoProcsOn(step, Core.DEMO.procs)
            for _, proc in ipairs(PROCS) do
                local came = shown[proc.key] and not demoOn[proc.key] and SwitchedOn(proc.key)
                local went = demoOn[proc.key] and not shown[proc.key]
                demoOn[proc.key] = shown[proc.key]
                if came then
                    PlayAlertSound(proc)
                    ShowTime(proc.key, GetTime(), DEMO_LENGTH)
                end
                if went and not active[proc.key] then HideTime(proc.key) end
            end
            step = step + 1
            RefreshAll()
        end)
        return
    end
    RefreshAll()
end)

-- settings changed, redraw
function ProcAlerts.Refresh()
    if not bar then return end
    Bars.Apply(bar)
    RefreshAll()
    UpdateReading()
    ProcAlerts.Check(true)
end

ProcAlerts.Icons = function() return icons end -- for tests
ProcAlerts.Bar = function() return bar end
ProcAlerts.Active = function() return active end
ProcAlerts.DemoOn = function() return demoOn end
ProcAlerts.GlowSeen = function() return glowSeen end
ProcAlerts.Reading = function() return reading ~= nil end
ProcAlerts.Time = function(key) return icons[key] and icons[key].time end

ns.OnSetting({ "procBar.scale", "procBar.spacing" }, function() ProcAlerts.Refresh() end)

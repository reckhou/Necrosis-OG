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

local _, ns = ...
local Core, Game = ns.Core, ns.Game
local Plain, IsSecret = Game.Plain, Game.IsSecret

local BarHighlight = {}
ns.BarHighlight = BarHighlight

-- glow the next spell on action bars
local FILTER = "HARMFUL|PLAYER"
local LAYOUT = "DisableUntrustedLayoutScriptsTemplate"

local families = {}
local glows = {}
local shown = {}
local nativeRequired = false
local PROC_SPELLS = { shadowTrance = "shadowBolt", decimation = "soulFire" }
local procIds = {}
for key, spell in pairs(PROC_SPELLS) do
    for _, id in ipairs(Core.SPELLS[spell]) do procIds[id] = key end
end

local procOn = {}
local procGlows = {}
local procShown = {}
local scanPending = false

local WRACK_IDS = Core.SpellIdSet({ "wrack" })
local wrackKnown = false
local channelling = false
local procActive = {}
local rotGlows = {}
local rotShown = {}

local estimates = {}
local lengths = {}
local rotationTicker

local siphonPlace
local typeImmune = false
local textImmune = false
local immuneGuids = {}
local siphonCastAt = -100
local siphonSkipped = false
local demoSet

local function Knows(id) return Plain(C_SpellBook.IsSpellKnown, id) == true end

local function KnowsFamily(id) return Knows(id) or Plain(IsPlayerSpell, id) == true end

-- get the debuff family from setting, in order
local function ReadFamilies()
    families = {}
    local timers = ns.db.timers
    for _, slot in ipairs(Core.EnemySlotsKnown(KnowsFamily, false, timers.trackOff, timers.trackOrder)) do
        local family = { key = slot.key, ids = Core.SpellIdSet(slot.keys), casts = {}, spells = {} }
        if slot.talent then
            family.brand = Game.SpellName(Core.SEARING_PAIN)
            local name = Game.SpellName(Core.SPELLS[slot.keys[1]][1])
            if name then family.spells[1] = { name = name, ranks = Core.SPELLS[slot.keys[1]], key = slot.keys[1] } end
        else
            for _, key in ipairs(slot.keys) do
                for _, id in ipairs(Core.SPELLS[key]) do family.casts[id] = true end
                local name = Game.SpellName(Core.HighestKnown(Core.SPELLS[key], Knows))
                if name then family.spells[#family.spells + 1] = { name = name, ranks = Core.SPELLS[key], key = key } end
            end
        end
        families[#families + 1] = family
    end
    siphonPlace = nil
    for place, family in ipairs(families) do
        if family.key == "siphonLife" then siphonPlace = place end
    end
    wrackKnown = false
    for id in pairs(WRACK_IDS) do wrackKnown = wrackKnown or KnowsFamily(id) end
end

local function HelperOn()
    local timers = ns.db.timers
    return wrackKnown and timers.barHighlight.on ~= false and timers.wrackHelper.on ~= false
end

local function UpdateReadability()
    nativeRequired = C_Secrets ~= nil and Plain(C_Secrets.ShouldAurasBeSecret) ~= false
    if nativeRequired or not (C_Secrets and C_Secrets.ShouldSpellAuraBeSecret) then return end
    for _, family in ipairs(families) do
        for _, spell in ipairs(family.spells) do
            for _, id in ipairs(spell.ranks) do
                if Plain(C_Secrets.ShouldSpellAuraBeSecret, id) ~= false then
                    nativeRequired = true
                    return
                end
            end
        end
    end
end

local function PlaceOfSpell(spellID)
    local name
    for place, family in ipairs(families) do
        if family.casts[spellID] then return place end
        if family.brand then
            name = name or Game.SpellName(spellID)
            if name == family.brand then return place end
        end
    end
    return nil
end

local function ActionSpell(slot)
    if type(slot) ~= "number" or IsSecret(slot) then return nil end
    local ok, kind, id, sub = pcall(GetActionInfo, slot)
    if not ok or IsSecret(kind) or IsSecret(id) or IsSecret(sub) then return nil end
    if kind == "spell" or (kind == "macro" and sub == "spell") then
        if type(id) == "number" then return id end
    end
    return nil
end

local function NewContainer(parent, family, width)
    local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate," .. LAYOUT)
    container:SetEnabled(false)
    container:EnableMouse(false)
    container:SetAlpha(0)
    container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
    container:SetFlowLayoutAnchorPoint("TOPLEFT")
    container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    container:SetFlowLayoutPadding(0, 0, 0, 0)
    container:SetFlowLayoutMaximumLineSize(width + 1)
    container:AddAuraGroup(family.key, FILTER, {
        maxFrameCount = 1, candidateFilters = { includeSpellIDs = family.ids },
        layout = { elementWidth = width, elementHeight = 1, elementSpacing = 0, lineSpacing = 0 },
        initializeFrame = function(element)
            element:SetSize(1, 1)
            element:EnableMouse(false)
        end,
    })
    return container
end

-- glow frame on top of the button
local function NewGlow(button, place, all)
    local width, height = button:GetSize()
    local size = Core.BAR_GLOW_SIZE
    local clip = CreateFrame("Frame", nil, button, LAYOUT)
    clip:Hide()
    clip:EnableMouse(false)
    clip:SetClipsChildren(true)
    clip:SetSize(width * size, height * size)
    clip:SetPoint("CENTER", button, "CENTER", 0, 0)
    local start, widths
    if all then start, widths = Core.BarGlowAllChain(#families) else start, widths = Core.BarGlowChain(place) end
    local chain, before = {}, nil
    for i, length in ipairs(widths) do
        local container = NewContainer(clip, families[i], length)
        if before then
            container:SetPoint("TOPLEFT", before, "TOPRIGHT", 0, 0)
        else
            container:SetPoint("TOPLEFT", clip, "CENTER", start, 0)
        end
        chain[i], before = container, container
    end
    local alert = CreateFrame("Frame", nil, clip, "ActionButtonSpellAlertTemplate")
    alert:EnableMouse(false)
    alert:SetSize(width * size, height * size)
    return { button = button, place = place, all = all, clip = clip, chain = chain, alert = alert }
end

local function Skipped(place)
    return siphonSkipped and place ~= nil and place == siphonPlace
end

local function ShiftOf(glow)
    if not siphonSkipped or not siphonPlace then return 0 end
    if glow.all or siphonPlace < glow.place then return Core.BAR_GLOW_STEP end
    return 0
end

local function Play(glow)
    local loop = glow.alert.ProcLoop
    if loop and not loop:IsPlaying() then loop:Play() end
end

local function Place(glow, native)
    local shift = native and ShiftOf(glow) or 0
    if glow.native == native and glow.shift == shift then return end
    glow.alert:ClearAllPoints()
    if native and #glow.chain > 0 then
        glow.alert:SetPoint("CENTER", glow.chain[#glow.chain], "TOPRIGHT", shift, 0)
    else
        glow.alert:SetPoint("CENTER", glow.clip, "CENTER", 0, 0)
    end
    glow.native, glow.shift = native, shift
end

local function Watch(glow, on)
    for _, container in ipairs(glow.chain) do
        if on then
            container:SetUnit("target")
            container:SetEnabled(true)
            container:UpdateAllAuras()
        else
            container:SetEnabled(false)
        end
    end
    glow.watching = on
end

local function Stop(glow)
    glow.clip:Hide()
    if glow.watching then Watch(glow, false) end
end

-- family debuff is on the target or not
local function IsOn(family)
    for _, spell in ipairs(family.spells) do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "target", spell.name, FILTER)
        if not ok or IsSecret(aura) then return nil end
        if aura ~= nil then return true end
    end
    return false
end

local function NextPlace()
    for place, family in ipairs(families) do
        if not Skipped(place) then
            local on = IsOn(family)
            if on == nil then return nil end
            if not on then return place end
        end
    end
    return nil
end

local function Now() return Plain(GetTime) or 0 end
local function TargetGuid() return Plain(UnitGUID, "target") end

-- read aura time or use last cast time
local function TimeLeft(family, native, now)
    if not native then
        for _, spell in ipairs(family.spells) do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "target", spell.name, FILTER)
            if ok and type(aura) == "table" and not IsSecret(aura) then
                local ends = aura.expirationTime
                if type(ends) == "number" and not IsSecret(ends) and ends > 0 then return ends - now, spell.key, "aura" end
            end
        end
    end
    local guid = TargetGuid()
    local cast = (estimates.target and estimates.target[family.key])
        or (guid and estimates[guid] and estimates[guid][family.key])
    if cast then return cast.endsAt - now, cast.spellKey, "cast" end
    return nil
end

local function SoonPlace(native, now)
    local latency = Game.Latency()
    for place, family in ipairs(families) do
        local left, spellKey
        if not Skipped(place) then left, spellKey = TimeLeft(family, native, now) end
        if left and left > 0 then
            local lead = Core.FlashLead(family.key, spellKey)
            if lead > 0 and left <= Core.AddLatency(lead, latency) then return place end
        end
    end
    return nil
end

local function DebuffLength(spellID, family)
    if family.brand then return Core.DEMONIC_BRAND_SECONDS end
    if lengths[spellID] == nil then
        lengths[spellID] = Core.ParseDebuffLength(Plain(C_Spell.GetSpellDescription, spellID))
    end
    return lengths[spellID]
end

local lastCast

local function OnCast(spellID)
    if type(spellID) ~= "number" or IsSecret(spellID) then
        lastCast = "secret"
        return
    end
    local place = PlaceOfSpell(spellID)
    lastCast = tostring(spellID)
    if not place then return end
    if place == siphonPlace then siphonCastAt = Now() end
    local family = families[place]
    local length = DebuffLength(spellID, family)
    lastCast = lastCast .. " " .. family.key .. " " .. tostring(length)
    if not length then return end
    local cast = { endsAt = Now() + length - Game.Latency() / 2,
        spellKey = family.brand and "demonicBrand" or Core.EnemySlotSpellKey(family.key, spellID) }
    for _, key in ipairs({ "target", TargetGuid() or "target" }) do
        estimates[key] = estimates[key] or {}
        estimates[key][family.key] = cast
    end
end

local function SetSiphonSkipped()
    local skipped = typeImmune or textImmune
    if skipped == siphonSkipped then return false end
    siphonSkipped = skipped
    if ns.MissingDebuffs and ns.MissingDebuffs.SetTargetSiphonImmune then
        ns.MissingDebuffs.SetTargetSiphonImmune(skipped)
    end
    return true
end

-- get siphon immunity for current target
local function ReadTargetImmunity()
    local guid = TargetGuid()
    textImmune = guid ~= nil and immuneGuids[guid] == true
    typeImmune = false
    local ok, _, typeID = pcall(UnitCreatureType, "target")
    if ok and not IsSecret(typeID) and type(typeID) == "number" then
        typeImmune = Core.SIPHON_IMMUNE_TYPES[typeID] == true
    end
    return SetSiphonSkipped()
end

local function OnTargetCombat(action, school)
    if IsSecret(action) or IsSecret(school) or not Core.IsImmuneText(action, school) then return false end
    if siphonPlace == nil or Now() - siphonCastAt > Core.TIMER_RESIST_WINDOW then return false end
    textImmune = true
    local guid = TargetGuid()
    if guid then immuneGuids[guid] = true end
    return SetSiphonSkipped()
end

local function PruneEstimates()
    local now = Now()
    for key, casts in pairs(estimates) do
        local any = false
        for family, cast in pairs(casts) do
            if cast.endsAt <= now then casts[family] = nil else any = true end
        end
        if not any then estimates[key] = nil end
    end
end

local function DemoNextPlace()
    if not demoSet then return nil end
    local timers = ns.db.timers
    local allFamilies = Core.EnemySlotsKnown(KnowsFamily, true, timers.trackOff, timers.trackOrder)
    return Core.DemoMissingNext(demoSet, allFamilies, families)
end

local function TargetOk()
    if ns.db.timers.barHighlight.on == false then return false end
    if demoSet then return true end
    return Plain(UnitCanAttack, "player", "target") == true
        and Plain(UnitIsDeadOrGhost, "target") == false
end

local function BoltFirst()
    return HelperOn() and TargetOk() and not (not demoSet and channelling) and procActive.shadowTrance == true
end

-- light the spell picked by wrack rotation
local function RefreshRotation()
    local active = HelperOn() and TargetOk()
    local native = not demoSet and (Game.InCombat() or nativeRequired)
    local choice, soon
    if active then
        soon = not demoSet and SoonPlace(native, Now()) or nil
        local missing
        if demoSet then missing = DemoNextPlace() elseif not native then missing = NextPlace() end
        choice = Core.RotationChoice({ channelling = not demoSet and channelling or false, missing = missing,
            soon = soon, bolt = procActive.shadowTrance == true })
    end
    local boltFirst = BoltFirst()
    for _, glow in ipairs(rotShown) do
        if active and native then
            if not glow.watching then Watch(glow, true) end
        elseif glow.watching then
            Watch(glow, false)
        end
        Place(glow, native and not (boltFirst and glow.kind == "bolt"))
        local on = choice ~= nil and glow.kind == choice and (choice ~= "refresh" or glow.place == soon)
        glow.alert:SetShown(on)
        glow.clip:SetShown(on)
        if on then Play(glow) end
    end
    BarHighlight.choice = choice
end

local function UpdateTicker()
    local wanted = not demoSet and HelperOn() and TargetOk() and #rotShown > 0
    if wanted and not rotationTicker and C_Timer and C_Timer.NewTicker then
        rotationTicker = C_Timer.NewTicker(0.1, RefreshRotation)
    elseif not wanted and rotationTicker then
        rotationTicker:Cancel()
        rotationTicker = nil
    end
end

local function NewProcGlow(button, key)
    local width, height = button:GetSize()
    local alert = CreateFrame("Frame", nil, button, "ActionButtonSpellAlertTemplate")
    alert:EnableMouse(false)
    alert:SetSize(width * Core.BAR_GLOW_SIZE, height * Core.BAR_GLOW_SIZE)
    alert:SetPoint("CENTER", button, "CENTER", 0, 0)
    alert:Hide()
    return { button = button, key = key, alert = alert }
end

local function RefreshProcs()
    local helper = HelperOn()
    local channel = not demoSet and channelling
    for _, glow in ipairs(procShown) do
        local on = procOn[glow.key] == true and not (helper and (channel or glow.key == "shadowTrance"))
        glow.alert:SetShown(on)
        if on then Play(glow) end
    end
end

-- update the shadow bolt and soul fire glows
function BarHighlight.SetProcs(state, active)
    procOn, procActive = {}, {}
    for key in pairs(PROC_SPELLS) do
        procOn[key] = state[key] == true or nil
        procActive[key] = active and active[key] == true or nil
    end
    BarHighlight.Redraw()
end

local function Refresh(resync)
    local target = TargetOk()
    local native = not demoSet and (Game.InCombat() or nativeRequired)
    local nextPlace
    if target then
        if demoSet then nextPlace = DemoNextPlace() elseif not native then nextPlace = NextPlace() end
    end
    local wrackChannel = not demoSet and channelling and HelperOn()
    if ns.MissingDebuffs then ns.MissingDebuffs.SetWrackChannel(wrackChannel) end
    local hold = wrackChannel or BoltFirst()
    for _, glow in ipairs(shown) do
        if not target then
            Stop(glow)
        elseif native then
            Place(glow, true)
            if not glow.watching or resync then Watch(glow, true) end
            local blocked = hold or Skipped(glow.place)
            glow.alert:Show()
            glow.clip:SetShown(not blocked)
            if not blocked then Play(glow) end
        else
            if glow.watching then Watch(glow, false) end
            Place(glow, false)
            local on = glow.place == nextPlace and not hold
            glow.alert:SetShown(on)
            glow.clip:SetShown(on)
            if on then Play(glow) end
        end
    end
    if resync then
        for _, glow in ipairs(rotShown) do
            if glow.watching then Watch(glow, true) end
        end
    end
    RefreshProcs()
    RefreshRotation()
    UpdateTicker()
end

function BarHighlight.Redraw() Refresh() end

local function Scan()
    scanPending = false
    local wanted, missed, procWanted, rotWanted = {}, false, {}, {}
    local helper = HelperOn()
    local allKeys = {}
    for i, family in ipairs(families) do allKeys[i] = family.key end
    allKeys = table.concat(allKeys, ",")
    local function Helper(button, kind, place)
        local id = (button:GetName() or tostring(button)) .. "|" .. kind .. "|" .. (place or 0) .. "|" .. allKeys
        local glow = rotGlows[id]
        if not glow then
            local ok, made = pcall(NewGlow, button, place or 0, true)
            if ok then
                made.kind = kind
                glow = made
                rotGlows[id] = glow
            else
                missed = true
            end
        end
        if glow then rotWanted[glow] = true end
    end
    for _, button in ipairs(ns.ActionButtons.Bar()) do
        local spell = ActionSpell(ns.ActionButtons.Slot(button))
        if helper and spell then
            if WRACK_IDS[spell] then Helper(button, "wrack") end
            if procIds[spell] == "shadowTrance" then Helper(button, "bolt") end
            local place = PlaceOfSpell(spell)
            if place then Helper(button, "refresh", place) end
        end
        local proc = spell and procIds[spell]
        if proc then
            local id = (button:GetName() or tostring(button)) .. "|" .. proc
            local ok, made = true, procGlows[id]
            if not made then ok, made = pcall(NewProcGlow, button, proc) end
            if ok then
                procGlows[id] = made
                procWanted[made] = true
            end
        end
        local place = spell and PlaceOfSpell(spell)
        if place then
            local keys = {}
            for i = 1, place do keys[i] = families[i].key end
            local id = (button:GetName() or tostring(button)) .. "|" .. place .. "|" .. table.concat(keys, ",")
            local glow = glows[id]
            if not glow then
                local ok, made = pcall(NewGlow, button, place)
                if ok then
                    glow = made
                    glows[id] = glow
                else
                    missed = true
                end
            end
            if glow then wanted[glow] = true end
        end
    end
    for _, glow in ipairs(shown) do
        if not wanted[glow] then Stop(glow) end
    end
    shown = {}
    for _, glow in pairs(glows) do
        if wanted[glow] then shown[#shown + 1] = glow end
    end
    table.sort(shown, function(a, b) return a.place < b.place end)
    for _, glow in ipairs(procShown) do
        if not procWanted[glow] then glow.alert:Hide() end
    end
    procShown = {}
    for glow in pairs(procWanted) do procShown[#procShown + 1] = glow end
    for _, glow in ipairs(rotShown) do
        if not rotWanted[glow] then Stop(glow) end
    end
    rotShown = {}
    for glow in pairs(rotWanted) do rotShown[#rotShown + 1] = glow end
    RefreshProcs()
    BarHighlight.retry = missed
    Refresh(true)
end

local function ScanSoon()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0, Scan)
end

local function LoadLengths()
    for _, family in ipairs(families) do
        for _, spell in ipairs(family.spells) do
            local id = Core.HighestKnown(spell.ranks, Knows)
            if id then DebuffLength(id, family) end
        end
    end
end

local function Rebuild()
    ReadFamilies()
    LoadLengths()
    UpdateReadability()
    Scan()
end

function BarHighlight.Shown() return shown end
function BarHighlight.ProcShown() return procShown end
function BarHighlight.HelperShown() return rotShown end

function BarHighlight.Report()
    local Text = ns.Text
    local native = Game.InCombat() or nativeRequired
    local now, latency = Now(), Game.Latency()
    local lit = {}
    for _, glow in ipairs(rotShown) do
        if glow.clip.IsShown and glow.clip:IsShown() then
            lit[#lit + 1] = glow.kind .. ":" .. ((glow.button.GetName and glow.button:GetName()) or "?")
        end
    end
    local lines = { string.format(Text.HELPER_REPORT_STATE, tostring(HelperOn()), tostring(wrackKnown),
        tostring(TargetOk()), tostring(Game.InCombat()), tostring(nativeRequired), tostring(channelling),
        tostring(procActive.shadowTrance == true), tostring(BarHighlight.choice), #rotShown,
        tostring(rotationTicker ~= nil), string.format("%.2f", latency)) }
    for _, family in ipairs(families) do
        local left, spellKey, source = TimeLeft(family, native, now)
        lines[#lines + 1] = string.format(Text.HELPER_REPORT_DOT, family.key,
            left and string.format("%.2f", left) or "-", source or "-",
            string.format("%.2f", Core.AddLatency(Core.FlashLead(family.key, spellKey), latency)))
    end
    lines[#lines + 1] = string.format(Text.HELPER_REPORT_LAST, tostring(lastCast), tostring(TargetGuid()),
        table.concat(lit, " "))
    return lines
end

function BarHighlight.HelperOn() return HelperOn() end

table.insert(ns.onSphere, function()
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "ADDON_RESTRICTION_STATE_CHANGED",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
        "UPDATE_BONUS_ACTIONBAR" }) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({ "UNIT_AURA", "UNIT_FLAGS", "UNIT_FACTION", "UNIT_HEALTH", "UNIT_COMBAT" }) do
        events:RegisterUnitEvent(event, "target")
    end
    for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
        events:RegisterUnitEvent(event, "player")
    end
    local alive
    events:SetScript("OnEvent", function(_, event, unit, second, spellID, _, school)
        if event == "UNIT_COMBAT" then
            if OnTargetCombat(second, school) then Refresh() end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            OnCast(spellID)
            RefreshRotation()
        elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            local wrack = type(spellID) == "number" and not IsSecret(spellID) and WRACK_IDS[spellID] == true
            local now = event == "UNIT_SPELLCAST_CHANNEL_START" and wrack
            if now ~= channelling and (wrack or not now) then
                channelling = now
                Refresh()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            immuneGuids = {}
            ReadTargetImmunity()
            Rebuild()
        elseif event == "PLAYER_TARGET_CHANGED" then
            local guid = TargetGuid()
            estimates.target = guid and estimates[guid] and Core.Copy(estimates[guid]) or nil
            alive = Plain(UnitIsDeadOrGhost, "target") == false
            ReadTargetImmunity()
            Refresh(true)
        elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
            C_Timer.After(0, function()
                UpdateReadability()
                Refresh(true)
            end)
        elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
            if event == "PLAYER_REGEN_ENABLED" then PruneEstimates() end
            if event == "PLAYER_REGEN_ENABLED" and BarHighlight.retry then
                Scan()
            else
                Refresh(true)
            end
        elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED"
            or event == "UPDATE_BONUS_ACTIONBAR" then
            ScanSoon()
        elseif event == "UNIT_HEALTH" then
            local now = Plain(UnitIsDeadOrGhost, "target") == false
            if now ~= alive then
                alive = now
                Refresh()
            end
        elseif event == "UNIT_AURA" then
            if not (Game.InCombat() or nativeRequired) then Refresh() end
        else
            Refresh()
        end
    end)
    table.insert(ns.onSpellsChanged, Rebuild)
    if ns.onDemoData then
        table.insert(ns.onDemoData, function(on)
            demoSet = nil
            if on then
                local step = 0
                ns.DemoEvery(Core.DEMO.missingStep, function()
                    local sets = Core.DEMO.missingSets
                    demoSet = sets[step % #sets + 1]
                    step = step + 1
                    Refresh()
                end)
            else
                Refresh(true)
            end
        end)
    end
    ns.ActionButtons.OnChange(ScanSoon)
    ns.OnSetting(Core.BAR_HIGHLIGHT_SETTINGS, Rebuild)
    Rebuild()
end)

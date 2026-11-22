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

local _, ns = ...
local Core, Game = ns.Core, ns.Game
local Plain, IsSecret = Game.Plain, Game.IsSecret

local BarHighlight = {}
ns.BarHighlight = BarHighlight

-- glow the next debuff to cast on action bar button
local FILTER = "HARMFUL|PLAYER"
local LAYOUT = "DisableUntrustedLayoutScriptsTemplate"
local BUTTONS_PER_BAR = 12
local FALLBACK_BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
    "MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

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
            if name then family.spells[1] = { name = name, ranks = Core.SPELLS[slot.keys[1]] } end
        else
            for _, key in ipairs(slot.keys) do
                for _, id in ipairs(Core.SPELLS[key]) do family.casts[id] = true end
                local name = Game.SpellName(Core.HighestKnown(Core.SPELLS[key], Knows))
                if name then family.spells[#family.spells + 1] = { name = name, ranks = Core.SPELLS[key] } end
            end
        end
        families[#families + 1] = family
    end
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

local function BarButtons()
    local names = ActionButtonUtil and ActionButtonUtil.ActionBarButtonNames or FALLBACK_BARS
    local buttons = {}
    for _, prefix in ipairs(names) do
        for i = 1, BUTTONS_PER_BAR do
            local button = _G[prefix .. i]
            if type(button) == "table" and button.GetName then buttons[#buttons + 1] = button end
        end
    end
    return buttons
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
local function NewGlow(button, place)
    local width, height = button:GetSize()
    local size = Core.BAR_GLOW_SIZE
    local clip = CreateFrame("Frame", nil, button, LAYOUT)
    clip:Hide()
    clip:EnableMouse(false)
    clip:SetClipsChildren(true)
    clip:SetSize(width * size, height * size)
    clip:SetPoint("CENTER", button, "CENTER", 0, 0)
    local start, widths = Core.BarGlowChain(place)
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
    return { button = button, place = place, clip = clip, chain = chain, alert = alert }
end

local function Play(glow)
    local loop = glow.alert.ProcLoop
    if loop and not loop:IsPlaying() then loop:Play() end
end

local function Place(glow, native)
    if glow.native == native then return end
    glow.alert:ClearAllPoints()
    if native then
        glow.alert:SetPoint("CENTER", glow.chain[#glow.chain], "TOPRIGHT", 0, 0)
    else
        glow.alert:SetPoint("CENTER", glow.clip, "CENTER", 0, 0)
    end
    glow.native = native
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
        local on = IsOn(family)
        if on == nil then return nil end
        if not on then return place end
    end
    return nil
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
    for _, glow in ipairs(procShown) do
        local on = procOn[glow.key] == true
        glow.alert:SetShown(on)
        if on then Play(glow) end
    end
end

-- proc glow for shadow bolt and soul fire, call from proc alert
function BarHighlight.SetProcs(state)
    procOn = {}
    for key in pairs(PROC_SPELLS) do procOn[key] = state[key] == true or nil end
    RefreshProcs()
end

local function Refresh(resync)
    local target = ns.db.timers.barHighlight.on ~= false and Plain(UnitCanAttack, "player", "target") == true
        and Plain(UnitIsDeadOrGhost, "target") == false
    local native = Game.InCombat() or nativeRequired
    local nextPlace = target and not native and NextPlace() or nil
    for _, glow in ipairs(shown) do
        if not target then
            Stop(glow)
        elseif native then
            Place(glow, true)
            if not glow.watching or resync then Watch(glow, true) end
            glow.alert:Show()
            glow.clip:Show()
            Play(glow)
        else
            if glow.watching then Watch(glow, false) end
            Place(glow, false)
            local on = glow.place == nextPlace
            glow.alert:SetShown(on)
            glow.clip:SetShown(on)
            if on then Play(glow) end
        end
    end
end

local function Scan()
    scanPending = false
    local wanted, missed, procWanted = {}, false, {}
    for _, button in ipairs(BarButtons()) do
        local spell = ActionSpell(button.action)
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
    RefreshProcs()
    BarHighlight.retry = missed
    Refresh(true)
end

local function ScanSoon()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0, Scan)
end

local function Rebuild()
    ReadFamilies()
    UpdateReadability()
    Scan()
end

function BarHighlight.Shown() return shown end
function BarHighlight.ProcShown() return procShown end

table.insert(ns.onSphere, function()
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "ADDON_RESTRICTION_STATE_CHANGED",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
        "UPDATE_BONUS_ACTIONBAR" }) do
        events:RegisterEvent(event)
    end
    for _, event in ipairs({ "UNIT_AURA", "UNIT_FLAGS", "UNIT_FACTION", "UNIT_HEALTH" }) do
        events:RegisterUnitEvent(event, "target")
    end
    local alive
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            Rebuild()
        elseif event == "PLAYER_TARGET_CHANGED" then
            alive = Plain(UnitIsDeadOrGhost, "target") == false
            Refresh(true)
        elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
            C_Timer.After(0, function()
                UpdateReadability()
                Refresh(true)
            end)
        elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
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
    ns.OnSetting(Core.BAR_HIGHLIGHT_SETTINGS, Rebuild)
    Rebuild()
end)

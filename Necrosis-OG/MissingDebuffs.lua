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
local known, byUnit, byBase = {}, {}, {}
local filter = "HARMFUL|PLAYER"
local nativeRequired = false
local demoSet
local TARGET_SIZE, PLATE_SIZE = 18, 14

local function Knows(id) return Game.Plain(C_SpellBook.IsSpellKnown, id) == true end

local function KnowsFamily(id) return Knows(id) or Game.Plain(IsPlayerSpell, id) == true end

-- collect the debuff which warlock know, by slot order
local function ReadSpellbook()
    known = {}
    local off = ns.db.timers.trackOff
    for _, slot in ipairs(Core.OrderEnemySlots(ns.db.timers.trackOrder)) do
        local family = { key = slot.key, ids = Core.SpellIdSet(slot.keys) }
        for _, key in ipairs(off[slot.key] and {} or slot.keys) do
            local ranks, id = Core.SPELLS[key], nil
            if slot.talent then
                if KnowsFamily(slot.talent) then id = ranks[1] end
            else
                id = Core.HighestKnown(ranks, Knows)
            end
            local name = Game.SpellName(id)
            local texture = id and Game.Plain(C_Spell.GetSpellTexture, id)
            if name and texture then
                family[#family + 1] = { key = key, name = name, texture = texture, ranks = ranks }
            end
        end
        if #family > 0 then known[#known + 1] = family end
    end
end

-- check which aura can read in this client
local function UpdateReadability()
    local restricted = C_Secrets and Game.Plain(C_Secrets.ShouldAurasBeSecret) ~= false
    nativeRequired = restricted or false
    for _, family in ipairs(known) do
        for _, spell in ipairs(family) do
            spell.readable = not restricted
            if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
                spell.readable = true
                for _, id in ipairs(spell.ranks) do
                    if Game.Plain(C_Secrets.ShouldSpellAuraBeSecret, id) ~= false then
                        nativeRequired = true
                        spell.readable = false
                        break
                    end
                end
            end
        end
    end
end

-- icon of the debuff unit not have, else nil
local function MissingTexture(unit, family)
    local texture = family[1].texture
    local last = ns.db.timers.lastInSlot[family.key]
    for _, spell in ipairs(family) do
        if not spell.readable then return nil end
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spell.name, filter)
        if not ok or Game.IsSecret(aura) or aura ~= nil then return nil end
        if spell.key == last then texture = spell.texture end
    end
    return texture
end

local layoutTemplate = "DisableUntrustedLayoutScriptsTemplate"

local function NewContainer(cell, family, width, anchor, grow)
    local container = CreateFrame("AuraContainer", nil, cell, "CustomAuraContainerTemplate," .. layoutTemplate)
    container:SetEnabled(false)
    container:EnableMouse(false)
    container:SetAlpha(0)
    container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
    container:SetFlowLayoutAnchorPoint(anchor)
    container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection[grow], AnchorUtil.FlowDirection.Down)
    container:SetFlowLayoutPadding(0, 0, 0, 0)
    container:SetFlowLayoutMaximumLineSize(width + 1)
    container:AddAuraGroup(family.key, filter, {
        maxFrameCount = 1, candidateFilters = { includeSpellIDs = family.ids },
        layout = { elementWidth = width, elementHeight = 1, elementSpacing = 0, lineSpacing = 0 },
        initializeFrame = function(button)
            button:SetSize(1, 1)
            button:EnableMouse(false)
        end,
    })
    return container
end

local function CreateNativeCell(strip, family)
    local step = strip.size + 2
    local cell = CreateFrame("Frame", nil, strip, layoutTemplate)
    cell:Hide()
    cell:SetSize(strip.size, strip.size)
    cell:EnableMouse(false)
    local container = NewContainer(cell, family, step, "TOPRIGHT", "Left")
    container:SetPoint("TOPRIGHT", cell, "TOPLEFT", step, 0)
    cell.half = NewContainer(cell, family, step / 2, "TOPLEFT", "Right")
    local clip = CreateFrame("Frame", nil, cell, layoutTemplate)
    clip:EnableMouse(false)
    clip:SetClipsChildren(true)
    clip:SetSize(step, strip.size)
    clip:SetPoint("TOPRIGHT", container, "TOPLEFT", -1, 0)
    cell.icon = clip:CreateTexture(nil, "ARTWORK")
    cell.icon:SetAllPoints(cell)
    cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    cell.icon:SetAlpha(strip.alpha)
    cell.container, cell.family = container, family.key
    return cell
end

local function StopCell(cell)
    cell:Hide()
    cell.container:SetEnabled(false)
    cell.half:SetEnabled(false)
    cell.active = false
end

local function Hang(frame, key, point, to, toPoint, x)
    local mark = frame[key]
    if mark and mark.to == to and mark.x == x then return end
    frame:ClearAllPoints()
    frame:SetPoint(point, to, toPoint, x, 0)
    frame[key] = { to = to, x = x }
end

-- put the cells in one row, centre
local function ChainCells(strip, chain)
    local step = strip.size + 2
    local start = (#Core.ENEMY_SLOTS - #chain) * step / 2
    for i, cell in ipairs(chain) do
        cell.slot = i
        local before = chain[i - 1]
        if before then
            Hang(cell.half, "hung", "TOPLEFT", before.half, "TOPRIGHT", 0)
        else
            Hang(cell.half, "hung", "TOPLEFT", strip, "TOPLEFT", start)
        end
    end
    for i, cell in ipairs(chain) do
        local before = chain[i - 1]
        if before then
            Hang(cell, "hung", "TOPLEFT", before.container, "TOPLEFT", 0)
        else
            Hang(cell, "hung", "TOPLEFT", chain[#chain].half, "TOPRIGHT", 0)
        end
    end
end

local function PlaceIcons(strip, textures, keys)
    local step = strip.size + 2
    local start = (#Core.ENEMY_SLOTS - #textures) * step / 2
    for i, icon in ipairs(strip.icons) do
        if textures[i] then
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", strip, "LEFT", start + (i - 1) * step, 0)
            icon:SetTexture(textures[i])
            icon.family = keys and keys[i]
            icon:Show()
        else
            icon.family = nil
            icon:Hide()
        end
    end
end

local function RefreshDemo(strip)
    local textures = {}
    if strip.enabled then
        local families = Core.EnemySlotsKnown(KnowsFamily, true, ns.db.timers.trackOff, ns.db.timers.trackOrder)
        for _, index in ipairs(demoSet) do
            local family = families[index]
            if family then
                textures[#textures + 1] = Game.Plain(C_Spell.GetSpellTexture, Core.SPELLS[family.keys[1]][1])
            end
        end
    end
    for _, cell in pairs(strip.cells) do
        if cell and cell.active then StopCell(cell) end
    end
    PlaceIcons(strip, textures)
    strip:SetShown(#textures > 0 or (strip.enabled and strip.placing == true))
end

-- show missing debuff icon for one unit
local function Refresh(unit, resync)
    local strip = byUnit[unit]
    if not strip then return end
    if demoSet then return RefreshDemo(strip) end
    strip.alive = Game.Plain(UnitIsDeadOrGhost, unit) == false
    local enemy = strip.enabled and strip.alive and Game.Plain(UnitCanAttack, "player", unit) == true
        and Game.Plain(UnitAffectingCombat, unit) == true
    local combat = Game.InCombat()
    local native = enemy and (combat or nativeRequired)
    local chain, textures, keys = {}, {}, {}
    for _, family in ipairs(known) do
        local cell = strip.cells[family.key]
        if cell == nil and (enemy or not combat) then
            local ok, frame = pcall(CreateNativeCell, strip, family)
            cell = ok and frame or false
            strip.cells[family.key] = cell
        end
        if native and cell then
            local texture = family[1].texture
            for _, spell in ipairs(family) do
                if spell.key == ns.db.timers.lastInSlot[family.key] then texture = spell.texture end
            end
            cell.icon:SetTexture(texture)
            if cell.unit ~= unit or not cell.active or resync then
                for _, container in ipairs({ cell.container, cell.half }) do
                    container:SetUnit(unit)
                    container:SetEnabled(true)
                end
                cell:Show()
                cell.container:UpdateAllAuras()
                cell.half:UpdateAllAuras()
                cell.unit, cell.active = unit, true
            end
            cell.wanted = true
            chain[#chain + 1] = cell
        elseif enemy and not native then
            textures[#textures + 1] = MissingTexture(unit, family)
            keys[#textures] = family.key
        end
    end
    if #chain > 0 then ChainCells(strip, chain) end
    PlaceIcons(strip, textures, keys)
    local shown = #textures > 0
    for _, cell in pairs(strip.cells) do
        if cell and cell.wanted then
            shown = true
            cell.wanted = nil
        elseif cell and cell.active then
            StopCell(cell)
        end
    end
    strip:SetShown(shown or (strip.enabled and strip.placing == true))
end

local function NewStrip(parent, size)
    local strip = CreateFrame("Frame", nil, parent)
    strip:EnableMouse(false)
    strip:SetSize(#Core.ENEMY_SLOTS * (size + 2) - 2, size)
    strip.size, strip.cells, strip.icons = size, {}, {}
    strip.flashing = {}
    strip.alpha, strip.scale, strip.enabled = 0.5, 1, true
    for i = 1, #Core.ENEMY_SLOTS do
        local icon = strip:CreateTexture(nil, "ARTWORK")
        icon:SetSize(size, size)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetAlpha(strip.alpha)
        icon:Hide()
        strip.icons[i] = icon
    end
    strip:Hide()
    return strip
end

local function Look(strip)
    return strip == byUnit.target and ns.db.timers.targetReminder or ns.db.timers.plateReminder
end

local function PositionTarget()
    local strip, look, default = byUnit.target, ns.db.timers.targetReminder, Core.DEFAULTS.timers.targetReminder
    strip:ClearAllPoints()
    strip:SetPoint("CENTER", UIParent, "CENTER", Core.ClampTargetOffset(look.x, default.x) / strip.scale,
        Core.ClampTargetOffset(look.y, default.y) / strip.scale)
end

local function PositionPlate(strip, base)
    local look = ns.db.timers.plateReminder
    strip:ClearAllPoints()
    strip:SetPoint("CENTER", base, "BOTTOM", Core.ClampPlateOffset(look.x) / strip.scale,
        Core.ClampPlateOffset(look.y, Core.DEFAULTS.timers.plateReminder.y) / strip.scale)
end

local function ApplyLook(strip, base)
    local look = Look(strip)
    strip.enabled = look.on ~= false
    strip.scale = Core.ClampScale(look.scale) / 100
    strip:SetScale(strip.scale)
    strip.alpha = Core.ClampOpacity(look.opacity) / 100
    for _, icon in ipairs(strip.icons) do icon:SetAlpha(strip.alpha) end
    for _, cell in pairs(strip.cells) do
        if cell then cell.icon:SetAlpha(strip.alpha) end
    end
    if strip == byUnit.target then
        PositionTarget()
    elseif base then
        PositionPlate(strip, base)
    end
end

local function StopDrag(strip)
    if not strip.dragging then return end
    strip:StopMovingOrSizing()
    strip.dragging = false
    local x, y = strip:GetCenter()
    local cx, cy = UIParent:GetCenter()
    if not (Core.IsNumber(x) and Core.IsNumber(y) and Core.IsNumber(cx) and Core.IsNumber(cy)) then return end
    local look = ns.db.timers.targetReminder
    look.x = Core.ClampTargetOffset(math.floor(x * strip.scale - cx + 0.5))
    look.y = Core.ClampTargetOffset(math.floor(y * strip.scale - cy + 0.5))
    PositionTarget()
end

local function UpdatePlacement()
    local strip = byUnit.target
    strip.placing = ns.placing and not Game.InCombat()
    if not strip.placing then StopDrag(strip) end
    local shown = strip.placing and strip.enabled
    strip:EnableMouse(shown)
    strip.title:SetShown(shown)
    strip.shade:SetShown(shown)
    strip.handle:SetShown(shown)
    strip.handle:EnableMouse(shown)
    Refresh("target")
end

-- strip for the target frame
local function CreateTarget()
    local strip = NewStrip(UIParent, TARGET_SIZE)
    byUnit.target = strip
    strip:SetFrameStrata("MEDIUM")
    strip:SetMovable(true)
    strip:SetClampedToScreen(true)
    strip:RegisterForDrag("LeftButton")
    local function StartDrag()
        if strip.placing then
            strip:StartMoving()
            strip.dragging = true
        end
    end
    local function EndDrag() StopDrag(strip) end
    strip:SetScript("OnDragStart", StartDrag)
    strip:SetScript("OnDragStop", EndDrag)
    strip.shade = strip:CreateTexture(nil, "BACKGROUND")
    strip.shade:SetAllPoints()
    strip.shade:SetColorTexture(0.45, 0.15, 0.55, 0.35)
    strip.title = strip:CreateFontString(nil, "OVERLAY", ns.Media.Font("GameFontNormalSmall", Core.DRAG_LABEL_SIZE, true))
    strip.title:SetText(ns.Text.MISSING_TARGET_DEBUFFS)
    strip.title:SetPoint("BOTTOM", strip, "TOP", 0, 2)
    strip.handle = CreateFrame("Frame", nil, strip)
    strip.handle:SetPoint("TOPLEFT", strip.title, "TOPLEFT", -4, 2)
    strip.handle:SetPoint("BOTTOMRIGHT", strip.title, "BOTTOMRIGHT", 4, -2)
    strip.handle:RegisterForDrag("LeftButton")
    strip.handle:SetScript("OnDragStart", StartDrag)
    strip.handle:SetScript("OnDragStop", EndDrag)
    strip.handle:EnableMouse(false)
    strip.handle:Hide()
    ApplyLook(strip)
    UpdatePlacement()
    table.insert(ns.onPlacing, UpdatePlacement)
    table.insert(ns.onRecall, function()
        local defaults = Core.DEFAULTS.timers
        local target, plate = ns.db.timers.targetReminder, ns.db.timers.plateReminder
        target.x, target.y = defaults.targetReminder.x, defaults.targetReminder.y
        PositionTarget()
        plate.x, plate.y = defaults.plateReminder.x, defaults.plateReminder.y
        for _, other in pairs(byBase) do PositionPlate(other, other.base) end
    end)
end

local casts = {}

-- remember we cast it on this unit, for flash
local function Remember(unit, strip, key)
    strip.flashing[key] = true
    local guid = Game.Plain(UnitGUID, unit)
    if guid then
        casts[guid] = casts[guid] or {}
        casts[guid][key] = true
    end
end

local function Recall(unit, strip)
    strip.flashing = {}
    local guid = Game.Plain(UnitGUID, unit)
    for key in pairs(guid and casts[guid] or {}) do strip.flashing[key] = true end
end

-- player cast a debuff spell, flash it icon
local function OnCast(spellID)
    local key = Core.EnemySlotOfSpell(spellID)
    if not key and KnowsFamily(Core.DEMONIC_BRAND_TALENT) then
        local name = Game.SpellName(spellID)
        if name and name == Game.SpellName(Core.SEARING_PAIN) then
            key = Core.EnemySlotOfSpell(Core.SPELLS.demonicBrand[1])
        end
    end
    if not key then return end
    for unit, strip in pairs(byUnit) do
        if unit == "target" or Game.Plain(UnitIsUnit, unit, "target") == true then Remember(unit, strip, key) end
    end
end

local function Detach(unit)
    local strip = byUnit[unit]
    if strip then
        strip:Hide()
        for _, cell in pairs(strip.cells) do
            if cell and cell.active then StopCell(cell) end
        end
        strip.unit, byUnit[unit] = nil, nil
    end
end

local function AttachPlate(unit, base)
    Detach(unit)
    if not base or base:IsForbidden() then return end
    local strip = byBase[base]
    if not strip then
        strip = NewStrip(base, PLATE_SIZE)
        strip.base = base
        byBase[base] = strip
    elseif strip.unit then
        Detach(strip.unit)
    end
    strip.unit, byUnit[unit] = unit, strip
    Recall(unit, strip)
    ApplyLook(strip, base)
end

local function RefreshAll()
    UpdateReadability()
    for unit, strip in pairs(byUnit) do
        ApplyLook(strip, strip.base)
        if not Game.InCombat() then
            for key, cell in pairs(strip.cells) do
                if cell == false then strip.cells[key] = nil end
            end
        end
        Refresh(unit, true)
    end
end

local function SyncFrames()
    for unit in pairs(byUnit) do
        if unit ~= "target" then Detach(unit) end
    end
    for _, base in ipairs(C_NamePlate.GetNamePlates()) do
        if not base:IsForbidden() and base.GetUnit then
            local unit = Game.Plain(base.GetUnit, base)
            if Core.NameplateIndex(unit) then AttachPlate(unit, base) end
        end
    end
    RefreshAll()
end

table.insert(ns.onSphere, function()
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    CreateTarget()
    ReadSpellbook()
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED",
        "NAME_PLATE_UNIT_REMOVED", "UNIT_AURA", "UNIT_FLAGS", "UNIT_FACTION", "UNIT_HEALTH",
        "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
        events:RegisterEvent(event)
    end
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    local flasher = CreateFrame("Frame")
    flasher:SetScript("OnUpdate", function()
        local now = GetTime()
        for _, group in pairs(byUnit) do
            for i, icon in ipairs(group.icons) do
                local on = icon.family and group.flashing[icon.family]
                icon:SetAlpha(on and group.alpha * Core.FlashFactor(now, (i - 1) * Core.MISSING_FLASH_STEP) or group.alpha)
            end
            for _, cell in pairs(group.cells) do
                if cell and cell.slot then
                    local on = group.flashing[cell.family]
                    cell.icon:SetAlpha(on and group.alpha * Core.FlashFactor(now, (cell.slot - 1) * Core.MISSING_FLASH_STEP)
                        or group.alpha)
                end
            end
        end
    end)
    events:SetScript("OnEvent", function(_, event, unit, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            ReadSpellbook()
            SyncFrames()
        elseif event == "PLAYER_TARGET_CHANGED" then
            Recall("target", byUnit.target)
            Refresh("target", true)
        elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
            C_Timer.After(0, RefreshAll)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local spellID = select(2, ...)
            if unit == "player" and type(spellID) == "number" and not Game.IsSecret(spellID) then OnCast(spellID) end
        elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
            if event == "PLAYER_REGEN_ENABLED" then
                casts = {}
                for _, group in pairs(byUnit) do group.flashing = {} end
            end
            UpdatePlacement()
            RefreshAll()
        elseif not Game.IsSecret(unit) and type(unit) == "string" then
            if event == "NAME_PLATE_UNIT_REMOVED" then
                Detach(unit)
            elseif event == "NAME_PLATE_UNIT_ADDED" then
                AttachPlate(unit, Game.Plain(C_NamePlate.GetNamePlateForUnit, unit))
                Refresh(unit, true)
            elseif event == "UNIT_HEALTH" then
                local group = byUnit[unit]
                if group and group.alive ~= (Game.Plain(UnitIsDeadOrGhost, unit) == false) then Refresh(unit) end
            elseif byUnit[unit] then
                Refresh(unit)
                if event == "UNIT_AURA" or event == "UNIT_FLAGS" then
                    if unit == "target" then
                        local host = Game.Plain(C_NamePlate.GetNamePlateForUnit, "target")
                        local plate = byBase[host]
                        if plate and plate.unit then Refresh(plate.unit) end
                    elseif Game.Plain(UnitIsUnit, unit, "target") == true then
                        Refresh("target")
                    end
                end
            end
        end
    end)
    table.insert(ns.onSpellsChanged, function()
        ReadSpellbook()
        RefreshAll()
    end)
    table.insert(ns.onDemoData, function(on)
        demoSet = nil
        if on then
            local step = 0
            ns.DemoEvery(Core.DEMO.missingStep, function()
                local sets = Core.DEMO.missingSets
                demoSet = sets[step % #sets + 1]
                step = step + 1
                for unit in pairs(byUnit) do Refresh(unit) end
            end)
        end
        for unit in pairs(byUnit) do Refresh(unit, true) end
    end)
    ns.OnSetting(Core.MISSING_SETTINGS, function()
        ReadSpellbook()
        RefreshAll()
    end)
    SyncFrames()
end)

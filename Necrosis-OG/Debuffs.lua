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

-- your debuffs on enemies, focus icons and list of all targets
local _, ns = ...
local Core, Text = ns.Core, ns.Text

local Debuffs = {}
ns.Debuffs = Debuffs

local FILTER = "HARMFUL"
local CLICK_WINDOW = 5

local lists = {}
local plates = {}
local clickedAt = {}
local pending = false
local created = false
local nextSeq = 0
local earlyCasts = {}
local slotById = {}
local nextSlotId = 0
local debuffLengths = {}

local IsSecret, Plain, InCombat, SpellName = ns.Game.IsSecret, ns.Game.Plain, ns.Game.InCombat, ns.Game.SpellName

local function EnumValue(group, key, fallback)
    local t = type(group) == "table" and group[key]
    if t ~= nil then return t end
    return fallback
end

-- call method of game container, true if game take it
local function Call(object, method, ...)
    if not object or type(object[method]) ~= "function" then return false end
    return (pcall(object[method], object, ...))
end

local function Scale(key) return Core.TimerScale(ns.db.timers, key) / 100 end
local function GrowsDown(key) return ns.db.timers.grow[key] ~= "up" end
local function On(key) return ns.db.timers[key .. "On"] ~= false end
local function Now() return Plain(GetTime) or 0 end
local function IsKnown(spellID) return Plain(C_SpellBook.IsSpellKnown, spellID) == true end

-- spell the demon knows now
local function PetKnows(spellID) return Plain(C_SpellBook.IsSpellKnown, spellID, ns.PetBank()) == true end

local healthCurve, timeOptions

-- time text "7" under a minute, "1m" from a minute
local function TimeOptions()
    if timeOptions == nil then
        local options = {}
        local curve = ns.Durations.ColourCurve(Core.TimeFlashPoints())
        if curve then options.textColor = { curve = curve, property = ns.Durations.RemainingProperty() } end
        options.textFormatter = ns.Durations.Formatter("cooldown")
        timeOptions = next(options) and options or false
    end
    return timeOptions or nil
end

local function SetTime(button, time)
    local options = TimeOptions()
    if options and Call(button, "SetDurationText", time, options) then return end
    button:SetDurationText(time)
end

local ICON_STEP = Core.FOCUS_ICON + Core.FOCUS_ICON_GAP
local FOCUS_WIDTH = Core.FOCUS_MAX_PER_ROW * ICON_STEP - Core.FOCUS_ICON_GAP
local FOCUS_HEIGHT = Core.FOCUS_ROW_COUNT * ICON_STEP - Core.FOCUS_ICON_GAP

local function InsetFor(size) return Core.MENU_ICON_INSET * size / Core.MENU_ITEM_SIZE end
local RING_INSET = InsetFor(Core.FOCUS_ICON)

local function Inside(region, frame, inset)
    inset = inset or RING_INSET
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    region:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
end

-- cut texture round with mask
local function Mask(frame, texture, inset)
    Inside(texture, frame, inset)
    local mask = frame:CreateMaskTexture()
    mask:SetTexture(Core.UiTexture("Mask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
end

-- cut texture round and put grey ring over, return ring
local function Round(frame, texture, inset)
    Mask(frame, texture, inset)
    local ring = frame:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints()
    ring:SetTexture(Core.UiTexture("Ring-01"))
    return ring
end

local SQUARE_BORDER = 1
local SQUARE_TRIM = 0.08

local function Square(frame, texture)
    Inside(texture, frame, SQUARE_BORDER)
    texture:SetTexCoord(SQUARE_TRIM, 1 - SQUARE_TRIM, SQUARE_TRIM, 1 - SQUARE_TRIM)
    local border = frame:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0, 0, 0, 1)
    return border
end

-- one round icon with time, size in px
local function IconFace(frame, size, font, square)
    local inset = square and SQUARE_BORDER or InsetFor(size)
    frame:SetSize(size, size)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    if square then Square(frame, icon) else Round(frame, icon, inset) end
    local cooldown = ns.Durations.NewSwipe(frame, { optional = true, reverse = true, shape = square and "square" or "mask",
        place = function(swipe) Inside(swipe, frame, inset) end })
    local time = ns.Durations.NewTimeText(frame, cooldown, font)
    time:SetWordWrap(false)
    time:SetDrawLayer("OVERLAY", 7)
    return icon, cooldown, time
end

-- dress game aura frame as round icon
local function RoundIcon(button, size, font, square)
    local icon, cooldown, time = IconFace(button, size, font, square)
    button:SetIcon(icon)
    if cooldown then Call(button, "SetDurationCooldown", cooldown) end
    SetTime(button, time)
end

local FOCUS_FONT = ns.Durations.TimeFont(Core.FOCUS_TIME_SIZE)
local ENEMY_FONT = ns.Durations.TimeFont(Core.ENEMY_TIME_SIZE)

-- control on focus icon, 40 px
local function FocusIcon(button) RoundIcon(button, Core.FOCUS_ICON, FOCUS_FONT) end

-- icon of all targets list, 28 px, no click
local function EnemyIcon(button)
    RoundIcon(button, Core.MULTI_ICON, ENEMY_FONT, true)
    Call(button, "EnableMouse", false)
end

-- look alike of game aura frame for demo
local function DemoIcon(parent, size, font, square)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:SetFrameLevel(parent:GetFrameLevel() + 2)
    frame.icon, frame.cooldown, frame.time = IconFace(frame, size, font, square)
    frame.span = ns.Durations.New()
    frame.binding = ns.Durations.Text(frame.time, "cooldown", "")
    ns.Durations.ColourText(frame.binding, Core.TimeFlashPoints())
    frame:Hide()
    return frame
end

local function RunDemoIcon(frame, spellID, start, length)
    frame.icon:SetTexture(Plain(C_Spell.GetSpellTexture, spellID))
    if frame.cooldown then pcall(frame.cooldown.SetCooldown, frame.cooldown, start, length) end
    ns.Durations.Set(frame.span, start, length)
    ns.Durations.ShowText(frame.binding, frame.span)
    frame:Show()
end

local function StopDemoIcon(frame)
    if not frame then return end
    if frame.cooldown then pcall(frame.cooldown.SetCooldown, frame.cooldown, 0, 0) end
    ns.Durations.HideText(frame.binding, frame.time)
    frame:Hide()
end

local FOCUS_STYLE = "icon"
local ENEMY_STYLE = "icon"
local INITIALIZE = { focus = { icon = FocusIcon }, multi = { icon = EnemyIcon } }

-- aura container for unit
local function NewContainer(parent, unit, key, style, vertical, ids)
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok or not container then return nil end
    local axis = type(AnchorUtil) == "table" and AnchorUtil.FlowLayoutAxis or nil
    Call(container, "SetFlowLayoutAxis", EnumValue(axis, vertical and "Vertical" or "Horizontal", vertical and 1 or 0))
    Call(container, "SetUnit", unit)
    Call(container, "AddAuraGroup", key, FILTER, {
        initializeFrame = INITIALIZE[key][style],
        candidateFilters = { isFromPlayerOrPlayerPet = true, includeSpellIDs = ids },
        sortMethod = EnumValue(AuraContainerSortMethod, "ExpirationOnly", EnumValue(AuraContainerSortMethod, "Expiration", nil)),
        maxFrameCount = 1,
        layout = { elementSpacing = 2, lineSpacing = Core.TIMER_GAP },
    })
    Call(container, "SetEnabled", true)
    return container
end

local function PlaceContainer(container, parent, down, x)
    local flow = type(AnchorUtil) == "table" and AnchorUtil.FlowDirection or nil
    local corner = down and "TOPLEFT" or "BOTTOMLEFT"
    Call(container, "SetFlowLayoutAnchorPoint", corner)
    Call(container, "SetFlowLayoutGrowthDirection", EnumValue(flow, "Right", 1),
        EnumValue(flow, down and "Down" or "Up", down and -1 or 1))
    container:ClearAllPoints()
    container:SetPoint(corner, parent, corner, x or 0, 0)
end

local function ChooseStyle(containers, style)
    for name, container in pairs(containers) do
        local chosen = name == style
        Call(container, "SetEnabled", chosen)
        container:SetShown(chosen)
    end
end

-- flash of ended debuff
local function CreateBlink(texture, from, to)
    local blink = texture:CreateAnimationGroup()
    blink:SetLooping("BOUNCE")
    local fade = blink:CreateAnimation("Alpha")
    fade:SetFromAlpha(from or 1)
    fade:SetToAlpha(to or Core.FLASH_LOW)
    fade:SetDuration(Core.FLASH_SECONDS / 2)
    return blink
end

-- start or stop flash of row or slot
local function SetFlash(object, on, dimmed)
    if on then
        object.icon:SetAlpha(1)
        if not object.blink:IsPlaying() then object.blink:Play() end
    else
        object.blink:Stop()
        object.icon:SetAlpha(dimmed or 1)
    end
end

local function ApplyPlace(list)
    if list.guarded and InCombat() then
        pending = true
        return
    end
    local saved = ns.db.timers[list.key]
    list.frame:SetScale(Scale(list.key))
    list.frame:ClearAllPoints()
    list.frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
end

local function SavePlace(list)
    local left, bottom = list.frame:GetLeft(), list.frame:GetBottom()
    if type(left) ~= "number" or type(bottom) ~= "number" then return end
    local saved = ns.db.timers[list.key]
    saved.point, saved.relativePoint, saved.x, saved.y = "BOTTOMLEFT", "BOTTOMLEFT", left, bottom
    ApplyPlace(list)
end

local function CreateList(key, title, width, height, guarded)
    local list = { key = key, guarded = guarded }
    local frame = CreateFrame("Frame", "NecrosisOGTimers" .. key, UIParent)
    frame:SetSize(width, height)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    list.startDrag = function()
        if not ns.db.locked and not (guarded and InCombat()) then frame:StartMoving() end
    end
    list.stopDrag = function()
        frame:StopMovingOrSizing()
        SavePlace(list)
    end
    frame:SetScript("OnDragStart", list.startDrag)
    frame:SetScript("OnDragStop", list.stopDrag)
    frame.shade = frame:CreateTexture(nil, "BACKGROUND")
    frame.shade:SetAllPoints()
    frame.shade:SetColorTexture(0.3, 0.1, 0.4, 0.6)
    frame.title = frame:CreateFontString(nil, "OVERLAY", ns.Media.Font("GameFontNormalSmall"))
    frame.title:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.title:SetText(title)
    list.frame = frame
    lists[key] = list
    ApplyPlace(list)
    return list
end

local FOCUS_STATE = "[@focus,exists,harm,nodead] valid; none"

local DEMO_FOCUS_STATE = "[@focus,exists,harm,nodead] valid; [combat] none; valid"
local FOCUS_SNIPPET = [[
    if newstate == "valid" then self:Show() else self:Hide() end
]]

-- spell tooltip then the click
local function IconTooltip(item)
    return function(tooltip)
        if not item.spell then return false end
        tooltip:SetSpellByID(item.spell)
        ns.Tips.Click(tooltip, "any", Text.ACT_CAST_ON_FOCUS)
    end
end

local function NewFocusIcon(header, def)
    local item = { def = def, containers = {} }
    local frame = CreateFrame("Frame", nil, header)
    frame:SetSize(Core.FOCUS_ICON, Core.FOCUS_ICON)
    item.frame = frame
    item.icon = frame:CreateTexture(nil, "ARTWORK")
    item.ring = Round(frame, item.icon)
    item.icon:SetAlpha(Core.FOCUS_DIM)
    item.blink = CreateBlink(item.icon)
    item.containers[FOCUS_STYLE] = NewContainer(frame, "focus", "focus", FOCUS_STYLE, true, Core.FocusIconIds(def))
    local cover = CreateFrame("Frame", nil, frame)
    cover:SetAllPoints(frame)
    cover:SetFrameLevel(frame:GetFrameLevel() + 8)
    item.range = cover:CreateTexture(nil, "OVERLAY")
    item.range:SetColorTexture(1, 0, 0)
    Mask(cover, item.range)
    item.range:SetAlpha(0)
    local click = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
    click:SetAllPoints(frame)
    click:SetFrameLevel(frame:GetFrameLevel() + 10)
    click:RegisterForClicks("AnyUp")
    click:SetAttribute("useOnKeyDown", false)
    click:SetAttribute("type1", "spell")
    click:SetAttribute("unit1", "focus")
    click:SetScript("PreClick", function() clickedAt[def.key] = Now() end)
    ns.Tips.Attach(click, IconTooltip(item), "ANCHOR_RIGHT")
    ns.Rings.Attach(click, click, def.spell, { icon = false })
    item.click = click
    return item
end

local function FocusItem(key)
    local list = lists.focus
    for _, row in ipairs(list and list.items or {}) do
        if row.def.key == key then return row end
    end
    return nil
end

-- creature type of focus, nil if none or hidden
local function FocusTypeID()
    if Plain(UnitExists, "focus") ~= true then return nil end
    local ok, _, typeID = pcall(UnitCreatureType, "focus")
    if not ok or IsSecret(typeID) or type(typeID) ~= "number" then return nil end
    return typeID
end

-- layout focus icons of known spells
local function ArrangeFocus()
    local list = lists.focus
    if not list then return end
    if InCombat() then
        pending = true
        return
    end
    ApplyPlace(list)
    local driver = ns.demo == true and DEMO_FOCUS_STATE or FOCUS_STATE
    if list.driver ~= driver then
        list.driver = driver
        RegisterStateDriver(list.header, "focus", driver)
    end
    list.header:ClearAllPoints()
    list.header:SetPoint("TOPLEFT", list.frame, "TOPLEFT", 0, 0)
    local everything = ns.demo == true
    local typeID, shown = not everything and FocusTypeID() or nil, {}
    for _, item in ipairs(list.items) do
        local def = item.def
        local id = Core.FocusIconSpell(def, def.pet and PetKnows or IsKnown, everything)
        item.spell = id
        shown[def.key] = On("focus") and Core.FocusIconOn(def.key, ns.db.timers.focusOff) and id ~= nil
            and (typeID == nil or Core.FocusIconFits(def.key, typeID)) or nil
    end
    local places = Core.FocusLayout(shown)
    for _, item in ipairs(list.items) do
        local place = places[item.def.key]
        if place then
            item.frame:ClearAllPoints()
            item.frame:SetPoint("TOPLEFT", list.header, "TOPLEFT", place.col * ICON_STEP, -place.row * ICON_STEP)
            item.frame:SetAlpha(1)
            item.icon:SetTexture(Plain(C_Spell.GetSpellTexture, item.spell))
            local cast = item.spell
            if item.def.pet then cast = SpellName(item.spell) or item.spell end
            item.click:SetAttribute("spell1", cast)
            for _, container in pairs(item.containers) do PlaceContainer(container, item.frame, true, 0) end
            ChooseStyle(item.containers, FOCUS_STYLE)
            SetFlash(item, item.casted == true, Core.FOCUS_DIM)
            item.frame:Show()
        else
            item.frame:Hide()
        end
    end
    list.header:SetSize(FOCUS_WIDTH, FOCUS_HEIGHT)
end

local function UpdateFocusFit()
    local list = lists.focus
    if not list or not list.items then return end
    local typeID = ns.demo ~= true and FocusTypeID() or nil
    for _, item in ipairs(list.items) do
        local fits = typeID == nil or Core.FocusIconFits(item.def.key, typeID)
        item.frame:SetAlpha(fits and 1 or 0.3)
    end
end

local function UpdateFocus()
    local list = lists.focus
    if not list then return end
    if InCombat() then
        pending = true
        return
    end
    local placing = ns.placing
    list.frame.shade:SetShown(placing)
    list.frame.title:SetShown(placing)
    list.frame:EnableMouse(placing and not ns.db.locked)
    list.frame:SetShown(placing or On("focus"))
end

-- red cover when spell can not reach focus
local function UpdateFocusRange()
    local list = lists.focus
    if not list or not list.items then return end
    local alpha = Core.FOCUS_RANGE_ALPHA
    if ns.demoData then
        for _, item in ipairs(list.items) do
            item.range:SetAlpha(item.def.key == Core.DEMO.focusOutOfRange and alpha or 0)
        end
        return
    end
    for _, item in ipairs(list.items) do
        local ok, inRange = false, nil
        if item.spell and not item.def.pet and type(C_Spell) == "table" and type(C_Spell.IsSpellInRange) == "function" then
            ok, inRange = pcall(C_Spell.IsSpellInRange, item.spell, "focus")
        end
        if ok and IsSecret(inRange) then
            if not pcall(item.range.SetAlphaFromBoolean, item.range, inRange, 0, alpha) then item.range:SetAlpha(0) end
        else
            item.range:SetAlpha(ok and inRange == false and alpha or 0)
        end
    end
end

local rangeTicker

local function WatchFocusRange()
    local wanted = lists.focus ~= nil and On("focus") and Plain(UnitExists, "focus") == true
    if wanted and not rangeTicker and C_Timer and C_Timer.NewTicker then
        rangeTicker = C_Timer.NewTicker(Core.FOCUS_RANGE_SECONDS, UpdateFocusRange)
    elseif not wanted and rangeTicker then
        rangeTicker:Cancel()
        rangeTicker = nil
    end
    UpdateFocusRange()
end

local function RefreshFocusAuras()
    local list = lists.focus
    if not list then return end
    for _, item in ipairs(list.items) do
        for _, container in pairs(item.containers) do Call(container, "UpdateAllAuras") end
    end
end

local function MultiWidth() return Core.MULTI_WIDTH end

-- one enemy block, two rows
local function NewLine(list)
    local line = CreateFrame("Frame", nil, list.frame)
    line:SetSize(Core.MULTI_WIDTH, Core.MULTI_BLOCK)
    line.backdrop = line:CreateTexture(nil, "BACKGROUND", nil, 0)
    line.backdrop:SetAllPoints()
    line.backdrop:SetColorTexture(unpack(Core.ROW_BACKDROP))
    line.tint = line:CreateTexture(nil, "BACKGROUND", nil, 1)
    line.tint:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
    line.tint:SetSize(Core.MULTI_WIDTH, Core.MULTI_HEAD)
    line.tint:SetColorTexture(unpack(Core.ROW_TARGET_TINT))
    line.tint:Hide()
    line.portrait = line:CreateTexture(nil, "ARTWORK")
    line.portrait:SetSize(Core.MULTI_HEAD, Core.MULTI_HEAD)
    line.portrait:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
    local mask = line:CreateMaskTexture()
    mask:SetTexture(Core.UiTexture("Mask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(line.portrait)
    line.portrait:AddMaskTexture(mask)
    line.mark = line:CreateFontString(nil, "OVERLAY", ns.Media.Font("GameFontNormalSmall"))
    line.mark:SetText(Text.MULTI_TARGET_MARK)
    line.mark:SetPoint("RIGHT", line.portrait, "LEFT", -1, 0)
    local barWidth = Core.MULTI_WIDTH - Core.MULTI_HEAD - 2 - Core.MULTI_THREAT_ICON - 3 - Core.MULTI_THREAT_WIDTH
    line.bar = CreateFrame("StatusBar", nil, line)
    line.bar:SetSize(barWidth, Core.MULTI_HEALTH_BAR)
    line.bar:SetPoint("LEFT", line.portrait, "RIGHT", 2, 0)
    line.barFill = ns.Media.DressBar(line.bar:CreateTexture(nil, "ARTWORK"))
    line.bar:SetStatusBarTexture(line.barFill)
    line.bar:SetMinMaxValues(0, 100)
    line.bar:SetValue(100)
    line.barBack = line.bar:CreateTexture(nil, "BACKGROUND")
    line.barBack:SetAllPoints()
    line.barBack:SetColorTexture(0, 0, 0, 0.5)
    line.name = line.bar:CreateFontString(nil, "OVERLAY", ns.Media.Font("GameFontHighlightSmall", nil, true))
    line.name:SetPoint("LEFT", line.bar, "LEFT", 3, 0)
    line.name:SetSize(barWidth - Core.MULTI_HEALTH_WIDTH - 4, Core.MULTI_HEALTH_BAR)
    line.name:SetJustifyH("LEFT")
    line.name:SetWordWrap(false)
    line.health = line.bar:CreateFontString(nil, "OVERLAY", ns.Media.Font("GameFontHighlightSmall", nil, true))
    line.health:SetPoint("RIGHT", line.bar, "RIGHT", -3, 0)
    line.health:SetSize(Core.MULTI_HEALTH_WIDTH, Core.MULTI_HEALTH_BAR)
    line.health:SetJustifyH("RIGHT")
    line.health:SetWordWrap(false)
    line.threat = line:CreateFontString(nil, "OVERLAY", ns.Media.Font("GameFontHighlightSmall", nil, true))
    line.threat:SetPoint("TOPRIGHT", line, "TOPRIGHT", 0, 0)
    line.threat:SetSize(Core.MULTI_THREAT_WIDTH, Core.MULTI_HEAD)
    line.threat:SetJustifyH("RIGHT")
    line.threat:SetWordWrap(false)
    line.threatIcon = line:CreateTexture(nil, "ARTWORK")
    line.threatIcon:SetSize(Core.MULTI_THREAT_ICON, Core.MULTI_THREAT_ICON)
    line.threatIcon:SetPoint("RIGHT", line.threat, "LEFT", -1, 0)
    line.threatIcon:SetTexture(Core.THREAT_ICON)
    local threatMask = line:CreateMaskTexture()
    threatMask:SetTexture(Core.UiTexture("Mask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    threatMask:SetAllPoints(line.threatIcon)
    line.threatIcon:AddMaskTexture(threatMask)
    line.cover = CreateFrame("Frame", nil, line)
    line.cover:SetAllPoints()
    line.cover:SetFrameLevel(line:GetFrameLevel() + 20)
    line.slots = {}
    for _, def in ipairs(Core.ENEMY_SLOTS) do
        local frame = CreateFrame("Frame", nil, line)
        frame:SetSize(Core.MULTI_ICON, Core.MULTI_ICON)
        local icon = frame:CreateTexture(nil, "ARTWORK")
        local ring = Square(frame, icon)
        local warn = line.cover:CreateTexture(nil, "OVERLAY")
        warn:SetColorTexture(0, 0, 0, 1)
        Inside(warn, frame, SQUARE_BORDER)
        warn:Hide()
        frame:Hide()
        nextSlotId = nextSlotId + 1
        local slot = { def = def, ids = Core.SpellIdSet(def.keys), containers = {}, frame = frame, icon = icon,
            ring = ring, blink = CreateBlink(icon), cast = false, column = false,
            id = nextSlotId, warn = warn, warnBlink = CreateBlink(warn, 0, 1 - Core.FLASH_LOW) }
        slotById[slot.id] = slot
        line.slots[#line.slots + 1] = slot
    end
    line:Hide()
    return line
end

-- picture of family when none debuff cast
local function SlotTexture(slot)
    local last = ns.db.timers.lastInSlot and ns.db.timers.lastInSlot[slot.def.key]
    local spell = last and Core.SPELLS[last] and Core.HighestKnown(Core.SPELLS[last], IsKnown) or nil
    for _, key in ipairs(slot.def.keys) do
        spell = spell or Core.HighestKnown(Core.SPELLS[key], IsKnown)
    end
    if not spell and ns.demo == true then spell = Core.SPELLS[slot.def.keys[1]][1] end
    return spell and Plain(C_Spell.GetSpellTexture, spell) or nil
end

local function SlotOf(line, key)
    for _, slot in ipairs(line.slots) do
        if slot.def.key == key then return slot end
    end
    return nil
end

-- flash icon before debuff end
local function SetWarn(slot, on)
    if on then
        slot.warn:Show()
        if not slot.warnBlink:IsPlaying() then slot.warnBlink:Play() end
    else
        slot.warnBlink:Stop()
        slot.warn:Hide()
    end
end

local warnSchedule

local function UpdateWarn(id)
    local slot = slotById[id]
    if not slot then return end
    local now, endsAt = Now(), slot.endsAt
    if not endsAt or now >= endsAt then
        slot.endsAt = nil
        SetWarn(slot, false)
        warnSchedule.Cancel(id)
        return
    end
    local startAt = endsAt - Core.FLASH_LEAD_SECONDS
    SetWarn(slot, slot.column and now >= startAt)
    warnSchedule.At(id, now >= startAt and endsAt or startAt)
end

warnSchedule = ns.Durations.NewSchedule(UpdateWarn)

-- debuff length from spell description
local function DebuffLength(spellID)
    if debuffLengths[spellID] == nil then
        debuffLengths[spellID] = Core.ParseDebuffLength(Plain(C_Spell.GetSpellDescription, spellID))
    end
    return debuffLengths[spellID]
end

local function ResetCasts(line)
    for _, slot in ipairs(line.slots) do
        slot.cast = false
        slot.icon:SetTexture(SlotTexture(slot))
        SetFlash(slot, false, Core.FOCUS_DIM)
        slot.endsAt = nil
        UpdateWarn(slot.id)
    end
end

-- spell is cast on enemy of this line
local function MarkCast(line, slot, spellID, at, length)
    slot.cast = true
    local texture = Plain(C_Spell.GetSpellTexture, spellID)
    if texture then slot.icon:SetTexture(texture) end
    SetFlash(slot, true)
    length = length or DebuffLength(spellID)
    slot.endsAt = length and (at or Now()) + length or nil
    UpdateWarn(slot.id)
end

local function EachContainer(line, action)
    for _, slot in ipairs(line.slots) do
        for _, container in pairs(slot.containers) do action(container) end
    end
end

local function AllLines(multi)
    local all = {}
    for _, line in ipairs(multi.lines) do all[#all + 1] = line end
    for _, line in ipairs(multi.demoLines or {}) do all[#all + 1] = line end
    return all
end

local controlRows = {}

local function Stack()
    local multi = lists.multi
    if not multi then return end
    local down = GrowsDown("multi")
    local corner, edge = down and "TOPLEFT" or "BOTTOMLEFT", down and "BOTTOMLEFT" or "TOPLEFT"
    local ordered = {}
    for _, line in ipairs(AllLines(multi)) do
        if line.seq and line:IsShown() then ordered[#ordered + 1] = line end
    end
    table.sort(ordered, function(a, b) return a.seq < b.seq end)
    local controls = controlRows
    local target = multi.frame
    for _, row in ipairs(Core.RowChain(down, controls, ordered)) do
        if row.stackTarget ~= target or row.stackCorner ~= corner then
            row.stackTarget, row.stackCorner = target, corner
            row:ClearAllPoints()
            if target == multi.frame then
                row:SetPoint(corner, target, corner, 0, 0)
            else
                row:SetPoint(corner, target, edge, 0, down and -Core.TIMER_GAP or Core.TIMER_GAP)
            end
        end
        target = row
    end
end

local function DragsList(row, list, on)
    if not row.dragsList then
        row.dragsList = true
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", list.startDrag)
        row:SetScript("OnDragStop", list.stopDrag)
    end
    if row.dragOn ~= on then
        row.dragOn = on
        row:EnableMouse(on)
    end
end

-- stack rows, show list frame if it has row
local function Layout(rows)
    if rows then controlRows = rows end
    local multi = lists.multi
    if not multi then return end
    Stack()
    local count = 0
    for _, line in ipairs(AllLines(multi)) do if line:IsShown() and line.seq then count = count + 1 end end
    local controls = controlRows
    local placing = ns.placing
    multi.frame.shade:SetShown(placing)
    multi.frame.title:SetShown(placing and count + #controls == 0)
    local drag = placing and not ns.db.locked
    multi.frame:EnableMouse(drag)
    for _, line in ipairs(AllLines(multi)) do DragsList(line, multi, drag) end
    for _, row in ipairs(controls) do DragsList(row, multi, drag) end
    multi.frame:SetShown(placing or count + #controls > 0)
    return count
end

local function ArrangeMulti()
    local multi = lists.multi
    if not multi then return end
    local known = Core.EnemySlotsKnown(IsKnown, ns.demo == true, ns.db.timers.trackOff)
    local ordinal = {}
    for i, slot in ipairs(known) do ordinal[slot.key] = i end
    multi.columns = #known
    multi.width = MultiWidth()
    multi.frame:SetWidth(multi.width)
    local row2 = -(Core.MULTI_HEAD + Core.MULTI_ROW_GAP)
    for _, line in ipairs(AllLines(multi)) do
        line.stackTarget = nil
        for _, slot in ipairs(line.slots) do
            local n = ordinal[slot.def.key]
            slot.column = n ~= nil
            if n then
                slot.frame:ClearAllPoints()
                slot.frame:SetPoint("TOPLEFT", line, "TOPLEFT", (n - 1) * (Core.MULTI_ICON + Core.MULTI_ICON_GAP), row2)
                if not slot.containers[ENEMY_STYLE] and not line.demo then
                    slot.containers[ENEMY_STYLE] = NewContainer(slot.frame, line.unit or "player", "multi", ENEMY_STYLE,
                        true, slot.ids)
                end
                for _, container in pairs(slot.containers) do PlaceContainer(container, slot.frame, true, 0) end
                ChooseStyle(slot.containers, ENEMY_STYLE)
                if not slot.cast then slot.icon:SetTexture(SlotTexture(slot)) end
                SetFlash(slot, slot.cast, Core.FOCUS_DIM)
                slot.frame:Show()
            else
                for _, container in pairs(slot.containers) do
                    Call(container, "SetEnabled", false)
                    container:Hide()
                end
                SetFlash(slot, false, Core.FOCUS_DIM)
                slot.frame:Hide()
            end
            UpdateWarn(slot.id)
        end
    end
    if ns.Timers and ns.Timers.Update then ns.Timers.Update() end
    Layout()
end

-- apply style, direction, rows and size, out of combat only
local function Arrange()
    if InCombat() then
        pending = true
        return
    end
    pending = false
    ArrangeFocus()
    UpdateFocus()
    WatchFocusRange()
    ArrangeMulti()
end

-- enemies with nameplate, attackable and alive
local function Candidates()
    local candidates = {}
    for unit in pairs(plates) do
        local index = Core.NameplateIndex(unit)
        local attack = Plain(UnitCanAttack, "player", unit)
        local dead = Plain(UnitIsDead, unit)
        local okThreat, threat = pcall(UnitThreatSituation, "player", unit)
        local fighting = not okThreat or IsSecret(threat) or threat ~= nil
        if index and attack ~= false and dead ~= true and fighting then
            candidates[#candidates + 1] = { unit = unit, index = index,
                target = Plain(UnitIsUnit, unit, "target") == true }
        end
    end
    return Core.OrderNameplates(candidates)
end

local function WriteName(line, unit) line.name:SetText(Core.ShortName(UnitName(unit), Core.MULTI_NAME_CHARS)) end

local function SetName(line, unit)
    if not pcall(WriteName, line, unit) then line.name:SetText("") end
end

local function WriteHealth(line, unit, curve)
    local percent = UnitHealthPercent(unit, true, curve)
    line.health:SetFormattedText("%.0f%%", percent)
    line.bar:SetValue(percent)
end

local function WriteHealthColour(line, unit, curve)
    local colour = UnitHealthPercent(unit, true, curve)
    line.bar:SetStatusBarColor(colour:GetRGBA())
end

-- health bar length and text like "85%"
local function SetHealth(line, unit)
    local curve = CurveConstants and CurveConstants.ScaleTo100
    local shown = curve and pcall(WriteHealth, line, unit, curve)
    if not shown then
        line.health:SetText("")
        line.bar:SetValue(100)
    end
    healthCurve = healthCurve or ns.Durations.ColourCurve(Core.HEALTH_COLOUR_POINTS)
    local coloured = healthCurve and pcall(WriteHealthColour, line, unit, healthCurve)
    if not coloured then line.bar:SetStatusBarColor(0, 1, 0) end
end

local function WriteThreat(line, value)
    if value == nil then error("no threat") end
    line.threat:SetFormattedText("%.0f%%", value)
end

local function ShowThreat(line, value, state)
    local shown = pcall(WriteThreat, line, value)
    if not shown then line.threat:SetText("") end
    line.threatIcon:SetShown(shown)
    local r, g, b
    if shown and not IsSecret(value) then
        r, g, b = Core.ThreatColor(value)
    elseif shown then
        r, g, b = Core.ThreatStateColour(state)
    end
    line.threat:SetTextColor(r or 1, g or 1, b or 1)
end

-- your threat in percent
local function SetThreat(line, unit, isTarget)
    local who = isTarget and "target" or unit
    local ok, _, _, scaled = pcall(UnitDetailedThreatSituation, "player", who)
    if not ok then scaled = nil end
    ShowThreat(line, scaled, Plain(UnitThreatSituation, "player", who))
end

local function SetPortrait(line, unit, guid)
    local key = tostring(unit) .. ":" .. tostring(guid)
    if line.portraitFor == key then return end
    line.portraitFor = key
    if type(SetPortraitTexture) == "function" then pcall(SetPortraitTexture, line.portrait, unit) end
end

local function EndLine(line)
    line.frozenAt = nil
    line.seq = nil
    line.stackTarget = nil
    line.portraitFor = nil
    line:Hide()
    line:ClearAllPoints()
    ResetCasts(line)
end

local function ReleaseFrozen(lines, live)
    local now, on, frozen = Now(), On("multi"), 0
    for _, line in ipairs(lines) do
        if line.frozenAt and (not on or now - line.frozenAt >= Core.MULTI_FROZEN_SECONDS) then EndLine(line) end
        if line.frozenAt then frozen = frozen + 1 end
    end
    while frozen > 0 and live + frozen > #lines do
        local oldest
        for _, line in ipairs(lines) do
            if line.frozenAt and (not oldest or line.frozenAt < oldest.frozenAt) then oldest = line end
        end
        EndLine(oldest)
        frozen = frozen - 1
    end
    return frozen
end

local function AnyFrozen()
    local list = lists.multi
    if not list then return false end
    for _, line in ipairs(list.lines) do if line.frozenAt then return true end end
    return false
end

-- put line on nameplate unit
local function Bind(line, unit)
    if line.unit ~= unit then
        local moved = true
        EachContainer(line, function(container) moved = Call(container, "SetUnit", unit) and moved end)
        line.unit = moved and unit or nil
        ResetCasts(line)
    end
    return line.unit == unit
end

local function FreeLine(lines, unit)
    local free
    for _, line in ipairs(lines) do
        if not line.seq then
            if line.unit == unit then return line end
            free = free or line
        end
    end
    return free
end

local function LastLine(lines)
    local last
    for _, line in ipairs(lines) do
        if line.seq and not line.frozenAt and (not last or line.seq > last.seq) then last = line end
    end
    return last
end

-- show picture, name, health, threat of enemy on its line
local function Describe(line, candidate)
    SetName(line, candidate.unit)
    SetHealth(line, candidate.unit)
    SetThreat(line, candidate.unit, candidate.target)
    local guid = Plain(UnitGUID, candidate.unit)
    if guid and line.guid and guid ~= line.guid then ResetCasts(line) end
    line.guid = guid
    SetPortrait(line, candidate.unit, guid)
    line.portrait:SetDesaturated(false)
    line.bar:SetAlpha(1)
    line.health:SetTextColor(1, 1, 1)
    line.mark:SetShown(candidate.target)
    line.tint:SetShown(candidate.target)
    if candidate.target then line.name:SetTextColor(1, 0.82, 0) else line.name:SetTextColor(1, 1, 1) end
    line:Show()
end

local PLATE_SETTINGS = { "nameplateShowEnemies", "nameplateShowOffscreen" }
local plateSyncPending = false

local function SetGameSetting(name, value)
    if not (C_CVar and C_CVar.SetCVar) then return false end
    local ok, done = pcall(C_CVar.SetCVar, name, value)
    return ok and done ~= false
end

local function SyncNameplateSettings()
    if InCombat() then
        plateSyncPending = true
        return
    end
    plateSyncPending = false
    if not (C_CVar and C_CVar.GetCVar) then return end
    local changed = ns.db.timers.plateSettings
    if On("multi") then
        for _, name in ipairs(PLATE_SETTINGS) do
            local value = Plain(C_CVar.GetCVar, name)
            if value ~= nil and value ~= "1" and SetGameSetting(name, "1") then changed[name] = true end
        end
    else
        for name in pairs(changed) do
            if Plain(C_CVar.GetCVar, name) == "1" then SetGameSetting(name, "0") end
            changed[name] = nil
        end
    end
end

local WARNINGS = {
    { setting = "nameplateShowEnemies", text = "MULTI_WARN_ENEMY_PLATES" },
    { setting = "nameplateShowOffscreen", text = "MULTI_WARN_OFFSCREEN_PLATES" },
}
local WARNING_HEIGHT = 12

local function CreateWarnings(list)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame.lines = {}
    for i, warning in ipairs(WARNINGS) do
        local line = frame:CreateFontString(nil, "OVERLAY", ns.Media.Font("GameFontNormalSmall"))
        line:SetText(Text[warning.text])
        line:SetTextColor(1, 0.35, 0.2)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        line:Hide()
        frame.lines[i] = line
    end
    frame:Hide()
    list.warnings = frame
end

local function UpdateWarnings(fighting)
    local list = lists.multi
    local frame = list and list.warnings
    if not frame then return end
    local off = {}
    if fighting and On("multi") and C_CVar and C_CVar.GetCVar then
        for i, warning in ipairs(WARNINGS) do
            if Plain(C_CVar.GetCVar, warning.setting) == "0" then off[#off + 1] = frame.lines[i] end
        end
    end
    for _, line in ipairs(frame.lines) do line:Hide() end
    frame:SetScale(Scale("multi"))
    frame:SetSize(MultiWidth(), math.max(1, #off) * WARNING_HEIGHT)
    frame:ClearAllPoints()
    if GrowsDown("multi") then
        frame:SetPoint("BOTTOMLEFT", list.frame, "TOPLEFT", 0, Core.TIMER_GAP)
    else
        frame:SetPoint("TOPLEFT", list.frame, "BOTTOMLEFT", 0, -Core.TIMER_GAP)
    end
    for i, line in ipairs(off) do
        line:ClearAllPoints()
        line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, (#off - i) * WARNING_HEIGHT)
        line:Show()
    end
    frame:SetShown(#off > 0)
end

local function ApplyEarlyCasts(line)
    local early = line.unit and earlyCasts[line.unit]
    earlyCasts[line.unit or false] = nil
    if not early then return end
    local now = Now()
    for slotKey, cast in pairs(early) do
        local slot = SlotOf(line, slotKey)
        local same = not (cast.guid and line.guid) or cast.guid == line.guid
        if slot and same and now - cast.at <= Core.EARLY_CAST_SECONDS then MarkCast(line, slot, cast.spellID, cast.at) end
    end
end

-- keep each enemy on own line, keep the order
local function UpdateMulti()
    local list = lists.multi
    if not list then return end
    local lines = list.lines
    local wanted = (On("multi") and next(plates)) and Candidates() or {}
    local byUnit = {}
    for _, candidate in ipairs(wanted) do byUnit[candidate.unit] = candidate end
    local live, joining = {}, {}
    for _, line in ipairs(lines) do
        if line.seq and not line.frozenAt then
            local candidate = line.unit and byUnit[line.unit]
            if candidate then
                live[candidate.unit] = line
                Describe(line, candidate)
            else
                EndLine(line)
            end
        elseif line.seq and line.unit and byUnit[line.unit] then
            live[line.unit] = line
        end
    end
    for _, candidate in ipairs(wanted) do
        if not live[candidate.unit] then joining[#joining + 1] = candidate end
    end
    local liveCount = 0
    for _ in pairs(live) do liveCount = liveCount + 1 end
    local frozen = ReleaseFrozen(lines, liveCount + #joining)
    for _, candidate in ipairs(joining) do
        local line = FreeLine(lines, candidate.unit)
        if not line and candidate.target then
            line = LastLine(lines)
            if line then EndLine(line) end
        end
        if line and Bind(line, candidate.unit) then
            nextSeq = nextSeq + 1
            line.seq = nextSeq
            Describe(line, candidate)
            ApplyEarlyCasts(line)
        end
    end
    Layout()
    return frozen
end

-- nameplate gone, keep line greyed untill time up
local function Freeze(unit)
    local list = lists.multi
    if not list or not On("multi") then return end
    for _, line in ipairs(list.lines) do
        if line.unit == unit and line.seq and not line.frozenAt and line:IsShown() then
            if Plain(UnitIsDead, unit) == true then
                EndLine(line)
                Stack()
            else
                line.frozenAt = Now()
                line.mark:Hide()
                line.tint:Hide()
                line.name:SetTextColor(0.5, 0.5, 0.5)
                line.health:SetTextColor(0.5, 0.5, 0.5)
                line.portrait:SetDesaturated(true)
                line.bar:SetAlpha(0.5)
            end
        end
    end
end

local function Thaw(unit)
    local list = lists.multi
    if not list then return end
    for _, line in ipairs(list.lines) do
        if line.unit == unit and line.frozenAt then
            line.frozenAt = nil
            line.portraitFor = nil
            EachContainer(line, function(container) Call(container, "UpdateAllAuras") end)
        end
    end
    local guid = Plain(UnitGUID, unit)
    if not guid then return end
    for _, line in ipairs(list.lines) do
        if line.frozenAt and line.unit ~= unit and line.guid == guid then EndLine(line) end
    end
end

local function Update()
    UpdateFocus()
    UpdateMulti()
end

local function RememberEarlyCast(multi, slotKey, spellID, byClick)
    local now = Now()
    for unit in pairs(plates) do
        local hasLine = false
        for _, line in ipairs(multi.lines) do
            if line.seq and not line.frozenAt and line.unit == unit then hasLine = true end
        end
        if not hasLine and (Plain(UnitIsUnit, unit, "target") == true
            or (byClick and Plain(UnitIsUnit, unit, "focus") == true)) then
            earlyCasts[unit] = earlyCasts[unit] or {}
            earlyCasts[unit][slotKey] = { spellID = spellID, at = now, guid = Plain(UnitGUID, unit) }
        end
    end
end

-- remember own casts on enemies
local function OnCast(spellID, unit)
    local rowKey, slotKey = Core.FocusIconOfSpell(spellID), Core.EnemySlotOfSpell(spellID)
    local byPet = unit == "pet"
    if byPet then
        local def = rowKey and Core.FOCUS_ICON_BY_KEY[rowKey]
        if not (def and def.pet) then return end
        slotKey = nil
    end
    if not rowKey and not slotKey then return end
    local byClick = rowKey and clickedAt[rowKey] and Now() - clickedAt[rowKey] <= CLICK_WINDOW
    local focus = lists.focus
    if rowKey and focus and Plain(UnitExists, "focus") == true
        and (byClick or Plain(UnitIsUnit, byPet and "pettarget" or "target", "focus") == true) then
        local row = FocusItem(rowKey)
        if row then
            row.casted = true
            SetFlash(row, true, Core.FOCUS_DIM)
        end
    end
    local multi = lists.multi
    if slotKey and multi then
        local spellKey = Core.EnemySlotSpellKey(slotKey, spellID)
        if spellKey and ns.db.timers.lastInSlot[slotKey] ~= spellKey then
            ns.db.timers.lastInSlot[slotKey] = spellKey
            for _, line in ipairs(multi.lines) do
                local slot = SlotOf(line, slotKey)
                if slot and not slot.cast then slot.icon:SetTexture(SlotTexture(slot)) end
            end
        end
        for _, line in ipairs(multi.lines) do
            if line.seq and not line.frozenAt and line.unit then
                local hit = Plain(UnitIsUnit, line.unit, "target") == true
                    or (byClick and Plain(UnitIsUnit, line.unit, "focus") == true)
                local slot = hit and SlotOf(line, slotKey)
                if slot then MarkCast(line, slot, spellID) end
            end
        end
        RememberEarlyCast(multi, slotKey, spellID, byClick)
    end
end

local function CreateFocusList()
    local list = CreateList("focus", Text.TIMER_LIST_FOCUS, FOCUS_WIDTH, FOCUS_HEIGHT, true)
    local header = CreateFrame("Frame", "NecrosisOGFocusRows", list.frame, "SecureHandlerStateTemplate")
    header:SetSize(FOCUS_WIDTH, FOCUS_HEIGHT)
    header:SetAttribute("_onstate-focus", FOCUS_SNIPPET)
    RegisterStateDriver(header, "focus", FOCUS_STATE)
    list.driver = FOCUS_STATE
    list.header = header
    list.items = {}
    for _, def in ipairs(Core.FOCUS_ICONS) do list.items[#list.items + 1] = NewFocusIcon(header, def) end
    return list
end

local renewPending = false

local function RenewPetContainers()
    local list = lists.focus
    if not list then return end
    if InCombat() then
        renewPending = true
        return
    end
    renewPending = false
    for _, item in ipairs(list.items) do
        if item.def.pet then
            local old = item.containers[FOCUS_STYLE]
            local new = NewContainer(item.frame, "focus", "focus", FOCUS_STYLE, true, Core.FocusIconIds(item.def))
            if new then
                if old then
                    Call(old, "SetEnabled", false)
                    old:Hide()
                end
                item.containers[FOCUS_STYLE] = new
            end
        end
    end
    ArrangeFocus()
end

table.insert(ns.onPetSpells, RenewPetContainers)

local function Create()
    if created then return end
    if InCombat() then
        pending = true
        return
    end
    created = true
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    CreateFocusList()
    local multi = CreateList("multi", Text.TIMER_LIST_MULTI, MultiWidth(), Core.MULTI_BLOCK)
    multi.lines = {}
    for i = 1, Core.MULTI_LINES do multi.lines[i] = NewLine(multi) end
    CreateWarnings(multi)
    Arrange()
    Update()
    SyncNameplateSettings()
end

local handlers = {}
handlers.NAME_PLATE_UNIT_ADDED = function(unit)
    if type(unit) == "string" and not IsSecret(unit) then
        plates[unit] = true
        Thaw(unit)
    end
    UpdateMulti()
end

handlers.NAME_PLATE_UNIT_REMOVED = function(unit)
    if type(unit) == "string" and not IsSecret(unit) then
        plates[unit] = nil
        Freeze(unit)
    end
    UpdateMulti()
end

handlers.PLAYER_FOCUS_CHANGED = function()
    local list = lists.focus
    if not list then return end
    for _, item in ipairs(list.items) do
        item.casted = false
        SetFlash(item, false, Core.FOCUS_DIM)
    end
    RefreshFocusAuras()
    if InCombat() then UpdateFocusFit() else ArrangeFocus() end
    WatchFocusRange()
end

handlers.PLAYER_TARGET_CHANGED = function() UpdateMulti() end

table.insert(ns.onSpellsChanged, function() if created then Arrange() end end)
handlers.UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
    if (unit ~= "player" and unit ~= "pet") or IsSecret(spellID) or type(spellID) ~= "number" then return end
    OnCast(spellID, unit)
end

handlers.PLAYER_REGEN_ENABLED = function()
    if renewPending then RenewPetContainers() end
    if not created then Create() elseif pending then Arrange() else ArrangeFocus() end
    if plateSyncPending then SyncNameplateSettings() end
    UpdateWarnings(false)
    UpdateMulti()
end

handlers.PLAYER_REGEN_DISABLED = function() UpdateWarnings(true) end

local multiDirty = false
handlers.UNIT_THREAT_LIST_UPDATE = function(unit)
    if multiDirty then return end
    if type(unit) == "string" and not IsSecret(unit) and not plates[unit] and unit ~= "target" then return end
    multiDirty = true
end

handlers.UNIT_HEALTH = function(unit)
    local list = lists.multi
    if not list or type(unit) ~= "string" or IsSecret(unit) or not plates[unit] then return end
    for _, line in ipairs(list.lines) do
        if line.unit == unit and line.seq and not line.frozenAt then SetHealth(line, unit) end
    end
end

table.insert(ns.onSphere, function()
    local events = CreateFrame("Frame")
    for name in pairs(handlers) do
        if name == "UNIT_SPELLCAST_SUCCEEDED" then
            events:RegisterUnitEvent(name, "player", "pet")
        else
            events:RegisterEvent(name)
        end
    end
    events:SetScript("OnEvent", function(_, event, ...) handlers[event](...) end)
    local ticker = CreateFrame("Frame")
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= Core.MULTI_INTERVAL then
            elapsed = 0
            if next(plates) or AnyFrozen() then multiDirty = true end
        end
        if multiDirty then
            multiDirty = false
            UpdateMulti()
        end
    end)
    Create()
    table.insert(ns.onPlacing, function() Debuffs.Refresh() end)
end)

local DEMO_SEQ = 1000000

local function DemoSlotSpell(slot)
    for _, key in ipairs(slot.def.keys) do
        local id = Core.HighestKnown(Core.SPELLS[key], IsKnown)
        if id then return id end
    end
    return Core.SPELLS[slot.def.keys[1]][1]
end

local function CreateDemoParts()
    local focus, multi = lists.focus, lists.multi
    for _, item in ipairs(focus and focus.items or {}) do
        item.demo = item.demo or DemoIcon(item.frame, Core.FOCUS_ICON, FOCUS_FONT)
    end
    if not multi or multi.demoLines then return end
    multi.demoLines = {}
    for i = 1, #Core.DEMO.enemies do
        local line = NewLine(multi)
        line.demo = true
        for _, slot in ipairs(line.slots) do slot.demo = DemoIcon(slot.frame, Core.MULTI_ICON, ENEMY_FONT, true) end
        multi.demoLines[i] = line
    end
end

-- fake enemy first row
local function DescribeDemo(line, index, def)
    line.portrait:SetTexture(Plain(C_Spell.GetSpellTexture, Core.SPELLS[def.portrait][1]))
    line.portrait:SetDesaturated(false)
    line.name:SetText(string.format(Text.DEMO_ENEMY, index))
    line.bar:SetValue(def.health)
    line.bar:SetStatusBarColor(Core.ColourAt(Core.HEALTH_COLOUR_POINTS, def.health / 100))
    line.bar:SetAlpha(1)
    line.health:SetFormattedText("%.0f%%", def.health)
    line.health:SetTextColor(1, 1, 1)
    ShowThreat(line, def.threat)
    local target = def.target == true
    line.mark:SetShown(target)
    line.tint:SetShown(target)
    if target then line.name:SetTextColor(1, 0.82, 0) else line.name:SetTextColor(1, 1, 1) end
end

-- one fake debuff
local function DemoDebuff(frame, spellID, length, now)
    RunDemoIcon(frame, spellID, now, length)
    ns.DemoAt(now + length, function() StopDemoIcon(frame) end)
end

local function StartDemoData()
    local focus, multi = lists.focus, lists.multi
    local pause = Core.DEMO.pause
    for _, item in ipairs(focus and focus.items or {}) do
        local length = Core.DEMO.focusLengths[item.def.key]
        if length and item.demo then
            ns.DemoEvery(length + pause, function(now)
                if not item.spell then return end
                item.casted = true
                SetFlash(item, true, Core.FOCUS_DIM)
                DemoDebuff(item.demo, item.spell, length, now)
            end)
        end
    end
    UpdateFocusRange()
    for i, line in ipairs(multi and multi.demoLines or {}) do
        local def = Core.DEMO.enemies[i]
        line.seq = DEMO_SEQ + i
        DescribeDemo(line, i, def)
        line:Show()
        for _, slot in ipairs(line.slots) do
            local length = def.slots[slot.def.key]
            if length then
                ns.DemoEvery(length + pause, function(now)
                    if not slot.column then return end
                    local spellID = DemoSlotSpell(slot)
                    MarkCast(line, slot, spellID, now, length)
                    DemoDebuff(slot.demo, spellID, length, now)
                end)
            end
        end
    end
    Layout()
end

local function StopDemoData()
    local focus, multi = lists.focus, lists.multi
    for _, item in ipairs(focus and focus.items or {}) do
        StopDemoIcon(item.demo)
        item.casted = false
        SetFlash(item, false, Core.FOCUS_DIM)
    end
    UpdateFocusRange()
    for _, line in ipairs(multi and multi.demoLines or {}) do
        for _, slot in ipairs(line.slots) do StopDemoIcon(slot.demo) end
        EndLine(line)
    end
    Layout()
end

table.insert(ns.onDemo, function(on)
    if not created then return end
    if on then CreateDemoParts() end
    Arrange()
end)

table.insert(ns.onDemoData, function(on)
    if not created then return end
    if on then StartDemoData() else StopDemoData() end
end)

-- settings changed, redraw lists
function Debuffs.Refresh()
    if not created then return end
    Arrange()
    Update()
    SyncNameplateSettings()
    UpdateWarnings(InCombat())
end

function Debuffs.Rescale(key, old)
    local list = lists[key]
    if list then
        SavePlace(list)
        local saved = ns.db.timers[list.key]
        saved.x, saved.y = saved.x * old / Scale(key), saved.y * old / Scale(key)
        ApplyPlace(list)
    end
    UpdateWarnings(InCombat())
end

table.insert(ns.onRecall, function()
    for key, list in pairs(lists) do
        ns.db.timers[key] = Core.Copy(Core.DEFAULTS.timers[key])
        ApplyPlace(list)
    end
end)

-- still block of demo enemy for welcome card
function Debuffs.Sample(parent, index)
    local def = Core.DEMO.enemies[index]
    local line = NewLine({ frame = parent })
    line.demo = true
    DescribeDemo(line, index, def)
    local row2, n = -(Core.MULTI_HEAD + Core.MULTI_ROW_GAP), 0
    for _, slot in ipairs(line.slots) do
        if def.slots[slot.def.key] then
            n = n + 1
            slot.frame:ClearAllPoints()
            slot.frame:SetPoint("TOPLEFT", line, "TOPLEFT", (n - 1) * (Core.MULTI_ICON + Core.MULTI_ICON_GAP), row2)
            slot.icon:SetTexture(Plain(C_Spell.GetSpellTexture, Core.SPELLS[slot.def.keys[1]][1]))
            slot.frame:Show()
        end
    end
    line:Show()
    return line
end

-- still row of focus icons for welcome card
function Debuffs.FocusSample(parent, size)
    local row = CreateFrame("Frame", nil, parent)
    local step = size + math.floor(Core.FOCUS_ICON_GAP * size / Core.FOCUS_ICON + 0.5)
    for i, def in ipairs(Core.FOCUS_ICONS) do
        local frame = CreateFrame("Frame", nil, row)
        frame:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * step, 0)
        local icon = IconFace(frame, size, FOCUS_FONT)
        icon:SetTexture(Plain(C_Spell.GetSpellTexture, Core.SPELLS[def.spell][1]))
    end
    row:SetSize((#Core.FOCUS_ICONS - 1) * step + size, size)
    return row
end

function Debuffs.Frame() return lists.multi and lists.multi.frame or nil end
function Debuffs.Width() return lists.multi and lists.multi.width or MultiWidth() end
Debuffs.Layout = Layout
ns.Timers.SetHost({ Frame = Debuffs.Frame, Width = Debuffs.Width, Layout = Layout, Rescale = Debuffs.Rescale })

ns.OnSetting(Core.TIMER_LIST_SETTINGS, function() Debuffs.Refresh() end)

Debuffs.Lists = function() return lists end
Debuffs.Plates = function() return plates end

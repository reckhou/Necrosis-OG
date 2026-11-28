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

-- pick soulstone target from a list when in group
local _, ns = ...
local Core, Text = ns.Core, ns.Text
local Buttons = ns.Buttons
local Stones = ns.Stones

local Shortcut = {}
ns.SoulstoneShortcut = Shortcut

local IsSecret, Plain, InCombat = ns.Game.IsSecret, ns.Game.Plain, ns.Game.InCombat

local ROW_HEIGHT, ROW_GAP = 20, 2
local SINGLE_WIDTH = 168
local VISIBLE_ROWS = 5
local ROLE_SIZE = 12
local PADDING, TITLE_HEIGHT, HEADING_HEIGHT = 14, 24, 16
local GOLD = { 1, 0.82, 0 }
local PURPLE = { 0.72, 0.35, 1 }
local FLASH_FILL = { 0.96, 0.62, 0.04 }
local FLASH_BORDER = { 0.99, 0.88, 0.28 }
local FLASH_GLOW = { 0.98, 0.75, 0.14 }
local WARNING_SIZE = 23
local WARNING_COLOUR = { 1, 0.1, 0.1 }
local FLASH_SECONDS = 0.20
local ALERT_SOUND = 8959
local ERROR_SOUND = 847
local POPOUT_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
}

local popout, header, footerRule
local listBox = {}
local footers = {}
local allRows = {}
local note
local warning
local clicked
local sentByClick = false
local casting
local closeOnEnd = false
local closeAfterCombat = false
local rangeTicker

-- if right click open the list now
function Shortcut.Armed()
    if ns.debugGroup then return true end
    local held = Stones.State()
    return held.soulstone ~= nil and Stones.InGroup()
end

local function FriendlyTarget()
    if not ns.RangeCover.IsFriendlyPlayer("target") then return nil end
    return Stones.UnitFullName("target")
end

local function IsSelf(name) return Core.SamePlayer(name, Stones.UnitFullName("player")) end

local function IsFar(ok, inRange) return ok and not IsSecret(inRange) and inRange == false end

local function WouldHold(unit)
    if InCombat() or not Stones.State().soulstone then return false end
    if unit == nil or unit == "target" then return IsFar(ns.RangeCover.SoulstoneOnTarget()) end
    return IsFar(ns.RangeCover.StoneReaches(unit))
end

Shortcut.WouldHold = WouldHold

-- when target too far, empty the click so stone not go on yourself
function Shortcut.HoldFarUse(button, unit, ...)
    if not WouldHold(unit) then return false end
    local saved = {}
    for _, attribute in ipairs({ ... }) do
        saved[attribute] = button:GetAttribute(attribute)
        if saved[attribute] then button:SetAttribute(attribute, "") end
    end
    button.farHeld = saved
    ns.Banner(Text.SOULSTONE_OUT_OF_RANGE, 1.0, 0.1, 0.1)
    if not ns.Silent() and type(PlaySound) == "function" then pcall(PlaySound, ERROR_SOUND) end
    return true
end

function Shortcut.ReleaseFarUse(button)
    local saved = button.farHeld
    if not saved or InCombat() then return end
    button.farHeld = nil
    for attribute, value in pairs(saved) do button:SetAttribute(attribute, value) end
end

local function ShowName(row, inRange, hidden)
    local far = Core.FOCUS_RANGE_ALPHA
    if hidden then
        if pcall(row.label.SetAlphaFromBoolean, row.label, inRange, 1, 0)
            and pcall(row.farLabel.SetAlphaFromBoolean, row.farLabel, inRange, 0, far) then
            return
        end
        inRange = true
    end
    row.label:SetAlpha(inRange == false and 0 or 1)
    row.farLabel:SetAlpha(inRange == false and far or 0)
end

-- red name for player out of rnage
local function ApplyRange(row)
    if not row.farLabel then return end
    if ns.debugGroup or ns.demo or not row:IsShown() or not row.unit or not row.player then
        ShowName(row, true)
        return
    end
    local ok, inRange = ns.RangeCover.StoneReaches(row.unit)
    if ok and IsSecret(inRange) then
        ShowName(row, inRange, true)
    else
        ShowName(row, not (ok and inRange == false))
    end
end

local function UpdateRanges()
    if not popout or not popout:IsShown() then return end
    for _, row in ipairs(allRows) do ApplyRange(row) end
end

local function WatchRange(on)
    if on and not rangeTicker and C_Timer and C_Timer.NewTicker then
        rangeTicker = C_Timer.NewTicker(Core.FOCUS_RANGE_SECONDS, UpdateRanges)
    elseif not on and rangeTicker then
        rangeTicker:Cancel()
        rangeTicker = nil
    end
end

local function NewEdges(row)
    local edges = {}
    for i, points in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local edge = row:CreateTexture(nil, "BORDER")
        edge:SetPoint(points[1], row, points[1], 0, 0)
        edge:SetPoint(points[2], row, points[2], 0, 0)
        edge:SetSize(1, 1)
        edge:Hide()
        edges[i] = edge
    end
    return edges
end

local function Paint(row, colour, fillAlpha, edgeAlpha)
    row.highlight = colour
    if colour then
        row.fill:SetColorTexture(colour[1], colour[2], colour[3], fillAlpha or 0.20)
        for _, edge in ipairs(row.edges) do edge:SetColorTexture(colour[1], colour[2], colour[3], edgeAlpha or 0.90) end
    else
        row.fill:SetColorTexture(0, 0, 0, 0.25)
    end
    for _, edge in ipairs(row.edges) do edge:SetShown(colour ~= nil) end
end

local function ClassColour(class)
    local colour = type(RAID_CLASS_COLORS) == "table" and class and RAID_CLASS_COLORS[class]
    if colour then return colour.r, colour.g, colour.b end
    return 1, 1, 1
end

local function SetFlash(row, on)
    if row.flashing == on then return end
    row.flashing = on
    row.flash:SetShown(on)
    if on then row.pulse:Play() else row.pulse:Stop() end
end

-- gold for current target, purple for previous one
local function UpdateHighlights()
    if not popout then return end
    local target, previous = FriendlyTarget(), Stones.PreviousTarget()
    for _, row in ipairs(allRows) do
        local name = row.player
        local isTarget = name and target and Core.SamePlayer(name, target)
        local isPrevious = name and previous and Core.SamePlayer(name, previous)
        local isFlashing = casting ~= nil and name ~= nil and Core.SamePlayer(name, casting)
        if isFlashing then
            Paint(row, FLASH_FILL, 0.12, 0.35)
        else
            Paint(row, (isTarget and GOLD) or (isPrevious and PURPLE) or nil)
        end
        row.tag:SetShown(isPrevious == true and not row.footer)
        SetFlash(row, isFlashing)
        ApplyRange(row)
    end
end

local function SetName(row, name, class)
    row.player = name
    row.label:SetText(name or Text.SOULSTONE_NOBODY_TARGETED)
    row.label:SetTextColor(ClassColour(class))
    row.farLabel:SetText(name or Text.SOULSTONE_NOBODY_TARGETED)
end

local function RowPreClick(row, mouse)
    if ns.debugGroup or mouse ~= "LeftButton" then return end
    local name = row.footer == "target" and FriendlyTarget() or row.player
    clicked, sentByClick = { row = row, name = name }, false
    local unit = row.footer == "target" and "target" or row.unit
    if unit and Shortcut.HoldFarUse(row, unit, "macrotext1") then
        clicked.held = true
        return
    end
    local start, duration, hidden = Stones.Cooldown("soulstone")
    local ready = not hidden and Core.CooldownLeft(start, duration, GetTime()) == 0
    if name and ready and ns.Speech then ns.Speech.Speak("soulstone", "name", name) end
end

local function RowPostClick(row, mouse)
    Shortcut.ReleaseFarUse(row)
    if mouse ~= "LeftButton" or not clicked then return end
    local held = clicked.held
    clicked = nil
    if sentByClick or held then return end
    local start, duration, hidden = Stones.Cooldown("soulstone")
    local left = not hidden and Core.CooldownLeft(start, duration, GetTime()) or 0
    if left > 0 then ns.Banner(string.format(Text.SOULSTONE_ON_COOLDOWN, Core.CooldownText(left)), 1.0, 0.82, 0.0) end
    UpdateHighlights()
end

local function NewRow(name, footer, parent)
    local row = CreateFrame("Button", name, parent or popout, "SecureActionButtonTemplate")
    row:SetSize(SINGLE_WIDTH, ROW_HEIGHT)
    row:RegisterForClicks("AnyUp")
    row:SetAttribute("useOnKeyDown", false)
    row.footer = footer
    row.fill = row:CreateTexture(nil, "BACKGROUND")
    row.fill:SetAllPoints()
    row.edges = NewEdges(row)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    local hover = row:GetHighlightTexture()
    if hover then hover:SetBlendMode("ADD") end
    local flash = CreateFrame("Frame", nil, row)
    flash:SetAllPoints()
    flash:SetFrameLevel(row:GetFrameLevel() + 1)
    local flashFill = flash:CreateTexture(nil, "BACKGROUND")
    flashFill:SetAllPoints()
    flashFill:SetColorTexture(FLASH_FILL[1], FLASH_FILL[2], FLASH_FILL[3], 0.50)
    local flashGlow = flash:CreateTexture(nil, "ARTWORK")
    flashGlow:SetAllPoints()
    flashGlow:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    flashGlow:SetBlendMode("ADD")
    flashGlow:SetVertexColor(FLASH_GLOW[1], FLASH_GLOW[2], FLASH_GLOW[3], 0.65)
    local flashEdges = NewEdges(flash)
    for _, edge in ipairs(flashEdges) do
        edge:SetColorTexture(FLASH_BORDER[1], FLASH_BORDER[2], FLASH_BORDER[3], 0.98)
        edge:Show()
    end
    flash:Hide()
    row.flash = flash
    row.pulse = flash:CreateAnimationGroup()
    row.pulse:SetLooping("BOUNCE")
    local step = ns.Bars.AlphaStep(row.pulse, 1, 0.22, FLASH_SECONDS)
    if step.SetSmoothing then step:SetSmoothing("IN_OUT") end
    local textLayer = CreateFrame("Frame", nil, row)
    textLayer:SetAllPoints()
    textLayer:SetFrameLevel(row:GetFrameLevel() + 2)
    row.textLayer = textLayer
    row.role = textLayer:CreateTexture(nil, "OVERLAY")
    row.role:SetSize(ROLE_SIZE, ROLE_SIZE)
    row.role:SetPoint("LEFT", textLayer, "LEFT", 4, 0)
    row.role:SetTexture(ROLE_ICON)
    row.role:Hide()
    row.tag = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.tag:SetPoint("RIGHT", textLayer, "RIGHT", -5, 0)
    row.tag:SetText(Text.SOULSTONE_PREV_TAG)
    row.tag:SetTextColor(PURPLE[1], PURPLE[2], PURPLE[3])
    row.tag:Hide()
    row.label = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", textLayer, "LEFT", 6, 0)
    row.label:SetPoint("RIGHT", textLayer, "RIGHT", -30, 0)
    row.label:SetJustifyH("CENTER")
    row.label:SetWordWrap(false)
    row.farLabel = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.farLabel:SetPoint("LEFT", textLayer, "LEFT", 6, 0)
    row.farLabel:SetPoint("RIGHT", textLayer, "RIGHT", -30, 0)
    row.farLabel:SetJustifyH("CENTER")
    row.farLabel:SetWordWrap(false)
    row.farLabel:SetTextColor(1, 0, 0)
    row.farLabel:SetAlpha(0)
    row:SetScript("PreClick", RowPreClick)
    row:SetScript("PostClick", RowPostClick)
    ns.Sounds.Button(row)
    row:Hide()
    allRows[#allRows + 1] = row
    return row
end

local function ItemMacro(name, how)
    local held = Stones.State()
    return Core.SoulstoneShortcutMacro(Stones.List("soulstone"), held.soulstone and held.soulstone.id, name, how)
end

local function SetIcon(row, class, role)
    local shown = ns.Media.SetNameIcon(row.role, class, role)
    row.role:ClearAllPoints()
    for _, label in ipairs({ row.label, row.farLabel }) do
        label:ClearAllPoints()
        label:SetPoint("CENTER", row.textLayer, "CENTER", shown and (ROLE_SIZE + 4) / 2 or 0, 0)
    end
    if shown then row.role:SetPoint("RIGHT", row.label, "LEFT", -4, 0) end
end

local function Fill(row, name, class, how, unit, role)
    row.unit = unit
    SetName(row, name, class)
    SetIcon(row, class, role)
    Buttons.SetActions(row, { type1 = "macro", macrotext1 = not ns.debugGroup and ItemMacro(name, how) or false })
end

local function Place(region, x, y)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", popout, "TOPLEFT", x, -y)
end

-- fill and place the list, only out of combat
local function Layout()
    if not popout or InCombat() then return false end
    local members, raid
    if ns.debugGroup then
        members, raid = ns.debugGroup.members, ns.debugGroup.raid
    else
        members, raid = Stones.Group()
    end
    local list = Core.SoulstoneCandidates(members, raid)
    local stride = ROW_HEIGHT + ROW_GAP
    local listed = {}
    for i, row in ipairs(listBox.rows) do
        local member = list[i]
        if member then
            listed[#listed + 1] = member.name
            Fill(row, member.name, member.class, "name", member.unit, member.role)
            row:SetWidth(SINGLE_WIDTH)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", listBox.content, "TOPLEFT", 0, -(i - 1) * stride)
            row:Show()
        else
            row.player, row.unit = nil, nil
            row:Hide()
        end
    end
    local contentHeight = math.max(#list * stride - ROW_GAP, 1)
    local shown = math.max(math.min(#list, VISIBLE_ROWS), 1)
    local viewHeight = shown * stride - ROW_GAP
    listBox.content:SetSize(SINGLE_WIDTH, contentHeight)
    listBox.scroll:SetSize(SINGLE_WIDTH, viewHeight)
    listBox.scroll:ClearAllPoints()
    listBox.scroll:SetPoint("TOPLEFT", popout, "TOPLEFT", PADDING, -(PADDING + TITLE_HEIGHT))
    listBox.scroll:SetVerticalScroll(0)
    listBox.maxScroll = math.max(0, contentHeight - viewHeight)
    listBox.scroll:SetShown(#list > 0)
    local bottom = PADDING + TITLE_HEIGHT + viewHeight
    note:SetShown(#list == 0)
    if #list == 0 then
        Place(note, PADDING, bottom + 2)
        bottom = bottom + HEADING_HEIGHT + ROW_GAP
    end
    local previous, target = Core.SoulstoneFooters(listed, Stones.PreviousTarget(), FriendlyTarget())
    local hasFooter = previous ~= nil or target ~= nil
    footerRule:SetShown(hasFooter)
    if hasFooter then
        footerRule:ClearAllPoints()
        footerRule:SetPoint("TOPLEFT", popout, "TOPLEFT", PADDING, -(bottom + 3))
        footerRule:SetPoint("TOPRIGHT", popout, "TOPRIGHT", -PADDING, -(bottom + 3))
        bottom = bottom + 7
    end
    for _, entry in ipairs({ { "previous", previous }, { "target", target } }) do
        local row, name = footers[entry[1]], entry[2]
        row.heading:SetShown(name ~= nil)
        if name then
            Place(row.heading, PADDING, bottom + 2)
            bottom = bottom + HEADING_HEIGHT
            local how = (entry[1] == "target" and "target") or (IsSelf(name) and "self") or "name"
            local class, unit
            if entry[1] == "target" then
                unit = "target"
            elseif IsSelf(name) then
                unit = "player"
            end
            for _, member in ipairs(members) do
                if Core.SamePlayer(member.name, name) then
                    class = member.class
                    if not unit then unit = member.unit end
                end
            end
            if not class and unit then
                local ok, _, file = pcall(UnitClass, unit)
                if ok and type(file) == "string" then class = file end
            end
            Fill(row, name, class, how, unit)
            SetIcon(row, nil, nil)
            row:SetWidth(SINGLE_WIDTH)
            Place(row, PADDING, bottom)
            bottom = bottom + ROW_HEIGHT + ROW_GAP
            row:Show()
        else
            row.player, row.unit = nil, nil
            row:Hide()
        end
    end
    popout:SetSize(SINGLE_WIDTH + PADDING * 2, bottom + PADDING - ROW_GAP)
    UpdateHighlights()
    return true
end

local function Close()
    casting = nil
    closeOnEnd = false
    if not popout then return end
    UpdateHighlights()
    if InCombat() then
        closeAfterCombat = popout:IsShown() == true
    else
        closeAfterCombat = false
        popout:Hide()
    end
end

local CLOSE_CLICK = [[
    self:GetFrameRef("shortcut"):Hide()
    return false
]]

local function ScrollWheel(_, delta)
    if not listBox.scroll or not listBox.maxScroll then return end
    local target = listBox.scroll:GetVerticalScroll() - delta * (ROW_HEIGHT + ROW_GAP)
    listBox.scroll:SetVerticalScroll(math.max(0, math.min(listBox.maxScroll, target)))
end

local function CreatePopout()
    popout = CreateFrame("Frame", "NecrosisOGSoulstoneShortcut", UIParent, "SecureHandlerBaseTemplate, BackdropTemplate")
    ns.SettingsWindow.TrackScale(popout, true)
    popout:SetSize(SINGLE_WIDTH + PADDING * 2, 80)
    popout:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popout:SetFrameStrata("DIALOG")
    popout:SetClampedToScreen(true)
    popout:EnableMouse(true)
    if popout.SetBackdrop then popout:SetBackdrop(POPOUT_BACKDROP) end
    popout.title = popout:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    popout.title:SetPoint("TOP", popout, "TOP", 0, -PADDING)
    popout.title:SetJustifyH("CENTER")
    popout.title:SetText(Core.Gradient(Text.SOULSTONE_TARGET_TITLE, Core.GRADIENT_TITLE))
    local divider = popout:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", popout, "TOPLEFT", PADDING, -(PADDING + TITLE_HEIGHT - 4))
    divider:SetPoint("TOPRIGHT", popout, "TOPRIGHT", -PADDING, -(PADDING + TITLE_HEIGHT - 4))
    divider:SetSize(1, 1)
    divider:SetColorTexture(0.78, 0.65, 0.35, 0.45)
    popout.divider = divider
    footerRule = popout:CreateTexture(nil, "ARTWORK")
    footerRule:SetSize(1, 1)
    footerRule:SetColorTexture(1, 1, 1, 0.16)
    footerRule:Hide()

    local close = CreateFrame("Button", "NecrosisOGSoulstoneShortcutClose", popout,
        "SecureActionButtonTemplate, UIPanelCloseButton")
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", popout, "TOPRIGHT", -5, -5)
    close:RegisterForClicks("AnyUp")
    close:SetAttribute("useOnKeyDown", false)
    close:SetScript("OnClick", nil)
    SecureHandlerSetFrameRef(close, "shortcut", popout)
    header:WrapScript(close, "OnClick", CLOSE_CLICK)
    ns.Sounds.Button(close)
    popout.close = close

    local function Heading(colour)
        local line = popout:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        if colour then line:SetTextColor(colour[1], colour[2], colour[3]) end
        line:Hide()
        return line
    end
    listBox.scroll = CreateFrame("ScrollFrame", nil, popout)
    listBox.content = CreateFrame("Frame", nil, listBox.scroll)
    listBox.content:SetSize(SINGLE_WIDTH, ROW_HEIGHT)
    listBox.scroll:SetScrollChild(listBox.content)
    listBox.scroll:EnableMouseWheel(true)
    listBox.scroll:SetScript("OnMouseWheel", ScrollWheel)
    listBox.rows = {}
    for i = 1, Core.SOULSTONE_ROWS do
        local row = NewRow("NecrosisOGSoulstoneRow" .. i, nil, listBox.content)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", ScrollWheel)
        listBox.rows[i] = row
    end
    note = Heading({ 0.6, 0.6, 0.6 })
    note:SetText(Text.SOULSTONE_NOBODY)
    for _, entry in ipairs({ { "previous", PURPLE, "SOULSTONE_PREVIOUS" }, { "target", GOLD, "SOULSTONE_CURRENT" } }) do
        local row = NewRow("NecrosisOGSoulstoneRow_" .. entry[1], entry[1])
        row.heading = Heading(entry[2])
        row.heading:SetText(Text[entry[3]])
        footers[entry[1]] = row
    end
    popout:Hide()
    popout:HookScript("OnShow", function()
        closeAfterCombat = false
        if not Layout() then UpdateHighlights() end
        WatchRange(true)
    end)
    popout:HookScript("OnHide", function()
        WatchRange(false)
    end)
    ns.Sounds.Window(popout)
end

local function CreateWarning()
    warning = CreateFrame("Frame", "NecrosisOGSoulstoneWarning", UIParent)
    warning:SetSize(700, 30)
    warning:SetPoint("TOP", UIErrorsFrame or UIParent, "TOP", 0, 0)
    warning:SetFrameStrata("DIALOG")
    warning:SetFrameLevel(20)
    warning:EnableMouse(false)
    warning.text = warning:CreateFontString(nil, "OVERLAY", ns.Media.Font("ErrorFont", WARNING_SIZE, true))
    warning.text:SetPoint("TOP", warning, "TOP", 0, 0)
    warning.text:SetTextColor(WARNING_COLOUR[1], WARNING_COLOUR[2], WARNING_COLOUR[3])
    warning:Hide()
end

local function HideWarning()
    if warning then warning:Hide() end
end

-- warn when stone cast on other than previous one
local function ShowWarning(recipient, previous)
    if not warning then CreateWarning() end
    warning.text:SetText(string.format(Text.SOULSTONE_MISMATCH_WARN, recipient, previous))
    warning:Show()
    if not ns.Silent() and type(PlaySound) == "function" then
        pcall(PlaySound, type(SOUNDKIT) == "table" and SOUNDKIT.RAID_WARNING or ALERT_SOUND)
    end
end

table.insert(Stones.casts, function(event, cast)
    if event == "sent" then
        local fromList = clicked ~= nil
        if fromList then sentByClick = true end
        casting = cast.recipient or (clicked and clicked.name)
        closeOnEnd = fromList
        if casting then UpdateHighlights() end
        local previous = Stones.PreviousTarget()
        if Core.SoulstoneMismatchWarning(Stones.InGroup(), previous, cast.recipient, fromList) then
            ShowWarning(cast.recipient, previous)
        else
            HideWarning()
        end
    else
        HideWarning()
        if casting then
            local shouldClose = closeOnEnd
            closeOnEnd = false
            if shouldClose then
                Close()
            else
                casting = nil
                UpdateHighlights()
            end
        end
    end
end)

-- give soulstone button the right click to open list
function Shortcut.Attach(button, secureHeader)
    if not popout then
        header = secureHeader
        CreatePopout()
    end
    SecureHandlerSetFrameRef(button, "shortcut", popout)
    header:WrapScript(button, "OnClick", Core.SOULSTONE_SHORTCUT_CLICK)
end

function Shortcut.Preview()
    Buttons.Refresh()
    if popout then popout:SetShown(ns.debugGroup ~= nil) end
end

Buttons.OnRefresh(function()
    if not popout then return end
    if not Shortcut.Armed() then
        casting = nil
        closeOnEnd = false
        popout:Hide()
    end
    Layout()
end)

local events = CreateFrame("Frame")
local rosterDue = false
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
        if not popout or not popout:IsShown() then return end
        if not Layout() then
            local row = footers.target
            if row:IsShown() then SetName(row, FriendlyTarget()) end
            UpdateHighlights()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if closeAfterCombat then Close() end
    elseif not rosterDue then
        rosterDue = true
        C_Timer.After(0, function()
            rosterDue = false
            Buttons.Refresh()
        end)
    end
end)

table.insert(ns.onSphere, function()
    for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE",
        "PLAYER_ROLES_ASSIGNED" }) do
        events:RegisterEvent(event)
    end
end)

Shortcut.Frame = function() return popout end
Shortcut.Warning = function() return warning end
Shortcut.Column = function(index) if index == 1 then return listBox end end
Shortcut.Footer = function(key) return footers[key] end
Shortcut.Casting = function() return casting end

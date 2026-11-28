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

-- window of the summon queue
local _, ns = ...
local Core, Text = ns.Core, ns.Text
local Buttons = ns.Buttons
local Stones = ns.Stones

local Summon = {}
ns.SummonQueue = Summon

local IsSecret, Plain, InCombat, SpellName = ns.Game.IsSecret, ns.Game.Plain, ns.Game.InCombat, ns.Game.SpellName

local PADDING, TITLE_HEIGHT = 14, 24
local BODY_TOP = PADDING + TITLE_HEIGHT
local INNER_WIDTH = 220
local ROW_HEIGHT, ROW_GAP, HEAD_HEIGHT = 20, 2, 18
local DISMISS_WIDTH = 18
local HEADER_HEIGHT, NEXT_HEIGHT = 16, 20
local LIST_TOP = HEADER_HEIGHT + NEXT_HEIGHT + 8
local MAX_LIST_HEIGHT = 220
local SCROLLBAR_WIDTH = 22
local FOOTER_GAP, FOOTER_HEIGHT = 6, 20
local DEFAULT_OPTIONS_HEIGHT = 202
local TICK = 1
local HELPERS_GOOD, HELPERS_SHORT = { 0.4, 1, 0.4 }, { 1, 0.7, 0.2 }
local STATE_TEXT = { accepted = "SUMMON_ACCEPTED", declined = "SUMMON_DECLINED", expired = "SUMMON_EXPIRED",
    shard = "SUMMON_OTHER_SHARD" }
local POPOUT_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
}

local queue = Core.NewSummonQueue()
local frame, queueBody, optionsBody, scroll, content, header, nextButton, awayHead, emptyNote, toggleButton
local sections = {}
local wanted = false
local manual = false
local pendingAuto = false

local awayChoice

local function AwayOpen()
    if awayChoice ~= nil then return awayChoice end
    return ns.Game.Plain(IsInRaid) ~= true
end

local optionsOpen = false
local optionsHeight = DEFAULT_OPTIONS_HEIGHT
local lastListHeight = HEAD_HEIGHT
local demo
local demoOpened = false
local ticker
local cues = {}
local started = false

local function Saved() return ns.db.summon end

local function RitualId()
    return Core.HighestKnown(Core.SPELLS.ritualOfSummoning, Buttons.IsKnown)
end

local function Enabled()
    return RitualId() ~= nil
end

-- if right click on ritual button open the queue
function Summon.Takes()
    return Enabled() or ns.demo == true
end

local function InstanceOf(unit)
    if type(UnitPosition) ~= "function" then return nil end
    local ok, _, _, _, instance = pcall(UnitPosition, unit)
    if ok and not IsSecret(instance) and type(instance) == "number" then return instance end
    return nil
end

local function MapOf(unit)
    local id = type(C_Map) == "table" and Plain(C_Map.GetBestMapForUnit, unit)
    local info = type(id) == "number" and Plain(C_Map.GetMapInfo, id)
    if type(info) ~= "table" then return nil, nil end
    local dungeon
    if type(info.mapType) == "number" and not IsSecret(info.mapType) then
        dungeon = info.mapType == Core.SUMMON_MAP_DUNGEON
    end
    return not IsSecret(info.name) and info.name or nil, dungeon
end

local function RosterZone(unit)
    local index = tonumber(string.match(unit, "^raid(%d+)$"))
    if not index or type(GetRaidRosterInfo) ~= "function" then return nil end
    local ok, _, _, _, _, _, _, zone = pcall(GetRaidRosterInfo, index)
    if ok and not IsSecret(zone) and type(zone) == "string" and zone ~= "" then return zone end
    return nil
end

-- read group member with info for summon
local function Detail(member)
    local unit = member.unit
    member.guid = Plain(UnitGUID, unit)
    member.online = Plain(UnitIsConnected, unit) ~= false
    member.dead = Plain(UnitIsDeadOrGhost, unit) == true
    member.visible = Plain(UnitIsVisible, unit) == true
    member.phased = Plain(UnitPhaseReason, unit) ~= nil
    member.instance = InstanceOf(unit)
    local zone, dungeon = MapOf(unit)
    member.zone, member.inDungeon = RosterZone(unit) or zone, dungeon
    return member
end

local function Members()
    if demo then return demo.members end
    local members = Stones.Group()
    for _, member in ipairs(members) do Detail(member) end
    return members
end

local function Find(members, who)
    for _, member in ipairs(members) do
        if who.guid and member.guid then
            if who.guid == member.guid then return member end
        elseif Core.SamePlayer(who.name, member.name) then
            return member
        end
    end
    return nil
end

local function Me()
    if demo then return { inInstance = false } end
    local inInstance = Plain(IsInInstance)
    return { inInstance = inInstance, instance = InstanceOf("player") }
end

local function Shards()
    if demo then return demo.shards end
    local count = Plain(C_Item and C_Item.GetItemCount, Core.SOUL_SHARD_ITEM)
    return type(count) == "number" and count or 0
end

local function ChatLocked()
    return not demo and type(C_ChatInfo) == "table" and Plain(C_ChatInfo.InChatMessagingLockdown) == true
end

local function Queue() return demo and demo.queue or queue end

-- set macro of button just before the click
local function Prepare(button, mouse)
    if InCombat() then return end
    local target = mouse == "LeftButton" and button.who
    local ritual = RitualId()
    local member = target and not ns.debugGroup and not demo and Find(Members(), target)
    local macro
    if member and ritual and not Core.SummonBlocked(Me(), member) then
        macro = Core.SummonMacro(member.unit, SpellName(ritual))
    end
    Buttons.SetActions(button, { type1 = "macro", macrotext1 = macro or false })
    if macro then
        Core.SummonClicked(queue, member, GetTime())
        if ns.Speech then ns.Speech.Speak("ritualOfSummoning", "name", member.name) end
    end
end

local Layout, UpdateCues, UpdateTicker

local function ClassColour(class)
    local colour = type(RAID_CLASS_COLORS) == "table" and class and RAID_CLASS_COLORS[class]
    if colour then return colour.r, colour.g, colour.b end
    return 1, 1, 1
end

local function Dismiss(entry)
    if not ns.debugGroup and entry and Core.SummonDismiss(Queue(), entry) then Summon.Update() end
end

local function RowTooltip(tooltip, row)
    local data = row.data
    if not data then return false end
    ns.Tips.Title(tooltip, data.name)
    if data.zone then ns.Tips.Line(tooltip, data.zone) end
    if data.reason then
        ns.Tips.Note(tooltip, Text[data.reason])
        return
    end
    if data.waited then ns.Tips.Line(tooltip, string.format(Text.SUMMON_TIP_WAITED, Core.SummonClock(data.waited))) end
    if data.castable then ns.Tips.Click(tooltip, "left", Text.ACT_SUMMON) end
    if data.section == "waiting" then ns.Tips.Click(tooltip, "right", Text.ACT_SUMMON_REMOVE) end
end

local function RowWidth(activeWidth, section)
    return section == "away" and activeWidth or (activeWidth - DISMISS_WIDTH)
end

local function NewRow(name, section)
    local rowWidth = RowWidth(INNER_WIDTH, section)
    local row = CreateFrame("Button", name, content, "SecureActionButtonTemplate")
    row:SetSize(rowWidth, ROW_HEIGHT)
    row:RegisterForClicks("AnyUp")
    row:SetAttribute("useOnKeyDown", false)
    row.section = section
    local fill = row:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0, 0, 0, 0.25)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    local hover = row:GetHighlightTexture()
    if hover then hover:SetBlendMode("ADD") end
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(12, 12)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon:Hide()
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.label:SetWidth(94)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.info:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.info:SetWidth(math.max(40, rowWidth - 104))
    row.info:SetJustifyH("RIGHT")
    row.info:SetWordWrap(false)
    ns.Tips.Attach(row, RowTooltip, "ANCHOR_RIGHT")
    row:SetScript("PreClick", Prepare)
    row:SetScript("PostClick", function(self, mouse)
        if mouse == "RightButton" and self.section == "waiting" then Dismiss(self.entry) end
    end)
    ns.Sounds.Button(row)
    if section ~= "away" then
        local dismiss = CreateFrame("Button", nil, content)
        dismiss:SetSize(DISMISS_WIDTH, ROW_HEIGHT)
        dismiss:SetPoint("LEFT", row, "RIGHT", 0, 0)
        local dismissFill = dismiss:CreateTexture(nil, "BACKGROUND")
        dismissFill:SetAllPoints()
        dismissFill:SetColorTexture(0, 0, 0, 0.25)
        dismiss:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        local dismissHover = dismiss:GetHighlightTexture()
        if dismissHover then dismissHover:SetBlendMode("ADD") end
        local cross = dismiss:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cross:SetPoint("CENTER", dismiss, "CENTER", 0, 0)
        cross:SetText("x")
        dismiss:SetScript("OnClick", function() Dismiss(row.entry) end)
        ns.Sounds.Button(dismiss)
        dismiss:Hide()
        row.dismiss = dismiss
    end
    row:Hide()
    return row
end

-- put data of one player into row
local function FillRow(row, data, entry, y, activeWidth)
    local rowWidth = RowWidth(activeWidth, row.section)
    row.data, row.entry = data, entry
    row.who = data.castable and { guid = data.guid, name = data.name } or nil
    row:SetWidth(rowWidth)
    row.info:SetWidth(math.max(40, rowWidth - 104))
    local iconShown = ns.Media.SetNameIcon(row.icon, data.class, data.role)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", iconShown and 20 or 5, 0)
    row.label:SetText(data.name)
    row.info:SetText(data.info or "")
    if data.reason then
        row.label:SetTextColor(0.55, 0.55, 0.55)
        row.info:SetTextColor(0.55, 0.55, 0.55)
    else
        row.label:SetTextColor(ClassColour(data.class))
        row.info:SetTextColor(0.85, 0.85, 0.85)
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    row:Show()
    if row.dismiss then row.dismiss:Show() end
end

local function HideRow(row)
    row.data, row.entry, row.who = nil, nil, nil
    row:Hide()
    if row.dismiss then row.dismiss:Hide() end
end

local function SummonedInfo(entry, now)
    if entry.offline then return Text.SUMMON_OFFLINE end
    local words = STATE_TEXT[entry.state] and Text[STATE_TEXT[entry.state]]
    if entry.state == "offered" then words = Core.SummonClock(entry.endsAt - now) end
    if entry.byOther then words = string.format(Text.SUMMON_BY_OTHER, words) end
    return words
end

local function RoleOf(members, entry)
    local member = Find(members, entry)
    return member and member.role or nil
end

-- rows of each list from queue and group
local function Rows(members, now, list, sample)
    local waiting, summoned = Core.SummonLists(list)
    local me, ritual = sample and { inInstance = false } or Me(), RitualId()
    local function Castable(entry)
        local member = Find(members, entry)
        return (ritual ~= nil or sample ~= nil) and member ~= nil and not Core.SummonBlocked(me, member)
    end
    local lists = { waiting = {}, summoned = {}, away = {} }
    for _, entry in ipairs(waiting) do
        local waited = now - entry.addedAt
        local info = entry.offline and Text.SUMMON_OFFLINE or Core.SummonClock(waited)
        if entry.zone and not entry.offline then info = entry.zone .. "  " .. info end
        lists.waiting[#lists.waiting + 1] = { entry = entry, data = { section = "waiting", guid = entry.guid,
            name = entry.name, class = entry.class, role = RoleOf(members, entry), zone = entry.zone, info = info,
            waited = waited, castable = Castable(entry) } }
    end
    for _, entry in ipairs(summoned) do
        lists.summoned[#lists.summoned + 1] = { entry = entry, data = { section = "summoned", guid = entry.guid,
            name = entry.name, class = entry.class, role = RoleOf(members, entry), zone = entry.zone,
            info = SummonedInfo(entry, now), castable = Core.SummonRetryable(entry) and Castable(entry) } }
    end
    for _, member in ipairs(Core.SummonAway(members, list)) do
        local reason = Core.SummonBlocked(me, member)
        lists.away[#lists.away + 1] = { data = { section = "away", guid = member.guid, name = member.name,
            class = member.class, role = member.role, zone = member.zone, reason = reason,
            info = reason and Text[reason] or member.zone,
            castable = reason == nil and (ritual ~= nil or sample ~= nil) } }
    end
    local nextEntry = Core.SummonNext(waiting, summoned, Castable)
    return lists, nextEntry
end

local function UpdateSize()
    if not frame or InCombat() then return end
    local bodyHeight = math.max(optionsHeight, LIST_TOP + lastListHeight)
    if queueBody then queueBody:SetSize(INNER_WIDTH, LIST_TOP + lastListHeight) end
    local footerBlock = FOOTER_GAP + 1 + FOOTER_GAP + FOOTER_HEIGHT
    frame:SetSize(INNER_WIDTH + PADDING * 2, BODY_TOP + bodyHeight + footerBlock + PADDING)
end

local function SetOptionsOpen(open)
    if not frame or InCombat() then return end
    optionsOpen = open == true
    queueBody:SetShown(not optionsOpen)
    optionsBody:SetShown(optionsOpen)
    toggleButton:SetText(optionsOpen and Text.SUMMON_HIDE_OPTIONS or Text.SUMMON_OPTIONS)
    if optionsOpen then
        UpdateSize()
    else
        Layout()
    end
end

local function EstimateListHeight(lists)
    local h = HEAD_HEIGHT
    local waitCount = math.min(#lists.waiting, Core.SUMMON_ROWS)
    h = h + (waitCount == 0 and HEAD_HEIGHT or waitCount * (ROW_HEIGHT + ROW_GAP))
    local sumCount = math.min(#lists.summoned, Core.SUMMON_ROWS)
    if sumCount > 0 then h = h + ROW_GAP * 2 + HEAD_HEIGHT + sumCount * (ROW_HEIGHT + ROW_GAP) end
    h = h + ROW_GAP * 2 + HEAD_HEIGHT + ROW_GAP
    if AwayOpen() then h = h + math.min(#lists.away, Core.SUMMON_ROWS) * (ROW_HEIGHT + ROW_GAP) end
    return h
end

Layout = function()
    if not frame or not frame:IsShown() or InCombat() then return end
    local sample = ns.debugGroup or demo
    local now = ns.debugGroup and ns.debugGroup.now or GetTime()
    local members = sample and sample.members or Members()
    local lists, nextEntry = Rows(members, now, sample and sample.queue or queue, sample)
    local helpers = sample and sample.helpers or Core.SummonHelpers(members)
    local colour = helpers >= Core.SUMMON_HELPERS and HELPERS_GOOD or HELPERS_SHORT
    header.helpers:SetText(string.format(Text.SUMMON_HELPERS_LINE, helpers, Core.SUMMON_HELPERS))
    header.helpers:SetTextColor(colour[1], colour[2], colour[3])
    local shards = sample and sample.shards or Shards()
    header.shards:SetText(string.format(Text.SUMMON_SHARDS_LINE, shards))
    header.locked:SetShown(ChatLocked())
    nextButton.who = nextEntry and shards > 0 and { guid = nextEntry.guid, name = nextEntry.name } or nil
    nextButton:SetEnabled(nextButton.who ~= nil)
    if not nextButton.who then Buttons.SetActions(nextButton, { type1 = "macro", macrotext1 = false }) end

    local needsScroll = EstimateListHeight(lists) > MAX_LIST_HEIGHT
    local activeWidth = needsScroll and (INNER_WIDTH - SCROLLBAR_WIDTH) or INNER_WIDTH

    local y = 0
    local function Head(region, text)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        region:SetText(text)
        region:Show()
        y = y + HEAD_HEIGHT
    end
    local function List(key, shown)
        local rows, list = sections[key].rows, lists[key]
        for i, row in ipairs(rows) do
            local item = shown and list[i]
            if item then
                FillRow(row, item.data, item.entry, y, activeWidth)
                y = y + ROW_HEIGHT + ROW_GAP
            else
                HideRow(row)
            end
        end
    end
    Head(sections.waiting.heading, string.format(Text.SUMMON_WAITING, #lists.waiting))
    emptyNote:SetShown(#lists.waiting == 0)
    if #lists.waiting == 0 then
        emptyNote:ClearAllPoints()
        emptyNote:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
        y = y + HEAD_HEIGHT
    end
    List("waiting", true)
    sections.summoned.heading:SetShown(#lists.summoned > 0)
    if #lists.summoned > 0 then
        y = y + ROW_GAP * 2
        Head(sections.summoned.heading, string.format(Text.SUMMON_SUMMONED, #lists.summoned))
    end
    List("summoned", true)
    y = y + ROW_GAP * 2
    awayHead:SetWidth(activeWidth)
    awayHead:ClearAllPoints()
    awayHead:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    awayHead:SetText(string.format(AwayOpen() and Text.SUMMON_AWAY_OPEN or Text.SUMMON_AWAY_CLOSED, #lists.away))
    y = y + HEAD_HEIGHT + ROW_GAP
    List("away", AwayOpen())

    local contentHeight = math.max(1, y)
    lastListHeight = math.min(contentHeight, MAX_LIST_HEIGHT)
    content:SetSize(activeWidth, contentHeight)
    scroll:SetSize(activeWidth, lastListHeight)
    if scroll.ScrollBar then scroll.ScrollBar:SetShown(needsScroll) end
    if not needsScroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
    UpdateSize()
end

local function ApplyPlace()
    local saved = Saved()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", saved.x / frame:GetScale(), saved.y / frame:GetScale())
end

-- make the window
local function Create()
    frame = CreateFrame("Frame", "NecrosisOGSummonFrame", UIParent, "SecureHandlerStateTemplate, BackdropTemplate")
    ns.SettingsWindow.TrackScale(frame, true)
    frame:SetSize(INNER_WIDTH + PADDING * 2, 160)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    if frame.SetBackdrop then frame:SetBackdrop(POPOUT_BACKDROP) end
    frame:SetScript("OnDragStart", function(self)
        if InCombat() then return end
        self.dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self.dragging = false
        self:StopMovingOrSizing()
        if self.SetUserPlaced then pcall(self.SetUserPlaced, self, false) end
        local x, y = self:GetCenter()
        local cx, cy = UIParent:GetCenter()
        if type(x) == "number" and type(cx) == "number" then
            local scale = self:GetScale()
            Saved().x, Saved().y = x * scale - cx, y * scale - cy
            ApplyPlace()
        end
    end)
    ApplyPlace()

    frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -PADDING)
    frame.title:SetJustifyH("CENTER")
    frame.title:SetText(Core.Gradient(Text.SUMMON_TITLE, Core.GRADIENT_TITLE))
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -(PADDING + TITLE_HEIGHT - 4))
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -(PADDING + TITLE_HEIGHT - 4))
    divider:SetSize(1, 1)
    divider:SetColorTexture(0.78, 0.65, 0.35, 0.45)
    frame.divider = divider

    local close = CreateFrame("Button", "NecrosisOGSummonClose", frame, "UIPanelCloseButton")
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() Summon.Close() end)
    ns.Sounds.Button(close)
    frame.close = close

    queueBody = CreateFrame("Frame", nil, frame)
    queueBody:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -BODY_TOP)
    queueBody:SetSize(INNER_WIDTH, LIST_TOP + HEAD_HEIGHT)

    header = {}
    header.helpers = queueBody:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    header.helpers:SetPoint("TOPLEFT", queueBody, "TOPLEFT", 2, 0)
    header.shards = queueBody:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    header.shards:SetPoint("TOPLEFT", queueBody, "TOPLEFT", 92, 0)
    header.shards:SetTextColor(0.9, 0.6, 1)
    header.locked = queueBody:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
    header.locked:SetPoint("TOPRIGHT", queueBody, "TOPRIGHT", -2, 0)
    header.locked:SetText(Text.SUMMON_CHAT_LOCKED)

    nextButton = CreateFrame("Button", "NecrosisOGSummonNext", queueBody,
        "SecureActionButtonTemplate, UIPanelButtonTemplate")
    nextButton:SetSize(INNER_WIDTH, NEXT_HEIGHT)
    nextButton:SetPoint("TOP", queueBody, "TOP", 0, -(HEADER_HEIGHT + 4))
    nextButton:SetText(Text.SUMMON_NEXT)
    nextButton:RegisterForClicks("AnyUp")
    nextButton:SetAttribute("useOnKeyDown", false)
    nextButton:SetScript("PreClick", Prepare)
    ns.Sounds.Button(nextButton)

    scroll = CreateFrame("ScrollFrame", "NecrosisOGSummonScroll", queueBody, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", queueBody, "TOPLEFT", 0, -LIST_TOP)
    scroll:SetSize(INNER_WIDTH, HEAD_HEIGHT)
    if scroll.ScrollBar then
        scroll.ScrollBar:ClearAllPoints()
        scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, -16)
        scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 16)
        scroll.ScrollBar:Hide()
    end

    optionsBody = CreateFrame("Frame", nil, frame)
    optionsBody:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -BODY_TOP)
    optionsHeight = ns.SettingsWindow.NewSummonOptions(optionsBody, INNER_WIDTH) or DEFAULT_OPTIONS_HEIGHT
    optionsBody:SetSize(INNER_WIDTH, optionsHeight)
    optionsBody:Hide()

    local footerRule = frame:CreateTexture(nil, "ARTWORK")
    footerRule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, PADDING + FOOTER_HEIGHT + FOOTER_GAP)
    footerRule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, PADDING + FOOTER_HEIGHT + FOOTER_GAP)
    footerRule:SetSize(1, 1)
    footerRule:SetColorTexture(1, 1, 1, 0.16)
    frame.footerRule = footerRule

    toggleButton = CreateFrame("Button", "NecrosisOGSummonOptions", frame, "UIPanelButtonTemplate")
    toggleButton:SetSize(104, FOOTER_HEIGHT)
    toggleButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, PADDING)
    toggleButton:SetText(Text.SUMMON_OPTIONS)
    toggleButton:SetScript("OnClick", function()
        if InCombat() then return end
        SetOptionsOpen(not optionsOpen)
    end)
    ns.Sounds.Button(toggleButton)

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(INNER_WIDTH, 1)
    scroll:SetScrollChild(content)

    local function Heading()
        local line = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        line:Hide()
        return line
    end
    for _, key in ipairs({ "waiting", "summoned", "away" }) do
        local section = { rows = {} }
        if key ~= "away" then section.heading = Heading() end
        for i = 1, Core.SUMMON_ROWS do section.rows[i] = NewRow("NecrosisOGSummonRow_" .. key .. i, key) end
        sections[key] = section
    end
    emptyNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    emptyNote:SetText(Text.SUMMON_NOBODY)
    emptyNote:Hide()
    awayHead = CreateFrame("Button", nil, content)
    awayHead:SetSize(INNER_WIDTH, HEAD_HEIGHT)
    awayHead.line = awayHead:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    awayHead.line:SetPoint("LEFT", awayHead, "LEFT", 0, 0)
    function awayHead:SetText(text) self.line:SetText(text) end
    awayHead:SetScript("OnClick", function()
        awayChoice = not AwayOpen()
        Layout()
    end)
    ns.Sounds.Button(awayHead)

    frame:SetAttribute("_onstate-combat", [[ if newstate == "yes" then self:Hide() end ]])
    RegisterStateDriver(frame, "combat", "[combat] yes; no")
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, frame:GetName()) end
    frame:Hide()
    frame:SetScript("OnHide", function()
        if InCombat() or (UIParent.IsShown and not UIParent:IsShown()) then return end
        wanted, demoOpened = false, false
        if optionsOpen then
            optionsOpen = false
            queueBody:Show()
            optionsBody:Hide()
            toggleButton:SetText(Text.SUMMON_OPTIONS)
        end
        UpdateCues()
        UpdateTicker()
    end)
    ns.Sounds.Window(frame)
end

local function Shown() return frame ~= nil and frame:IsShown() == true end

local function Show(byPlayer)
    if InCombat() then return false end
    if not frame then Create() end
    wanted, manual = true, byPlayer == true
    if optionsOpen then
        optionsOpen = false
        queueBody:Show()
        optionsBody:Hide()
        toggleButton:SetText(Text.SUMMON_OPTIONS)
    end
    frame:Show()
    Layout()
    UpdateCues()
    UpdateTicker()
    return true
end

function Summon.Close()
    wanted, pendingAuto, demoOpened = false, false, false
    if frame and not InCombat() then frame:Hide() end
    UpdateCues()
    UpdateTicker()
end

function Summon.Toggle()
    if InCombat() then return ns.Print(Text.SUMMON_AFTER_COMBAT) end
    if Shown() then return Summon.Close() end
    Show(true)
end

-- open for new request, wait if in combat
local function AutoOpen()
    if Saved().autoOpen ~= true or Shown() then return end
    if InCombat() then
        pendingAuto = true
    elseif not (ns.Welcome and ns.Welcome.IsActive and ns.Welcome.IsActive()) then
        Show(false)
    end
end

UpdateCues = function()
    local waiting = #(Core.SummonLists(Queue()))
    for _, cue in ipairs(cues) do
        local show = waiting > 0 and (not cue.when or cue.when())
        ns.Rings.ShowGlow(cue.glow, show)
        cue.count:SetText(show and tostring(waiting) or "")
        if cue.cooldownText and show ~= cue.playing then cue.cooldownText:SetAlpha(show and 0 or 1) end
        if show and not cue.playing then cue.pulse:Play() elseif not show and cue.playing then cue.pulse:Stop() end
        cue.playing = show
    end
end

function Summon.RefreshCues() UpdateCues() end

-- glow with count on button while someone waiting
function Summon.AddCue(parent, when, cooldownText)
    local cue = { glow = ns.Rings.NewGlow(parent, "ritualOfSummoning"), when = when, cooldownText = cooldownText }
    if cooldownText then cue.glow:SetFrameLevel(cooldownText:GetFrameLevel() + 1) end
    cue.pulse = cue.glow:CreateAnimationGroup()
    cue.pulse:SetLooping("BOUNCE")
    ns.Bars.AlphaStep(cue.pulse, 1, Core.BAR_PULSE_DIM, Core.BAR_PULSE)
    cue.count = cue.glow:CreateFontString(nil, "OVERLAY", ns.Media.Font("GameFontNormal", nil, true))
    cue.count:SetPoint("CENTER", cue.glow, "CENTER", 0, 0)
    ns.Rings.ShowGlow(cue.glow, false)
    cues[#cues + 1] = cue
    return cue
end

-- apply time and group change to queue then redraw
function Summon.Update()
    local list = Queue()
    if not demo and #list.entries > 0 then
        local members = Members()
        Core.SummonTick(list, GetTime(), function(entry) return Find(members, entry) end)
    end
    if Shown() and not manual and #list.entries == 0 and not demo then return Summon.Close() end
    Layout()
    UpdateCues()
    UpdateTicker()
end

UpdateTicker = function()
    local run = not demo and (Shown() or #queue.entries > 0)
    if run and not ticker then
        ticker = C_Timer.NewTicker(TICK, Summon.Update)
    elseif not run and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local CHANNELS = {
    CHAT_MSG_WHISPER = "whisper", CHAT_MSG_PARTY = "group", CHAT_MSG_PARTY_LEADER = "group",
    CHAT_MSG_RAID = "group", CHAT_MSG_RAID_LEADER = "group", CHAT_MSG_INSTANCE_CHAT = "group",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "group",
}

-- check chat message from group member
local function OnChat(channel, message, sender, guid)
    if not Enabled() or Saved().listen[channel] ~= true or IsSecret(message) or not Stones.InGroup() then return end
    if not Core.SummonMatches(message, Core.SummonWords(Saved().requestWords)) then return end
    if IsSecret(guid) then guid = nil end
    if IsSecret(sender) then sender = nil end
    local member = Find(Members(), { guid = guid, name = sender })
    if not member then return end
    if Core.SummonRequest(queue, member, GetTime()) then
        if not demo then
            AutoOpen()
            Summon.Update()
        end
    end
end

local function OnSummonStatus(unit)
    if not Enabled() or IsSecret(unit) or type(unit) ~= "string" or not C_IncomingSummon then return end
    if Plain(UnitIsUnit, unit, "player") == true then return end
    local status = Plain(C_IncomingSummon.IncomingSummonStatus, unit)
    if type(status) ~= "number" then return end
    local member = Find(Members(), { guid = Plain(UnitGUID, unit), name = Stones.UnitFullName(unit) })
    if member and not demo and Core.SummonStatus(queue, member, status, GetTime()) then Summon.Update() end
end

local function Empty()
    queue = Core.NewSummonQueue()
    pendingAuto = false
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    local channel = CHANNELS[event]
    if channel then
        local message, sender = ...
        OnChat(channel, message, sender, (select(12, ...)))
    elseif event == "INCOMING_SUMMON_CHANGED" then
        OnSummonStatus((...))
    elseif event == "PLAYER_REGEN_ENABLED" then
        if demo then return end
        if wanted and not Shown() then
            if manual or #queue.entries > 0 then
                frame:Show()
            else
                wanted = false
            end
        elseif pendingAuto and #(Core.SummonLists(queue)) > 0 then
            AutoOpen()
        end
        pendingAuto = false
        Summon.Update()
    elseif event == "GROUP_ROSTER_UPDATE" then
        if demo then return end
        if not Stones.InGroup() then
            Empty()
            Summon.Close()
        else
            Summon.Update()
        end
    end
end)

table.insert(ns.onSphere, function()
    started = true
    for event in pairs(CHANNELS) do events:RegisterEvent(event) end
    for _, event in ipairs({ "INCOMING_SUMMON_CHANGED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE" }) do
        events:RegisterEvent(event)
    end
end)

table.insert(ns.onRecall, function()
    local saved, default = Saved(), Core.DEFAULTS.summon
    saved.x, saved.y = default.x, default.y
    if frame and not InCombat() then ApplyPlace() end
end)

table.insert(ns.onDemoData, function(on)
    if on then
        if not started then return end
        ns.DemoEvery(Core.DEMO.summon.restart, function(now)
            demo = Core.DemoSummon(now, Text.DEMO_ZONE)
            Layout()
            UpdateCues()
        end)
        ns.DemoEvery(TICK, function() Layout() end)
        if Saved().autoOpen == true and not Shown() then
            AutoOpen()
            demoOpened = Shown()
        end
        UpdateTicker()
    elseif demo then
        demo = nil
        if demoOpened then
            Summon.Close()
        else
            Summon.Update()
        end
    end
end)

Summon.Frame = function() return frame end
Summon.QueueBody = function() return queueBody end
Summon.OptionsBody = function() return optionsBody end
Summon.Queue = function() return Queue() end
Summon.Rows = function(key) return sections[key] and sections[key].rows end
Summon.NextButton = function() return nextButton end
Summon.AwayHead = function() return awayHead end
Summon.Header = function() return header end
Summon.Cues = function() return cues end

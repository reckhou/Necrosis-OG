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

-- settings window, open from game options, sphere right click or /nog
local _, ns = ...
local Core, Text = ns.Core, ns.Text

local Window = {}
ns.SettingsWindow = Window

local WIDTH, HEIGHT = 384, 512
local WINDOW_ART = "Interface\\PaperDollInfoFrame\\UI-Character-General-"
local PAGE_LEFT, PAGE_TOP = 30, -82
local PAGE_WIDTH, PAGE_HEIGHT = 290, 346
Window.PAGE_WIDTH, Window.PAGE_HEIGHT = PAGE_WIDTH, PAGE_HEIGHT
local TAB_GAP = 12
local TAB_TOP = -44
local TAB_ART = "Interface\\SpellBook\\SpellBook-SkillLineTab"
local ROW_HEIGHT = 18
local MIN_ROW_HEIGHT = 16
local SLIDER_WIDTH = 120
local RIGHT_COLUMN = 150
local SLIDER_RIGHT = 165
local DRAG_PURPLE = { 0xFF / 255, 0x50 / 255, 0xFF / 255 }
local DRAG_TEXT = { 0xF4 / 255, 0xE6 / 255, 0xFF / 255 }

local frame, pageTitle, afterCombatNote
local CreateLockButton
local pages, tabs = {}, {}
local controls = {}
local current = 1

local Plain, InCombat, SpellName = ns.Game.Plain, ns.Game.InCombat, ns.Game.SpellName

-- show note when some change wait combat end
local function UpdateNote()
    if not afterCombatNote then return end
    local waiting = (ns.Buttons and ns.Buttons.IsPending and ns.Buttons.IsPending())
        or (ns.Sphere and ns.Sphere.LayoutPending and ns.Sphere.LayoutPending())
    afterCombatNote:SetShown(waiting == true)
end

local function RefreshAll()
    for _, control in ipairs(controls) do control:Refresh() end
    UpdateNote()
end

-- apply the change then refresh all controls
local function Changed(apply)
    return function(...)
        apply(...)
        RefreshAll()
    end
end

local function Label(parent, text, x, y, font)
    local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

-- check box, get() return setting and set(on) change it
local function Check(page, x, y, text, get, set, labelWidth)
    local box = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    box:SetSize(26, 26)
    box:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    box.label = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    box.label:SetPoint("LEFT", box, "RIGHT", 2, 0)
    box.label:SetJustifyH("LEFT")
    box.label:SetWidth(labelWidth or (PAGE_WIDTH - x - 30))
    box.label:SetText(text)
    box:SetScript("OnClick", function(self) Changed(set)(self:GetChecked() == true) end)
    function box:Refresh() self:SetChecked(get() == true) end
    controls[#controls + 1] = box
    return box
end

-- slider with value in the title, opts.snap is a value drag will stick to, opts.wheel is mouse wheel move one step
local function Slider(page, x, y, text, low, high, step, get, set, kind, opts)
    local slider = CreateFrame("Slider", nil, page, "UISliderTemplateWithLabels")
    slider:SetSize(SLIDER_WIDTH, 16)
    if slider.Text.SetFontObject then slider.Text:SetFontObject("GameFontHighlightSmall") end
    slider:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    local function Show(value)
        if kind == "percent" then return string.format(Text.SETTINGS_PERCENT_VALUE, value) end
        if kind == "times" then return string.format(Text.SETTINGS_TIMES_VALUE, value) end
        return tostring(value)
    end
    slider.Low:SetText(Show(low))
    slider.High:SetText(Show(high))
    local function Title(value) slider.Text:SetText(string.format(Text.SETTINGS_VALUE, text, Show(value))) end
    slider:SetScript("OnValueChanged", function(self, value)
        if self.refreshing then return end
        value = Core.RoundToStep(value, step)
        if opts and opts.snap and not self.stepping and math.abs(value - opts.snap) < (high - low) / SLIDER_WIDTH then
            value = opts.snap
            self.refreshing = true
            self:SetValue(value)
            self.refreshing = false
        end
        Title(value)
        if math.abs(value - get()) > step / 2 then Changed(set)(value) end
    end)
    if opts and opts.wheel then
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta)
            self.stepping = true
            self:SetValue(math.max(low, math.min(high, Core.RoundToStep(self:GetValue() + delta * step, step))))
            self.stepping = false
        end)
    end
    function slider:Refresh()
        self.refreshing = true
        self:SetValue(get())
        self.refreshing = false
        Title(get())
    end
    controls[#controls + 1] = slider
    return slider
end

-- grey out control while on() is false
local function GreyedBy(widget, on)
    local refresh = widget.Refresh
    function widget:Refresh()
        refresh(self)
        local enabled = on() == true
        self:SetAlpha(enabled and 1 or 0.5)
        if self.pageLabel then self.pageLabel:SetAlpha(enabled and 1 or 0.5) end
        if type(self.SetEnabled) == "function" then pcall(self.SetEnabled, self, enabled) end
    end
    return widget
end

-- dropdown list of the game
local function Dropdown(page, x, y, text, options, get, set, width, maxRows)
    local label = text and Label(page, text, x, y)
    local dropdown = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width or 150)
    dropdown.pageLabel = label
    dropdown:SetPoint("TOPLEFT", page, "TOPLEFT", x, text and y - 14 or y)
    dropdown:SetupMenu(function(_, root)
        local choices = type(options) == "function" and options() or options
        if not maxRows or #choices > maxRows then
            root:SetScrollMode(maxRows and 20 * maxRows or 320)
        end
        for _, option in ipairs(choices) do
            root:CreateRadio(option[2], function(value) return value == get() end,
                function(value) Changed(set)(value) end, option[1])
        end
    end)
    function dropdown:Refresh() self:GenerateMenu() end
    controls[#controls + 1] = dropdown
    return dropdown
end

local function PushButton(page, x, y, text, onClick, width, enabled)
    local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    button:SetSize(width or 170, 22)
    button:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", function() Changed(onClick)() end)
    if enabled then
        function button:Refresh() self:SetEnabled(enabled() == true) end
        controls[#controls + 1] = button
    end
    return button
end

local MENUS = {
    { key = "utility", title = Text.SET_BUTTON_UTILITY, list = Core.UTILITY_MENU },
    { key = "curses", title = Text.SET_BUTTON_CURSES, list = Core.CURSE_MENU },
    { key = "demons", title = Text.SET_BUTTON_DEMONS, list = Core.DEMON_MENU },
}
local MENU_LISTS = {}
for _, menu in ipairs(MENUS) do MENU_LISTS[menu.key] = menu.list end
local selectedMenu = MENUS[1].key

local function EntrySpell(entry)
    local known = Core.PickSpell(entry.keys, ns.Buttons.IsKnown)
    return known or Core.SPELLS[entry.keys[1]][1], known ~= nil
end

-- list of rows to drag and reorder, scroll if too long
local function OrderList(page, x, y, width, height, source)
    local rowHeight = ROW_HEIGHT
    if height < source.rows * ROW_HEIGHT and height >= source.rows * MIN_ROW_HEIGHT then
        rowHeight = math.floor(height / source.rows)
    end
    local fits = height >= source.rows * rowHeight
    local scroll = fits and CreateFrame("Frame", nil, page) or CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetSize(width, height)
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width, rowHeight)
    if fits then
        child:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    else
        scroll:SetScrollChild(child)
        scroll.scrollBarHideable = true
    end
    local Step
    local list = { rows = {}, scroll = scroll, child = child, count = source.rows }
    local function PlaceRow(row)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -row.y)
    end
    local function CursorDown()
        if type(GetCursorPosition) ~= "function" then return nil end
        local top, scale = child:GetTop(), child:GetEffectiveScale()
        if not top or not scale or scale == 0 then return nil end
        local _, cursorY = GetCursorPosition()
        return top - cursorY / scale
    end
    local function Follow()
        local from = list.from
        if not from then return end
        local down = CursorDown()
        if not down then return end
        local last = math.max(1, list.count)
        list.target = scroll:IsMouseOver() and Core.DragSlot(down, rowHeight, last) or from
        local dragged = list.rows[from]
        dragged.y = math.max(0, math.min((last - 1) * rowHeight, down - rowHeight / 2))
        PlaceRow(dragged)
    end
    Step = function(_, dt)
        Follow()
        local instant = ns.AnimationsOn and not ns.AnimationsOn()
        local speed = ns.AnimationSpeed and ns.AnimationSpeed() or 1
        local settled = list.from == nil
        for place, row in ipairs(list.rows) do
            if not row:IsShown() then
                if row.y ~= (place - 1) * rowHeight then
                    row.y = (place - 1) * rowHeight
                    PlaceRow(row)
                end
            elseif place ~= list.from then
                local goal = (Core.DragPlace(place, list.from or place, list.target or place) - 1) * rowHeight
                if row.y ~= goal then
                    row.y = instant and goal or Core.EaseToward(row.y, goal, dt, speed)
                    PlaceRow(row)
                    if row.y ~= goal then settled = false end
                end
            end
        end
        if settled then child:SetScript("OnUpdate", nil) end
    end
    for i = 1, source.rows do
        local row = CreateFrame("Button", nil, child)
        row:SetSize(width - 10, rowHeight)
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * rowHeight)
        row:RegisterForDrag("LeftButton")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(rowHeight - 2, rowHeight - 2)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.name:SetJustifyH("LEFT")
        row.tag = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        row.tag:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.tag:SetJustifyH("RIGHT")
        row:RegisterForClicks("RightButtonUp")
        row:SetScript("OnClick", function(self)
            if source.toggle then
                source.toggle(self.index)
                RefreshAll()
            end
        end)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row:GetHighlightTexture():SetBlendMode("ADD")
        row.index = i
        row.dragBand = row:CreateTexture(nil, "BACKGROUND")
        row.dragBand:SetAllPoints(row)
        row.dragBand:SetColorTexture(DRAG_PURPLE[1], DRAG_PURPLE[2], DRAG_PURPLE[3], 0.3)
        row.dragBand:Hide()
        row.y = (i - 1) * rowHeight
        row:SetScript("OnDragStart", function(self)
            list.from, list.target = self.index, self.index
            self.dragBand:Show()
            self.name:SetTextColor(DRAG_TEXT[1], DRAG_TEXT[2], DRAG_TEXT[3])
            self.baseLevel = self:GetFrameLevel()
            self:SetFrameLevel(self.baseLevel + 20)
            child:SetScript("OnUpdate", Step)
        end)
        row:SetScript("OnDragStop", function(self)
            self.dragBand:Hide()
            self.name:SetTextColor(1, 1, 1)
            self:SetFrameLevel(self.baseLevel or self:GetFrameLevel())
            local from = list.from
            if not from then return end
            Follow()
            local target = list.target
            list.from, list.target = nil, nil
            if target and target ~= from and scroll:IsMouseOver() then
                local heights = {}
                for place, other in ipairs(list.rows) do heights[place] = other.y end
                source.move(from, target)
                RefreshAll()
                for place, other in ipairs(list.rows) do
                    other.y = heights[Core.DragSource(place, from, target)] or other.y
                    PlaceRow(other)
                end
            end
            child:SetScript("OnUpdate", Step)
        end)
        list.rows[i] = row
    end
    function list:Refresh()
        local entries = source.entries()
        child:SetHeight(math.max(1, #entries) * rowHeight)
        self.count = #entries
        for i, row in ipairs(self.rows) do
            local entry = entries[i]
            if entry then
                if entry.atlas then
                    row.icon:SetAtlas(entry.atlas)
                else
                    row.icon:SetTexture(entry.icon)
                    row.icon:SetTexCoord(0, 1, 0, 1)
                end
                row.name:SetText(entry.name)
                row.icon:SetDesaturated(not entry.known)
                row.name:SetAlpha(entry.known and 1 or 0.5)
                row.tag:SetText(entry.tag or "")
                row:Show()
            else
                row:Hide()
            end
        end
    end
    controls[#controls + 1] = list
    return list
end

local function MenuSource()
    local most = 0
    for _, menu in ipairs(MENUS) do most = math.max(most, #menu.list) end
    return {
        rows = most,
        entries = function()
            local entries = {}
            for i, entry in ipairs(Core.OrderMenu(MENU_LISTS[selectedMenu], ns.db.buttons.menuOrder[selectedMenu])) do
                local id, known = EntrySpell(entry)
                local off = Core.MenuEntryOff(ns.db.buttons.menuOff[selectedMenu], entry)
                entries[i] = { name = SpellName(id) or tostring(id),
                    icon = Plain(C_Spell.GetSpellTexture, id), known = known and not off,
                    tag = off and Text.SET_MENU_OFF or (not known and Text.SET_MENU_UNLEARNED) or nil }
            end
            return entries
        end,
        move = function(from, to) Window.MoveSpell(selectedMenu, from, to) end,
        toggle = function(place) Window.ToggleSpell(selectedMenu, place) end,
    }
end

local SLOTS = {
    firestone = { Text.SET_BUTTON_FIRESTONE, "FirestoneButton-01", "FirestoneButton-02" },
    spellstone = { Text.SET_BUTTON_SPELLSTONE, "SpellstoneButton-01", "SpellstoneButton-02" },
    healthstone = { Text.SET_BUTTON_HEALTHSTONE, "HealthstoneButton-01", "HealthstoneButton-02" },
    soulstone = { Text.SET_BUTTON_SOULSTONE, "SoulstoneButton-01", "SoulstoneButton-02" },
    utility = { Text.SET_BUTTON_UTILITY, "BuffMenuButton-01" },
    mount = { Text.SET_BUTTON_MOUNT, "MountButton-01" },
    demons = { Text.SET_BUTTON_DEMONS, "PetMenuButton-01" },
    curses = { Text.SET_BUTTON_CURSES, "CurseMenuButton-01" },
    shards = { Text.SET_BUTTON_SHARDS, "ShardDestroy-01" },
}

local function RingSource()
    return {
        rows = #Core.BUTTON_SLOTS,
        entries = function()
            local entries = {}
            for i, slot in ipairs(Core.OrderSlots(ns.db.buttons.ringOrder)) do
                local off = ns.db.buttons.show[slot] == false
                local usable = ns.Buttons.SlotUsable(slot)
                local on = usable and not off
                local icon, atlas = Core.UiTexture(SLOTS[slot][2]), nil
                if SLOTS[slot][3] then
                    if on then icon = Core.UiTexture(SLOTS[slot][3]) end
                else
                    local kind, value = ns.Buttons.SlotIcon(slot)
                    if kind == "atlas" then atlas = value elseif kind == "texture" then icon = value end
                end
                entries[i] = { name = SLOTS[slot][1], icon = icon, atlas = atlas,
                    known = on, tag = off and Text.SET_MENU_OFF or (not usable and Text.SET_BUTTON_UNUSABLE) or nil }
            end
            return entries
        end,
        move = function(from, to)
            ns.SetSetting("buttons.ringOrder", Core.MoveSlot(ns.db.buttons.ringOrder, from, to))
        end,
        toggle = function(place)
            local slot = Core.OrderSlots(ns.db.buttons.ringOrder)[place]
            if slot then ns.Buttons.SetShown(slot, ns.db.buttons.show[slot] == false) end
        end,
    }
end

-- part of page show only when shown() true
local function Section(page, shown)
    local section = CreateFrame("Frame", nil, page)
    section:SetAllPoints(page)
    function section:Refresh() self:SetShown(shown() == true) end
    controls[#controls + 1] = section
    return section
end

function Window.MoveSpell(key, from, to)
    ns.SetSetting("buttons.menuOrder." .. key, Core.MoveInOrder(MENU_LISTS[key], ns.db.buttons.menuOrder[key], from, to))
    RefreshAll()
end

-- right click spell to switch it off or on
function Window.ToggleSpell(key, place)
    local entry = Core.OrderMenu(MENU_LISTS[key], ns.db.buttons.menuOrder[key])[place]
    if not entry or not select(2, EntrySpell(entry)) then return end
    local switchOff = not Core.MenuEntryOff(ns.db.buttons.menuOff[key], entry)
    ns.SetSetting("buttons.menuOff." .. key .. "." .. Core.MenuEntryId(entry), switchOff or nil)
    RefreshAll()
end

local db = function() return ns.db end

local DIRECTIONS = {
    { "up", Text.SET_DIRECTION_UP }, { "down", Text.SET_DIRECTION_DOWN },
    { "left", Text.SET_DIRECTION_LEFT }, { "right", Text.SET_DIRECTION_RIGHT },
}
local GROWTH = { { "up", Text.SET_DIRECTION_UP }, { "down", Text.SET_DIRECTION_DOWN } }

-- one lock for all movable things
local function SetLocked(on)
    ns.SetLocked(on)
    if ns.Timers.Refresh then ns.Timers.Refresh() end
    if ns.Alerts.Refresh then ns.Alerts.Refresh() end
end

-- small info icon with tooltip after the heading
local function InfoIcon(page, after, title, lines)
    local icon = CreateFrame("Frame", nil, page)
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", after, "RIGHT", 4, 0)
    icon:EnableMouse(true)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexture("Interface\\FriendsFrame\\InformationIcon")
    ns.Tips.Attach(icon, function(tooltip)
        ns.Tips.Title(tooltip, title)
        for _, line in ipairs(lines) do ns.Tips.Line(tooltip, line) end
    end, "ANCHOR_RIGHT", true)
    return icon
end

local MACRO_GAP = 28

-- icon to drag on action bar
local function MacroIcon(page, x, y, key)
    local icon = CreateFrame("Button", nil, page)
    icon:SetSize(26, 26)
    icon:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon:RegisterForDrag("LeftButton")
    icon:SetScript("OnDragStart", function() ns.Buttons.PickupFocusMacro(key) end)
    icon:SetScript("OnClick", function() ns.Buttons.PickupFocusMacro(key) end)
    local spells = Core.SPELLS[Core.STONE_MACRO_SPELLS[key] or key]
    ns.Tips.Attach(icon, function(tooltip)
        ns.Tips.Title(tooltip, (key == "hearthstone" and Text.HEARTHSTONE) or (key == "healthstone" and Text.BIND_HEALTHSTONE)
            or SpellName(spells[1]) or key)
        ns.Tips.Line(tooltip, Text.TIP_MACRO_DRAG)
        if key == "sacrifice" then ns.Tips.Line(tooltip, Text.TIP_SACRIFICE_MACRO) end
        if Core.CURSE_MACROS[key] then
            ns.Tips.Line(tooltip, string.format(Text.ACT_THEN, SpellName(Core.SPELLS.amplifyCurse[1]) or "?", SpellName(spells[1]) or key))
        end
    end, "ANCHOR_RIGHT", true)
    function icon:Refresh()
        if key == "hearthstone" then
            self.texture:SetTexture(Plain(C_Item.GetItemIconByID, Core.HEARTHSTONE_ITEM))
            return
        end
        self.texture:SetTexture(Plain(C_Spell.GetSpellTexture, spells[1]))
        self.texture:SetDesaturated(Core.HighestKnown(spells, Core.PET_SPELLS[key] and ns.PetKnows or ns.Buttons.IsKnown) == nil)
    end
    controls[#controls + 1] = icon
    return icon
end

-- section heading, one color per letter
local function Heading(page, text, y)
    return Label(page, Core.Gradient(text, Core.GRADIENT_HEADING), 0, y, "SystemFont_Shadow_Small_Outline")
end

local function GreyLabel(label, on)
    controls[#controls + 1] = { Refresh = function() label:SetAlpha(on() == true and 1 or 0.5) end }
    return label
end

local CONFIRM_DIALOGS = { positions = "NECROSIS_OG_RESET_POSITIONS", settings = "NECROSIS_OG_RESET_ALL",
    speech = "NECROSIS_OG_RESTORE_SPEECH" }

local confirmed = {}

-- ask yes or no before do action
local function Confirm(which, text, yes, onAccept, arg)
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return end
    local name = CONFIRM_DIALOGS[which]
    confirmed[which] = onAccept
    StaticPopupDialogs[name] = StaticPopupDialogs[name] or {
        text = text,
        button1 = yes,
        button2 = Text.SET_RESET_NO,
        OnAccept = function() if confirmed[which] then confirmed[which]() end end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
    }
    StaticPopup_Show(name, arg)
end

-- reset all setting after yes
function Window.ConfirmReset()
    Confirm("settings", Text.SET_RESET_CONFIRM, Text.SET_RESET_YES, function() ns.Sphere.ResetAll() end)
end

function Window.ConfirmPositions()
    Confirm("positions", Text.SET_RESET_POSITIONS_CONFIRM, Text.SET_RESET_YES, function() ns.Sphere.ResetPositions() end)
end

-- general tab
local function GeneralPage(page)
    Heading(page, Text.SET_HEAD_FOCUS, 0)
    Check(page, 0, -16, Text.SET_AUTO_FOCUS, function() return db().buttons.autoFocus == true end, function(on)
        ns.SetSetting("buttons.autoFocus", on)
    end)
    local macroHead = Heading(page, Text.SET_FOCUS_MACROS, -48)
    InfoIcon(page, macroHead, Text.SET_FOCUS_MACROS, { Text.TIP_MACROS_BARS, Text.TIP_MACROS_KEYS })
    local petIcons = {}
    for i, key in ipairs(Core.MACRO_ROW) do
        local icon = MacroIcon(page, 4 + MACRO_GAP * (i - 1), -64, key)
        if Core.PET_SPELLS[key] then petIcons[#petIcons + 1] = icon end
    end
    table.insert(ns.onSpellsChanged, function()
        for _, icon in ipairs(petIcons) do icon:Refresh() end
    end)

    Heading(page, Text.SET_HEAD_DISPLAY, -106)
    local animOn = function() return db().animation.on ~= false end
    Check(page, 0, -122, Text.SET_ANIMATE, animOn, function(on) ns.SetAnimationsOn(on) end)
    GreyedBy(Slider(page, SLIDER_RIGHT, -136, Text.SET_ANIM_SPEED, Core.ANIM_SPEED_MIN, Core.ANIM_SPEED_MAX,
        Core.ANIM_SPEED_STEP, function() return Core.ClampAnimSpeed(db().animation.speed) end,
        function(value) ns.SetAnimationSpeed(value) end, "times"), animOn)
    Check(page, 0, -150, Text.SET_TOOLTIPS, function() return db().tooltips ~= false end,
        function(on) ns.SetSetting("tooltips", on) end)
    Dropdown(page, 0, -178, Text.SET_FONT, ns.Media.FontChoices, function() return db().font end,
        function(value) ns.SetSetting("font", value) end, 138)
    local sizes = {}
    for i, size in ipairs(Core.TEXT_SIZES) do sizes[i] = { size, string.format(Text.SETTINGS_PERCENT_VALUE, size) } end
    Dropdown(page, RIGHT_COLUMN, -178, Text.SET_TEXT_SIZE, sizes, function() return Core.TextSizeOrDefault(db().textSize) end,
        function(value) ns.SetSetting("textSize", value) end, 138)
    Dropdown(page, 0, -218, Text.SET_BAR_TEXTURE, ns.Media.BarChoices, function() return db().barTexture end,
        function(value) ns.SetSetting("barTexture", value) end, 138)

    Heading(page, Text.SET_HEAD_TOOLS, -(PAGE_HEIGHT - 82))
    local demo = PushButton(page, 4, -(PAGE_HEIGHT - 64), Text.SET_DEMO_START, function() ns.SetDemo(not ns.demoData) end,
        138)
    function demo:Refresh() self:SetText(ns.demoData and Text.SET_DEMO_STOP or Text.SET_DEMO_START) end
    controls[#controls + 1] = demo
    PushButton(page, 4, -(PAGE_HEIGHT - 36), Text.SET_RESET_POSITIONS, function() Window.ConfirmPositions() end,
        138)
    PushButton(page, RIGHT_COLUMN - 2, -(PAGE_HEIGHT - 36), Text.SET_RESET_ALL, function() Window.ConfirmReset() end,
        138)
end

local function SpherePage(page)
    Slider(page, 5, -16, Text.SET_SPHERE_SCALE, Core.SCALE_MIN, Core.SCALE_MAX, Core.SCALE_STEP,
        function() return Core.ClampSphereScale(db().sphere.scale) end, function(value) ns.Sphere.SetScale(value) end, "percent")
    Slider(page, SLIDER_RIGHT, -16, Text.SET_SHARD_LIMIT, Core.SHARD_LIMIT_MIN, Core.SHARD_LIMIT_MAX, 1,
        function() return Core.ClampShardLimit(db().buttons.shardLimit) end, function(value) ns.Shards.SetLimit(value) end)
    Check(page, 0, -66, Text.SET_SHOW_COUNT, function() return db().sphere.showCount end, function(on)
        ns.SetSetting("sphere.showCount", on)
    end, SLIDER_RIGHT - 30)
    local lowShards = Section(page, function() return db().sphere.showCount == true end)
    Slider(lowShards, SLIDER_RIGHT, -74, Text.SET_LOW_SHARDS, 0, Core.SHARD_COUNT_MAX, 1,
        function() return Core.ClampThreshold(db().sphere.lowShards) end, function(value)
            ns.SetSetting("sphere.lowShards", value)
        end)
    local function ClickChoices()
        local choices = { { "none", Text.SET_CLICK_NONE }, { "bags", Text.SET_CLICK_BAGS } }
        for _, entry in ipairs(Core.UTILITY_MENU) do
            local id, known = EntrySpell(entry)
            local name = SpellName(id) or Core.MenuEntryId(entry)
            choices[#choices + 1] = { Core.MenuEntryId(entry), known and name or ("|cff808080" .. name .. "|r") }
        end
        return choices
    end
    for i, click in ipairs(Core.SPHERE_CLICKS) do
        local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
        Dropdown(page, column * RIGHT_COLUMN, -136 - row * 50, Text[click.text], ClickChoices,
            function() return Core.SphereClick(click.key, db().sphere.clicks[click.key]) end, function(value)
                ns.SetSetting("sphere.clicks." .. click.key, value)
            end, 138)
    end
    local skins = {}
    for i, skin in ipairs(Core.SKIN_LIST) do skins[i] = { skin, Text["SET_SKIN_" .. string.upper(skin)] } end
    Dropdown(page, 0, -236, Text.SET_SKIN, skins, function() return Core.SkinOrDefault(db().skin) end, function(value)
        ns.SetSetting("skin", value)
    end, 138)
end

local function ButtonsPage(page)
    Check(page, 0, 0, Text.SET_BUTTONS_RING, function() return not db().buttons.free end,
        function(on) ns.Buttons.SetFree(not on) end)

    Slider(page, SLIDER_RIGHT, -88, Text.SET_SIZE, Core.BUTTON_SIZE_MIN, Core.BUTTON_SIZE_MAX, Core.BUTTON_SIZE_STEP,
        function() return Core.ClampButtonSize(db().sphere.buttonSize) end, function(value)
            ns.SetSetting("sphere.buttonSize", value)
        end, "times")

    local ring = Section(page, function() return not db().buttons.free end)
    local function RingSlider(x, y, text, low, high, step, key, clamp, kind)
        Slider(ring, x, y, text, low, high, step, function() return clamp(db().sphere[key]) end, function(value)
            ns.SetSetting("sphere." .. key, value)
        end, kind, { snap = Core.DEFAULTS.sphere[key], wheel = true })
    end
    RingSlider(5, -40, Text.SET_ROTATION, Core.ROTATION_MIN, Core.ROTATION_MAX, Core.ROTATION_STEP, "rotation",
        Core.ClampRotation)
    RingSlider(SLIDER_RIGHT, -40, Text.SET_SPACING, Core.SPACING_MIN, Core.SPACING_MAX, Core.SPACING_STEP, "spacing",
        Core.ClampSpacing, "times")
    RingSlider(5, -88, Text.SET_DISTANCE, Core.DISTANCE_MIN, Core.DISTANCE_MAX, Core.DISTANCE_STEP, "distance",
        Core.ClampDistance, "times")
    Heading(ring, Text.SET_ORDER_HELP, -130)

    local free = Section(page, function() return db().buttons.free end)
    local hint = Label(free, Text.SET_BUTTONS_FREE_HINT, 0, -36, "GameFontHighlightSmall")
    hint:SetWidth(PAGE_WIDTH)
    PushButton(free, 4, -85, Text.SET_BUTTONS_RESET, function() ns.Buttons.ResetPlaces() end, 138)
    Label(free, Text.SET_BUTTONS_SWITCH, 0, -130, "GameFontHighlightSmall"):SetWidth(PAGE_WIDTH)

    OrderList(page, 0, -162, PAGE_WIDTH - 10, #Core.BUTTON_SLOTS * ROW_HEIGHT, RingSource())
end

local function MenusPage(page)
    Check(page, 0, 0, Text.SET_MENU_CLOSES, function() return db().buttons.menuCloses == true end, function(on)
        ns.SetSetting("buttons.menuCloses", on)
    end)
    local choices = {}
    for i, menu in ipairs(MENUS) do choices[i] = { menu.key, menu.title } end
    Dropdown(page, 0, -28, Text.SET_MENU_CHOOSE, choices, function() return selectedMenu end,
        function(value) selectedMenu = value end, 138)
    Dropdown(page, RIGHT_COLUMN, -28, Text.SET_MENU_DIRECTION, DIRECTIONS,
        function() return Core.MenuDirection(selectedMenu, db().buttons.menuDirection[selectedMenu]) end, function(value)
            ns.SetSetting("buttons.menuDirection." .. selectedMenu, value)
        end, 138)
    local function ShiftSlider(x, text, axis)
        Slider(page, x, -84, text, Core.MENU_SHIFT_MIN, Core.MENU_SHIFT_MAX, Core.MENU_SHIFT_STEP, function()
            local shift = db().buttons.menuOffset and db().buttons.menuOffset[selectedMenu]
            return select(axis, Core.MenuShift(shift))
        end, function(value)
            ns.Buttons.SetMenuShift(selectedMenu, axis, value)
        end)
    end
    ShiftSlider(5, Text.SET_MENU_SHIFT_X, 1)
    ShiftSlider(SLIDER_RIGHT, Text.SET_MENU_SHIFT_Y, 2)
    Heading(page, Text.SET_ORDER_HELP, -114)
    OrderList(page, 0, -128, PAGE_WIDTH - 10, PAGE_HEIGHT - 128, MenuSource())
end

local SWITCH_STEP = RIGHT_COLUMN

local function KeyName(key) return SpellName(Core.SPELLS[key][1]) or key end

-- controls tab
local function ControlsPage(page)
    local timers = function() return db().timers end

    local focusOn = function() return timers().focusOn ~= false end
    Heading(page, Text.SET_FOCUS_ON, 0)
    Check(page, 0, -16, Text.SET_SHOW, focusOn, function(on)
        ns.SetSetting("timers.focusOn", on)
    end)
    GreyedBy(Slider(page, SLIDER_RIGHT, -30, Text.SET_SIZE, Core.SCALE_MIN, Core.SCALE_MAX, Core.SCALE_STEP,
        function() return Core.TimerScale(timers(), "focus") end, function(value) ns.Timers.SetScale("focus", value) end,
        "percent"), focusOn)
    GreyLabel(Heading(page, Text.SET_FOCUS_ICONS, -62), focusOn)
    for i, key in ipairs(Core.FOCUS_SWITCHES) do
        local name = KeyName(key)
        if key == "fear" then name = string.format(Text.SET_FOCUS_FEAR, name) end
        GreyedBy(Check(page, ((i - 1) % 2) * SWITCH_STEP, -74 - math.floor((i - 1) / 2) * 24, name,
            function() return timers().focusOff[key] ~= true end, function(on)
                ns.SetSetting("timers.focusOff." .. key, (not on) or nil)
            end), focusOn)
    end

    Heading(page, Text.SET_CONTROL_ON, -130)
    Check(page, 0, -146, Text.SET_SHOW, function() return timers().controlOn ~= false end, function(on)
        ns.SetSetting("timers.controlOn", on)
    end)
end

local SHOW_X = 200
local HEAD_TOP = -8
local HEAD_ROW = 28
local SECTION_SPACE = 8
local SLIDER_TOP = -14
local SECTION_ROW = 46
local TRACK_HEIGHT = 40 + #Core.ENEMY_SLOTS * ROW_HEIGHT

local SCROLL_BAR_X = 4

local function FamilyKnown(id) return ns.Buttons.IsKnown(id) or Plain(IsPlayerSpell, id) == true end

local function FamilyName(slot)
    if slot.key == "bane" then return Text.SET_ROW_BANE end
    if slot.key == "curse" then return Text.SET_ROW_CURSE end
    return KeyName(slot.keys[1])
end

local function FamilyIcon(slot)
    for _, key in ipairs(slot.keys) do
        local id = Core.HighestKnown(Core.SPELLS[key], ns.Buttons.IsKnown)
        if id then return Plain(C_Spell.GetSpellTexture, id) end
    end
    return Plain(C_Spell.GetSpellTexture, Core.SPELLS[slot.keys[1]][1])
end

local function FamilySource()
    local timers = function() return db().timers end
    return {
        rows = #Core.ENEMY_SLOTS,
        entries = function()
            local entries = {}
            for i, slot in ipairs(Core.OrderEnemySlots(timers().trackOrder)) do
                local off = timers().trackOff[slot.key] == true
                local known = Core.EnemySlotKnown(slot, FamilyKnown)
                entries[i] = { name = FamilyName(slot), icon = FamilyIcon(slot), known = known and not off,
                    tag = off and Text.SET_MENU_OFF or (not known and Text.SET_MENU_UNLEARNED) or nil }
            end
            return entries
        end,
        move = function(from, to)
            ns.SetSetting("timers.trackOrder", Core.MoveEnemySlot(timers().trackOrder, from, to))
        end,
        toggle = function(place)
            local slot = Core.OrderEnemySlots(timers().trackOrder)[place]
            if not slot or not Core.EnemySlotKnown(slot, FamilyKnown) then return end
            ns.SetSetting("timers.trackOff." .. slot.key, (timers().trackOff[slot.key] ~= true) or nil)
        end,
    }
end

local function NewSection(content, title, on, path, bodyHeight)
    local section = CreateFrame("Frame", nil, content)
    section:SetWidth(PAGE_WIDTH)
    Heading(section, title, HEAD_TOP)
    Check(section, SHOW_X, HEAD_TOP + 7, Text.SET_SHOW, on, function(value) ns.SetSetting(path, value) end, 60)
    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -HEAD_ROW)
    body:SetSize(PAGE_WIDTH, bodyHeight)
    section.body, section.on, section.bodyHeight = body, on, bodyHeight
    return section
end

local function OffsetSliders(body, y, low, high, get, set)
    Slider(body, 5, y, Text.SET_MENU_SHIFT_X, low, high, 1, function() return get("x") end,
        function(value) set("x", value) end)
    Slider(body, SLIDER_RIGHT, y, Text.SET_MENU_SHIFT_Y, low, high, 1, function() return get("y") end,
        function(value) set("y", value) end)
end

local function ReminderSection(content, title, saved, clamp, low, high)
    local look = function() return db().timers[saved] end
    local section = NewSection(content, title, function() return look().on ~= false end, "timers." .. saved .. ".on",
        -SLIDER_TOP + (clamp and SECTION_ROW or 0) + 30)
    local body = section.body
    Slider(body, 5, SLIDER_TOP, Text.SET_SIZE, Core.SCALE_MIN, Core.SCALE_MAX, Core.SCALE_STEP,
        function() return Core.ClampScale(look().scale) end,
        function(value) ns.SetSetting("timers." .. saved .. ".scale", Core.ClampScale(value)) end, "percent")
    Slider(body, SLIDER_RIGHT, SLIDER_TOP, Text.SET_BAR_OPACITY, Core.OPACITY_MIN, Core.OPACITY_MAX, Core.OPACITY_STEP,
        function() return Core.ClampOpacity(look().opacity) end,
        function(value) ns.SetSetting("timers." .. saved .. ".opacity", Core.ClampOpacity(value)) end, "percent")
    if not clamp then return section end
    local defaults = Core.DEFAULTS.timers[saved]
    OffsetSliders(body, SLIDER_TOP - SECTION_ROW, low, high, function(key) return clamp(look()[key], defaults[key]) end,
        function(key, value) ns.SetSetting("timers." .. saved .. "." .. key, clamp(value)) end)
    return section
end

local function DebuffsPage(page)
    local timers = function() return db().timers end
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    scroll:SetSize(PAGE_WIDTH, PAGE_HEIGHT)
    if scroll.ScrollBar then
        scroll.ScrollBar:ClearAllPoints()
        scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", SCROLL_BAR_X, -16)
        scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", SCROLL_BAR_X, 16)
    end
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PAGE_WIDTH, PAGE_HEIGHT)
    scroll:SetScrollChild(content)

    local multi = NewSection(content, Text.SET_MULTI_ON, function() return timers().multiOn ~= false end,
        "timers.multiOn", -SLIDER_TOP + 30)
    Slider(multi.body, 5, SLIDER_TOP, Text.SET_SIZE, Core.SCALE_MIN, Core.SCALE_MAX, Core.SCALE_STEP,
        function() return Core.TimerScale(timers(), "multi") end, function(value) ns.Timers.SetScale("multi", value) end,
        "percent")
    Dropdown(multi.body, RIGHT_COLUMN, 0, Text.SET_TIMER_GROWS, GROWTH,
        function() return timers().grow.multi == "down" and "down" or "up" end, function(value)
            ns.SetSetting("timers.grow.multi", value)
        end, 105)

    local target = ReminderSection(content, Text.SET_MISSING_TARGET, "targetReminder")
    local plate = ReminderSection(content, Text.SET_MISSING_PLATE, "plateReminder", Core.ClampPlateOffset,
        Core.PLATE_OFFSET_MIN, Core.PLATE_OFFSET_MAX)
    local glow = NewSection(content, Text.SET_BAR_HIGHLIGHT, function() return timers().barHighlight.on ~= false end,
        "timers.barHighlight.on", 0)

    local track = CreateFrame("Frame", nil, content)
    track:SetSize(PAGE_WIDTH, TRACK_HEIGHT)
    Heading(track, Text.SET_TRACK, HEAD_TOP)
    Label(track, Text.SET_ORDER_HELP, 0, HEAD_TOP - 16, "GameFontDisableSmall")
    OrderList(track, 0, HEAD_TOP - 32, PAGE_WIDTH - 10, #Core.ENEMY_SLOTS * ROW_HEIGHT, FamilySource())

    local layout = {}
    function layout:Refresh()
        local y = 0
        for _, section in ipairs({ multi, target, plate, glow }) do
            local on = section.on() == true
            section.body:SetShown(on)
            local height = HEAD_ROW + (on and section.bodyHeight or 0)
            section:ClearAllPoints()
            section:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            section:SetHeight(height)
            y = y + height + SECTION_SPACE
        end
        track:ClearAllPoints()
        track:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        content:SetHeight(y + TRACK_HEIGHT)
    end
    controls[#controls + 1] = layout
end

local function AlertRow(page, key, y)
    Check(page, 0, y, ns.AlertName(key), function() return db().alerts[key .. "On"] ~= false end, function(on)
        ns.SetSetting("alerts." .. key .. "On", on)
    end)
    Check(page, RIGHT_COLUMN, y, Text.SET_ALERT_SOUND, function() return db().alerts.sounds[key] ~= false end,
        function(on) ns.SetSetting("alerts.sounds." .. key, on) end)
end

-- size, spacing and opacity of bar
local function BarSliders(page, y, saved)
    Slider(page, 5, y - 46, Text.SET_BAR_OPACITY, Core.OPACITY_MIN, Core.OPACITY_MAX, Core.OPACITY_STEP,
        function() return Core.ClampOpacity(db()[saved].opacity) end, function(value)
            ns.SetSetting(saved .. ".opacity", Core.ClampOpacity(value))
        end, "percent")
    Slider(page, 5, y, Text.SET_BAR_SIZE, Core.SCALE_MIN, Core.SCALE_MAX, Core.SCALE_STEP,
        function() return Core.ClampScale(db()[saved].scale) end, function(value)
            ns.SetSetting(saved .. ".scale", Core.ClampScale(value))
        end, "percent")
    Slider(page, SLIDER_RIGHT, y, Text.SET_SPACING, Core.BAR_SPACING_MIN, Core.BAR_SPACING_MAX, Core.BAR_SPACING_STEP,
        function() return Core.ClampBarSpacing(db()[saved].spacing) end, function(value)
            ns.SetSetting(saved .. ".spacing", Core.ClampBarSpacing(value))
        end)
end

local BAR_BLOCK = 128

local function BarBlock(tab, title, saved)
    local on = function() return db()[saved].on ~= false end
    Heading(tab, title, HEAD_TOP)
    Check(tab, SHOW_X, HEAD_TOP + 7, Text.SET_SHOW, on, function(value) ns.SetSetting(saved .. ".on", value) end, 60)
    local body = Section(tab, on)
    BarSliders(body, HEAD_TOP - 30, saved)
    return body
end

local ALERT_ROW = 26

local function AlertsPage(tab)
    local page = BarBlock(tab, Text.SET_PROC_BAR, "procBar")
    for i, key in ipairs(Core.ALERT_KEYS) do AlertRow(page, key, -BAR_BLOCK - (i - 1) * ALERT_ROW) end
    local soundsTop = -BAR_BLOCK - #Core.ALERT_KEYS * ALERT_ROW - 8
    Check(page, 0, soundsTop, Text.SET_WARN_SOUND, function() return db().timers.warnSound end,
        function(on) ns.SetSetting("timers.warnSound", on) end)
    Check(page, 0, soundsTop - 26, Text.SET_SOUND_DEMON, function() return db().timers.sounds.enslaveDemon ~= false end,
        function(on) ns.SetSetting("timers.sounds.enslaveDemon", on) end)
    Check(page, 0, soundsTop - 52, Text.SET_SOUND_SOULSTONE, function() return db().alerts.sounds.soulstone ~= false end,
        function(on) ns.SetSetting("alerts.sounds.soulstone", on) end)
    local sacrificeOn = function() return db().alerts.sacrificeOn ~= false end
    Check(page, 0, soundsTop - 78, string.format(Text.SET_SACRIFICE_GLOW, SpellName(Core.SPELLS.sacrifice[1]) or "?"),
        sacrificeOn, function(on) ns.SetSetting("alerts.sacrificeOn", on) end, RIGHT_COLUMN - 30)
    local thresholds = {}
    for i, percent in ipairs(Core.SACRIFICE_THRESHOLDS) do
        thresholds[i] = { percent, string.format(Text.SET_SACRIFICE_AT, percent) }
    end
    GreyedBy(Dropdown(page, RIGHT_COLUMN, soundsTop - 78, nil, thresholds,
        function() return Core.SacrificeThresholdOrDefault(db().alerts.sacrificeAt) end,
        function(value) ns.SetSetting("alerts.sacrificeAt", value) end, PAGE_WIDTH - RIGHT_COLUMN), sacrificeOn)
end

local SAFE_CHOICES = { { "off", Text.SET_SAFE_OFF }, { "narrow", Text.SET_SAFE_NARROW }, { "wide", Text.SET_SAFE_WIDE } }
local SAFE_COLUMN = 140
local REMINDER_ROW = 27
local REMINDER_TOP = -BAR_BLOCK

local function RemindersPage(tab)
    local page = BarBlock(tab, Text.SET_REMINDER_BAR, "reminderBar")
    for i, key in ipairs(Core.CONTROL_BUTTON_KEYS) do
        local def = Core.CONTROL_BUTTONS[key]
        local name = def.label and Text[def.label]
            or SpellName(Core.SPELLS[def.spells[#def.spells]][1]) or key
        local y = REMINDER_TOP - (i - 1) * REMINDER_ROW
        Check(page, 0, y, name, function() return db().controlButtons[key].on ~= false end,
            function(on)
                ns.SetSetting("controlButtons." .. key .. ".on", on)
            end, SAFE_COLUMN - 30)
        if def.alwaysShow then
            Check(page, SAFE_COLUMN, y, Text.SET_ALERT_SOUND, function() return db().alerts.sounds[key] ~= false end,
                function(on) ns.SetSetting("alerts.sounds." .. key, on) end)
        else
            GreyedBy(Dropdown(page, SAFE_COLUMN, y, nil, SAFE_CHOICES,
                function() return Core.SafeLevelOrDefault(db().controlButtons[key].safeHide) end,
                function(value)
                    ns.SetSetting("controlButtons." .. key .. ".safeHide", value)
                end, PAGE_WIDTH - SAFE_COLUMN), function() return db().controlButtons[key].on ~= false end)
        end
    end
end

-- tall box for emote or line text
local function SpeechBox(page, x, y, height, get, set)
    local holder = CreateFrame("Frame", nil, page)
    holder:SetSize(PAGE_WIDTH - 5, height)
    holder:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    local background = holder:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.5)
    local box = CreateFrame("EditBox", nil, holder)
    box:SetMultiLine(true)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetWidth(PAGE_WIDTH - 17)
    box:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, -6)
    box:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -6, 6)
    box:SetAutoFocus(false)
    box:SetMaxLetters(255)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() box:SetFocus() end)
    local function Save(self)
        local text = string.gsub(self:GetText(), "[\r\n]+", " ")
        if text ~= get() then Changed(set)(text) end
    end
    box:SetScript("OnEnterPressed", function(self)
        Save(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", Save)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(get())
        self:SetCursorPosition(0)
        self:ClearFocus()
    end)
    function holder:Refresh()
        if box:HasFocus() then return end
        box:SetText(get())
        box:SetCursorPosition(0)
    end
    holder.box = box
    controls[#controls + 1] = holder
    return holder
end

local selectedSubject = Core.SPEECH_SUBJECTS[1]
local selectedPreset = {}

local function SubjectName(subject)
    if subject == "soulstone" then return Text.SET_BUTTON_SOULSTONE end
    if subject == "hearthstone" then return Text.HEARTHSTONE end
    if subject == "mount" then return Text.SET_BUTTON_MOUNT end
    return SpellName(Core.SPELLS[subject][1]) or subject
end

local function Presets() return Core.SpeechSets(selectedSubject, db().speech.sets, Text) end

-- preset shown now, 0 if subject has none
local function CurrentPreset()
    local count = #Presets()
    return math.min(selectedPreset[selectedSubject] or 1, count)
end

local function SpeechPage(page)
    local speechOn = function() return db().speech.on == true end
    local subjectOn = function() return db().speech.off[selectedSubject] ~= true end
    local channels = { { "SAY", Text.SET_CHANNEL_SAY }, { "YELL", Text.SET_CHANNEL_YELL }, { "PARTY", Text.SET_CHANNEL_PARTY } }
    GreyedBy(Dropdown(page, 0, 0, nil, channels, function() return db().speech.channel end,
        function(value) ns.SetSetting("speech.channel", value) end, 138), speechOn)
    Check(page, RIGHT_COLUMN, 0, Text.SET_SPEECH_ON, function() return db().speech.on end,
        function(on) ns.SetSetting("speech.on", on) end)

    local rest = Section(page, speechOn)
    local subjects = {}
    for i, subject in ipairs(Core.SPEECH_SUBJECTS) do subjects[i] = { subject, SubjectName(subject) } end
    Dropdown(rest, 0, -32, nil, subjects, function() return selectedSubject end,
        function(value) selectedSubject = value end, 138)
    Check(rest, RIGHT_COLUMN, -32, Text.SET_SPEECH_SUBJECT_ON, subjectOn, function(on)
        ns.SetSetting("speech.off." .. selectedSubject, (not on) or nil)
    end)

    local lines = Section(rest, subjectOn)
    local help = Label(lines, Text.SET_SPEECH_HELP, 0, -66, "GameFontHighlightSmall")
    help:SetWidth(PAGE_WIDTH)

    local PRESET_TOP = -94
    Dropdown(lines, 0, PRESET_TOP, Text.SET_SPEECH_PRESET, function()
        local options = {}
        for i, set in ipairs(Presets()) do
            options[i] = { i, string.format(Text.SET_SPEECH_PRESET_NAME, i, Core.PresetName(set, 40, Text.SET_SPEECH_EMPTY)) }
        end
        return options
    end, CurrentPreset, function(value) selectedPreset[selectedSubject] = value end, nil, 10)
    PushButton(lines, 158, PRESET_TOP - 14, Text.SET_SPEECH_ADD, function()
        local index = ns.Speech.AddSet(selectedSubject)
        if index then
            selectedPreset[selectedSubject] = index
        end
    end, 62,
        function() return #Presets() < Core.SPEECH_MAX end)
    PushButton(lines, 224, PRESET_TOP - 14, Text.SET_SPEECH_DELETE, function()
        local index = CurrentPreset()
        if index > 0 then ns.Speech.DeleteSet(selectedSubject, index) end
    end, 62)

    local boxes = Section(lines, function() return CurrentPreset() > 0 end)
    Label(boxes, Text.SET_SPEECH_EMOTE, 0, PRESET_TOP - 44)
    SpeechBox(boxes, 0, PRESET_TOP - 58, 40, function()
        local set = Presets()[CurrentPreset()]
        return set and set.emote or ""
    end, function(text) ns.Speech.SetText(selectedSubject, CurrentPreset(), "emote", text) end)
    Label(boxes, Text.SET_SPEECH_LINE, 0, PRESET_TOP - 106)
    SpeechBox(boxes, 0, PRESET_TOP - 120, 62, function()
        local set = Presets()[CurrentPreset()]
        return set and set.line or ""
    end, function(text) ns.Speech.SetText(selectedSubject, CurrentPreset(), "line", text) end)

    PushButton(lines, 4, PRESET_TOP - 190, Text.SET_SPEECH_RESTORE, function()
        local subject = selectedSubject
        Confirm("speech", Text.SET_SPEECH_RESTORE_CONFIRM, Text.SET_SPEECH_RESTORE_YES, function()
            ns.Speech.Restore(subject)
            selectedPreset[subject] = 1
            RefreshAll()
        end, SubjectName(subject))
    end)
end

local PAGES = {
    { Text.SETTINGS_TAB_GENERAL, "Ability_Creature_Cursed_03", GeneralPage },
    { Text.SETTINGS_TAB_SPHERE, "INV_Misc_Gem_Amethyst_02", SpherePage },
    { Text.SETTINGS_TAB_BUTTONS, "Trade_Engineering", ButtonsPage },
    { Text.SETTINGS_TAB_MENUS, "INV_Misc_Book_01", MenusPage },
    { Text.SETTINGS_TAB_DEBUFFS, Core.SPELLS.baneOfAgony[1], DebuffsPage },
    { Text.SETTINGS_TAB_CONTROLS, "Spell_Shadow_Cripple", ControlsPage },
    { Text.SETTINGS_TAB_ALERTS, "INV_Misc_Bell_01", AlertsPage },
    { Text.SETTINGS_TAB_REMINDERS, "INV_Misc_PocketWatch_01", RemindersPage },
    { Text.SETTINGS_TAB_SPEECH, "ability_warrior_rallyingcry", SpeechPage },
}

function Window.ShowPage(index)
    current = index
    for i, page in ipairs(pages) do
        page:SetShown(i == index)
        tabs[i]:SetChecked(i == index)
    end
    pageTitle:SetText(PAGES[index][1])
end

local function SavePlace()
    local point, _, relativePoint, x, y = frame:GetPoint()
    local saved = ns.db.settingsWindow
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

local function LockTooltip(tooltip)
    local locked = db().locked
    ns.Tips.Title(tooltip, locked and Text.LOCK_LOCKED or Text.LOCK_UNLOCKED)
    ns.Tips.Line(tooltip, locked and Text.LOCK_TIP_LOCKED or Text.LOCK_TIP_UNLOCKED)
    ns.Tips.Click(tooltip, "any", locked and Text.ACT_UNLOCK or Text.ACT_LOCK)
end

CreateLockButton = function()
    local button = CreateFrame("Button", "NecrosisOGLockButton", frame, "UIPanelButtonTemplate")
    button:SetSize(60, 18)
    button:SetPoint("RIGHT", frame, "TOPRIGHT", -64, -24)
    button:SetScript("OnClick", function(self)
        Changed(SetLocked)(not db().locked)
        ns.Tips.Redraw(self)
    end)
    ns.Tips.Attach(button, LockTooltip, "ANCHOR_RIGHT", true)
    function button:Refresh()
        self:SetText(db().locked and Text.LOCK_BUTTON_UNLOCK or Text.LOCK_BUTTON_LOCK)
    end
    controls[#controls + 1] = button
    return button
end

-- old stone window look for new frame
function Window.ClassicFrame(window, titleText)
    window:SetSize(WIDTH, HEIGHT)
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    if window.SetHitRectInsets then window:SetHitRectInsets(0, 30, 0, 70) end
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)

    local corners = { { "TopLeft", "TOPLEFT", 256 }, { "TopRight", "TOPRIGHT", 128 },
        { "BottomLeft", "BOTTOMLEFT", 256 }, { "BottomRight", "BOTTOMRIGHT", 128 } }
    for _, corner in ipairs(corners) do
        local texture = window:CreateTexture(nil, "BORDER")
        texture:SetSize(corner[3], 256)
        texture:SetTexture(WINDOW_ART .. corner[1])
        texture:SetPoint(corner[2])
    end
    local portrait = window:CreateTexture(nil, "BACKGROUND", nil, 1)
    local PORTRAIT_X, PORTRAIT_Y = 37, -36
    local disc = window:CreateTexture(nil, "BACKGROUND", nil, 0)
    disc:SetSize(60, 60)
    disc:SetPoint("CENTER", window, "TOPLEFT", PORTRAIT_X, PORTRAIT_Y)
    disc:SetTexture(Core.UiTexture("Mask"))
    disc:SetVertexColor(0, 0, 0, 1)
    portrait:SetSize(54, 54)
    portrait:SetPoint("CENTER", window, "TOPLEFT", PORTRAIT_X, PORTRAIT_Y)
    portrait:SetTexture(Core.UiTexture("SettingsLogo"))
    local portraitMask = window:CreateMaskTexture()
    portraitMask:SetTexture(Core.UiTexture("Mask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    portraitMask:SetAllPoints(portrait)
    portrait:AddMaskTexture(portraitMask)
    local title = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("CENTER", window, "TOP", -14, -24)
    title:SetText(Core.Gradient(titleText, Core.GRADIENT_TITLE))
    local line = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    line:SetPoint("TOP", window, "TOPLEFT", 184, -50)
    line:SetTextColor(1, 0.8, 0)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("CENTER", window, "TOPRIGHT", -46, -24)
    return title, line, close
end

-- page inside window dark panel
function Window.NewPage(window)
    local page = CreateFrame("Frame", nil, window)
    page:SetPoint("TOPLEFT", window, "TOPLEFT", PAGE_LEFT, PAGE_TOP)
    page:SetSize(PAGE_WIDTH, PAGE_HEIGHT)
    return page
end

local function Create()
    frame = CreateFrame("Frame", "NecrosisOGSettingsFrame", UIParent)
    local _
    _, pageTitle = Window.ClassicFrame(frame, Text.SETTINGS_TITLE)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePlace()
    end)
    local saved = ns.db.settingsWindow
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    local version = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    version:SetPoint("CENTER", frame, "TOPLEFT", 306, -64)
    version:SetTextColor(99 / 255, 227 / 255, 20 / 255)
    version:SetText(Text.SETTINGS_VERSION:format(ns.Version()))
    CreateLockButton()
    afterCombatNote = frame:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
    afterCombatNote:SetPoint("TOP", pageTitle, "BOTTOM", 0, -2)
    afterCombatNote:SetText(Text.SETTINGS_AFTER_COMBAT)
    afterCombatNote:Hide()

    for i, def in ipairs(PAGES) do
        local page = Window.NewPage(frame)
        def[3](page)
        page:Hide()
        pages[i] = page

        local tab = CreateFrame("CheckButton", nil, frame)
        tab:SetSize(32, 32)
        if i == 1 then
            tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", -32, TAB_TOP)
        else
            tab:SetPoint("TOPLEFT", tabs[i - 1], "BOTTOMLEFT", 0, -TAB_GAP)
        end
        local art = tab:CreateTexture(nil, "BACKGROUND")
        art:SetSize(64, 64)
        art:SetTexture(TAB_ART)
        art:SetPoint("TOPLEFT", -3, 11)
        if type(def[2]) == "number" then
            tab:SetNormalTexture(Plain(C_Spell.GetSpellTexture, def[2]) or "Interface\\Icons\\INV_Misc_QuestionMark")
        else
            tab:SetNormalTexture("Interface\\Icons\\" .. def[2])
        end
        tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        tab:GetHighlightTexture():SetBlendMode("ADD")
        tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
        tab:GetCheckedTexture():SetBlendMode("ADD")
        tab:SetScript("OnClick", function()
            if i ~= current and PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
                PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            end
            Window.ShowPage(i)
        end)
        ns.Tips.Attach(tab, function(tooltip) ns.Tips.Title(tooltip, def[1]) end, "ANCHOR_RIGHT", true)
        tabs[i] = tab
    end

    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, frame:GetName()) end
    frame:SetScript("OnShow", RefreshAll)
    frame:Hide()
    Window.ShowPage(1)
end

function Window.Toggle()
    if not frame then Create() end
    frame:SetShown(not frame:IsShown())
end

function Window.Open()
    if not frame then Create() end
    frame:Show()
end

function Window.SetLocked(on) Changed(SetLocked)(on) end

-- small page in game options with button open the window
local function RegisterGameOptions()
    if type(Settings) ~= "table" or type(Settings.RegisterCanvasLayoutCategory) ~= "function" then return end
    local panel = CreateFrame("Frame")
    Label(panel, Text.SETTINGS_TITLE, 16, -16, "GameFontNormalLarge")
    local text = Label(panel, Text.SET_OPTIONS_TEXT, 16, -44, "GameFontHighlight")
    text:SetWidth(500)
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(170, 24)
    open:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -84)
    open:SetText(Text.SET_OPEN)
    open:SetScript("OnClick", function()
        if not frame then Create() end
        frame:Show()
    end)
    pcall(function()
        local category = Settings.RegisterCanvasLayoutCategory(panel, Text.SETTINGS_TITLE)
        Settings.RegisterAddOnCategory(category)
    end)
end

table.insert(ns.onDemoData, function() if frame then RefreshAll() end end)

local forWarlock = false

table.insert(ns.onSphere, function()
    forWarlock = true
    RegisterGameOptions()
end)

function NecrosisOG_OnAddonCompartmentClick()
    if not forWarlock then
        ns.Print(Text.COMPARTMENT_NOT_WARLOCK)
        return
    end
    Window.Toggle()
end

-- print /nog commands
local function PrintHelp()
    ns.Print(Text.HELP_OPEN)
    ns.Print(Text.HELP_WELCOME)
    ns.Print(Text.HELP_TIMER)
    ns.Print(Text.HELP_HELP)
end

-- slash command /nog
function Window.Command(message)
    local command, rest = Core.SplitCommand(message)
    if command == "" or command == "welcome" then
        if not forWarlock then
            ns.Print(Text.COMPARTMENT_NOT_WARLOCK)
            return
        end
        if command == "welcome" then ns.Welcome.Show() else Window.Open() end
    elseif command == "timer" then
        local seconds, name = Core.ParseTimerCommand(rest)
        if not (seconds and ns.Timers and ns.Timers.StartCustom(name or Text.CUSTOM_TIMER_NAME, seconds)) then
            ns.Print(Text.CUSTOM_TIMER_USAGE)
        end
    else
        PrintHelp()
    end
end

if type(SlashCmdList) == "table" then
    SLASH_NECROSISOG1 = "/nog"
    SlashCmdList["NECROSISOG"] = Window.Command
end

function NecrosisOG_OnAddonCompartmentEnter(_, button)
    if not GameTooltip or not button then return end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    ns.Tips.Title(GameTooltip, Text.SETTINGS_TITLE)
    ns.Tips.Click(GameTooltip, "any", Text.ACT_TOGGLE_SETTINGS)
    GameTooltip:Show()
end

function NecrosisOG_OnAddonCompartmentLeave(_, button)
    if GameTooltip and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then C_Timer.After(0, UpdateNote) else UpdateNote() end
end)

Window.Frame = function() return frame end
Window.Pages = function() return pages, tabs end
Window.Current = function() return current end

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

-- settings window, open from game options, sphere right click or /nog
local _, ns = ...
local Core, Text = ns.Core, ns.Text

local Window = {}
ns.SettingsWindow = Window

local WIDTH, HEIGHT = 384, 512
local SETTINGS_EXTRA_HEIGHT = 68
local WINDOW_ART = "Interface\\PaperDollInfoFrame\\UI-Character-General-"
local PAGE_LEFT, PAGE_TOP = 30, -82
local PAGE_WIDTH, PAGE_HEIGHT = 290, 346
Window.PAGE_WIDTH, Window.PAGE_HEIGHT = PAGE_WIDTH, PAGE_HEIGHT
local TAB_GAP = 8
local TAB_TOP = -36
local TAB_ART = "Interface\\SpellBook\\SpellBook-SkillLineTab"
local ROW_HEIGHT = 18
local MIN_ROW_HEIGHT = 16
local SLIDER_WIDTH = 120
local SLIDER_STEP_BTN = 16
local SLIDER_STEP_GAP = 2
local RIGHT_COLUMN = 150
local SLIDER_RIGHT = 165
local DRAG_PURPLE = { 0xFF / 255, 0x50 / 255, 0xFF / 255 }
local DRAG_TEXT = { 0xF4 / 255, 0xE6 / 255, 0xFF / 255 }

local frame, pageTitle, afterCombatNote
local CreateLockButton
local CreateGuideButton
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

local function Changed(apply)
    return function(...)
        apply(...)
        RefreshAll()
    end
end

local FIT_FLOOR = 0.75

-- fit one line inside given width
local function Fit(fontString, width)
    if type(fontString) ~= "table" or type(fontString.GetFont) ~= "function"
        or type(fontString.GetStringWidth) ~= "function" or type(fontString.SetFont) ~= "function" then
        return
    end
    local file, size, flags = fontString:GetFont()
    if type(size) ~= "number" then return end
    fontString.fitSize = fontString.fitSize or size
    if size ~= fontString.fitSize then
        fontString:SetFont(file, fontString.fitSize, flags)
    end
    local needed = fontString:GetStringWidth()
    if type(needed) == "number" and needed > width and width > 0 then
        local scaled = math.floor(fontString.fitSize * math.max(FIT_FLOOR, width / needed))
        fontString:SetFont(file, scaled, flags)
    end
end

Window.FitText = Fit

local function FitButton(button, growTo)
    local text = type(button.GetFontString) == "function" and button:GetFontString()
    if not text then return end
    local base = button:GetWidth()
    local setText = button.SetText
    local function Refit()
        if growTo and type(text.GetStringWidth) == "function" then
            Fit(text, 10000)
            local natural = text:GetStringWidth()
            if type(natural) == "number" then button:SetWidth(math.max(base, math.min(growTo, natural + 16))) end
        end
        Fit(text, button:GetWidth() - 16)
    end
    button.SetText = function(self, value)
        setText(self, value)
        Refit()
    end
    Refit()
end

Window.FitButton = FitButton

local function Label(parent, text, x, y, font, maxWidth)
    local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    if maxWidth ~= false then Fit(label, maxWidth or (PAGE_WIDTH - x)) end
    return label
end

-- check box, get() return setting and set(on) change it
local function Check(page, x, y, text, get, set, labelWidth, spellID)
    local box = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    box:SetSize(26, 26)
    box:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    local labelAnchor = box
    local labelGap = 2
    local width = labelWidth or (PAGE_WIDTH - x - 30)
    if spellID then
        local icon = box:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", box, "RIGHT", 2, 0)
        icon:SetTexture(Plain(C_Spell.GetSpellTexture, spellID))
        labelAnchor, labelGap = icon, 4
        width = width - 20
    end
    box.label = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    box.label:SetPoint("LEFT", labelAnchor, "RIGHT", labelGap, 0)
    box.label:SetJustifyH("LEFT")
    box.label:SetWidth(width)
    box.label:SetText(text)
    box:SetScript("OnClick", function(self) Changed(set)(self:GetChecked() == true) end)
    ns.Sounds.Check(box)
    function box:Refresh() self:SetChecked(get() == true) end
    controls[#controls + 1] = box
    return box
end

-- slider with value in the title, opts.snap is a value drag will stick to, opts.wheel is mouse wheel move one step
local function Slider(page, x, y, text, low, high, step, get, set, kind, opts)
    local slider = CreateFrame("Slider", nil, page, "UISliderTemplateWithLabels")
    local inset = SLIDER_STEP_BTN + SLIDER_STEP_GAP
    local width = opts and opts.width or SLIDER_WIDTH
    slider:SetSize(width - 2 * inset, 16)
    if slider.Text.SetFontObject then slider.Text:SetFontObject("GameFontHighlightSmall") end
    slider:SetPoint("TOPLEFT", page, "TOPLEFT", x + inset, y)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    local function Show(value)
        if kind == "percent" then return string.format(Text.SETTINGS_PERCENT_VALUE, value) end
        if opts and opts.off == value then return Text.SET_MENU_OFF end
        if kind == "times" then return string.format(Text.SETTINGS_TIMES_VALUE, value) end
        return tostring(value)
    end
    slider.Low:SetText(Show(low))
    slider.High:SetText(Show(high))
    local function Title(value)
        slider.Text:SetText(string.format(Text.SETTINGS_VALUE, text, Show(value)))
        Fit(slider.Text, opts and opts.width or SLIDER_WIDTH + 30)
    end
    slider:SetScript("OnValueChanged", function(self, value)
        if self.refreshing then return end
        value = Core.RoundToStep(value, step)
        if opts and opts.snap and not self.stepping and math.abs(value - opts.snap) < (high - low) / width then
            value = opts.snap
            self.refreshing = true
            self:SetValue(value)
            self.refreshing = false
        end
        Title(value)
        if math.abs(value - get()) > step / 2 then Changed(set)(value) end
    end)
    local function Step(delta)
        if slider.IsEnabled and slider:IsEnabled() == false then return end
        slider.stepping = true
        slider:SetValue(math.max(low, math.min(high, Core.RoundToStep(slider:GetValue() + delta * step, step))))
        slider.stepping = false
    end
    local function StepButton(label, delta, point, relPoint, offset)
        local button = CreateFrame("Button", nil, slider, "UIPanelButtonTemplate")
        button:SetSize(SLIDER_STEP_BTN, SLIDER_STEP_BTN)
        button:SetPoint(point, slider, relPoint, offset, 0)
        button:SetText(label)
        button:SetScript("OnClick", function() Step(delta) end)
        ns.Sounds.Button(button)
        return button
    end
    slider.minus = StepButton("-", -1, "RIGHT", "LEFT", -SLIDER_STEP_GAP)
    slider.plus = StepButton("+", 1, "LEFT", "RIGHT", SLIDER_STEP_GAP)
    if not (opts and opts.wheel == false) then
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(_, delta) Step(delta) end)
    end
    function slider:Refresh()
        self.refreshing = true
        if opts and opts.bounds then
            low, high = opts.bounds()
            self:SetMinMaxValues(low, high)
            self.Low:SetText(Show(low))
            self.High:SetText(Show(high))
        end
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
        if self.minus and type(self.minus.SetEnabled) == "function" then self.minus:SetEnabled(enabled) end
        if self.plus and type(self.plus.SetEnabled) == "function" then self.plus:SetEnabled(enabled) end
    end
    return widget
end

local function Dropdown(page, x, y, text, options, get, set, width, maxRows, inlineLabelX)
    local label = text and Label(page, text, inlineLabelX or x, inlineLabelX and y - 5 or y,
        nil, inlineLabelX and x - inlineLabelX - 8 or width or 150)
    local dropdown = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width or 150)
    dropdown.pageLabel = label
    dropdown:SetPoint("TOPLEFT", page, "TOPLEFT", x, text and not inlineLabelX and y - 14 or y)
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

Window.Dropdown = Dropdown

local function PushButton(page, x, y, text, onClick, width, enabled)
    local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    button:SetSize(width or 170, 22)
    button:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    button:SetText(text)
    FitButton(button)
    button:SetScript("OnClick", function() Changed(onClick)() end)
    ns.Sounds.Button(button)
    if enabled then
        function button:Refresh() self:SetEnabled(enabled() == true) end
        controls[#controls + 1] = button
    end
    return button
end

local MENUS = {
    { key = "utility", titleKey = "SET_BUTTON_UTILITY", list = Core.UTILITY_MENU },
    { key = "curses", titleKey = "SET_BUTTON_CURSES", list = Core.CURSE_MENU },
    { key = "demons", titleKey = "SET_BUTTON_DEMONS", list = Core.DEMON_MENU },
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
        ns.Sounds.Button(row)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row:GetHighlightTexture():SetBlendMode("ADD")
        row.index = i
        row.dragBand = row:CreateTexture(nil, "BACKGROUND")
        row.dragBand:SetAllPoints(row)
        row.dragBand:SetColorTexture(DRAG_PURPLE[1], DRAG_PURPLE[2], DRAG_PURPLE[3], 0.3)
        row.dragBand:Hide()
        row.y = (i - 1) * rowHeight
        row:SetScript("OnDragStart", function(self)
            if source.canDrag and not source.canDrag() then return end
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
            if target and target ~= from and scroll:IsMouseOver() and (not source.canDrag or source.canDrag()) then
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
    weaponStone = { "SET_BUTTON_WEAPON_STONE", "SpellstoneButton-01", "SpellstoneButton-02" },
    healthstone = { "SET_BUTTON_HEALTHSTONE", "HealthstoneButton-01", "HealthstoneButton-02" },
    soulstone = { "SET_BUTTON_SOULSTONE", "SoulstoneButton-01", "SoulstoneButton-02" },
    utility = { "SET_BUTTON_UTILITY", "BuffMenuButton-01" },
    mount = { "SET_BUTTON_MOUNT", "MountButton-01" },
    demons = { "SET_BUTTON_DEMONS", "PetMenuButton-01" },
    curses = { "SET_BUTTON_CURSES", "CurseMenuButton-01" },
    shards = { "SET_BUTTON_SHARDS", "ShardDestroy-01" },
}

local function RingSource()
    return {
        rows = #Core.BUTTON_SLOTS,
        canDrag = function() return not ns.db.buttons.free end,
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
                entries[i] = { name = Text[SLOTS[slot][1]], icon = icon, atlas = atlas,
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

local function DIRECTIONS()
    return { { "up", Text.SET_DIRECTION_UP }, { "down", Text.SET_DIRECTION_DOWN },
        { "left", Text.SET_DIRECTION_LEFT }, { "right", Text.SET_DIRECTION_RIGHT } }
end

local function GROWTH() return { { "up", Text.SET_DIRECTION_UP }, { "down", Text.SET_DIRECTION_DOWN } } end

-- one lock for all movable things
local function SetLocked(on)
    ns.SetLocked(on)
    if ns.Timers.Refresh then ns.Timers.Refresh() end
    if ns.Alerts.Refresh then ns.Alerts.Refresh() end
end

-- small info icon with tooltip after the label
local function InfoIcon(page, after, title, describe)
    local icon = CreateFrame("Frame", nil, page)
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", after, "RIGHT", 4, 0)
    icon:EnableMouse(true)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexture("Interface\\FriendsFrame\\InformationIcon")
    ns.Tips.Attach(icon, function(tooltip)
        if title then ns.Tips.Title(tooltip, title) end
        describe(tooltip)
    end, "ANCHOR_RIGHT", true)
    return icon
end

Window.InfoIcon = InfoIcon

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
    ns.Sounds.Button(icon)
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

local function Heading(page, text, y, maxWidth)
    return Label(page, Core.Gradient(text, Core.GRADIENT_HEADING), 0, y, "GameFontNormal", maxWidth)
end

local function GreyLabel(label, on)
    controls[#controls + 1] = { Refresh = function() label:SetAlpha(on() == true and 1 or 0.5) end }
    return label
end

local CONFIRM_TITLES = { positions = "SET_RESET_POSITIONS", settings = "SET_RESET_ALL", speech = "SET_SPEECH_RESTORE",
    deleteSpeech = "SET_SPEECH_DELETE", language = "SET_LANGUAGE" }

local CONFIRM_RELOADS = { settings = true, language = true }

local confirmed, confirmBoxes = {}, {}

-- ask yes or no before do action
local function Confirm(which, text, yes, onAccept, arg)
    local box = confirmBoxes[which]
    if not box then
        local reloads = CONFIRM_RELOADS[which]
        box = ns.Dialog.New({ name = "NecrosisOGConfirm" .. which, reload = reloads })
        local function Close() box.frame:Hide() end
        local function Accept()
            if confirmed[which] then confirmed[which]() end
        end
        if reloads then
            box.yes:SetScript("PreClick", Accept)
            local function CloseQuietly()
                ns.Sounds.Hush(box.frame)
                Close()
            end
            box.yes:SetScript("PostClick", CloseQuietly)
            box.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
            box.frame:SetScript("OnEvent", CloseQuietly)
        else
            box.yes:SetScript("OnClick", function()
                Close()
                Accept()
            end)
        end
        box.no:SetScript("OnClick", Close)
        confirmBoxes[which] = box
    end
    confirmed[which] = onAccept
    box.SetTitle(Text[CONFIRM_TITLES[which]])
    box.text:SetText(arg and string.format(text, arg) or text)
    box.yes:SetText(yes)
    box.no:SetText(Text.SET_RESET_NO)
    box.Fit()
    box.frame:Raise()
    box.frame:Show()
end

function Window.ConfirmBox(which) return confirmBoxes[which] end

-- reset all setting after yes
function Window.ConfirmReset()
    if InCombat() then return ns.Print(Text.RESET_IN_COMBAT) end
    Confirm("settings", Text.SET_RESET_CONFIRM, Text.SET_RESET_YES, function() ns.Sphere.ResetAll() end)
end

function Window.ConfirmLanguage()
    if InCombat() then return ns.Print(Text.LANGUAGE_IN_COMBAT) end
    Confirm("language", Text.SET_LANGUAGE_RELOAD_CONFIRM, Text.SET_LANGUAGE_RELOAD_YES)
end

function Window.ConfirmPositions()
    Confirm("positions", Text.SET_RESET_POSITIONS_CONFIRM, Text.SET_RESET_YES, function() ns.Sphere.ResetPositions() end)
end

local shardLimitSlider

function Window.RefreshShardLimit()
    if shardLimitSlider and frame:IsShown() then shardLimitSlider:Refresh() end
end

local function SpherePage(page)
    Heading(page, Text.UNLOCK_LOOK, 0)
    Slider(page, 5, -24, Text.SET_SPHERE_SCALE, Core.SCALE_MIN, Core.SCALE_MAX, Core.SCALE_STEP,
        function() return Core.ClampSphereScale(db().sphere.scale) end, function(value) ns.Sphere.SetScale(value) end, "percent")
    local skins = {}
    for i, skin in ipairs(Core.SKIN_LIST) do skins[i] = { skin, Text["SET_SKIN_" .. string.upper(skin)] } end
    Dropdown(page, RIGHT_COLUMN, -12, Text.SET_SKIN, skins,
        function() return Core.SkinOrDefault(db().skin) end, function(value) ns.SetSetting("skin", value) end, 138)

    Heading(page, Text.SET_BUTTON_SHARDS, -58)
    Check(page, 0, -74, Text.SET_SHOW_COUNT, function() return db().sphere.showCount end,
        function(on) ns.SetSetting("sphere.showCount", on) end, SLIDER_RIGHT - 30)
    local lowShards = Section(page, function() return db().sphere.showCount == true end)
    Slider(lowShards, SLIDER_RIGHT, -82, Text.SET_LOW_SHARDS, 0, Core.SHARD_COUNT_MAX, 1,
        function() return Core.ClampThreshold(db().sphere.lowShards) end,
        function(value) ns.SetSetting("sphere.lowShards", value) end)
    local low, high = ns.Shards.LimitBounds()
    Check(page, 0, -116, Text.SET_AUTO_DESTROY_SHARDS, function() return db().buttons.autoDestroy end,
        function(on) ns.SetSetting("buttons.autoDestroy", on) end, 110)
    shardLimitSlider = Slider(page, SLIDER_RIGHT, -128, Text.SET_SHARD_LIMIT, low, high, 1,
        ns.Shards.Limit, ns.Shards.SetLimit, nil, { bounds = ns.Shards.LimitBounds })
    local orbs = GreyedBy(Check(page, 0, -145, Text.SET_SOUL_ORBS_ANIMATION,
        function() return db().sphere.soulOrbsAnimation end,
        function(on) ns.SetSetting("sphere.soulOrbsAnimation", on) end, 116),
        function() return db().animation.on ~= false end)
    InfoIcon(page, orbs.label, Text.SET_SOUL_ORBS_ANIMATION, function(tooltip)
        ns.Tips.Line(tooltip, Text.TIP_ORBS_GAIN)
    end)

    Heading(page, Text.SET_SPHERE_THREAT, -182)
    Check(page, 0, -198, Text.SET_SHOW_THREAT, function() return db().sphere.showThreat end,
        function(on) ns.SetSetting("sphere.showThreat", on) end)

    local clicks = Heading(page, Text.SET_SPHERE_CLICKS, -236)
    InfoIcon(page, clicks, Text.SET_SPHERE_CLICKS, function(tooltip)
        ns.Tips.Line(tooltip, Text.TIP_SPHERE_CLICKS)
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
        Dropdown(page, column * RIGHT_COLUMN, -255 - row * 46, Text[click.text], ClickChoices,
            function() return Core.SphereClick(click.key, db().sphere.clicks[click.key]) end, function(value)
                ns.SetSetting("sphere.clicks." .. click.key, value)
            end, 138)
    end
end

local function ButtonsPage(page)
    Dropdown(page, 0, 0, Text.SET_BUTTONS_LAYOUT,
        { { false, Text.SET_BUTTONS_LAYOUT_RING }, { true, Text.SET_BUTTONS_LAYOUT_FREE } },
        function() return db().buttons.free end, ns.Buttons.SetFree, 138)

    Slider(page, SLIDER_RIGHT, -17, Text.SET_SIZE, Core.BUTTON_SIZE_MIN, Core.BUTTON_SIZE_MAX, Core.BUTTON_SIZE_STEP,
        function() return Core.ClampButtonSize(db().sphere.buttonSize) end, function(value)
            ns.SetSetting("sphere.buttonSize", value)
        end, "times")

    local ring = Section(page, function() return not db().buttons.free end)
    local function RingSlider(x, y, text, low, high, step, key, clamp, kind)
        Slider(ring, x, y, text, low, high, step, function() return clamp(db().sphere[key]) end, function(value)
            ns.SetSetting("sphere." .. key, value)
        end, kind, { snap = Core.DEFAULTS.sphere[key], wheel = true })
    end
    RingSlider(5, -61, Text.SET_ROTATION, Core.ROTATION_MIN, Core.ROTATION_MAX, Core.ROTATION_STEP, "rotation",
        Core.ClampRotation)
    RingSlider(SLIDER_RIGHT, -61, Text.SET_SPACING, Core.SPACING_MIN, Core.SPACING_MAX, Core.SPACING_STEP, "spacing",
        Core.ClampSpacing, "times")
    RingSlider(5, -108, Text.SET_DISTANCE, Core.DISTANCE_MIN, Core.DISTANCE_MAX, Core.DISTANCE_STEP, "distance",
        Core.ClampDistance, "times")
    local free = Section(page, function() return db().buttons.free end)
    PushButton(free, 4, -54, Text.SET_BUTTONS_RESET, ns.Buttons.ResetPlaces, 138)

    local function AutoHideOn() return db().sphere.autoHide.on == true end
    Check(page, -2, -140, Text.SET_AUTO_HIDE, AutoHideOn,
        function(on) ns.SetSetting("sphere.autoHide.on", on) end, 148)
    GreyedBy(Slider(page, 178, -145, Text.SET_AUTO_HIDE_FADED,
        Core.FADED_ALPHA_MIN * 100, Core.FADED_ALPHA_MAX * 100, Core.FADED_ALPHA_STEP * 100,
        function()
            return math.floor(Core.ClampFadedAlpha(db().sphere.autoHide.fadedAlpha, db().buttons.free) * 100 + 0.5)
        end,
        function(value)
            ns.SetSetting("sphere.autoHide.fadedAlpha", Core.ClampFadedAlpha(value / 100, db().buttons.free))
        end,
        "percent", { width = 112, bounds = function()
            return Core.FadedAlphaMin(db().buttons.free) * 100, Core.FADED_ALPHA_MAX * 100
        end }), AutoHideOn)
    GreyedBy(Check(page, 14, -172, Text.SET_AUTO_HIDE_COMBAT,
        function() return db().sphere.autoHide.combatShow ~= false end,
        function(on) ns.SetSetting("sphere.autoHide.combatShow", on) end), AutoHideOn)

    OrderList(page, 0, -236, PAGE_WIDTH - 10, #Core.BUTTON_SLOTS * ROW_HEIGHT, RingSource())
    local listHeading = Heading(page, Text.SETTINGS_TAB_BUTTONS, -214)
    InfoIcon(page, listHeading, Text.SETTINGS_TAB_BUTTONS, function(tooltip)
        if db().buttons.free then
            ns.Tips.Line(tooltip, Text.TIP_BUTTONS_FREE)
        ns.Tips.Line(tooltip, " ")
            ns.Tips.Line(tooltip, Text.SET_BUTTONS_SWITCH)
        else
            ns.Tips.Line(tooltip, Text.SET_ORDER_HELP)
        end
    end)
end

local function MenusPage(page)
    Check(page, 0, 0, Text.SET_MENU_CLOSES, function() return db().buttons.menuCloses == true end, function(on)
        ns.SetSetting("buttons.menuCloses", on)
    end)
    local selectorWidth = 94
    for i, menu in ipairs(MENUS) do
        local key = menu.key
        local button = PushButton(page, (i - 1) * 98, -29, Text[menu.titleKey], function()
            selectedMenu = key
        end, selectorWidth)
        function button:Refresh()
            if selectedMenu == key then self:LockHighlight() else self:UnlockHighlight() end
        end
        controls[#controls + 1] = button
    end
    Dropdown(page, 0, -67, Text.SET_MENU_DIRECTION, DIRECTIONS,
        function() return Core.MenuDirection(selectedMenu, db().buttons.menuDirection[selectedMenu]) end, function(value)
            ns.SetSetting("buttons.menuDirection." .. selectedMenu, value)
        end, 90)
    local function ShiftSlider(x, text, axis)
        Slider(page, x, -82, text, Core.MENU_SHIFT_MIN, Core.MENU_SHIFT_MAX, Core.MENU_SHIFT_STEP, function()
            local shift = db().buttons.menuOffset and db().buttons.menuOffset[selectedMenu]
            return select(axis, Core.MenuShift(shift))
        end, function(value)
            ns.Buttons.SetMenuShift(selectedMenu, axis, value)
        end, nil, { snap = 0, width = 86 })
    end
    ShiftSlider(100, Text.SET_MENU_SHIFT_X, 1)
    ShiftSlider(198, Text.SET_MENU_SHIFT_Y, 2)
    local spells = Heading(page, Text.SET_MENU_SPELLS, -129)
    InfoIcon(page, spells, Text.SET_MENU_SPELLS, function(tooltip)
        ns.Tips.Line(tooltip, Text.SET_ORDER_HELP)
    end)
    OrderList(page, 0, -151, PAGE_WIDTH - 10, PAGE_HEIGHT + SETTINGS_EXTRA_HEIGHT - 151, MenuSource())
end

local SHOW_X = 200
local HEAD_TOP = -8
local HEAD_ROW = 28
local SECTION_SPACE = 8
local SLIDER_TOP = -14
local SECTION_ROW = 46
local DEBUFFS_BOTTOM_INSET = 24
local TRACK_TOP = -2
local TRACK_HEIGHT = 22 - TRACK_TOP + #Core.ENEMY_SLOTS * ROW_HEIGHT

local SCROLL_BAR_X = 4

local function FamilyKnown(id) return ns.Buttons.IsKnown(id) or Plain(IsPlayerSpell, id) == true end

local function KeyName(key) return SpellName(Core.SPELLS[key][1]) or key end

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

local function NewSection(content, title, on, path, bodyHeight, switchLabel)
    local section = CreateFrame("Frame", nil, content)
    section:SetWidth(PAGE_WIDTH)
    section.heading = Heading(section, title, HEAD_TOP, SHOW_X - 4)
    Check(section, SHOW_X, HEAD_TOP + 7, switchLabel or Text.SET_SHOW, on, function(value) ns.SetSetting(path, value) end, 60)
    local body = CreateFrame("Frame", nil, section)
    body:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -HEAD_ROW)
    body:SetSize(PAGE_WIDTH, bodyHeight)
    section.body, section.on, section.bodyHeight = body, on, bodyHeight
    return section
end

local function ControlsPage(page)
    local timers = function() return db().timers end
    local focus = NewSection(page, Text.SET_FOCUS_ON, function() return timers().focusOn ~= false end,
        "timers.focusOn", 98)
    focus:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    InfoIcon(focus, focus.heading, Text.SET_FOCUS_ON, function(tooltip)
        ns.Tips.Line(tooltip, Text.TIP_CONTROL_FOCUS)
    end)
    Slider(focus.body, 5, SLIDER_TOP, Text.SET_SIZE, Core.SCALE_MIN, Core.SCALE_MAX, Core.SCALE_STEP,
        function() return Core.TimerScale(timers(), "focus") end,
        function(value) ns.Timers.SetScale("focus", value) end, "percent")
    for i, key in ipairs(Core.FOCUS_SWITCHES) do
        local name = KeyName(key)
        if key == "fear" then name = string.format(Text.SET_FOCUS_FEAR, name) end
        Check(focus.body, ((i - 1) % 2) * RIGHT_COLUMN, -42 - math.floor((i - 1) / 2) * 26, name,
            function() return timers().focusOff[key] ~= true end,
            function(on) ns.SetSetting("timers.focusOff." .. key, (not on) or nil) end, 118,
            Core.SPELLS[key][1])
    end

    local control = NewSection(page, Text.SET_CONTROL_ON, function() return timers().controlOn ~= false end,
        "timers.controlOn", 0)
    control:SetPoint("TOPLEFT", focus, "BOTTOMLEFT", 0, -SECTION_SPACE)
    control:SetHeight(HEAD_ROW)
    control.body:Hide()
    InfoIcon(control, control.heading, Text.SET_CONTROL_ON, function(tooltip)
        ns.Tips.Line(tooltip, Text.TIP_CONTROL_TIMERS)
    end)
    controls[#controls + 1] = { Refresh = function()
        local on = focus.on()
        focus.body:SetShown(on)
        focus:SetHeight(HEAD_ROW + (on and focus.bodyHeight or 0))
    end }
end

local function OffsetSliders(body, y, low, high, get, set)
    Slider(body, 5, y, Text.SET_MENU_SHIFT_X, low, high, 1, function() return get("x") end,
        function(value) set("x", value) end, nil, { snap = 0 })
    Slider(body, SLIDER_RIGHT, y, Text.SET_MENU_SHIFT_Y, low, high, 1, function() return get("y") end,
        function(value) set("y", value) end, nil, { snap = 0 })
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

-- wrack switch and help below the glow switch
local function WrackRotationOption(body, glowOn)
    local function KnowsWrack() return Core.HighestKnown(Core.SPELLS.wrack, FamilyKnown) ~= nil end
    local row = CreateFrame("Frame", nil, body)
    row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    row:SetSize(PAGE_WIDTH, 26)
    local box = GreyedBy(Check(row, 4, 0, Text.SET_SMART_WRACK_ROTATION,
        function() return db().timers.wrackHelper.on ~= false end,
        function(on) ns.SetSetting("timers.wrackHelper.on", on) end, 136), KnowsWrack)
    local spellIcon = box:CreateTexture(nil, "ARTWORK")
    spellIcon:SetSize(16, 16)
    spellIcon:SetPoint("LEFT", box, "RIGHT", 2, 0)
    spellIcon:SetTexture(Plain(C_Spell.GetSpellTexture, Core.SPELLS.wrack[1]))
    box.label:ClearAllPoints()
    box.label:SetPoint("LEFT", spellIcon, "RIGHT", 4, 0)

    local widened = false
    local function ResetWidth(tooltip)
        if not widened then return end
        widened = false
        tooltip:SetMinimumWidth(0, false)
    end
    GameTooltip:HookScript("OnTooltipCleared", ResetWidth)
    GameTooltip:HookScript("OnHide", ResetWidth)
    local info = InfoIcon(row, box.label, Text.SET_SMART_WRACK_ROTATION, function(tooltip)
        local wrack = SpellName(Core.SPELLS.wrack[1]) or "?"
        local bolt = SpellName(Core.SPELLS.shadowBolt[1]) or "?"
        ns.Tips.Line(tooltip, Text.HELPER_SOURCE)
        ns.Tips.Line(tooltip, " ")
        ns.Tips.Line(tooltip, Text.HELPER_INTRO)
        ns.Tips.Line(tooltip, " ")
        ns.Tips.Line(tooltip, "1. " .. string.format(Text.HELPER_KEEP_DOTS, wrack))
        ns.Tips.Line(tooltip, " ")
        ns.Tips.Line(tooltip, "2. " .. string.format(Text.HELPER_INSTANT_BOLT, bolt))
        ns.Tips.Line(tooltip, " ")
        ns.Tips.Line(tooltip, string.format(Text.HELPER_REFRESH, wrack))
        ns.Tips.Line(tooltip, " ")
        ns.Tips.Line(tooltip, string.format(Text.HELPER_CLIPPING, wrack, bolt))
        local known, on = KnowsWrack(), glowOn()
        if not known or not on then
            ns.Tips.Line(tooltip, " ")
            if not known then ns.Tips.Note(tooltip, Text.HELPER_UNKNOWN_NOTE) end
            if not on then ns.Tips.Note(tooltip, Text.HELPER_GLOW_NOTE) end
        end
        tooltip:SetMinimumWidth(340, true)
        widened = true
    end)
    return box, info
end

function Window.PageScroll(page, name, top, height)
    local scroll = CreateFrame("ScrollFrame", name, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, top)
    scroll:SetSize(PAGE_WIDTH, (height or PAGE_HEIGHT) + top)
    if scroll.ScrollBar then
        scroll.ScrollBar:ClearAllPoints()
        scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", SCROLL_BAR_X, -16)
        scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", SCROLL_BAR_X, 16)
    end
    return scroll
end

local function ScrollContent(page, height)
    local scroll = Window.PageScroll(page, nil, 0, height - DEBUFFS_BOTTOM_INSET)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PAGE_WIDTH, height)
    scroll:SetScrollChild(content)
    return content
end

local ALERT_TALENTS = {
    shadowTrance = 18094,
    decimation = 440870,
    amplifyCurse = Core.SPELLS.amplifyCurse[1],
}

local ALERT_ICONS = {
    shadowTrance = Core.SHADOW_TRANCE_ID,
    antiFear = Core.SPELLS.fear[1],
}

local function AlertSwitch(page, x, y, key, path, get)
    local talent = ALERT_TALENTS[key]
    local icon = ALERT_ICONS[key] or talent
    local box = Check(page, x, y, ns.AlertName(key), get, function(on) ns.SetSetting(path, on) end, 118, icon)
    if talent then
        GreyedBy(box, function() return FamilyKnown(talent) end)
        table.insert(ns.onSpellsChanged, function() box:Refresh() end)
    end
    return box
end

local SOUND_SPELLS = {
    SET_WARN_SOUND = Core.SPELLS.banish[1],
    SET_SOUND_DEMON = Core.SPELLS.enslaveDemon[1],
    SET_SOUND_SOULSTONE = Core.SPELLS.createSoulstone[1],
    SET_SOUND_BREATH = Core.SPELLS.unendingBreath[1],
}

local function GeneralPage(page)
    local macroHead = Heading(page, Text.SET_FOCUS_MACROS, 0)
    InfoIcon(page, macroHead, Text.SET_FOCUS_MACROS, function(tooltip)
        ns.Tips.Line(tooltip, Text.TIP_MACROS_BARS)
        ns.Tips.Line(tooltip, " ")
        ns.Tips.Line(tooltip, Text.TIP_MACROS_KEYS)
        ns.Tips.Line(tooltip, " ")
        ns.Tips.Line(tooltip, Text.TIP_MACROS_FOCUS)
    end)
    local petIcons = {}
    for i, key in ipairs(Core.MACRO_ROW) do
        local icon = MacroIcon(page, 4 + MACRO_GAP * (i - 1), -20, key)
        if Core.PET_SPELLS[key] then petIcons[#petIcons + 1] = icon end
    end
    table.insert(ns.onSpellsChanged, function()
        for _, icon in ipairs(petIcons) do icon:Refresh() end
    end)

    Heading(page, Text.SET_HEAD_DISPLAY, -60)
    local off = Core.RoundToStep(Core.ANIM_SPEED_MIN - Core.ANIM_SPEED_STEP, Core.ANIM_SPEED_STEP)
    Slider(page, 5, -88, Text.SET_ANIM_SPEED, off, Core.ANIM_SPEED_MAX, Core.ANIM_SPEED_STEP,
        function()
            if db().animation.on == false then return off end
            return Core.ClampAnimSpeed(db().animation.speed)
        end,
        function(value)
            local on = value >= Core.ANIM_SPEED_MIN
            if on then ns.SetAnimationSpeed(value) end
            ns.SetAnimationsOn(on)
        end, "times", { off = off })
    Check(page, RIGHT_COLUMN, -85, Text.SET_TOOLTIPS, function() return db().tooltips ~= false end,
        function(on) ns.SetSetting("tooltips", on) end)

    Dropdown(page, 4, -121, Text.SET_LANGUAGE, function()
        local auto = string.format(Text.SET_LANGUAGE_AUTO, Core.LanguageName(ns.clientLanguage) or Core.LanguageName("enUS"))
        return Core.LanguageChoices(ns.Locales, auto)
    end, function() return Core.LanguageOrDefault(db().language, ns.Locales) end, function(value)
        if value == db().language then return end
        ns.SetSetting("language", value)
        Window.ConfirmLanguage()
    end, 138)
    local windowSizes = {}
    for i, size in ipairs(Core.WINDOW_SCALES) do
        windowSizes[i] = { size, string.format(Text.SETTINGS_PERCENT_VALUE, size) }
    end
    Dropdown(page, RIGHT_COLUMN, -121, Text.SET_WINDOW_SIZE, windowSizes,
        function() return Core.WindowScaleOrDefault(db().windowScale) end,
        function(value) ns.SetSetting("windowScale", value) end, 138)
    local soundsTop, footerGap, footerHeight, bottomMargin = -168, 10, 38, 25
    local rowHeight, groupGap = 24, 16
    local height = 0
    for _, group in ipairs(Core.SOUND_LIST) do
        height = height + groupGap + math.ceil(#group.entries / 2) * rowHeight
    end
    local available = PAGE_HEIGHT + SETTINGS_EXTRA_HEIGHT + soundsTop - HEAD_ROW - footerGap - footerHeight - bottomMargin
    local sounds = NewSection(page, Text.SET_SOUNDS, ns.SoundsOn, "soundsOn", math.min(height, available), Text.SET_ON)
    sounds:SetPoint("TOPLEFT", page, "TOPLEFT", 0, soundsTop)
    local list = sounds.body
    if height > sounds.bodyHeight then
        local scroll = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
        scroll:SetAllPoints(list)
        list = CreateFrame("Frame", nil, scroll)
        list:SetSize(PAGE_WIDTH, height)
        scroll:SetScrollChild(list)
    end
    local y = 0
    for _, group in ipairs(Core.SOUND_LIST) do
        Label(list, Text[group.title], 4, -y)
        y = y + groupGap
        for i, sound in ipairs(group.entries) do
            local path, label, alert = sound[1], sound[2], sound[3]
            local keys = Core.SplitPath(path)
            local function On()
                local value = db()
                for _, key in ipairs(keys) do value = value[key] end
                return value ~= false
            end
            local x = ((i - 1) % 2) * RIGHT_COLUMN
            local rowY = -y - math.floor((i - 1) / 2) * rowHeight
            local box
            if alert then
                box = AlertSwitch(list, x, rowY, alert, path, On)
            else
                box = Check(list, x, rowY, Text[label], On, function(on) ns.SetSetting(path, on) end, 118,
                    SOUND_SPELLS[label])
            end
            box:SetSize(rowHeight, rowHeight)
        end
        y = y + math.ceil(#group.entries / 2) * rowHeight
    end

    local other = CreateFrame("Frame", nil, page)
    other:SetSize(PAGE_WIDTH, footerHeight)
    other:SetPoint("TOPLEFT", sounds, "BOTTOMLEFT", 0, -footerGap)
    Heading(other, Text.SET_HEAD_OTHER, 0)
    local demo = PushButton(other, 4, -16, Text.SET_DEMO_START, function() ns.SetDemo(not ns.demoData) end,
        138, function() return not InCombat() end)
    local refreshDemo = demo.Refresh
    function demo:Refresh()
        refreshDemo(self)
        self:SetText(ns.demoData and Text.SET_DEMO_STOP or Text.SET_DEMO_START)
    end
    PushButton(other, RIGHT_COLUMN, -16, Text.SET_RESET_ALL, function() Window.ConfirmReset() end, 138)
    controls[#controls + 1] = { Refresh = function()
        local on = ns.SoundsOn()
        sounds.body:SetShown(on)
        sounds:SetHeight(HEAD_ROW + (on and sounds.bodyHeight or 0))
    end }
end

local function DebuffsPage(page)
    local timers = function() return db().timers end
    local content = ScrollContent(page, PAGE_HEIGHT + SETTINGS_EXTRA_HEIGHT)

    local track = CreateFrame("Frame", nil, content)
    track:SetSize(PAGE_WIDTH, TRACK_HEIGHT)
    track:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    local trackHeading = Heading(track, Text.SET_TRACK, TRACK_TOP)
    InfoIcon(track, trackHeading, Text.SET_TRACK, function(tooltip)
        ns.Tips.Line(tooltip, Text.TIP_TRACK_DISPLAYS)
        ns.Tips.Line(tooltip, " ")
        ns.Tips.Note(tooltip, Text.SET_ORDER_HELP)
    end)
    OrderList(track, 0, TRACK_TOP - 22, PAGE_WIDTH - 10, #Core.ENEMY_SLOTS * ROW_HEIGHT, FamilySource())

    local multi = NewSection(content, Text.SET_DEBUFF_TRACKER, function() return timers().multiOn ~= false end,
        "timers.multiOn", -SLIDER_TOP + 30)
    InfoIcon(multi, multi.heading, Text.SET_DEBUFF_TRACKER, function(tooltip)
        ns.Tips.Line(tooltip, Text.TIP_TRACKER_NAMEPLATES)
    end)
    Slider(multi.body, 5, SLIDER_TOP, Text.SET_SIZE, Core.SCALE_MIN, Core.SCALE_MAX, Core.SCALE_STEP,
        function() return Core.TimerScale(timers(), "multi") end, function(value) ns.Timers.SetScale("multi", value) end,
        "percent")
    Dropdown(multi.body, RIGHT_COLUMN, 0, Text.SET_TIMER_GROWS, GROWTH,
        function() return timers().grow.multi == "down" and "down" or "up" end, function(value)
            ns.SetSetting("timers.grow.multi", value)
        end, 105)

    local missing = CreateFrame("Frame", nil, content)
    missing:SetWidth(PAGE_WIDTH)
    Heading(missing, Text.SET_MISSING_DEBUFFS, 0)
    local target = ReminderSection(missing, Text.SET_MISSING_ON_TARGET, "targetReminder")
    local plate = ReminderSection(missing, Text.SET_MISSING_ON_NAMEPLATES, "plateReminder", Core.ClampPlateOffset,
        Core.PLATE_OFFSET_MIN, Core.PLATE_OFFSET_MAX)

    local function Place(section, parent, y)
        local on = section.on()
        section.body:SetShown(on)
        local height = HEAD_ROW + (on and section.bodyHeight or 0)
        section:ClearAllPoints()
        section:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
        section:SetHeight(height)
        return y + height
    end
    local layout = {}
    function layout:Refresh()
        local y = Place(multi, content, TRACK_HEIGHT + SECTION_SPACE) + SECTION_SPACE
        missing:ClearAllPoints()
        missing:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        local plateTop = Place(target, missing, 20) + SECTION_SPACE
        local height = Place(plate, missing, plateTop)
        missing:SetHeight(height)
        content:SetHeight(y + height + SECTION_SPACE)
    end
    controls[#controls + 1] = layout
end

local DEBUFFS_PAGE_INDEX = 7

local function RotationPage(page)
    local timers = function() return db().timers end
    local helper = NewSection(page, Text.SET_BAR_HIGHLIGHT, function() return timers().barHighlight.on ~= false end,
        "timers.barHighlight.on", 70)
    helper:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    InfoIcon(helper, helper.heading, Text.SET_BAR_HIGHLIGHT, function(tooltip)
        ns.Tips.Line(tooltip, string.format(Text.TIP_ROTATION_ORDER,
            Core.TipHeading(Text.SET_TRACK) .. "|cffffffff",
            "|cffffff00" .. Text.SETTINGS_TAB_DEBUFFS .. "|r|cffffffff"))
        ns.Tips.Line(tooltip, " ")
        ns.Tips.Line(tooltip, Text.TIP_ROTATION_GLOW)
    end)
    local wrackBox, wrackInfo = WrackRotationOption(helper.body, helper.on)
    PushButton(helper.body, 4, -40, Text.SET_EDIT_ORDER, function()
        Window.ShowPage(DEBUFFS_PAGE_INDEX)
    end, 138)
    local layout = {}
    function layout:Refresh()
        local on = helper.on() == true
        helper.body:SetShown(on)
        helper:SetHeight(HEAD_ROW + (on and helper.bodyHeight or 0))
    end
    controls[#controls + 1] = layout
    table.insert(ns.onSpellsChanged, function()
        wrackBox:Refresh()
        ns.Tips.Redraw(wrackInfo)
    end)
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

local ALERT_ROW = 26

local function AlertsPage(tab)
    tab:SetScript("OnHide", function() ns.ProcAlerts.StopPreview() end)

    local testAlertsY = -96 - math.ceil(#Core.ALERT_KEYS / 2) * ALERT_ROW
    local alertBar = NewSection(tab, Text.SET_PROC_BAR, function() return db().procBar.on ~= false end,
        "procBar.on", -testAlertsY + ALERT_ROW)
    BarSliders(alertBar.body, SLIDER_TOP, "procBar")
    for i, key in ipairs(Core.ALERT_KEYS) do
        local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local field = key .. "On"
        AlertSwitch(alertBar.body, column * RIGHT_COLUMN, -96 - row * ALERT_ROW, key, "alerts." .. field,
            function() return db().alerts[field] ~= false end)
    end
    PushButton(alertBar.body, RIGHT_COLUMN, testAlertsY, Text.SET_TEST_ALERTS,
        function() ns.ProcAlerts.TestAlerts() end, 130, function() return not InCombat() and not ns.demoData end)

    local glows = NewSection(tab, Text.SET_ACTION_BAR_GLOWS, function() return db().alerts.glows.on ~= false end,
        "alerts.glows.on", 156)
    for i, key in ipairs({ "shadowTrance", "decimation" }) do
        AlertSwitch(glows.body, (i - 1) * RIGHT_COLUMN, 0, key, "alerts.glows." .. key,
            function() return db().alerts.glows[key] ~= false end)
    end
    local thresholds = {}
    for i, percent in ipairs(Core.SACRIFICE_THRESHOLDS) do
        thresholds[i] = { percent, string.format(Text.SET_SACRIFICE_AT, percent) }
    end
    local function healthRow(key, label, condition, y)
        local on = function() return db().alerts[key .. "On"] ~= false end
        Check(glows.body, 0, y, label, on, function(value) ns.SetSetting("alerts." .. key .. "On", value) end,
            nil, Core.SPELLS[key][1])
        local conditionLabel = Label(glows.body, condition, 28, y - 28, "GameFontHighlightSmall", false)
        conditionLabel:SetWidth(175)
        GreyLabel(conditionLabel, on)
        local setting = key .. "At"
        GreyedBy(Dropdown(glows.body, 210, y - 21, nil, thresholds,
            function() return Core.SacrificeThresholdOrDefault(db().alerts[setting], Core.DEFAULTS.alerts[setting]) end,
            function(value) ns.SetSetting("alerts." .. setting, value) end, PAGE_WIDTH - 210), on)
    end
    healthRow("sacrifice", Text.SET_SACRIFICE_GLOW, Text.SET_SACRIFICE_HEALTH, -28)
    healthRow("healthFunnel", SpellName(Core.SPELLS.healthFunnel[1]) or Text.SET_HEALTH_FUNNEL_GLOW,
        Text.SET_HEALTH_FUNNEL_HEALTH, -79)
    PushButton(glows.body, RIGHT_COLUMN, -130, Text.SET_TEST_GLOWS,
        function() ns.ProcAlerts.TestGlows() end, 130, function() return not InCombat() and not ns.demoData end)

    local layout = {}
    function layout:Refresh()
        local y = 0
        for _, section in ipairs({ alertBar, glows }) do
            local on = section.on() == true
            section.body:SetShown(on)
            local height = HEAD_ROW + (on and section.bodyHeight or 0)
            section:ClearAllPoints()
            section:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -y)
            section:SetHeight(height)
            y = y + height + SECTION_SPACE
        end
    end
    controls[#controls + 1] = layout
end

local function RemindersPage(tab)
    local bar = NewSection(tab, Text.SET_REMINDER_BAR, function() return db().reminderBar.on ~= false end,
        "reminderBar.on", 126)
    bar:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
    BarSliders(bar.body, SLIDER_TOP, "reminderBar")
    Check(bar.body, 0, -94, Text.SET_SAFE_NARROW, function() return db().reminderBar.hideInCities end,
        function(on) ns.SetSetting("reminderBar.hideInCities", on) end)

    local reminders = CreateFrame("Frame", nil, tab)
    reminders:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -SECTION_SPACE)
    reminders:SetSize(PAGE_WIDTH, 190)
    local heading = Heading(reminders, Text.SETTINGS_TAB_REMINDERS, 0)
    InfoIcon(reminders, heading, Text.SETTINGS_TAB_REMINDERS, function(tooltip)
        ns.Tips.Line(tooltip, string.format(Text.TIP_REMINDER_SNOOZE, Core.REMINDER_DISMISS_SECONDS / 60))
    end)
    local keys = { "armour", "unendingBreath", "demon", "healthstone", "soulstone", "weaponStone",
        "sacrifice", "soulLink" }
    for i, key in ipairs(keys) do
        local def = Core.CONTROL_BUTTONS[key]
        local id = Core.SPELLS[def.spells[#def.spells]][1]
        local name = def.label and Text[def.label] or SpellName(id) or key
        local x, y = ((i - 1) % 2) * RIGHT_COLUMN, -17 - math.floor((i - 1) / 2) * 26
        local box = Check(reminders, x, y, name, function() return db().controlButtons[key].on ~= false end,
            function(on) ns.SetSetting("controlButtons." .. key .. ".on", on) end, 98)
        local icon = box:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", box, "RIGHT", 2, 0)
        icon:SetTexture(Plain(C_Spell.GetSpellTexture, key == "demon" and Core.SPELLS.senseDemons[1] or id))
        box.label:ClearAllPoints()
        box.label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        if key == "sacrifice" or key == "soulLink" then
            GreyedBy(box, function() return ns.Buttons.IsKnown(id) end)
        end
    end
    local function choices()
        local list = { { "", Text.SET_DEMON_AUTOMATIC } }
        for _, key in ipairs(Core.DEMON_SUMMON_KEYS) do
            local id = Core.HighestKnown(Core.SPELLS[key], ns.Buttons.IsKnown)
            if id then list[#list + 1] = { key, Text["SET_DEMON_" .. string.upper(key)] } end
        end
        return list
    end
    local presets = Section(reminders, function() return db().controlButtons.sacrifice.on ~= false end)
    for i, field in ipairs({ "preferred", "keep" }) do
        local label = field == "preferred" and Text.SET_SACRIFICE_PREFERRED or Text.SET_SACRIFICE_KEEP
        GreyedBy(Dropdown(presets, (i - 1) * RIGHT_COLUMN, -125, label, choices,
            function() return db().controlButtons.sacrifice[field] end,
            function(key) ns.SetSetting("controlButtons.sacrifice." .. field, key) end, 136),
            function() return ns.Buttons.IsKnown(Core.SPELLS.demonicSacrifice[1])
                and (field == "preferred" or ns.Buttons.IsKnown(Core.SPELLS.demonicPact[1])) end)
    end
    controls[#controls + 1] = { Refresh = function()
        local on = bar.on()
        bar.body:SetShown(on)
        reminders:SetShown(on)
        bar:SetHeight(HEAD_ROW + (on and bar.bodyHeight or 0))
    end }
    table.insert(ns.onSpellsChanged, function() Window.Refresh() end)
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
    local shown = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shown:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, -6)
    shown:SetWidth(PAGE_WIDTH - 17)
    shown:SetJustifyH("LEFT")
    shown:SetJustifyV("TOP")
    box:SetTextColor(0, 0, 0, 0)
    box:SetScript("OnEditFocusGained", function(self)
        self:SetTextColor(1, 1, 1, 1)
        shown:Hide()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        Save(self)
        self:SetTextColor(0, 0, 0, 0)
        shown:SetText(Core.ColourTags(get()))
        shown:Show()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(get())
        self:SetCursorPosition(0)
        self:ClearFocus()
    end)
    function holder:Refresh()
        if box:HasFocus() then return end
        box:SetText(get())
        box:SetCursorPosition(0)
        shown:SetText(Core.ColourTags(get()))
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
    local speech = NewSection(page, Text.SETTINGS_TAB_SPEECH, speechOn, "speech.on", 306, Text.SET_SPEECH_ON)
    speech:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    speech:SetHeight(HEAD_ROW + speech.bodyHeight)
    InfoIcon(speech, speech.heading, Text.SETTINGS_TAB_SPEECH, function(tooltip)
        ns.Tips.Line(tooltip, Text.TIP_SPEECH_PRESETS)
        ns.Tips.Line(tooltip, Text.TIP_SPEECH_NAMES)
    end)
    local rest = speech.body
    local channels = { { "SAY", Text.SET_CHANNEL_SAY }, { "YELL", Text.SET_CHANNEL_YELL }, { "PARTY", Text.SET_CHANNEL_PARTY } }
    local channelList = Dropdown(rest, 0, 0, Text.SET_SPEECH_CHANNEL, channels, function()
        if selectedSubject == "ritualOfSummoning" then return "PARTY" end
        return db().speech.channel
    end, function(value) ns.SetSetting("speech.channel", value) end, 138)

    local subjects = {}
    for i, subject in ipairs(Core.SPEECH_SUBJECTS) do subjects[i] = { subject, SubjectName(subject) } end
    local subjectList = Dropdown(rest, 0, -46, Text.SET_SPEECH_SUBJECT, subjects, function() return selectedSubject end,
        function(value) selectedSubject = value end, 138)
    local ritualInfo = InfoIcon(rest, subjectList.pageLabel, SubjectName("ritualOfSummoning"), function(tooltip)
        ns.Tips.Line(tooltip, Text.TIP_SPEECH_RITUAL)
    end)
    Check(rest, RIGHT_COLUMN, -59, Text.SET_SPEECH_SUBJECT_ON, subjectOn, function(on)
        ns.SetSetting("speech.off." .. selectedSubject, (not on) or nil)
    end)
    controls[#controls + 1] = { Refresh = function()
        local on = speechOn()
        rest:SetShown(on)
        speech:SetHeight(HEAD_ROW + (on and speech.bodyHeight or 0))
        ritualInfo:SetShown(selectedSubject == "ritualOfSummoning")
        local locked = selectedSubject == "ritualOfSummoning"
        channelList:SetEnabled(not locked)
        channelList:SetAlpha(locked and 0.5 or 1)
        channelList.pageLabel:SetAlpha(locked and 0.5 or 1)
    end }
    local lines = Section(rest, subjectOn)

    local PRESET_TOP = -94
    Dropdown(lines, 0, PRESET_TOP, Text.SET_SPEECH_PRESET, function()
        local options = {}
        for i, set in ipairs(Presets()) do
            options[i] = { i, string.format(Text.SET_SPEECH_PRESET_NAME, i,
                Core.ColourTags(Core.PresetName(set, 40, Text.SET_SPEECH_EMPTY))) }
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
        local subject, index = selectedSubject, CurrentPreset()
        local preset = Presets()[index]
        if not preset then return end
        local emote, line = preset.emote, preset.line
        local function Delete()
            local current = Core.SpeechSets(subject, db().speech.sets, Text)[index]
            if not current or current.emote ~= emote or current.line ~= line then return end
            ns.Speech.DeleteSet(subject, index)
        end
        if emote ~= "" or line ~= "" then
            Confirm("deleteSpeech", Text.SET_SPEECH_DELETE_CONFIRM, Text.SET_SPEECH_DELETE, function()
                Delete()
                RefreshAll()
            end, SubjectName(subject))
        else
            Delete()
        end
    end, 62, function() return CurrentPreset() > 0 end)

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

function Window.NewSummonOptions(page, width)
    local panelWidth = width or PAGE_WIDTH
    local function CheckSetting(x, y, label, path, get, labelWidth)
        Check(page, x, y, label, get, function(value)
            ns.SetSetting("summon." .. path, value)
        end, labelWidth or (panelWidth - x - 30)):Refresh()
    end
    Heading(page, Text.SET_SUMMON_WINDOW, 0)
    CheckSetting(0, -18, Text.SET_SUMMON_AUTO_OPEN, "autoOpen", function() return db().summon.autoOpen end)
    Heading(page, Text.SET_SUMMON_LISTEN, -46)
    local wordsTop
    if panelWidth < 250 then
        CheckSetting(0, -60, Text.SET_SUMMON_LISTEN_GROUP, "listen.group", function() return db().summon.listen.group end)
        CheckSetting(0, -82, Text.SET_SUMMON_LISTEN_WHISPER, "listen.whisper", function() return db().summon.listen.whisper end)
        wordsTop = -112
    else
        CheckSetting(0, -58, Text.SET_SUMMON_LISTEN_GROUP, "listen.group", function() return db().summon.listen.group end, 123)
        CheckSetting(155, -58, Text.SET_SUMMON_LISTEN_WHISPER, "listen.whisper", function() return db().summon.listen.whisper end)
        wordsTop = -88
    end

    Heading(page, Text.SET_SUMMON_WORDS, wordsTop)
    Label(page, Text.SET_SUMMON_WORDS_HELP, 0, wordsTop - 16, "GameFontHighlightSmall", panelWidth)
    local boxWidth = panelWidth - 28
    local scroll = CreateFrame("ScrollFrame", "NecrosisOGSummonWordsScroll", page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 2, wordsTop - 38)
    scroll:SetSize(boxWidth, 52)
    local background = scroll:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.5)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetSize(boxWidth, 52)
    scroll:SetScrollChild(box)
    scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
    ScrollingEdit_OnLoad(box)
    box:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
    box:SetScript("OnTextChanged", function(self) ScrollingEdit_OnTextChanged(self, scroll) end)
    box:SetScript("OnUpdate", ScrollingEdit_OnUpdate)
    box:SetText(db().summon.requestWords)
    box:SetCursorPosition(0)
    box:SetScript("OnEditFocusLost", function(self)
        local words = table.concat(Core.SummonWords(self:GetText()), "\n")
        if words ~= db().summon.requestWords then ns.SetSetting("summon.requestWords", words) end
        if self:GetText() ~= words then self:SetText(words) end
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(db().summon.requestWords)
        self:ClearFocus()
    end)
    page:SetScript("OnHide", function() box:ClearFocus() end)
    return -(wordsTop - 38 - 52)
end

local PAGES = {
    { "SETTINGS_TAB_GENERAL", "Ability_Creature_Cursed_03", GeneralPage },
    { "SETTINGS_TAB_SPHERE", "INV_Misc_Gem_Amethyst_02", SpherePage },
    { "SETTINGS_TAB_BUTTONS", "Trade_Engineering", ButtonsPage },
    { "SETTINGS_TAB_MENUS", "INV_Misc_Book_01", MenusPage },
    { "SETTINGS_TAB_ALERTS", "INV_Misc_Bell_01", AlertsPage },
    { "SETTINGS_TAB_REMINDERS", "INV_Misc_PocketWatch_01", RemindersPage },
    { "SETTINGS_TAB_DEBUFFS", Core.SPELLS.baneOfAgony[1], DebuffsPage },
    { "SETTINGS_TAB_ROTATION", Core.SPELLS.lifeTap[1], RotationPage },
    { "SETTINGS_TAB_CONTROLS", "Spell_Shadow_Cripple", ControlsPage },
    { "SETTINGS_TAB_SPEECH", "ability_warrior_rallyingcry", SpeechPage },
}

function Window.ShowPage(index)
    current = index
    for i, page in ipairs(pages) do
        page:SetShown(i == index)
        tabs[i]:SetChecked(i == index)
    end
    pageTitle:SetText(Text[PAGES[index][1]])
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
    button:SetPoint("CENTER", frame, "TOPLEFT", 306, -64)
    FitButton(button, 100)
    button:SetScript("OnClick", function(self)
        Changed(SetLocked)(not db().locked)
        ns.Tips.Redraw(self)
    end)
    ns.Sounds.Button(button)
    ns.Tips.Attach(button, LockTooltip, "ANCHOR_RIGHT", true)
    function button:Refresh()
        self:SetText(db().locked and Text.LOCK_BUTTON_UNLOCK or Text.LOCK_BUTTON_LOCK)
    end
    controls[#controls + 1] = button
    return button
end

local function GuideTooltip(tooltip)
    ns.Tips.Title(tooltip, Text.SET_WELCOME_GUIDE)
end

CreateGuideButton = function()
    local button = CreateFrame("Button", "NecrosisOGGuideButton", frame, "UIPanelButtonTemplate")
    button:SetSize(20, 18)
    button:SetPoint("RIGHT", frame, "TOPRIGHT", -64, -24)
    button:SetText("?")
    button:SetScript("OnClick", function()
        Window.Close()
        ns.Welcome.Show(true)
    end)
    ns.Sounds.Button(button)
    ns.Tips.Attach(button, GuideTooltip, "ANCHOR_RIGHT", true)
    return button
end

-- old stone window look for new frame
function Window.ClassicFrame(window, titleText, secure, extraHeight)
    extraHeight = extraHeight or 0
    Window.TrackScale(window, secure)
    window:SetSize(WIDTH, HEIGHT + extraHeight)
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
        local height = corner[2]:find("^BOTTOM") and 256 + extraHeight or 256
        texture:SetSize(corner[3], height)
        texture:SetTexture(WINDOW_ART .. corner[1])
        texture:SetPoint(corner[2])
    end
    local portrait = window:CreateTexture(nil, "BACKGROUND", nil, 1)
    local PORTRAIT_X, PORTRAIT_Y = 37, -36
    local disc = window:CreateTexture(nil, "BACKGROUND", nil, 0)
    disc:SetSize(72, 72)
    disc:SetPoint("CENTER", window, "TOPLEFT", PORTRAIT_X, PORTRAIT_Y)
    disc:SetColorTexture(0, 0, 0, 1)
    local discMask = window:CreateMaskTexture()
    discMask:SetTexture(Core.UiTexture("Mask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    discMask:SetAllPoints(disc)
    disc:AddMaskTexture(discMask)
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
    ns.Sounds.Button(close)
    return title, line, close
end

-- page inside window dark panel
function Window.NewPage(window)
    local page = CreateFrame("Frame", nil, window)
    page:SetPoint("TOPLEFT", window, "TOPLEFT", PAGE_LEFT, PAGE_TOP)
    page:SetSize(PAGE_WIDTH, PAGE_HEIGHT)
    return page
end

local scaledWindows = {}
local scalePending = false

function Window.TrackScale(window, secure)
    scaledWindows[window] = secure == true
    window:SetScale(Core.WindowScaleOrDefault(db().windowScale) / 100)
end

-- change size of the settings window, keep the corner in place
function Window.ApplyScale()
    local scale = Core.WindowScaleOrDefault(db().windowScale) / 100
    scalePending = false
    for window, secure in pairs(scaledWindows) do
        local old = window:GetScale()
        if old ~= scale then
            if secure and InCombat() then
                scalePending = true
            else
                local point, parent, relativePoint, x, y = window:GetPoint()
                window:SetScale(scale)
                if point and parent == UIParent then
                    window:ClearAllPoints()
                    window:SetPoint(point, parent, relativePoint, x * old / scale, y * old / scale)
                    if window == frame then SavePlace() end
                end
            end
        end
    end
end

ns.OnSetting("windowScale", Window.ApplyScale)
ns.OnSetting("buttons.autoDestroy", function() Window.Refresh() end)

local function Create()
    frame = CreateFrame("Frame", "NecrosisOGSettingsFrame", UIParent)
    local title
    title, pageTitle = Window.ClassicFrame(frame, Text.SETTINGS_TITLE, nil, SETTINGS_EXTRA_HEIGHT)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePlace()
    end)
    local saved = ns.db.settingsWindow
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    local version = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    version:SetPoint("LEFT", title, "RIGHT", 4, 0)
    version:SetTextColor(99 / 255, 227 / 255, 20 / 255)
    version:SetText(Text.SETTINGS_VERSION:format(ns.Version()))
    CreateLockButton()
    CreateGuideButton()
    afterCombatNote = frame:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
    afterCombatNote:SetPoint("TOP", pageTitle, "BOTTOM", 0, -2)
    afterCombatNote:SetText(Text.SETTINGS_AFTER_COMBAT)
    afterCombatNote:Hide()

    local lastTab
    for i, def in ipairs(PAGES) do
        local page = Window.NewPage(frame)
        if def[3] == GeneralPage or def[3] == ButtonsPage or def[3] == MenusPage or def[3] == AlertsPage or def[3] == RemindersPage or def[3] == DebuffsPage then
            page:SetHeight(PAGE_HEIGHT + SETTINGS_EXTRA_HEIGHT)
        end
        def[3](page)
        page:Hide()
        pages[i] = page

        local tab = CreateFrame("CheckButton", nil, frame)
        tab:SetSize(32, 32)
        local art = tab:CreateTexture(nil, "BACKGROUND")
        art:SetSize(64, 64)
        art:SetTexture(TAB_ART)
        if lastTab then
            tab:SetPoint("TOPLEFT", lastTab, "BOTTOMLEFT", 0, -TAB_GAP)
        else
            tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", -32, TAB_TOP)
        end
        art:SetPoint("TOPLEFT", -3, 11)
        lastTab = tab
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
            if i ~= current then ns.Sounds.Play("tab") end
            Window.ShowPage(i)
        end)
        ns.Tips.Attach(tab, function(tooltip) ns.Tips.Title(tooltip, Text[def[1]]) end, "ANCHOR_RIGHT", true)
        tabs[i] = tab
    end

    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, frame:GetName()) end
    frame:SetScript("OnShow", RefreshAll)
    frame:Hide()
    ns.Sounds.Window(frame)
    if ns.AutoHide then ns.AutoHide.AddWindow(frame) end
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

function Window.Close()
    if frame then frame:Hide() end
end

function Window.Refresh()
    if frame and frame:IsShown() then RefreshAll() end
end

function Window.SetLocked(on) Changed(SetLocked)(on) end

-- small page in game options with button open the window
local function RegisterGameOptions()
    if type(Settings) ~= "table" or type(Settings.RegisterCanvasLayoutCategory) ~= "function" then return end
    local panel = CreateFrame("Frame")
    Label(panel, Text.SETTINGS_TITLE, 16, -16, "GameFontNormalLarge")
    local text = Label(panel, Text.SET_OPTIONS_TEXT, 16, -44, "GameFontHighlight", false)
    text:SetWidth(500)
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(170, 24)
    open:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -84)
    open:SetText(Text.SET_OPEN)
    open:SetScript("OnClick", function()
        if not frame then Create() end
        frame:Show()
    end)
    ns.Sounds.Button(open)
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

local function PrintHelp()
    ns.Print(Text.HELP_OPEN)
    ns.Print(Text.HELP_WELCOME)
    ns.Print(Text.HELP_TIMER)
    ns.Print(Text.HELP_HELPER)
    ns.Print(Text.HELP_SUMMON)
    ns.Print(Text.HELP_DEBUG)
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
    elseif command == "debug" then
        local mode = rest:lower()
        if not forWarlock then return ns.Print(Text.COMPARTMENT_NOT_WARLOCK) end
        if mode ~= "party" and mode ~= "raid" and mode ~= "off" then return ns.Print(Text.HELP_DEBUG) end
        if InCombat() then return ns.Print(Text.DEBUG_IN_COMBAT) end
        if mode == "off" and not ns.debugGroup then return ns.Print(Text.DEBUG_OFF) end
        ns.debugGroup = mode ~= "off" and Core.DemoSummon(GetTime(), Text.DEMO_ZONE, mode) or nil
        ns.SoulstoneShortcut.Preview()
        ns.SummonQueue.Update()
        ns.Print(mode == "party" and Text.DEBUG_PARTY or mode == "raid" and Text.DEBUG_RAID or Text.DEBUG_OFF)
    elseif command == "summon" then
        if not forWarlock then
            ns.Print(Text.COMPARTMENT_NOT_WARLOCK)
            return
        end
        ns.SummonQueue.Toggle()
    elseif command == "helper" then
        for _, line in ipairs(ns.BarHighlight and ns.BarHighlight.Report() or {}) do ns.Print(line) end
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
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TALENT_UPDATE" then
        Window.Refresh()
        return
    end
    if scalePending then Window.ApplyScale() end
    if C_Timer and C_Timer.After then C_Timer.After(0, UpdateNote) else UpdateNote() end
end)

Window.Frame = function() return frame end
Window.Pages = function() return pages, tabs end
Window.Current = function() return current end

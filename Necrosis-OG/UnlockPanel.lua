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
local Core, Text = ns.Core, ns.Text
local InCombat = ns.Game.InCombat

local Panel = {}
ns.UnlockPanel = Panel

local PADDING, TITLE_HEIGHT = 14, 24
local BODY_TOP = PADDING + TITLE_HEIGHT
local INNER_WIDTH = 220
local HEAD_HEIGHT = 16
local BUTTON_HEIGHT = 20
local LOOK_ROW = 26
local PRESET_GAP = 4
local SECTION_GAP = 8
local FRAME_STEP = 22
local FOOTER_GAP, FOOTER_HEIGHT = 6, 20
local ACTION_GAP = 6
local POPOUT_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
}

local panel
local hidingForWelcome = false
local reopenSettings = false

local function db() return ns.db end

local function Heading(parent, text, y)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    label:SetJustifyH("LEFT")
    label:SetText(ns.Core.Gradient(text, ns.Core.GRADIENT_HEADING))
    ns.SettingsWindow.FitText(label, INNER_WIDTH)
    return label
end

-- make button, refresh the panel after click
local function Button(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, BUTTON_HEIGHT)
    button:SetText(text)
    ns.SettingsWindow.FitButton(button)
    button:SetScript("OnClick", function()
        onClick()
        Panel.Refresh()
    end)
    ns.Sounds.Button(button)
    return button
end

-- turn on the setting of one preset
local function ApplyPreset(presetKey)
    local changes = Core.PresetChanges(presetKey)
    if not changes then return end
    for _, change in ipairs(changes) do
        ns.SetSetting(change.path, change.value)
    end
    if ns.SettingsWindow and ns.SettingsWindow.Refresh then ns.SettingsWindow.Refresh() end
end

-- switch one frame on or off, it can have many setting
local function ToggleFrame(entry, on)
    for _, path in ipairs(entry.paths) do
        ns.SetSetting(path, on)
    end
    if ns.SettingsWindow and ns.SettingsWindow.Refresh then ns.SettingsWindow.Refresh() end
end

local function Closed()
    if hidingForWelcome then return end
    if UIParent and UIParent.IsShown and not UIParent:IsShown() then return end
    if db() and not db().locked then ns.SettingsWindow.SetLocked(true) end
    if reopenSettings then
        reopenSettings = false
        if ns.SettingsWindow and ns.SettingsWindow.Open then ns.SettingsWindow.Open() end
    end
end

local function Create()
    panel = CreateFrame("Frame", "NecrosisOGUnlockFrame", UIParent, "BackdropTemplate")
    ns.SettingsWindow.TrackScale(panel)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    if panel.SetBackdrop then panel:SetBackdrop(POPOUT_BACKDROP) end
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetPoint("LEFT", UIParent, "LEFT", 20, 0)

    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOP", panel, "TOP", 0, -PADDING)
    heading:SetJustifyH("CENTER")
    heading:SetText(Core.Gradient(Text.UNLOCK_HEADING, Core.GRADIENT_TITLE))
    panel.heading = heading

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING, -(PADDING + TITLE_HEIGHT - 4))
    divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PADDING, -(PADDING + TITLE_HEIGHT - 4))
    divider:SetSize(1, 1)
    divider:SetColorTexture(0.78, 0.65, 0.35, 0.45)
    panel.divider = divider

    local close = CreateFrame("Button", "NecrosisOGUnlockClose", panel, "UIPanelCloseButton")
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() panel:Hide() end)
    ns.Sounds.Button(close)
    panel.close = close

    local page = CreateFrame("Frame", nil, panel)
    page:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING, -BODY_TOP)
    panel.page = page

    local y = 0

    Heading(page, Text.UNLOCK_PRESETS, y)
    y = y + HEAD_HEIGHT
    panel.presets = {}
    local count = #Core.LAYOUT_PRESET_ORDER
    local presetWidth = math.floor((INNER_WIDTH - PRESET_GAP * (count - 1)) / count)
    for i, key in ipairs(Core.LAYOUT_PRESET_ORDER) do
        local preset = Core.LAYOUT_PRESETS[key]
        local button = Button(page, Text[preset.label], presetWidth, function() ApplyPreset(key) end)
        button:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * (presetWidth + PRESET_GAP), -y)
        panel.presets[key] = button
    end
    y = y + BUTTON_HEIGHT + SECTION_GAP

    Heading(page, Text.UNLOCK_FRAMES, y)
    y = y + HEAD_HEIGHT
    panel.checks = {}
    local labelWidth = INNER_WIDTH - 24
    for i, entry in ipairs(Core.FRAME_LIST) do
        local box = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
        box:SetSize(22, 22)
        box:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(y + (i - 1) * FRAME_STEP))
        box.label = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        box.label:SetPoint("LEFT", box, "RIGHT", 2, 0)
        box.label:SetJustifyH("LEFT")
        if box.label.SetWordWrap then box.label:SetWordWrap(false) end
        box.label:SetWidth(labelWidth)
        box.label:SetText(Text[entry.label])
        ns.SettingsWindow.FitText(box.label, labelWidth)
        box:SetScript("OnClick", function(self)
            ToggleFrame(entry, self:GetChecked() == true)
            Panel.Refresh()
        end)
        ns.Sounds.Check(box)
        panel.checks[entry.key] = box
    end
    y = y + #Core.FRAME_LIST * FRAME_STEP + SECTION_GAP

    local window = ns.SettingsWindow
    Heading(page, Text.UNLOCK_LOOK, y)
    y = y + HEAD_HEIGHT
    local sizes = {}
    for i, size in ipairs(Core.TEXT_SIZES) do
        sizes[i] = { size, string.format(Text.SETTINGS_PERCENT_VALUE, size) }
    end
    local width = 124
    local function LookRow(key, label, choices, get)
        window.Dropdown(page, INNER_WIDTH - width, -y, label, choices, get,
            function(value) ns.SetSetting(key, value) end, width, nil, 0)
        y = y + LOOK_ROW
    end
    LookRow("font", Text.SET_FONT, ns.Media.FontChoices, function() return db().font end)
    LookRow("textSize", Text.SET_TEXT_SIZE, sizes, function() return Core.TextSizeOrDefault(db().textSize) end)
    LookRow("barTexture", Text.SET_BAR_TEXTURE, ns.Media.BarChoices, function() return db().barTexture end)
    y = y + SECTION_GAP
    local reset = Button(page, Text.SET_RESET_POSITIONS, INNER_WIDTH, window.ConfirmPositions)
    reset:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
    panel.resetButton = reset
    y = y + BUTTON_HEIGHT
    page:SetSize(INNER_WIDTH, y)

    local footerRule = panel:CreateTexture(nil, "ARTWORK")
    footerRule:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PADDING, PADDING + FOOTER_HEIGHT + FOOTER_GAP)
    footerRule:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PADDING, PADDING + FOOTER_HEIGHT + FOOTER_GAP)
    footerRule:SetSize(1, 1)
    footerRule:SetColorTexture(1, 1, 1, 0.16)
    panel.footerRule = footerRule

    local actionWidth = math.floor((INNER_WIDTH - ACTION_GAP) / 2)
    panel.demoButton = Button(panel, Text.SET_DEMO_START, actionWidth, function() ns.SetDemo(not ns.demoData) end)
    panel.demoButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PADDING, PADDING)
    panel.lockButton = Button(panel, Text.LOCK_BUTTON_LOCK, actionWidth, function() ns.SettingsWindow.SetLocked(true) end)
    panel.lockButton:SetPoint("LEFT", panel.demoButton, "RIGHT", ACTION_GAP, 0)

    local footerBlock = FOOTER_GAP + 1 + FOOTER_GAP + FOOTER_HEIGHT
    panel:SetSize(INNER_WIDTH + PADDING * 2, BODY_TOP + y + footerBlock + PADDING)

    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, panel:GetName()) end
    panel:Hide()
    panel:SetScript("OnShow", function() Panel.Refresh() end)
    panel:SetScript("OnHide", Closed)
    ns.Sounds.Window(panel)
    panel:RegisterEvent("PLAYER_REGEN_DISABLED")
    panel:RegisterEvent("PLAYER_REGEN_ENABLED")
    panel:SetScript("OnEvent", function() Panel.Refresh() end)
end

function Panel.Refresh()
    if not (panel and panel:IsShown()) then return end
    local saved = db()
    local active = Core.ActiveLayoutPreset(saved)
    for key, button in pairs(panel.presets) do
        if active == key then
            if button.LockHighlight then button:LockHighlight() end
        else
            if button.UnlockHighlight then button:UnlockHighlight() end
        end
    end
    for _, entry in ipairs(Core.FRAME_LIST) do
        local box = panel.checks[entry.key]
        if box then box:SetChecked(Core.FrameOn(saved, entry)) end
    end
    panel.demoButton:SetText(ns.demoData and Text.SET_DEMO_STOP or Text.SET_DEMO_START)
    panel.demoButton:SetEnabled(not InCombat())
    panel.resetButton:SetEnabled(not InCombat())
    panel.lockButton:SetText(Text.LOCK_BUTTON_LOCK)
end

function Panel.Show()
    if not panel then Create() end
    local settingsFrame = ns.SettingsWindow and ns.SettingsWindow.Frame and ns.SettingsWindow.Frame()
    if settingsFrame and settingsFrame:IsShown() then
        reopenSettings = true
        ns.SettingsWindow.Close()
    end
    panel:Show()
end

function Panel.HideForWelcome()
    if not (panel and panel:IsShown()) then return end
    hidingForWelcome = true
    panel:Hide()
    hidingForWelcome = false
end

table.insert(ns.onPlacing, function(on)
    if on then
        if ns.Welcome and ns.Welcome.IsActive and ns.Welcome.IsActive() then return end
        Panel.Show()
    elseif panel then
        panel:Hide()
    end
end)

table.insert(ns.onDemoData, function() Panel.Refresh() end)

local watchedPaths = {}
for _, entry in ipairs(Core.FRAME_LIST) do
    for _, path in ipairs(entry.paths) do watchedPaths[#watchedPaths + 1] = path end
end

ns.OnSetting(watchedPaths, function() Panel.Refresh() end)

function Panel.Frame() return panel end

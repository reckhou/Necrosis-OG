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
local Core, Text = ns.Core, ns.Text
local InCombat = ns.Game.InCombat

local Panel = {}
ns.UnlockPanel = Panel

local BUTTON_HEIGHT = 22
local BUTTON_BOTTOM = 14
local PRESET_Y = -20
local PRESET_GAP = 7
local FRAMES_HEAD_Y = -58
local FRAMES_TOP_Y = -78
local FRAME_STEP = 28
local ACTION_GAP = 6

local panel
local hidingForWelcome = false
local reopenSettings = false

local function db() return ns.db end

local function Heading(page, text, y)
    local label = page:CreateFontString(nil, "ARTWORK", "SystemFont_Shadow_Small_Outline")
    label:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
    label:SetJustifyH("LEFT")
    label:SetText(Core.Gradient(text, Core.GRADIENT_HEADING))
    ns.SettingsWindow.FitText(label, ns.SettingsWindow.PAGE_WIDTH)
    return label
end

-- make button, refresh the panel after click
local function Button(page, text, width, onClick)
    local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    button:SetSize(width, BUTTON_HEIGHT)
    button:SetText(text)
    ns.SettingsWindow.FitButton(button)
    button:SetScript("OnClick", function()
        onClick()
        Panel.Refresh()
    end)
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
    panel = CreateFrame("Frame", "NecrosisOGUnlockFrame", UIParent)
    local _, heading = ns.SettingsWindow.ClassicFrame(panel, Text.SETTINGS_TITLE)
    heading:SetText(Text.UNLOCK_HEADING)
    panel.heading = heading
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetPoint("TOP", UIParent, "TOP", 0, -60)

    local page = ns.SettingsWindow.NewPage(panel)
    panel.page = page

    Heading(page, Text.UNLOCK_PRESETS, 0)
    panel.presets = {}
    local count = #Core.LAYOUT_PRESET_ORDER
    local presetWidth = math.floor((ns.SettingsWindow.PAGE_WIDTH - PRESET_GAP * (count - 1)) / count)
    for i, key in ipairs(Core.LAYOUT_PRESET_ORDER) do
        local preset = Core.LAYOUT_PRESETS[key]
        local button = Button(page, Text[preset.label], presetWidth, function() ApplyPreset(key) end)
        button:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * (presetWidth + PRESET_GAP), PRESET_Y)
        panel.presets[key] = button
    end

    Heading(page, Text.UNLOCK_FRAMES, FRAMES_HEAD_Y)
    panel.checks = {}
    for i, entry in ipairs(Core.FRAME_LIST) do
        local box = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
        box:SetSize(26, 26)
        box:SetPoint("TOPLEFT", page, "TOPLEFT", 0, FRAMES_TOP_Y - (i - 1) * FRAME_STEP)
        box.label = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        box.label:SetPoint("LEFT", box, "RIGHT", 2, 0)
        box.label:SetJustifyH("LEFT")
        box.label:SetWidth(ns.SettingsWindow.PAGE_WIDTH - 30)
        box.label:SetText(Text[entry.label])
        box:SetScript("OnClick", function(self)
            ToggleFrame(entry, self:GetChecked() == true)
            Panel.Refresh()
        end)
        panel.checks[entry.key] = box
    end

    local actionWidth = math.floor((ns.SettingsWindow.PAGE_WIDTH - 8 - ACTION_GAP) / 2)
    panel.demoButton = Button(page, Text.SET_DEMO_START, actionWidth, function() ns.SetDemo(not ns.demoData) end)
    panel.demoButton:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 4, BUTTON_BOTTOM)
    panel.lockButton = Button(page, Text.LOCK_BUTTON_LOCK, actionWidth, function() ns.SettingsWindow.SetLocked(true) end)
    panel.lockButton:SetPoint("LEFT", panel.demoButton, "RIGHT", ACTION_GAP, 0)

    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, panel:GetName()) end
    panel:Hide()
    panel:SetScript("OnShow", function() Panel.Refresh() end)
    panel:SetScript("OnHide", Closed)
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

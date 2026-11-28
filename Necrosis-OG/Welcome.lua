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

-- welcome card, show once for new charactor
local _, ns = ...
local Core, Text = ns.Core, ns.Text
local Plain, InCombat = ns.Game.Plain, ns.Game.InCombat

local Welcome = {}
ns.Welcome = Welcome

local LINE_GAP = 8
local PRESET_GAP = 7
local BUTTON_HEIGHT = 22
local BUTTON_GAP = 4
local BUTTON_BOTTOM = 14

local ICON = 32
local PICTURE = ICON
local FOCUS_SIZE = ICON
local BUTTON_ROW_GAP = 4
local TEXT_LEFT = PICTURE + 12
local SAMPLE_SHARDS = 16
local SAMPLE_ENEMY = 1
local SAMPLE_GAP = 4

local BUTTON_ROW = {
    { slot = "soulstone", fallback = "SoulstoneButton-01" },
    { slot = "healthstone", fallback = "HealthstoneButton-01" },
    { slot = "demons", fallback = "PetMenuButton-01" },
    { slot = "curses", fallback = "CurseMenuButton-01" },
}

local function Lead(lead, rest, perCode)
    return Core.Gradient(lead, Core.GRADIENT_HEADING, nil, perCode) .. " |cffffffff" .. rest .. "|r"
end

local function Gold(text)
    return "|cffffd100" .. text .. "|cffffffff"
end

local PRESET_DESC = {
    full = "WELCOME_PRESET_FULL",
    lite = "WELCOME_PRESET_LITE",
    minimal = "WELCOME_PRESET_MINIMAL",
}

local VIEWS = {
    minimal = { "sphere", "buttons" },
    lite = { "litePlus", "reminder", "alert", "highlight" },
    full = { "fullPlus", "multi", "focus", "missing" },
}

local LITE_SPELLS = {
    reminder = Core.SPELLS.soulLink[1],
    alert = Core.PROC_BUFFS.shadowTrance[1],
    highlight = Core.SPELLS.corruption[1],
}

local card
local welcomePending = false
local returnToSettings = false

local function db() return ns.db end

local function Line(page, font, width)
    local line = page:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    line:SetWidth(width or ns.SettingsWindow.PAGE_WIDTH)
    line:SetJustifyH("LEFT")
    return line
end

local function Picture(page)
    local holder = CreateFrame("Frame", nil, page)
    holder:SetSize(PICTURE, PICTURE)
    holder.texture = holder:CreateTexture(nil, "ARTWORK")
    holder.texture:SetAllPoints()
    return holder
end

-- shard picture of current skin with the count
local function SpherePicture(page)
    local holder = Picture(page)
    holder.count = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    holder.count:SetPoint("CENTER")
    holder.count:SetText(tostring(SAMPLE_SHARDS))
    return holder
end

local function ButtonsRow(page)
    local holder = CreateFrame("Frame", nil, page)
    holder:SetSize(#BUTTON_ROW * ICON + (#BUTTON_ROW - 1) * BUTTON_ROW_GAP, ICON)
    holder.icons = {}
    for i = 1, #BUTTON_ROW do
        local texture = holder:CreateTexture(nil, "ARTWORK")
        texture:SetSize(ICON, ICON)
        texture:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (ICON + BUTTON_ROW_GAP), 0)
        holder.icons[i] = texture
    end
    return holder
end

local function Button(page, text, width, onClick)
    local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    button:SetSize(width, BUTTON_HEIGHT)
    button:SetText(text)
    ns.SettingsWindow.FitButton(button)
    button:SetScript("OnClick", function()
        onClick()
        Welcome.Refresh()
    end)
    ns.Sounds.Button(button)
    return button
end

-- stop the demo and print how to open again
local function Closed()
    if UIParent and UIParent.IsShown and not UIParent:IsShown() then return end
    if ns.demoData then ns.SetDemo(false) end
    if db() and not db().locked then ns.SettingsWindow.SetLocked(true) end
    ns.Print(Text.WELCOME_AGAIN)
    if returnToSettings then
        returnToSettings = false
        ns.SettingsWindow.Open()
    end
end

local function LockOrUnlock()
    if db().locked then
        ns.SettingsWindow.SetLocked(false)
    else
        ns.SettingsWindow.SetLocked(true)
        if ns.demoData then ns.SetDemo(false) end
    end
end

local function ApplyPreset(presetKey)
    local changes = Core.PresetChanges(presetKey)
    if not changes then return end
    for _, change in ipairs(changes) do
        ns.SetSetting(change.path, change.value)
    end
    if ns.SettingsWindow and ns.SettingsWindow.Refresh then ns.SettingsWindow.Refresh() end
end

local function PlaceCard()
    local saved = (ns.db and ns.db.settingsWindow) or Core.DEFAULTS.settingsWindow
    card:ClearAllPoints()
    card:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
end

local function Create()
    card = CreateFrame("Frame", "NecrosisOGWelcomeFrame", UIParent)
    local _, heading = ns.SettingsWindow.ClassicFrame(card, Text.SETTINGS_TITLE)
    heading:SetText(Text.WELCOME_HEADING)
    card.heading = heading
    card:SetScript("OnDragStop", card.StopMovingOrSizing)
    PlaceCard()

    local page = ns.SettingsWindow.NewPage(card)
    card.page = page
    card.presets = {}
    local presetCount = #Core.LAYOUT_PRESET_ORDER
    local presetWidth = math.floor((ns.SettingsWindow.PAGE_WIDTH - PRESET_GAP * (presetCount - 1)) / presetCount)
    for i, key in ipairs(Core.LAYOUT_PRESET_ORDER) do
        local preset = Core.LAYOUT_PRESETS[key]
        local button = Button(page, Text[preset.label], presetWidth, function() ApplyPreset(key) end)
        button:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * (presetWidth + PRESET_GAP), 0)
        card.presets[key] = button
    end
    card.presetDesc = Line(page)
    card.presetDesc:SetTextColor(0.85, 0.85, 0.85)
    local textWidth = ns.SettingsWindow.PAGE_WIDTH - TEXT_LEFT

    card.spherePicture = SpherePicture(page)
    card.sphere = Line(page, nil, textWidth)
    card.sphere:SetText(Lead(Text.WELCOME_SPHERE_LEAD, Text.WELCOME_SPHERE))
    card.buttonsRow = ButtonsRow(page)
    card.buttons = Line(page)
    card.buttons:SetText(Lead(Text.WELCOME_BUTTONS_LEAD, Text.WELCOME_BUTTONS))

    card.litePlus = Line(page)
    card.litePlus:SetText(Text.WELCOME_INCLUDES_MINIMAL)
    card.reminderPicture = Picture(page)
    card.reminder = Line(page, nil, textWidth)
    card.reminder:SetText(Lead(Text.SET_REMINDER_BAR, Text.WELCOME_REMINDER))
    card.alertPicture = Picture(page)
    card.alert = Line(page, nil, textWidth)
    local alertRest = string.format(Text.WELCOME_ALERT,
        Gold(ns.Game.SpellName(Core.PROC_BUFFS.shadowTrance[1]) or ""), Gold(Text.WELCOME_IMMUNE))
    card.alert:SetText(Lead(Text.SET_PROC_BAR, alertRest, 3))
    card.highlightPicture = Picture(page)
    card.highlight = Line(page, nil, textWidth)
    card.highlight:SetText(Lead(Text.SET_ACTION_BAR_GLOWS, Text.WELCOME_HIGHLIGHT))

    card.fullPlus = Line(page)
    card.fullPlus:SetText(Text.WELCOME_INCLUDES_LITE)
    card.multi = Line(page)
    card.multi:SetText(Lead(Text.SET_DEBUFF_TRACKER, Text.WELCOME_MULTI))
    card.sample = ns.Debuffs and ns.Debuffs.Sample and ns.Debuffs.Sample(page, SAMPLE_ENEMY) or nil
    card.focus = Line(page)
    card.focus:SetText(Lead(Text.TIMER_LIST_FOCUS, Text.WELCOME_FOCUS))
    card.focusSample = ns.Debuffs and ns.Debuffs.FocusSample and ns.Debuffs.FocusSample(page, FOCUS_SIZE) or nil
    card.missing = Line(page)
    card.missing:SetText(Lead(Text.SET_MISSING_TARGET, Text.WELCOME_MISSING))

    card.blocks = {
        sphere = { line = card.sphere, picture = card.spherePicture },
        buttons = { line = card.buttons, under = card.buttonsRow, underHeight = PICTURE },
        litePlus = { line = card.litePlus },
        reminder = { line = card.reminder, picture = card.reminderPicture },
        alert = { line = card.alert, picture = card.alertPicture },
        highlight = { line = card.highlight, picture = card.highlightPicture },
        fullPlus = { line = card.fullPlus },
        multi = { line = card.multi, under = card.sample, underHeight = Core.MULTI_BLOCK },
        focus = { line = card.focus, under = card.focusSample, underHeight = FOCUS_SIZE },
        missing = { line = card.missing },
    }

    card.note = Line(page)
    card.note:SetText(Text.WELCOME_NOTE)
    card.note:SetTextColor(0.6, 0.6, 0.6)

    card.demoButton = Button(page, Text.SET_DEMO_START, 104, function() ns.SetDemo(not ns.demoData) end)
    card.demoButton:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 4, BUTTON_BOTTOM)
    card.lockButton = Button(page, Text.LOCK_BUTTON_LOCK, 64, LockOrUnlock)
    card.lockButton:SetPoint("LEFT", card.demoButton, "RIGHT", BUTTON_GAP, 0)
    card.settingsButton = Button(page, Text.SET_OPEN, 106, function()
        returnToSettings = false
        card:Hide()
        ns.SettingsWindow.Open()
    end)
    card.settingsButton:SetPoint("LEFT", card.lockButton, "RIGHT", BUTTON_GAP, 0)

    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, card:GetName()) end
    card:Hide()
    card:SetScript("OnShow", function() Welcome.Refresh() end)
    card:SetScript("OnHide", Closed)
    ns.Sounds.Window(card)
    card:RegisterEvent("PLAYER_REGEN_DISABLED")
    card:RegisterEvent("PLAYER_REGEN_ENABLED")
    card:SetScript("OnEvent", function() Welcome.Refresh() end)
end

-- only show blocks of chosen preset, from top to down
local function Layout(active)
    local page = card.page
    local view = VIEWS[active] or VIEWS.minimal
    local showing = {}
    for _, key in ipairs(view) do showing[key] = true end
    for key, block in pairs(card.blocks) do
        local show = showing[key] == true
        block.line:SetShown(show)
        if block.picture then block.picture:SetShown(show) end
        if block.under then block.under:SetShown(show) end
    end

    local y = BUTTON_HEIGHT + 4
    card.presetDesc:ClearAllPoints()
    card.presetDesc:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
    y = y + card.presetDesc:GetStringHeight() + LINE_GAP
    for _, key in ipairs(view) do
        local block = card.blocks[key]
        local line = block.line
        line:ClearAllPoints()
        if block.picture then
            block.picture:ClearAllPoints()
            block.picture:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
            line:SetPoint("LEFT", page, "TOPLEFT", TEXT_LEFT, -(y + PICTURE / 2))
            y = y + math.max(PICTURE, line:GetStringHeight()) + LINE_GAP
        else
            line:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
            y = y + line:GetStringHeight() + LINE_GAP
            if block.under then
                block.under:ClearAllPoints()
                block.under:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(y - LINE_GAP + SAMPLE_GAP))
                y = y - LINE_GAP + SAMPLE_GAP + block.underHeight + LINE_GAP
            end
        end
    end

    local room = ns.SettingsWindow.PAGE_HEIGHT - BUTTON_BOTTOM - BUTTON_HEIGHT - LINE_GAP
    local fits = y + card.note:GetStringHeight() <= room
    card.note:ClearAllPoints()
    card.note:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
    card.note:SetShown(fits)
end

function Welcome.Refresh()
    if not (card and card:IsShown()) then return end
    local saved = db()
    local locked = saved.locked
    local active = Core.ActiveLayoutPreset(saved)
    for key, button in pairs(card.presets) do
        if active == key then
            if button.LockHighlight then button:LockHighlight() end
        else
            if button.UnlockHighlight then button:UnlockHighlight() end
        end
    end
    card.presetDesc:SetText(Text[PRESET_DESC[active] or "WELCOME_PRESET_CUSTOM"])
    card.spherePicture.texture:SetTexture(Core.ShardTexture(saved.skin, SAMPLE_SHARDS))
    for part, spell in pairs(LITE_SPELLS) do
        local picture = card.blocks[part].picture
        picture.texture:SetTexture(Plain(C_Spell.GetSpellTexture, spell))
    end
    for i, item in ipairs(BUTTON_ROW) do
        local texture = card.buttonsRow.icons[i]
        local kind, value = nil, nil
        if ns.Buttons and ns.Buttons.SlotIcon then kind, value = ns.Buttons.SlotIcon(item.slot) end
        if kind == "atlas" then
            texture:SetAtlas(value)
        elseif kind == "texture" then
            texture:SetTexture(value)
        else
            texture:SetTexture(Core.UiTexture(item.fallback))
        end
    end
    card.lockButton:SetText(locked and Text.LOCK_BUTTON_UNLOCK or Text.LOCK_BUTTON_LOCK)
    card.demoButton:SetText(ns.demoData and Text.SET_DEMO_STOP or Text.SET_DEMO_START)
    card.demoButton:SetEnabled(not InCombat())
    Layout(active)
end

function Welcome.IsActive()
    return welcomePending or (card ~= nil and card:IsShown() == true)
end

function Welcome.Show(fromSettings)
    welcomePending = false
    returnToSettings = fromSettings == true
    if not card then Create() end
    if ns.UnlockPanel and ns.UnlockPanel.HideForWelcome then ns.UnlockPanel.HideForWelcome() end
    PlaceCard()
    card:Show()
end

table.insert(ns.onDemoData, function() Welcome.Refresh() end)
table.insert(ns.onPlacing, function() Welcome.Refresh() end)
local watchedPaths = {}
for _, entry in ipairs(Core.FRAME_LIST) do
    for _, path in ipairs(entry.paths) do watchedPaths[#watchedPaths + 1] = path end
end

ns.OnSetting(watchedPaths, function() Welcome.Refresh() end)

table.insert(ns.onSphere, function()
    if not (ns.db and ns.db.welcomed == false) then return end
    ns.db.welcomed = true
    welcomePending = true
    if C_Timer and C_Timer.After then C_Timer.After(1, Welcome.Show) else Welcome.Show() end
end)

Welcome.Frame = function() return card end

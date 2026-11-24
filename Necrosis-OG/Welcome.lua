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

-- welcome card, show once for new charactor
local _, ns = ...
local Core, Text = ns.Core, ns.Text
local Plain, InCombat = ns.Game.Plain, ns.Game.InCombat

local Welcome = {}
ns.Welcome = Welcome

local LINE_GAP = 12
local BUTTON_HEIGHT = 22
local BUTTON_GAP = 4
local BUTTON_BOTTOM = 14
local LINK_HEIGHT = 14

local PICTURE = 40
local FOCUS_SIZE = 24
local TEXT_LEFT = PICTURE + 12
local SAMPLE_SHARDS = 16
local SAMPLE_ENEMY = 1
local SAMPLE_GAP = 6
local BUTTON_PICTURES = { "SoulstoneButton-02", "HealthstoneButton-02", "PetMenuButton-01", "CurseMenuButton-01" }
local GOLD = "|cffffd100%s|r %s"
local WARNING_COLOUR = { 1, 0.48, 0.35 }
local PLATES = "nameplateShowEnemies"

local card

local function db() return ns.db end

-- true when enemy nameplate setting is off
local function PlatesOff()
    return C_CVar and Plain(C_CVar.GetCVar, PLATES) == "0"
end

local function SwitchOnPlates()
    if InCombat() or not (C_CVar and C_CVar.SetCVar) then return end
    pcall(C_CVar.SetCVar, PLATES, "1")
end

local function Line(page, font, width)
    local line = page:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    line:SetWidth(width or ns.SettingsWindow.PAGE_WIDTH)
    line:SetJustifyH("LEFT")
    return line
end

-- shard picture of current skin with the count
local function SpherePicture(page)
    local holder = CreateFrame("Frame", nil, page)
    holder:SetSize(PICTURE, PICTURE)
    holder.texture = holder:CreateTexture(nil, "ARTWORK")
    holder.texture:SetAllPoints()
    holder.count = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    holder.count:SetPoint("CENTER")
    holder.count:SetText(tostring(SAMPLE_SHARDS))
    return holder
end

local function ButtonsPicture(page)
    local holder = CreateFrame("Frame", nil, page)
    holder:SetSize(PICTURE, PICTURE)
    local size = (PICTURE - 4) / 2
    for i, name in ipairs(BUTTON_PICTURES) do
        local texture = holder:CreateTexture(nil, "ARTWORK")
        texture:SetSize(size, size)
        texture:SetPoint("TOPLEFT", holder, "TOPLEFT", ((i - 1) % 2) * (size + 4), -math.floor((i - 1) / 2) * (size + 4))
        texture:SetTexture(Core.UiTexture(name))
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
    return button
end

local function Link(page, text, onClick)
    local link = CreateFrame("Button", nil, page)
    link:SetSize(80, LINK_HEIGHT)
    link.label = link:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    link.label:SetAllPoints()
    link.label:SetJustifyH("LEFT")
    link.label:SetText(text)
    link:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1) end)
    link:SetScript("OnLeave", function(self) self.label:SetTextColor(1, 0.82, 0) end)
    link:SetScript("OnClick", function()
        onClick()
        Welcome.Refresh()
    end)
    return link
end

-- stop the demo and print how to open again
local function Closed()
    if UIParent and UIParent.IsShown and not UIParent:IsShown() then return end
    if ns.demoData then ns.SetDemo(false) end
    ns.Print(Text.WELCOME_AGAIN)
end

local function Create()
    card = CreateFrame("Frame", "NecrosisOGWelcomeFrame", UIParent)
    local _, heading = ns.SettingsWindow.ClassicFrame(card, Text.SETTINGS_TITLE)
    heading:SetText(Text.WELCOME_HEADING)
    card.heading = heading
    card:SetScript("OnDragStop", card.StopMovingOrSizing)
    card:SetPoint("TOP", UIParent, "TOP", 380, -60)

    local page = ns.SettingsWindow.NewPage(card)
    card.page = page
    local textWidth = ns.SettingsWindow.PAGE_WIDTH - TEXT_LEFT
    card.spherePicture = SpherePicture(page)
    card.sphere = Line(page, nil, textWidth)
    card.sphere:SetText(GOLD:format(Text.WELCOME_SPHERE_LEAD, Text.WELCOME_SPHERE))
    card.buttonsPicture = ButtonsPicture(page)
    card.buttons = Line(page, nil, textWidth)
    card.buttons:SetText(GOLD:format(Text.WELCOME_BUTTONS_LEAD, Text.WELCOME_BUTTONS))
    card.multi = Line(page)
    card.multi:SetText(GOLD:format(Text.SET_MULTI_ON, Text.WELCOME_MULTI))
    card.sample = ns.Debuffs and ns.Debuffs.Sample and ns.Debuffs.Sample(page, SAMPLE_ENEMY) or nil
    card.focus = Line(page)
    card.focus:SetText(GOLD:format(Text.TIMER_LIST_FOCUS, Text.WELCOME_FOCUS))
    card.focusSample = ns.Debuffs and ns.Debuffs.FocusSample and ns.Debuffs.FocusSample(page, FOCUS_SIZE) or nil
    card.under = {}
    if card.sample then card.under[card.multi] = { card.sample, Core.MULTI_BLOCK } end
    if card.focusSample then card.under[card.focus] = { card.focusSample, FOCUS_SIZE } end
    card.warning = Line(page)
    card.warning:SetText(Text.WELCOME_PLATES_OFF:format(Text.SET_MULTI_ON))
    card.warning:SetTextColor(WARNING_COLOUR[1], WARNING_COLOUR[2], WARNING_COLOUR[3])
    card.switchOn = Link(page, Text.WELCOME_PLATES_SWITCH, SwitchOnPlates)
    card.note = Line(page)
    card.note:SetText(Text.WELCOME_NOTE)
    card.note:SetTextColor(0.6, 0.6, 0.6)

    card.demoButton = Button(page, Text.WELCOME_SHOW_ALL, 112, function() ns.SetDemo(not ns.demoData) end)
    card.demoButton:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 4, BUTTON_BOTTOM)
    card.lockButton = Button(page, Text.LOCK_BUTTON_LOCK, 56, function() ns.SettingsWindow.SetLocked(not db().locked) end)
    card.lockButton:SetPoint("LEFT", card.demoButton, "RIGHT", BUTTON_GAP, 0)
    card.settingsButton = Button(page, Text.SET_OPEN, 104, function() ns.SettingsWindow.Open() end)
    card.settingsButton:SetPoint("LEFT", card.lockButton, "RIGHT", BUTTON_GAP, 0)

    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, card:GetName()) end
    card:Hide()
    card:SetScript("OnShow", function() Welcome.Refresh() end)
    card:SetScript("OnHide", Closed)
    card:RegisterEvent("PLAYER_REGEN_DISABLED")
    card:RegisterEvent("PLAYER_REGEN_ENABLED")
    card:SetScript("OnEvent", function() Welcome.Refresh() end)
end

-- put lines from top to down, warning only show when nameplates off
local function Layout()
    local page = card.page
    local y = 0
    for _, row in ipairs({ { card.spherePicture, card.sphere }, { card.buttonsPicture, card.buttons } }) do
        row[1]:ClearAllPoints()
        row[1]:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
        row[2]:ClearAllPoints()
        row[2]:SetPoint("LEFT", page, "TOPLEFT", TEXT_LEFT, -(y + PICTURE / 2))
        y = y + math.max(PICTURE, row[2]:GetStringHeight()) + LINE_GAP
    end
    local shown = { card.multi, card.focus }
    local platesOff = PlatesOff()
    card.warning:SetShown(platesOff)
    card.switchOn:SetShown(platesOff)
    if platesOff then shown[#shown + 1] = card.warning end
    for _, line in ipairs(shown) do
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
        y = y + line:GetStringHeight() + LINE_GAP
        local under = card.under[line]
        if under then
            under[1]:ClearAllPoints()
            under[1]:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(y - LINE_GAP + SAMPLE_GAP))
            y = y - LINE_GAP + SAMPLE_GAP + under[2] + LINE_GAP
        elseif line == card.warning then
            card.switchOn:ClearAllPoints()
            card.switchOn:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(y - LINE_GAP + 2))
            y = y + LINK_HEIGHT
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
    local locked = db().locked
    card.spherePicture.texture:SetTexture(Core.ShardTexture(db().skin, SAMPLE_SHARDS))
    card.lockButton:SetText(locked and Text.LOCK_BUTTON_UNLOCK or Text.LOCK_BUTTON_LOCK)
    card.demoButton:SetText(ns.demoData and Text.SET_DEMO_STOP or Text.WELCOME_SHOW_ALL)
    local fighting = InCombat()
    card.switchOn:SetEnabled(not fighting)
    if fighting then card.switchOn.label:SetTextColor(0.5, 0.5, 0.5) else card.switchOn.label:SetTextColor(1, 0.82, 0) end
    Layout()
end

function Welcome.Show()
    if not card then Create() end
    card:Show()
end

table.insert(ns.onDemoData, function() Welcome.Refresh() end)
table.insert(ns.onPlacing, function() Welcome.Refresh() end)

table.insert(ns.onSphere, function()
    if not (ns.db and ns.db.welcomed == false) then return end
    ns.db.welcomed = true
    if C_Timer and C_Timer.After then C_Timer.After(1, Welcome.Show) else Welcome.Show() end
end)

Welcome.Frame = function() return card end

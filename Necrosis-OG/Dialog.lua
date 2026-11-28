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

-- small confirm box of the add on
local _, ns = ...
local Core = ns.Core

local Dialog = {}
ns.Dialog = Dialog

local DIALOG_PAD, DIALOG_TITLE, DIALOG_INNER = 14, 24, 360
local DIALOG_BUTTON_WIDTH, DIALOG_FOOTER, DIALOG_GAP = 170, 22, 6
local DIALOG_BODY_TOP = DIALOG_PAD + DIALOG_TITLE
local DIALOG_TEXT_GAP = 12
local DIALOG_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
}

-- make new box with yes and no button
function Dialog.New(opts)
    local name, secure, reload = opts.name, opts.secure == true, opts.reload == true
    local frame = CreateFrame("Frame", name, UIParent,
        secure and "SecureHandlerStateTemplate, BackdropTemplate" or "BackdropTemplate")
    frame:SetWidth(DIALOG_INNER + DIALOG_PAD * 2)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    if frame.SetBackdrop then frame:SetBackdrop(DIALOG_BACKDROP) end
    if ns.SettingsWindow and ns.SettingsWindow.TrackScale then
        ns.SettingsWindow.TrackScale(frame, secure or reload)
    end

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -DIALOG_PAD)
    title:SetJustifyH("CENTER")
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", DIALOG_PAD, -(DIALOG_TITLE + DIALOG_PAD - 4))
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -DIALOG_PAD, -(DIALOG_TITLE + DIALOG_PAD - 4))
    divider:SetSize(1, 1)
    divider:SetColorTexture(0.78, 0.65, 0.35, 0.45)

    local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", DIALOG_PAD, -DIALOG_BODY_TOP)
    text:SetWidth(DIALOG_INNER)
    text:SetJustifyH("CENTER")

    local ruleY = DIALOG_PAD + DIALOG_FOOTER + DIALOG_GAP
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", DIALOG_PAD, ruleY)
    rule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -DIALOG_PAD, ruleY)
    rule:SetSize(1, 1)
    rule:SetColorTexture(1, 1, 1, 0.16)

    local function Button(buttonName, x, action)
        local button = CreateFrame("Button", buttonName, frame,
            action and "SecureActionButtonTemplate, UIPanelButtonTemplate" or "UIPanelButtonTemplate")
        button:SetSize(DIALOG_BUTTON_WIDTH, DIALOG_FOOTER)
        button:SetPoint("BOTTOM", frame, "BOTTOM", x, DIALOG_PAD)
        button:RegisterForClicks("AnyUp")
        if action then
            button:SetAttribute("useOnKeyDown", false)
        end
        if secure then SecureHandlerSetFrameRef(button, "dialog", frame) end
        return button
    end
    local half = DIALOG_BUTTON_WIDTH / 2 + DIALOG_GAP / 2
    local dialog = { frame = frame, title = title, text = text }
    dialog.yes = Button(opts.yesName or name .. "Yes", -half, secure or reload)
    dialog.no = Button(opts.noName or name .. "No", half, secure)
    if reload then
        dialog.yes:SetAttribute("type", "macro")
        dialog.yes:SetAttribute("macrotext", "/reload")
    end

    function dialog.SetTitle(words) title:SetText(Core.Gradient(words, Core.GRADIENT_TITLE)) end
    function dialog.Fit()
        local height = text.GetStringHeight and text:GetStringHeight() or 0
        frame:SetHeight(DIALOG_BODY_TOP + height + DIALOG_TEXT_GAP + 1 + DIALOG_FOOTER + DIALOG_GAP + DIALOG_PAD)
    end
    if opts.title then dialog.SetTitle(opts.title) end
    dialog.Fit()
    frame:Hide()
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
    ns.Sounds.Dialog(frame)
    ns.Sounds.Button(dialog.yes, "yes")
    ns.Sounds.Button(dialog.no, "cancel")
    return dialog
end

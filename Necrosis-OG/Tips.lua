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

-- tooltips of addon
local _, ns = ...
local Text = ns.Text

local Tips = {}
ns.Tips = Tips

local LABEL = { 1, 0.82, 0 }
local BODY = { 1, 1, 1 }
local NOTE = { 0.6, 0.6, 0.6 }
local GOOD = { 0.5, 1, 0.5 }

local CLICKS = {
    any = "CLICK_ANY", left = "CLICK_LEFT", right = "CLICK_RIGHT", middle = "CLICK_MIDDLE",
    shift = "CLICK_SHIFT", ctrl = "CLICK_CTRL", ctrlRight = "CLICK_CTRL_RIGHT", wheel = "CLICK_WHEEL",
    drag = "CLICK_DRAG",
}
Tips.CLICKS = CLICKS

function Tips.Title(tooltip, text, r, g, b) tooltip:SetText(text or "", r, g, b) end

function Tips.Line(tooltip, text)
    if text and text ~= "" then tooltip:AddLine(text, BODY[1], BODY[2], BODY[3], true) end
end

function Tips.Note(tooltip, text)
    if text and text ~= "" then tooltip:AddLine(text, NOTE[1], NOTE[2], NOTE[3], true) end
end

function Tips.Good(tooltip, text)
    if text and text ~= "" then tooltip:AddLine(text, GOOD[1], GOOD[2], GOOD[3], true) end
end

function Tips.Pair(tooltip, label, value)
    tooltip:AddDoubleLine(label, value, LABEL[1], LABEL[2], LABEL[3], BODY[1], BODY[2], BODY[3])
end

-- one line of a click and what it do
function Tips.Click(tooltip, click, action)
    if action then Tips.Pair(tooltip, Text[CLICKS[click] or click], action) end
end

-- show tooltip unless the switch is off or frame faded
function Tips.Show(frame)
    local build = frame and frame.tooltip
    if not build or frame.faded or type(GameTooltip) ~= "table" then return end
    if not frame.tooltipAlways and not ns.TooltipsOn() then return end
    GameTooltip:SetOwner(frame, frame.tooltipAnchor or "ANCHOR_LEFT")
    if build(GameTooltip, frame) == false then
        GameTooltip:Hide()
        return
    end
    GameTooltip:Show()
end

function Tips.Hide()
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
end

function Tips.Redraw(frame)
    if type(GameTooltip) == "table" and GameTooltip.IsOwned and GameTooltip:IsOwned(frame) then Tips.Show(frame) end
end

-- set tooltip on frame, build() write the lines
function Tips.Attach(frame, build, anchor, always)
    frame.tooltip, frame.tooltipAnchor, frame.tooltipAlways = build, anchor, always
    frame:SetScript("OnEnter", Tips.Show)
    frame:SetScript("OnLeave", Tips.Hide)
end

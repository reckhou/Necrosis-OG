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

-- tooltips of addon
local _, ns = ...
local Text = ns.Text

local Tips = {}
ns.Tips = Tips

local LABEL = { 1, 0.82, 0 }
local BODY = { 1, 1, 1 }
local NOTE = { 0.6, 0.6, 0.6 }
local GOOD = { 0.5, 1, 0.5 }

local function Hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

local CLICKS = {
    any = "CLICK_ANY", left = "CLICK_LEFT", right = "CLICK_RIGHT", middle = "CLICK_MIDDLE",
    shift = "CLICK_SHIFT", ctrl = "CLICK_CTRL", ctrlRight = "CLICK_CTRL_RIGHT", wheel = "CLICK_WHEEL",
    shiftRight = "CLICK_SHIFT_RIGHT",
    drag = "CLICK_DRAG",
}
Tips.CLICKS = CLICKS

local function Mark(text, rest)
    if type(text) ~= "string" then return text end
    rest = rest or Hex(BODY)
    if text:find("[", 1, true) then
        text = text:gsub("%[tab%](.-)%[/tab%]", "|cffffff00%1|r" .. rest)
        text = text:gsub("%[head%](.-)%[/head%]", function(name)
            return ns.Core.TipHeading(name) .. rest
        end)
    end
    return ns.Core.ColourTags(text)
end

Tips.Mark = Mark

function Tips.Title(tooltip, text, r, g, b)
    tooltip:SetText(Mark(text, r and Hex({ r, g, b }) or nil) or "", r, g, b)
end

function Tips.Line(tooltip, text)
    if text and text ~= "" then tooltip:AddLine(Mark(text, Hex(BODY)), BODY[1], BODY[2], BODY[3], true) end
end

function Tips.Note(tooltip, text)
    if text and text ~= "" then tooltip:AddLine(Mark(text, Hex(NOTE)), NOTE[1], NOTE[2], NOTE[3], true) end
end

function Tips.Good(tooltip, text)
    if text and text ~= "" then tooltip:AddLine(Mark(text, Hex(GOOD)), GOOD[1], GOOD[2], GOOD[3], true) end
end

function Tips.Pair(tooltip, label, value)
    tooltip:AddDoubleLine(Mark(label, Hex(LABEL)), Mark(value), LABEL[1], LABEL[2], LABEL[3], BODY[1], BODY[2], BODY[3])
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

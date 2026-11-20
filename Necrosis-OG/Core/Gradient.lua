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

-- gradient color text, one color code for each letter
local _, ns = ...
local Core = ns.Core

Core.GRADIENT_HEADING = { { 0xC0, 0x50, 0xFF }, { 0xE0, 0x50, 0xFF }, { 0xFF, 0x66, 0xF0 }, { 0xFF, 0x99, 0xF5 },
    { 0xFF, 0xC4, 0xFF } }
Core.GRADIENT_TITLE = { { 0xFF, 0x00, 0xFF }, { 0xFF, 0x50, 0xFF }, { 0xFF, 0x99, 0xFF }, { 0xFF, 0xC4, 0xFF },
    { 0xFF, 0xFF, 0xFF } }

Core.GRADIENT_SPAN = 9

function Core.Gradient(text, stops, span)
    local letters = {}
    for letter in string.gmatch(text, "[%z\1-\127\194-\244][\128-\191]*") do letters[#letters + 1] = letter end
    local count = 0
    for _, letter in ipairs(letters) do
        if letter ~= " " then count = count + 1 end
    end
    if count == 0 then return text end
    local points = {}
    for i, stop in ipairs(stops) do
        points[i] = { #stops > 1 and (i - 1) / (#stops - 1) or 0, stop[1], stop[2], stop[3] }
    end
    local out, place, last = {}, 0, nil
    for _, letter in ipairs(letters) do
        if letter ~= " " then
            local x = 0
            if count > 1 then
                local run = math.min(count, span or Core.GRADIENT_SPAN) - 1
                local at = place % (2 * run)
                if at > run then at = 2 * run - at end
                x = at / run
            end
            local r, g, b = Core.ColourAt(points, x)
            local code = string.format("|cff%02x%02x%02x", math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
            if code ~= last then
                out[#out + 1] = code
                last = code
            end
            place = place + 1
        end
        out[#out + 1] = letter
    end
    out[#out + 1] = "|r"
    return table.concat(out)
end

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

-- threat ring math
local _, ns = ...
local Core = ns.Core
local isNumber = Core.IsNumber

Core.RING_SEGMENTS = 120
Core.RING_SEGMENT_WIDTH, Core.RING_SEGMENT_HEIGHT = 12, 4
Core.RING_THICKNESS = 8

function Core.ThreatPercent(scaledPercentage)
    if not isNumber(scaledPercentage) then return 0 end
    return math.max(0, math.min(100, scaledPercentage))
end

Core.THREAT_COLOUR_POINTS = { { 0, 0, 1, 0 }, { 0.5, 1, 1, 0 }, { 0.8, 1, 0, 0 }, { 1, 1, 0, 0 } }

function Core.ThreatColor(percent)
    return Core.ColourAt(Core.THREAT_COLOUR_POINTS, Core.ThreatPercent(percent) / 100)
end

Core.THREAT_STATE_COLOURS = { [0] = { 0, 1, 0 }, [1] = { 1, 1, 0 }, [2] = { 1, 0.6, 0 }, [3] = { 1, 0, 0 } }

function Core.ThreatStateColour(state)
    local colour = isNumber(state) and Core.THREAT_STATE_COLOURS[state] or nil
    if not colour then return nil end
    return colour[1], colour[2], colour[3]
end

function Core.ThreatAlpha(percent)
    return math.min(1, 0.2 + Core.ThreatPercent(percent) / 100 * 0.8)
end

-- needle angle in radian, 0% at top and go clockwise
function Core.ThreatNeedleAngle(percent)
    return math.rad(90 - Core.ThreatPercent(percent) / 100 * 359)
end

Core.THREAT_EASE = 6
Core.THREAT_EASE_STOP = 0.2

function Core.ThreatEase(current, goal, dt, speed)
    goal = Core.ThreatPercent(goal)
    if not isNumber(current) then return goal end
    local gap = goal - current
    if math.abs(gap) < Core.THREAT_EASE_STOP then return goal end
    local rate = Core.THREAT_EASE * (isNumber(speed) and speed > 0 and speed or 1)
    local nextPercent = current + gap * (1 - math.exp(-rate * math.max(0, isNumber(dt) and dt or 0)))
    if math.abs(goal - nextPercent) < Core.THREAT_EASE_STOP then return goal end
    return nextPercent
end

Core.THREAT_FLASH_SECONDS = 0.8
Core.THREAT_FLASH_LOW = 0.25
Core.THREAT_FLASH_TINT = 0.35

local function FlashWave(elapsed)
    local part = (math.max(0, isNumber(elapsed) and elapsed or 0) / Core.THREAT_FLASH_SECONDS) % 1
    return part < 0.5 and part * 2 or (1 - part) * 2
end

function Core.ThreatFlashAlpha(elapsed)
    return 1 - (1 - Core.THREAT_FLASH_LOW) * FlashWave(elapsed)
end

function Core.ThreatFlashTint(elapsed)
    return Core.THREAT_FLASH_TINT * (1 - FlashWave(elapsed))
end

function Core.ThreatFlashColor(r, g, b, tint)
    local t = isNumber(tint) and math.max(0, math.min(1, tint)) or 0
    return r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t
end

-- ring segment offset and rotation for sphere size
function Core.RingSegments(sphereSize)
    local radius = sphereSize / 2 + 2
    local segments = {}
    for i = 1, Core.RING_SEGMENTS do
        local angle = math.rad(i / Core.RING_SEGMENTS * 360)
        segments[i] = { x = radius * math.cos(angle), y = radius * math.sin(angle), rotation = angle + math.pi / 2 }
    end
    return segments
end

function Core.NeedleOffset(sphereSize, percent)
    local radius = sphereSize / 2 + Core.RING_THICKNESS / 4
    local angle = Core.ThreatNeedleAngle(percent)
    return radius * math.cos(angle), radius * math.sin(angle), angle
end

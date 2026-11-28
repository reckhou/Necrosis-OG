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

-- path and timing of the soul orbs
local _, ns = ...
local Core = ns.Core
local isNumber = Core.IsNumber

Core.ORB_COUNT = 3
Core.ORB_COLOR = { 0.71, 0.42, 1.0 }
Core.ORB_CORE_COLOR = { 0.88, 0.78, 1.0 }
Core.ORB_SIZE = 44
Core.ORB_SPEED_SCALE = 0.75
Core.ORB_BLOOM_SECONDS = 0.16
Core.ORB_FLIGHT_SECONDS = 0.72
Core.ORB_FLIGHT_JITTER = 0.08
Core.ORB_STAGGER = 0.03
Core.ORB_TRAIL_COUNT = 4
Core.ORB_TRAIL_STEP = 0.024
Core.ORB_FLASH_SECONDS = 0.38
Core.ORB_MAX_BURSTS = 3
Core.ORB_DEFAULT_Y = 0.50

function Core.OrbGain(previous, current)
    if not isNumber(previous) or not isNumber(current) or current <= previous then return 0 end
    return current - previous
end

function Core.OrbCubic(t, p0, p1, p2, p3)
    local u = 1 - t
    return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
end

function Core.OrbEase(p)
    if not isNumber(p) then return 0 end
    if p <= 0 then return 0 elseif p >= 1 then return 1 end
    return 0.5 * (1 - (1 - p) ^ 3) + 0.5 * (p ^ 2.2)
end

-- points of the curve for one orb
function Core.OrbControlPoints(index, count, startX, startY, destX, destY, screenH, rand)
    rand = rand or math.random
    count = math.max(1, isNumber(count) and count or Core.ORB_COUNT)
    index = isNumber(index) and index or 1
    local angle = ((((index - 1) * 0.618034) % 1) + rand() * (0.8 / count)) * 2 * math.pi
    local ringR = 22 + rand() * 24
    local ringX = startX + math.cos(angle) * ringR
    local ringY = startY + math.sin(angle) * ringR
    local dx, dy = destX - startX, destY - startY
    local dist = math.sqrt(dx * dx + dy * dy)
    local bowSign = (isNumber(screenH) and screenH > 0 and startY > screenH * 0.5) and -1 or 1
    local spreadAngle = (((index - 1) + rand() * 0.7) / count) * 2 * math.pi
    local spreadR = 45 + rand() * 55
    local c1x = startX + math.cos(spreadAngle) * spreadR * 1.9
    local c1y = startY + math.sin(spreadAngle) * spreadR * 1.4 + 40 * bowSign
    local c2x = destX + (c1x - destX) * 0.15
    local c2y = destY + bowSign * math.min(120, dist * 0.26)
    return ringX, ringY, c1x, c1y, c2x, c2y
end

function Core.OrbOrigin(screenW, screenH)
    local w = isNumber(screenW) and screenW > 0 and screenW or 1024
    local h = isNumber(screenH) and screenH > 0 and screenH or 768
    return w / 2, h * Core.ORB_DEFAULT_Y
end

-- position, size and alpha of orb at this age
function Core.OrbPosition(orb, age)
    if not isNumber(age) or age <= 0 then
        return false, orb.startX, orb.startY, 1, 0
    end
    local bloomDur = isNumber(orb.bloomDur) and orb.bloomDur > 0 and orb.bloomDur or Core.ORB_BLOOM_SECONDS
    local flightDur = isNumber(orb.flightDur) and orb.flightDur > 0 and orb.flightDur or Core.ORB_FLIGHT_SECONDS
    if age < bloomDur then
        local p = age / bloomDur
        local eased = 1 - (1 - p) ^ 2.2
        local x = orb.startX + (orb.ringX - orb.startX) * eased
        local y = orb.startY + (orb.ringY - orb.startY) * eased
        local alpha = math.min(1, p / 0.25)
        local scale = 1.4 - 0.4 * eased
        return true, x, y, scale, alpha
    end
    local p = math.min(1, (age - bloomDur) / flightDur)
    local eased = Core.OrbEase(p)
    local x = Core.OrbCubic(eased, orb.ringX, orb.c1x, orb.c2x, orb.destX)
    local y = Core.OrbCubic(eased, orb.ringY, orb.c1y, orb.c2y, orb.destY)
    local scale = p > 0.8 and (1 - 0.38 * ((p - 0.8) / 0.2)) or 1
    local alpha = p > 0.85 and (1 - 0.35 * ((p - 0.85) / 0.15)) or 1
    return true, x, y, scale, alpha
end

function Core.OrbStep(orb, dt)
    dt = isNumber(dt) and dt > 0 and dt or 0
    if orb.delay and orb.delay > 0 then
        orb.delay = orb.delay - dt
        if orb.delay > 0 then
            return false, orb.startX, orb.startY, 1, 0, false
        end
        dt = -orb.delay
        orb.delay = 0
    end
    orb.age = (orb.age or 0) + dt
    local bloomDur = isNumber(orb.bloomDur) and orb.bloomDur > 0 and orb.bloomDur or Core.ORB_BLOOM_SECONDS
    local flightDur = isNumber(orb.flightDur) and orb.flightDur > 0 and orb.flightDur or Core.ORB_FLIGHT_SECONDS
    if orb.age >= bloomDur + flightDur then
        return false, orb.destX, orb.destY, 0.62, 0, true
    end
    local visible, x, y, scale, alpha = Core.OrbPosition(orb, orb.age)
    return visible, x, y, scale, alpha, false
end

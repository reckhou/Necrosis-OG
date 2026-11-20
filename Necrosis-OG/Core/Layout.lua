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

-- layout rules of buttons, menus and drag
local _, ns = ...
local Core = ns.Core
local isNumber = Core.IsNumber

Core.BUTTON_SLOTS = { "soulstone", "healthstone", "utility", "curses", "demons", "shards", "mount", "spellstone",
    "firestone" }
Core.BUTTON_SIZE = 34

Core.BUTTON_SCALE = 1.11
Core.BUTTON_SIZE_MIN, Core.BUTTON_SIZE_MAX, Core.BUTTON_SIZE_STEP = 0.5, 2.0, 0.05

Core.BUTTON_RADIUS = 42 * 1.05
Core.BUTTON_FIRST_ANGLE = 207
Core.BUTTON_ANGLE_STEP = 39.204

Core.ROTATION_MIN, Core.ROTATION_MAX, Core.ROTATION_STEP = 0, 360, 9
Core.SPACING_MIN, Core.SPACING_MAX, Core.SPACING_STEP = 0.5, 2.0, 0.05
Core.DISTANCE_MIN, Core.DISTANCE_MAX, Core.DISTANCE_STEP = 0.8, 2.0, 0.05
Core.MENU_ITEM_SIZE = 40
Core.MENU_ITEM_STEP = 32

Core.MENU_ICON_INSET = 5

-- round value to nearest step
function Core.RoundToStep(value, step)
    if not isNumber(value) then return value end
    local rounded = math.floor(value / step + 0.5) * step
    return tonumber(string.format("%.4f", rounded))
end

local function Clamp(value, low, high, step, default)
    if not isNumber(value) then return default end
    return Core.RoundToStep(math.max(low, math.min(high, value)), step)
end

Core.ClampValue = Clamp

function Core.ClampRotation(value)
    return Clamp(value, Core.ROTATION_MIN, Core.ROTATION_MAX, Core.ROTATION_STEP, Core.DEFAULTS.sphere.rotation)
end

function Core.ClampSpacing(value)
    return Clamp(value, Core.SPACING_MIN, Core.SPACING_MAX, Core.SPACING_STEP, Core.DEFAULTS.sphere.spacing)
end

function Core.ClampDistance(value)
    return Clamp(value, Core.DISTANCE_MIN, Core.DISTANCE_MAX, Core.DISTANCE_STEP, Core.DEFAULTS.sphere.distance)
end

function Core.ClampButtonSize(value)
    return Clamp(value, Core.BUTTON_SIZE_MIN, Core.BUTTON_SIZE_MAX, Core.BUTTON_SIZE_STEP, Core.DEFAULTS.sphere.buttonSize)
end

function Core.ButtonScale(size)
    return Core.BUTTON_SCALE * Core.ClampButtonSize(size)
end

-- offsets of shown buttons around the sphere center
function Core.ButtonOffsets(count, rotation, spacing, distance)
    local defaults = Core.DEFAULTS.sphere
    rotation, spacing, distance = Core.ClampRotation(rotation), Core.ClampSpacing(spacing), Core.ClampDistance(distance)
    local first = Core.BUTTON_FIRST_ANGLE + (rotation - defaults.rotation)
    local step = Core.BUTTON_ANGLE_STEP * spacing / defaults.spacing
    local radius = Core.BUTTON_RADIUS * distance / defaults.distance
    local offsets = {}
    for i = 1, count do
        local angle = math.rad(first - (i - 1) * step)
        offsets[i] = { x = radius * math.cos(angle), y = radius * math.sin(angle) }
    end
    return offsets
end

Core.MENU_DIRECTIONS = { "up", "down", "left", "right" }
Core.MENU_DEFAULT_DIRECTION = { demons = "up", utility = "up", curses = "up" }

local UPSTREAM_DIRECTION = { demons = "up", utility = "left", curses = "right" }
local DIRECTION_STEPS = { up = { 0, 1 }, down = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
Core.MENU_FIRST_DISTANCE = 36

Core.DEMONS_CALIBRATION = { x = -53, y = -5 }

function Core.MenuDirection(menu, direction)
    if DIRECTION_STEPS[direction] then return direction end
    return Core.MENU_DEFAULT_DIRECTION[menu] or "up"
end

-- offset of i-th spell in menu from its button
function Core.MenuOffset(menu, i, direction)
    direction = Core.MenuDirection(menu, direction)
    local step = (i - 1) * Core.MENU_ITEM_STEP
    if direction == UPSTREAM_DIRECTION[menu] then
        if menu == "demons" then return 55 + Core.DEMONS_CALIBRATION.x, 43 + Core.DEMONS_CALIBRATION.y + step end
        if menu == "curses" then return 33 + step, 32 end
        return -24 - step, 30
    end
    local d = DIRECTION_STEPS[direction]
    local distance = Core.MENU_FIRST_DISTANCE + step
    return d[1] * distance, d[2] * distance
end

Core.MENU_SHIFT_MIN, Core.MENU_SHIFT_MAX, Core.MENU_SHIFT_STEP = -100, 100, 1

function Core.ClampMenuShift(value)
    return Clamp(value, Core.MENU_SHIFT_MIN, Core.MENU_SHIFT_MAX, Core.MENU_SHIFT_STEP, 0)
end

function Core.MenuShift(saved)
    if type(saved) ~= "table" then return 0, 0 end
    return Core.ClampMenuShift(saved.x), Core.ClampMenuShift(saved.y)
end

function Core.MenuEntryId(entry) return entry.keys[1] end

Core.SPHERE_CLICKS = {
    { key = "left", prefix = "", button = "1", text = "CLICK_LEFT" },
    { key = "middle", prefix = "", button = "3", text = "CLICK_MIDDLE" },
    { key = "ctrlLeft", prefix = "ctrl-", button = "1", text = "CLICK_CTRL" },
    { key = "shiftLeft", prefix = "shift-", button = "1", text = "CLICK_SHIFT" },
}

function Core.SphereClickEntry(value)
    for _, entry in ipairs(Core.UTILITY_MENU) do
        if Core.MenuEntryId(entry) == value then return entry end
    end
    return nil
end

function Core.SphereClick(key, value)
    if value == "none" or value == "bags" or Core.SphereClickEntry(value) then return value end
    return Core.DEFAULTS.sphere.clicks[key]
end

-- menu entries in player order, then the rest
function Core.OrderMenu(list, saved)
    local byId, used, ordered = {}, {}, {}
    for _, entry in ipairs(list) do byId[Core.MenuEntryId(entry)] = entry end
    if type(saved) == "table" then
        for _, id in ipairs(saved) do
            if byId[id] and not used[id] then
                used[id] = true
                ordered[#ordered + 1] = byId[id]
            end
        end
    end
    for _, entry in ipairs(list) do
        local id = Core.MenuEntryId(entry)
        if not used[id] then
            used[id] = true
            ordered[#ordered + 1] = entry
        end
    end
    return ordered
end

function Core.MenuEntryOff(saved, entry)
    return type(saved) == "table" and saved[Core.MenuEntryId(entry)] == true
end

function Core.OrderSlots(saved)
    local entries = {}
    for i, slot in ipairs(Core.BUTTON_SLOTS) do entries[i] = { keys = { slot } } end
    local ordered = {}
    for i, entry in ipairs(Core.OrderMenu(entries, saved)) do ordered[i] = entry.keys[1] end
    return ordered
end

function Core.MoveSlot(saved, from, to)
    local entries = {}
    for i, slot in ipairs(Core.BUTTON_SLOTS) do entries[i] = { keys = { slot } } end
    return Core.MoveInOrder(entries, saved, from, to)
end

-- new order after drag entry from -> to, return list of names
function Core.MoveInOrder(list, saved, from, to)
    local ids = {}
    for i, entry in ipairs(Core.OrderMenu(list, saved)) do ids[i] = Core.MenuEntryId(entry) end
    if not ids[from] or not ids[to] or from == to then return ids end
    local id = table.remove(ids, from)
    table.insert(ids, to, id)
    return ids
end

function Core.DragSlot(down, rowHeight, count)
    if not isNumber(down) or not isNumber(rowHeight) or rowHeight <= 0 or not isNumber(count) or count < 1 then return 1 end
    return math.max(1, math.min(math.floor(count), math.floor(down / rowHeight) + 1))
end

-- place of row index while dragging from -> to
function Core.DragPlace(index, from, to)
    if index == from then return to end
    if from < to and index > from and index <= to then return index - 1 end
    if from > to and index >= to and index < from then return index + 1 end
    return index
end

function Core.DragSource(place, from, to)
    if place == to then return from end
    if from < to and place >= from and place < to then return place + 1 end
    if from > to and place > to and place <= from then return place - 1 end
    return place
end

Core.DRAG_EASE = 22

function Core.EaseToward(current, goal, dt, speed)
    if not isNumber(current) or not isNumber(goal) then return goal end
    local gap = goal - current
    if math.abs(gap) < 0.5 then return goal end
    local rate = Core.DRAG_EASE * (isNumber(speed) and speed > 0 and speed or 1)
    return current + gap * (1 - math.exp(-rate * math.max(0, isNumber(dt) and dt or 0)))
end

function Core.TempEnchant(enchants)
    if type(enchants) ~= "table" then return false, nil end
    for _, enchant in pairs(enchants) do
        if type(enchant) == "table" and enchant.hasEnchant == true and enchant.enchantType ~= 1 then
            local left = isNumber(enchant.timeLeft) and enchant.timeLeft > 0 and enchant.timeLeft / 1000 or nil
            return true, left
        end
    end
    return false, nil
end

Core.ENCHANT_LENGTH = 7200

function Core.EnchantSpan(left, now)
    local length = math.max(Core.ENCHANT_LENGTH, left)
    return now - (length - left), length, now + left
end

-- "29m" for minutes, "45" for seconds
function Core.CooldownText(remaining)
    if not isNumber(remaining) or remaining <= 0 then return "" end
    if remaining >= 60 then return math.floor(remaining / 60) .. "m" end
    return tostring(math.ceil(remaining))
end

Core.COOLDOWN_TEXT_RULES = {
    { threshold = 0, step = 1, rounding = "Up", format = "%d" },
    { threshold = 60, format = "%dm", components = { { div = 60, step = 1, rounding = "Down" } } },
}

Core.COOLDOWN_RED_WINDOW = 120
Core.COOLDOWN_FLASH_LEAD = 30

function Core.CooldownTextPoints(total)
    if not isNumber(total) or total <= 0 then total = Core.COOLDOWN_RED_WINDOW end
    local window = math.min(total, Core.COOLDOWN_RED_WINDOW)
    local half = Core.FLASH_SECONDS / 2
    local steps = math.floor(math.min(Core.COOLDOWN_FLASH_LEAD, window) / half)
    local function point(x, opacity)
        local fade = math.min(1, x / window)
        return { x, 1, fade, fade, opacity }
    end
    local points = {}
    for step = 0, steps do points[#points + 1] = point(step * half, step % 2 == 0 and 1 or Core.FLASH_LOW) end
    if points[#points][1] < window then points[#points + 1] = point(window, 1) end
    points[#points + 1] = { Core.FLASH_FAR_SECONDS, 1, 1, 1, 1 }
    return points
end

-- sec left of cooldown, short one is ignore
function Core.CooldownLeft(start, duration, now)
    if not (isNumber(start) and isNumber(duration) and isNumber(now)) then return 0 end
    if start <= 0 or duration <= 2 then return 0 end
    return math.max(0, start + duration - now)
end

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

-- red cover on button when target is out of range
local _, ns = ...
local Core = ns.Core

local RangeCover = {}
ns.RangeCover = RangeCover

local IsSecret, Plain, InCombat = ns.Game.IsSecret, ns.Game.Plain, ns.Game.InCombat

local covers = {}

local function Draw(cover, ok, inRange)
    local alpha = Core.FOCUS_RANGE_ALPHA
    if ok and IsSecret(inRange) then
        if not pcall(cover.texture.SetAlphaFromBoolean, cover.texture, inRange, 0, alpha) then
            cover.texture:SetAlpha(0)
        end
    else
        cover.texture:SetAlpha(ok and inRange == false and alpha or 0)
    end
end

-- if spell can reach the target
local function SpellReaches(spellID)
    if type(C_Spell) ~= "table" or type(C_Spell.IsSpellInRange) ~= "function" then return false end
    return pcall(C_Spell.IsSpellInRange, spellID, "target")
end

local function ReadSpell(spell)
    return function()
        local spellID, key = spell()
        if not spellID or not Core.TakesRangeCover(key) then return false end
        if Plain(C_Spell and C_Spell.SpellHasRange, spellID) == false then return false end
        return SpellReaches(spellID)
    end
end

local function StoneSpell(itemID)
    if type(C_Item) ~= "table" or type(C_Item.GetItemSpell) ~= "function" then return nil end
    local ok, _, spellID = pcall(C_Item.GetItemSpell, itemID)
    if ok and not IsSecret(spellID) and type(spellID) == "number" then return spellID end
    return nil
end

-- if unit is living friendly player
function RangeCover.IsFriendlyPlayer(unit)
    if Plain(UnitIsPlayer, unit) ~= true or Plain(UnitIsDeadOrGhost, unit) == true
        or Plain(UnitCanAttack, "player", unit) == true then
        return false
    end
    return Plain(UnitCanAssist, "player", unit) == true or Plain(UnitIsVisible, unit) == false
end

-- if soulstone can reach this unit
function RangeCover.StoneReaches(unit)
    if not unit then return false end
    if unit == "player" or Plain(UnitIsUnit, unit, "player") == true then return true, true end
    if Plain(UnitExists, unit) ~= true then return false end
    if Plain(UnitIsConnected, unit) == false or Plain(UnitIsVisible, unit) == false then return true, false end
    local held = ns.Stones.State().soulstone
    if not held then return false end
    local spellID = StoneSpell(held.id)
    if spellID and type(C_Spell) == "table" and type(C_Spell.IsSpellInRange) == "function" then
        local ok, inRange = pcall(C_Spell.IsSpellInRange, spellID, unit)
        if ok and (IsSecret(inRange) or inRange ~= nil) then return ok, inRange end
    end
    if not InCombat() and type(C_Item) == "table" and type(C_Item.IsItemInRange) == "function" then
        local ok, inRange = pcall(C_Item.IsItemInRange, held.id, unit)
        if ok and (IsSecret(inRange) or inRange ~= nil) then return ok, inRange end
    end
    if type(UnitInRange) == "function" then
        local ok, inRange, checked = pcall(UnitInRange, unit)
        if ok and (IsSecret(inRange) or (checked == true and inRange ~= nil)) then return ok, inRange end
    end
    return false
end

function RangeCover.SoulstoneOnTarget()
    if not ns.Stones.State().soulstone or Plain(UnitIsUnit, "target", "player") == true
        or not RangeCover.IsFriendlyPlayer("target") then
        return false
    end
    return RangeCover.StoneReaches("target")
end

local function Update(cover)
    if ns.demo or cover.owner:IsVisible() ~= true then
        cover.texture:SetAlpha(0)
        return
    end
    Draw(cover, cover.read())
end

local function UpdateAll()
    for _, cover in ipairs(covers) do Update(cover) end
end

local ticker

local function Watch()
    local wanted = #covers > 0 and Plain(UnitExists, "target") == true
    if wanted and not ticker and C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(Core.FOCUS_RANGE_SECONDS, UpdateAll)
    elseif not wanted and ticker then
        ticker:Cancel()
        ticker = nil
    end
    if wanted then
        UpdateAll()
    else
        for _, cover in ipairs(covers) do cover.texture:SetAlpha(0) end
    end
end

-- put red cover on a frame
local function New(frame, size, owner, read)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints(frame)
    holder:SetFrameLevel(frame:GetFrameLevel() + 1)
    local texture = holder:CreateTexture(nil, "OVERLAY", nil, 2)
    texture:SetPoint("CENTER", frame, "CENTER", 0, 0)
    texture:SetSize(size * Core.SWIPE_WIDTH, size * Core.SWIPE_HEIGHT)
    texture:SetTexture(Core.UiTexture("Swipe"))
    texture:SetVertexColor(1, 0, 0, 1)
    texture:SetAlpha(0)
    local cover = { frame = frame, owner = owner, texture = texture, read = read }
    covers[#covers + 1] = cover
    return cover
end

function RangeCover.AddSpell(frame, size, owner, spell)
    local cover = New(frame, size, owner, ReadSpell(spell))
    owner:HookScript("OnShow", function() if ticker then Update(cover) end end)
    return cover
end

function RangeCover.AddSoulstone(button, face)
    return New(face or button, Core.BUTTON_SIZE, button, RangeCover.SoulstoneOnTarget)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", Watch)
table.insert(ns.onSphere, function() events:RegisterEvent("PLAYER_TARGET_CHANGED") end)
table.insert(ns.onDemo, Watch)

RangeCover.All = function() return covers end
RangeCover.Watching = function() return ticker ~= nil end
RangeCover.Update = UpdateAll

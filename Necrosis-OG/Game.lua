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

-- safe call to game api
local _, ns = ...

local Game = {}
ns.Game = Game

function Game.IsSecret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return not ok or secret == true
end

local IsSecret = Game.IsSecret

-- value of the call, nil if it fail or value is secret
function Game.Plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or IsSecret(value) then return nil end
    return value
end

local Plain = Game.Plain

function Game.InCombat() return InCombatLockdown() == true end

function Game.Latency()
    local ok, _, _, home, world = pcall(GetNetStats)
    if not ok then return 0 end
    local ms = (type(world) == "number" and world > 0) and world or home
    return ns.Core.LatencySeconds(ms)
end

function Game.SpellName(id)
    if not id then return nil end
    return Plain(C_Spell and C_Spell.GetSpellName, id)
end

if ns.Core and ns.Core.AddDurationWord then
    ns.Core.AddDurationWord(rawget(_G, "INT_SPELL_DURATION_SEC"), 1)
    ns.Core.AddDurationWord(rawget(_G, "INT_SPELL_DURATION_MIN"), 60)
end

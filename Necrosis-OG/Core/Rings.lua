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

-- ring tint color of each icon
local _, ns = ...
local Core = ns.Core
local copy = Core.Copy

Core.RING_ICON_LIFT = 0.35
Core.RING_ICON_PRESSED = 0.75

Core.COOLDOWN_DIM = 0.8
Core.SWIPE_WIDTH = 108 / 128
Core.SWIPE_HEIGHT = 104 / 128

Core.RING_TINT = {
    Agony = { 0.860, 0.140, 0.166 },
    AntiFearImmune = { 0.925, 0.075, 0.464 },
    Aqua = { 0.162, 0.494, 0.838 },
    Armor = { 0.730, 0.250, 0.750 },
    Banish = { 0.112, 0.888, 0.289 },
    BuffMenuButton = { 0.925, 0.075, 0.101 },
    CurseMenuButton = { 0.225, 0.775, 0.368 },
    Doom = { 0.075, 0.925, 0.656 },
    Doomguard = { 0.925, 0.075, 0.223 },
    Elements = { 0.404, 0.079, 0.921 },
    Enslave = { 0.269, 0.175, 0.825 },
    Exhaust = { 0.750, 0.260, 0.250 },
    Felhunter = { 0.750, 0.351, 0.250 },
    FirestoneButton = { 0.877, 0.123, 0.155 },
    HealthstoneButton = { 0.165, 0.915, 0.085 },
    Imp = { 0.075, 0.925, 0.193 },
    Inccubus = { 0.825, 0.175, 0.434 },
    Infernal = { 0.145, 0.867, 0.133 },
    Invisible = { 0.099, 0.901, 0.518 },
    Kilrogg = { 0.763, 0.369, 0.237 },
    MountButton = { 0.925, 0.075, 0.104 },
    PetMenuButton = { 0.470, 0.093, 0.907 },
    Reckless = { 0.822, 0.178, 0.219 },
    ShadowProtection = { 0.608, 0.075, 0.925 },
    ShardDestroy = { 0.566, 0.108, 0.892 },
    SoulstoneButton = { 0.585, 0.088, 0.912 },
    SpellstoneButton = { 0.381, 0.128, 0.872 },
    Succubus = { 0.250, 0.675, 0.750 },
    Tongues = { 0.911, 0.089, 0.339 },
    TP = { 0.533, 0.237, 0.763 },
    Voidwalker = { 0.075, 0.112, 0.925 },
    Weakness = { 0.182, 0.818, 0.354 },
    healthFunnel = { 0.877, 0.123, 0.401 },
    senseDemons = { 0.889, 0.111, 0.310 },
    soulLink = { 0.709, 0.250, 0.750 },
    demonicSacrifice = { 0.200, 0.338, 0.800 },
    lifeTap = { 0.454, 0.075, 0.925 },
    drainSoul = { 0.168, 0.537, 0.832 },
    drainMana = { 0.134, 0.519, 0.866 },
    howlOfTerror = { 0.750, 0.391, 0.250 },
    fear = { 0.250, 0.293, 0.750 },
    baneOfHavoc = { 0.881, 0.119, 0.420 },
    deathCoil = { 0.205, 0.875, 0.125 },
    felDomination = { 0.138, 0.862, 0.590 },
    unendingBreath = { 0.198, 0.528, 0.802 },
    banish = { 0.105, 0.895, 0.193 },
    seduction = { 0.789, 0.290, 0.211 },
    curseOfRecklessness = { 0.812, 0.188, 0.226 },
    curseOfWeakness = { 0.181, 0.819, 0.250 },
    shadowTrance = { 0.544, 0.250, 0.750 },
    decimation = { 0.925, 0.075, 0.107 },
    amplifyCurse = { 0.750, 0.732, 0.250 },
    classWarlock = { 0.596, 0.250, 0.750 },
    soulShard = { 0.732, 0.078, 0.922 },
    imp = { 0.075, 0.925, 0.193 },
    voidwalker = { 0.075, 0.112, 0.925 },
    succubus = { 0.250, 0.675, 0.750 },
    incubus = { 0.825, 0.175, 0.434 },
    felhunter = { 0.750, 0.351, 0.250 },
    inferno = { 0.145, 0.867, 0.133 },
    ritualOfDoom = { 0.925, 0.075, 0.223 },
    enslaveDemon = { 0.269, 0.175, 0.825 },
    demonSkin = { 0.730, 0.250, 0.750 },
    demonArmor = { 0.730, 0.250, 0.750 },
    detectInvisibility = { 0.099, 0.901, 0.518 },
    eyeOfKilrogg = { 0.763, 0.369, 0.237 },
    ritualOfSummoning = { 0.533, 0.237, 0.763 },
    shadowWard = { 0.608, 0.075, 0.925 },
    baneOfAgony = { 0.860, 0.140, 0.166 },
    curseOfTongues = { 0.911, 0.089, 0.339 },
    curseOfExhaustion = { 0.750, 0.260, 0.250 },
    curseOfElements = { 0.404, 0.079, 0.921 },
    baneOfDoom = { 0.075, 0.925, 0.656 },
    createHealthstone = { 0.165, 0.915, 0.085 },
    createSoulstone = { 0.585, 0.088, 0.912 },
    createFirestone = { 0.877, 0.123, 0.155 },
    createSpellstone = { 0.381, 0.128, 0.872 },
}

function Core.RingColour(key)
    local colour = key and Core.RING_TINT[key]
    if not colour then return 1, 1, 1 end
    return colour[1], colour[2], colour[3]
end

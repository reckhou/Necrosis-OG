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

-- mount button, left click summon steed and right click use hearthstone
local _, ns = ...
local Core, Text = ns.Core, ns.Text
local Buttons = ns.Buttons
local IsSecret, Plain = ns.Game.IsSecret, ns.Game.Plain

local Mount = {}
ns.Mount = Mount

local button

-- dreadsteed first, then felsteed
local function BestSteed()
    return Core.PickSpell({ "felsteed", "dreadsteed" }, Buttons.IsKnown)
end

local function HearthLine()
    local count = Plain(C_Item.GetItemCount, Core.HEARTHSTONE_ITEM)
    if count == 0 then return Text.TIP_HEARTH_NONE end
    local ok, start, duration = pcall(C_Container.GetItemCooldown, Core.HEARTHSTONE_ITEM)
    if not ok or IsSecret(start) or IsSecret(duration) then return nil end
    local left = Core.CooldownLeft(start, duration, GetTime())
    if left > 0 then return string.format(Text.TIP_HEARTH_COOLING, Core.TimerText(left)) end
    return nil
end

local function Tooltip(tooltip)
    Buttons.SpellTooltip(tooltip, button.spellID, Core.SPELLS.felsteed[1])
    ns.Tips.Click(tooltip, "left", Text.ACT_STEED)
    ns.Tips.Click(tooltip, "right", Text.ACT_HEARTHSTONE)
    ns.Tips.Note(tooltip, HearthLine())
end

Buttons.OnCreate(function(sphere)
    button = Buttons.NewSecureButton("NecrosisOGMountButton", sphere, Core.BUTTON_SIZE)
    button:SetScale(Core.BUTTON_SCALE)
    button.icon:SetTexture(Core.UiTexture("MountButton-01"))
    ns.Rings.Attach(button, button, "MountButton")
    button.tooltip = Tooltip
    button.speechSubject = function(mouse)
        if button.spellID and mouse ~= "RightButton" then return "mount", nil end
    end
    Buttons.AddSlot("mount", button)
end)

Buttons.OnRefresh(function()
    local id = BestSteed()
    button.spellID = id
    Buttons.SetActions(button, { ["type*"] = id and "spell" or false, ["spell*"] = id or false,
        type2 = "item", item2 = "item:" .. Core.HEARTHSTONE_ITEM })
    button.icon:SetDesaturated(id == nil and not ns.demo)
    button.wanted = id ~= nil or Buttons.DemoMode()
end)

Mount.Button = function() return button end

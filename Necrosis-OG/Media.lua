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

-- font, text size and bar texture for addon text and bars
local _, ns = ...
local Core = ns.Core

local Media = {}
ns.Media = Media

local fonts = {}
local order = {}
local bars = {}
local works = {}

-- LibSharedMedia if other addon load it, else nil
local function Lsm()
    local stub = _G.LibStub
    if not stub then return nil end
    local ok, lib = pcall(stub, "LibSharedMedia-3.0", true)
    return ok and type(lib) == "table" and lib or nil
end

local function LsmTable(kind)
    local lib = Lsm()
    if not lib or type(lib.HashTable) ~= "function" then return nil end
    local ok, hash = pcall(lib.HashTable, lib, kind)
    return ok and type(hash) == "table" and hash or nil
end

local probe

local function FontWorks(file)
    if works[file] == nil then
        local ok, result = pcall(function()
            if not probe then
                local holder = CreateFrame("Frame")
                holder:Hide()
                probe = holder:CreateFontString(nil, "OVERLAY")
            end
            return probe:SetFont(file, 12, "")
        end)
        works[file] = not (ok and result == false)
    end
    return works[file]
end

local function Saved(key)
    return ns.db and ns.db[key] or Core.DEFAULTS[key]
end

-- file of chosen font, nil for blizzard default
local function FontFile()
    local key = Saved("font")
    local name = Core.LsmName(key)
    if name then
        local hash = LsmTable("font")
        return hash and type(hash[name]) == "string" and hash[name] or nil
    end
    local entry = Core.MediaEntry(Core.FONT_LIST, key)
    if not entry or entry == Core.FONT_LIST[1] or not FontWorks(entry.file) then return nil end
    return entry.file
end

local function BarLook()
    local key = Saved("barTexture")
    local name = Core.LsmName(key)
    if name then
        local hash = LsmTable("statusbar")
        if hash and type(hash[name]) == "string" then return hash[name], false end
    end
    local entry = Core.MediaEntry(Core.BAR_TEXTURE_LIST, key) or Core.BAR_TEXTURE_LIST[1]
    return entry.file, entry.solid == true
end

local function DrawFont(entry, file)
    local size = Core.ScaledFontSize(entry.size, Saved("textSize"))
    if not (file and entry.object:SetFont(file, size, entry.flags) ~= false) then
        entry.object:SetFont(entry.path, size, entry.flags)
    end
end

local function DrawBar(texture)
    local file, solid = BarLook()
    if solid then
        texture:SetColorTexture(1, 1, 1, 1)
    else
        texture:SetTexture(file)
    end
end

-- font object copy of base with chosen font and size
function Media.Font(base, size, outline)
    local name = "NecrosisOGFont_" .. base .. (size and ("_" .. size) or "") .. (outline and "_Outline" or "")
    if fonts[name] == nil then
        local ok, entry = pcall(function()
            local source = _G[base]
            local path, height, flags = source:GetFont()
            local object = CreateFont(name)
            object:CopyFontObject(source)
            flags = flags or ""
            if outline and not string.find(flags, "OUTLINE", 1, true) then
                flags = flags == "" and "OUTLINE" or (flags .. ",OUTLINE")
            end
            return { object = object, path = path, size = size or height, flags = flags }
        end)
        fonts[name] = ok and entry or false
        if ok then
            order[#order + 1] = entry
            DrawFont(entry, FontFile())
        end
    end
    return fonts[name] and name or base
end

-- set the chosen look on bar texture, now and after each change
function Media.DressBar(texture)
    bars[#bars + 1] = texture
    DrawBar(texture)
    return texture
end

function Media.ApplyFonts()
    local file = FontFile()
    for _, entry in ipairs(order) do DrawFont(entry, file) end
end

function Media.ApplyBars()
    for _, texture in ipairs(bars) do DrawBar(texture) end
end

function Media.DragLabel(parent, anchor, text)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(1, 1)
    holder:SetPoint("BOTTOM", anchor, "TOP", 0, 0)
    local label = holder:CreateFontString(nil, "OVERLAY", Media.Font("GameFontNormalSmall", Core.DRAG_LABEL_SIZE, true))
    label:SetPoint("BOTTOM", holder, "BOTTOM", 0, 2)
    label:SetText(Core.Gradient(text, Core.GRADIENT_HEADING))
    return holder, label
end

local ROLE_ICON = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORDS = { TANK = { 0, 19 / 64, 22 / 64, 41 / 64 }, HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 } }
local CLASS_ICON = "Interface\\WorldStateFrame\\ICONS-CLASSES"
local CLASS_COORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
    DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 },
    SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 }, PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 },
    WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 },
    DEATHKNIGHT = { 0.25, 0.5, 0.5, 0.75 }, MONK = { 0.5, 0.73828125, 0.5, 0.75 },
    DEMONHUNTER = { 0.7421875, 0.98828125, 0.5, 0.75 }, EVOKER = { 0, 0.25, 0.75, 1 },
}

function Media.SetNameIcon(texture, class, role)
    if ROLE_COORDS[role] then
        texture:SetTexture(ROLE_ICON)
        texture:SetTexCoord(unpack(ROLE_COORDS[role]))
    elseif CLASS_COORDS[class] then
        texture:SetTexture(CLASS_ICON)
        texture:SetTexCoord(unpack(CLASS_COORDS[class]))
    else
        texture:Hide()
        return false
    end
    texture:Show()
    return true
end

-- choices for dropdown, { key, label }
function Media.FontChoices()
    return Core.MediaChoices(Core.FONT_LIST, LsmTable("font"), function(entry) return ns.Text[entry.text] end,
        function(entry) return FontWorks(entry.file) end)
end

function Media.BarChoices()
    return Core.MediaChoices(Core.BAR_TEXTURE_LIST, LsmTable("statusbar"), function(entry) return ns.Text[entry.text] end)
end

local function ApplyAll()
    Media.ApplyFonts()
    Media.ApplyBars()
end

local listening = false

local function Listen()
    local lib = Lsm()
    if listening or not lib or type(lib.RegisterCallback) ~= "function" then return end
    listening = true
    pcall(lib.RegisterCallback, Media, "LibSharedMedia_Registered", function(_, kind, name)
        local wanted = (kind == "font" and Saved("font")) or (kind == "statusbar" and Saved("barTexture")) or nil
        if wanted and Core.LsmName(wanted) == name then ApplyAll() end
    end)
end

local function Start()
    ApplyAll()
    Listen()
end

table.insert(ns.onLoad, Start)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", Start)

ns.OnSetting("font", Media.ApplyFonts)
ns.OnSetting("textSize", Media.ApplyFonts)
ns.OnSetting("barTexture", Media.ApplyBars)

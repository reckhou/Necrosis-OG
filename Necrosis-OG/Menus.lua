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

-- demons, utility and curses buttons with their menu
local _, ns = ...
local Core, Text = ns.Core, ns.Text
local Buttons = ns.Buttons

local Menus = {}
ns.Menus = Menus

local MENU_BODY = [[
    local menu = self:GetFrameRef("menu")
    if menu:IsShown() then
        menu:Hide()
    else
        for i = 1, 2 do
            local other = self:GetFrameRef("other" .. i)
            if other then other:Hide() end
        end
        menu:Show()
    end
    return false
]]
local TOGGLE_MENU = [[ if button ~= "LeftButton" then return end ]] .. MENU_BODY

local REMINDER_CLICK = [[ if button ~= "LeftButton" then return nil, true end ]] .. MENU_BODY

local BEFORE_SPELL = [[ return nil, true ]]

local AFTER_SPELL = Core.KEEP_SUMMON .. [[
    local menu = self:GetFrameRef("menu")
    if not menu:GetAttribute("keepOpen") then menu:Hide() end
]]

local MENUS = {
    demons = { list = Core.DEMON_MENU, art = "PetMenuButton", name = "NecrosisOGDemonsButton",
        menuName = "NecrosisOGDemonsMenu", spell = "senseDemons" },
    utility = { list = Core.UTILITY_MENU, art = "BuffMenuButton", name = "NecrosisOGUtilityButton",
        menuName = "NecrosisOGUtilityMenu", classAtlas = "warlock" },
    curses = { list = Core.CURSE_MENU, art = "CurseMenuButton", name = "NecrosisOGCursesButton",
        menuName = "NecrosisOGCursesMenu", spell = "deathCoil" },
}
local MENU_KEYS = { "utility", "demons", "curses" }

local SpellName, IsSecret, Plain, InCombat = ns.Game.SpellName, ns.Game.IsSecret, ns.Game.Plain, ns.Game.InCombat

-- if spell is switched off on menus tab
local function EntryOff(menuKey, entry)
    local off = ns.db.buttons.menuOff
    return Core.MenuEntryOff(off and off[menuKey], entry)
end

local function SwitchedOff(menuKey, entryKey)
    for _, entry in ipairs(MENUS[menuKey].list) do
        if entry.keys[1] == entryKey then return EntryOff(menuKey, entry) end
    end
    return false
end

local function Last(menuKey, saved)
    if not Core.SPELLS[saved] or SwitchedOff(menuKey, saved) then return nil end
    return Core.HighestKnown(Core.SPELLS[saved], Buttons.IsKnown)
end

local function LastDemon() return Last("demons", ns.db.buttons.lastDemon) end
local function LastCurse() return Last("curses", ns.db.buttons.lastCurse) end

-- last utility spell cast, entry and spell id
local function LastUtility()
    local entry = Core.SphereClickEntry(ns.db.buttons.lastUtility)
    if entry and EntryOff("utility", entry) then return nil end
    local id = entry and Core.PickSpell(entry.keys, Buttons.IsKnown)
    if not id then return nil end
    return entry, id
end

-- amplify curse id for right click of the item, nil when curse is not amplified or not learned
local function Amplify(entry)
    if not Core.AMPLIFY_KEYS[entry.keys[1]] then return nil end
    return Core.HighestKnown(Core.SPELLS.amplifyCurse, Buttons.IsKnown)
end

local menus = {}

local function ItemTooltip(item)
    return function(tooltip)
        Buttons.SpellTooltip(tooltip, item.spellID, Core.SPELLS[item.entry.keys[1]][1])
        if item.entry.demon and item.spellID then
            if Core.HighestKnown(Core.SPELLS.felDomination, Buttons.IsKnown) then
                ns.Tips.Click(tooltip, "right", Text.ACT_FAST_SUMMON)
            end
        end
        local amplify = item.spellID and Amplify(item.entry)
        if amplify then
            ns.Tips.Click(tooltip, "right", string.format(Text.ACT_THEN, SpellName(amplify) or "?", SpellName(item.spellID) or "?"))
        end
    end
end

local DressRing = Buttons.DressRing

local function AnchorFace(item, dx, dy)
    item.face:ClearAllPoints()
    item.face:SetPoint("CENTER", item, "CENTER", dx or 0, dy or 0)
end

local function NewFace(item, menu)
    local face = CreateFrame("Frame", nil, menu.faceOwner)
    face:SetSize(Core.MENU_ITEM_SIZE, Core.MENU_ITEM_SIZE)
    face:SetScale(menu.faceScale or 1)
    if menu.faceStrata then face:SetFrameStrata(menu.faceStrata) end
    face:SetFrameLevel(item:GetFrameLevel())
    item.icon:SetParent(face)
    item.icon:ClearAllPoints()
    item.icon:SetAllPoints(face)
    face.icon = item.icon
    item.face = face
    AnchorFace(item)

    face.open = face:CreateAnimationGroup()
    face.open.move = face.open:CreateAnimation("Translation")
    face.open.move:SetDuration(Core.MENU_OPEN)
    face.open.move:SetSmoothing("OUT")
    ns.Bars.AlphaStep(face.open, 0, 1, Core.MENU_OPEN)
    ns.Bars.ScaleStep(face.open, Core.MENU_GROW_FROM, 1, Core.MENU_OPEN)
    face.open:SetScript("OnFinished", function() AnchorFace(item) end)

    face.close = face:CreateAnimationGroup()
    face.close:SetToFinalAlpha(true)
    face.close.move = face.close:CreateAnimation("Translation")
    face.close.move:SetDuration(Core.MENU_CLOSE)
    face.close.move:SetSmoothing("IN")
    ns.Bars.AlphaStep(face.close, 1, 0, Core.MENU_CLOSE)
    ns.Bars.ScaleStep(face.close, 1, Core.MENU_GROW_FROM, Core.MENU_CLOSE):SetSmoothing("IN")
    face.close:SetScript("OnFinished", function()
        face:Hide()
        AnchorFace(item)
    end)

    ns.PopUpAnimation(face.open)
    ns.PopUpAnimation(face.close)
    face:Hide()
    return face
end

-- face fly out from menu button when open
local function OpenFace(item)
    local face = item.face
    face.close:Stop()
    face.open:Stop()
    face:SetAlpha(1)
    face:Show()
    if not ns.AnimationsOn() then return AnchorFace(item) end
    local dx, dy = item.dx or 0, item.dy or 0
    AnchorFace(item, -dx, -dy)
    face.open.move:SetOffset(dx, dy)
    face.open:Play()
end

-- face fly back into button then hide
local function CloseFace(item)
    local face = item.face
    face.open:Stop()
    AnchorFace(item)
    if ns.AnimationsOn() and face:IsVisible() then
        face.close.move:SetOffset(-(item.dx or 0), -(item.dy or 0))
        face.close:Play()
    else
        face.close:Stop()
        face:Hide()
    end
end

-- grey when spell can not cast now
local function Shade(item)
    local usable = true
    if not ns.demo then
        if not item.spellID then
            usable = false
        elseif Plain(C_Spell.IsSpellUsable, item.spellID) == false then
            usable = false
        end
    end
    item.icon:SetDesaturated(not usable)
end

local shaded = {}

local cooldownLengths = {}

local function NoteLength(id)
    local ok, info = pcall(C_Spell.GetSpellCooldown, id)
    if not ok or type(info) ~= "table" then return end
    local length = info.duration
    if IsSecret(length) or type(length) ~= "number" then return end
    if length > 2 then cooldownLengths[id] = length end
end

-- cooldown parts on the frame, size px square
local function NewCooldown(frame, size)
    local width, height = size * Core.SWIPE_WIDTH, size * Core.SWIPE_HEIGHT
    local dimFrame = CreateFrame("Frame", nil, frame)
    dimFrame:SetAllPoints(frame)
    dimFrame:SetFrameLevel(frame:GetFrameLevel() + 1)
    local dim = dimFrame:CreateTexture(nil, "OVERLAY")
    dim:SetPoint("CENTER", frame, "CENTER", 0, 0)
    dim:SetSize(width, height)
    dim:SetTexture(Core.UiTexture("Swipe"))
    dim:SetVertexColor(0, 0, 0, 1)
    dim:SetAlpha(0)
    local swipe = ns.Durations.NewSwipe(frame, { size = size, level = 4 })
    local text = ns.Durations.NewTimeText(frame, swipe)
    local cd = { swipe = swipe, dim = dim, text = text, binding = ns.Durations.Text(text, "cooldown", "") }
    swipe:SetScript("OnCooldownDone", function()
        dim:SetAlpha(0)
        ns.Durations.HideText(cd.binding, text)
    end)
    return cd
end

local function ClearCooldown(cd)
    pcall(cd.swipe.SetCooldown, cd.swipe, 0, 0)
    cd.dim:SetAlpha(0)
    ns.Durations.HideText(cd.binding, cd.text)
end

-- draw cooldown of spell id on cd
local function DrawCooldown(cd, id)
    if not cd then return end
    if ns.demo then id = nil end
    local duration
    if id and C_Spell.GetSpellCooldownDuration then
        local ok, value = pcall(C_Spell.GetSpellCooldownDuration, id, true)
        if ok then duration = value end
    end
    if not duration then return ClearCooldown(cd) end
    if not InCombat() then NoteLength(id) end
    local okZero, zero = pcall(duration.IsZero, duration)
    if not okZero then return ClearCooldown(cd) end
    local hidden = IsSecret(zero)
    if not hidden and zero == true then return ClearCooldown(cd) end
    pcall(cd.swipe.SetCooldownFromDurationObject, cd.swipe, duration, true)
    if not hidden then
        cd.dim:SetAlpha(1 - Core.COOLDOWN_DIM)
    elseif not pcall(cd.dim.SetAlphaFromBoolean, cd.dim, zero, 0, 1 - Core.COOLDOWN_DIM) then
        cd.dim:SetAlpha(0)
    end
    ns.Durations.ColourByLength(cd, cooldownLengths[id])
    ns.Durations.ShowText(cd.binding, duration)
end

local function UpdateCooldown(item) DrawCooldown(item.cd, item.spellID) end

local function CreateItem(menu, header, entry, menuKey, after)
    local item = Buttons.NewSecureButton(nil, menu, Core.MENU_ITEM_SIZE)
    item.entry = entry
    item.menuKey = menuKey
    local face = NewFace(item, menu)
    if entry.gameIcon then
        DressRing(face, Core.MENU_ICON_INSET, entry.art)
    else
        item.icon:SetTexture(Core.UiTexture(entry.art .. "-01"))
    end
    ns.Rings.Attach(face, item, entry.gameIcon and entry.keys[1] or entry.art)
    item.cd = NewCooldown(face, Core.MENU_ITEM_SIZE)
    item:HookScript("OnShow", function()
        Shade(item)
        UpdateCooldown(item)
        OpenFace(item)
    end)
    shaded[#shaded + 1] = item
    item:HookScript("OnHide", function() CloseFace(item) end)
    item.tooltip = ItemTooltip(item)
    local key = entry.keys[1]
    if entry.demon or key == "ritualOfSummoning" then
        item.speechSubject = function()
            if not item.spellID then return nil end
            return key, key == "ritualOfSummoning" and "target" or nil
        end
    end
    SecureHandlerSetFrameRef(item, "menu", menu)
    header:WrapScript(item, "OnClick", BEFORE_SPELL, after or AFTER_SPELL)
    item:Hide()
    return item
end

-- set actions and picture of one spell, return if it shows
local function RefreshItem(item)
    local id = Core.PickSpell(item.entry.keys, Buttons.IsKnown)
    item.spellID = id
    local actions = Buttons.CastActions(item.entry.keys[1], id)
    -- right click cast the same as left click, some spell have own right click
    actions.type2, actions.spell2, actions.macrotext2 = actions.type1, actions.spell1, actions.macrotext1
    local amplify = id and Amplify(item.entry)
    local amplifyName, curseName = amplify and SpellName(amplify), id and SpellName(id)
    if amplifyName and curseName then
        actions.type2, actions.macrotext2 = "macro", Core.AmplifyCast(amplifyName, curseName)
    end
    if item.entry.demon then
        local domination = id and Core.HighestKnown(Core.SPELLS.felDomination, Buttons.IsKnown)
        local dominationName, demonName = domination and SpellName(domination), id and SpellName(id)
        local full = Core.DemonSummonMacro(dominationName, demonName)
        Buttons.SummonActions(item, actions, full, full and Core.DemonSummonMacro(dominationName, demonName, false, true))
    end
    if actions.type2 == "macro" then actions.spell2 = false end
    Buttons.SetActions(item, actions)
    if item.entry.gameIcon then
        item.icon:SetTexture(Plain(C_Spell.GetSpellTexture, id or Core.SPELLS[item.entry.keys[1]][1]))
    end
    Shade(item)
    UpdateCooldown(item)
    if ns.demo then return true end
    if EntryOff(item.menuKey, item.entry) then return false end
    return id ~= nil or Buttons.DemoMode()
end

local LinkReminder

-- menu name, left click and right click
local function MenuTooltip(key)
    local Tips = ns.Tips
    return function(tooltip)
        if key == "demons" then
            Tips.Title(tooltip, Text.TIP_DEMONS_TITLE)
            Tips.Click(tooltip, "left", Text.ACT_OPEN_MENU)
            local last = LastDemon()
            if last then Tips.Click(tooltip, "right", SpellName(last) or "?") end
        elseif key == "curses" then
            Tips.Title(tooltip, Text.TIP_CURSES_TITLE)
            Tips.Click(tooltip, "left", Text.ACT_OPEN_MENU)
            local last = LastCurse()
            if last then Tips.Click(tooltip, "right", SpellName(last) or "?") end
        else
            Tips.Title(tooltip, Text.TIP_UTILITY_TITLE)
            Tips.Click(tooltip, "left", Text.ACT_OPEN_MENU)
            local _, id = LastUtility()
            if id then Tips.Click(tooltip, "right", SpellName(id) or "?") end
        end
    end
end

local function GameIcon(def)
    if def.spell then
        local icon = Plain(C_Spell.GetSpellTexture, Core.SPELLS[def.spell][1])
        if icon then return "texture", icon end
    elseif def.classAtlas then
        local atlas = GetClassAtlas and GetClassAtlas(def.classAtlas) or ("classicon-" .. def.classAtlas)
        if not (C_Texture and C_Texture.GetAtlasInfo) or C_Texture.GetAtlasInfo(atlas) then return "atlas", atlas end
    end
    return nil
end

local function LastEntry(key)
    if key == "utility" then return (LastUtility()) end
    local last = key == "demons" and LastDemon() or key == "curses" and LastCurse()
    if not last then return nil end
    local saved = key == "demons" and ns.db.buttons.lastDemon or ns.db.buttons.lastCurse
    for _, entry in ipairs(MENUS[key].list) do
        if entry.keys[1] == saved then return entry end
    end
    return nil
end

local ShowRing = Buttons.ShowRing

-- button picture is last spell's, else game icon in grey ring
local function WearPicture(key)
    local button = menus[key].button
    local entry = LastEntry(key)
    local known = entry and Core.PickSpell(entry.keys, Buttons.IsKnown)
    if entry and entry.gameIcon then
        local id = known or Core.SPELLS[entry.keys[1]][1]
        local icon = Plain(C_Spell.GetSpellTexture, id)
        if icon then
            ShowRing(button, true)
            button.icon:SetTexture(icon)
            button.icon:SetTexCoord(0, 1, 0, 1)
            ns.Rings.SetKey(button, entry.keys[1])
            return known
        end
    elseif entry then
        ShowRing(button, false)
        button.icon:SetTexture(Core.UiTexture(entry.art .. "-01"))
        button.icon:SetTexCoord(0, 1, 0, 1)
        ns.Rings.SetKey(button, entry.art)
        return known
    end
    local kind, value = GameIcon(MENUS[key])
    if not kind then return end
    ShowRing(button, true)
    ns.Rings.SetKey(button, MENUS[key].spell or "classWarlock")
    if kind == "atlas" then
        button.icon:SetAtlas(value)
    else
        button.icon:SetTexture(value)
        button.icon:SetTexCoord(0, 1, 0, 1)
    end
end

local function WearGameIcon(key)
    local button = menus[key].button
    button.cdSpell = WearPicture(key)
    DrawCooldown(button.cd, button.cdSpell)
end

local function CreateMenu(key, sphere, header)
    local def = MENUS[key]
    local button = Buttons.NewSecureButton(def.name, sphere, Core.BUTTON_SIZE)
    button:SetScale(Core.BUTTON_SCALE)
    button.icon:SetTexture(Core.UiTexture(def.art .. "-01"))
    ns.Rings.Attach(button, button, def.art)
    button.cd = NewCooldown(button, Core.BUTTON_SIZE)
    button.tooltip = MenuTooltip(key)
    if key == "demons" then
        button.speechSubject = function(mouse)
            if mouse == "RightButton" and LastDemon() then return ns.db.buttons.lastDemon, nil end
        end
    end

    local menu = CreateFrame("Frame", def.menuName, button, "SecureHandlerBaseTemplate")
    menu:SetSize(1, 1)
    menu:SetPoint("CENTER", button, "CENTER", 0, 0)
    menu:Hide()
    menu.faceOwner = button
    SecureHandlerSetFrameRef(button, "menu", menu)
    header:WrapScript(button, "OnClick", TOGGLE_MENU)

    local items = {}
    for i, entry in ipairs(def.list) do items[i] = CreateItem(menu, header, entry, key) end
    menus[key] = { button = button, menu = menu, items = items }
    Buttons.AddSlot(key, button)
end

local function OrderedItems(key)
    local state = menus[key]
    local byEntry, ordered = {}, {}
    for _, item in ipairs(state.items) do byEntry[item.entry] = item end
    for i, entry in ipairs(Core.OrderMenu(MENUS[key].list, ns.db.buttons.menuOrder[key])) do ordered[i] = byEntry[entry] end
    return ordered
end

local function RefreshMenu(key)
    local state = menus[key]
    local shown = 0
    WearGameIcon(key)
    local direction = ns.db.buttons.menuDirection[key]
    local shiftX, shiftY = Core.MenuShift(ns.db.buttons.menuOffset and ns.db.buttons.menuOffset[key])
    state.menu:SetAttribute("keepOpen", ns.db.buttons.menuCloses ~= true)
    for _, item in ipairs(OrderedItems(key)) do
        if RefreshItem(item) then
            shown = shown + 1
            item:ClearAllPoints()
            local x, y = Core.MenuOffset(key, shown, direction)
            item.dx, item.dy = x + shiftX, y + shiftY
            item:SetPoint("CENTER", state.button, "CENTER", item.dx, item.dy)
            item:Show()
        else
            item:Hide()
        end
    end
    state.button.wanted = shown > 0
    if key == "utility" then
        local entry, id = LastUtility()
        local cast = Buttons.CastActions(entry and entry.keys[1], id)
        Buttons.SetActions(state.button, { type2 = cast.type1, spell2 = cast.spell1, macrotext2 = cast.macrotext1 })
    end
    if key == "demons" or key == "curses" then
        local last
        if key == "demons" then last = LastDemon() else last = LastCurse() end
        Buttons.SetActions(state.button, { type2 = last and "spell" or false, spell2 = last or false, macrotext2 = false })
    end
end

Buttons.OnCreate(function(sphere, header)
    for _, key in ipairs(MENU_KEYS) do CreateMenu(key, sphere, header) end
    for _, key in ipairs(MENU_KEYS) do
        local n = 0
        for _, other in ipairs(MENU_KEYS) do
            if other ~= key then
                n = n + 1
                SecureHandlerSetFrameRef(menus[key].button, "other" .. n, menus[other].menu)
            end
        end
    end
    LinkReminder()
end)

local PICK_AFTER = [[
    local owner = self:GetFrameRef("owner")
    local macro = self:GetAttribute("againmacro")
    if macro then
        owner:SetAttribute("type2", "macro")
        owner:SetAttribute("summonfull", macro)
        owner:SetAttribute("summonkeep", self:GetAttribute("againkeep"))
        owner:SetAttribute("againart", self:GetAttribute("againart"))
    end
    local menu = self:GetFrameRef("menu")
    if not menu:GetAttribute("keepOpen") then menu:Hide() end
]] .. Core.KEEP_SUMMON

local picker

LinkReminder = function()
    if not (picker and menus.demons) then return end
    for _, item in ipairs(menus.demons.items) do SecureHandlerSetFrameRef(item, "owner", picker.owner) end
end

-- owner is demon reminder, header is secure header
function Menus.AttachDemonPicker(owner, header)
    local menu = CreateFrame("Frame", "NecrosisOGDemonReminderMenu", owner, "SecureHandlerBaseTemplate")
    menu:SetSize(1, 1)
    menu:SetPoint("CENTER", owner, "CENTER", 0, 0)
    menu:SetScale(Core.BUTTON_SCALE / Core.CONTROL_ICON_SCALE)
    menu:SetFrameStrata("HIGH")
    menu:Hide()
    menu.faceOwner, menu.faceScale, menu.faceStrata = owner, Core.BUTTON_SCALE / Core.CONTROL_ICON_SCALE, "HIGH"
    SecureHandlerSetFrameRef(owner, "menu", menu)
    header:WrapScript(owner, "OnClick", REMINDER_CLICK, Core.KEEP_SUMMON)
    local items = {}
    for _, entry in ipairs(Core.DEMON_MENU) do
        if entry.demon then
            local item = CreateItem(menu, header, entry, "demons", PICK_AFTER)
            SecureHandlerSetFrameRef(item, "owner", owner)
            items[#items + 1] = item
        end
    end
    picker = { owner = owner, menu = menu, items = items }
    LinkReminder()
end

local function RefreshPicker()
    if not picker then return end
    picker.menu:SetAttribute("keepOpen", ns.db.buttons.menuCloses ~= true)
    local domination = Core.HighestKnown(Core.SPELLS.felDomination, Buttons.IsKnown)
    local dominationName = domination and SpellName(domination)
    local shown = 0
    for _, item in ipairs(picker.items) do
        if RefreshItem(item) then
            shown = shown + 1
            item:ClearAllPoints()
            item.dx, item.dy = 0, Core.DemonPickerOffset(shown)
            item:SetPoint("CENTER", picker.owner, "CENTER", item.dx, item.dy)
            local demonName = item.spellID and SpellName(item.spellID)
            item:SetAttribute("againmacro", demonName and Core.DemonAgainMacro(dominationName, demonName) or nil)
            item:SetAttribute("againkeep", demonName and Core.DemonAgainMacro(dominationName, demonName, true) or nil)
            item:SetAttribute("againart", item.entry.art)
            item:Show()
        else
            item:Hide()
        end
    end
end

Buttons.OnRefresh(function()
    for _, key in ipairs(MENU_KEYS) do RefreshMenu(key) end
    RefreshPicker()
end)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if unit ~= "player" or IsSecret(spellID) then return end
    local demon, curse = Core.DemonKey(spellID), Core.CurseKey(spellID)
    local utility = Core.UtilityKey(spellID)
    local utilityEntry = utility and Core.SphereClickEntry(utility)
    if utilityEntry and EntryOff("utility", utilityEntry) then utility = nil end
    local menuCurse = curse
    if demon and SwitchedOff("demons", demon) then demon = nil end
    if menuCurse and SwitchedOff("curses", menuCurse) then menuCurse = nil end
    if utility and utility ~= ns.db.buttons.lastUtility then
        ns.db.buttons.lastUtility = utility
        Buttons.Refresh()
    end
    if demon and demon ~= ns.db.buttons.lastDemon then
        ns.db.buttons.lastDemon = demon
        Buttons.Refresh()
    elseif menuCurse and menuCurse ~= ns.db.buttons.lastCurse then
        ns.db.buttons.lastCurse = menuCurse
        Buttons.Refresh()
    end
    if curse and Core.IsBaneKey(curse) and ns.db.buttons.lastBane ~= curse then
        ns.db.buttons.lastBane = curse
        Buttons.Refresh()
    end
end)

table.insert(ns.onSphere, function() events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player") end)

local usableEvents = CreateFrame("Frame")
usableEvents:SetScript("OnEvent", function()
    for _, item in ipairs(shaded) do
        if item:IsVisible() then Shade(item) end
    end
end)

table.insert(ns.onSphere, function()
    usableEvents:RegisterEvent("SPELL_UPDATE_USABLE")
    usableEvents:RegisterEvent("BAG_UPDATE_DELAYED")
end)

local cooldownEvents = CreateFrame("Frame")

local function UpdateAllCooldowns()
    for _, item in ipairs(shaded) do
        if item:IsVisible() then UpdateCooldown(item) end
    end
    for _, key in ipairs(MENU_KEYS) do
        local button = menus[key] and menus[key].button
        if button then DrawCooldown(button.cd, button.cdSpell) end
    end
end

cooldownEvents:SetScript("OnEvent", function(_, event)
    UpdateAllCooldowns()
    if event == "UNIT_SPELLCAST_SUCCEEDED" and C_Timer and C_Timer.After then C_Timer.After(0.3, UpdateAllCooldowns) end
end)

table.insert(ns.onSphere, function()
    cooldownEvents:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    cooldownEvents:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
end)

Menus.State = function(key) return menus[key] end
Menus.Picker = function() return picker end

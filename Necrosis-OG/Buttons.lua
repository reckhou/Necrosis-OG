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

-- the buttons around sphere, healthstone and soulstone buttons, macros
local _, ns = ...
local Core, Text = ns.Core, ns.Text

local Buttons = {}
ns.Buttons = Buttons

local sphere, header
local created = false
local waitingSphere
local pending = false
local slots = {}
local refreshers = {}
local creators = {}

local IsSecret, Plain, InCombat, SpellName = ns.Game.IsSecret, ns.Game.Plain, ns.Game.InCombat, ns.Game.SpellName

function Buttons.IsKnown(spellID)
    return Plain(C_SpellBook.IsSpellKnown, spellID) == true
end

function Buttons.DemoMode() return ns.demo == true end

function Buttons.OnRefresh(refresh) refreshers[#refreshers + 1] = refresh end
function Buttons.OnCreate(create) creators[#creators + 1] = create end

-- add button into the ring, can drag it alone
function Buttons.AddSlot(slot, button)
    slots[slot] = button
    button.slot = slot
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:SetScript("OnDragStart", function(self) Buttons.DragStart(self) end)
    button:SetScript("OnDragStop", function(self) Buttons.DragStop(self) end)
end

local Tips = ns.Tips
local ShowTooltip, HideTooltip = Tips.Show, Tips.Hide

-- run before each click of secure button
function Buttons.PreClick(button, mouse)
    if button.speechSubject and ns.Speech then
        local subject, target = button.speechSubject(mouse)
        if subject then ns.Speech.Speak(subject, target) end
    end
    if button.onPreClick then button.onPreClick(button, mouse) end
end

function Buttons.PostClick(button, mouse)
    if button.onPostClick then button.onPostClick(button, mouse) end
    if ns.Shards and ns.Shards.TryAuto then ns.Shards.TryAuto("add-on button") end
end

-- secure button cast or use what its attributes say
function Buttons.NewSecureButton(name, parent, size)
    local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    button:SetSize(size, size)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", HideTooltip)
    button:SetScript("PreClick", Buttons.PreClick)
    button:SetScript("PostClick", Buttons.PostClick)
    return button
end

-- game icon cut round, under the grey ring
function Buttons.DressRing(frame, inset, art)
    frame.icon:ClearAllPoints()
    frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    frame.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    local mask = frame:CreateMaskTexture()
    mask:SetTexture(Core.UiTexture("Mask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(frame.icon)
    frame.icon:AddMaskTexture(mask)
    frame.iconMask = mask
    frame.ring = frame:CreateTexture(nil, "OVERLAY")
    frame.ring:SetAllPoints()
    frame.ring:SetTexture(Core.UiTexture(art .. "-01"))
end

-- set many attributes, false will clear one
function Buttons.SetActions(button, actions)
    for name, value in pairs(actions) do
        if value == false then button:SetAttribute(name, nil) else button:SetAttribute(name, value) end
    end
end

local summonButtons = {}

function Buttons.IsCasting()
    for _, fn in ipairs({ UnitCastingInfo or false, UnitChannelInfo or false }) do
        if fn and Plain(fn, "player") ~= nil then return true end
    end
    return false
end

function Buttons.SummonActions(button, actions, full, keep)
    summonButtons[button] = true
    actions.summonfull, actions.summonkeep = full or false, full and keep or false
    actions.type2 = full and "macro" or false
    actions.macrotext2 = full and (Buttons.IsCasting() and keep or full) or false
    return actions
end

local function MatchSummons(casting)
    if InCombat() then return end
    for button in pairs(summonButtons) do
        local macro = button:GetAttribute(casting and "summonkeep" or "summonfull")
        if macro and button:GetAttribute("macrotext2") ~= macro then button:SetAttribute("macrotext2", macro) end
    end
end

local castEvents = CreateFrame("Frame")
castEvents:SetScript("OnEvent", function(_, event)
    MatchSummons(event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or Buttons.IsCasting())
end)

table.insert(ns.onSphere, function()
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_CHANNEL_STOP" }) do
        castEvents:RegisterUnitEvent(event, "player")
    end
    castEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
end)

local FOCUS_KEYS = { banish = true, fear = true, enslaveDemon = true }

-- left click actions to cast the spell
function Buttons.CastActions(key, id)
    if not id then return { type1 = false, spell1 = false, macrotext1 = false } end
    local actions = { type1 = "spell", spell1 = id, macrotext1 = false }
    local name = ns.db.buttons.autoFocus == true and FOCUS_KEYS[key] and SpellName(id)
    if name then
        actions.type1, actions.spell1 = "macro", false
        actions.macrotext1 = "/focus [harm]\n/cast " .. name
    end
    return actions
end

-- tooltip lines for spell
function Buttons.SpellTooltip(tooltip, spellID, fallbackID)
    tooltip:SetSpellByID(spellID or fallbackID)
end

-- if button shows
function Buttons.SlotShown(slot)
    local button = slots[slot]
    return button ~= nil and button.wanted == true and ns.db.buttons.show[slot] ~= false
end

function Buttons.SlotUsable(slot)
    local button = slots[slot]
    return button ~= nil and button.wanted == true
end

function Buttons.SlotIcon(slot)
    local button = slots[slot]
    if not button or not button.icon then return nil end
    local atlas = button.icon.GetAtlas and button.icon:GetAtlas()
    if atlas then return "atlas", atlas end
    local texture = button.icon:GetTexture()
    if texture then return "texture", texture end
    return nil
end

-- place shown buttons around sphere by player order
local function Layout()
    local shown = {}
    for _, slot in ipairs(Core.OrderSlots(ns.db.buttons.ringOrder)) do
        local button = slots[slot]
        if button then
            if Buttons.SlotShown(slot) then shown[#shown + 1] = button else button:Hide() end
        end
    end
    local free = ns.db.buttons.free == true
    local places = ns.db.buttons.places
    local ring = ns.db.sphere
    local size = Core.ClampButtonSize(ring.buttonSize)
    for _, button in pairs(slots) do button:SetScale(Core.ButtonScale(size)) end
    for i, offset in ipairs(Core.ButtonOffsets(#shown, ring.rotation, ring.spacing, ring.distance)) do
        local button = shown[i]
        local place = free and places[button.slot]
        local x, y = offset.x, offset.y
        if type(place) == "table" and type(place.x) == "number" and type(place.y) == "number" then
            x, y = place.x, place.y
        end
        button:ClearAllPoints()
        button:SetPoint("CENTER", sphere, "CENTER", x / size, y / size)
        button:Show()
    end
    for _, button in pairs(slots) do
        if free then button:RegisterForDrag("LeftButton") else button:RegisterForDrag() end
    end
end

local warnedDrag = false

function Buttons.DragStart(button)
    if not ns.db.buttons.free or ns.db.locked then return end
    if InCombat() then
        if not warnedDrag then
            warnedDrag = true
            ns.Print(Text.NO_MOVE_IN_COMBAT)
        end
        return
    end
    button.dragging = true
    button:StartMoving()
end

function Buttons.DragStop(button)
    if not button.dragging then return end
    button.dragging = false
    button:StopMovingOrSizing()
    if button.SetUserPlaced then pcall(button.SetUserPlaced, button, false) end
    local bx, by = button:GetCenter()
    local sx, sy = sphere:GetCenter()
    local own, other = button:GetEffectiveScale(), sphere:GetEffectiveScale()
    if type(bx) == "number" and type(sx) == "number" and type(own) == "number" and own > 0 then
        local x = (bx * own - sx * other) / own
        local y = (by * own - sy * other) / own
        local size = Core.ClampButtonSize(ns.db.sphere.buttonSize)
        ns.db.buttons.places[button.slot] = { x = x * size, y = y * size }
    end
    Buttons.Refresh()
end

-- free the buttons, or keep them around sphere
function Buttons.SetFree(on)
    ns.db.buttons.free = on and true or false
    if not on then ns.db.buttons.places = {} end
    return Buttons.Refresh()
end

function Buttons.ResetPlaces()
    ns.db.buttons.places = {}
    return Buttons.Refresh()
end

-- set every action, place and shown state, wait if in combat
function Buttons.Refresh()
    if not created then return false end
    if InCombat() then
        pending = true
        return false
    end
    pending = false
    ns.Fire(refreshers)
    Layout()
    return true
end

local Stones = ns.Stones
local Durations = ns.Durations
local STONES = {}
local KIND_KEYS = {}
for i, kind in ipairs(Stones.KINDS) do
    STONES[kind] = Stones.Definition(kind)
    KIND_KEYS[kind] = i
end

Buttons.STONE_KINDS = Stones.KINDS
local StoneList = Stones.List
local stoneButtons = {}
local held, equipped = Stones.State()

local UpdateCooldowns
local cooldownEnds = Durations.NewSchedule(function() UpdateCooldowns() end)
local demoCooldowns = {}

-- dim stone picture while cooldown
local function DimWhileCooling(button)
    local dim = button.cooling and Core.COOLDOWN_DIM or nil
    if not (ns.Rings and ns.Rings.SetDim and ns.Rings.SetDim(button, dim)) and button.icon.SetVertexColor then
        local value = dim or 1
        button.icon:SetVertexColor(value, value, value)
    end
end

local UpdateCooldownParts

local function UpdateCooldown(kind)
    UpdateCooldownParts(kind)
    DimWhileCooling(stoneButtons[kind])
end

UpdateCooldownParts = function(kind)
    local button = stoneButtons[kind]
    local start, duration, hidden, ending
    local fake = demoCooldowns[kind]
    if fake then
        start, duration = fake.start, fake.length
    else
        start, duration, hidden, ending = Stones.Cooldown(kind)
    end
    if hidden then
        pcall(button.cooldown.SetCooldown, button.cooldown, start, duration)
        Durations.HideText(button.binding, button.timeText)
        button.cooling = true
        cooldownEnds.At(KIND_KEYS[kind], GetTime() + 1)
        return
    end
    local left = ending and math.max(0, ending - GetTime()) or Core.CooldownLeft(start, duration, GetTime())
    button.cooling = left > 0
    if left > 0 then
        if ending then
            button.cooldown:SetCooldownFromExpirationTime(ending, duration)
            Durations.SetEnd(button.span, ending, duration)
        else
            button.cooldown:SetCooldown(start, duration)
            Durations.Set(button.span, start, duration)
        end
        Durations.ColourByLength(button, duration)
        Durations.ShowText(button.binding, button.span)
        cooldownEnds.At(KIND_KEYS[kind], ending or start + duration)
    else
        button.cooldown:SetCooldown(0, 0)
        Durations.HideText(button.binding, button.timeText)
        cooldownEnds.Cancel(KIND_KEYS[kind])
    end
end

-- stone picture: none, in bags or on cooldown
local function UpdatePicture(kind)
    local button, stone = stoneButtons[kind], STONES[kind]
    local state = "-01"
    if ns.demo then
        state = "-02"
    elseif stone.onWeapon and equipped[kind] then
        state = held[kind] and "-03" or "-04"
    elseif held[kind] then
        state = "-02"
    elseif kind == "soulstone" and button.cooling then
        state = "-03"
    end
    button.icon:SetTexture(Core.UiTexture(stone.art .. state))
end

UpdateCooldowns = function()
    for kind in pairs(STONES) do
        if stoneButtons[kind] then
            UpdateCooldown(kind)
            UpdatePicture(kind)
        end
    end
end

function Buttons.UpdateStones() Stones.Refresh() end

-- stones held and weapon enchant as one string
local function StoneState()
    local parts = {}
    for _, kind in ipairs(Stones.KINDS) do
        parts[#parts + 1] = tostring(held[kind] and held[kind].id or 0) .. (equipped[kind] and "e" or "")
    end
    return table.concat(parts, ",")
end

local refreshedFor
local readHeld, readEquipped

table.insert(Stones.changed, function()
    held, equipped = Stones.State()
    if not created then return end
    UpdateCooldowns()
    if held == readHeld and equipped == readEquipped then return end
    readHeld, readEquipped = held, equipped
    local state = StoneState()
    if state ~= refreshedFor then
        refreshedFor = state
        Buttons.Refresh()
    end
end)

local tradeOpen = false

local function Trade(unit)
    if InCombat() then return end
    local stone = held.healthstone
    if not stone then return end
    if tradeOpen then
        C_Container.PickupContainerItem(stone.bag, stone.slot)
        if type(ClickTradeButton) == "function" then ClickTradeButton(1) end
        return
    end
    if Core.CanTradeTo(Plain(UnitExists, unit), Plain(UnitIsPlayer, unit), Plain(UnitIsFriend, "player", unit),
        Plain(UnitIsUnit, unit, "player")) then
        C_Container.PickupContainerItem(stone.bag, stone.slot)
        if CursorHasItem() then C_Item.DropItemOnUnit(unit) end
    end
end

local MENU_TAGS = { "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_TARGET" }

-- trade healthstone entry on unit menu
local function AddTradeEntry(_, root, contextData)
    local unit = type(contextData) == "table" and contextData.unit or nil
    if InCombat() or type(unit) ~= "string" or IsSecret(unit) then return end
    if not Core.CanTradeTo(Plain(UnitExists, unit), Plain(UnitIsPlayer, unit), Plain(UnitIsFriend, "player", unit),
        Plain(UnitIsUnit, unit, "player")) then return end
    local have = held.healthstone ~= nil
    local label = have and Text.MENU_TRADE_HEALTHSTONE or Text.MENU_TRADE_NO_STONE
    local function Click() Trade(unit) end
    local entry
    if type(MenuUtil) == "table" and type(MenuUtil.CreateButton) == "function" and type(root.Insert) == "function"
        and type(root.EnumerateElementDescriptions) == "function" then
        local ok = pcall(function()
            local place
            for index, element in root:EnumerateElementDescriptions() do
                if element.text ~= nil and not IsSecret(element.text) and element.text == TRADE then place = index + 1 break end
            end
            if not place then error("no Trade entry") end
            entry = MenuUtil.CreateButton(label, Click)
            root:Insert(entry, place)
        end)
        if not ok then entry = nil end
    end
    if not entry then entry = root:CreateButton(label, Click) end
    if not have and entry and entry.SetEnabled then entry:SetEnabled(false) end
end

local function HookUnitMenus()
    if type(Menu) ~= "table" or type(Menu.ModifyMenu) ~= "function" then return end
    for _, tag in ipairs(MENU_TAGS) do pcall(Menu.ModifyMenu, tag, AddTradeEntry) end
end

local function IsUsable(kind)
    return held[kind] ~= nil
end

local function SetStoneActions(kind)
    local button = stoneButtons[kind]
    local createId = Core.HighestKnown(Core.SPELLS[STONES[kind].create], Buttons.IsKnown)
    button.createId = createId
    local usable = IsUsable(kind)
    local hasUse = usable or STONES[kind].alwaysUse
    button.wanted = createId ~= nil or usable or Buttons.DemoMode()
    local actions = {
        type1 = hasUse and "macro" or false, macrotext1 = hasUse and STONES[kind].useMacro or false,
        type2 = createId and "spell" or false, spell2 = createId or false,
    }
    if kind == "healthstone" then
        actions["ctrl-type2"] = "trade"
    elseif STONES[kind].onWeapon then
        actions.askReplace = (held[kind] ~= nil and equipped[kind] == true) or false
        Buttons.SetActions(Buttons.replaceButtons[kind], { type1 = actions.type1, macrotext1 = actions.macrotext1 })
    elseif kind == "soulstone" then
        local ritual = Core.HighestKnown(Core.SPELLS.ritualOfSummoning, Buttons.IsKnown)
        actions["shift-type*"] = ritual and "spell" or false
        actions["shift-spell*"] = ritual or false
    end
    Buttons.SetActions(button, actions)
end

local function StoneTooltip(kind)
    return function(tooltip)
        local button = stoneButtons[kind]
        if held[kind] and tooltip.SetItemByID then
            tooltip:SetItemByID(held[kind].id)
        else
            Buttons.SpellTooltip(tooltip, button.createId, Core.SPELLS[STONES[kind].create][1])
        end
        if kind == "healthstone" then
            Tips.Click(tooltip, "left", Text.ACT_USE)
            Tips.Click(tooltip, "right", Text.ACT_CREATE)
            Tips.Click(tooltip, "ctrlRight", Text.ACT_TRADE)
            Tips.Note(tooltip, Text.TIP_TRADE_OUT_OF_COMBAT)
        elseif STONES[kind].onWeapon then
            Tips.Click(tooltip, "left", Text.ACT_PUT_ON)
            Tips.Click(tooltip, "right", Text.ACT_CREATE)
            Tips.Note(tooltip, Text.TIP_REPLACE_ASKS)
        else
            Tips.Click(tooltip, "left", Text.ACT_USE_FRIEND)
            Tips.Click(tooltip, "right", Text.ACT_CREATE)
            local ritual = Core.HighestKnown(Core.SPELLS.ritualOfSummoning, Buttons.IsKnown)
            if ritual then Tips.Click(tooltip, "shift", SpellName(ritual) or "?") end
            local target, at = ns.db.buttons.soulstoneTarget, ns.db.buttons.soulstoneAt
            if type(target) == "string" and target ~= "" and type(at) == "number" and at > 0 then
                local minutes = math.max(0, math.floor(((GetServerTime and GetServerTime() or time()) - at) / 60))
                Tips.Note(tooltip, string.format(Text.TIP_SOULSTONE_LAST, target, minutes))
            end
        end
    end
end

local ERROR_SOUND = 847

local function WarnNoStone(kind, mouse)
    if mouse ~= "LeftButton" or IsUsable(kind) or IsModifierKeyDown() then return end
    if type(UIErrorsFrame.SuppressMessagesThisFrame) == "function" then UIErrorsFrame:SuppressMessagesThisFrame() end
    ns.Banner(Text[STONES[kind].noStone], 1.0, 0.1, 0.1)
    if not ns.Silent() then PlaySound(ERROR_SOUND) end
end

local function CreateStoneButton(kind)
    local stone = STONES[kind]
    local button = Buttons.NewSecureButton(stone.name, sphere, Core.BUTTON_SIZE)
    button:SetScale(Core.BUTTON_SCALE)
    button.icon:SetTexture(Core.UiTexture(stone.art .. "-01"))
    ns.Rings.Attach(button, button, stone.art)
    button.tooltip = StoneTooltip(kind)
    button.onPreClick = function(self, mouse)
        if kind == "soulstone" and mouse == "LeftButton" and self:GetAttribute("type1") == "macro" and not InCombat() then
            self:SetAttribute("macrotext1", Stones.UseMacro(kind))
        end
        if STONES[kind].onWeapon and mouse == "LeftButton" and held[kind] and not self:GetAttribute("askReplace")
            and not IsModifierKeyDown() then
            Stones.NoteApplied(kind)
        end
        WarnNoStone(kind, mouse)
    end
    if kind == "healthstone" then button.trade = function() Trade("target") end end
    if kind == "soulstone" then
        button.speechSubject = function(mouse)
            if mouse ~= "LeftButton" then return nil end
            if IsShiftKeyDown() then
                if not Core.HighestKnown(Core.SPELLS.ritualOfSummoning, Buttons.IsKnown) then return nil end
                return "ritualOfSummoning", "target"
            end
            if IsModifierKeyDown() or not held.soulstone then return nil end
            return "soulstone", "friend"
        end
    end

    button.cooldown = Durations.NewSwipe(button, { level = 4 })
    button.timeText = Durations.NewTimeText(button, button.cooldown)
    button.span = Durations.New()
    button.binding = Durations.Text(button.timeText, "cooldown", "")

    stoneButtons[kind] = button
    Buttons.AddSlot(kind, button)
end

Buttons.OnRefresh(function()
    for _, kind in ipairs(Buttons.STONE_KINDS) do SetStoneActions(kind) end
end)

local events = CreateFrame("Frame")

local ASK_REPLACE = [[
    if button ~= "LeftButton" or not self:GetAttribute("askReplace") then return end
    self:GetFrameRef("dialog"):Show()
    return false
]]
local AFTER_REPLACE = [[ self:GetFrameRef("dialog"):Hide() ]]
local CANCEL_REPLACE = [[
    self:GetFrameRef("dialog"):Hide()
    return false
]]

local function DialogButton(name, dialog, text, x)
    local button = CreateFrame("Button", name, dialog, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    button:SetSize(120, 22)
    button:SetPoint("BOTTOM", dialog, "BOTTOM", x, 14)
    button:SetText(text)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    SecureHandlerSetFrameRef(button, "dialog", dialog)
    return button
end

Buttons.replaceButtons = {}

-- dialog to ask replace the weapon stone
local function CreateReplaceDialog(kind)
    local suffix = kind == "firestone" and "" or "Spellstone"
    local dialog = CreateFrame("Frame", "NecrosisOGReplaceEnchant" .. suffix, UIParent, "SecureHandlerBaseTemplate")
    dialog:SetSize(330, 100)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    dialog:SetFrameStrata("DIALOG")
    local background = dialog:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.85)
    local text = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOP", dialog, "TOP", 0, -16)
    text:SetWidth(300)
    text:SetText(string.format(Text.STONE_REPLACE, kind == "spellstone" and Text.SET_BUTTON_SPELLSTONE or Text.SET_BUTTON_FIRESTONE))
    local replace = DialogButton("NecrosisOGReplaceEnchantYes" .. suffix, dialog, Text.STONE_REPLACE_YES, -66)
    replace:SetScript("PreClick", function() Stones.NoteApplied(kind) end)
    header:WrapScript(replace, "OnClick", [[ return nil, true ]], AFTER_REPLACE)
    local cancel = DialogButton("NecrosisOGReplaceEnchantNo" .. suffix, dialog, Text.STONE_REPLACE_NO, 66)
    header:WrapScript(cancel, "OnClick", CANCEL_REPLACE)
    dialog:Hide()
    Buttons.replaceButtons[kind] = replace
    if kind == "firestone" then Buttons.replaceButton = replace end
    local stoneButton = stoneButtons[kind]
    SecureHandlerSetFrameRef(stoneButton, "dialog", dialog)
    header:WrapScript(stoneButton, "OnClick", ASK_REPLACE)
    return dialog
end

local sphereButton

-- "bags", spell id or nil
local function SphereClickAction(key)
    local value = Core.SphereClick(key, ns.db.sphere.clicks[key])
    if value == "bags" then return "bags" end
    local entry = Core.SphereClickEntry(value)
    return entry and Core.PickSpell(entry.keys, Buttons.IsKnown) or nil, entry
end

local function RefreshSphereButton()
    if not sphereButton then return end
    for _, click in ipairs(Core.SPHERE_CLICKS) do
        local action, entry = SphereClickAction(click.key)
        local actions = { type1 = "none", spell1 = false, macrotext1 = false }
        if type(action) == "number" then actions = Buttons.CastActions(entry.keys[1], action) end
        for name, value in pairs(actions) do
            local attribute = click.prefix .. name:gsub("1$", click.button)
            if value == false then sphereButton:SetAttribute(attribute, nil) else sphereButton:SetAttribute(attribute, value) end
        end
    end
end

Buttons.OnRefresh(RefreshSphereButton)

-- sphere tooltip, each click and what it do
local function SphereTooltip(tooltip)
    Tips.Title(tooltip, Text.SETTINGS_TITLE, 0.6, 0.4, 1)
    for _, click in ipairs(Core.SPHERE_CLICKS) do
        local action = SphereClickAction(click.key)
        local what = action == "bags" and Text.SET_CLICK_BAGS or (action and SpellName(action))
        if what then Tips.Pair(tooltip, Text[click.text], what) end
    end
    Tips.Click(tooltip, "right", Text.ACT_SETTINGS)
    if not ns.db.locked then Tips.Click(tooltip, "drag", Text.ACT_MOVE) end
end

local function CreateSphereButton()
    local button = Buttons.NewSecureButton("NecrosisOGSphereButton", sphere, Core.SPHERE_SIZE)
    button:ClearAllPoints()
    button:SetAllPoints(sphere)
    button:SetFrameLevel(sphere:GetFrameLevel() + 1)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function() local drag = sphere:GetScript("OnDragStart"); if drag then drag(sphere) end end)
    button:SetScript("OnDragStop", function() local stop = sphere:GetScript("OnDragStop"); if stop then stop(sphere) end end)
    button.tooltip = SphereTooltip
    button:SetScript("OnEnter", function(self)
        ns.Sphere.SetHighlight(true)
        ShowTooltip(self)
    end)
    button:SetScript("OnLeave", function()
        ns.Sphere.SetHighlight(false)
        HideTooltip()
    end)
    button.speechSubject = function(mouse)
        if mouse ~= "LeftButton" and mouse ~= "MiddleButton" then return nil end
        local key = mouse == "MiddleButton" and "middle" or (IsControlKeyDown() and "ctrlLeft")
            or (IsShiftKeyDown() and "shiftLeft") or "left"
        local action, entry = SphereClickAction(key)
        if type(action) == "number" and entry.keys[1] == "ritualOfSummoning" then return "ritualOfSummoning", "target" end
        return nil
    end
    button.onPostClick = function(_, mouse)
        if mouse == "RightButton" then
            ns.SettingsWindow.Toggle()
        elseif mouse == "MiddleButton" and SphereClickAction("middle") == "bags" and type(ToggleAllBags) == "function" then
            ToggleAllBags()
        end
    end
    sphereButton = button
end

local function CreateAll(frame)
    sphere = frame
    header = CreateFrame("Frame", "NecrosisOGButtonHeader", UIParent, "SecureHandlerBaseTemplate")
    CreateSphereButton()
    for _, kind in ipairs(Buttons.STONE_KINDS) do CreateStoneButton(kind) end
    CreateReplaceDialog("firestone")
    CreateReplaceDialog("spellstone")
    ns.Fire(creators, sphere, header)
    created = true
    Buttons.UpdateStones()
end

local macrosReady = false
local warnedMacrosFull = false

local function FindMacro(name)
    local accounts, characters = GetNumMacros()
    local base = Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS or 120
    for i = 1, accounts or 0 do
        if GetMacroInfo(i) == name then return i end
    end
    for i = base + 1, base + (characters or 0) do
        if GetMacroInfo(i) == name then return i end
    end
    return nil
end

local function MacrosAvailable()
    return type(CreateMacro) == "function" and type(GetMacroInfo) == "function" and type(GetNumMacros) == "function"
end

local SHOW_TOOLTIP = "#showtooltip\n"

local function MacroText(key)
    if Core.STONE_MACROS[key] then
        local text = ns.Bindings and ns.Bindings.StoneMacro(key, Core.MACRO_LIMIT - #SHOW_TOOLTIP)
        if not text or text == "" then return nil end
        return Core.STONE_MACROS[key], SHOW_TOOLTIP .. text
    end
    local id = Core.HighestKnown(Core.SPELLS[key], Buttons.IsKnown)
    local spellName = id and SpellName(id)
    if not spellName then return nil end
    return Core.FOCUS_MACROS[key], Core.FocusMacroBody(spellName, ns.db.buttons.autoFocus == true)
end

-- update one focus macro, create it if create is true
local function SyncFocusMacro(key, create)
    local macro, body = MacroText(key)
    if not macro then return nil end
    local index = FindMacro(macro)
    if index then
        local _, _, old = GetMacroInfo(index)
        if old ~= body then pcall(EditMacro, index, nil, nil, body) end
        return index
    elseif create then
        local ok, made = pcall(CreateMacro, macro, "INV_MISC_QUESTIONMARK", body, true)
        if (not ok or not made or made == 0) and not warnedMacrosFull then
            warnedMacrosFull = true
            ns.Print(Text.FOCUS_MACROS_FULL)
        end
        if ok and made and made ~= 0 then return made end
    end
    return nil
end

function Buttons.SyncFocusMacros()
    if not macrosReady or InCombat() or not MacrosAvailable() then return end
    local focus = ns.db.buttons.autoFocus == true
    for _, key in ipairs(Core.FOCUS_MACRO_KEYS) do SyncFocusMacro(key, focus) end
    for _, key in ipairs(Core.STONE_MACRO_KEYS) do SyncFocusMacro(key, false) end
end

Buttons.OnRefresh(Buttons.SyncFocusMacros)

-- put focus macro on cursor
function Buttons.PickupFocusMacro(key)
    if not (Core.FOCUS_MACROS[key] or Core.STONE_MACROS[key]) or not macrosReady or InCombat() or not MacrosAvailable() then return false end
    if type(PickupMacro) ~= "function" then return false end
    local index = SyncFocusMacro(key, true)
    if not index then return false end
    return pcall(PickupMacro, index)
end

local handlers = {}

handlers.UPDATE_MACROS = function()
    macrosReady = true
    Buttons.SyncFocusMacros()
end

handlers.PLAYER_ENTERING_WORLD = function()
    C_Timer.After(2, function()
        macrosReady = true
        Buttons.SyncFocusMacros()
    end)
end

handlers.PLAYER_REGEN_ENABLED = function()
    warnedDrag = false
    if waitingSphere then
        local frame = waitingSphere
        waitingSphere = nil
        CreateAll(frame)
    elseif pending then
        Buttons.Refresh()
    end
end

handlers.SPELLS_CHANGED = function() Buttons.Refresh() end
handlers.LEARNED_SPELL_IN_SKILL_LINE = function() Buttons.Refresh() end
handlers.TRADE_SHOW = function() tradeOpen = true end
handlers.TRADE_CLOSED = function() tradeOpen = false end

events:SetScript("OnEvent", function(_, event, ...) handlers[event](...) end)

table.insert(ns.onSphere, function(frame)
    HookUnitMenus()
    for name in pairs(handlers) do events:RegisterEvent(name) end
    if InCombat() then
        waitingSphere = frame
        ns.Print(Text.BUTTONS_AFTER_COMBAT)
        return
    end
    CreateAll(frame)
end)

table.insert(ns.onRecall, function() Buttons.ResetPlaces() end)

table.insert(ns.onDemo, function()
    if not created then return end
    UpdateCooldowns()
    Buttons.Refresh()
end)

table.insert(ns.onDemoData, function(on)
    if not created then return end
    if on then
        for kind, length in pairs(Core.DEMO.stoneCooldowns) do
            ns.DemoEvery(length + Core.DEMO.pause, function(now)
                demoCooldowns[kind] = { start = now, length = length }
                UpdateCooldowns()
                if kind == "soulstone" then
                    ns.DemoAt(now + length, function() ns.Controls.SoulstoneReadySound() end)
                end
            end)
        end
    else
        for kind in pairs(demoCooldowns) do demoCooldowns[kind] = nil end
        UpdateCooldowns()
    end
end)

Buttons.Stone = function(kind) return stoneButtons[kind], held[kind], equipped[kind] end -- for tests
Buttons.Header = function() return header end
Buttons.SphereButton = function() return sphereButton end
Buttons.IsPending = function() return pending end

-- show or hide one button
function Buttons.SetShown(slot, on)
    if not Core.ToSet(Core.BUTTON_SLOTS)[slot] then return end
    ns.db.buttons.show[slot] = on == true
    Buttons.Refresh()
    ns.Sphere.UpdateShards()
end

function Buttons.SetMenuShift(menu, axis, value)
    if menu ~= "demons" and menu ~= "utility" and menu ~= "curses" then return end
    local all = ns.db.buttons.menuOffset
    if type(all) ~= "table" then all = {}; ns.db.buttons.menuOffset = all end
    if type(all[menu]) ~= "table" then all[menu] = {} end
    all[menu][axis == 1 and "x" or "y"] = Core.ClampMenuShift(value)
    Buttons.Refresh()
end

ns.OnSetting({ "buttons.autoFocus", "buttons.ringOrder", "buttons.menuOrder", "buttons.menuOff",
    "buttons.menuCloses", "buttons.menuDirection", "sphere.clicks", "sphere.buttonSize", "sphere.rotation",
    "sphere.spacing", "sphere.distance", "controlButtons", "reminderBar.scale", "reminderBar.spacing" }, function() Buttons.Refresh() end)

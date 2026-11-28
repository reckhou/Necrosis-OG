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

-- shard button, limit and destroy extra shards, move shards to soul bag
local _, ns = ...
local Core, Text = ns.Core, ns.Text
local Buttons = ns.Buttons

local Shards = {}
ns.Shards = Shards

local button

local IsSecret, Plain, InCombat = ns.Game.IsSecret, ns.Game.Plain, ns.Game.InCombat

local lastBag = type(NUM_BAG_SLOTS) == "number" and NUM_BAG_SLOTS or 4

local function BagInfo(bag, shardFamily)
    local ok, _, family = pcall(C_Container.GetContainerNumFreeSlots, bag)
    local soul = ok and not IsSecret(family) and Core.IsSoulBag(family, shardFamily)
    local slots = Plain(C_Container.GetContainerNumSlots, bag)
    return soul, Core.IsNumber(slots) and slots or 0
end

local function SoulBagCapacity()
    local shardFamily = Plain(C_Item.GetItemFamily, Core.SOUL_SHARD_ITEM)
    local capacity = 0
    for bag = 1, lastBag do
        local soul, slots = BagInfo(bag, shardFamily)
        if soul then capacity = capacity + slots end
    end
    return capacity
end

local function Limit(capacity)
    return Core.ShardLimit(ns.db.buttons.shardLimit, capacity or SoulBagCapacity())
end

function Shards.Limit() return (Limit()) end

function Shards.LimitBounds()
    local _, low, high = Limit()
    return low, high
end

local function Count()
    local count = Plain(C_Item.GetItemCount, Core.SOUL_SHARD_ITEM)
    return type(count) == "number" and count or 0
end

function Shards.ShownLimit(limit)
    if button and Buttons.SlotShown("shards") then return limit or Shards.Limit() end
    return nil
end

-- bags with soul bag flag, shards and free slots
local function ReadBags()
    local shardFamily = Plain(C_Item.GetItemFamily, Core.SOUL_SHARD_ITEM)
    local bags, capacity = {}, 0
    for bag = 0, lastBag do
        local soul, slots = BagInfo(bag, shardFamily)
        local entry = { bag = bag, soul = soul, shards = {}, free = {} }
        if soul and bag > 0 then capacity = capacity + slots end
        if slots > 0 then
            for slot = 1, slots do
                local ok2, id = pcall(C_Container.GetContainerItemID, bag, slot)
                if ok2 and not IsSecret(id) then
                    if id == nil then
                        entry.free[#entry.free + 1] = { bag = bag, slot = slot }
                    elseif id == Core.SOUL_SHARD_ITEM then
                        entry.shards[#entry.shards + 1] = { bag = bag, slot = slot }
                    end
                end
            end
        end
        bags[#bags + 1] = entry
    end
    return bags, capacity
end

-- put back anything on cursor
local function EmptyCursor()
    if CursorHasItem() then ClearCursor() end
end

local function Extras()
    local loose = {}
    local bags, capacity = ReadBags()
    for _, entry in ipairs(bags) do
        if not entry.soul then
            for _, place in ipairs(entry.shards) do loose[#loose + 1] = place end
        end
    end
    return Core.ShardsToDestroy(loose, Count(), Limit(capacity))
end

-- destroy last shard over limit, outside soul bag
function Shards.Destroy()
    if GetCursorInfo() then return "holding" end
    local extra = Extras()
    if #extra == 0 then return "none" end
    local place = extra[#extra]
    C_Container.PickupContainerItem(place.bag, place.slot)
    local kind, id = GetCursorInfo()
    if kind ~= "item" or id ~= Core.SOUL_SHARD_ITEM then
        EmptyCursor()
        return "none"
    end
    local ok = pcall(DeleteCursorItem)
    if not ok or GetCursorInfo() then
        ClearCursor()
        return "refused"
    end
    return "deleted"
end

local armed = false
local busyUntil
local BUSY_SECONDS = 1.5
local lastCombatEnd
local lastDelete
local countTicker
local swipeEnd
local holdUntil
local refused = {}
local keyListener, hooked

local function AutoOn() return ns.db and ns.db.buttons.autoDestroy == true end

local function Since(moment) return moment and GetTime() - moment or nil end

-- sec left to count down and full length, or nil
local function CountdownLeft()
    if not AutoOn() or not armed or InCombat() then return nil end
    local left, total = Core.ShardWaitLeft(Since(lastCombatEnd), Since(lastDelete))
    if holdUntil and holdUntil - GetTime() > left then left, total = holdUntil - GetTime(), Core.SHARD_LIMIT_HOLD end
    if left > 0 then return left, total end
end

function Shards.UpdateCountdown()
    if not button then return end
    local left, total = CountdownLeft()
    if left then
        local ending = GetTime() + left
        if not swipeEnd or math.abs(ending - swipeEnd) > 0.05 then
            swipeEnd = ending
            button.cooldown:SetCooldown(ending - total, total)
            local function Again() if swipeEnd == ending then Shards.UpdateCountdown() end end
            C_Timer.After(math.max(0, left - Core.SHARD_READY_LEAD), Again)
            C_Timer.After(left + 0.02, Again)
        end
    elseif swipeEnd then
        swipeEnd = nil
        button.cooldown:SetCooldown(0, 0)
    end
    button.ready:SetShown((left == nil or left <= Core.SHARD_READY_LEAD + 0.01) and AutoOn() and armed
        and not InCombat())
    if left then
        button.countText:SetText(tostring(math.ceil(left)))
        button.countText:Show()
        if not countTicker and C_Timer and C_Timer.NewTicker then
            countTicker = C_Timer.NewTicker(Core.SHARD_COUNT_EVERY, Shards.UpdateCountdown)
        end
    else
        button.countText:Hide()
        if countTicker then
            countTicker:Cancel()
            countTicker = nil
        end
    end
end

-- after a press, destroy one shard if allowed
local function TryAuto(kind)
    if not armed then return end
    if not Core.ShardAutoAllowed(InCombat(), Since(lastCombatEnd), Since(lastDelete)) then return end
    if busyUntil and GetTime() < busyUntil then return end
    if holdUntil and GetTime() < holdUntil then return end
    if refused[kind] then return end
    if Plain(GetCurrentKeyBoardFocus) then return end
    if Plain(SpellIsTargeting) then return end
    if not AutoOn() then armed = false return end
    local before = #Extras()
    local result = Shards.Destroy()
    if result == "deleted" then
        busyUntil = GetTime() + BUSY_SECONDS
        lastDelete = GetTime()
        if before <= 1 then armed = false end
        Shards.UpdateCountdown()
    elseif result == "refused" then
        refused[kind] = true
    elseif result == "none" then
        armed = false
    end
end

Shards.TryAuto = TryAuto

local function BuildKeyListener()
    if keyListener or InCombat() then return end
    local frame = CreateFrame("Frame", "NecrosisOGShardKeys", UIParent)
    if not pcall(frame.SetPropagateKeyboardInput, frame, true) then return end
    if frame.GetPropagateKeyboardInput and frame:GetPropagateKeyboardInput() ~= true then return end
    if not pcall(frame.EnableKeyboard, frame, true) then return end
    frame:SetScript("OnKeyDown", function() TryAuto("key") end)
    keyListener = frame
end

local GLOBAL_CALLS = { "UseAction", "CastSpellByName", "CastSpellByID", "UseInventoryItem", "RunMacro",
    "JumpOrAscendStart" }
local TABLE_CALLS = { { "C_Container", "UseContainerItem" }, { "C_Item", "UseItemByName" }, { "C_Macro", "RunMacroText" } }

local function SetupHooks()
    if hooked then return end
    hooked = true
    for _, name in ipairs(GLOBAL_CALLS) do
        if type(_G[name]) == "function" then
            pcall(hooksecurefunc, name, function() TryAuto(name) end)
        end
    end
    for _, call in ipairs(TABLE_CALLS) do
        local owner = _G[call[1]]
        if type(owner) == "table" and type(owner[call[2]]) == "function" then
            pcall(hooksecurefunc, owner, call[2], function() TryAuto(call[2]) end)
        end
    end
    if WorldFrame and WorldFrame.HookScript then
        WorldFrame:HookScript("OnMouseDown", function(_, mouse)
            if mouse == "LeftButton" then TryAuto("world click") end
        end)
    end
end

function Shards.Arm()
    busyUntil = nil
    armed = AutoOn() and #Extras() > 0
    if AutoOn() then
        SetupHooks()
        BuildKeyListener()
    end
end

-- set limit from settings page
function Shards.SetLimit(limit)
    local current, low, high = Limit()
    if not Core.IsNumber(limit) then return end
    limit = math.max(low, math.min(high, math.floor(limit)))
    if limit == current then return end
    ns.SetSetting("buttons.shardLimit", limit)
end

-- right click, auto destroy on or off
function Shards.ToggleAuto()
    ns.SetSetting("buttons.autoDestroy", not AutoOn())
    ns.Print(AutoOn() and Text.SHARDS_AUTO_ON or Text.SHARDS_AUTO_OFF)
    if AutoOn() then TryAuto("shard button") end
end

-- left click, move shards into soul bag
function Shards.Sort()
    local loose, free, hasSoulBag = {}, {}, false
    for _, entry in ipairs(ReadBags()) do
        if entry.soul then
            hasSoulBag = true
            for _, place in ipairs(entry.free) do free[#free + 1] = place end
        else
            for _, place in ipairs(entry.shards) do loose[#loose + 1] = place end
        end
    end
    if not hasSoulBag then
        ns.Print(Text.SHARDS_NO_SOUL_BAG)
        return
    end
    if #loose == 0 then return end
    if #free == 0 then
        ns.Print(Text.SHARDS_SOUL_BAG_FULL)
        return
    end
    local moves = Core.ShardMoves(loose, free)
    EmptyCursor()
    for _, move in ipairs(moves) do
        C_Container.PickupContainerItem(move.from.bag, move.from.slot)
        C_Container.PickupContainerItem(move.to.bag, move.to.slot)
        EmptyCursor()
    end
end

function Shards.Update()
    if not button then return end
    local over = Count() > Limit()
    local icon = Plain(C_Item.GetItemIconByID, Core.SOUL_SHARD_ITEM)
    local key = "ShardDestroy"
    if icon then
        button.icon:SetTexture(icon)
        if not button.dressed then
            button.dressed = true
            Buttons.DressRing(button, Core.MENU_ICON_INSET * Core.BUTTON_SIZE / Core.MENU_ITEM_SIZE, "Ring")
        end
        key = "soulShard"
    else
        button.icon:SetTexture(Core.UiTexture(over and "ShardDestroy-02" or "ShardDestroy-01"))
    end
    ns.Rings.SetKey(button, key)
    ns.Rings.SetGlowKey(button.lit, key)
    ns.Rings.SetGlowKey(button.pulse, key)
    button.lit:SetShown(over and button.dressed == true)
    local on = AutoOn()
    button.pulse:SetShown(on)
    if on then
        if not button.pulse.beat:IsPlaying() then button.pulse.beat:Play() end
    else
        button.pulse.beat:Stop()
    end
    Shards.UpdateCountdown()
end

function Shards.FreeSoulSlots()
    local free, hasSoulBag = 0, false
    for _, entry in ipairs(ReadBags()) do
        if entry.soul then
            hasSoulBag = true
            free = free + #entry.free
        end
    end
    return hasSoulBag and free or nil
end

local Tips = ns.Tips

local function Tooltip(tooltip)
    Tips.Title(tooltip, Text.TIP_SHARDS_TITLE)
    Tips.Pair(tooltip, Text.TIP_SHARDS_HELD, string.format(Text.TIP_SHARDS_COUNT, Count(), Limit()))
    local free = Shards.FreeSoulSlots()
    if free then Tips.Pair(tooltip, Text.TIP_SHARDS_FREE, tostring(free)) end
    local on = AutoOn()
    Tips.Click(tooltip, "left", Text.ACT_MOVE_TO_BAG)
    Tips.Click(tooltip, "right", (on and "|cff00ff00" or "|cffff2020") .. (on and Text.ACT_AUTO_ON or Text.ACT_AUTO_OFF) .. "|r")
    Tips.Click(tooltip, "wheel", Text.ACT_CHANGE_LIMIT)
end

local function Changed()
    Shards.Update()
    if ns.Sphere then ns.Sphere.UpdateShards() end
    Tips.Redraw(button)
    if ns.SettingsWindow and ns.SettingsWindow.RefreshShardLimit then ns.SettingsWindow.RefreshShardLimit() end
end

local function Create(sphere)
    button = CreateFrame("Button", "NecrosisOGShardsButton", sphere)
    button:SetSize(Core.BUTTON_SIZE, Core.BUTTON_SIZE)
    button:SetScale(Core.BUTTON_SCALE)
    button:RegisterForClicks("AnyUp")
    button:EnableMouseWheel(true)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.lit = ns.Rings.NewGlow(button, "ShardDestroy")
    button.lit:Hide()
    button.pulse = ns.Rings.NewGlow(button, "ShardDestroy", true)
    button.pulse:SetFrameLevel(button:GetFrameLevel() + 4)
    button.pulse:Hide()
    button.pulse.beat = button.pulse:CreateAnimationGroup()
    button.pulse.beat:SetLooping("BOUNCE")
    local fade = button.pulse.beat:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(Core.SHARD_PULSE_DIM)
    fade:SetDuration(Core.SHARD_PULSE)
    local cooldown = ns.Durations.NewSwipe(button, { level = 5, reverse = true })
    button.cooldown = cooldown
    cooldown:SetAlpha(0)
    cooldown:SetCooldown(GetTime(), 0.1)
    C_Timer.After(0.3, function()
        cooldown:SetAlpha(1)
        if not swipeEnd then cooldown:SetCooldown(0, 0) end
    end)
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(button:GetFrameLevel() + 6)
    button.ready = overlay:CreateTexture(nil, "ARTWORK")
    button.ready:SetTexture(Core.UiTexture("Swipe"))
    button.ready:SetVertexColor(0, 0, 0, 0.7)
    button.ready:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.ready:SetSize(Core.BUTTON_SIZE * Core.SWIPE_WIDTH, Core.BUTTON_SIZE * Core.SWIPE_HEIGHT)
    button.ready:Hide()
    button.countText = overlay:CreateFontString(nil, "OVERLAY", ns.Durations.TimeFont())
    button.countText:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.countText:SetTextColor(1, 1, 1)
    button.countText:Hide()
    Tips.Attach(button, Tooltip)
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "LeftButton" then
            Shards.Sort()
        elseif mouse == "RightButton" then
            Shards.ToggleAuto()
        end
    end)
    ns.Sounds.Button(button)
    button:SetScript("OnMouseWheel", function(_, delta)
        Shards.SetLimit(Limit() + (delta > 0 and 1 or -1))
    end)
    ns.Rings.Attach(button, button, "ShardDestroy")
    button.wanted = true
    Buttons.AddSlot("shards", button)
    Shards.Update()
    if ns.Sphere then ns.Sphere.UpdateShards() end
end

Buttons.OnCreate(function(sphere) Create(sphere) end)

local events = CreateFrame("Frame")
local lastCapacity
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then lastCombatEnd = GetTime() end
    Shards.Arm()
    Shards.Update()
    if event == "BAG_UPDATE_DELAYED" then
        local capacity = SoulBagCapacity()
        if capacity ~= lastCapacity then
            lastCapacity = capacity
            if ns.SettingsWindow and ns.SettingsWindow.RefreshShardLimit then ns.SettingsWindow.RefreshShardLimit() end
        end
    end
end)

table.insert(ns.onSphere, function()
    lastCapacity = SoulBagCapacity()
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    Shards.Arm()
end)

ns.OnSetting("buttons.shardLimit", function()
    holdUntil = GetTime() + Core.SHARD_LIMIT_HOLD
    Shards.Arm()
    if button then Changed(); Shards.UpdateCountdown() end
end)

ns.OnSetting("buttons.autoDestroy", function()
    refused = {}
    Shards.Arm()
    if button then Changed() end
end)

Shards.Button = function() return button end

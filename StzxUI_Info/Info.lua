-- StzxUI Info
-- Small text readouts, in the info bar across the top of the screen (left,
-- centre or right, your choice for each), or each on its own in move mode:
--   Levelling    "Lv 18  45%  12.3k xp/h  1h 05m" (XP per hour this session and the
--                time to the next level at that pace; hidden at max level). Hover:
--                exact XP, rested, quests ready to hand in, this session's numbers
--   Hearthstone  "Hearth: Ironforge", or its cooldown "Hearth 23m"; hover for every
--                travel option you have, click for a menu that casts them (Travel.lua)
--   Coordinates  "45.2, 67.8" (blank where the game hides your position, e.g. dungeons)
--   Layer        which server layer you're on, read from creatures nearby (off by default)
--   Gold         your gold; its tooltip lists every character's and the total
--   Bags         free bag slots
--   Durability   your most worn item's durability, yellow then red as it drops
--   Stats        "60 fps  42 ms  14:05"; its tooltip lists addon memory use
-- Plus a thin XP bar along the bottom of the info bar (rested XP shown lighter).
-- One "Text size" slider sizes them all, in the bar or not.
--
-- Each readout is one entry in READOUTS below: its frame, settings, how wide
-- it is in the bar, how it updates (a timer and/or game events) and its tooltip.

local ADDON_NAME = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local Info = StzxUI:NewModule("Info", ADDON_NAME, {
	showStats = true,
	statsClock = true,   -- add the time to the stats text
	clock24 = true,      -- 24-hour clock
	memoryTooltip = true, -- addon memory in the stats tooltip
	showCoords = true,
	showXP = true,
	xpBar = true,         -- thin XP bar along the info bar
	showGold = true,
	showBags = true,
	showDurability = true,
	showLayer = false,    -- which server layer you're on (read from creatures nearby)
	showHearth = true,
	travelMenu = true,    -- click the hearthstone readout: travel menu (Travel.lua)
	topBar = true,        -- readouts sit in the info bar
	barLength = 100,      -- % of the screen's width
	barStats = "RIGHT",   -- where each readout sits in the bar: LEFT, CENTER, RIGHT
	barCoords = "CENTER",
	barXP = "LEFT",
	barHearth = "LEFT",
	barGold = "RIGHT",
	barBags = "RIGHT",
	barDurability = "RIGHT",
	barLayer = "CENTER",
	textSize = 13,
}, {
	title = "Info",
	description = "Readouts in a bar across the top of the screen: levelling, hearthstone, coordinates, gold, bags, "
		.. "durability, FPS, latency and clock.",
})

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FLAT = "Interface\\Buttons\\WHITE8x8"
local A = StzxUI.ACCENT
local FREE_HEIGHT = 20
local HEARTHSTONE = 6948 -- the Hearthstone item

local GREEN, YELLOW, RED = "|cff7fdf7f", "|cffffd166", "|cffff6b6b"

local function Short(n)
	if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
	if n >= 1000 then return ("%.1fk"):format(n / 1000) end
	return tostring(math.floor(n))
end

-- 1234567 -> "1,234,567"
local function Thousands(n)
	local text = tostring(math.floor(n))
	while true do
		local done
		text, done = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if done == 0 then return text end
	end
end

local function Duration(seconds)
	if seconds >= 3600 then
		return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
	end
	return ("%dm"):format(math.max(1, math.floor(seconds / 60)))
end

-- A class's colour as a text colour code (white if unknown).
local function ClassCode(class)
	local colour = class and C_ClassColor and C_ClassColor.GetClassColor(class)
	if not colour then return "|cffffffff" end
	return ("|cff%02x%02x%02x"):format(colour.r * 255, colour.g * 255, colour.b * 255)
end

local function Tooltip(frame)
	GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM", 0, -4)
	GameTooltip:ClearLines()
	return GameTooltip
end

---------------------------------------------------------------------------
-- Stats: FPS, latency, clock; addon memory in the tooltip
---------------------------------------------------------------------------

local function LatencyColor(ms)
	if ms < 100 then return GREEN end
	if ms < 250 then return YELLOW end
	return RED
end

local function UpdateStats(frame)
	local db = Info.db
	local fps = math.floor((GetFramerate() or 0) + 0.5)
	local _, _, home, world = GetNetStats()
	local ms = math.max(home or 0, world or 0)
	local text = ("%d fps  %s%d ms|r"):format(fps, LatencyColor(ms), ms)
	if db.statsClock then
		text = text .. "  " .. date(db.clock24 and "%H:%M" or "%I:%M %p"):gsub("^0", "")
	end
	frame.text:SetText(text)
end

local function Memory(kb)
	if kb >= 1024 then return ("%.1f MB"):format(kb / 1024) end
	return ("%d KB"):format(kb)
end

-- Loaded addons by memory use, biggest first: { { title, kb }, ... }, total kb.
function Info.AddonMemory()
	UpdateAddOnMemoryUsage()
	local list, total = {}, 0
	for i = 1, C_AddOns.GetNumAddOns() do
		if C_AddOns.IsAddOnLoaded(i) then
			local name, title = C_AddOns.GetAddOnInfo(i)
			local kb = GetAddOnMemoryUsage(i) or 0
			total = total + kb
			list[#list + 1] = { (title and title ~= "" and title or name), kb }
		end
	end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	return list, total
end

local MEMORY_LINES = 12

local function StatsTooltip(frame)
	local tip = Tooltip(frame)
	local _, _, home, world = GetNetStats()
	tip:AddLine("Performance", 1, 1, 1)
	tip:AddDoubleLine("Frame rate", ("%d fps"):format(math.floor((GetFramerate() or 0) + 0.5)), 0.8, 0.8, 0.8, 1, 1, 1)
	tip:AddDoubleLine("Home latency", ("%d ms"):format(home or 0), 0.8, 0.8, 0.8, 1, 1, 1)
	tip:AddDoubleLine("World latency", ("%d ms"):format(world or 0), 0.8, 0.8, 0.8, 1, 1, 1)
	if Info.db.memoryTooltip then
		tip:AddLine(" ")
		if InCombatLockdown() then
			-- Measuring every addon's memory can stutter the game: not in a fight.
			tip:AddLine("Addon memory: after the fight", 0.6, 0.6, 0.6)
		else
			local list, total = Info.AddonMemory()
			tip:AddDoubleLine("Addon memory", Memory(total), 1, 1, 1, 1, 1, 1)
			for i = 1, math.min(MEMORY_LINES, #list) do
				tip:AddDoubleLine(list[i][1], Memory(list[i][2]), 0.8, 0.8, 0.8, 1, 1, 1)
			end
		end
	end
	tip:Show()
end

---------------------------------------------------------------------------
-- Coordinates
---------------------------------------------------------------------------

local function UpdateCoords(frame)
	local mapID = Plain(C_Map.GetBestMapForUnit("player"))
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	local x, y
	if position then
		x, y = position:GetXY()
		x, y = Plain(x), Plain(y)
	end
	if x and y and (x > 0 or y > 0) then
		frame.text:SetFormattedText("%.1f, %.1f", x * 100, y * 100)
	else
		frame.text:SetText("--, --")
	end
end

---------------------------------------------------------------------------
-- Levelling pace (and the XP bar)
---------------------------------------------------------------------------

-- This session's XP, counted from each gain (a level-up wraps the bar).
local session = { start = nil, gained = 0, gains = 0, lastGain = nil, lastXP = nil, lastMax = nil, money = nil }

local function MaxLevel()
	return (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
end

function Info.ResetXP()
	session.start, session.gained, session.gains, session.lastGain = GetTime(), 0, 0, nil
	session.lastXP, session.lastMax = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
end

local function CountXP()
	local xp, max = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
	if not (xp and max) then return end
	local last, lastMax = session.lastXP, session.lastMax
	if last then
		local gain = xp - last
		if gain < 0 and lastMax then gain = (lastMax - last) + xp end -- levelled up
		if gain > 0 then
			session.gained, session.gains, session.lastGain = session.gained + gain, session.gains + 1, gain
		end
	end
	session.lastXP, session.lastMax = xp, max
end

-- Text for the readout (also used by the tests).
function Info.XPText()
	local level = Plain(UnitLevel("player")) or 0
	local xp, max = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
	if level >= MaxLevel() or not (xp and max) or max <= 0 then return nil end
	local text = ("Lv %d  %d%%"):format(level, math.floor(xp / max * 100))
	local elapsed = GetTime() - (session.start or GetTime())
	if session.gained > 0 and elapsed >= 60 then
		local perHour = session.gained / elapsed * 3600
		text = text .. ("  %s xp/h  %s"):format(Short(perHour), Duration((max - xp) / perHour * 3600))
	else
		text = text .. "  -- xp/h"
	end
	return text
end

local function UpdateXP(frame)
	frame.text:SetText(Info.XPText() or "")
end

-- Finished quests in your log, waiting to be handed in: count, total XP.
function Info.QuestXPWaiting()
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and GetQuestLogRewardXP) then return 0, 0 end
	local count, xp = 0, 0
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		local id = info and not info.isHeader and Plain(info.questID)
		if id and (C_QuestLog.IsComplete(id) or (C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(id))) then
			count = count + 1
			xp = xp + (Plain(GetQuestLogRewardXP(id)) or 0)
		end
	end
	return count, xp
end

-- Hover: the exact numbers behind the levelling readout.
local function LevellingTooltip(frame)
	local level = Plain(UnitLevel("player")) or 0
	local xp, max = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
	if not (xp and max) or max <= 0 then return end
	local tip = Tooltip(frame)
	local W, G = 0.8, 1 -- label grey, value white
	local toGo = max - xp
	tip:AddLine(("Level %d"):format(level), 1, 1, 1)
	tip:AddDoubleLine("Experience", ("%s / %s (%.1f%%)"):format(Thousands(xp), Thousands(max), xp / max * 100), W, W, W, G, G, G)
	tip:AddDoubleLine("To level " .. (level + 1), Thousands(toGo), W, W, W, G, G, G)
	local rested = (GetXPExhaustion and Plain(GetXPExhaustion())) or 0
	if rested > 0 then
		tip:AddDoubleLine("Rested", ("%s (%d%% of a level)"):format(Thousands(rested), math.floor(rested / max * 100)),
			W, W, W, 0.45, 0.7, 1)
	else
		tip:AddDoubleLine("Rested", "none", W, W, W, 0.6, 0.6, 0.6)
	end
	local count, questXP = Info.QuestXPWaiting()
	if count > 0 then
		tip:AddDoubleLine(("Quests to hand in (%d)"):format(count), Thousands(questXP) .. " XP", W, W, W, 1, 0.82, 0.25)
		local after = xp + questXP
		if after >= max then
			tip:AddDoubleLine("After handing in", "enough to level!", W, W, W, 0.5, 1, 0.5)
		else
			tip:AddDoubleLine("After handing in", ("%.1f%%, %s to go"):format(after / max * 100, Thousands(max - after)),
				W, W, W, G, G, G)
		end
	end
	tip:AddLine(" ")
	tip:AddLine("This session", 1, 1, 1)
	local elapsed = GetTime() - (session.start or GetTime())
	tip:AddDoubleLine("Time", Duration(math.max(60, elapsed)), W, W, W, G, G, G)
	tip:AddDoubleLine("XP gained", Thousands(session.gained), W, W, W, G, G, G)
	if session.gained > 0 and elapsed >= 60 then
		local perHour = session.gained / elapsed * 3600
		tip:AddDoubleLine("XP per hour", Thousands(perHour), W, W, W, G, G, G)
		tip:AddDoubleLine("Time to level at this pace", Duration(toGo / perHour * 3600), W, W, W, G, G, G)
	end
	if session.lastGain then
		tip:AddDoubleLine("Last gain", Thousands(session.lastGain) .. " XP", W, W, W, G, G, G)
		local average = session.gained / session.gains
		tip:AddDoubleLine("Average gain", ("%s XP (about %d more to level)"):format(Thousands(average),
			math.ceil(toGo / average)), W, W, W, G, G, G)
	end
	tip:AddLine(" ")
	tip:AddLine("/stzx xp starts the session count again.", 0.6, 0.6, 0.6)
	tip:Show()
end

---------------------------------------------------------------------------
-- Hearthstone
---------------------------------------------------------------------------

-- Seconds left on the Hearthstone's cooldown (0: ready).
function Info.HearthCooldown()
	if not (C_Container and C_Container.GetItemCooldown) then return 0 end
	local start, duration = C_Container.GetItemCooldown(HEARTHSTONE)
	start, duration = Plain(start), Plain(duration)
	if not (start and duration) or start <= 0 or duration <= 1.5 then return 0 end -- 1.5: just the global cooldown
	return math.max(0, start + duration - GetTime())
end

local function BindLocation()
	return (GetBindLocation and Plain(GetBindLocation())) or "?"
end

function Info.HearthText()
	local left = Info.HearthCooldown()
	if left > 0 then return ("Hearth %s%s|r"):format(YELLOW, Duration(left)) end
	return ("Hearth: %s%s|r"):format(GREEN, BindLocation())
end

local function UpdateHearth(frame) frame.text:SetText(Info.HearthText()) end

local function HearthTooltip(frame)
	local tip = Tooltip(frame)
	tip:AddLine("Hearthstone", 1, 1, 1)
	tip:AddDoubleLine("Set to", BindLocation(), 0.8, 0.8, 0.8, 1, 1, 1)
	local left = Info.HearthCooldown()
	tip:AddDoubleLine("Ready", left > 0 and ("in " .. Duration(left)) or "now", 0.8, 0.8, 0.8, 1, 1, 1)
	tip:Show()
end

---------------------------------------------------------------------------
-- Gold
---------------------------------------------------------------------------

local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

-- Copper as "123g 45s" (no copper once there's gold), "45s 6c" or "6c", with coin icons.
function Info.MoneyText(copper)
	copper = math.floor(math.abs(copper or 0))
	local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if gold > 0 then return ("%s%s %d%s"):format(Thousands(gold), GOLD, silver, SILVER) end
	if silver > 0 then return ("%d%s %d%s"):format(silver, SILVER, rest, COPPER) end
	return ("%d%s"):format(rest, COPPER)
end

local function UpdateGold(frame)
	frame.text:SetText(Info.MoneyText(Plain(GetMoney()) or 0))
end

local function GoldTooltip(frame)
	local tip = Tooltip(frame)
	tip:AddLine("Gold on your characters", 1, 1, 1)
	local total = 0
	for _, char in ipairs(StzxUI:Characters()) do
		total = total + char.money
		tip:AddDoubleLine(ClassCode(char.class) .. char.name .. "|r", Info.MoneyText(char.money), 1, 1, 1, 1, 1, 1)
	end
	tip:AddLine(" ")
	tip:AddDoubleLine("Total", Info.MoneyText(total), 1, 0.82, 0.25, 1, 1, 1)
	local now, start = Plain(GetMoney()), session.money
	if now and start and now ~= start then
		local sign = now > start and (GREEN .. "+") or (RED .. "-")
		tip:AddDoubleLine("This session", sign .. Info.MoneyText(now - start) .. "|r", 0.8, 0.8, 0.8, 1, 1, 1)
	end
	tip:Show()
end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------

local BAGS = { 0, 1, 2, 3, 4 } -- backpack and four bags (the reagent bag is counted on its own)
local REAGENT_BAG = 5

local function Slots(bag)
	local total = Plain(C_Container.GetContainerNumSlots(bag)) or 0
	if total <= 0 then return 0, 0 end
	return Plain((C_Container.GetContainerNumFreeSlots(bag))) or 0, total
end

-- Free and total slots in your bags (not the reagent bag).
function Info.BagSpace()
	local free, total = 0, 0
	for _, bag in ipairs(BAGS) do
		local f, t = Slots(bag)
		free, total = free + f, total + t
	end
	return free, total
end

function Info.BagText()
	local free = Info.BagSpace()
	local colour = (free <= 2 and RED) or (free <= 6 and YELLOW) or ""
	return ("Bags %s%d|r"):format(colour, free)
end

local function UpdateBags(frame) frame.text:SetText(Info.BagText()) end

local function BagsTooltip(frame)
	local tip = Tooltip(frame)
	local free, total = Info.BagSpace()
	tip:AddLine("Bags", 1, 1, 1)
	tip:AddDoubleLine("Free slots", ("%d of %d"):format(free, total), 0.8, 0.8, 0.8, 1, 1, 1)
	local rf, rt = Slots(REAGENT_BAG)
	if rt > 0 then tip:AddDoubleLine("Reagent bag", ("%d of %d"):format(rf, rt), 0.8, 0.8, 0.8, 1, 1, 1) end
	tip:Show()
end

---------------------------------------------------------------------------
-- Durability
---------------------------------------------------------------------------

local GEAR_SLOTS = 19

-- Each worn item's durability: { { slot, fraction }, ... }, most worn first.
function Info.Durability()
	local list = {}
	for slot = 1, GEAR_SLOTS do
		local current, max = GetInventoryItemDurability(slot)
		current, max = Plain(current), Plain(max)
		if current and max and max > 0 then list[#list + 1] = { slot, current / max } end
	end
	table.sort(list, function(a, b) return a[2] < b[2] end)
	return list
end

local function DurabilityColour(fraction)
	if fraction < 0.25 then return RED end
	if fraction < 0.5 then return YELLOW end
	return ""
end

function Info.DurabilityText()
	local worst = Info.Durability()[1]
	if not worst then return "Dur --" end
	return ("Dur %s%d%%|r"):format(DurabilityColour(worst[2]), math.floor(worst[2] * 100))
end

local function UpdateDurability(frame) frame.text:SetText(Info.DurabilityText()) end

local function DurabilityTooltip(frame)
	local tip = Tooltip(frame)
	tip:AddLine("Durability", 1, 1, 1)
	local any = false
	for _, item in ipairs(Info.Durability()) do
		if item[2] < 1 then
			any = true
			local link = Plain(GetInventoryItemLink("player", item[1])) or ("Slot " .. item[1])
			tip:AddDoubleLine(link, DurabilityColour(item[2]) .. math.floor(item[2] * 100) .. "%|r", 1, 1, 1, 1, 1, 1)
		end
	end
	if not any then tip:AddLine("Everything is fully repaired.", 0.8, 0.8, 0.8) end
	tip:Show()
end

---------------------------------------------------------------------------
-- Layer
---------------------------------------------------------------------------
-- Busy zones are split into copies ("layers"). The game doesn't say which
-- one you're on, but every creature's ID carries a number for it (the 5th
-- part of "Creature-0-server-instance-ZONE-npc-spawn"); layer addons read
-- the same. StzxUI shows that number from the creatures around you, so you
-- can see when it changes. Not in dungeons. It can't switch layers.

local layer = { id = nil, from = nil, at = nil, previous = nil }

-- The layer number in a creature's ID, or nil (also used by the tests).
function Info.LayerFromGUID(guid)
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, zone = strsplit("-", guid)
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(zone)
end

local function ReadLayer()
	if IsInInstance and Plain((IsInInstance())) then return end
	local units = { "target", "mouseover" }
	-- A few nameplates too (their units are named nameplate1, nameplate2...).
	for i = 1, 40 do
		if #units >= 8 then break end
		local unit = "nameplate" .. i
		if Plain(UnitExists(unit)) then units[#units + 1] = unit end
	end
	for _, unit in ipairs(units) do
		local id = Info.LayerFromGUID(Plain(UnitGUID(unit)))
		if id then
			if layer.id and layer.id ~= id then layer.previous = layer.id end
			layer.id, layer.from, layer.at = id, Plain(UnitName(unit)), GetTime()
			return
		end
	end
end

local function UpdateLayer(frame)
	ReadLayer()
	if IsInInstance and Plain((IsInInstance())) then
		frame.text:SetText("Layer: instance")
	elseif layer.id then
		frame.text:SetText(("Layer %d"):format(layer.id))
	else
		frame.text:SetText("Layer --")
	end
end

local function LayerTooltip(frame)
	local tip = Tooltip(frame)
	tip:AddLine("Layer", 1, 1, 1)
	if layer.id then
		tip:AddDoubleLine("Layer number", tostring(layer.id), 0.8, 0.8, 0.8, 1, 1, 1)
		if layer.from then
			tip:AddDoubleLine("Read from", ("%s, %s ago"):format(layer.from, Duration(math.max(1, GetTime() - layer.at))),
				0.8, 0.8, 0.8, 1, 1, 1)
		end
		if layer.previous then tip:AddDoubleLine("Before that", tostring(layer.previous), 0.8, 0.8, 0.8, 1, 1, 1) end
	else
		tip:AddLine("Target or mouse over a creature to read it.", 0.8, 0.8, 0.8)
	end
	tip:AddLine(" ")
	tip:AddLine("The number changes when you move to another layer.", 0.6, 0.6, 0.6)
	tip:Show()
end

local function ResetLayer() layer.id, layer.from, layer.at, layer.previous = nil, nil, nil, nil end
Info.ResetLayer = ResetLayer

---------------------------------------------------------------------------
-- The readouts
---------------------------------------------------------------------------
-- Bar order, left to right within each side. width: room in the bar per point
-- of text size (fixed, so neighbours don't shuffle as numbers change). free:
-- the box on its own at text size 10. every: seconds between updates.

local READOUTS = {
	{ id = "levelling", frameName = "StzxUIInfoLevelling", mover = "InfoLevelling", label = "Info: levelling",
		show = "showXP", place = "barXP", width = 18, free = 240, every = 5, update = UpdateXP, tooltip = LevellingTooltip,
		available = function() return Info.XPText() ~= nil end },
	{ id = "hearth", frameName = "StzxUIInfoHearth", mover = "InfoHearth", label = "Info: hearthstone",
		show = "showHearth", place = "barHearth", width = 11, free = 170, every = 5, update = UpdateHearth,
		tooltip = HearthTooltip, events = { "HEARTHSTONE_BOUND", "BAG_UPDATE_COOLDOWN" } },
	{ id = "coords", frameName = "StzxUIInfoCoords", mover = "InfoCoords", label = "Info: coordinates",
		show = "showCoords", place = "barCoords", width = 6.5, free = 170, every = 0.2, update = UpdateCoords },
	{ id = "layer", frameName = "StzxUIInfoLayer", mover = "InfoLayer", label = "Info: layer",
		show = "showLayer", place = "barLayer", width = 6, free = 110, every = 5, update = UpdateLayer,
		tooltip = LayerTooltip, events = { "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" } },
	{ id = "gold", frameName = "StzxUIInfoGold", mover = "InfoGold", label = "Info: gold",
		show = "showGold", place = "barGold", width = 8.5, free = 170, update = UpdateGold,
		tooltip = GoldTooltip, events = { "PLAYER_MONEY" } },
	{ id = "bags", frameName = "StzxUIInfoBags", mover = "InfoBags", label = "Info: bag space",
		show = "showBags", place = "barBags", width = 4.5, free = 100, update = UpdateBags,
		tooltip = BagsTooltip, events = { "BAG_UPDATE_DELAYED" } },
	{ id = "durability", frameName = "StzxUIInfoDurability", mover = "InfoDurability", label = "Info: durability",
		show = "showDurability", place = "barDurability", width = 5, free = 100, update = UpdateDurability,
		tooltip = DurabilityTooltip, events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" } },
	{ id = "stats", frameName = "StzxUIInfoStats", mover = "InfoStats", label = "Info: stats",
		show = "showStats", place = "barStats", width = function() return Info.db.statsClock and 12.5 or 8 end,
		free = 170, every = 1, update = UpdateStats, tooltip = StatsTooltip },
}
Info.READOUTS = READOUTS

local bar, xpBar
local tickers = {}

local function Width(def, size)
	local w = type(def.width) == "function" and def.width() or def.width
	return w * size
end

local function IsOn(def)
	return Info.db[def.show] and (not def.available or def.available())
end

local function MakeReadout(def)
	local frame = CreateFrame("Frame", def.frameName, UIParent)
	frame.key = def.mover
	frame:SetFrameStrata("LOW")
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT")
	text:SetPoint("RIGHT")
	text:SetShadowOffset(1, -1)
	text:SetWordWrap(false)
	frame.text = text
	if def.tooltip then
		frame:EnableMouse(true)
		frame:SetScript("OnEnter", def.tooltip)
		frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	if def.click then
		frame:EnableMouse(true)
		frame:SetScript("OnMouseUp", def.click)
	end
	def.frame = frame
	return frame
end

---------------------------------------------------------------------------
-- The info bar
---------------------------------------------------------------------------

local function BarHeight() return Info.db.textSize + 12 end

local function BarWidth()
	return math.floor(UIParent:GetWidth() * Info.db.barLength / 100 + 0.5)
end

local function BuildBar()
	bar = CreateFrame("Frame", "StzxUIInfoBar", UIParent)
	bar:SetFrameStrata("BACKGROUND")
	local fill = bar:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(0.05, 0.05, 0.06, 0.85)
	-- Accent line along the bottom; the ends get one too when the bar is shorter
	-- than the screen.
	local function Line(p1, p2, horizontal)
		local line = bar:CreateTexture(nil, "BORDER")
		line:SetPoint(p1)
		line:SetPoint(p2)
		if horizontal then line:SetHeight(1) else line:SetWidth(1) end
		line:SetColorTexture(A.r, A.g, A.b, 1)
		return line
	end
	bar.bottom = Line("BOTTOMLEFT", "BOTTOMRIGHT", true)
	bar.ends = { Line("TOPLEFT", "BOTTOMLEFT", false), Line("TOPRIGHT", "BOTTOMRIGHT", false) }
	bar:SetSize(BarWidth(), BarHeight())

	-- The XP bar: a thin strip just under the info bar, rested XP lighter behind it.
	xpBar = CreateFrame("StatusBar", "StzxUIInfoXPBar", bar)
	xpBar:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
	xpBar:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	xpBar:SetHeight(3)
	xpBar:SetStatusBarTexture(FLAT)
	xpBar:SetStatusBarColor(A.r, A.g, A.b, 1)
	local back = xpBar:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.7)
	xpBar.rested = CreateFrame("StatusBar", nil, xpBar)
	xpBar.rested:SetAllPoints()
	xpBar.rested:SetFrameLevel(math.max(0, xpBar:GetFrameLevel() - 1))
	xpBar.rested:SetStatusBarTexture(FLAT)
	xpBar.rested:SetStatusBarColor(A.r, A.g, A.b, 0.35)
end

local function UpdateXPBar()
	local db = Info.db
	local xp, max = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
	local show = db.topBar and db.xpBar and Info.XPText() ~= nil and xp and max and max > 0
	xpBar:SetShown(show and true or false)
	if not show then return end
	local rested = (GetXPExhaustion and Plain(GetXPExhaustion())) or 0
	xpBar:SetMinMaxValues(0, max)
	xpBar:SetValue(xp)
	xpBar.rested:SetMinMaxValues(0, max)
	xpBar.rested:SetValue(math.min(max, xp + rested))
end
Info.UpdateXPBar = UpdateXPBar

-- Put the readouts in the bar, or back in their own boxes.
local function PlaceReadouts()
	local db = Info.db
	local size = db.textSize
	for _, def in ipairs(READOUTS) do def.frame.text:SetFont(FONT, size, "") end
	if not db.topBar then
		local s = size / 10
		for _, def in ipairs(READOUTS) do
			local frame = def.frame
			local w, h = def.free * s, FREE_HEIGHT * s
			frame:SetSize(w, h)
			frame.text:SetJustifyH("CENTER")
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", StzxUI.movers[def.mover], "TOPLEFT")
			StzxUI:SetMoverSize(def.mover, w, h)
		end
		bar:Hide()
		return
	end
	bar:SetSize(BarWidth(), BarHeight())
	StzxUI:SetMoverSize("InfoBar", BarWidth(), BarHeight())
	for _, edge in ipairs(bar.ends) do edge:SetShown(db.barLength < 100) end
	bar:Show()
	local gap, edge = math.floor(size * 1.5), 10
	local sides = { LEFT = {}, CENTER = {}, RIGHT = {} }
	for _, def in ipairs(READOUTS) do
		if IsOn(def) then table.insert(sides[db[def.place]] or sides.CENTER, def) end
	end
	-- Left side: from the bar's left edge rightwards.
	local x = edge
	for _, def in ipairs(sides.LEFT) do
		local frame = def.frame
		frame:SetSize(Width(def, size), BarHeight())
		frame.text:SetJustifyH("LEFT")
		frame:ClearAllPoints()
		frame:SetPoint("LEFT", bar, "LEFT", x, 0)
		x = x + frame:GetWidth() + gap
	end
	-- Right side: from the bar's right edge leftwards (last in the list is rightmost).
	x = -edge
	for i = #sides.RIGHT, 1, -1 do
		local frame = sides.RIGHT[i].frame
		frame:SetSize(Width(sides.RIGHT[i], size), BarHeight())
		frame.text:SetJustifyH("RIGHT")
		frame:ClearAllPoints()
		frame:SetPoint("RIGHT", bar, "RIGHT", x, 0)
		x = x - frame:GetWidth() - gap
	end
	-- Centre: a row centred on the bar.
	local total = 0
	for _, def in ipairs(sides.CENTER) do total = total + Width(def, size) end
	total = total + gap * math.max(0, #sides.CENTER - 1)
	x = -total / 2
	for _, def in ipairs(sides.CENTER) do
		local frame = def.frame
		frame:SetSize(Width(def, size), BarHeight())
		frame.text:SetJustifyH("CENTER")
		frame:ClearAllPoints()
		frame:SetPoint("LEFT", bar, "CENTER", x, 0)
		x = x + frame:GetWidth() + gap
	end
	UpdateXPBar()
end

local function Refresh()
	if not bar then return end -- not built yet
	local db = Info.db
	for _, def in ipairs(READOUTS) do def.frame:SetShown(db[def.show] and true or false) end
	PlaceReadouts()
	for _, ticker in pairs(tickers) do ticker:Cancel() end
	wipe(tickers)
	for _, def in ipairs(READOUTS) do
		if db[def.show] then
			def.update(def.frame)
			if def.every then
				tickers[def.id] = C_Timer.NewTicker(def.every, function() def.update(def.frame) end)
			end
		end
	end
	UpdateXPBar()
end
Info.Refresh = Refresh

local SIDES = { { "LEFT", "Left" }, { "CENTER", "Centre" }, { "RIGHT", "Right" } }

function Info:OnInitialize()
	local page = StzxUI:AddSettingsPage("Info")
	StzxUI:AddHeader(page, "Info bar", "A bar across the top of the screen that holds the readouts below.")
	StzxUI:AddCheckbox(page, self, "topBar", "Show the info bar",
		"Off: each readout sits on its own; place them in move mode.", Refresh)
	StzxUI:AddSlider(page, self, "barLength", "Bar length",
		"How much of the screen's width it covers. Move the bar itself in move mode.", 30, 100, 5,
		function(value) return ("%d%%"):format(value) end, Refresh)
	StzxUI:AddSlider(page, self, "textSize", "Text size",
		"All the readouts, in the bar or on their own.", 9, 24, 1, nil, Refresh)
	StzxUI:AddHeader(page, "Levelling")
	StzxUI:AddCheckbox(page, self, "showXP", "Show levelling pace",
		"Level and progress, XP per hour this session and the time to the next level at that pace. "
		.. "Hidden at max level. /stzx xp starts the count again.", Refresh)
	StzxUI:AddDropdown(page, self, "barXP", "Place in the bar", nil, SIDES, Refresh)
	StzxUI:AddCheckbox(page, self, "xpBar", "XP bar along the info bar",
		"A thin experience bar just under the info bar, rested XP shown lighter. Hidden at max level.", Refresh)
	StzxUI:AddHeader(page, "Hearthstone")
	StzxUI:AddCheckbox(page, self, "showHearth", "Show your hearthstone",
		"Where it's set, or how long until it's ready (or Astral Recall's, for shamans). Hover for every travel "
		.. "option this character has: hearthstone, Astral Recall, Teleport: Moonglade, mage teleports and portals, "
		.. "engineering teleporters.", Refresh)
	StzxUI:AddCheckbox(page, self, "travelMenu", "Click it for a travel menu",
		"A small menu of this character's travel options; click one to cast it or use the item. Out of combat only.")
	StzxUI:AddDropdown(page, self, "barHearth", "Place in the bar", nil, SIDES, Refresh)
	StzxUI:AddHeader(page, "Coordinates")
	StzxUI:AddCheckbox(page, self, "showCoords", "Show map coordinates",
		"Your position on the current map. The game hides it in dungeons and raids.", Refresh)
	StzxUI:AddDropdown(page, self, "barCoords", "Place in the bar", nil, SIDES, Refresh)
	StzxUI:AddHeader(page, "Gold")
	StzxUI:AddCheckbox(page, self, "showGold", "Show your gold",
		"Hover it for every character's gold, the total and this session's change.", Refresh)
	StzxUI:AddDropdown(page, self, "barGold", "Place in the bar", nil, SIDES, Refresh)
	StzxUI:AddHeader(page, "Bags")
	StzxUI:AddCheckbox(page, self, "showBags", "Show free bag slots",
		"Yellow at 6 or fewer, red at 2 or fewer. Hover for the reagent bag.", Refresh)
	StzxUI:AddDropdown(page, self, "barBags", "Place in the bar", nil, SIDES, Refresh)
	StzxUI:AddHeader(page, "Durability")
	StzxUI:AddCheckbox(page, self, "showDurability", "Show durability",
		"Your most worn item: yellow under 50%, red under 25%. Hover for each worn item.", Refresh)
	StzxUI:AddDropdown(page, self, "barDurability", "Place in the bar", nil, SIDES, Refresh)
	StzxUI:AddHeader(page, "Layer")
	StzxUI:AddCheckbox(page, self, "showLayer", "Show which layer you're on",
		"Busy zones are split into copies (layers). Read from the creatures around you (target or mouse over one); "
		.. "the number changes when you move to another layer. Showing only: it can't switch layers.", Refresh)
	StzxUI:AddDropdown(page, self, "barLayer", "Place in the bar", nil, SIDES, Refresh)
	StzxUI:AddHeader(page, "Stats")
	StzxUI:AddCheckbox(page, self, "showStats", "Show FPS and latency",
		"Frame rate and the higher of your home/world latency.", Refresh)
	StzxUI:AddCheckbox(page, self, "statsClock", "Add the clock",
		"Shows your computer's time after the latency.", Refresh)
	StzxUI:AddCheckbox(page, self, "clock24", "24-hour clock",
		"Off: 2:05 PM. On: 14:05.", Refresh)
	StzxUI:AddCheckbox(page, self, "memoryTooltip", "Addon memory in its tooltip",
		"Hover the stats to see which addons use the most memory (not checked during fights).")
	StzxUI:AddDropdown(page, self, "barStats", "Place in the bar", nil, SIDES, Refresh)
	StzxUI:AddButton(page, "Place these on screen", "Move mode",
		function() StzxUI:EnterMoveMode() end, "Opens StzxUI move mode.")
end

function Info:OnEnable()
	local db = self.db
	BuildBar()
	StzxUI:RegisterMover("InfoBar", bar, {
		label = "Info bar",
		category = "Info",
		default = { "TOP", "TOP", 0, 0 },
		anchor = "TOP",
		scalable = false, -- its size comes from the length and text size settings
		isShown = function() return db.topBar end,
	})
	-- Each readout on its own (info bar off): stacked down the top right at first.
	-- Text size sizes them, so no mouse-wheel scaling on top of it.
	local s = db.textSize / 10
	local byEvent = {}
	for i, def in ipairs(READOUTS) do
		local frame = MakeReadout(def)
		frame:SetSize(def.free * s, FREE_HEIGHT * s)
		local order = ({ stats = 0, coords = 1, levelling = 2 })[def.id] or (i + 2) -- older ones keep their spots
		StzxUI:RegisterMover(def.mover, frame, {
			label = def.label,
			category = "Info",
			default = { "TOPRIGHT", "TOPRIGHT", -200, -8 - 20 * order },
			scalable = false,
			isShown = function() return IsOn(def) and not db.topBar end,
		})
		for _, event in ipairs(def.events or {}) do
			byEvent[event] = byEvent[event] or {}
			table.insert(byEvent[event], def)
		end
	end
	Info.ResetXP()
	session.money = Plain(GetMoney())
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_XP_UPDATE")
	events:RegisterEvent("PLAYER_LEVEL_UP")
	events:RegisterEvent("UPDATE_EXHAUSTION")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("DISPLAY_SIZE_CHANGED")
	events:RegisterEvent("UI_SCALE_CHANGED")
	events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	for event in pairs(byEvent) do events:RegisterEvent(event) end
	events:SetScript("OnEvent", function(_, event)
		if byEvent[event] then
			for _, def in ipairs(byEvent[event]) do
				if db[def.show] then def.update(def.frame) end
			end
			return
		end
		if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
			PlaceReadouts() -- the screen's width changed: the bar follows
			return
		end
		if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
			ResetLayer() -- a new zone (or a loading screen): read the layer afresh
			if event == "PLAYER_ENTERING_WORLD" then Refresh() end
			return
		end
		CountXP()
		if db.showXP then UpdateXP(READOUTS[1].frame) end
		UpdateXPBar()
		if event == "PLAYER_LEVEL_UP" then PlaceReadouts() end -- max level hides levelling
	end)
	Refresh()
end

StzxUI.slashCommands.xp = {
	help = "start the XP-per-hour count again",
	run = function()
		Info.ResetXP()
		StzxUI:Say("levelling pace counts from now.")
	end,
}

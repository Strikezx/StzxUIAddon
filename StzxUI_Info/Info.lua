-- StzxUI Info
-- Small text readouts, each movable in move mode:
--   Stats        "60 fps  42 ms  14:05"
--   Coordinates  "45.2, 67.8" (blank where the game hides your position, e.g. dungeons)
--   Levelling    "Lv 18  45%  12.3k xp/h  1h 05m" (XP per hour this session and the
--                time to the next level at that pace; hidden at max level)
-- The first pieces of DaylightUI-style "info panel" in StzxUI.

local ADDON_NAME = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local Info = StzxUI:NewModule("Info", ADDON_NAME, {
	showStats = true,
	statsClock = true,   -- add the time to the stats text
	clock24 = true,      -- 24-hour clock
	showCoords = true,
	showXP = true,
}, {
	title = "Info",
	description = "Small movable readouts: FPS, latency and clock; map coordinates; levelling pace.",
})

local WIDTH, HEIGHT = 170, 20

local function MakeReadout(name, width)
	local frame = CreateFrame("Frame", name, UIParent)
	frame:SetSize(width or WIDTH, HEIGHT)
	frame:SetFrameStrata("LOW")
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER")
	text:SetShadowOffset(1, -1)
	frame.text = text
	return frame
end

---------------------------------------------------------------------------
-- Stats: FPS, latency, clock
---------------------------------------------------------------------------

local function LatencyColor(ms)
	if ms < 100 then return "|cff7fdf7f" end -- green
	if ms < 250 then return "|cffffd166" end -- yellow
	return "|cffff6b6b"                      -- red
end

local function UpdateStats(frame, db)
	local fps = math.floor((GetFramerate() or 0) + 0.5)
	local _, _, home, world = GetNetStats()
	local ms = math.max(home or 0, world or 0)
	local text = ("%d fps  %s%d ms|r"):format(fps, LatencyColor(ms), ms)
	if db.statsClock then
		text = text .. "  " .. date(db.clock24 and "%H:%M" or "%I:%M %p"):gsub("^0", "")
	end
	frame.text:SetText(text)
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
-- Levelling pace
---------------------------------------------------------------------------

-- This session's XP, counted from each gain (a level-up wraps the bar).
local session = { start = nil, gained = 0, lastXP = nil, lastMax = nil }

local function MaxLevel()
	return (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or 60
end

function Info.ResetXP()
	session.start, session.gained = GetTime(), 0
	session.lastXP, session.lastMax = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
end

local function CountXP()
	local xp, max = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
	if not (xp and max) then return end
	local last, lastMax = session.lastXP, session.lastMax
	if last then
		local gain = xp - last
		if gain < 0 and lastMax then gain = (lastMax - last) + xp end -- levelled up
		if gain > 0 then session.gained = session.gained + gain end
	end
	session.lastXP, session.lastMax = xp, max
end

local function Short(n)
	if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
	if n >= 1000 then return ("%.1fk"):format(n / 1000) end
	return tostring(math.floor(n))
end

local function Duration(seconds)
	if seconds >= 3600 then
		return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
	end
	return ("%dm"):format(math.max(1, math.floor(seconds / 60)))
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
	local text = Info.XPText()
	frame.text:SetText(text or "")
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local stats, coords, levelling
local statsTicker, coordsTicker, xpTicker

local function Refresh()
	if not stats then return end -- not built yet
	local db = Info.db
	stats:SetShown(db.showStats)
	coords:SetShown(db.showCoords)
	levelling:SetShown(db.showXP)

	if statsTicker then statsTicker:Cancel() statsTicker = nil end
	if coordsTicker then coordsTicker:Cancel() coordsTicker = nil end
	if xpTicker then xpTicker:Cancel() xpTicker = nil end
	if db.showXP then
		UpdateXP(levelling)
		xpTicker = C_Timer.NewTicker(5, function() UpdateXP(levelling) end)
	end
	if db.showStats then
		UpdateStats(stats, db)
		statsTicker = C_Timer.NewTicker(1, function() UpdateStats(stats, db) end)
	end
	if db.showCoords then
		UpdateCoords(coords)
		coordsTicker = C_Timer.NewTicker(0.2, function() UpdateCoords(coords) end)
	end
end

function Info:OnInitialize()
	local page = StzxUI:AddSettingsPage("Info")
	StzxUI:AddHeader(page, "Stats")
	StzxUI:AddCheckbox(page, self, "showStats", "Show FPS and latency",
		"Frame rate and the higher of your home/world latency.", Refresh)
	StzxUI:AddCheckbox(page, self, "statsClock", "Add the clock",
		"Shows your computer's time after the latency.", Refresh)
	StzxUI:AddCheckbox(page, self, "clock24", "24-hour clock",
		"Off: 2:05 PM. On: 14:05.", Refresh)
	StzxUI:AddHeader(page, "Coordinates")
	StzxUI:AddCheckbox(page, self, "showCoords", "Show map coordinates",
		"Your position on the current map. The game hides it in dungeons and raids.", Refresh)
	StzxUI:AddHeader(page, "Levelling")
	StzxUI:AddCheckbox(page, self, "showXP", "Show levelling pace",
		"Level and progress, XP per hour this session and the time to the next level at that pace. "
		.. "Hidden at max level. /stzx xp starts the count again.", Refresh)
	StzxUI:AddButton(page, "Place these on screen", "Move mode",
		function() StzxUI:EnterMoveMode() end, "Opens StzxUI move mode.")
end

function Info:OnEnable()
	local db = self.db
	stats = MakeReadout("StzxUIInfoStats")
	coords = MakeReadout("StzxUIInfoCoords")

	StzxUI:RegisterMover("InfoStats", stats, {
		label = "Info: stats",
		category = "Info",
		default = { "TOPRIGHT", "TOPRIGHT", -200, -8 },
		isShown = function() return db.showStats end,
	})
	StzxUI:RegisterMover("InfoCoords", coords, {
		label = "Info: coordinates",
		category = "Info",
		default = { "TOPRIGHT", "TOPRIGHT", -200, -28 },
		isShown = function() return db.showCoords end,
	})
	levelling = MakeReadout("StzxUIInfoLevelling", 240)
	StzxUI:RegisterMover("InfoLevelling", levelling, {
		label = "Info: levelling",
		category = "Info",
		default = { "TOPRIGHT", "TOPRIGHT", -200, -48 },
		isShown = function() return db.showXP and Info.XPText() ~= nil end,
	})
	Info.ResetXP()
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_XP_UPDATE")
	events:RegisterEvent("PLAYER_LEVEL_UP")
	events:SetScript("OnEvent", function()
		CountXP()
		if db.showXP then UpdateXP(levelling) end
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

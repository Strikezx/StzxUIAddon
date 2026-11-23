-- StzxUI Info
-- Two small text readouts, each movable in move mode:
--   Stats        "60 fps  42 ms  14:05"
--   Coordinates  "45.2, 67.8" (blank where the game hides your position, e.g. dungeons)
-- The first pieces of DaylightUI-style "info panel" in StzxUI.

local ADDON_NAME = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local Info = StzxUI:NewModule("Info", ADDON_NAME, {
	showStats = true,
	statsClock = true,   -- add the time to the stats text
	clock24 = true,      -- 24-hour clock
	showCoords = true,
}, {
	title = "Info",
	description = "Small movable readouts: FPS, latency and clock; map coordinates.",
})

local WIDTH, HEIGHT = 170, 20

local function MakeReadout(name)
	local frame = CreateFrame("Frame", name, UIParent)
	frame:SetSize(WIDTH, HEIGHT)
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
-- Module
---------------------------------------------------------------------------

local stats, coords
local statsTicker, coordsTicker

local function Refresh()
	if not stats then return end -- not built yet
	local db = Info.db
	stats:SetShown(db.showStats)
	coords:SetShown(db.showCoords)

	if statsTicker then statsTicker:Cancel() statsTicker = nil end
	if coordsTicker then coordsTicker:Cancel() coordsTicker = nil end
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
	StzxUI:AddButton(page, "Place these on screen", "Move mode",
		function() StzxUI:EnterMoveMode() end, "Opens StzxUI move mode.")
end

function Info:OnEnable()
	local db = self.db
	stats = MakeReadout("StzxUIInfoStats")
	coords = MakeReadout("StzxUIInfoCoords")

	StzxUI:RegisterMover("InfoStats", stats, {
		label = "Info: stats",
		default = { "TOPRIGHT", "TOPRIGHT", -200, -8 },
		isShown = function() return db.showStats end,
	})
	StzxUI:RegisterMover("InfoCoords", coords, {
		label = "Info: coordinates",
		default = { "TOPRIGHT", "TOPRIGHT", -200, -28 },
		isShown = function() return db.showCoords end,
	})
	Refresh()
end

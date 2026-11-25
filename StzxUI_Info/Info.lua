-- StzxUI Info
-- Small text readouts, in the info bar across the top of the screen (left,
-- centre or right, your choice for each), or each on its own in move mode:
--   Stats        "60 fps  42 ms  14:05"
--   Coordinates  "45.2, 67.8" (blank where the game hides your position, e.g. dungeons)
--   Levelling    "Lv 18  45%  12.3k xp/h  1h 05m" (XP per hour this session and the
--                time to the next level at that pace; hidden at max level)
-- One "Text size" slider sizes them all, in the bar or not.

local ADDON_NAME = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local Info = StzxUI:NewModule("Info", ADDON_NAME, {
	showStats = true,
	statsClock = true,   -- add the time to the stats text
	clock24 = true,      -- 24-hour clock
	showCoords = true,
	showXP = true,
	topBar = true,        -- readouts sit in the info bar
	barLength = 100,      -- % of the screen's width
	barStats = "RIGHT",   -- where each readout sits in the bar: LEFT, CENTER, RIGHT
	barCoords = "CENTER",
	barXP = "LEFT",
	textSize = 13,
}, {
	title = "Info",
	description = "Readouts in a bar across the top of the screen: FPS, latency and clock; map coordinates; levelling pace.",
})

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local A = StzxUI.ACCENT

-- Each readout's box at text size 10 when placed on its own; it grows with the text.
local FREE = { InfoStats = 170, InfoCoords = 170, InfoLevelling = 240 }
local FREE_HEIGHT = 20

local function MakeReadout(name, key)
	local frame = CreateFrame("Frame", name, UIParent)
	frame.key = key
	frame:SetFrameStrata("LOW")
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT")
	text:SetPoint("RIGHT")
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

local stats, coords, levelling, bar
local statsTicker, coordsTicker, xpTicker

---------------------------------------------------------------------------
-- The info bar
---------------------------------------------------------------------------

-- Room each readout needs in the bar, roughly its longest text at this size.
-- Fixed (not measured), so neighbours don't shuffle as the numbers change.
local function DockedWidth(frame, size)
	if frame == stats then return (Info.db.statsClock and 12.5 or 8) * size end
	if frame == coords then return 6.5 * size end
	return 18 * size
end

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
end

-- Readouts shown right now, in bar order (left to right within each side).
local function ShownReadouts()
	local db = Info.db
	local list = {}
	if db.showXP and Info.XPText() then list[#list + 1] = { levelling, db.barXP } end
	if db.showCoords then list[#list + 1] = { coords, db.barCoords } end
	if db.showStats then list[#list + 1] = { stats, db.barStats } end
	return list
end

-- Put the readouts in the bar, or back in their own boxes.
local function PlaceReadouts()
	local db = Info.db
	local size = db.textSize
	for _, frame in ipairs({ stats, coords, levelling }) do
		frame.text:SetFont(FONT, size, "")
	end
	if not db.topBar then
		local s = size / 10
		for _, frame in ipairs({ stats, coords, levelling }) do
			local w, h = FREE[frame.key] * s, FREE_HEIGHT * s
			frame:SetSize(w, h)
			frame.text:SetJustifyH("CENTER")
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", StzxUI.movers[frame.key], "TOPLEFT")
			StzxUI:SetMoverSize(frame.key, w, h)
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
	for _, item in ipairs(ShownReadouts()) do table.insert(sides[item[2]] or sides.CENTER, item[1]) end
	-- Left side: from the bar's left edge rightwards.
	local x = edge
	for _, frame in ipairs(sides.LEFT) do
		frame:SetSize(DockedWidth(frame, size), BarHeight())
		frame.text:SetJustifyH("LEFT")
		frame:ClearAllPoints()
		frame:SetPoint("LEFT", bar, "LEFT", x, 0)
		x = x + frame:GetWidth() + gap
	end
	-- Right side: from the bar's right edge leftwards (last in the list is rightmost).
	x = -edge
	for i = #sides.RIGHT, 1, -1 do
		local frame = sides.RIGHT[i]
		frame:SetSize(DockedWidth(frame, size), BarHeight())
		frame.text:SetJustifyH("RIGHT")
		frame:ClearAllPoints()
		frame:SetPoint("RIGHT", bar, "RIGHT", x, 0)
		x = x - frame:GetWidth() - gap
	end
	-- Centre: a row centred on the bar.
	local total = 0
	for _, frame in ipairs(sides.CENTER) do total = total + DockedWidth(frame, size) end
	total = total + gap * math.max(0, #sides.CENTER - 1)
	x = -total / 2
	for _, frame in ipairs(sides.CENTER) do
		frame:SetSize(DockedWidth(frame, size), BarHeight())
		frame.text:SetJustifyH("CENTER")
		frame:ClearAllPoints()
		frame:SetPoint("LEFT", bar, "CENTER", x, 0)
		x = x + frame:GetWidth() + gap
	end
end

local function Refresh()
	if not stats then return end -- not built yet
	local db = Info.db
	stats:SetShown(db.showStats)
	coords:SetShown(db.showCoords)
	levelling:SetShown(db.showXP)
	PlaceReadouts()

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
	StzxUI:AddHeader(page, "Stats")
	StzxUI:AddCheckbox(page, self, "showStats", "Show FPS and latency",
		"Frame rate and the higher of your home/world latency.", Refresh)
	StzxUI:AddCheckbox(page, self, "statsClock", "Add the clock",
		"Shows your computer's time after the latency.", Refresh)
	StzxUI:AddCheckbox(page, self, "clock24", "24-hour clock",
		"Off: 2:05 PM. On: 14:05.", Refresh)
	StzxUI:AddDropdown(page, self, "barStats", "Place in the bar", nil, SIDES, Refresh)
	StzxUI:AddHeader(page, "Coordinates")
	StzxUI:AddCheckbox(page, self, "showCoords", "Show map coordinates",
		"Your position on the current map. The game hides it in dungeons and raids.", Refresh)
	StzxUI:AddDropdown(page, self, "barCoords", "Place in the bar", nil, SIDES, Refresh)
	StzxUI:AddHeader(page, "Levelling")
	StzxUI:AddCheckbox(page, self, "showXP", "Show levelling pace",
		"Level and progress, XP per hour this session and the time to the next level at that pace. "
		.. "Hidden at max level. /stzx xp starts the count again.", Refresh)
	StzxUI:AddDropdown(page, self, "barXP", "Place in the bar", nil, SIDES, Refresh)
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
	-- Text size sizes the readouts, so no mouse-wheel scaling on top of it.
	local s = db.textSize / 10
	stats = MakeReadout("StzxUIInfoStats", "InfoStats")
	stats:SetSize(FREE.InfoStats * s, FREE_HEIGHT * s)
	StzxUI:RegisterMover("InfoStats", stats, {
		label = "Info: stats",
		category = "Info",
		default = { "TOPRIGHT", "TOPRIGHT", -200, -8 },
		scalable = false,
		isShown = function() return db.showStats and not db.topBar end,
	})
	coords = MakeReadout("StzxUIInfoCoords", "InfoCoords")
	coords:SetSize(FREE.InfoCoords * s, FREE_HEIGHT * s)
	StzxUI:RegisterMover("InfoCoords", coords, {
		label = "Info: coordinates",
		category = "Info",
		default = { "TOPRIGHT", "TOPRIGHT", -200, -28 },
		scalable = false,
		isShown = function() return db.showCoords and not db.topBar end,
	})
	levelling = MakeReadout("StzxUIInfoLevelling", "InfoLevelling")
	levelling:SetSize(FREE.InfoLevelling * s, FREE_HEIGHT * s)
	StzxUI:RegisterMover("InfoLevelling", levelling, {
		label = "Info: levelling",
		category = "Info",
		default = { "TOPRIGHT", "TOPRIGHT", -200, -48 },
		scalable = false,
		isShown = function() return db.showXP and not db.topBar and Info.XPText() ~= nil end,
	})
	Info.ResetXP()
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_XP_UPDATE")
	events:RegisterEvent("PLAYER_LEVEL_UP")
	events:RegisterEvent("DISPLAY_SIZE_CHANGED")
	events:RegisterEvent("UI_SCALE_CHANGED")
	events:SetScript("OnEvent", function(_, event)
		if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
			PlaceReadouts() -- the screen's width changed: the bar follows
			return
		end
		CountXP()
		if db.showXP then UpdateXP(levelling) end
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

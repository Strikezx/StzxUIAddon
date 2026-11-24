-- StzxUI Runs: the history window (/stzx runs)
--
--   Run history                                               [x]
--   Dungeon            When          Time   XP     Gold    Bosses Deaths Loot
--   The Deadmines      Nov 24 19:05  42:10  18.2k  +3g 12s  5      1      4
--   ...
--   [Newer]                  1-15 of 37                         [Older]
--
-- Hover a run to see its bosses and loot.

local _, ns = ...
local StzxUI = _G.StzxUI
local A = StzxUI.ACCENT
local Runs = ns.Runs

local ROWS, ROW_HEIGHT = 15, 20
local COLUMNS = {
	{ key = "name", title = "Dungeon", width = 170 },
	{ key = "when", title = "When", width = 95 },
	{ key = "time", title = "Time", width = 60 },
	{ key = "xp", title = "XP", width = 55 },
	{ key = "gold", title = "Gold", width = 85 },
	{ key = "bosses", title = "Bosses", width = 50 },
	{ key = "deaths", title = "Deaths", width = 50 },
	{ key = "loot", title = "Loot", width = 40 },
}
local WIDTH = 24
for _, c in ipairs(COLUMNS) do WIDTH = WIDTH + c.width end

local window
local first = 1 -- index of the top row in the history

---------------------------------------------------------------------------
-- Text for one run
---------------------------------------------------------------------------

local function Short(n)
	if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
	if n >= 1000 then return ("%.1fk"):format(n / 1000) end
	return tostring(math.floor(n))
end

-- "+3g 12s", "-45s", "0"
function Runs.Money(copper)
	if not copper or copper == 0 then return "0" end
	local sign = copper < 0 and "-" or "+"
	copper = math.abs(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if g == 0 and c > 0 then parts[#parts + 1] = c .. "c" end
	return sign .. table.concat(parts, " ")
end

function Runs.Columns(run)
	return {
		name = run.name,
		when = date("%b %d %H:%M", run.start),
		time = Runs.Clock(run.duration or 0),
		xp = run.xp > 0 and Short(run.xp) or "-",
		gold = Runs.Money(run.money),
		bosses = tostring(#run.bosses),
		deaths = tostring(run.deaths),
		loot = tostring(#run.loot),
	}
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function ShowTooltip(row)
	local run = row.run
	if not run then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(run.name, A.r, A.g, A.b)
	if run.level then GameTooltip:AddLine(("Level %d when you went in"):format(run.level), 0.8, 0.8, 0.8) end
	if #run.bosses > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Bosses", 1, 1, 1)
		for _, boss in ipairs(run.bosses) do GameTooltip:AddLine(boss, 0.8, 0.8, 0.8) end
	end
	if #run.loot > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Loot", 1, 1, 1)
		for _, link in ipairs(run.loot) do GameTooltip:AddLine(link) end
	end
	GameTooltip:Show()
end

local function Build()
	local f = CreateFrame("Frame", "StzxUIRunsWindow", UIParent)
	f:SetSize(WIDTH, 92 + ROWS * ROW_HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	table.insert(UISpecialFrames, "StzxUIRunsWindow") -- Escape closes it

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)
	local line = f:CreateTexture(nil, "BORDER")
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	line:SetHeight(2)
	line:SetColorTexture(A.r, A.g, A.b, 1)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText("Run history")
	title:SetTextColor(A.r, A.g, A.b)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	-- Column headings.
	local x = 12
	for _, c in ipairs(COLUMNS) do
		local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h:SetPoint("TOPLEFT", x, -40)
		h:SetWidth(c.width - 6)
		h:SetJustifyH("LEFT")
		h:SetText(c.title)
		x = x + c.width
	end

	f.rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, f)
		row:SetSize(WIDTH - 24, ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 12, -56 - (i - 1) * ROW_HEIGHT)
		row:EnableMouse(true)
		local shade = row:CreateTexture(nil, "BACKGROUND")
		shade:SetAllPoints()
		shade:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
		row.cells = {}
		local cx = 0
		for _, c in ipairs(COLUMNS) do
			local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			cell:SetPoint("LEFT", cx, 0)
			cell:SetWidth(c.width - 6)
			cell:SetJustifyH("LEFT")
			cell:SetWordWrap(false)
			row.cells[c.key] = cell
			cx = cx + c.width
		end
		row:SetScript("OnEnter", ShowTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.rows[i] = row
	end

	f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	f.empty:SetPoint("TOP", 0, -90)
	f.empty:SetText("No runs yet. Your next dungeon will show up here.")

	local function Page(step)
		local count = #Runs.History()
		first = math.max(1, math.min(first + step, math.max(1, count - ROWS + 1)))
		ns.RefreshWindow()
	end
	f.newer = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.newer:SetSize(80, 22)
	f.newer:SetPoint("BOTTOMLEFT", 10, 10)
	f.newer:SetText("Newer")
	f.newer:SetScript("OnClick", function() Page(-ROWS) end)
	f.older = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.older:SetSize(80, 22)
	f.older:SetPoint("BOTTOMRIGHT", -10, 10)
	f.older:SetText("Older")
	f.older:SetScript("OnClick", function() Page(ROWS) end)
	f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.count:SetPoint("BOTTOM", 0, 16)
	return f
end

function ns.RefreshWindow()
	if not (window and window:IsShown()) then return end
	local history = Runs.History()
	for i, row in ipairs(window.rows) do
		local run = history[first + i - 1]
		row.run = run
		if run then
			local text = Runs.Columns(run)
			for key, cell in pairs(row.cells) do cell:SetText(text[key]) end
			row:Show()
		else
			row:Hide()
		end
	end
	local count = #history
	window.empty:SetShown(count == 0)
	window.count:SetText(count > 0 and ("%d-%d of %d"):format(first, math.min(first + ROWS - 1, count), count) or "")
	window.newer:SetEnabled(first > 1)
	window.older:SetEnabled(first + ROWS <= count)
end

function ns.OpenWindow()
	window = window or Build()
	first = 1
	window:Show()
	ns.RefreshWindow()
end

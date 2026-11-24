-- StzxUI Runs: dungeon and raid run history
--
-- Every time you go into a dungeon or raid, StzxUI notes:
--   the place, when, how long, XP gained, gold gained (or spent), bosses
--   killed, deaths, and items you looted (green and better).
-- The run ends when you leave the instance. A /reload or a quick disconnect
-- inside carries on the same run.
--
-- Everything comes from the game's own events. Two limits on Forever:
--   * Loot and party chat are secret inside instances, so loot is read from
--     your own loot window: items you pick up yourself. Rolls you win
--     aren't counted.
--   * Kills of ordinary mobs aren't counted (that would need the combat log).
--
-- History is saved per character (StzxUIRunsDB), apart from your settings.

local ADDON_NAME, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local RESUME_WITHIN = 30 * 60 -- seconds: back in the same instance within this, same run
local MIN_QUALITY = 2         -- green and better

local Runs = StzxUI:NewModule("Runs", ADDON_NAME, {
	track = true,
	raids = true,       -- raids as well as dungeons
	showTimer = true,   -- small movable timer while inside
	keep = 50,          -- runs kept in the history
}, {
	title = "Runs",
	description = "Dungeon and raid run history: time, XP, gold, bosses, deaths and loot.",
})
ns.Runs = Runs

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

local function Data()
	StzxUIRunsDB = StzxUIRunsDB or {}
	StzxUIRunsDB.history = StzxUIRunsDB.history or {}
	return StzxUIRunsDB
end

function Runs.History() return Data().history end
function Runs.Current() return Data().current end

-- Where we are, if it's a dungeon or raid we track: name, instanceID, kind.
local function Instance()
	local inside, kind = IsInInstance()
	if not Plain(inside) then return nil end
	kind = Plain(kind)
	if kind ~= "party" and not (kind == "raid" and Runs.db.raids) then return nil end
	local name, _, _, difficulty, _, _, _, instanceID = GetInstanceInfo()
	name, instanceID = Plain(name), Plain(instanceID)
	if not (name and instanceID) then return nil end
	return name, instanceID, kind, Plain(difficulty)
end

---------------------------------------------------------------------------
-- A run
---------------------------------------------------------------------------

local function XP()
	return Plain(UnitXP("player")) or 0, Plain(UnitXPMax("player")) or 0
end

local function Start(name, instanceID, kind, difficulty)
	local xp, max = XP()
	Data().current = {
		name = name, instanceID = instanceID, kind = kind, difficulty = difficulty,
		start = time(), lastSeen = time(),
		level = Plain(UnitLevel("player")),
		xp = 0, lastXP = xp, lastMax = max,
		moneyStart = GetMoney(),
		bosses = {}, deaths = 0, loot = {},
	}
	Runs:Refresh()
end

-- Close the current run and move it into the history (newest first).
local function Finish()
	local data = Data()
	local run = data.current
	if not run then return end
	data.current = nil
	-- Ended now (we just left), or when last seen inside (logged out in there).
	local ended = run.lastSeen or time()
	if time() - ended <= 60 then ended = time() end
	run.duration = math.max(0, ended - run.start)
	run.money = (run.moneyEnd or GetMoney()) - run.moneyStart
	run.lastXP, run.lastMax, run.moneyStart, run.moneyEnd, run.lastSeen = nil, nil, nil, nil, nil
	table.insert(data.history, 1, run)
	for i = #data.history, (Runs.db.keep or 50) + 1, -1 do data.history[i] = nil end
	Runs:Refresh()
	if ns.RefreshWindow then ns.RefreshWindow() end
	return run
end
Runs.Finish = Finish

-- Called on every loading screen and at login.
function Runs:CheckZone()
	if not self.db.track then return end
	local data = Data()
	local run = data.current
	local name, instanceID, kind, difficulty = Instance()
	if run then
		local sameInstance = instanceID and run.instanceID == instanceID
		if sameInstance and time() - (run.lastSeen or 0) <= RESUME_WITHIN then
			run.lastSeen = time()
			self:Refresh()
			return -- carrying on (a /reload, a ghost run back, a quick disconnect)
		end
		Finish()
	end
	if name then Start(name, instanceID, kind, difficulty) end
end

local function CountXP(run)
	local xp, max = XP()
	local gain = xp - (run.lastXP or xp)
	if gain < 0 and run.lastMax then gain = (run.lastMax - run.lastXP) + xp end -- levelled up
	if gain > 0 then run.xp = run.xp + gain end
	run.lastXP, run.lastMax = xp, max
end

---------------------------------------------------------------------------
-- Loot from your own loot window
---------------------------------------------------------------------------

local slots = {} -- loot window slot -> item link, while it's open

local function ReadLootWindow()
	wipe(slots)
	for slot = 1, GetNumLootItems() do
		local link = Plain(GetLootSlotLink(slot))
		local _, _, _, _, quality = GetLootSlotInfo(slot)
		quality = Plain(quality)
		if link and quality and quality >= MIN_QUALITY then slots[slot] = link end
	end
end

local function Looted(slot)
	local run = Data().current
	local link = slots[slot]
	if run and link then
		table.insert(run.loot, link)
		slots[slot] = nil
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
	local run = Data().current
	if event == "PLAYER_ENTERING_WORLD" then
		Runs:CheckZone()
	elseif not run then
		return
	elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
		CountXP(run)
	elseif event == "PLAYER_MONEY" then
		run.moneyEnd = GetMoney()
	elseif event == "PLAYER_DEAD" then
		run.deaths = run.deaths + 1
	elseif event == "ENCOUNTER_END" then
		local _, name, _, _, success = ...
		name, success = Plain(name), Plain(success)
		if success == 1 and name then table.insert(run.bosses, name) end
	elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
		ReadLootWindow()
	elseif event == "LOOT_SLOT_CLEARED" then
		Looted(...)
	elseif event == "LOOT_CLOSED" then
		wipe(slots)
	end
end)

---------------------------------------------------------------------------
-- Timer readout while inside: "Deadmines  12:34  3 bosses"
---------------------------------------------------------------------------

local timer, ticker

function Runs.Clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return ("%d:%02d:%02d"):format(seconds / 3600, seconds % 3600 / 60, seconds % 60)
	end
	return ("%d:%02d"):format(seconds / 60, seconds % 60)
end

function Runs.TimerText()
	local run = Data().current
	if not run then return nil end
	local bosses = #run.bosses
	local text = ("%s  %s"):format(run.name, Runs.Clock(time() - run.start))
	if bosses > 0 then text = text .. ("  %d %s"):format(bosses, bosses == 1 and "boss" or "bosses") end
	return text
end

function Runs:Refresh()
	if not timer then return end
	local show = self.db.showTimer and Data().current ~= nil
	timer:SetShown(show)
	if ticker then ticker:Cancel() ticker = nil end
	if show then
		local function Update()
			local run = Data().current
			if run then run.lastSeen = time() end
			timer.text:SetText(Runs.TimerText() or "")
		end
		Update()
		ticker = C_Timer.NewTicker(1, Update)
	end
end

---------------------------------------------------------------------------
-- Settings, start-up, command
---------------------------------------------------------------------------

function Runs:OnInitialize()
	local page = StzxUI:AddSettingsPage("Runs")
	StzxUI:AddCheckbox(page, self, "track", "Keep a history of my dungeon runs",
		"Time, XP, gold, bosses, deaths and loot for each run. Loot counts what you pick up yourself "
		.. "(the game keeps loot rolls secret inside instances).",
		function(on) if on then self:CheckZone() end end)
	StzxUI:AddCheckbox(page, self, "raids", "Raids too", nil)
	StzxUI:AddCheckbox(page, self, "showTimer", "Show a run timer while inside",
		"A small readout you can move in move mode.", function() self:Refresh() end)
	StzxUI:AddSlider(page, self, "keep", "Runs to keep", "Older runs drop off the end.", 10, 100, 10)
	StzxUI:AddButton(page, "Run history", "Open", function() ns.OpenWindow() end,
		"Your recent runs. /stzx runs does the same.")
	StzxUI:AddButton(page, "Clear the history", "Clear", function()
		StzxUI:ShowDialog({
			title = "Clear run history",
			text = "Forget every saved run for this character?",
			accept = "Clear",
			onAccept = function()
				wipe(Runs.History())
				if ns.RefreshWindow then ns.RefreshWindow() end
				return true
			end,
		})
	end)
end

function Runs:OnEnable()
	Data()
	timer = CreateFrame("Frame", "StzxUIRunTimer", UIParent)
	timer:SetSize(240, 20)
	timer.text = timer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	timer.text:SetPoint("CENTER")
	timer.text:SetShadowOffset(1, -1)
	timer:Hide()
	StzxUI:RegisterMover("RunTimer", timer, {
		label = "Run timer",
		category = "Info",
		default = { "TOP", "TOP", 0, -100 },
		isShown = function() return self.db.showTimer end,
	})
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_MONEY",
		"PLAYER_DEAD", "ENCOUNTER_END", "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	-- Note we're still inside every 30 seconds, so a /reload carries the run on.
	C_Timer.NewTicker(30, function()
		local run = Data().current
		if run then run.lastSeen = time() end
	end)
	self:CheckZone()
end

StzxUI.slashCommands.runs = {
	help = "open your dungeon run history",
	run = function() ns.OpenWindow() end,
}

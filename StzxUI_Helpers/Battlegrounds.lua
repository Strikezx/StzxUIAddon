-- StzxUI Helpers: battleground history
--
-- When a battleground ends, StzxUI notes how you did: the battleground, win
-- or loss, your killing blows, honourable kills, deaths and honour, and how
-- long it ran. /stzx bg (or the button on the PvP page) shows each
-- battleground's win rate and averages, and your last few matches.
--
-- Forever note: the scoreboard is hidden from addons while a match is on.
-- StzxUI only reads it once the match has a winner. If the game still hides
-- your numbers then, the result (win or loss) is saved without them.
--
-- Saved for the whole account in StzxUIBattlegroundsDB, each match with the
-- character who played it.

local ADDON_NAME, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local Battlegrounds = StzxUI:NewModule("Battlegrounds", ADDON_NAME, {
	record = true,     -- note each battleground
	announce = true,   -- a chat line when one is noted
	keep = 200,        -- matches kept
}, {
	title = "Battlegrounds",
	description = "Notes how each battleground went; /stzx bg shows win rates and averages.",
})
ns.Battlegrounds = Battlegrounds

local FACTIONS = { [0] = "Horde", [1] = "Alliance" } -- the scoreboard's faction numbers

local function Data()
	StzxUIBattlegroundsDB = StzxUIBattlegroundsDB or {}
	StzxUIBattlegroundsDB.matches = StzxUIBattlegroundsDB.matches or {}
	return StzxUIBattlegroundsDB.matches
end

local recorded = false -- this match already noted
local last             -- the entry noted for this match (numbers filled in later if hidden at first)

-- Your row on the scoreboard, if the game shows it.
local function MyScore()
	local me = StzxUI:MyCharacterName()
	local first = Plain(UnitName("player"))
	for i = 1, (GetNumBattlefieldScores() or 0) do
		local info = C_PvP.GetScoreInfo(i)
		local name = info and Plain(info.name)
		if name and ((me and name == me) or (first and (name == first or name:find("^" .. first .. "[%s%-]")))) then
			return info
		end
	end
	return nil
end

-- Note the match that just ended (also used by the tests). Returns the entry.
local function FillNumbers(entry, info)
	if not info then return end
	entry.kb = Plain(info.killingBlows)
	entry.hk = Plain(info.honorableKills)
	entry.deaths = Plain(info.deaths)
	entry.honor = Plain(info.honorGained)
end

function Battlegrounds.Record()
	if recorded then
		-- Noted already; the game may show the numbers now.
		if last and not last.kb then FillNumbers(last, MyScore()) end
		return nil
	end
	local winner = Plain(GetBattlefieldWinner())
	if winner == nil then return nil end
	recorded = true
	local info = MyScore()
	local myFaction = (info and Plain(info.faction) and FACTIONS[Plain(info.faction)]) or Plain(UnitFactionGroup("player"))
	local entry = {
		map = Plain((GetInstanceInfo())) or "Battleground",
		char = StzxUI:MyCharacterName(),
		when = time(),
		won = FACTIONS[winner] ~= nil and FACTIONS[winner] == myFaction,
		draw = FACTIONS[winner] == nil,
		seconds = GetBattlefieldInstanceRunTime and math.floor((Plain(GetBattlefieldInstanceRunTime()) or 0) / 1000) or nil,
	}
	FillNumbers(entry, info)
	last = entry
	local list = Data()
	table.insert(list, entry)
	while #list > (Battlegrounds.db.keep or 200) do table.remove(list, 1) end
	if Battlegrounds.db.announce then
		local result = entry.draw and "a draw" or (entry.won and "|cff7fdf7fa win|r" or "|cffff6b6ba loss|r")
		local stats = entry.kb and (" (%d killing blows, %d deaths)"):format(entry.kb, entry.deaths or 0) or ""
		StzxUI:Say(("%s: %s%s noted. /stzx bg for your history."):format(entry.map, result, stats))
	end
	return entry
end

-- A short report: each battleground's record, then the last few matches.
function Battlegrounds.Report(char)
	local byMap, order = {}, {}
	local mine = {}
	for _, m in ipairs(Data()) do
		if not char or m.char == char then
			mine[#mine + 1] = m
			local s = byMap[m.map]
			if not s then
				s = { n = 0, wins = 0, kb = 0, hk = 0, deaths = 0, honor = 0, counted = 0 }
				byMap[m.map] = s
				order[#order + 1] = m.map
			end
			s.n = s.n + 1
			if m.won then s.wins = s.wins + 1 end
			if m.kb then
				s.counted = s.counted + 1
				s.kb, s.hk = s.kb + m.kb, s.hk + (m.hk or 0)
				s.deaths, s.honor = s.deaths + (m.deaths or 0), s.honor + (m.honor or 0)
			end
		end
	end
	if #mine == 0 then return "No battlegrounds noted yet." end
	table.sort(order)
	local lines = {}
	for _, map in ipairs(order) do
		local s = byMap[map]
		local line = ("%s: %d played, %d won (%d%%)"):format(map, s.n, s.wins, math.floor(s.wins / s.n * 100 + 0.5))
		if s.counted > 0 then
			line = line .. ("; average %.1f killing blows, %.1f deaths, %d honour"):format(s.kb / s.counted,
				s.deaths / s.counted, math.floor(s.honor / s.counted + 0.5))
		end
		lines[#lines + 1] = line
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Last matches:"
	for i = #mine, math.max(1, #mine - 4), -1 do
		local m = mine[i]
		local result = m.draw and "draw" or (m.won and "win" or "loss")
		local stats = m.kb and (", %d KB, %d HK, %d deaths"):format(m.kb, m.hk or 0, m.deaths or 0) or ""
		lines[#lines + 1] = ("%s  %s, %s%s"):format(date("%d %b %H:%M", m.when), m.map, result, stats)
	end
	return table.concat(lines, "\n")
end

function Battlegrounds.Show()
	StzxUI:ShowDialog({
		title = "Battleground history",
		text = Battlegrounds.Report(StzxUI:MyCharacterName()),
	})
end

function Battlegrounds:OnInitialize()
	local page = StzxUI:AddSettingsPage("Battlegrounds")
	StzxUI:AddCheckbox(page, self, "record", "Note how each battleground went",
		"When a match ends: the battleground, win or loss, killing blows, honourable kills, deaths, honour.")
	StzxUI:AddCheckbox(page, self, "announce", "Say in chat when one is noted", nil)
	StzxUI:AddButton(page, "This character's history", "Show", Battlegrounds.Show,
		"Win rate and averages per battleground, and your last matches. Also /stzx bg.")
end

function Battlegrounds:OnEnable()
	local events = CreateFrame("Frame")
	events:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" then
			recorded, last = false, nil -- a new match (or none)
		elseif self.db.record then
			Battlegrounds.Record()
		end
	end)
end

StzxUI.slashCommands.bg = {
	help = "your battleground history (\"/stzx bg clear\" forgets it)",
	run = function(arg)
		if arg == "clear" then
			StzxUIBattlegroundsDB = { matches = {} }
			StzxUI:Say("battleground history cleared.")
			return
		end
		Battlegrounds.Show()
	end,
}

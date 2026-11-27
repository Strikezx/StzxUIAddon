-- StzxUI.Threat: reading threat from the game
--
-- The game still tells addons about threat (unlike the combat log), but in
-- some moments it can make the answers secret, like auras. Secret answers can
-- still be shown (text, bars), never compared or sorted. Everything that
-- shows threat goes through here, so the "is it secret?" care lives in one place.

local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local Threat = {}
StzxUI.Threat = Threat

local function IsSecret(v)
	return issecretvalue and issecretvalue(v) or false
end

-- Threat colours by status (0 safe, 1 about to pull, 2 pulled, 3 tanking):
-- the game's own, or these if it has none.
local FALLBACK = { [0] = { 0.69, 0.69, 0.69 }, [1] = { 1, 1, 0.47 }, [2] = { 1, 0.6, 0 }, [3] = { 1, 0, 0 } }
function Threat.Colour(status)
	if GetThreatStatusColor then return GetThreatStatusColor(status) end
	local c = FALLBACK[status] or FALLBACK[0]
	return c[1], c[2], c[3]
end

-- `unit`'s threat on `mob`, or nil when the game says plainly that `unit`
-- isn't on its threat list. Returns { tanking, status, percent, raw, secret }:
--   percent  how close to pulling (100 = pulls); for the one tanking, how far
--            ahead of the next person, like Blizzard's own target frame
--   secret   true when the game has made these values secret right now:
--            show them, but don't compare them
function Threat.Read(unit, mob)
	if not (UnitDetailedThreatSituation and Plain(UnitExists(mob))) then return nil end
	local tanking, status, _, raw = UnitDetailedThreatSituation(unit, mob)
	local secret = IsSecret(tanking) or IsSecret(status) or IsSecret(raw)
	if not secret and status == nil then return nil end
	local percent = raw
	if not secret and tanking and UnitThreatPercentageOfLead then
		local lead = UnitThreatPercentageOfLead(unit, mob)
		if not IsSecret(lead) and lead and lead > 0 then percent = lead end
	end
	-- raw: share of the top threat (whoever has aggro sits at 100); what a meter shows.
	return { tanking = tanking, status = status, percent = percent, raw = raw, secret = secret }
end

-- Is threat secret right now for `unit` against `mob`? Two answers: the
-- state (who has aggro) and the values (the percentages). Uses the game's
-- own predicates when it has them, else looks at the values themselves.
function Threat.Secrecy(unit, mob)
	local state, values
	if C_Secrets and C_Secrets.ShouldUnitThreatStateBeSecret then
		state = Plain(C_Secrets.ShouldUnitThreatStateBeSecret(unit, mob))
	end
	if C_Secrets and C_Secrets.ShouldUnitThreatValuesBeSecret then
		values = Plain(C_Secrets.ShouldUnitThreatValuesBeSecret(unit, mob))
	end
	if state == nil or values == nil then
		local t = Threat.Read(unit, mob)
		local secret = t and t.secret or false
		if state == nil then state = secret end
		if values == nil then values = secret end
	end
	return state, values
end

---------------------------------------------------------------------------
-- The automatic check: is threat secret in fights on Forever?
---------------------------------------------------------------------------
-- A moment after a fight starts and again in the middle of it, StzxUI looks
-- at your target and notes whether threat is readable. After the fight it
-- says so in chat, the first time and whenever the answer changes. /stzx
-- threat shows the last fight's answers (and checks right now).

local CHECKS = { { at = 2, name = "start of fight" }, { at = 10, name = "mid-fight" } }
local fight = 0         -- counts fights, so a late timer from an old fight does nothing
local results = {}      -- this fight: { [name] = "readable" | "secret" }
local lastSummary       -- what was last said in chat
Threat.lastFight = nil  -- the last fight's summary (for /stzx threat)

local function Word(state, values)
	if values then return "secret" end
	if state then return "partly secret (who has aggro is hidden)" end
	return "readable"
end

-- One look at the target (also used by the tests). Returns the word, or nil
-- when there's nothing to look at.
function Threat.CheckNow()
	if not (Plain(UnitExists("target")) and Plain(UnitCanAttack("player", "target"))) then return nil end
	return Word(Threat.Secrecy("player", "target"))
end

local function Summary()
	local parts = {}
	for _, check in ipairs(CHECKS) do
		if results[check.name] then parts[#parts + 1] = check.name .. ": " .. results[check.name] end
	end
	if #parts == 0 then return nil end
	return table.concat(parts, ", ")
end

function Threat.FightStarted()
	fight = fight + 1
	results = {}
	local this = fight
	for _, check in ipairs(CHECKS) do
		C_Timer.After(check.at, function()
			if fight ~= this or not Plain(UnitAffectingCombat("player")) then return end
			results[check.name] = Threat.CheckNow()
		end)
	end
end

-- After a fight: returns what to say in chat, or nil (nothing new).
function Threat.FightEnded()
	fight = fight + 1 -- any check still waiting belongs to a fight that's over
	local summary = Summary()
	results = {}
	if not summary then return nil end
	Threat.lastFight = summary
	if summary == lastSummary then return nil end
	lastSummary = summary
	return "threat check: " .. summary .. "."
end

StzxUI.slashCommands.threat = {
	help = "is threat readable in fights? (checks now and shows the last fight)",
	run = function()
		local now = Threat.CheckNow()
		StzxUI:Say("threat right now:", now or "no enemy targeted (target one to check)")
		StzxUI:Say("last fight:", Threat.lastFight or "no fight checked yet this session")
	end,
}

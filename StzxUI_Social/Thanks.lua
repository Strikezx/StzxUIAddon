-- StzxUI Social: thanking people who buff you
-- Watches your own buffs. When a new one arrives from another player, out of
-- combat, it thanks them once (emote or whisper) and then waits before it
-- will thank that person again.
--
-- WoW: Forever notes
--  * Names have two parts ("Strikezx Kincrag"). UnitName() returns the first
--    name and the surname; whispers need both.
--  * In combat and other restricted moments, buff data is secret. We simply
--    do nothing then: no thanks in combat.

local _, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local GLOBAL_GAP = 10       -- seconds between any two thank-yous (a raid buff is not 20 emotes)
local thankedAt = {}        -- [full name] = GetTime() of the last thank-you
local lastThankAt = -math.huge

-- "Strikezx Kincrag", "Strikezx" for a unit, or nil if we can't read it.
local function Names(unit)
	local first, surname = UnitName(unit)
	first, surname = Plain(first), Plain(surname)
	if not first or first == "" then return nil end
	if surname and surname ~= "" then
		return first .. " " .. surname, first
	end
	return first, first
end

-- Should we thank whoever `unit` is?
local function IsThankable(unit, db)
	if Plain(UnitIsPlayer(unit)) ~= true then return false end      -- NPCs, pets, unknown
	if Plain(UnitIsUnit(unit, "player")) ~= false then return false end -- yourself, or unknown
	if not db.thankGroup then
		if Plain(UnitInParty(unit)) or Plain(UnitInRaid(unit)) then return false end
	end
	return true
end

local function SendThanks(unit, db)
	local fullName, firstName = Names(unit)
	if not fullName then return end

	local now = GetTime()
	if now - lastThankAt < GLOBAL_GAP then return end
	local last = thankedAt[fullName]
	if last and now - last < db.thankCooldown * 60 then return end

	local ok
	if db.thankMode == "WHISPER" then
		local message = db.thankMessage
		if type(message) ~= "string" or message == "" then message = "Thanks for the buff, %s!" end
		message = message:gsub("%%s", firstName)
		ok = pcall(C_ChatInfo.SendChatMessage, message, "WHISPER", nil, fullName)
	else
		local perform = C_ChatInfo.PerformEmote or DoEmote
		ok = pcall(perform, "THANK", fullName)
	end

	if ok then
		thankedAt[fullName] = now
		lastThankAt = now
	end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, _, _, updateInfo)
	local db = ns.Social.db
	if not db.thankEnabled or InCombatLockdown() then return end
	-- When buff data is locked away, don't even look at it.
	if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return end
	if not updateInfo or updateInfo.isFullUpdate or not updateInfo.addedAuras then return end

	for _, aura in ipairs(updateInfo.addedAuras) do
		local helpful = Plain(aura.isHelpful)
		local source = Plain(aura.sourceUnit)
		if helpful and source and IsThankable(source, db) then
			SendThanks(source, db)
			return -- one thank-you per update is plenty
		end
	end
end)

function ns.EnableThanks()
	-- Only our own buffs: the unit is always "player", so no unit checks needed.
	frame:RegisterUnitEvent("UNIT_AURA", "player")
end

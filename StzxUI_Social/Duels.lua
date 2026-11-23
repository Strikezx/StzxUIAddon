-- StzxUI Social: declining duels
-- When a duel request arrives, decline it and close the popup.
-- Uses the same calls Blizzard's own Decline button makes (CancelDuel).

local _, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local frame = CreateFrame("Frame")

local function Decline(popupName, playerName)
	CancelDuel()
	StaticPopup_Hide(popupName)
	if ns.Social.db.announceDuels then
		local who = Plain(playerName)
		StzxUI:Print(("Declined a duel from %s."):format(who or "someone"))
	end
end

frame:SetScript("OnEvent", function(_, event, playerName)
	local db = ns.Social.db
	if not db.declineDuels then return end

	if event == "DUEL_REQUESTED" then
		Decline("DUEL_REQUESTED", playerName)
	elseif event == "DUEL_TO_THE_DEATH_REQUESTED" and db.declineDeathDuels then
		Decline("DUEL_TO_THE_DEATH_REQUESTED", playerName)
	end
end)

function ns.EnableDuels()
	frame:RegisterEvent("DUEL_REQUESTED")
	frame:RegisterEvent("DUEL_TO_THE_DEATH_REQUESTED")
end

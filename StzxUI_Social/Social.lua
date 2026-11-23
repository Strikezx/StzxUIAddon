-- StzxUI Social
-- Being polite (and left alone): decline duels, thank people who buff you.
-- This file sets up the module and its settings page; Duels.lua and
-- Thanks.lua hold the two features.

local ADDON_NAME, ns = ...
local StzxUI = _G.StzxUI

local Social = StzxUI:NewModule("Social", ADDON_NAME, {
	-- Duels
	declineDuels = true,      -- decline every duel request
	declineDeathDuels = true, -- also decline duels to the death
	announceDuels = true,     -- say in chat who we declined

	-- Thanks
	thankEnabled = true,      -- thank players who buff you
	thankMode = "EMOTE",      -- "EMOTE" (/thank) or "WHISPER"
	thankMessage = "Thanks for the buff, %s!", -- %s = their name
	thankGroup = false,       -- also thank party/raid members
	thankCooldown = 5,        -- minutes before thanking the same person again
})
ns.Social = Social

function Social:OnInitialize()
	local page = StzxUI:AddSettingsPage("Social")

	StzxUI:AddCheckbox(page, self, "declineDuels", "Decline duel requests",
		"Automatically declines every duel request.")
	StzxUI:AddCheckbox(page, self, "declineDeathDuels", "Also decline duels to the death",
		"Declines duel-to-the-death requests as well.")
	StzxUI:AddCheckbox(page, self, "announceDuels", "Tell me when a duel is declined",
		"Prints who asked, so you know it happened.")

	StzxUI:AddCheckbox(page, self, "thankEnabled", "Thank players who buff me",
		"Out of combat only. Never more than once every few minutes per player.")
	StzxUI:AddDropdown(page, self, "thankMode", "How to thank",
		"An emote everyone nearby sees, or a private whisper.",
		{ { "EMOTE", "Emote (/thank)" }, { "WHISPER", "Whisper" } })
	StzxUI:AddCheckbox(page, self, "thankGroup", "Also thank my party or raid",
		"Off by default: group members rebuff each other all the time.")
	StzxUI:AddSlider(page, self, "thankCooldown", "Wait before thanking the same player",
		"Minutes before the same player is thanked again.", 1, 30, 1,
		function(value) return ("%d min"):format(value) end)
end

function Social:OnEnable()
	ns.EnableDuels()
	ns.EnableThanks()
end

-- /stzx thanks <message>  (sets the whisper text; there is no text box in
-- Blizzard's option lists, so this is the way to change it for now)
StzxUI.slashCommands.thanks = {
	help = "set the thank-you whisper, %s = their name (e.g. /stzx thanks Cheers %s!)",
	run = function(text)
		if not Social.db then return end
		if text == "" then
			StzxUI:Say("thank-you whisper is:", Social.db.thankMessage)
			return
		end
		Social.db.thankMessage = text
		StzxUI:Say("thank-you whisper set to:", text)
	end,
}

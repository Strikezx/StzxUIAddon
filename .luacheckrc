-- luacheck settings for StzxUI (WoW uses Lua 5.1)
std = "lua51"
max_line_length = false
codes = true

exclude_files = {
	".luacheckrc",
	"Libs/",
	"tests/",
}

ignore = {
	"212", -- unused argument (event handlers get many we don't need)
}

-- Globals StzxUI creates
globals = {
	"StzxUI",
	"StzxUIDB",
	"SlashCmdList",
	"SLASH_STZXUI1",
	"SLASH_STZXUI2",
}

-- Game globals StzxUI reads (add new ones here as modules grow)
read_globals = {
	-- Lua / client helpers
	"issecretvalue",
	-- Frames and events
	"CreateFrame",
	"EventUtil",
	-- Addon info
	"C_AddOns",
	-- Settings panel
	"Settings",
	"MinimalSliderWithSteppersMixin",
	-- Chat and emotes
	"C_ChatInfo",
	"DoEmote",
	-- Units and auras
	"UnitName",
	"UnitIsPlayer",
	"UnitIsUnit",
	"UnitInParty",
	"UnitInRaid",
	"C_UnitAuras",
	"C_Secrets",
	-- Combat state and time
	"InCombatLockdown",
	"IsInInstance",
	"GetTime",
	-- Duels and popups
	"CancelDuel",
	"StaticPopup_Hide",
}

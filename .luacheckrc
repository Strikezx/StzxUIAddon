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
	-- Frames, fonts, tooltips, keys
	"UIParent",
	"GameTooltip",
	"UISpecialFrames",
	"IsShiftKeyDown",
	"SettingsPanel",
	"CreateSettingsButtonInitializer",
	"CreateSettingsListSectionHeaderInitializer",
	-- Profiles and reload
	"C_EncodingUtil",
	"C_UI",
	"GetRealmName",
	-- Info module
	"C_Map",
	"C_Timer",
	"GetFramerate",
	"GetNetStats",
	"date",
	-- Unit frames
	"UnitHealth", "UnitHealthMax", "UnitHealthPercent", "CurveConstants",
	"UnitPower", "UnitPowerMax", "UnitPowerType",
	"UnitClass", "UnitReaction", "UnitIsTapDenied", "UnitLevel", "UnitClassification",
	"UnitIsGhost", "UnitIsDeadOrGhost", "UnitIsConnected", "UnitExists",
	"UnitCastingInfo", "UnitChannelInfo",
	"C_ClassColor", "CLASS_ICON_TCOORDS", "AbbreviateLargeNumbers", "STANDARD_TEXT_FONT",
	"SetPortraitTexture", "RegisterUnitWatch", "RegisterStateDriver", "EventRegistry", "GetMaxLevelForPlayerExpansion", "UnitXP", "UnitXPMax", "C_CVar", "CreateColor", "GetQuestID", "QuestFrame",
	"QuestMapFrame", "QuestMapFrame_CloseQuestDetails", "QuestMapFrame_ShowQuestDetails", "hooksecurefunc", "UnitInRange", "UnitIsGroupLeader",
	"GetRaidTargetIndex", "SetRaidTargetIconTexture", "GameTooltip_SetDefaultAnchor",
	"Enum", "C_UnitAuras",
}

-- StzxUI Unit Frames: the Party & Raid module
-- Its own section (StzxUI > Sections > Party & Raid), so it can be switched
-- off without touching the player and target frames.
-- Settings: StzxUI > Party & Raid.

local ADDON_NAME, ns = ...
local StzxUI = _G.StzxUI

local PARTY_DEFAULTS = {
	enabled = true,
	showPlayer = true,      -- yourself at the top of the party
	showSolo = false,       -- show your own frame even when not in a group
	width = 150,
	height = 36,
	powerHeight = 4,        -- 0 hides the power bar
	spacing = 6,
	growth = "DOWN",        -- "DOWN", "UP", "RIGHT", "LEFT"
	healthText = "PERCENT", -- "BOTH", "NUMBER", "PERCENT", "NONE"
	healthColour = "CLASS",
	showDebuffs = true,
	onlyDispellable = false,
	maxDebuffs = 3,
	debuffSize = 20,
	rangeFade = true,
	powerText = false,
}

local RAID_DEFAULTS = {
	enabled = true,
	width = 72,
	height = 38,
	powerHeight = 0,
	spacing = 3,
	groupsAcross = true,    -- each group is a column (false: each group is a row)
	healthText = "PERCENT",
	healthColour = "CLASS",
	showDebuffs = true,
	onlyDispellable = true,
	maxDebuffs = 2,
	debuffSize = 14,
	rangeFade = true,
	powerText = false,
}

local GroupFrames = StzxUI:NewModule("GroupFrames", ADDON_NAME, {
	hideBlizzard = true,
	party = PARTY_DEFAULTS,
	raid = RAID_DEFAULTS,
}, {
	title = "Party & Raid",
	description = "StzxUI's party and raid frames: health, debuffs, range fading and click to target.",
})

local HEALTH_TEXTS = {
	{ "PERCENT", "Percent (76%)" },
	{ "NUMBER", "Number (530)" },
	{ "BOTH", "Number and percent" },
	{ "NONE", "None" },
}
local COLOURS = { { "CLASS", "Class colour" }, { "GREEN", "Green" } }

local function Refresh() ns.RefreshGroups() end
local function NeedsReload() StzxUI:AskReload("This change takes effect after a reload.") end

---------------------------------------------------------------------------
-- Settings page
---------------------------------------------------------------------------

local function AddCommonOptions(page, owner)
	StzxUI:AddSlider(page, owner, "width", "Width", nil, 50, 300, 2, nil, Refresh)
	StzxUI:AddSlider(page, owner, "height", "Height", nil, 20, 80, 1, nil, Refresh)
	StzxUI:AddSlider(page, owner, "powerHeight", "Power bar height", "0 hides the power bar.", 0, 10, 1, nil, Refresh)
	StzxUI:AddSlider(page, owner, "spacing", "Spacing", nil, 0, 20, 1, nil, Refresh)
	StzxUI:AddDropdown(page, owner, "healthText", "Health text", nil, HEALTH_TEXTS, Refresh)
	StzxUI:AddDropdown(page, owner, "healthColour", "Health bar colour", nil, COLOURS, Refresh)
	StzxUI:AddCheckbox(page, owner, "showDebuffs", "Show debuffs", nil, Refresh)
	StzxUI:AddCheckbox(page, owner, "onlyDispellable", "Only debuffs I can remove",
		"Shows only the debuffs your class can dispel (magic, curse, poison, disease).", Refresh)
	StzxUI:AddSlider(page, owner, "maxDebuffs", "Debuffs shown", nil, 1, 6, 1, nil, Refresh)
	StzxUI:AddSlider(page, owner, "debuffSize", "Debuff size", nil, 10, 32, 1, nil, Refresh)
	StzxUI:AddCheckbox(page, owner, "rangeFade", "Fade members out of range",
		"Members too far away to heal (about 40 yards) are faded.", Refresh)
end

function GroupFrames:OnInitialize()
	local page = StzxUI:AddSettingsPage("Party & Raid")
	StzxUI:AddCheckbox(page, self, "hideBlizzard", "Hide Blizzard's party and raid frames",
		"Bringing them back needs a reload.", function(value)
			if value then self:HideBlizzard() else NeedsReload() end
		end)
	StzxUI:AddButton(page, "Place the frames", "Move mode",
		function() StzxUI:EnterMoveMode() end, "Party and raid each have a box you can drag.")

	local party = { name = "GroupParty", db = self.db.party, defaults = PARTY_DEFAULTS }
	StzxUI:AddHeader(page, "Party")
	StzxUI:AddCheckbox(page, party, "enabled", "Show StzxUI party frames", nil, NeedsReload)
	StzxUI:AddCheckbox(page, party, "showPlayer", "Include yourself", nil, Refresh)
	StzxUI:AddCheckbox(page, party, "showSolo", "Show even when not in a group",
		"Handy for setting things up. Needs a reload.", NeedsReload)
	StzxUI:AddDropdown(page, party, "growth", "Grow", "Which way new members are added.",
		{ { "DOWN", "Down" }, { "UP", "Up" }, { "RIGHT", "Right" }, { "LEFT", "Left" } }, Refresh)
	AddCommonOptions(page, party)

	local raid = { name = "GroupRaid", db = self.db.raid, defaults = RAID_DEFAULTS }
	StzxUI:AddHeader(page, "Raid")
	StzxUI:AddCheckbox(page, raid, "enabled", "Show StzxUI raid frames", nil, NeedsReload)
	StzxUI:AddCheckbox(page, raid, "groupsAcross", "Groups side by side",
		"On: each group is a column. Off: each group is a row.", Refresh)
	AddCommonOptions(page, raid)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

function GroupFrames:HideBlizzard()
	if not self.db.hideBlizzard then return end
	if self.db.party.enabled then ns.HideBlizzardFrames("party") end
	if self.db.raid.enabled then ns.HideBlizzardFrames("raid") end
end

local SPOTS = {
	party = { key = "PartyFrames", label = "Party", at = { "LEFT", "LEFT", 30, 120 } },
	raid = { key = "RaidFrames", label = "Raid", at = { "TOPLEFT", "TOPLEFT", 30, -180 } },
}

local function Build(self)
	for _, kind in ipairs({ "party", "raid" }) do
		local settings = self.db[kind]
		if settings.enabled then
			local spot = SPOTS[kind]
			-- An ordinary box the size of a full group: this is what moves.
			local area = CreateFrame("Frame", "StzxUI" .. spot.key, UIParent)
			area:SetSize(ns.GroupAreaSize(kind, settings))
			ns.CreateGroupHeader(kind, area, settings)
			StzxUI:RegisterMover(spot.key, area, {
				label = spot.label,
				category = "Group frames",
				default = spot.at,
			})
		end
	end
	ns.StartGroupEvents()
	self:HideBlizzard()
end

function GroupFrames:OnEnable()
	if InCombatLockdown() then
		local waiter = CreateFrame("Frame")
		waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
		waiter:SetScript("OnEvent", function()
			waiter:UnregisterAllEvents()
			Build(self)
		end)
		StzxUI:Say("party and raid frames will appear when combat ends.")
		return
	end
	Build(self)
end

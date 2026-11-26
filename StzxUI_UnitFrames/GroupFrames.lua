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

-- Click-casting: which spell a mouse button (with a modifier) casts on the
-- member you click. Plain left-click still targets, plain right-click opens
-- the menu. Each slot holds a spell name ("" for nothing).
local CLICK_SLOTS = {
	{ key = "shift1", label = "Shift + left-click", prefix = "shift-", button = 1 },
	{ key = "ctrl1", label = "Ctrl + left-click", prefix = "ctrl-", button = 1 },
	{ key = "alt1", label = "Alt + left-click", prefix = "alt-", button = 1 },
	{ key = "shift2", label = "Shift + right-click", prefix = "shift-", button = 2 },
	{ key = "ctrl2", label = "Ctrl + right-click", prefix = "ctrl-", button = 2 },
	{ key = "alt2", label = "Alt + right-click", prefix = "alt-", button = 2 },
	{ key = "middle", label = "Middle click", prefix = "", button = 3 },
	{ key = "button4", label = "Mouse button 4", prefix = "", button = 4 },
	{ key = "button5", label = "Mouse button 5", prefix = "", button = 5 },
}
local CLICK_DEFAULTS = {}
for _, slot in ipairs(CLICK_SLOTS) do CLICK_DEFAULTS[slot.key] = "" end
ns.CLICK_SLOTS = CLICK_SLOTS

local GroupFrames = StzxUI:NewModule("GroupFrames", ADDON_NAME, {
	hideBlizzard = true,
	party = PARTY_DEFAULTS,
	raid = RAID_DEFAULTS,
	clickCast = CLICK_DEFAULTS,
}, {
	title = "Party & Raid",
	description = "StzxUI's party and raid frames: health, debuffs, range fading, click to target and click-casting.",
})

local HEALTH_TEXTS = {
	{ "PERCENT", "Percent (76%)" },
	{ "NUMBER", "Number (530)" },
	{ "BOTH", "Number and percent" },
	{ "NONE", "None" },
}
local COLOURS = { { "CLASS", "Class colour" }, { "GREEN", "Green" } }

local function Refresh() ns.RefreshGroups() end

-- The character's helpful spells (from the spellbook), for the click-casting menus.
function ns.HelpfulSpells()
	local names, seen = {}, {}
	local book = C_SpellBook
	if book and book.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank then
		for line = 1, book.GetNumSpellBookSkillLines() do
			local info = book.GetSpellBookSkillLineInfo(line)
			if info and not info.isGuild and not info.shouldHide then
				for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
					local item = book.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
					if item and item.spellID and not item.isPassive and item.itemType == Enum.SpellBookItemType.Spell
						and C_Spell.IsSpellHelpful(item.spellID) and not seen[item.name] then
						seen[item.name] = true
						names[#names + 1] = item.name
					end
				end
			end
		end
	end
	table.sort(names)
	return names
end
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
	StzxUI:AddButton(page, "Test frames", "Show / hide",
		function() StzxUI:ToggleTestMode() end,
		"Pretend party and raid members, drawn with your current settings, so you can see and place the "
		.. "frames without a group. Also on the move mode toolbar and /stzx test. Hidden when combat starts.")

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

	ns.clickCastDB = self.db.clickCast
	local click = { name = "GroupClick", db = self.db.clickCast, defaults = CLICK_DEFAULTS }
	StzxUI:AddHeader(page, "Click-casting",
		"Pick a spell for a click and it's cast on the party or raid member you click, in fights too. "
		.. "Plain left-click still targets and plain right-click opens the menu. Spells come from your spellbook.")
	for _, slot in ipairs(CLICK_SLOTS) do
		local function Choices()
			local list = { { "", "Nothing" } }
			local current = self.db.clickCast[slot.key]
			local found = current == ""
			for _, name in ipairs(ns.HelpfulSpells()) do
				list[#list + 1] = { name, name }
				if name == current then found = true end
			end
			if not found then list[#list + 1] = { current, current } end -- a spell set on another character
			return list
		end
		StzxUI:AddDropdown(page, click, slot.key, slot.label, nil, Choices, function() ns.RefreshClickCast() end)
	end
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

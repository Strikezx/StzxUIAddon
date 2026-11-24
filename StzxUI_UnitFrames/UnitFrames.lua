-- StzxUI Unit Frames: the module
-- Player and target frames, each with its own cast bar, all movable and
-- resizable in move mode. Settings: StzxUI > Unit Frames.

local ADDON_NAME, ns = ...
local StzxUI = _G.StzxUI

local FRAME_DEFAULTS = {
	enabled = true,
	portrait = "ICON",     -- "ICON" class icon, "PORTRAIT" character portrait, "NONE",
	                       -- or "JI:<style>" with the JiberishUI Icons addon
	healthText = "BOTH",   -- "BOTH" 530 | 76%, "NUMBER", "PERCENT", "NONE"
	powerText = true,
	castBar = true,
}

local UnitFrames = StzxUI:NewModule("UnitFrames", ADDON_NAME, {
	hideBlizzard = true,   -- hide Blizzard's player and target frames
	healthColour = "CLASS", -- "CLASS" (class / reaction colour) or "GREEN"
	player = FRAME_DEFAULTS,
	target = FRAME_DEFAULTS,
}, {
	title = "Unit Frames",
	description = "StzxUI's player and target frames with cast bars.",
})
ns.module = UnitFrames

local frames, castBars = {}, {}

local PORTRAITS = {
	{ "ICON", "Class icon" },
	{ "PORTRAIT", "Character portrait" },
	{ "NONE", "None" },
}
local HEALTH_TEXTS = {
	{ "BOTH", "Number and percent (530 | 76%)" },
	{ "NUMBER", "Number (530)" },
	{ "PERCENT", "Percent (76%)" },
	{ "NONE", "None" },
}

local function RefreshAll()
	for _, frame in pairs(frames) do ns.UpdateUnitFrame(frame) end
	for _, bar in pairs(castBars) do ns.RefreshCastBar(bar) end
end

---------------------------------------------------------------------------
-- Settings page
---------------------------------------------------------------------------

local function AddFrameOptions(page, unit, title)
	-- A small "owner" so the settings helpers write into db.player / db.target.
	local owner = { name = "UnitFrames" .. title, db = UnitFrames.db[unit], defaults = FRAME_DEFAULTS }
	StzxUI:AddHeader(page, title .. " frame")
	StzxUI:AddCheckbox(page, owner, "enabled", "Show the " .. title:lower() .. " frame",
		"Turning a frame on or off applies after a reload.",
		function() StzxUI:AskReload(("The %s frame changes after a reload."):format(title:lower())) end)
	StzxUI:AddDropdown(page, owner, "portrait", "Portrait",
		"Round class icon or the character's face. With the JiberishUI Icons addon installed, its styles are listed too. NPCs always show their face.",
		function()
			local list = {}
			for _, choice in ipairs(PORTRAITS) do table.insert(list, choice) end
			for _, choice in ipairs(ns.JiberishStyles()) do table.insert(list, choice) end
			return list
		end, RefreshAll)
	StzxUI:AddDropdown(page, owner, "healthText", "Health text",
		"What the health bar shows.", HEALTH_TEXTS, RefreshAll)
	StzxUI:AddCheckbox(page, owner, "powerText", "Show power numbers",
		"Mana, rage or energy as current / maximum.", RefreshAll)
	StzxUI:AddCheckbox(page, owner, "castBar", "Show the " .. title:lower() .. " cast bar",
		"A separate bar you can move on its own in move mode.", RefreshAll)
end

function UnitFrames:OnInitialize()
	local page = StzxUI:AddSettingsPage("Unit Frames")
	StzxUI:AddHeader(page, "All frames")
	StzxUI:AddCheckbox(page, self, "hideBlizzard", "Hide Blizzard's player and target frames",
		"Hides the game's own frames where StzxUI shows its own. Bringing them back needs a reload.",
		function(value)
			if not value then StzxUI:AskReload("Blizzard's frames come back after a reload.") end
			if value then UnitFrames:HideBlizzard() end
		end)
	StzxUI:AddDropdown(page, self, "healthColour", "Health bar colour",
		"Class colour for players and friendly/neutral/hostile colours for others, or always green.",
		{ { "CLASS", "Class and reaction" }, { "GREEN", "Green" } }, RefreshAll)
	StzxUI:AddButton(page, "Place the frames", "Move mode",
		function() StzxUI:EnterMoveMode() end, "Drag, resize (mouse wheel) and line up the frames.")
	AddFrameOptions(page, "player", "Player")
	AddFrameOptions(page, "target", "Target")
end

---------------------------------------------------------------------------
-- Building the frames
---------------------------------------------------------------------------

function UnitFrames:HideBlizzard()
	if not self.db.hideBlizzard then return end
	for _, unit in ipairs({ "player", "target" }) do
		if self.db[unit].enabled then ns.HideBlizzardFrames(unit) end
	end
end

-- Default spots: player left of centre, target mirrored on the right,
-- cast bars just under each frame.
local DEFAULTS = {
	player = { "CENTER", "CENTER", -300, -150 },
	target = { "CENTER", "CENTER", 300, -150 },
	playerCast = { "CENTER", "CENTER", -300, -200 },
	targetCast = { "CENTER", "CENTER", 300, -200 },
}

local function Build(self)
	local db = self.db
	local specs = {
		{ unit = "player", name = "StzxUIPlayerFrame", side = "LEFT", title = "Player" },
		{ unit = "target", name = "StzxUITargetFrame", side = "RIGHT", title = "Target" },
	}
	for _, spec in ipairs(specs) do
		local settings = db[spec.unit]
		if settings.enabled then
			local frame = ns.CreateUnitFrame(spec.unit, spec.name, spec.side, settings)
			frames[spec.unit] = frame
			StzxUI:RegisterMover(spec.title .. "Frame", frame, {
				label = spec.title,
				category = "Unit frames",
				default = DEFAULTS[spec.unit],
			})

			local bar = ns.CreateCastBar(spec.unit, spec.name .. "CastBar", function() return settings.castBar end)
			castBars[spec.unit] = bar
			StzxUI:RegisterMover(spec.title .. "CastBar", bar, {
				label = spec.title .. " cast bar",
				category = "Unit frames",
				default = DEFAULTS[spec.unit .. "Cast"],
				isShown = function() return settings.castBar end,
			})
		end
	end
	self:HideBlizzard()
	RefreshAll()
end

function UnitFrames:OnEnable()
	-- Secure frames can't be set up in combat (e.g. a /reload mid-fight):
	-- wait for combat to end.
	if InCombatLockdown() then
		local waiter = CreateFrame("Frame")
		waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
		waiter:SetScript("OnEvent", function()
			waiter:UnregisterAllEvents()
			Build(self)
		end)
		StzxUI:Say("unit frames will appear when combat ends.")
		return
	end
	Build(self)
end

-- For tests and other modules.
ns.frames, ns.castBars = frames, castBars
UnitFrames.frames, UnitFrames.castBars = frames, castBars

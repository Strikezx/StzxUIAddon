-- StzxUI Unit Frames: the module
-- Player, target and focus frames (each with its own cast bar), plus small
-- target-of-target and pet frames. All movable and resizable in move mode.
-- Settings: StzxUI > Unit Frames.

local ADDON_NAME, ns = ...
local StzxUI = _G.StzxUI

local FRAME_DEFAULTS = {
	enabled = true,
	portrait = "ICON",     -- "ICON" class icon, "PORTRAIT" character portrait, "NONE",
	                       -- or "JI:<style>" with the JiberishUI Icons addon
	healthText = "BOTH",   -- "BOTH" 530 | 76%, "NUMBER", "PERCENT", "NONE"
	powerText = true,
	castBar = true,
	showBuffs = true,
	showDebuffs = true,
	onlyMine = false,       -- target: only debuffs you cast
	auraSize = 24,
	auraSpacing = 1,        -- pixels between icons
	auraPosition = "ABOVE", -- "ABOVE" or "BELOW" the frame
	width = 230,            -- the frame's length (Style.WIDTH)
	threat = true,          -- target and focus: your threat % in a small coloured box
}

-- The small frames start simpler: no portrait, percent only, no auras.
local SMALL_DEFAULTS = {
	enabled = true,
	portrait = "NONE",
	healthText = "PERCENT",
	powerText = false,
	castBar = false,
	showBuffs = false,
	showDebuffs = false,
	onlyMine = false,
	auraSize = 20,
	auraSpacing = 1,
	auraPosition = "ABOVE",
	width = 130,
}

-- Every frame StzxUI can show. `small` frames use the compact size and
-- have no cast bar; `cast` frames get their own movable cast bar.
local SPECS = {
	{ unit = "player", key = "Player", title = "Player", side = "LEFT", cast = true,
		at = { -300, -150 }, castAt = { -300, -200 } },
	{ unit = "target", key = "Target", title = "Target", side = "RIGHT", cast = true,
		at = { 300, -150 }, castAt = { 300, -200 } },
	{ unit = "focus", key = "Focus", title = "Focus", side = "RIGHT", cast = true,
		at = { 520, 20 }, castAt = { 520, -30 } },
	{ unit = "targettarget", key = "TargetTarget", title = "Target of target", side = "RIGHT", small = true,
		at = { 510, -150 } },
	{ unit = "pet", key = "Pet", title = "Pet", side = "LEFT", small = true,
		at = { -510, -150 } },
}

local UnitFrames = StzxUI:NewModule("UnitFrames", ADDON_NAME, {
	hideBlizzard = true,   -- hide Blizzard's frames where StzxUI shows its own
	healthColour = "CLASS", -- "CLASS" (class / reaction colour) or "GREEN"
	player = FRAME_DEFAULTS,
	target = FRAME_DEFAULTS,
	focus = FRAME_DEFAULTS,
	targettarget = SMALL_DEFAULTS,
	pet = SMALL_DEFAULTS,
}, {
	title = "Unit Frames",
	description = "StzxUI's player, target, focus, target-of-target and pet frames, with cast bars.",
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

-- A frame's length from its setting (out of combat; otherwise after it).
local widthWaiter
function ns.ApplyWidth(unit, width)
	local frame = frames[unit]
	if not frame then return end
	if ns.SetFrameWidth(frame, width) then
		local spec
		for _, s in ipairs(SPECS) do if s.unit == unit then spec = s end end
		StzxUI:SetMoverSize(spec.key .. "Frame", width, frame:GetHeight())
		return
	end
	widthWaiter = widthWaiter or CreateFrame("Frame")
	widthWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
	widthWaiter:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents()
		for _, s in ipairs(SPECS) do
			if frames[s.unit] then ns.ApplyWidth(s.unit, UnitFrames.db[s.unit].width) end
		end
	end)
end

local function RefreshAll()
	for _, frame in pairs(frames) do ns.UpdateUnitFrame(frame) end
	for _, bar in pairs(castBars) do ns.RefreshCastBar(bar) end
end

---------------------------------------------------------------------------
-- Settings page
---------------------------------------------------------------------------

local function AddFrameOptions(page, spec)
	local unit, title = spec.unit, spec.title
	-- A small "owner" so the settings helpers write into db.player / db.target ...
	local owner = { name = "UnitFrames" .. spec.key, db = UnitFrames.db[unit],
		defaults = spec.small and SMALL_DEFAULTS or FRAME_DEFAULTS }
	StzxUI:AddHeader(page, title .. " frame")
	StzxUI:AddCheckbox(page, owner, "enabled", "Show the " .. title:lower() .. " frame",
		"Turning a frame on or off applies after a reload.",
		function() StzxUI:AskReload(("The %s frame changes after a reload."):format(title:lower())) end)
	StzxUI:AddSlider(page, owner, "width", "Length",
		"How wide the frame is. In move mode, Ctrl + mouse wheel does the same. (Not in combat.)",
		spec.small and 80 or 140, spec.small and 240 or 400, 5, function(value) return ("%d px"):format(value) end,
		function(value) ns.ApplyWidth(unit, value) end)
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
	if spec.cast then
		StzxUI:AddCheckbox(page, owner, "castBar", "Show the " .. title:lower() .. " cast bar",
			"A separate bar you can move on its own in move mode.", RefreshAll)
	end
	StzxUI:AddCheckbox(page, owner, "showDebuffs", "Show debuffs",
		"Small debuff icons, bordered by type: blue magic, purple curse, brown disease, green poison.", RefreshAll)
	if unit == "target" or unit == "focus" then
		StzxUI:AddCheckbox(page, owner, "threat", "Show my threat",
			"Your threat on this enemy as a % in a small box at the top of the frame, coloured like Blizzard's: "
			.. "grey safe, yellow close to pulling, orange pulled, red tanking. (For a tank: how far ahead of "
			.. "the next person.) If the game makes threat secret in a fight, the % still shows but the box "
			.. "stays plain (red while you're tanking).", RefreshAll)
		StzxUI:AddCheckbox(page, owner, "onlyMine", "Only my debuffs",
			"Only debuffs you put on the target, e.g. to watch your own DoTs.", RefreshAll)
	end
	StzxUI:AddCheckbox(page, owner, "showBuffs", "Show buffs",
		"Small buff icons after the debuffs. Hover an icon for its tooltip.", RefreshAll)
	StzxUI:AddSlider(page, owner, "auraSize", "Buff and debuff size",
		"Icon size.", 16, 36, 2, function(value) return ("%d px"):format(value) end, RefreshAll)
	StzxUI:AddSlider(page, owner, "auraSpacing", "Space between icons",
		nil, 0, 6, 1, function(value) return ("%d px"):format(value) end, RefreshAll)
	StzxUI:AddDropdown(page, owner, "auraPosition", "Buffs and debuffs go",
		"Above or below the frame.", { { "ABOVE", "Above the frame" }, { "BELOW", "Below the frame" } }, RefreshAll)
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
	for _, spec in ipairs(SPECS) do AddFrameOptions(page, spec) end
end

---------------------------------------------------------------------------
-- Building the frames
---------------------------------------------------------------------------

function UnitFrames:HideBlizzard()
	if not self.db.hideBlizzard then return end
	for _, spec in ipairs(SPECS) do
		if self.db[spec.unit].enabled then ns.HideBlizzardFrames(spec.unit) end
	end
end

local function Build(self)
	local db = self.db
	for _, spec in ipairs(SPECS) do
		local settings = db[spec.unit]
		if settings.enabled then
			local name = "StzxUI" .. spec.key .. "Frame"
			local size = spec.small and ns.SIZES.compact or ns.SIZES.full
			local frame = ns.CreateUnitFrame(spec.unit, name, spec.side, settings, size)
			frames[spec.unit] = frame
			StzxUI:RegisterMover(spec.key .. "Frame", frame, {
				label = spec.title,
				category = "Unit frames",
				default = { "CENTER", "CENTER", spec.at[1], spec.at[2] },
				-- Ctrl + mouse wheel in move mode: longer or shorter, 10 px a notch.
				widthWheel = function(delta)
					local lo, hi = spec.small and 80 or 140, spec.small and 240 or 400
					settings.width = math.max(lo, math.min(hi, settings.width + (delta > 0 and 10 or -10)))
					ns.ApplyWidth(spec.unit, settings.width)
				end,
			})

			if spec.cast then
				local bar = ns.CreateCastBar(spec.unit, name .. "CastBar", function() return settings.castBar end)
				castBars[spec.unit] = bar
				StzxUI:RegisterMover(spec.key .. "CastBar", bar, {
					label = spec.title .. " cast bar",
					category = "Unit frames",
					default = { "CENTER", "CENTER", spec.castAt[1], spec.castAt[2] },
					isShown = function() return settings.castBar end,
				})
			end
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

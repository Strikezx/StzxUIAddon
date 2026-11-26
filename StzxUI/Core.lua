-- StzxUI Core
-- The shared heart of StzxUI: the module list, the chat printer and a few
-- helpers every module uses. Each feature lives in its own addon folder
-- (StzxUI_Social, StzxUI_Info, ...) and plugs in through StzxUI:NewModule().
--
-- Other core files:
--   Profiles.lua  saved settings, per-character profiles, export/import
--   Dialog.lua    the small StzxUI pop-up window (names, export strings, reload)
--   Settings.lua  the StzxUI options pages
--   Movers.lua    how a frame becomes movable
--   MoveMode.lua  /stzx move: grid, toolbar, drag and drop

local ADDON_NAME = ...

local StzxUI = {
	modules = {},       -- [name] = module table
	moduleOrder = {},   -- names, in the order they registered
	slashCommands = {}, -- [word] = { help = "...", run = function(rest) end }
}
_G.StzxUI = StzxUI

-- StzxUI's accent colour. StzxUI blue (#4fc3f7) unless the player picks
-- "class colour" (see ApplyAccent below). Always changed in place, so files
-- that keep a reference to this table see the new colour.
StzxUI.ACCENT = { r = 0.31, g = 0.76, b = 0.97 }
local STZX_BLUE = { r = 0.31, g = 0.76, b = 0.97 }

-- Account-wide core settings (the same on every character).
StzxUI.CORE_DEFAULTS = {
	chatMessages = true,   -- print StzxUI notices in the chat window
	accent = "STZX",       -- "STZX" (StzxUI blue) or "CLASS" (your class colour)
	snapToGrid = true,     -- move mode snaps frames to the grid
	snapToFrames = true,   -- move mode lines frames up with each other's edges
	gridSize = 16,         -- grid spacing in move mode
	hiddenCategories = {}, -- move mode: [category] = true to hide its boxes
	withEditMode = true,   -- opening Blizzard's Edit Mode opens move mode too
}

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local PREFIX = "|cff4fc3f7Stzx|rUI:"

-- Print a notice in chat, unless the player turned notices off.
function StzxUI:Print(...)
	if self.db and self.db.core and not self.db.core.chatMessages then return end
	print(PREFIX, ...)
end

-- Same, but always shows (for replies to slash commands and warnings).
function StzxUI:Say(...)
	print(PREFIX, ...)
end

-- WoW: Forever uses the modern client's addon rules. In restricted moments
-- (combat, encounters, PvP) some values come back "secret": addons may show
-- them but may not compare, test or do maths on them. Plain() turns a secret
-- into nil so code can safely write "if value then ... end".
function StzxUI.Plain(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end

-- Fill any missing keys in `target` from `defaults` (nested tables too),
-- without touching values the player already saved.
local function ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then target[key] = {} end
			ApplyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
	return target
end
StzxUI.ApplyDefaults = ApplyDefaults

-- Set StzxUI.ACCENT from the "accent" option.
function StzxUI:ApplyAccent()
	local accent, colour = self.ACCENT, STZX_BLUE
	if self.db and self.db.core.accent == "CLASS" then
		local _, class = UnitClass("player")
		class = StzxUI.Plain(class)
		local classColour = class and C_ClassColor and C_ClassColor.GetClassColor(class)
		if classColour then colour = classColour end
	end
	accent.r, accent.g, accent.b = colour.r, colour.g, colour.b
end

local function ReadVersion()
	local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
	-- In a copy straight from GitHub the packager has not filled this in yet.
	if not version or version:find("^@") then return "dev" end
	return version
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
-- A module file does:
--   local Social = StzxUI:NewModule("Social", "StzxUI_Social", { declineDuels = true },
--       { title = "Social", description = "Duels and thank-yous" })
--   function Social:OnInitialize() ... end  -- settings are ready in self.db
--   function Social:OnEnable() ... end      -- the player is in the world
--
-- The core sets the module up when the module's own addon has finished
-- loading, and turns it on at login (or straight away if it loads later).
-- A module switched off under StzxUI > Sections is loaded but never started.

function StzxUI:NewModule(name, addonName, defaults, info)
	assert(type(name) == "string", "StzxUI:NewModule needs a name")
	assert(not self.modules[name], "StzxUI module registered twice: " .. name)
	info = info or {}
	local module = {
		name = name,
		title = info.title or name,
		description = info.description,
		addonName = addonName or ADDON_NAME,
		defaults = defaults or {},
		initialized = false,
		active = false,   -- switched on in this profile
		enabled = false,  -- OnEnable has run
	}
	self.modules[name] = module
	table.insert(self.moduleOrder, name)
	return module
end

function StzxUI:GetModule(name)
	return self.modules[name]
end

-- Is this section switched on in the current profile? (On unless switched off.)
function StzxUI:IsModuleOn(name)
	return not (self.profile and self.profile.enabled[name] == false)
end

local function SafeCall(module, method)
	local fn = module[method]
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, module)
	if not ok then
		StzxUI:Say(("|cffff5555%s:%s failed:|r %s"):format(module.name, method, tostring(err)))
	end
end

function StzxUI:InitializeModule(module)
	if module.initialized or not self.profile then return end
	local saved = self.profile.modules
	saved[module.name] = ApplyDefaults(saved[module.name] or {}, module.defaults)
	module.db = saved[module.name]
	module.initialized = true
	module.active = self:IsModuleOn(module.name)
	if module.active then
		SafeCall(module, "OnInitialize")
	end
end

function StzxUI:EnableModule(module)
	if module.enabled or not module.initialized or not module.active then return end
	module.enabled = true
	SafeCall(module, "OnEnable")
end

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------

local loggedIn = false
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

events:SetScript("OnEvent", function(_, event, loadedName)
	if event == "ADDON_LOADED" then
		if loadedName == ADDON_NAME then
			StzxUI.version = ReadVersion()
			StzxUI:LoadProfiles()        -- Profiles.lua
			StzxUI:ApplyAccent()
			StzxUI:CreateSettingsPanel() -- Settings.lua
		end
		-- Set up every module whose addon has now finished loading.
		for _, name in ipairs(StzxUI.moduleOrder) do
			local module = StzxUI.modules[name]
			if module.addonName == loadedName then
				StzxUI:InitializeModule(module)
				if loggedIn then StzxUI:EnableModule(module) end
			end
		end
	elseif event == "PLAYER_LOGIN" then
		loggedIn = true
		StzxUI:NoteCharacter()       -- Characters.lua
		StzxUI:FinishSettingsPanel() -- Settings.lua
		for _, name in ipairs(StzxUI.moduleOrder) do
			StzxUI:EnableModule(StzxUI.modules[name])
		end
	end
end)

---------------------------------------------------------------------------
-- /stzx
---------------------------------------------------------------------------

StzxUI.slashCommands.move = {
	help = "unlock StzxUI frames so you can drag them (same again to lock)",
	run = function() StzxUI:ToggleMoveMode() end,
}
StzxUI.slashCommands.test = {
	help = "show or hide test frames (pretend party and raid) to see and place them",
	run = function() StzxUI:ToggleTestMode() end,
}
StzxUI.slashCommands.profile = {
	help = "show which profile this character uses",
	run = function()
		StzxUI:Say(("this character uses the profile '%s'."):format(StzxUI.profileName or "?"))
	end,
}

SLASH_STZXUI1 = "/stzx"
SLASH_STZXUI2 = "/stzxui"
SlashCmdList.STZXUI = function(input)
	local word, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	word = (word or ""):lower()

	if word == "" then
		StzxUI:OpenSettings()
	elseif word == "version" then
		StzxUI:Say("version", StzxUI.version or "dev")
	elseif word == "help" then
		StzxUI:Say("commands:")
		print("  /stzx - open the settings")
		print("  /stzx version - show the version")
		local words = {}
		for command in pairs(StzxUI.slashCommands) do table.insert(words, command) end
		table.sort(words)
		for _, command in ipairs(words) do
			local handler = StzxUI.slashCommands[command]
			if type(handler) == "table" and handler.help then
				print(("  /stzx %s - %s"):format(command, handler.help))
			end
		end
	elseif StzxUI.slashCommands[word] then
		local handler = StzxUI.slashCommands[word]
		local fn = type(handler) == "table" and handler.run or handler
		fn(rest)
	else
		StzxUI:Say(("unknown command '%s'. Type /stzx help"):format(word))
	end
end

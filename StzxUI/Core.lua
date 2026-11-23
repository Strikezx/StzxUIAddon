-- StzxUI Core
-- The shared heart of StzxUI: the saved settings, the module list, the chat
-- printer and a few helpers every module uses. Each feature lives in its own
-- addon folder (StzxUI_Social, StzxUI_Frames, ...) and plugs in through
-- StzxUI:NewModule(), so any part can be switched off in the AddOns list.

local ADDON_NAME = ...

local StzxUI = {
	modules = {},      -- [name] = module table
	moduleOrder = {},  -- names, in the order they registered
}
_G.StzxUI = StzxUI

-- Defaults for the core's own settings. Modules bring their own defaults.
local CORE_DEFAULTS = {
	chatMessages = true, -- print StzxUI notices in the chat window
}

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local PREFIX = "|cff4fc3f7Stzx|rUI:"

-- Print a notice in chat, unless the player turned notices off.
function StzxUI:Print(...)
	if self.db and not self.db.core.chatMessages then return end
	print(PREFIX, ...)
end

-- Same, but always shows (for replies to slash commands).
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
--   local Social = StzxUI:NewModule("Social", "StzxUI_Social", { declineDuels = true })
--   function Social:OnInitialize() ... end  -- settings are ready in self.db
--   function Social:OnEnable() ... end      -- the player is in the world
--
-- The core sets the module up when the module's own addon has finished
-- loading, and turns it on at login (or straight away if it loads later).

function StzxUI:NewModule(name, addonName, defaults)
	assert(type(name) == "string", "StzxUI:NewModule needs a name")
	assert(not self.modules[name], "StzxUI module registered twice: " .. name)
	local module = {
		name = name,
		addonName = addonName or ADDON_NAME,
		defaults = defaults or {},
		initialized = false,
		enabled = false,
	}
	self.modules[name] = module
	table.insert(self.moduleOrder, name)
	return module
end

function StzxUI:GetModule(name)
	return self.modules[name]
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
	if module.initialized or not self.db then return end
	self.db.modules[module.name] = ApplyDefaults(self.db.modules[module.name] or {}, module.defaults)
	module.db = self.db.modules[module.name]
	module.initialized = true
	SafeCall(module, "OnInitialize")
end

function StzxUI:EnableModule(module)
	if module.enabled or not module.initialized then return end
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
			StzxUIDB = StzxUIDB or {}
			StzxUI.db = ApplyDefaults(StzxUIDB, { core = CORE_DEFAULTS, modules = {} })
			StzxUI.version = ReadVersion()
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
		StzxUI:FinishSettingsPanel() -- Settings.lua
		for _, name in ipairs(StzxUI.moduleOrder) do
			StzxUI:EnableModule(StzxUI.modules[name])
		end
	end
end)

---------------------------------------------------------------------------
-- /stzx
---------------------------------------------------------------------------

StzxUI.slashCommands = {} -- modules can add: StzxUI.slashCommands.word = function(rest) end

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
		for command, handler in pairs(StzxUI.slashCommands) do
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

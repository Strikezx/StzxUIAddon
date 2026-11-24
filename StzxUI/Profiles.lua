-- StzxUI Profiles
-- Everything a player sets up (module options, frame positions, which
-- sections are on) lives in a named profile. Each character picks one.
-- Profiles can be copied, reset, deleted, and shared as a text string.
--
-- Saved layout (StzxUIDB, account-wide):
--   core        = { chatMessages, accent, snapToGrid, snapToFrames, gridSize, hiddenCategories }
--                 (same on every character)
--   profiles    = { [name] = { modules = {}, positions = {}, scales = {}, enabled = {} } }
--   profileKeys = { ["Strikezx Kincrag - Realm"] = "Default" }

local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local DB_VERSION = 3
local DEFAULT_PROFILE = "Default"
local EXPORT_PREFIX = "!STZX1!"
local MAX_NAME_LENGTH = 32

StzxUI.DEFAULT_PROFILE = DEFAULT_PROFILE

local function NewProfileData()
	return {
		modules = {},   -- [module name] = that module's settings
		positions = {}, -- [mover key] = { x = , y = } top-left offset from screen centre
		scales = {},    -- [mover key] = size (1 = normal), set with the mouse wheel in move mode
		enabled = {},   -- [module name] = false when that section is switched off
	}
end

-- "Strikezx Kincrag - RealmName", or just "Strikezx Kincrag" when the game
-- gives no realm name (Forever returns an empty one). Also returns the bare
-- name, used to find a key saved in an older format.
local function CharacterKey()
	local name, surname = UnitName("player")
	name, surname = Plain(name) or "Unknown", Plain(surname)
	if surname and surname ~= "" then name = name .. " " .. surname end
	local realm = Plain(GetRealmName())
	if type(realm) == "string" and realm ~= "" then
		return name .. " - " .. realm, name
	end
	return name, name
end

-- Copy a saved table, keeping only plain data (text, numbers, true/false,
-- nested tables). Used for copies and for anything pasted in from outside.
local MAX_DEPTH, MAX_ENTRIES = 8, 20000
local function CleanCopy(source, depth, budget)
	depth = depth or 0
	budget = budget or { left = MAX_ENTRIES }
	if type(source) ~= "table" or depth > MAX_DEPTH then return nil end
	local copy = {}
	for key, value in pairs(source) do
		budget.left = budget.left - 1
		if budget.left < 0 then return nil end
		local keyType, valueType = type(key), type(value)
		if keyType == "string" or keyType == "number" then
			if valueType == "table" then
				local inner = CleanCopy(value, depth + 1, budget)
				if inner == nil and budget.left < 0 then return nil end
				copy[key] = inner
			elseif valueType == "string" or valueType == "number" or valueType == "boolean" then
				copy[key] = value
			end
		end
	end
	return copy
end
StzxUI.CleanCopy = CleanCopy

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------

function StzxUI:LoadProfiles()
	StzxUIDB = StzxUIDB or {}
	local db = StzxUIDB
	db.core = StzxUI.ApplyDefaults(type(db.core) == "table" and db.core or {}, self.CORE_DEFAULTS)
	db.profiles = type(db.profiles) == "table" and db.profiles or {}
	db.profileKeys = type(db.profileKeys) == "table" and db.profileKeys or {}

	-- Version 1 kept module settings in StzxUIDB.modules: move them into "Default".
	if type(db.modules) == "table" then
		local default = db.profiles[DEFAULT_PROFILE] or NewProfileData()
		default.modules = db.modules
		db.profiles[DEFAULT_PROFILE] = default
		db.modules = nil
	end
	-- Version 3: buff and debuff icons a touch bigger (24, small frames 20),
	-- unless you'd already picked your own size.
	if (tonumber(db.version) or 0) < 3 then
		local bigger = { player = { 22, 24 }, target = { 22, 24 }, focus = { 22, 24 },
			targettarget = { 18, 20 }, pet = { 18, 20 } }
		for _, data in pairs(db.profiles) do
			local frames = type(data) == "table" and type(data.modules) == "table" and data.modules.UnitFrames
			if type(frames) == "table" then
				for unit, sizes in pairs(bigger) do
					local f = frames[unit]
					if type(f) == "table" and f.auraSize == sizes[1] then f.auraSize = sizes[2] end
				end
			end
		end
	end
	db.version = DB_VERSION

	db.profiles[DEFAULT_PROFILE] = db.profiles[DEFAULT_PROFILE] or NewProfileData()
	for _, data in pairs(db.profiles) do
		StzxUI.ApplyDefaults(data, NewProfileData())
	end

	self.db = db
	local key, bareName = CharacterKey()
	self.charKey = key
	-- Keys saved by earlier versions: "Name - " (empty realm) or just "Name".
	if db.profileKeys[key] == nil then
		for _, old in ipairs({ bareName .. " - ", bareName }) do
			if old ~= key and db.profileKeys[old] ~= nil then
				db.profileKeys[key] = db.profileKeys[old]
				db.profileKeys[old] = nil
				break
			end
		end
	end
	local name = db.profileKeys[key]
	if type(name) ~= "string" or not db.profiles[name] then name = DEFAULT_PROFILE end
	db.profileKeys[self.charKey] = name
	self.profileName = name
	self.profile = db.profiles[name]
end

---------------------------------------------------------------------------
-- Profile actions (each change that swaps tables asks for a /reload)
---------------------------------------------------------------------------

function StzxUI:GetProfileNames()
	local names = {}
	for name in pairs(self.db.profiles) do table.insert(names, name) end
	table.sort(names, function(a, b)
		if a == DEFAULT_PROFILE then return true end
		if b == DEFAULT_PROFILE then return false end
		return a:lower() < b:lower()
	end)
	return names
end

-- Trimmed name, or nil plus the reason it can't be used.
function StzxUI:CheckProfileName(text)
	local name = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
	if name == "" then return nil, "Type a name first." end
	if #name > MAX_NAME_LENGTH then return nil, ("Keep it under %d letters."):format(MAX_NAME_LENGTH) end
	if self.db.profiles[name] then return nil, ("There is already a profile called '%s'."):format(name) end
	return name
end

-- Which profile the next /reload will use (after a switch, before the reload).
function StzxUI:GetChosenProfile()
	return self.db.profileKeys[self.charKey] or self.profileName
end

function StzxUI:SwitchProfile(name)
	if not self.db.profiles[name] then return false end
	self.db.profileKeys[self.charKey] = name
	if name ~= self.profileName then
		self:AskReload(("This character will use the profile '%s'."):format(name))
	end
	return true
end

-- New profile, copied from `copyFrom` (a profile name) or empty.
function StzxUI:CreateProfile(text, copyFrom)
	local name, problem = self:CheckProfileName(text)
	if not name then return nil, problem end
	local source = copyFrom and self.db.profiles[copyFrom]
	local data = source and CleanCopy(source) or NewProfileData()
	self.db.profiles[name] = StzxUI.ApplyDefaults(data, NewProfileData())
	return name
end

function StzxUI:DeleteProfile(name)
	if name == DEFAULT_PROFILE then return false, "The Default profile can't be deleted." end
	if not self.db.profiles[name] then return false, "No such profile." end
	self.db.profiles[name] = nil
	-- Characters that used it go back to Default.
	for key, used in pairs(self.db.profileKeys) do
		if used == name then self.db.profileKeys[key] = DEFAULT_PROFILE end
	end
	if name == self.profileName then
		self:AskReload(("Profile '%s' deleted. This character now uses Default."):format(name))
	end
	return true
end

-- Back to defaults: options, positions and sections.
function StzxUI:ResetProfile()
	local data = self.profile
	for key in pairs(data) do data[key] = nil end
	StzxUI.ApplyDefaults(data, NewProfileData())
	self:AskReload(("Profile '%s' is back to its defaults."):format(self.profileName))
end

---------------------------------------------------------------------------
-- Sharing: a profile as one line of text
---------------------------------------------------------------------------

function StzxUI:ExportProfile()
	local payload = { addon = "StzxUI", v = 1, profile = CleanCopy(self.profile) }
	local ok, text = pcall(function()
		local raw = C_EncodingUtil.SerializeCBOR(payload)
		return EXPORT_PREFIX .. C_EncodingUtil.EncodeBase64(C_EncodingUtil.CompressString(raw))
	end)
	if ok then return text end
	return nil, "Export failed: " .. tostring(text)
end

-- Read a shared string. Returns the profile data, or nil plus a reason.
function StzxUI:DecodeProfile(text)
	if type(text) ~= "string" then return nil, "Nothing pasted." end
	text = text:gsub("%s+", "")
	if text:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
		return nil, "That isn't a StzxUI profile string."
	end
	local ok, payload = pcall(function()
		local packed = C_EncodingUtil.DecodeBase64(text:sub(#EXPORT_PREFIX + 1))
		return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecompressString(packed))
	end)
	if not ok or type(payload) ~= "table" or payload.addon ~= "StzxUI" or type(payload.profile) ~= "table" then
		return nil, "The string is damaged or incomplete. Copy it again."
	end
	local data = CleanCopy(payload.profile)
	if not data then return nil, "The string is too large." end
	return StzxUI.ApplyDefaults(data, NewProfileData())
end

-- Import a string as a new profile (named "Imported", "Imported 2", ...) and switch to it.
function StzxUI:ImportProfile(text)
	local data, problem = self:DecodeProfile(text)
	if not data then return nil, problem end
	local name, n = "Imported", 1
	while self.db.profiles[name] do
		n = n + 1
		name = "Imported " .. n
	end
	self.db.profiles[name] = data
	self:SwitchProfile(name)
	return name
end

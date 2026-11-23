-- Offline test harness for StzxUI.
-- Fakes just enough of the WoW API to load the addons in the game's order
-- and fire events at them. It can't prove anything about the real client:
-- it catches typos, load-order mistakes and logic slips before you /reload.
--
-- Run from the repo root:  lua5.1 tests/harness.lua

local failures, passes = 0, 0
local function check(cond, label)
	if cond then passes = passes + 1 else failures = failures + 1; io.write("FAIL: " .. label .. "\n") end
end

---------------------------------------------------------------------------
-- Fake client
---------------------------------------------------------------------------
local log = { prints = {}, emotes = {}, whispers = {}, cancelled = 0, hidden = {}, settings = {} }
local now, inCombat, aurasSecret = 1000, false, false
local units = {} -- [token] = { name, surname, isPlayer, isSelf, inParty }

function print(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring(select(i, ...)) end table.insert(log.prints, table.concat(t, " ")) end
function issecretvalue(v) return type(v) == "table" and v.__secret == true end
local SECRET = { __secret = true }

local frames = {}
function CreateFrame()
	local f = { events = {}, unitEvents = {} }
	function f:RegisterEvent(e) self.events[e] = true end
	function f:RegisterUnitEvent(e, u) self.events[e] = true; self.unitEvents[e] = u end
	function f:SetScript(_, fn) self.onEvent = fn end
	table.insert(frames, f)
	return f
end
local function Fire(event, ...)
	for _, f in ipairs(frames) do
		if f.events[event] and f.onEvent then
			local unit = f.unitEvents[event]
			if not unit or unit == (...) then f.onEvent(f, event, ...) end
		end
	end
end

C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }
SlashCmdList = {}
function GetTime() return now end
function InCombatLockdown() return inCombat end
function IsInInstance() return false end
C_Secrets = { ShouldAurasBeSecret = function() return aurasSecret end }
function UnitName(u) local d = units[u]; if d then return d.name, d.surname end end
function UnitIsPlayer(u) local d = units[u]; return d and d.isPlayer or false end
function UnitIsUnit(a, b) if b == "player" then local d = units[a]; return d and d.isSelf or false end return a == b end
function UnitInParty(u) local d = units[u]; return d and d.inParty or false end
function UnitInRaid() return nil end
function CancelDuel() log.cancelled = log.cancelled + 1 end
function StaticPopup_Hide(which) table.insert(log.hidden, which) end
C_ChatInfo = {
	PerformEmote = function(emote, target) table.insert(log.emotes, emote .. ">" .. tostring(target)); return true end,
	SendChatMessage = function(msg, kind, _, target) table.insert(log.whispers, kind .. ">" .. target .. ">" .. msg) end,
}

-- Settings API: record what gets registered, write defaults into the table like the real one.
local categoryId = 0
local function NewCategory(name) categoryId = categoryId + 1; local c = { name = name, id = categoryId }; function c:GetID() return self.id end; return c end
local function NewSetting(var, key, tbl, kind, default)
	if tbl[key] == nil then tbl[key] = default end
	local s = { var = var, key = key, tbl = tbl, kind = kind }
	function s:SetValueChangedCallback(fn) self.cb = fn end
	log.settings[var] = s
	return s
end
Settings = {
	VarType = { Boolean = "boolean", String = "string", Number = "number" },
	RegisterVerticalLayoutCategory = function(name) return NewCategory(name) end,
	RegisterVerticalLayoutSubcategory = function(_, name) return NewCategory(name) end,
	RegisterAddOnSetting = function(_, var, key, tbl, kind, _, default) return NewSetting(var, key, tbl, kind, default) end,
	RegisterAddOnCategory = function(c) log.registered = c.name end,
	CreateCheckbox = function() end,
	CreateDropdown = function(_, _, options) log.dropdownOptions = options() end,
	CreateSlider = function() end,
	CreateSliderOptions = function() return { SetLabelFormatter = function(self, _, fn) self.fmt = fn end } end,
	CreateControlTextContainer = function()
		local c = { data = {} }
		function c:Add(v, l) table.insert(self.data, { value = v, label = l }) end
		function c:GetData() return self.data end
		return c
	end,
	OpenToCategory = function(id) log.opened = id end,
}
MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }

---------------------------------------------------------------------------
-- Load like the game: each addon's files in TOC order, then ADDON_LOADED.
---------------------------------------------------------------------------
local function LoadAddon(folder)
	local toc = assert(io.open(folder .. "/" .. folder .. ".toc")):read("*a")
	local ns = {}
	for line in toc:gmatch("[^\r\n]+") do
		if line:match("%.lua$") then
			local chunk = assert(loadfile(folder .. "/" .. line))
			chunk(folder, ns)
		end
	end
	Fire("ADDON_LOADED", folder)
end

StzxUIDB = nil -- fresh install
LoadAddon("StzxUI")
LoadAddon("StzxUI_Social")
Fire("PLAYER_LOGIN")

local Social = StzxUI:GetModule("Social")
check(StzxUI.version == "dev", "version placeholder shows as dev")
check(StzxUIDB and StzxUIDB.core.chatMessages == true, "core defaults saved")
check(Social.initialized and Social.enabled, "Social module initialized and enabled")
check(StzxUIDB.modules.Social.declineDuels == true, "Social defaults saved")
check(log.registered == "StzxUI", "settings category registered at login")
check(log.settings.STZXUI_SOCIAL_THANKMODE ~= nil, "thank mode setting registered")
check(log.dropdownOptions and #log.dropdownOptions == 2, "thank mode dropdown has 2 choices")

-- Duels
Fire("DUEL_REQUESTED", "Grumpy Orcface")
check(log.cancelled == 1 and log.hidden[1] == "DUEL_REQUESTED", "duel declined and popup hidden")
check(log.prints[#log.prints]:find("Grumpy Orcface", 1, true), "declined duel announced")
Social.db.declineDeathDuels = false
Fire("DUEL_TO_THE_DEATH_REQUESTED", "Someone Else")
check(log.cancelled == 1, "death duel left alone when that option is off")
Social.db.declineDuels = false
Fire("DUEL_REQUESTED", "Another One")
check(log.cancelled == 1, "duels left alone when declining is off")
Social.db.declineDuels, Social.db.declineDeathDuels = true, true
Fire("DUEL_REQUESTED", SECRET)
check(log.cancelled == 2 and log.prints[#log.prints]:find("someone", 1, true), "secret name still declines, says 'someone'")

-- Thanks
units.nameplate1 = { name = "Petra", surname = "Stonewell", isPlayer = true }
units.party1 = { name = "Buddy", surname = "Pal", isPlayer = true, inParty = true }
units.player = { name = "Strikezx", surname = "Kincrag", isPlayer = true, isSelf = true }
local function Buffed(source, helpful)
	Fire("UNIT_AURA", "player", { addedAuras = { { isHelpful = helpful ~= false, sourceUnit = source } } })
end

Buffed("nameplate1")
check(log.emotes[1] == "THANK>Petra Stonewell", "emote thanks with the full two-part name")
now = now + 30
Buffed("nameplate1")
check(#log.emotes == 1, "same player not thanked again inside the cooldown")
now = now + 5 * 60
Buffed("nameplate1")
check(#log.emotes == 2, "thanked again after the cooldown")
now = now + 600
Buffed("party1")
check(#log.emotes == 2, "party member not thanked by default")
Buffed("player")
check(#log.emotes == 2, "own buffs not thanked")
Buffed("nameplate1", false)
check(#log.emotes == 2, "harmful auras ignored")
inCombat = true; now = now + 600
Buffed("nameplate1")
check(#log.emotes == 2, "no thanks in combat")
inCombat, aurasSecret = false, true
Buffed("nameplate1")
check(#log.emotes == 2, "no thanks while auras are secret")
aurasSecret = false
Buffed(SECRET)
check(#log.emotes == 2, "secret source ignored")
Social.db.thankMode = "WHISPER"; now = now + 600
Buffed("nameplate1")
check(log.whispers[1] == "WHISPER>Petra Stonewell>Thanks for the buff, Petra!", "whisper goes to full name, message uses first name")
Fire("UNIT_AURA", "player", { isFullUpdate = true, addedAuras = { { isHelpful = true, sourceUnit = "nameplate1" } } })
check(#log.whispers == 1, "full updates (login, zoning) never thank")

-- Slash commands
SlashCmdList.STZXUI("thanks Cheers %s, appreciated!")
check(Social.db.thankMessage == "Cheers %s, appreciated!", "/stzx thanks sets the whisper")
SlashCmdList.STZXUI("")
check(log.opened ~= nil, "/stzx opens the settings")
SlashCmdList.STZXUI("help")
check(log.prints[#log.prints]:find("/stzx thanks", 1, true), "/stzx help lists module commands")
SlashCmdList.STZXUI("nonsense")
check(log.prints[#log.prints]:find("unknown command", 1, true), "unknown command explained")

-- Saved settings survive a reload
local saved = StzxUIDB
frames, log.settings = {}, {}
StzxUI = nil
StzxUIDB = saved
LoadAddon("StzxUI")
LoadAddon("StzxUI_Social")
Fire("PLAYER_LOGIN")
check(StzxUI:GetModule("Social").db.thankMessage == "Cheers %s, appreciated!", "settings kept after /reload")

io.write(("%d passed, %d failed\n"):format(passes, failures))
os.exit(failures == 0 and 0 or 1)

-- Offline test harness for StzxUI.
-- Fakes just enough of the WoW client to load the addons in the game's order,
-- fire events, drag frames and click buttons. It can't prove anything about
-- the real client: it catches typos, load-order mistakes and logic slips
-- before you /reload. A frame method the fake doesn't know raises an error,
-- so new API calls get noticed (then check them against Blizzard's source).
--
-- Run from the repo root:  lua5.1 tests/harness.lua

local failures, passes = 0, 0
local function check(cond, label)
	if cond then passes = passes + 1 else failures = failures + 1; io.write("FAIL: " .. label .. "\n") end
end

---------------------------------------------------------------------------
-- Fake client state
---------------------------------------------------------------------------
local log
local now, inCombat, aurasSecret, shiftDown = 1000, false, false, false
local units, mapPos = {}, nil
local frames, tickers
local SECRET = { __secret = true }
local SECRET_TEXT = "<secret>"
local unitState = {}   -- [unit] = fake unit data for the unit frames
local casting = {}     -- [unit] = { name, texture, startMS, endMS, castID, notInterruptible, channel }
local blizzard = {}
local auraState = {}   -- [unit] = list of fake auras { auraInstanceID, icon, duration, expirationTime, applications, dispelName, harmful, mine }
local realmName = "Testrealm"
local group = { kind = nil, units = {} } -- fake roster: kind "party"/"raid", units in order
local rangeOf = {}     -- [unit] = { inRange, checked }
local questID = 0      -- the quest open in the quest giver window
local questLog, questOffers = {}, {}
local instance, money, lootWindow = nil, 0, {}
local mailLoaded = true
local afters = {}
local function RunAfters() local list = afters; afters = {}; for _, fn in ipairs(list) do fn() end end
local function TickAll(list)
	for _, t in ipairs(list) do
		if not t.cancelled and (t.left == nil or t.left > 0) then
			if t.left then t.left = t.left - 1 end
			t.fn(t)
		end
	end
end
local editMode = { active = false, gridShown = true, spacing = 20 }
local cvars = {}
local jiberishInstalled = false
local SCREEN_W, SCREEN_H = 1600, 900

local function ResetLog()
	log = { pushed = {}, prints = {}, emotes = {}, whispers = {}, cancelled = 0, hidden = {}, settings = {},
		reloads = 0, categories = {}, settingsClosed = 0 }
end
ResetLog()

function print(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring(select(i, ...)) end table.insert(log.prints, table.concat(t, " ")) end
local function lastPrint() return log.prints[#log.prints] or "" end
function issecretvalue(v) return type(v) == "table" and v.__secret == true end
date = os.date

---------------------------------------------------------------------------
-- Fake frames (with simple geometry for anchoring and dragging)
---------------------------------------------------------------------------
local FRACTION = {
	TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
	LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
	BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

local Frame = {}
Frame.__index = Frame
local UIParentRect = { left = 0, bottom = 0, w = SCREEN_W, h = SCREEN_H }

local function NewFrame(kind, name, parent)
	local f = setmetatable({ kind = kind, name = name, parent = parent, points = {}, w = 0, h = 0,
		shown = true, scripts = {}, events = {}, unitEvents = {}, text = "" }, Frame)
	table.insert(frames, f)
	if name then _G[name] = f end
	return f
end

function Frame:Rect()
	if self.isUIParent then return UIParentRect end
	if self.allPointsOf then
		local r = self.allPointsOf:Rect()
		return r and { left = r.left, bottom = r.bottom, w = r.w, h = r.h }
	end
	local p = self.points[1]
	if not p then return nil end
	local rel = p.rel or self.parent or UIParent
	local rr = rel:Rect()
	if not rr then return nil end
	local rf, pf = FRACTION[p.relPoint], FRACTION[p.point]
	local ax, ay = rr.left + rf[1] * rr.w + p.x, rr.bottom + rf[2] * rr.h + p.y
	return { left = ax - pf[1] * self.w, bottom = ay - pf[2] * self.h, w = self.w, h = self.h }
end
function Frame:SetPoint(point, rel, relPoint, x, y)
	if type(rel) == "number" then rel, relPoint, x, y = nil, point, rel, relPoint end
	if type(relPoint) == "number" then relPoint, x, y = point, relPoint, x end
	relPoint = relPoint or point
	assert(FRACTION[point] and FRACTION[relPoint], "bad anchor point " .. tostring(point))
	self.allPointsOf = nil
	table.insert(self.points, { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 })
end
function Frame:ClearAllPoints() self.points = {}; self.allPointsOf = nil end
function Frame:SetAllPoints(rel) self.allPointsOf = rel or self.parent end
function Frame:GetLeft() local r = self:Rect(); return r and r.left end
function Frame:GetEffectiveScale() return self.effScale or 1 end
-- In the frame's own units: divided by its scale, as the game does.
function Frame:GetRect()
	local r = self:Rect()
	if not r then return nil end
	local s = self.effScale or 1
	return r.left / s, r.bottom / s, r.w / s, r.h / s
end
function Frame:SetEnabled(on) self.enabled = on and true or false end
function Frame:GetTop() local r = self:Rect(); return r and (r.bottom + r.h) end
function Frame:GetCenter() local r = self:Rect(); if r then return r.left + r.w / 2, r.bottom + r.h / 2 end end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth() return self.isUIParent and SCREEN_W or self.w end
function Frame:GetHeight() return self.isUIParent and SCREEN_H or self.h end
function Frame:Show() local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
function Frame:Hide() local was = self.shown; self.shown = false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:RegisterUnitEvent(e, u) self.events[e] = true; self.unitEvents[e] = u end
function Frame:StartMoving() self.moving = true end
function Frame:StopMovingOrSizing() self.moving = false end
function Frame:CreateTexture() return NewFrame("Texture", nil, self) end
function Frame:CreateFontString() return NewFrame("FontString", nil, self) end
function Frame:SetText(t) self.text = t or "" end
function Frame:GetText() return self.text end
function Frame:SetFormattedText(fmt, ...) self.text = fmt:format(...) end
function Frame:SetChecked(v) self.checked = v end
function Frame:GetChecked() return self.checked end
function Frame:Click(button) if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end end
function Frame:EnableKeyboard(v) self.keyboard = v end
function Frame:SetPropagateKeyboardInput(v) self.propagate = v end
function Frame:GetStringHeight() return 14 end
function Frame:HighlightText() self.highlighted = true end
function Frame:SetFocus() self.focused = true end
function Frame:SetCursorPosition(n) self.cursor = n end
function Frame:SetFormattedText(fmt, ...)
	local args, secret = { ... }, false
	for i = 1, select("#", ...) do if issecretvalue(args[i]) then secret = true end end
	if secret then self.text = SECRET_TEXT else self.text = fmt:format(...) end
end
function Frame:SetText(t) if issecretvalue(t) then self.text = SECRET_TEXT else self.text = t or "" end end
function Frame:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
function Frame:SetValue(v) self.value = v end
function Frame:GetValue() return self.value end
function Frame:SetStatusBarColor(r, g, b) self.colour = { r, g, b } end
function Frame:SetReverseFill(v) self.reverse = v end
function Frame:SetAttribute(k, v)
	self.attributes = self.attributes or {}
	self.attributes[k] = v
	if self.scripts.OnAttributeChanged then self.scripts.OnAttributeChanged(self, k, v) end
end
function Frame:HookScript(name, fn)
	local old = self.scripts[name]
	self.scripts[name] = old and function(...) old(...); fn(...) end or fn
end
function Frame:SetGradient(_, from, to) self.gradient = { from = from, to = to } end
function Frame:SetAlphaFromBoolean(v, yes, no)
	self.alpha = issecretvalue(v) and "secret" or (v and yes or no)
end
function Frame:GetAttribute(k) return self.attributes and self.attributes[k] end
function Frame:SetTexture(t) self.texture = t end
function Frame:SetTexCoord(...) self.texCoord = { ... } end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:GetAlpha() return self.alpha or 1 end
function Frame:SetScale(sc) self.scale = sc end
function Frame:GetScale() return self.scale or 1 end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetFrameLevel(l) self.level = l end
function Frame:CreateMaskTexture() return NewFrame("MaskTexture", nil, self) end
function Frame:AddMaskTexture(m) self.mask = m end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:SetParent(p) self.parent = p end
function Frame:GetParent() return self.parent end
function Frame:SetCooldown(start, duration) self.cooldownStart, self.cooldownDuration, self.durationObject = start, duration, nil end
function Frame:SetCooldownFromDurationObject(d) self.durationObject, self.cooldownStart = d, nil end
function Frame:Clear() self.cooldownStart, self.durationObject = nil, nil end
function Frame:IsVisible() local f = self while f do if not f.shown then return false end f = f.parent end return true end
local NOOPS = { "SetFrameStrata", "SetToplevel", "SetClampedToScreen", "SetMovable", "EnableMouse",
	"RegisterForDrag", "RegisterForClicks", "SetDontSavePosition", "SetColorTexture", "SetTextColor",
	"SetJustifyH", "SetShadowOffset", "SetAutoFocus", "SetMaxLetters", "SetMultiLine", "SetFontObject",
	"SetScrollChild", "SetOwner", "AddLine", "SetFont", "SetShadowColor", "SetWordWrap", "SetWidth",
	"SetVertexColor", "SetStatusBarTexture", "EnableMouseWheel", "SetUnit", "SetReverse", "SetDrawEdge" }
for _, m in ipairs(NOOPS) do Frame[m] = function() end end

local function Fire(event, ...)
	for _, f in ipairs(frames) do
		if f.events[event] and f.scripts.OnEvent then
			local unit = f.unitEvents[event]
			if not unit or unit == (...) then f.scripts.OnEvent(f, event, ...) end
		end
	end
end
local function Script(f, name, ...) assert(f.scripts[name], "no " .. name .. " script")(f, ...) end

---------------------------------------------------------------------------
-- Fake game API
---------------------------------------------------------------------------
local function InstallClient()
	frames, tickers = {}, {}
	UIParent = setmetatable({ isUIParent = true, points = {}, shown = true, scripts = {}, events = {}, unitEvents = {} }, Frame)
	GameTooltip = NewFrame("GameTooltip", "GameTooltip")
	UISpecialFrames = {}
	SlashCmdList = {}
	-- The secure group header: rebuilds its buttons from the fake roster
	-- whenever it's shown or an attribute changes, like Blizzard's.
	local function HeaderUnits(h)
		local a = h.attributes or {}
		if group.kind == "raid" and a.showRaid then return group.units end
		if group.kind == "party" and a.showParty then
			local list = {}
			if a.showPlayer then list[1] = "player" end
			for _, u in ipairs(group.units) do list[#list + 1] = u end
			return list
		end
		if group.kind == nil and a.showSolo then return { "player" } end
		return {}
	end
	local function HeaderUpdate(h)
		if not h:IsVisible() or (h.attributes and h.attributes._ignore) then return end
		local list = HeaderUnits(h)
		local start = h:GetAttribute("startingIndex") or 1
		local shown = #list - (start - 1)
		for i = 1, math.max(1, shown) do
			if not h[i] then
				h[i] = NewFrame("Button", h.name .. "UnitButton" .. i, h)
				h[i].template = h:GetAttribute("template")
				h[i].configCode = h:GetAttribute("initialConfigFunction")
			end
		end
		local i = 1
		while h[i] do
			local unit = (i <= shown) and list[start + i - 1] or nil
			if h[i]:GetAttribute("unit") ~= unit then h[i]:SetAttribute("unit", unit) end
			h[i].shown = unit ~= nil
			i = i + 1
		end
		log.headerUpdates = (log.headerUpdates or 0) + 1
	end
	function CreateFrame(kind, name, parent, template)
		local f = NewFrame(kind, name, parent or UIParent)
		if template and template:find("Header") then
			f.shown = false
			f.attributes = {
				showParty = template == "SecurePartyHeaderTemplate" or nil,
				showRaid = template == "SecureRaidGroupHeaderTemplate" or nil,
			}
			f.scripts.OnShow = HeaderUpdate
			f.scripts.OnAttributeChanged = function(h, k) if k ~= "_ignore" then HeaderUpdate(h) end end
			f.headerUpdate = HeaderUpdate
		end
		return f
	end
	-- Quest windows: three quest giver pages and the quest log's detail page,
	-- each with its parchment texture (.Bg).
	for _, name in ipairs({ "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel" }) do
		local panel = NewFrame("Frame", name)
		panel.Bg = panel:CreateTexture()
		panel.Bg:SetSize(300, 400)
		panel.shown = false
	end
	QuestFrame = NewFrame("Frame", "QuestFrame")
	QuestFrame.shown = false
	QuestMapFrame = NewFrame("Frame", "QuestMapFrame")
	QuestMapFrame.DetailsFrame = NewFrame("Frame", nil, QuestMapFrame)
	QuestMapFrame.DetailsFrame.Bg = QuestMapFrame.DetailsFrame:CreateTexture()
	QuestMapFrame.DetailsFrame.Bg:SetSize(280, 500)
	function QuestMapFrame_ShowQuestDetails(id) QuestMapFrame.DetailsFrame.questID = id end
	function QuestMapFrame_CloseQuestDetails() QuestMapFrame.DetailsFrame.questID = nil end
	function hooksecurefunc(t, name, fn)
		if type(t) == "string" then t, name, fn = _G, t, name end
		local old = t[name]
		t[name] = function(...) local a, b = old(...); fn(...); return a, b end
	end
	function GetQuestID() return questID end
	function UnitXP() return unitState.player.xp or 0 end
	function UnitXPMax() return unitState.player.xpMax or 1000 end
	function GetMaxLevelForPlayerExpansion() return 60 end
	function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
	C_CVar = {
		GetCVar = function(k) return cvars[k] end,
		SetCVar = function(k, v) cvars[k] = tostring(v); log.cvarSets = (log.cvarSets or 0) + 1 end,
	}
	function RegisterStateDriver(frame, state, condition) frame.stateDriver = { state = state, condition = condition } end
	function UnitInRange(u) local r = rangeOf[u]; if r then return r[1], r[2] end return true, true end
	function UnitIsGroupLeader(u) local d = unitState[u]; return d and d.leader or false end
	function GetRaidTargetIndex(u) local d = unitState[u]; return d and d.marker end
	function SetRaidTargetIconTexture(tex, index) tex.markerIndex = index end
	C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }
	function GetTime() return now end
	function InCombatLockdown() return inCombat end
	-- Instances: instance = nil (outside) or { name, kind, id }.
	function IsInInstance() if instance then return true, instance.kind end return false, "none" end
	function GetInstanceInfo()
		if not instance then return "Eastern Kingdoms", "none", 0, "", 0, 0, false, 0 end
		return instance.name, instance.kind, 1, "Normal", 5, 0, false, instance.id
	end
	function time() return math.floor(now) end
	function date(fmt, t) return os.date(fmt, t) end
	function wipe(t) for k in pairs(t) do t[k] = nil end return t end
	function GetMoney() return money end
	function strtrim(t) return (t:gsub("^%s+", ""):gsub("%s+$", "")) end
	-- The mail window (Blizzard_MailFrame): made when "mailLoaded" is set.
	if mailLoaded then
		MailFrame = NewFrame("Frame", "MailFrame")
		SendMailFrame = NewFrame("Frame", "SendMailFrame", MailFrame)
		SendMailNameEditBox = NewFrame("EditBox", "SendMailNameEditBox", SendMailFrame)
		SendMailSubjectEditBox = NewFrame("EditBox", "SendMailSubjectEditBox", SendMailFrame)
		function SendMailFrame_SendMail() log.mailSent = SendMailNameEditBox:GetText() end
	else
		MailFrame, SendMailFrame, SendMailNameEditBox, SendMailFrame_SendMail = nil, nil, nil, nil
	end
	function GetNumLootItems() return #lootWindow end
	function GetLootSlotLink(i) return lootWindow[i] and lootWindow[i].link end
	function GetLootSlotInfo(i) local l = lootWindow[i]; if l then return nil, l.link, 1, nil, l.quality end end
	function IsShiftKeyDown() return shiftDown end
	C_Secrets = { ShouldAurasBeSecret = function() return aurasSecret end }
	function UnitName(u) local d = units[u]; if d then return d.name, d.surname end end
	function UnitIsPlayer(u) local d = units[u]; return d and d.isPlayer or false end
	function UnitIsUnit(a, b) if b == "player" then local d = units[a]; return d and d.isSelf or false end return a == b end
	function UnitInParty(u) local d = units[u]; return d and d.inParty or false end
	function UnitInRaid() return nil end
	function GetRealmName() return realmName end
	function CancelDuel() log.cancelled = log.cancelled + 1 end
	function StaticPopup_Hide(which) table.insert(log.hidden, which) end
	C_ChatInfo = {
		PerformEmote = function(emote, target) table.insert(log.emotes, emote .. ">" .. tostring(target)); return true end,
		SendChatMessage = function(msg, kind, _, target) table.insert(log.whispers, kind .. ">" .. target .. ">" .. msg) end,
	}
	C_UI = { Reload = function() log.reloads = log.reloads + 1 end }
	-- Unit frame APIs
	local function U(unit) return unitState[unit] or {} end
	function UnitExists(u) return unitState[u] ~= nil end
	function UnitClass(u) return U(u).class and "Class", U(u).class end
	function UnitHealth(u) return U(u).hp or 0 end
	function UnitHealthMax(u) return U(u).hpMax or 1 end
	CurveConstants = { ScaleTo100 = {} }
	function UnitHealthPercent(u, _, curve)
		local d = U(u)
		if issecretvalue(d.hp) then return SECRET end
		return (d.hp or 0) / (d.hpMax or 1) * (curve and 100 or 1)
	end
	function UnitPower(u) return U(u).power or 0 end
	function UnitPowerMax(u) return U(u).powerMax or 0 end
	function UnitPowerType(u) return 0, U(u).powerToken or "MANA" end
	function UnitReaction(u) return U(u).reaction end
	function UnitIsTapDenied(u) return U(u).tapped or false end
	function UnitLevel(u) return U(u).level or 1 end
	function UnitClassification(u) return U(u).classification or "normal" end
	function UnitIsDeadOrGhost(u) return U(u).dead or false end
	function UnitIsGhost(u) return U(u).ghost or false end
	function UnitIsConnected(u) return U(u).offline ~= true end
	function AbbreviateLargeNumbers(n)
		if issecretvalue(n) then return SECRET end
		if n >= 1000 then return (("%.1fK"):format(n / 1000)) end
		return tostring(n)
	end
	C_ClassColor = { GetClassColor = function(class)
		local c = ({ DRUID = { 1, 0.49, 0.04 }, SHAMAN = { 0, 0.44, 0.87 } })[class]
		if c then return { r = c[1], g = c[2], b = c[3] } end
	end }
	CLASS_ICON_TCOORDS = { DRUID = { 0.75, 1, 0, 0.25 }, SHAMAN = { 0.25, 0.5, 0.25, 0.5 } }
	STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
	function SetPortraitTexture(tex, unit) tex.portraitOf = unit end
	function RegisterUnitWatch(frame) frame.unitWatch = true end
	function GameTooltip_SetDefaultAnchor() end
	local function Cast(u, wantChannel)
		local c = casting[u]
		if not c or (c.channel or false) ~= wantChannel then return nil end
		if wantChannel then return c.name, c.name, c.texture, c.startMS, c.endMS, false, c.notInterruptible end
		return c.name, c.name, c.texture, c.startMS, c.endMS, false, c.castID, c.notInterruptible
	end
	function UnitCastingInfo(u) return Cast(u, false) end
	function UnitChannelInfo(u) return Cast(u, true) end
	-- Auras
	Enum = { UnitAuraSortRule = { Expiration = 3 }, EditModeAccountSetting = { ShowGrid = 0, GridSpacing = 1 } }
	-- Edit Mode: Blizzard's callback registry and its manager frame, with one
	-- system frame (an action bar at half scale) to snap to.
	local callbacks = {}
	EventRegistry = {
		RegisterCallback = function(_, event, fn, owner) callbacks[event] = callbacks[event] or {}; callbacks[event][owner] = fn end,
		TriggerEvent = function(_, event) for _, fn in pairs(callbacks[event] or {}) do fn() end end,
	}
	EditModeManagerFrame = NewFrame("Frame", "EditModeManagerFrame")
	EditModeManagerFrame.Grid = NewFrame("Frame", nil, EditModeManagerFrame)
	function EditModeManagerFrame:IsEditModeActive() return editMode.active end
	function EditModeManagerFrame:GetAccountSettingValue(setting) if setting == 1 then return editMode.spacing end end
	function EditModeManagerFrame:SetGridShown(on) editMode.gridShown = on; self.Grid.shown = on end
	function EditModeManagerFrame:SetGridSpacing(n) editMode.spacing = n end
	local bar = NewFrame("Frame", "MainActionBar")
	bar.effScale = 0.5
	bar:SetSize(500, 50)
	bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 600, 100)
	EditModeManagerFrame.registeredSystemFrames = { bar }
	C_UnitAuras = {
		GetUnitAuras = function(unit, filter, maxCount)
			local list = {}
			for _, a in ipairs(auraState[unit] or {}) do
				local wantHarmful = filter:find("HARMFUL", 1, true) ~= nil
				local onlyMine = filter:find("PLAYER", 1, true) ~= nil
				if (a.harmful or false) == wantHarmful and (not onlyMine or a.mine) and #list < (maxCount or 99) then
					table.insert(list, a)
				end
			end
			return list
		end,
		GetAuraDuration = function(unit, id) return { durationOf = id } end,
		GetAuraApplicationDisplayCount = function(unit, id) return SECRET end,
	}
	function GameTooltip:SetUnitAuraByAuraInstanceID(unit, id) self.auraShown = id end
	-- The optional JiberishUI Icons addon (only its public table)
	if jiberishInstalled then
		local JI = { mergedStylePacks = {
			class = { styles = { fabled = { name = "Fabled" }, fabledrealm = { name = "Fabled Realm" } } },
			race = { styles = { fabledazeroth = { name = "Fabled Azeroth" } } },
		} }
		function JI:GetUnitIcon(unit, style)
			if not (unitState[unit] and unitState[unit].class) or not UnitIsPlayer(unit) then return end
			return { texCoords = { 0.125, 0.125, 0.125, 0.25, 0.25, 0.125, 0.25, 0.25 } }, "Interface\\AddOns\\JiberishIcons\\Media\\Class\\" .. style, 1024
		end
		JiberishIcons = { JI }
	else
		JiberishIcons = nil
	end
	-- Blizzard's own frames that StzxUI hides
	for _, name in ipairs({ "PlayerFrame", "TargetFrame", "PlayerCastingBarFrame", "TargetFrameSpellBar",
		"FocusFrame", "FocusFrameSpellBar", "PetFrame", "TargetFrameToT", "PartyFrame",
		"CompactRaidFrameManager", "CompactRaidFrameContainer" }) do
		blizzard[name] = NewFrame("Frame", name)
		blizzard[name].events.SOMETHING = true
	end
	function GetFramerate() return 59.6 end
	function GetNetStats() return 0, 0, 42, 61 end
	C_Map = {
		GetBestMapForUnit = function() return 1429 end,
		GetPlayerMapPosition = function() if mapPos then return { GetXY = function() return mapPos[1], mapPos[2] end } end end,
	}
	C_Timer = {
		NewTicker = function(_, fn, iterations)
			local t = { fn = fn, left = iterations }
			function t:Cancel() self.cancelled = true end
			table.insert(tickers, t)
			return t
		end,
		After = function(_, fn) table.insert(afters, fn) end,
	}
	-- Quest log and party: questLog = list of { questID, pushable, onQuest = { [unit] = bool } }
	C_QuestLog = {
		GetNumQuestLogEntries = function() return #questLog end,
		GetInfo = function(i) local q = questLog[i]; return q and { questID = q.questID, isHeader = q.header } end,
		GetLogIndexForQuestID = function(id) for i, q in ipairs(questLog) do if q.questID == id then return i end end end,
		IsPushableQuest = function(id) for _, q in ipairs(questLog) do if q.questID == id then return q.pushable end end return false end,
		IsUnitOnQuest = function(unit, id)
			for _, q in ipairs(questLog) do if q.questID == id then return (q.onQuest or {})[unit] or false end end
			return (questOffers[id] or {})[unit] or false
		end,
	}
	function QuestLogPushQuest(index) table.insert(log.pushed, questLog[index].questID) end
	function IsInGroup() return group.kind ~= nil end
	-- Profile strings: a tiny stand-in for CBOR/compress/base64 that round-trips Lua tables.
	local function Ser(v)
		if type(v) == "table" then
			local parts = {}
			for k, x in pairs(v) do parts[#parts + 1] = "[" .. Ser(k) .. "]=" .. Ser(x) end
			return "{" .. table.concat(parts, ",") .. "}"
		end
		return type(v) == "string" and ("%q"):format(v) or tostring(v)
	end
	C_EncodingUtil = {
		SerializeCBOR = Ser,
		DeserializeCBOR = function(s) return assert(loadstring("return " .. s))() end,
		CompressString = function(s) return "Z" .. s end,
		DecompressString = function(s) assert(s:sub(1, 1) == "Z", "bad data"); return s:sub(2) end,
		EncodeBase64 = function(s) return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end,
		DecodeBase64 = function(s)
			assert(#s % 2 == 0 and not s:find("[^0-9a-f]"), "bad base64")
			return (s:gsub("..", function(h) return string.char(tonumber(h, 16)) end))
		end,
	}

	-- Settings API: record what gets registered; settings read/write their table like the real one.
	local nextId = 0
	local function NewCategory(name, parent)
		nextId = nextId + 1
		local layout = { initializers = {} }
		function layout:AddInitializer(init) table.insert(self.initializers, init) end
		local c = { name = name, id = nextId, parent = parent, layout = layout, controls = {} }
		function c:GetID() return self.id end
		table.insert(log.categories, c)
		return c, layout
	end
	local function NewSetting(var, get, set)
		local s = { var = var, GetValue = get, SetValue = function(self, v) set(v); if self.cb then self.cb(self, v) end end }
		function s:SetValueChangedCallback(fn) self.cb = fn end
		assert(not log.settings[var], "setting registered twice: " .. var)
		log.settings[var] = s
		return s
	end
	SettingsPanel = { shown = false }
	function SettingsPanel:IsShown() return self.shown end
	function SettingsPanel:Close() self.shown = false; log.settingsClosed = log.settingsClosed + 1 end
	function SettingsPanel:GetLayout(c) return c.layout end
	Settings = {
		VarType = { Boolean = "boolean", String = "string", Number = "number" },
		RegisterVerticalLayoutCategory = function(name) return NewCategory(name) end,
		RegisterVerticalLayoutSubcategory = function(parent, name) return NewCategory(name, parent) end,
		RegisterAddOnSetting = function(_, var, key, tbl, _, _, default)
			if tbl[key] == nil then tbl[key] = default end
			return NewSetting(var, function() return tbl[key] end, function(v) tbl[key] = v end)
		end,
		RegisterProxySetting = function(_, var, _, _, _, get, set) return NewSetting(var, get, set) end,
		RegisterAddOnCategory = function(c) log.registered = c.name end,
		CreateCheckbox = function(c, s) table.insert(c.controls, s.var) end,
		CreateDropdown = function(c, s, options) table.insert(c.controls, s.var); log.options = log.options or {}; log.options[s.var] = options end,
		CreateSlider = function(c, s) table.insert(c.controls, s.var) end,
		CreateSliderOptions = function() return { SetLabelFormatter = function() end } end,
		CreateControlTextContainer = function()
			local c = { data = {} }
			function c:Add(v, l) table.insert(self.data, { value = v, label = l }) end
			function c:GetData() return self.data end
			return c
		end,
		OpenToCategory = function(id) log.opened = id end,
	}
	function CreateSettingsButtonInitializer(name, buttonText, click) return { kind = "button", name = name, buttonText = buttonText, click = click } end
	function CreateSettingsListSectionHeaderInitializer(name) return { kind = "header", name = name } end
	MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
end

---------------------------------------------------------------------------
-- Loading like the game: each addon's files in TOC order, then ADDON_LOADED.
---------------------------------------------------------------------------
local ADDONS = { "StzxUI", "StzxUI_Social", "StzxUI_Info", "StzxUI_UnitFrames", "StzxUI_Quests", "StzxUI_Runs" }
local function LoadAddon(folder)
	local toc = assert(io.open(folder .. "/" .. folder .. ".toc")):read("*a")
	local ns = {}
	for line in toc:gmatch("[^\r\n]+") do
		if line:match("%.lua$") then assert(loadfile(folder .. "/" .. line))(folder, ns) end
	end
	Fire("ADDON_LOADED", folder)
end
local function StartGame(savedDB)
	ResetLog()
	InstallClient()
	StzxUI, StzxUIDB = nil, savedDB
	for _, folder in ipairs(ADDONS) do LoadAddon(folder) end
	Fire("PLAYER_LOGIN")
end
local function Reload() StartGame(StzxUIDB) end

-- Helpers for the settings UI
local function Category(name) for _, c in ipairs(log.categories) do if c.name == name then return c end end end
local function Button(categoryName, label)
	for _, init in ipairs(Category(categoryName).layout.initializers) do
		if init.kind == "button" and init.name == label then return init end
	end
end
local function DialogText() return StzxUIDialog and StzxUIDialog.text.text or "" end
local function DialogShown() return StzxUIDialog and StzxUIDialog.shown end
local function DialogAccept(input)
	if input then
		if StzxUIDialog.options.input == "line" then StzxUIDialog.line:SetText(input) else StzxUIDialog.box:SetText(input) end
	end
	StzxUIDialog.acceptButton:Click()
end

units.player = { name = "Strikezx", surname = "Kincrag", isPlayer = true, isSelf = true }
unitState.player = { class = "SHAMAN", hp = 530, hpMax = 700, power = 18200, powerMax = 22000, level = 18 }
local CHAR = "Strikezx Kincrag - Testrealm"

---------------------------------------------------------------------------
-- 1. Upgrade from the first release's saved settings
---------------------------------------------------------------------------
StartGame({ core = { chatMessages = false }, modules = { Social = { thankMode = "WHISPER", thankCooldown = 7 } } })
check(StzxUIDB.version == 2, "saved settings upgraded to version 2")
check(StzxUIDB.modules == nil, "old module settings moved out")
check(StzxUIDB.profiles.Default.modules.Social.thankMode == "WHISPER", "your Social choices kept in the Default profile")
check(StzxUIDB.profiles.Default.modules.Social.thankCooldown == 7, "your cooldown kept")
check(StzxUIDB.core.chatMessages == false and StzxUIDB.core.snapToGrid == true and StzxUIDB.core.gridSize == 16, "core options kept, new ones added")
check(StzxUIDB.profileKeys[CHAR] == "Default", "character uses Default, keyed with surname and realm")
check(StzxUI:GetModule("Social").db.thankMode == "WHISPER", "Social reads the profile")

---------------------------------------------------------------------------
-- 2. Fresh install: modules, settings pages, sections
---------------------------------------------------------------------------
StartGame(nil)
local Social, Info = StzxUI:GetModule("Social"), StzxUI:GetModule("Info")
check(StzxUI.version == "dev", "version placeholder shows as dev")
check(Social.enabled and Info.enabled, "Social and Info started")
check(log.registered == "StzxUI", "settings registered at login")
check(Category("Social") and Category("Info") and Category("Profiles"), "Social, Info and Profiles pages exist")
check(log.settings.STZXUI_SECTION_SOCIAL and log.settings.STZXUI_SECTION_INFO, "a section switch per module")
check(Button("StzxUI", "Move StzxUI frames"), "move mode button on the main page")
check(log.settings.STZXUI_CORE_SNAPTOGRID and log.settings.STZXUI_CORE_GRIDSIZE, "snap and grid size options")

---------------------------------------------------------------------------
-- 3. Social still works
---------------------------------------------------------------------------
Fire("DUEL_REQUESTED", "Grumpy Orcface")
check(log.cancelled == 1 and log.hidden[1] == "DUEL_REQUESTED", "duel declined and popup hidden")
check(lastPrint():find("Grumpy Orcface", 1, true), "declined duel announced")
Social.db.declineDeathDuels = false
Fire("DUEL_TO_THE_DEATH_REQUESTED", "Someone Else")
check(log.cancelled == 1, "death duel left alone when that option is off")
Fire("DUEL_REQUESTED", SECRET)
check(log.cancelled == 2 and lastPrint():find("someone", 1, true), "secret name still declines")

units.nameplate1 = { name = "Petra", surname = "Stonewell", isPlayer = true }
units.party1 = { name = "Buddy", surname = "Pal", isPlayer = true, inParty = true }
local function Buffed(source, helpful)
	Fire("UNIT_AURA", "player", { addedAuras = { { isHelpful = helpful ~= false, sourceUnit = source } } })
end
Buffed("nameplate1")
check(log.emotes[1] == "THANK>Petra Stonewell", "emote thanks with the full two-part name")
now = now + 30; Buffed("nameplate1")
check(#log.emotes == 1, "same player not thanked inside the cooldown")
now = now + 600; Buffed("party1"); Buffed("player")
check(#log.emotes == 1, "party and self not thanked")
inCombat = true; Buffed("nameplate1"); inCombat = false
check(#log.emotes == 1, "no thanks in combat")
Social.db.thankMode = "WHISPER"; Buffed("nameplate1")
check(log.whispers[1] == "WHISPER>Petra Stonewell>Thanks for the buff, Petra!", "whisper to full name")

---------------------------------------------------------------------------
-- 4. Info readouts
---------------------------------------------------------------------------
local stats, coords = StzxUIInfoStats, StzxUIInfoCoords
check(stats.text.text:find("60 fps", 1, true) and stats.text.text:find("61 ms", 1, true), "stats show fps and the higher latency")
mapPos = { 0.4523, 0.6781 }; for _, t in ipairs(tickers) do t.fn(t) end
check(coords.text.text == "45.2, 67.8", "coordinates shown to one decimal")
mapPos = nil; for _, t in ipairs(tickers) do t.fn(t) end
check(coords.text.text == "--, --", "coordinates blank where the game hides them")
log.settings.STZXUI_INFO_SHOWCOORDS:SetValue(false)
check(not coords.shown and tickers[#tickers].fn ~= nil, "coordinates hide when switched off")
log.settings.STZXUI_INFO_SHOWCOORDS:SetValue(true)
check(coords.shown, "and come back when switched on")

---------------------------------------------------------------------------
-- 5. Move mode
---------------------------------------------------------------------------
local statsHolder = StzxUI.movers.InfoStats
check(statsHolder and StzxUI.movers.InfoCoords, "both readouts are movable")
check(stats.points[1].rel == statsHolder, "readout follows its holder")
check(statsHolder:GetTop() == SCREEN_H - 8, "default spot used before any move")

inCombat = true; SlashCmdList.STZXUI("move"); inCombat = false
check(not StzxUI.moveMode and lastPrint():find("combat", 1, true), "move mode refused in combat")

SettingsPanel.shown = true
Button("StzxUI", "Move StzxUI frames").click()
check(StzxUI.moveMode and log.settingsClosed == 1, "Unlock button opens move mode and closes the options")
check(statsHolder.overlay.shown and StzxUIMoveToolbar.shown, "boxes and toolbar shown")
check(StzxUIMoveToolbar.snap:GetChecked() == true, "toolbar shows snapping on")

local function DragTo(holder, left, top)
	Script(holder.overlay, "OnDragStart")
	holder:ClearAllPoints()
	holder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	Script(holder.overlay, "OnDragStop")
end
StzxUIDB.core.snapToFrames = false -- grid only for these checks
DragTo(statsHolder, 805, 455) -- 5,5 from centre
local pos = StzxUI.profile.positions.InfoStats
check(pos.x == 0 and pos.y == 0, "drop snaps to the 16-unit grid")
check(statsHolder:GetLeft() == 800 and statsHolder:GetTop() == 450, "holder re-placed on the grid")
shiftDown = true; DragTo(statsHolder, 805, 455); shiftDown = false
check(pos ~= StzxUI.profile.positions.InfoStats and StzxUI.profile.positions.InfoStats.x == 5, "Shift-drag places freely")
Script(statsHolder.overlay, "OnEnter")
check(statsHolder.overlay.keyboard and statsHolder.overlay.propagate == true, "hover takes arrow keys, other keys still reach the game")
Script(statsHolder.overlay, "OnKeyDown", "UP")
check(StzxUI.profile.positions.InfoStats.y == 6 and statsHolder.overlay.propagate == false, "arrow nudges 1 unit")
shiftDown = true; Script(statsHolder.overlay, "OnKeyDown", "RIGHT"); shiftDown = false
check(StzxUI.profile.positions.InfoStats.x == 21, "Shift-arrow nudges one grid step")
Script(statsHolder.overlay, "OnKeyDown", "W")
check(statsHolder.overlay.propagate == true, "other keys pass through")
Script(statsHolder.overlay, "OnLeave")
check(not statsHolder.overlay.keyboard, "keys released when the mouse leaves")
Script(statsHolder.overlay, "OnClick", "RightButton")
check(StzxUI.profile.positions.InfoStats == nil and statsHolder:GetTop() == SCREEN_H - 8, "right-click resets one frame")

StzxUIMoveToolbar.gridButton:Click()
check(StzxUIDB.core.gridSize == 32, "grid button steps to 32")
DragTo(statsHolder, 800 + 40, 450 + 40)
check(StzxUI.profile.positions.InfoStats.x == 32, "snapping uses the new grid size")
StzxUIMoveToolbar.snap:SetChecked(false); Script(StzxUIMoveToolbar.snap, "OnClick")
DragTo(statsHolder, 803, 452)
check(StzxUI.profile.positions.InfoStats.x == 3, "snapping can be switched off")
StzxUIDB.core.snapToGrid = true

-- Snap to other frames: the target frame's left edge is at 985.
StzxUIDB.core.snapToFrames = true
DragTo(statsHolder, 808, 760) -- right edge lands at 978, 7 short of 985 (height clear of the group frames)
check(statsHolder:GetLeft() + statsHolder:GetWidth() == 985, "right edge lines up with a nearby frame's edge")
check(StzxUI.profile.positions.InfoStats.y % 16 == 0, "the other direction still snaps to the grid")
local playerHolder = StzxUI.movers.PlayerFrame
DragTo(StzxUI.movers.PlayerCastBar, playerHolder:GetLeft() + 4, playerHolder:GetTop() - playerHolder:GetHeight() - 3)
check(StzxUI.movers.PlayerCastBar:GetLeft() == playerHolder:GetLeft()
	and StzxUI.movers.PlayerCastBar:GetTop() == playerHolder:GetTop() - playerHolder:GetHeight(),
	"cast bar dropped under the player frame lines up with it")
shiftDown = true; DragTo(statsHolder, 808, 600); shiftDown = false
check(statsHolder:GetLeft() == 808, "Shift ignores frame snapping too")

-- Mouse wheel resizes
local frameHolder = StzxUI.movers.PlayerFrame
local topBefore, leftBefore = frameHolder:GetTop(), frameHolder:GetLeft()
Script(frameHolder.overlay, "OnMouseWheel", 1)
Script(frameHolder.overlay, "OnMouseWheel", 1)
check(StzxUI.profile.scales.PlayerFrame == 1.1 and StzxUIPlayerFrame.scale == 1.1, "mouse wheel up makes the frame 10% bigger")
check(math.abs(frameHolder:GetWidth() - 230 * 1.1) < 0.01, "its box grows with it")
check(frameHolder:GetTop() == topBefore and frameHolder:GetLeft() == leftBefore, "top-left corner stays put")
check(frameHolder.overlay.label.text:find("110%", 1, true), "box shows the new size")
for _ = 1, 30 do Script(frameHolder.overlay, "OnMouseWheel", -1) end
check(StzxUI.profile.scales.PlayerFrame == 0.5, "can't shrink below half size")
Script(frameHolder.overlay, "OnClick", "RightButton")
check(StzxUI.profile.scales.PlayerFrame == nil and StzxUIPlayerFrame.scale == 1, "right-click also resets the size")

-- "Show" filter on the toolbar
local filters = {}
for _, f in ipairs(StzxUIMoveToolbar.filters) do if f.shown then filters[f.category] = f end end
check(filters.Info and filters["Unit frames"], "a Show switch for Info and for Unit frames")
filters.Info:SetChecked(false); Script(filters.Info, "OnClick")
check(not statsHolder.overlay.shown and frameHolder.overlay.shown, "unticking Info hides only Info's boxes")
check(StzxUIDB.core.hiddenCategories.Info == true, "the choice is remembered")
filters.Info:SetChecked(true); Script(filters.Info, "OnClick")
check(statsHolder.overlay.shown and StzxUIDB.core.hiddenCategories.Info == nil, "ticking brings them back")
StzxUI:ResetMover("InfoStats"); StzxUI:ResetMover("PlayerCastBar")

DragTo(StzxUI.movers.InfoCoords, 700, 300)
-- "Reset all" asks first
local resetAll
for _, f in ipairs(frames) do if f.text == "Reset all" and f.scripts.OnClick then resetAll = f end end
resetAll:Click()
check(DialogShown() and DialogText():find("every StzxUI frame", 1, true), "Reset all asks first")
DialogAccept()
check(next(StzxUI.profile.positions) == nil and not DialogShown(), "Reset all clears every position")

log.settings.STZXUI_INFO_SHOWSTATS:SetValue(false)
StzxUI:ExitMoveMode(); StzxUI:EnterMoveMode()
check(not statsHolder.overlay.shown and StzxUI.movers.InfoCoords.overlay.shown, "hidden readouts have no box")
log.settings.STZXUI_INFO_SHOWSTATS:SetValue(true)

Fire("PLAYER_REGEN_DISABLED")
check(not StzxUI.moveMode and not StzxUIMoveToolbar.shown and not StzxUI.movers.InfoCoords.overlay.shown, "combat closes move mode")
SlashCmdList.STZXUI("move")
check(StzxUI.moveMode, "/stzx move opens it")
StzxUIMoveToolbar:Hide() -- what Escape does
check(not StzxUI.moveMode, "Escape closes it")

-- Moving in combat waits until combat ends
DragTo(statsHolder, 900, 500) -- (out of move mode the script still works in the fake)
local leftBefore = statsHolder:GetLeft()
inCombat = true
StzxUI:ResetMover("InfoStats")
check(statsHolder:GetLeft() == leftBefore and leftBefore ~= nil, "no re-placing in combat")
inCombat = false; Fire("PLAYER_REGEN_ENABLED")
check(statsHolder:GetTop() == SCREEN_H - 8, "re-placed when combat ends")

-- Positions survive a reload
DragTo(statsHolder, 800 + 64, 450 - 32)
Reload()
statsHolder = StzxUI.movers.InfoStats
check(statsHolder:GetLeft() == 864 and statsHolder:GetTop() == 418, "positions kept after /reload")

---------------------------------------------------------------------------
-- 6. Profiles
---------------------------------------------------------------------------
check(select(2, StzxUI:CheckProfileName("   ")) == "Type a name first.", "empty name refused")
check(select(2, StzxUI:CheckProfileName("Default")):find("already", 1, true), "duplicate name refused")
check(select(2, StzxUI:CheckProfileName(("x"):rep(40))):find("under", 1, true), "long name refused")

Button("Profiles", "New profile from this one").click()
DialogAccept("   ")
check(DialogShown() and StzxUIDialog.problem.text == "Type a name first.", "dialog stays open and explains a bad name")
DialogAccept("Healing")
check(StzxUIDB.profiles.Healing and StzxUIDB.profileKeys[CHAR] == "Healing", "new profile created and chosen")
check(DialogShown() and DialogText():find("Reload", 1, true), "reload prompt stays open after creating (bug fix)")
check(StzxUIDB.profiles.Healing.positions.InfoStats.x == 64, "new profile is a copy")
check(StzxUIDB.profiles.Healing.positions ~= StzxUIDB.profiles.Default.positions, "and a separate copy")
DialogAccept()
check(log.reloads == 1, "Reload now reloads")
Reload()
check(StzxUI.profileName == "Healing" and StzxUI.movers.InfoStats:GetLeft() == 864, "after reload the new profile is live")
DragTo(StzxUI.movers.InfoStats, 800, 450)
check(StzxUIDB.profiles.Default.positions.InfoStats.x == 64, "moving in one profile leaves the other alone")

log.settings.STZXUI_PROFILE_ACTIVE:SetValue("Default")
check(StzxUIDB.profileKeys[CHAR] == "Default" and DialogShown(), "switching back via the dropdown asks to reload")
check(#log.options.STZXUI_PROFILE_ACTIVE() == 2 and log.options.STZXUI_PROFILE_ACTIVE()[1].value == "Default", "dropdown lists Default first")
StzxUIDialog.cancelButton:Click()

-- Export, then import as a new profile
local exported = StzxUI:ExportProfile()
check(type(exported) == "string" and exported:sub(1, 7) == "!STZX1!", "export makes a StzxUI string")
Button("Profiles", "Import a profile").click()
DialogAccept("hello")
check(DialogShown() and StzxUIDialog.problem.text:find("isn't a StzxUI", 1, true), "foreign text refused")
DialogAccept("!STZX1!zz")
check(StzxUIDialog.problem.text:find("damaged", 1, true), "damaged string refused")
DialogAccept("  " .. exported .. "\n")
check(StzxUIDB.profiles.Imported and StzxUIDB.profiles.Imported.positions.InfoStats.x == 0, "import creates 'Imported' with the shared positions")
check(StzxUIDB.profileKeys[CHAR] == "Imported", "and switches to it")
StzxUIDialog.cancelButton:Click()
check(StzxUI:ImportProfile(exported) == "Imported 2", "a second import gets its own name")

-- Delete
StzxUIDB.profileKeys["Alt Character - Testrealm"] = "Healing"
check(StzxUI:DeleteProfile("Default") == false, "Default can't be deleted")
Button("Profiles", "Delete this profile").click() -- current live profile is Healing
DialogAccept()
check(StzxUIDB.profiles.Healing == nil and StzxUIDB.profileKeys["Alt Character - Testrealm"] == "Default", "deleted; characters using it fall back to Default")
check(DialogShown() and DialogText():find("Reload", 1, true), "deleting the live profile asks to reload")
StzxUIDialog.cancelButton:Click()

-- Reset
StzxUIDB.profileKeys[CHAR] = "Default"
Reload()
StzxUI:GetModule("Social").db.thankMode = "WHISPER"
Button("Profiles", "Reset this profile").click()
DialogAccept()
check(next(StzxUIDB.profiles.Default.modules) == nil and next(StzxUIDB.profiles.Default.positions) == nil, "reset empties the profile")
Reload()
check(StzxUI:GetModule("Social").db.thankMode == "EMOTE", "defaults back after reload")

---------------------------------------------------------------------------
-- 7. Sections on/off
---------------------------------------------------------------------------
log.settings.STZXUI_SECTION_INFO:SetValue(false)
check(StzxUIDB.profiles.Default.enabled.Info == false and DialogShown(), "switching Info off is saved and asks to reload")
log.settings.STZXUI_SECTION_UNITFRAMES:SetValue(false)
log.settings.STZXUI_SECTION_GROUPFRAMES:SetValue(false)
log.settings.STZXUI_SECTION_RUNS:SetValue(false)
Reload()
check(not StzxUI:GetModule("Info").active and StzxUI.movers.InfoStats == nil and not Category("Info"), "Info stays off: no frames, no page")
check(log.settings.STZXUI_SECTION_INFO:GetValue() == false, "its switch shows off")
SlashCmdList.STZXUI("move")
check(not StzxUI.moveMode and lastPrint():find("nothing to move", 1, true), "move mode explains when there's nothing to move")
log.settings.STZXUI_SECTION_INFO:SetValue(true)
log.settings.STZXUI_SECTION_UNITFRAMES:SetValue(true)
log.settings.STZXUI_SECTION_GROUPFRAMES:SetValue(true)
log.settings.STZXUI_SECTION_RUNS:SetValue(true)
check(StzxUIDB.profiles.Default.enabled.Info == nil, "switching on clears the flag")
Reload()
check(StzxUI:GetModule("Info").enabled and StzxUI.movers.InfoStats, "Info back after reload")

---------------------------------------------------------------------------
-- 9. Unit frames
---------------------------------------------------------------------------
StartGame(nil)
local UF = StzxUI:GetModule("UnitFrames")
local P, T = StzxUIPlayerFrame, StzxUITargetFrame
check(UF.enabled and P and T, "player and target frames built")
check(P.attributes.unit == "player" and P.attributes["*type1"] == "target" and P.attributes["*type2"] == "togglemenu",
	"player frame: left-click targets, right-click opens the menu")
check(T.unitWatch and not P.unitWatch, "target frame shows only while you have a target")
check(Category("Unit Frames") and log.settings.STZXUI_UNITFRAMESPLAYER_HEALTHTEXT, "Unit Frames settings page")
for _, key in ipairs({ "PlayerFrame", "PlayerCastBar", "TargetFrame", "TargetCastBar" }) do
	check(StzxUI.movers[key] and StzxUI.movers[key].category == "Unit frames", key .. " is movable under Unit frames")
end

-- Player frame contents
check(P.nameText.text == "Strikezx Kincrag", "name with surname")
check(P.healthText.text == "530 | 76%", "health shows number and percent")
check(P.health.max == 700 and P.health.value == 530, "health bar filled from health")
check(P.powerText.text == "18.2K / 22.0K", "power shows current / maximum")
check(P.portrait.badge.text.text == "18", "level badge")
check(P.portrait.icon.shown and not P.portrait.face.shown and P.portrait.icon.texCoord[1] == 0.25, "class icon portrait")
check(P.health.colour[1] == 0 and P.health.colour[3] == 0.87, "health in class colour")
check(not P.health.reverse and T.health.reverse, "target mirrors the player frame")

log.settings.STZXUI_UNITFRAMESPLAYER_HEALTHTEXT:SetValue("NUMBER")
check(P.healthText.text == "530", "health text: number")
log.settings.STZXUI_UNITFRAMESPLAYER_HEALTHTEXT:SetValue("PERCENT")
check(P.healthText.text == "76%", "health text: percent")
log.settings.STZXUI_UNITFRAMESPLAYER_HEALTHTEXT:SetValue("NONE")
check(P.healthText.text == "", "health text: none")
log.settings.STZXUI_UNITFRAMESPLAYER_HEALTHTEXT:SetValue("BOTH")
log.settings.STZXUI_UNITFRAMESPLAYER_PORTRAIT:SetValue("PORTRAIT")
check(P.portrait.face.shown and P.portrait.face.portraitOf == "player" and P.portrait.face.mask, "character portrait, round")
log.settings.STZXUI_UNITFRAMESPLAYER_PORTRAIT:SetValue("NONE")
check(not P.portrait.shown, "portrait can be switched off")
log.settings.STZXUI_UNITFRAMESPLAYER_PORTRAIT:SetValue("ICON")
log.settings.STZXUI_UNITFRAMESPLAYER_POWERTEXT:SetValue(false)
check(P.powerText.text == "", "power numbers can be switched off")
log.settings.STZXUI_UNITFRAMES_HEALTHCOLOUR:SetValue("GREEN")
check(P.health.colour[2] == 0.76, "health colour: green")
log.settings.STZXUI_UNITFRAMES_HEALTHCOLOUR:SetValue("CLASS")

-- Live updates and secret values (combat)
unitState.player.hp = 350; Fire("UNIT_HEALTH", "player")
check(P.healthText.text == "350 | 50%", "health text updates on UNIT_HEALTH")
unitState.player.hp = SECRET; Fire("UNIT_HEALTH", "player")
check(P.health.value == SECRET and P.healthText.text == SECRET_TEXT, "secret health goes straight to the bar and text, no errors")
unitState.player.hp = 530
unitState.player.dead = true; Fire("UNIT_HEALTH", "player")
check(P.healthText.text == "Dead" and P.health.colour[1] == 0.4, "dead shows Dead, grey")
unitState.player.dead = false; Fire("UNIT_HEALTH", "player")

-- Target: an elite hostile NPC
units.target = { name = "Murloc Raider", isPlayer = false }
unitState.target = { hp = 120, hpMax = 480, reaction = 2, level = 17, classification = "elite", power = 0, powerMax = 0 }
Fire("PLAYER_TARGET_CHANGED")
check(T.nameText.text == "Murloc Raider", "target name without surname")
check(T.healthText.text == "120 | 25%" and T.health.colour[1] == 0.85, "hostile target in red")
check(T.portrait.badge.text.text == "17+", "elite level badge")
check(T.portrait.face.shown and T.portrait.face.portraitOf == "target", "NPCs show their face even in icon mode")
check(T.powerText.text == "", "no power numbers when the unit has no power")
unitState.target.tapped = true; Fire("UNIT_FLAGS", "target")
check(T.health.colour[1] == 0.55, "tapped target turns grey")
unitState.target.level = -1; Fire("UNIT_LEVEL", "target")
check(T.portrait.badge.text.text == "??+", "skull-level target shows ??")
units.target = { name = "Wrenzx", surname = SECRET, isPlayer = true }
unitState.target = { class = "DRUID", hp = 100, hpMax = 100, level = 18 }
Fire("PLAYER_TARGET_CHANGED")
check(T.nameText.text == SECRET_TEXT, "a secret surname is shown, not tested")
check(T.portrait.icon.shown and T.health.colour[1] == 1, "player target: class icon and class colour")

-- Cast bars
local PC, TC = StzxUIPlayerFrameCastBar, StzxUITargetFrameCastBar
local function Updates(seconds) local steps = math.floor(seconds / 0.1 + 0.5) for _ = 1, steps do now = now + 0.1 if PC.shown then PC.scripts.OnUpdate(PC, 0.1) end if TC.shown then TC.scripts.OnUpdate(TC, 0.1) end end end
casting.player = { name = "Healing Wave", texture = 136052, startMS = now * 1000, endMS = (now + 2) * 1000, castID = "cast-1" }
Fire("UNIT_SPELLCAST_START", "player", "cast-1")
check(PC.shown and PC.text.text == "Healing Wave" and PC.icon.texture == 136052, "player cast bar shows the spell")
Updates(0.5)
check(math.abs(PC.bar.value - 0.5) < 0.01 and PC.time.text == "1.5", "fills and counts down")
Fire("UNIT_SPELLCAST_STOP", "player", "old-cast")
check(PC.active, "the stop of an older cast is ignored")
casting.player = nil
Fire("UNIT_SPELLCAST_STOP", "player", "cast-1")
check(not PC.active and PC.shown, "cast done: starts fading")
Updates(0.5)
check(not PC.shown, "and is gone after the fade")
Fire("UNIT_SPELLCAST_FAILED", "player", "cast-2")
check(not PC.shown, "a failed attempt with no cast running shows nothing")

casting.player = { name = "Tranquility", startMS = now * 1000, endMS = (now + 4) * 1000, channel = true }
Fire("UNIT_SPELLCAST_CHANNEL_START", "player")
Updates(1)
check(math.abs(PC.bar.value - 3) < 0.01, "channels drain")
Fire("UNIT_SPELLCAST_INTERRUPTED", "player")
check(PC.text.text == "Interrupted" and PC.bar.colour[1] == 0.85, "interrupted: red with the reason")
Updates(1.2)
check(not PC.shown, "then fades")

casting.target = { name = "Shadow Bolt", startMS = SECRET, endMS = SECRET, castID = SECRET, notInterruptible = SECRET }
Fire("UNIT_SPELLCAST_START", "target", SECRET)
check(TC.shown and TC.bar.min == SECRET and TC.time.text == "", "secret cast times: bar still fills, no countdown")
Updates(0.3)
check(type(TC.bar.value) == "number", "bar is fed the clock")
Fire("UNIT_SPELLCAST_STOP", "target", SECRET)
check(not TC.active, "secret cast ends on its stop event")
casting.target = nil

log.settings.STZXUI_UNITFRAMESPLAYER_CASTBAR:SetValue(false)
casting.player = { name = "Healing Wave", startMS = now * 1000, endMS = (now + 2) * 1000, castID = "c3" }
Fire("UNIT_SPELLCAST_START", "player", "c3")
check(not PC.shown, "cast bar switched off stays hidden")
StzxUI:EnterMoveMode()
check(not StzxUI.movers.PlayerCastBar.overlay.shown and StzxUI.movers.PlayerFrame.overlay.shown, "and has no box in move mode")
StzxUI:ExitMoveMode()
log.settings.STZXUI_UNITFRAMESPLAYER_CASTBAR:SetValue(true)
casting.player = nil

-- Blizzard's frames
check(blizzard.PlayerFrame.parent ~= UIParent and not blizzard.PlayerFrame:IsVisible() and next(blizzard.PlayerFrame.events) == nil,
	"Blizzard's player frame hidden and silenced")
check(not blizzard.TargetFrame:IsVisible() and not blizzard.PlayerCastingBarFrame:IsVisible(), "Blizzard's target frame and cast bar hidden")

StzxUIDB.profiles.Default.modules.UnitFrames.hideBlizzard = false
Reload()
check(blizzard.PlayerFrame:IsVisible(), "with the option off, Blizzard's frames stay")
StzxUIDB.profiles.Default.modules.UnitFrames.hideBlizzard = true

-- Switching off the target frame (after reload) leaves Blizzard's target alone
StzxUIDB.profiles.Default.modules.UnitFrames.target.enabled = false
Reload()
check(StzxUITargetFrame == nil or not StzxUI.movers.TargetFrame, "no StzxUI target frame")
check(blizzard.TargetFrame:IsVisible() and not blizzard.PlayerFrame:IsVisible(), "Blizzard's target frame kept, player still hidden")
StzxUIDB.profiles.Default.modules.UnitFrames.target.enabled = true

-- Logging in mid-fight: frames wait for combat to end
inCombat = true
Reload()
check(StzxUI.movers.PlayerFrame == nil and lastPrint():find("combat ends", 1, true), "in combat: frames wait")
inCombat = false; Fire("PLAYER_REGEN_ENABLED")
check(StzxUI.movers.PlayerFrame and StzxUIPlayerFrame.shown, "built when combat ends")

---------------------------------------------------------------------------
-- 10. Accent colour
---------------------------------------------------------------------------
check(StzxUI.ACCENT.b == 0.97, "StzxUI blue by default")
log.settings.STZXUI_CORE_ACCENT:SetValue("CLASS")
check(DialogShown() and DialogText():find("after a reload", 1, true), "changing the accent asks to reload")
Reload()
check(StzxUI.ACCENT.r == 0 and StzxUI.ACCENT.b == 0.87, "class accent: Shaman blue")
StzxUIDB.core.accent = "STZX"
Reload()
check(StzxUI.ACCENT.r == 0.31, "back to StzxUI blue")

---------------------------------------------------------------------------
-- 11. JiberishUI Icons (optional addon)
---------------------------------------------------------------------------
local function PortraitChoices()
	local values = {}
	for _, o in ipairs(log.options.STZXUI_UNITFRAMESPLAYER_PORTRAIT()) do values[o.value] = o.label end
	return values
end
check(PortraitChoices()["JI:fabled"] == nil and PortraitChoices().ICON, "without Jiberish: only StzxUI's portrait choices")
StzxUIDB.profiles.Default.modules.UnitFrames.player.portrait = "JI:fabledrealm"
Reload()
check(StzxUIPlayerFrame.portrait.icon.shown and StzxUIPlayerFrame.portrait.icon.texCoord[1] == 0.25,
	"a saved Jiberish style with the addon gone falls back to the class icon")
jiberishInstalled = true
Reload()
local choices = PortraitChoices()
check(choices["JI:fabled"] == "Jiberish: Fabled" and choices["JI:fabledrealm"] and choices["JI:fabledazeroth"] == "Jiberish: Fabled Azeroth (race)",
	"with Jiberish: its class and race styles are listed")
local icon = StzxUIPlayerFrame.portrait.icon
check(icon.shown and icon.texture:find("fabledrealm", 1, true) and #icon.texCoord == 8, "player shows the Jiberish icon")
units.target = { name = "Murloc Raider", isPlayer = false }
unitState.target = { hp = 10, hpMax = 10, reaction = 2, level = 12 }
log.settings.STZXUI_UNITFRAMESTARGET_PORTRAIT:SetValue("JI:fabled")
Fire("PLAYER_TARGET_CHANGED")
check(StzxUITargetFrame.portrait.face.shown and not StzxUITargetFrame.portrait.icon.shown, "NPC target falls back to its face")
log.settings.STZXUI_UNITFRAMESPLAYER_PORTRAIT:SetValue("ICON")
check(StzxUIPlayerFrame.portrait.icon.texture:find("UI%-Classes%-Circles"), "back to the plain class icon")
log.settings.STZXUI_UNITFRAMESTARGET_PORTRAIT:SetValue("ICON")
jiberishInstalled = false

---------------------------------------------------------------------------
-- 12. Character key without a realm name (Forever returns "")
---------------------------------------------------------------------------
StzxUIDB.profiles.Old = { modules = {}, positions = {}, scales = {}, enabled = {} }
StzxUIDB.profileKeys = { ["Strikezx Kincrag - "] = "Old" } -- how version 2 saved it on Forever
realmName = ""
Reload()
check(StzxUI.charKey == "Strikezx Kincrag", "no realm: the key is just the name")
check(StzxUI.profileName == "Old" and StzxUIDB.profileKeys["Strikezx Kincrag - "] == nil, "old 'Name - ' key carried over")
realmName = "Forever"
Reload()
check(StzxUI.charKey == "Strikezx Kincrag - Forever" and StzxUI.profileName == "Old", "if a realm name appears later, the choice follows")
realmName = "Testrealm"
StzxUIDB.profileKeys = {}
Reload()

---------------------------------------------------------------------------
-- 13. Buffs and debuffs on the frames
---------------------------------------------------------------------------
units.target = { name = "Murloc Raider", isPlayer = false }
unitState.target = { hp = 100, hpMax = 100, reaction = 2, level = 12 }
auraState.player = {
	{ auraInstanceID = 1, icon = 135932, duration = 1800, expirationTime = now + 1200, applications = 0 },
	{ auraInstanceID = 2, icon = 136048, duration = 0, expirationTime = 0, applications = 0 },
}
auraState.target = {
	{ auraInstanceID = 11, icon = 136207, duration = 18, expirationTime = now + 9, applications = 3, dispelName = "Magic", harmful = true, mine = true },
	{ auraInstanceID = 12, icon = 132100, duration = 30, expirationTime = now + 20, applications = 1, harmful = true, mine = false },
	{ auraInstanceID = 13, icon = 135987, duration = 0, expirationTime = 0, applications = 0, harmful = false },
}
Reload()
local PA, TA = StzxUIPlayerFrame.auraContainer.buttons, StzxUITargetFrame.auraContainer.buttons
local function Shown(buttons) local n = 0 for _, b in ipairs(buttons) do if b.shown then n = n + 1 end end return n end
Fire("PLAYER_TARGET_CHANGED")
check(Shown(PA) == 2 and PA[1].icon.texture == 135932, "player buffs shown")
check(PA[1].cooldown.cooldownDuration == 1800 and PA[1].cooldown.cooldownStart == now + 1200 - 1800, "buff swipe from its duration")
check(not PA[2].cooldown.shown, "no swipe on a buff with no duration")
check(Shown(TA) == 3 and TA[1].icon.texture == 136207 and TA[3].icon.texture == 135987, "target: debuffs first, then buffs")
check(TA[1].count.text == 3 and TA[2].count.text == "", "stack count shown from 2 up")
check(TA[3].points[1].point == "BOTTOMRIGHT" and TA[3].points[1].y > 0, "target buffs start a new row, growing from the right")
log.settings.STZXUI_UNITFRAMESTARGET_ONLYMINE:SetValue(true)
check(Shown(TA) == 2 and TA[1].auraInstanceID == 11 and TA[2].auraInstanceID == 13, "only my debuffs (buffs still shown)")
log.settings.STZXUI_UNITFRAMESTARGET_ONLYMINE:SetValue(false)
log.settings.STZXUI_UNITFRAMESTARGET_SHOWBUFFS:SetValue(false)
check(Shown(TA) == 2, "buffs can be hidden")
log.settings.STZXUI_UNITFRAMESTARGET_SHOWDEBUFFS:SetValue(false)
check(Shown(TA) == 0, "debuffs can be hidden too")
log.settings.STZXUI_UNITFRAMESTARGET_SHOWBUFFS:SetValue(true)
log.settings.STZXUI_UNITFRAMESTARGET_SHOWDEBUFFS:SetValue(true)
log.settings.STZXUI_UNITFRAMESPLAYER_AURASIZE:SetValue(30)
check(PA[1].w == 30, "icon size option")
log.settings.STZXUI_UNITFRAMESPLAYER_AURAPOSITION:SetValue("BELOW")
check(StzxUIPlayerFrame.auraContainer.points[1].point == "TOPLEFT" and PA[1].points[1].point == "TOPLEFT", "auras can go below the frame")
log.settings.STZXUI_UNITFRAMESPLAYER_AURAPOSITION:SetValue("ABOVE")

-- A new debuff arrives in combat with every detail secret
table.insert(auraState.target, 1, { auraInstanceID = 14, icon = SECRET, duration = SECRET, expirationTime = SECRET,
	applications = SECRET, dispelName = SECRET, harmful = true })
Fire("UNIT_AURA", "target")
check(Shown(TA) == 4 and TA[1].icon.texture == SECRET, "secret aura still shows its icon")
check(TA[1].cooldown.durationObject and TA[1].cooldown.durationObject.durationOf == 14 and TA[1].cooldown.shown,
	"secret aura: swipe from the game's duration object")
check(TA[1].count.text == SECRET_TEXT, "secret aura: the game's own stack text")
Script(TA[1], "OnEnter")
check(GameTooltip.auraShown == 14, "hovering an icon shows the aura tooltip")
auraState.player, auraState.target = {}, {}
Fire("UNIT_AURA", "player"); Fire("UNIT_AURA", "target")
check(Shown(PA) == 0 and Shown(TA) == 0, "icons cleared when auras go")

---------------------------------------------------------------------------
-- 14. Focus, target-of-target and pet frames
---------------------------------------------------------------------------
Reload()
local F, TT, PET = StzxUIFocusFrame, StzxUITargetTargetFrame, StzxUIPetFrame
check(F and TT and PET and F.unitWatch and TT.unitWatch and PET.unitWatch, "focus, target-of-target and pet frames, shown only when the unit exists")
check(StzxUIFocusFrameCastBar and StzxUI.movers.FocusCastBar and not StzxUI.movers.TargetTargetCastBar, "focus has a cast bar; small frames don't")
check(TT.w == 130 and F.w == 230, "target-of-target is compact")
check(log.settings.STZXUI_UNITFRAMESFOCUS_ONLYMINE and not log.settings.STZXUI_UNITFRAMESPET_CASTBAR, "per-frame options fit each frame")
check(not TT.portrait.shown and TT.healthText.text ~= nil, "small frames start without a portrait")
units.focus = { name = "Defias Pillager", isPlayer = false }
unitState.focus = { hp = 300, hpMax = 600, reaction = 2, level = 15 }
Fire("PLAYER_FOCUS_CHANGED")
check(F.nameText.text == "Defias Pillager" and F.healthText.text == "300 | 50%", "focus frame fills in")
casting.focus = { name = "Fireball", startMS = now * 1000, endMS = (now + 3) * 1000, castID = "f1" }
Fire("UNIT_SPELLCAST_START", "focus", "f1")
check(StzxUIFocusFrameCastBar.shown and StzxUIFocusFrameCastBar.text.text == "Fireball", "focus cast bar")
casting.focus = nil
units.targettarget = { name = "Strikezx", surname = "Kincrag", isPlayer = true }
unitState.targettarget = { class = "SHAMAN", hp = 50, hpMax = 100 }
TT.scripts.OnUpdate(TT, 0.3)
check(TT.nameText.text == "Strikezx Kincrag" and TT.healthText.text == "50%", "target-of-target updates by itself")
unitState.targettarget.hp = 25
TT.scripts.OnUpdate(TT, 0.1)
check(TT.healthText.text == "50%", "...but not every frame")
TT.scripts.OnUpdate(TT, 0.2)
check(TT.healthText.text == "25%", "...a few times a second")
units.pet = { name = "Wolf", isPlayer = false }
unitState.pet = { hp = 80, hpMax = 100, reaction = 5, level = 18 }
Fire("UNIT_PET", "player")
check(PET.nameText.text == "Wolf" and PET.health.colour[2] == 0.76, "pet frame fills in, friendly green")
check(not blizzard.FocusFrame:IsVisible() and not blizzard.PetFrame:IsVisible() and not blizzard.TargetFrameToT:IsVisible(),
	"Blizzard's focus, pet and target-of-target frames hidden")
StzxUIDB.profiles.Default.modules.UnitFrames.focus.enabled = false
Reload()
check(not StzxUI.movers.FocusFrame and blizzard.FocusFrame:IsVisible(), "focus switched off: Blizzard's stays")
StzxUIDB.profiles.Default.modules.UnitFrames.focus.enabled = true
units.focus, units.targettarget, units.pet = nil, nil, nil
unitState.focus, unitState.targettarget, unitState.pet = nil, nil, nil

---------------------------------------------------------------------------
-- 15. Party and raid frames
---------------------------------------------------------------------------
StartGame(nil)
local PH, RH = StzxUIPartyHeader, StzxUIRaidHeader
check(PH and RH and StzxUI.movers.PartyFrames and StzxUI.movers.RaidFrames, "party and raid frames, each with a mover")
check(PH[5] and not PH[6] and RH[40] and not RH[41], "every button made up front, out of combat (5 party, 40 raid)")
check(PH[1].stzxStyled and RH[40].stzxStyled and PH[1].art, "every button styled")
check(PH.stateDriver.condition:find("[group:party] show", 1, true) and RH.stateDriver.condition == "[group:raid] show; hide",
	"party shows in a party, raid in a raid")
check(PH[1].configCode:find("SetWidth(150)", 1, true) and PH[1].configCode:find("togglemenu", 1, true),
	"buttons get their size and click actions in secure code")
check(PH.parent == StzxUIPartyFrames and StzxUIPartyFrames.h == 5 * 36 + 4 * 6, "header sits in a movable box sized for a full party")
check(Category("Party & Raid") and log.settings.STZXUI_GROUPPARTY_ONLYDISPELLABLE, "Party & Raid options page")
check(not blizzard.PartyFrame:IsVisible(), "Blizzard's party frames hidden")

-- Join a party.
units.party1 = { name = "Liala", surname = "Brightwood", isPlayer = true }
unitState.party1 = { class = "DRUID", hp = 300, hpMax = 400, power = 50, powerMax = 100, leader = true, marker = 8 }
units.party2 = { name = "Gorr", isPlayer = true }
unitState.party2 = { class = "SHAMAN", hp = 0, hpMax = 500, dead = true }
group.kind, group.units = "party", { "party1", "party2" }
PH:Show()
PH.headerUpdate(PH)
local me, liala, gorr = PH[1], PH[2], PH[3]
check(me.unit == "player" and liala.unit == "party1" and gorr.unit == "party2" and not PH[4].shown, "you first, then the party")
check(liala.nameText.text == "Liala Brightwood" and liala.healthText.text == "75%", "name with surname, health percent")
check(liala.health.colour[1] == 1 and liala.leader.shown and liala.marker.markerIndex == 8, "class colour, leader crown, raid marker")
check(gorr.healthText.text == "Dead", "dead members say so")
check(me.power.shown and me.power.max == 22000, "thin power bar")
unitState.party1.hp = 100
Fire("UNIT_HEALTH", "party1")
check(liala.healthText.text == "25%", "health updates by event")
auraState.party1 = {
	{ auraInstanceID = 71, icon = 136, duration = 10, expirationTime = now + 5, applications = 0, dispelName = "Magic", harmful = true },
	{ auraInstanceID = 72, icon = 137, duration = 0, expirationTime = 0, applications = 2, harmful = true },
	{ auraInstanceID = 73, icon = 138, duration = 0, expirationTime = 0, applications = 0, harmful = true },
	{ auraInstanceID = 74, icon = 139, duration = 0, expirationTime = 0, applications = 0, harmful = true },
}
Fire("UNIT_AURA", "party1")
check(liala.debuffs[1].shown and liala.debuffs[3].shown and not (liala.debuffs[4] and liala.debuffs[4].shown),
	"up to 3 debuffs on a party member")
check(liala.debuffs[1].auraInstanceID == 71 and liala.debuffs[2].count.text == 2, "debuff icons with stacks")
rangeOf.party1 = { false, true }
for _, f in ipairs(frames) do if f.scripts.OnUpdate and f.events.GROUP_ROSTER_UPDATE then f.scripts.OnUpdate(f, 1) end end
check(liala.art.alpha == 0.4 and me.art.alpha == 1, "out-of-range members fade (you never do)")
rangeOf.party1 = { SECRET, SECRET }
for _, f in ipairs(frames) do if f.scripts.OnUpdate and f.events.GROUP_ROSTER_UPDATE then f.scripts.OnUpdate(f, 1) end end
check(liala.art.alpha == "secret", "in combat the secret range check fades without being compared")
units.target = units.party1
function UnitIsUnit(a, b) return (a == "party1" and b == "target") or a == b end
Fire("PLAYER_TARGET_CHANGED")
check(liala.highlight.shown and not me.highlight.shown, "your target is highlighted")
unitState.party1.hp = SECRET
Fire("UNIT_HEALTH", "party1")
check(liala.healthText.text == "<secret>", "secret health is shown, not compared")

-- Settings apply straight away, out of combat.
local partyDB = StzxUIDB.profiles.Default.modules.GroupFrames.party
partyDB.width, partyDB.growth = 120, "RIGHT"
log.settings.STZXUI_GROUPPARTY_WIDTH:SetValue(120)
check(liala.w == 120 and PH:GetAttribute("point") == "LEFT" and StzxUIPartyFrames.w == 5 * 120 + 4 * 6,
	"width and growth change live")
inCombat = true
log.settings.STZXUI_GROUPPARTY_SPACING:SetValue(10)
check(PH:GetAttribute("xOffset") == 6, "...but wait while in combat")
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
check(PH:GetAttribute("xOffset") == 10, "...and catch up after")

-- A raid.
group.kind, group.units = "raid", {}
for i = 1, 12 do
	local u = "raid" .. i
	units[u] = { name = "Raider" .. i, isPlayer = true }
	unitState[u] = { class = "SHAMAN", hp = 50, hpMax = 100 }
	group.units[i] = u
end
RH:Show()
RH.headerUpdate(RH)
check(RH[12].unit == "raid12" and not RH[13].shown and RH[12].healthText.text == "50%", "raid cells fill in")
check(not blizzard.CompactRaidFrameContainer:IsVisible() and blizzard.CompactRaidFrameManager:IsVisible(),
	"Blizzard's raid frames hidden, its raid manager panel kept")
check(RH:GetAttribute("groupBy") == "GROUP" and RH:GetAttribute("unitsPerColumn") == 5, "raid sorted by group, 5 per column")
check(not RH[1].power.shown, "raid cells have no power bar by default")

StzxUIDB.profiles.Default.modules.GroupFrames.raid.enabled = false
Reload()
check(StzxUIPartyHeader and not StzxUI.movers.RaidFrames, "raid frames can be switched off on their own")
StzxUIDB.profiles.Default.modules.GroupFrames.raid.enabled = true
group.kind, group.units = nil, {}
for i = 1, 12 do units["raid" .. i], unitState["raid" .. i] = nil, nil end
units.party1, units.party2, unitState.party1, unitState.party2, auraState.party1 = nil, nil, nil, nil, nil
units.target = nil
rangeOf = {}

---------------------------------------------------------------------------
-- 16. Quests: Forever tint and quest item sparkles
---------------------------------------------------------------------------
cvars.outlineModeShowLootEffectWhenDisabled = "0"
StartGame(nil)
local Q = StzxUI:GetModule("Quests")
check(Q.enabled and Category("Quests"), "Quests module and options page")
check(Q.IsNewToForever(27146) == true and Q.IsNewToForever(9665) == false and Q.IsNewToForever(176) == false
	and Q.IsNewToForever(0) == nil, "new to Forever: above the last original Classic quest ID")
check(cvars.outlineModeShowLootEffectWhenDisabled == "1", "quest item sparkles switched on at login")
cvars.outlineModeShowLootEffectWhenDisabled = "0" -- a graphics preset turns it off
Fire("CVAR_UPDATE", "outlineModeShowLootEffectWhenDisabled")
check(cvars.outlineModeShowLootEffectWhenDisabled == "1", "...and back on after a graphics change")

local detail = QuestFrameDetailPanel
local glow = (function() for _, f in ipairs(frames) do if f.parent == detail and f.page == detail.Bg then return f end end end)()
questID = 27146
detail:Show()
check(glow and glow.shown and glow.gradient.from.a == 0.45 and glow.gradient.to.a == 0 and glow.h == 400 * 0.7,
	"new quest: glow on the parchment, fading upwards")
detail:Hide(); questID = 176; detail:Show()
check(not glow.shown, "original Classic quest: plain parchment")
questID = 27147
Fire("QUEST_DETAIL")
check(glow.shown, "updates when the quest giver shows another quest")

local logGlow = (function() for _, f in ipairs(frames) do if f.page == QuestMapFrame.DetailsFrame.Bg then return f end end end)()
QuestMapFrame_ShowQuestDetails(30000)
check(logGlow.shown, "quest log detail page tinted too")
QuestMapFrame_ShowQuestDetails(100)
check(not logGlow.shown, "...and not for Classic quests")

Q.db.tintColour = "GOLD"
log.settings.STZXUI_QUESTS_TINTSTRENGTH:SetValue(80)
check(glow.gradient.from.r == 1 and glow.gradient.from.a == 0.8, "colour and strength apply straight away")
log.settings.STZXUI_QUESTS_TINT:SetValue(false)
check(not glow.shown, "tint can be switched off")

QuestFrame.shown = true
SlashCmdList.STZXUI("quest")
check(lastPrint():find("27147 is new to Forever", 1, true), "/stzx quest says what it is")
QuestFrame.shown = false

log.settings.STZXUI_QUESTS_SPARKLES:SetValue(false)
check(cvars.outlineModeShowLootEffectWhenDisabled == "0" and DialogShown() and DialogText():find("restart", 1, true),
	"switching sparkles off says it needs a game restart")
Fire("CVAR_UPDATE", "outlineModeShowLootEffectWhenDisabled")
check(cvars.outlineModeShowLootEffectWhenDisabled == "0", "...and stops turning them back on")
questID = 0

---------------------------------------------------------------------------
-- 17. Info: levelling pace
---------------------------------------------------------------------------
unitState.player.xp, unitState.player.xpMax = 4500, 10000
StartGame(nil)
local InfoMod = StzxUI:GetModule("Info")
check(StzxUIInfoLevelling and StzxUI.movers.InfoLevelling and InfoMod.XPText() == "Lv 18  45%  -- xp/h",
	"levelling readout: level and progress, no pace yet")
now = now + 600
unitState.player.xp = 6500
Fire("PLAYER_XP_UPDATE", "player")
check(InfoMod.XPText() == "Lv 18  65%  12.0k xp/h  17m", "2000 XP in 10 minutes: 12k an hour, 17 minutes to go")
now = now + 600
unitState.player.level, unitState.player.xp, unitState.player.xpMax = 19, 500, 11000
Fire("PLAYER_XP_UPDATE", "player")
check(InfoMod.XPText():find("Lv 19  4%  ", 1, true) and InfoMod.XPText():find("18.0k xp/h", 1, true), -- 2000 + 3500 + 500 in 20 min
	"a level-up counts the XP on both sides of it")
SlashCmdList.STZXUI("xp")
check(InfoMod.XPText() == "Lv 19  4%  -- xp/h", "/stzx xp starts again")
unitState.player.level = 60
check(InfoMod.XPText() == nil, "hidden at max level")
unitState.player.level, unitState.player.xp, unitState.player.xpMax = 18, nil, nil

---------------------------------------------------------------------------
-- 18. Move mode alongside Edit Mode
---------------------------------------------------------------------------
StartGame(nil)
local function OpenEditMode()
	editMode.active = true
	EditModeManagerFrame.shown = true
	EditModeManagerFrame.Grid.shown = editMode.gridShown
	EventRegistry:TriggerEvent("EditMode.Enter")
end
local function CloseEditMode()
	editMode.active = false
	EditModeManagerFrame.shown = false
	EventRegistry:TriggerEvent("EditMode.Exit")
end
local bar = StzxUIMoveToolbar
OpenEditMode()
check(StzxUI.moveMode and StzxUIMoveToolbar and StzxUIMoveToolbar.shown, "opening Edit Mode opens move mode")
bar = StzxUIMoveToolbar
check(bar.points[1].point == "TOPLEFT", "toolbar moves to the corner, clear of Edit Mode's panel")
check(StzxUIMoveToolbar.gridButton.text == "Grid: 20 (Edit Mode)" and StzxUIMoveToolbar.gridButton.enabled == false,
	"uses Edit Mode's grid size")
local sh = StzxUI.movers.InfoStats
StzxUIDB.core.snapToFrames = false
DragTo(sh, 800 + 23, 450 + 3)
check(StzxUI.profile.positions.InfoStats.x == 20 and StzxUI.profile.positions.InfoStats.y == 0,
	"drops snap to Edit Mode's 20-unit grid")
StzxUIDB.core.snapToFrames = true
DragTo(sh, 604, 300 + 3)
check(StzxUI.profile.positions.InfoStats.x == -200, "snaps to a Blizzard frame's edge (action bar, even at its own scale)")
EditModeManagerFrame:SetGridShown(false)
check(StzxUIMoveToolbar.gridButton.text == "Grid: 16" and StzxUIMoveToolbar.gridButton.enabled,
	"Edit Mode's grid switched off: StzxUI's own grid comes back")
EditModeManagerFrame:SetGridShown(true)
CloseEditMode()
check(not StzxUI.moveMode, "closing Edit Mode closes move mode it opened")

StzxUI:EnterMoveMode()
OpenEditMode()
check(StzxUI.moveMode and StzxUIMoveToolbar.points[1].point == "TOPLEFT", "already open: stays open, toolbar moves aside")
CloseEditMode()
check(StzxUI.moveMode and StzxUIMoveToolbar.points[1].point == "TOP", "...and stays open after Edit Mode closes")
StzxUI:ExitMoveMode()

check(log.settings.STZXUI_CORE_WITHEDITMODE, "setting: Open with Edit Mode")
log.settings.STZXUI_CORE_WITHEDITMODE:SetValue(false)
OpenEditMode()
check(not StzxUI.moveMode, "switched off: Edit Mode opens alone")
CloseEditMode()
log.settings.STZXUI_CORE_WITHEDITMODE:SetValue(true)
inCombat = true
OpenEditMode()
check(not StzxUI.moveMode, "never in combat")
inCombat = false
CloseEditMode()

---------------------------------------------------------------------------
-- 19. Quests: party quest status
---------------------------------------------------------------------------
StartGame(nil)
local logPanel, giverPanel = StzxUIPartyQuestslog, StzxUIPartyQuestsgiver
check(logPanel and giverPanel and logPanel.parent == QuestMapFrame.DetailsFrame and giverPanel.parent == QuestFrame,
	"party panels beside the quest log page and the quest giver window")
check(log.settings.STZXUI_QUESTS_PARTYSTATUS, "setting: Show who in my party is on a quest")

questLog = {
	{ questID = 100, pushable = true, onQuest = { party1 = true } },
	{ questID = 200, header = true },
	{ questID = 300, pushable = false },
	{ questID = 400, pushable = true },
}
units.party1 = { name = "Liala", isPlayer = true }
unitState.party1 = { class = "DRUID" }
units.party2 = { name = "Gorr", isPlayer = true }
unitState.party2 = { class = "SHAMAN" }
units.party3 = { name = "Tamsin", isPlayer = true }
unitState.party3 = { class = "MAGE", offline = true }

-- Solo: no panel.
QuestMapFrame.shown, QuestMapFrame.DetailsFrame.shown = true, true
QuestMapFrame_ShowQuestDetails(100)
check(not logPanel.shown, "solo: no panel")

group.kind, group.units = "party", { "party1", "party2", "party3" }
QuestMapFrame_ShowQuestDetails(100)
check(logPanel.shown and logPanel.rows[1].name.text == "Liala" and logPanel.rows[1].status.text == "On it",
	"party member on the quest")
check(logPanel.rows[2].status.text == "Not on it" and logPanel.rows[3].status.text == "Offline" and not logPanel.rows[4].name.shown,
	"...one who isn't, one offline, no empty rows")
check(logPanel.share.enabled == true and logPanel.h == 30 + 3 * 16 + 28, "Share button on, panel sized to fit")
Script(logPanel.share, "OnClick")
check(log.pushed[1] == 100, "Share offers the quest to the party")
QuestMapFrame_ShowQuestDetails(300)
check(logPanel.share.enabled == false, "quests that can't be shared: button off")

-- Someone picks the quest up: refreshes on the event (after a short wait).
questLog[3].onQuest = { party2 = true }
Fire("UNIT_QUEST_LOG_CHANGED", "party2")
check(logPanel.rows[2].status.text == "Not on it", "waits a moment (events come in bursts)...")
RunAfters()
check(logPanel.rows[2].status.text == "On it", "...then updates")

-- Share all: every shareable quest, one a second.
log.pushed = {}
Script(logPanel.shareAll, "OnClick")
check(#log.pushed == 1 and log.pushed[1] == 100 and lastPrint():find("sharing 2 quests", 1, true), "Share all starts at once")
TickAll(tickers)
TickAll(tickers)
check(#log.pushed == 2 and log.pushed[2] == 400, "...then one a second, skipping headers and unshareable quests")

-- Quest giver: a quest you're being offered.
questOffers[500] = { party2 = true }
questID = 500
QuestFrame.shown = true
Fire("QUEST_DETAIL")
RunAfters()
check(giverPanel.shown and giverPanel.rows[2].status.text == "On it" and not giverPanel.share,
	"quest giver: shows who already has the quest you're offered")

log.settings.STZXUI_QUESTS_PARTYSTATUS:SetValue(false)
check(not logPanel.shown and not giverPanel.shown, "can be switched off")
log.settings.STZXUI_QUESTS_PARTYSTATUS:SetValue(true)

group.kind = nil
SlashCmdList.STZXUI("shareall")
check(lastPrint():find("join a party", 1, true), "/stzx shareall needs a party")
QuestFrame.shown, questID, questLog, questOffers = false, 0, {}, {}
QuestMapFrame.shown = false
group.units = {}
for i = 1, 3 do units["party" .. i], unitState["party" .. i] = nil, nil end

---------------------------------------------------------------------------
-- 20. Runs: dungeon run history
---------------------------------------------------------------------------
StzxUIRunsDB = nil
unitState.player.xp, unitState.player.xpMax = 1000, 10000
money = 50000
StartGame(nil)
local Runs = StzxUI:GetModule("Runs")
check(Runs.enabled and Category("Runs") and StzxUI.movers.RunTimer, "Runs section, options page and a movable timer")
check(Runs.Current() == nil and not StzxUIRunTimer.shown, "outside: no run")

local start = now
instance = { name = "The Deadmines", kind = "party", id = 36 }
Fire("PLAYER_ENTERING_WORLD")
local run = Runs.Current()
check(run and run.name == "The Deadmines" and run.level == 18, "going in starts a run")
check(StzxUIRunTimer.shown and Runs.TimerText() == "The Deadmines  0:00", "run timer shows while inside")

now = now + 600
unitState.player.xp = 4000
Fire("PLAYER_XP_UPDATE", "player")
Fire("ENCOUNTER_END", 1, "Rhahk'Zor", 1, 5, 1)
Fire("ENCOUNTER_END", 2, "Sneed", 1, 5, 0) -- a wipe
Fire("PLAYER_DEAD")
check(run.xp == 3000 and #run.bosses == 1 and run.deaths == 1, "XP, bosses killed (not wipes) and deaths counted")
check(Runs.TimerText() == "The Deadmines  10:00  1 boss", "timer shows time and bosses")

lootWindow = {
	{ link = "[Linen Cloth]", quality = 1 },
	{ link = "[Cruel Barb]", quality = 3 },
	{ link = "[Smelting Pants]", quality = 2 },
}
Fire("LOOT_READY")
Fire("LOOT_SLOT_CLEARED", 2)
Fire("LOOT_SLOT_CLEARED", 1)
Fire("LOOT_CLOSED")
check(#run.loot == 1 and run.loot[1] == "[Cruel Barb]", "loot you pick up, green and better")

-- A /reload inside carries the run on.
now = now + 60
Reload()
check(Runs.Current() == run or (Runs.Current() and Runs.Current().start == start), "/reload inside: same run")

money = 62345
Fire("PLAYER_MONEY")
now = now + 1500
TickAll(tickers) -- the game's "still inside" check, every 30 seconds
unitState.player.level, unitState.player.xp, unitState.player.xpMax = 19, 500, 11000
Fire("PLAYER_XP_UPDATE", "player")
-- Leave.
instance = nil
Fire("PLAYER_ENTERING_WORLD")
local done = Runs.History()[1]
check(Runs.Current() == nil and done and done.duration == 2160 and done.money == 12345,
	"leaving ends the run: 36 minutes, +1g 23s 45c")
check(done.xp == 3000 + 6000 + 500, "XP across a level-up")
local cols = Runs.Columns(done)
check(cols.time == "36:00" and cols.gold == "+1g 23s" and cols.xp == "9.5k" and cols.bosses == "1" and cols.loot == "1",
	"history row text")
check(not StzxUIRunTimer.shown, "timer hides outside")
check(Runs.Money(-4500) == "-45s" and Runs.Money(0) == "0" and Runs.Money(7) == "+7c", "money text")

-- Window.
SlashCmdList.STZXUI("runs")
check(StzxUIRunsWindow.shown and StzxUIRunsWindow.rows[1].cells.name.text == "The Deadmines"
	and not StzxUIRunsWindow.rows[2].shown and StzxUIRunsWindow.count.text == "1-1 of 1", "/stzx runs opens the history")

-- Raids can be left out; a logout inside and coming back much later is a new run.
Runs.db.raids = false
instance = { name = "Molten Core", kind = "raid", id = 409 }
Fire("PLAYER_ENTERING_WORLD")
check(Runs.Current() == nil, "raids off: not tracked")
Runs.db.raids = true
Fire("PLAYER_ENTERING_WORLD")
check(Runs.Current() and Runs.Current().name == "Molten Core", "raids on: tracked")
now = now + 3 * 3600
Reload()
check(#Runs.History() == 2 and Runs.Current().start == math.floor(now), "back hours later: old run closed, new one started")
check(Runs.History()[1].duration < 3600, "...ending when you were last seen inside")

-- Keep only so many.
Runs.db.keep = 3
for i = 1, 5 do
	instance = nil; Fire("PLAYER_ENTERING_WORLD")
	instance = { name = "Run " .. i, kind = "party", id = 100 + i }; Fire("PLAYER_ENTERING_WORLD")
end
instance = nil; Fire("PLAYER_ENTERING_WORLD")
check(#Runs.History() == 3 and Runs.History()[1].name == "Run 5", "history keeps the newest runs only")
Runs.db.keep = 50
StzxUIRunsWindow:Hide()
unitState.player.level, unitState.player.xp, unitState.player.xpMax = 18, nil, nil
money, lootWindow = 0, {}

---------------------------------------------------------------------------
-- 21. Social: recent mail names
---------------------------------------------------------------------------
StzxUISocialDB = { characters = { ["Sorchawyn Ashvale"] = { class = "WARLOCK" } } }
StartGame(nil)
local Mail = StzxUISocialDB and StzxUIMailNames
check(Mail and Mail.parent == SendMailFrame, "mail names panel on the Send Mail tab")
check(StzxUISocialDB.characters["Strikezx Kincrag"], "this character is noted for your others to mail")
check(log.settings.STZXUI_SOCIAL_MAILRECENT and log.settings.STZXUI_SOCIAL_MAILKEEP, "Mail options on the Social page")
SendMailFrame:Hide(); SendMailFrame:Show() -- open the Send Mail tab
check(Mail.shown and Mail.altsTitle.shown and not Mail.recentTitle.shown and Mail.buttons[1].text.text == "Sorchawyn Ashvale"
	and not Mail.buttons[2], "first time: just your other characters")

local function Send(name, ok)
	SendMailNameEditBox:SetText(name)
	SendMailFrame_SendMail()
	SendMailNameEditBox:SetText("") -- Blizzard clears the box after sending
	Fire(ok == false and "MAIL_FAILED" or "MAIL_SEND_SUCCESS")
end
Send("Liala Brightwood")
Send("Gorr")
Send("Nobody", false)
Send("liala brightwood ")
local names = {}
for i, b in ipairs(Mail.buttons) do if b.shown then names[i] = b.text.text end end
check(names[1] == "liala brightwood" and names[2] == "Gorr" and names[3] == "Sorchawyn Ashvale" and #names == 3,
	"newest first, no repeats, failed mail not kept, your characters below")
Mail.buttons[2]:Click()
check(SendMailNameEditBox.text == "Gorr" and SendMailSubjectEditBox.focused, "click a name: fills the To box")
Mail.buttons[2]:Click("RightButton")
check(Mail.buttons[2].text.text == "Sorchawyn Ashvale" and #StzxUISocialDB.recentMail == 1, "right-click forgets a recent name")
Mail.buttons[2]:Click("RightButton")
check(StzxUISocialDB.characters["Sorchawyn Ashvale"], "...but never your own characters")

StzxUI:GetModule("Social").db.mailKeep = 5
for i = 1, 8 do Send("Friend" .. i) end
check(#StzxUISocialDB.recentMail == 5 and StzxUISocialDB.recentMail[1] == "Friend8", "keeps the newest few")
log.settings.STZXUI_SOCIAL_MAILRECENT:SetValue(false)
check(not Mail.shown, "can be switched off")
log.settings.STZXUI_SOCIAL_MAILRECENT:SetValue(true)

-- Mail window loading later than StzxUI.
mailLoaded = false
Reload()
check(not StzxUIMailNames or StzxUIMailNames.parent ~= SendMailFrame, "no mail window yet: waits")
mailLoaded = true
MailFrame = NewFrame("Frame", "MailFrame")
SendMailFrame = NewFrame("Frame", "SendMailFrame", MailFrame)
SendMailNameEditBox = NewFrame("EditBox", "SendMailNameEditBox", SendMailFrame)
function SendMailFrame_SendMail() end
Fire("ADDON_LOADED", "Blizzard_MailFrame")
check(StzxUIMailNames and StzxUIMailNames.parent == SendMailFrame, "...and joins it when it loads")
StzxUISocialDB = nil

---------------------------------------------------------------------------
-- 8. Slash commands
---------------------------------------------------------------------------
SlashCmdList.STZXUI("profile")
check(lastPrint():find("'Default'", 1, true), "/stzx profile names the profile")
SlashCmdList.STZXUI("thanks Cheers %s!")
check(StzxUI:GetModule("Social").db.thankMessage == "Cheers %s!", "/stzx thanks still works")
SlashCmdList.STZXUI("help")
local helpText = table.concat(log.prints, "\n")
check(helpText:find("/stzx move", 1, true) and helpText:find("/stzx profile", 1, true), "/stzx help lists move and profile")
SlashCmdList.STZXUI("")
check(log.opened ~= nil, "/stzx opens the settings")

io.write(("%d passed, %d failed\n"):format(passes, failures))
os.exit(failures == 0 and 0 or 1)

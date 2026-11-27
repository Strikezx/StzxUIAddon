-- StzxUI Helpers: threat meter
--
-- A small movable list of who has how much threat on your target:
--
--   Defias Thug
--   [=========== Strikezx      100%]   <- has aggro (tank)
--   [========    Volgup         82%]
--   [====        Arturus        45%]
--
-- Each bar is that person's share of the top threat (whoever has aggro sits
-- at 100%). Players in class colours, pets in grey. When you're not the one
-- with aggro and you climb past the warning level, a "Threat 92%" warning
-- pops up (with a sound), once per climb.
--
-- Forever note: the game can make threat secret in some fights (StzxUI's
-- threat check says when). Then the meter still shows each bar and %, in
-- group order: it can't sort or warn on secret numbers.

local ADDON_NAME = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local Skin = StzxUI.Skin
local Threat = StzxUI.Threat

local ThreatMeter = StzxUI:NewModule("ThreatMeter", ADDON_NAME, {
	enabled = true,
	solo = false,          -- also when you're not in a group
	onlyInCombat = true,   -- hide out of combat
	rows = 5,              -- most bars shown
	warn = true,           -- warn when you're close to pulling aggro
	warnAt = 90,           -- %
	warnSound = true,
}, {
	title = "Threat Meter",
	description = "Who has how much threat on your target, with a warning before you pull aggro.",
})

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FLAT = "Interface\\Buttons\\WHITE8x8"
local MAX_ROWS, ROW, WIDTH = 10, 16, 190
local PET_COLOUR = { 0.55, 0.55, 0.55 }
local meter, warning
local warned = false -- warned this climb (resets when you drop well below)
local testing = false

---------------------------------------------------------------------------
-- Who to list
---------------------------------------------------------------------------

-- You, your pet and your group (with their pets), as unit tokens.
function ThreatMeter.Units()
	local units = { "player", "pet" }
	if IsInRaid() then
		units = {}
		for i = 1, GetNumGroupMembers() do
			units[#units + 1] = "raid" .. i
			units[#units + 1] = "raidpet" .. i
		end
	elseif IsInGroup() then
		for i = 1, GetNumSubgroupMembers() do
			units[#units + 1] = "party" .. i
			units[#units + 1] = "partypet" .. i
		end
	end
	return units
end

-- Everyone on the target's threat list: { { unit, name, threat }, ... },
-- highest first when the numbers are readable (also used by the tests).
-- Second return: true when the numbers are secret (then in group order).
function ThreatMeter.Entries(mob)
	local list, secret = {}, false
	for _, unit in ipairs(ThreatMeter.Units()) do
		if Plain(UnitExists(unit)) then
			local t = Threat.Read(unit, mob)
			if t then
				if t.secret then secret = true end
				list[#list + 1] = { unit = unit, threat = t }
			end
		end
	end
	if not secret then
		table.sort(list, function(a, b) return (a.threat.raw or 0) > (b.threat.raw or 0) end)
	end
	return list, secret
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function RowColour(unit)
	if not Plain(UnitIsPlayer(unit)) then return PET_COLOUR[1], PET_COLOUR[2], PET_COLOUR[3] end
	local class = Plain(select(2, UnitClass(unit)))
	local c = class and C_ClassColor and C_ClassColor.GetClassColor(class)
	if c then return c.r, c.g, c.b end
	return 0.8, 0.8, 0.8
end

local function ShowRow(row, name, r, g, b, value, isSecret)
	row.name:SetText(name)
	row.bar:SetStatusBarColor(r, g, b, 0.85)
	-- The bar stops at 100; the number can go past it (a pull at 110% / 130%).
	if isSecret then
		row.bar:SetValue(value)
	else
		value = value or 0
		row.bar:SetValue(math.min(100, value))
	end
	row.value:SetFormattedText("%.0f%%", value)
	row:Show()
end

local function Layout(shown)
	for i = shown + 1, MAX_ROWS do meter.rows[i]:Hide() end
	meter:SetHeight(22 + math.max(1, shown) * ROW + 4)
end

-- Your own threat: warn once as you climb past the warning level, unless
-- you're the one with aggro. Readable numbers only.
local function CheckWarning(entries, secret)
	local db = ThreatMeter.db
	if secret or not db.warn then return end
	local mine
	for _, e in ipairs(entries) do if e.unit == "player" then mine = e.threat end end
	local raw = mine and mine.raw
	if not raw or mine.tanking then
		warned = false
		return
	end
	if raw >= db.warnAt and not warned then
		warned = true
		warning.text:SetFormattedText("Threat %.0f%%", raw)
		warning:Show()
		warning.hideAt = GetTime() + 2
		if db.warnSound and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
	elseif raw < db.warnAt - 15 then
		warned = false -- dropped well below: the next climb warns again
	end
end

local function ShouldShow()
	local db = ThreatMeter.db
	if not db.enabled then return false end
	if not (db.solo or IsInGroup()) then return false end
	if db.onlyInCombat and not Plain(UnitAffectingCombat("player")) then return false end
	return Plain(UnitExists("target")) and Plain(UnitCanAttack("player", "target")) or false
end

function ThreatMeter.Update()
	if not meter or testing then return end
	if not ShouldShow() then
		meter:Hide()
		return
	end
	local entries, secret = ThreatMeter.Entries("target")
	if #entries == 0 then
		meter:Hide()
		return
	end
	meter.title:SetText(UnitName("target"))
	local shown = math.min(#entries, ThreatMeter.db.rows, MAX_ROWS)
	for i = 1, shown do
		local e = entries[i]
		local r, g, b = RowColour(e.unit)
		ShowRow(meter.rows[i], UnitName(e.unit), r, g, b, e.threat.raw, e.threat.secret)
	end
	Layout(shown)
	meter:Show()
	CheckWarning(entries, secret)
end

-- Sample bars for placing it (move mode's test frames).
local SAMPLE = {
	{ "Strikezx", "SHAMAN", 100 }, { "Volgup", nil, 82 }, { "Arturus", "WARRIOR", 64 },
	{ "Gareth", "MAGE", 45 }, { "Viasith", "PRIEST", 21 },
}
function ThreatMeter.ShowTest(on)
	testing = on and ThreatMeter.db.enabled
	if not meter then return end
	if not testing then
		ThreatMeter.Update()
		return
	end
	meter.title:SetText("Defias Thug (test)")
	local shown = math.min(#SAMPLE, ThreatMeter.db.rows)
	for i = 1, shown do
		local s = SAMPLE[i]
		local c = s[2] and C_ClassColor and C_ClassColor.GetClassColor(s[2])
		local r, g, b = PET_COLOUR[1], PET_COLOUR[2], PET_COLOUR[3]
		if c then r, g, b = c.r, c.g, c.b end
		ShowRow(meter.rows[i], s[1], r, g, b, s[3], false)
	end
	Layout(shown)
	meter:Show()
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function Build()
	meter = CreateFrame("Frame", "StzxUIThreatMeter", UIParent)
	meter:SetSize(WIDTH, 22 + 5 * ROW + 4)
	meter:SetFrameStrata("MEDIUM")
	Skin.Backdrop(meter, { edge = "accent", fill = { 0, 0, 0 }, alpha = 0.75 })
	meter.title = meter:CreateFontString(nil, "OVERLAY")
	meter.title:SetFont(FONT, 11, "")
	meter.title:SetPoint("TOPLEFT", 6, -5)
	meter.title:SetPoint("TOPRIGHT", -6, -5)
	meter.title:SetJustifyH("LEFT")
	meter.title:SetWordWrap(false)
	meter.title:SetTextColor(1, 0.82, 0.25)
	meter.rows = {}
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Frame", nil, meter)
		row:SetSize(WIDTH - 8, ROW - 2)
		row:SetPoint("TOPLEFT", 4, -22 - (i - 1) * ROW)
		row.bar = CreateFrame("StatusBar", nil, row)
		row.bar:SetAllPoints()
		row.bar:SetStatusBarTexture(FLAT)
		row.bar:SetMinMaxValues(0, 100)
		row.back = row:CreateTexture(nil, "BACKGROUND")
		row.back:SetAllPoints()
		row.back:SetColorTexture(1, 1, 1, 0.06)
		row.name = row.bar:CreateFontString(nil, "OVERLAY")
		row.name:SetFont(FONT, 11, "OUTLINE")
		row.name:SetPoint("LEFT", 4, 0)
		row.name:SetWidth(WIDTH - 60)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.value = row.bar:CreateFontString(nil, "OVERLAY")
		row.value:SetFont(FONT, 11, "OUTLINE")
		row.value:SetPoint("RIGHT", -4, 0)
		row:Hide()
		meter.rows[i] = row
	end
	meter:Hide()
	StzxUI:RegisterMover("ThreatMeter", meter, {
		label = "Threat meter",
		category = "Helpers",
		default = { "LEFT", "LEFT", 20, -200 },
		isShown = function() return ThreatMeter.db.enabled end,
	})

	-- The warning: big text in the middle of the screen for two seconds.
	warning = CreateFrame("Frame", "StzxUIThreatWarning", UIParent)
	warning:SetSize(260, 40)
	warning:SetFrameStrata("HIGH")
	warning.text = warning:CreateFontString(nil, "OVERLAY")
	warning.text:SetFont(FONT, 26, "OUTLINE")
	warning.text:SetPoint("CENTER")
	warning.text:SetTextColor(1, 0.25, 0.2)
	warning:Hide()
	warning:SetScript("OnUpdate", function(self)
		if self.hideAt and GetTime() >= self.hideAt then self:Hide() end
	end)
	StzxUI:RegisterMover("ThreatWarning", warning, {
		label = "Threat warning",
		category = "Helpers",
		default = { "TOP", "TOP", 0, -140 },
		isShown = function() return ThreatMeter.db.enabled and ThreatMeter.db.warn end,
	})
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

function ThreatMeter:OnInitialize()
	local page = StzxUI:AddSettingsPage("Threat Meter")
	StzxUI:AddHeader(page, "Threat meter",
		"Who has how much threat on your target: each bar is a share of the top threat (whoever has aggro is "
		.. "at 100%). Place it in move mode. If the game makes threat secret in a fight, the bars still show "
		.. "but in group order, and there's no warning (Combat > Threat checks this for you).")
	StzxUI:AddCheckbox(page, self, "enabled", "Show the threat meter", nil, ThreatMeter.Update)
	StzxUI:AddCheckbox(page, self, "solo", "Also when I'm not in a group",
		"Off: only in a party or raid. On: solo too (you and your pet).", ThreatMeter.Update)
	StzxUI:AddCheckbox(page, self, "onlyInCombat", "Only in combat",
		"Hide the meter when you're not fighting.", ThreatMeter.Update)
	StzxUI:AddSlider(page, self, "rows", "Most bars shown", "The top ones when there are more.", 3, MAX_ROWS, 1,
		function(value) return ("%d"):format(value) end, ThreatMeter.Update)
	StzxUI:AddHeader(page, "Warning")
	StzxUI:AddCheckbox(page, self, "warn", "Warn me before I pull aggro",
		"Big text in the middle of the screen when your threat passes the level below, unless you're the one "
		.. "with aggro. Once per climb: it warns again after you drop well below.")
	StzxUI:AddSlider(page, self, "warnAt", "Warn at", "Your share of the top threat.", 70, 100, 5,
		function(value) return ("%d%%"):format(value) end)
	StzxUI:AddCheckbox(page, self, "warnSound", "With a sound")
end

function ThreatMeter:OnEnable()
	Build()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED",
		"GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_PET" }) do
		events:RegisterEvent(event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_ENABLED" then warned = false end
		ThreatMeter.Update()
	end)
	-- Threat moves all the time in a fight: a light refresh while the meter shows.
	C_Timer.NewTicker(0.5, function()
		if meter:IsShown() or Plain(UnitAffectingCombat("player")) then ThreatMeter.Update() end
	end)
	StzxUI:RegisterTestMode("threatmeter", ThreatMeter.ShowTest)
	ThreatMeter.Update()
end

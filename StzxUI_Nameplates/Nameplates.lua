-- StzxUI Nameplates: the module
--
-- Every nameplate the game lets addons touch gets a StzxUI plate (see
-- Plate.lua). Blizzard's own plate stays where it is but invisible, so
-- clicking and tab-targeting work exactly as before.
--
-- Some plates are "forbidden" to addons (friendly players inside dungeons
-- and raids): those keep Blizzard's look. Your own personal resource bar is
-- left alone too.
--
-- Settings: StzxUI > Nameplates. /stzx test shows three pretend plates.

local ADDON_NAME, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local Nameplates = StzxUI:NewModule("Nameplates", ADDON_NAME, {
	width = 130,
	height = 10,
	healthText = "PERCENT", -- "PERCENT", "NUMBER", "NONE"
	classColours = true,    -- enemy players in their class colour
	showLevel = true,
	nameSize = 14,          -- the name above the bar (the level follows it)
	castBar = true,
	castHeight = 10,
	debuffs = true,         -- your debuffs on enemies
	maxDebuffs = 5,
	debuffSize = 20,
	targetOutline = true,
	fadeOthers = 70,        -- other plates' opacity (%) while you have a target; 100 = no fading
	aggro = true,           -- red edge when the mob is attacking you
}, {
	title = "Nameplates",
	description = "Clear target highlight, cast bars that show what you can interrupt, your debuffs on enemies.",
})

function ns.db() return Nameplates.db end

local plates = {}   -- unit token -> StzxUI plate
local platesOf = setmetatable({}, { __mode = "k" }) -- Blizzard nameplate -> StzxUI plate
local parked = setmetatable({}, { __mode = "k" })   -- Blizzard UnitFrame -> its hidden children
local alphaHooked = setmetatable({}, { __mode = "k" }) -- Blizzard UnitFrames we watch
local hidden = CreateFrame("Frame")
hidden:Hide()

---------------------------------------------------------------------------
-- Blizzard's plate: invisible, but left in place
---------------------------------------------------------------------------

-- Children kept: the widget container (quest/objective widgets) and the
-- soft-target icon. Protected or forbidden pieces are only made invisible.
local function HideBlizzard(nameplate)
	local uf = nameplate.UnitFrame
	if not uf then return end
	uf:SetAlpha(0)
	-- Blizzard's shared unit-frame code sets the frame fully visible again
	-- now and then (e.g. its range and status update, around combat), which
	-- brought back its big name above ours. Put it straight back to invisible.
	if not alphaHooked[uf] then
		alphaHooked[uf] = true
		hooksecurefunc(uf, "SetAlpha", function(self, alpha)
			if parked[self] and alpha ~= 0 then self:SetAlpha(0) end
		end)
	end
	if parked[uf] then return end
	local list = {}
	for i = uf:GetNumChildren(), 1, -1 do
		local child = select(i, uf:GetChildren())
		if child and child ~= uf.WidgetContainer and child ~= uf.SoftTargetFrame
			and not (child.IsForbidden and child:IsForbidden()) and not (child.IsProtected and child:IsProtected()) then
			child:SetParent(hidden)
			list[#list + 1] = child
		end
	end
	parked[uf] = list
end

local function ShowBlizzard(nameplate)
	local uf = nameplate.UnitFrame
	if not uf then return end
	for _, child in ipairs(parked[uf] or {}) do child:SetParent(uf) end
	parked[uf] = nil
	uf:SetAlpha(1)
end

---------------------------------------------------------------------------
-- Plates coming and going
---------------------------------------------------------------------------

local function Added(unit)
	local nameplate = C_NamePlate.GetNamePlateForUnit(unit) -- nil for forbidden plates
	if not nameplate then return end
	-- Your own personal resource bar keeps Blizzard's look.
	if Plain(UnitIsUnit(unit, "player")) then
		ShowBlizzard(nameplate)
		if platesOf[nameplate] then platesOf[nameplate]:Hide() end
		return
	end
	HideBlizzard(nameplate)
	local p = platesOf[nameplate]
	if not p then
		p = ns.CreatePlate(nameplate)
		p:SetPoint("CENTER", nameplate, "CENTER")
		platesOf[nameplate] = p
	end
	ns.LayoutPlate(p, Nameplates.db)
	p.unit = unit
	plates[unit] = p
	ns.UpdatePlate(p)
	p:Show()
end

local function Removed(unit)
	local p = plates[unit]
	if not p then return end
	plates[unit] = nil
	p.unit = nil
	p.cast.casting = false
	p.cast:Hide()
	p:Hide()
end

function Nameplates:RefreshAll()
	for _, p in pairs(plates) do
		ns.LayoutPlate(p, self.db)
		ns.UpdatePlate(p)
	end
	if ns.testHolder and ns.testHolder:IsShown() then ns.ShowTest(true) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local UNIT_EVENTS = {
	UNIT_HEALTH = ns.UpdateHealth,
	UNIT_MAXHEALTH = ns.UpdateHealth,
	UNIT_FACTION = ns.UpdateHealth,
	UNIT_NAME_UPDATE = ns.UpdateName,
	UNIT_LEVEL = ns.UpdateName,
	UNIT_AURA = ns.UpdateDebuffs,
	UNIT_THREAT_LIST_UPDATE = ns.UpdateThreat,
	UNIT_THREAT_SITUATION_UPDATE = ns.UpdateThreat,
	UNIT_SPELLCAST_START = ns.UpdateCast,
	UNIT_SPELLCAST_STOP = ns.UpdateCast,
	UNIT_SPELLCAST_FAILED = ns.UpdateCast,
	UNIT_SPELLCAST_DELAYED = ns.UpdateCast,
	UNIT_SPELLCAST_CHANNEL_START = ns.UpdateCast,
	UNIT_SPELLCAST_CHANNEL_UPDATE = ns.UpdateCast,
	UNIT_SPELLCAST_CHANNEL_STOP = ns.UpdateCast,
	UNIT_SPELLCAST_INTERRUPTIBLE = ns.UpdateCast,
	UNIT_SPELLCAST_NOT_INTERRUPTIBLE = ns.UpdateCast,
	UNIT_SPELLCAST_INTERRUPTED = ns.CastInterrupted,
}
local ALL_EVENTS = {
	PLAYER_TARGET_CHANGED = ns.UpdateTarget,
	RAID_TARGET_UPDATE = ns.UpdateMarker,
	PLAYER_REGEN_ENABLED = ns.UpdateThreat,
	PLAYER_REGEN_DISABLED = ns.UpdateThreat,
}

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		Added(unit)
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		Removed(unit)
	elseif UNIT_EVENTS[event] then
		local p = unit and plates[unit]
		if p then UNIT_EVENTS[event](p) end
	elseif ALL_EVENTS[event] then
		for _, p in pairs(plates) do ALL_EVENTS[event](p) end
	end
end)

---------------------------------------------------------------------------
-- /stzx auras: what the game tells StzxUI about your debuffs (to track down
-- debuffs missing from plates or frames). Try it in a fight.
---------------------------------------------------------------------------
-- One line per unit: how many of your debuffs (and all debuffs) the game
-- reports, or that it refused.
local function Report(label, unit, extra)
	local mine, err = StzxUI.Auras.Try(unit, "HARMFUL|PLAYER")
	if not mine then
		StzxUI:Say(("%s: refused (%s)"):format(label, err))
		return
	end
	local all = StzxUI.Auras.Try(unit, "HARMFUL") or 0
	StzxUI:Say(("%s: %d of your debuffs, %d in all%s"):format(label, mine, all, extra or ""))
end

local function IconsShown(p)
	local count = 0
	for _, icon in ipairs(p.debuffs) do
		if icon:IsShown() then count = count + 1 end
	end
	return count
end

StzxUI.slashCommands.auras = {
	help = "check which units' auras the game lets StzxUI read (try it in a fight)",
	run = function()
		local secret = C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
		StzxUI:Say(("in combat: %s, aura details hidden: %s"):format(
			InCombatLockdown() and "yes" or "no", secret and "yes" or "no"))
		Report("you", "player")
		if UnitExists("target") then Report("target", "target") end
		if UnitExists("party1") then Report("party1", "party1") end
		if UnitExists("pet") then Report("pet", "pet") end
		local any = false
		for unit, p in pairs(plates) do
			any = true
			Report(unit, unit, (", %d icons shown"):format(IconsShown(p)))
		end
		if not any then StzxUI:Say("no StzxUI nameplates on screen.") end
	end,
}

---------------------------------------------------------------------------
-- Test plates: three pretend enemies in the middle of the screen
---------------------------------------------------------------------------

local TESTS = {
	{ name = "Defias Pillager", level = 18, health = 0.72, colour = "hostile", target = true,
		debuffs = { "Interface\\Icons\\Spell_Shadow_ShadowWordPain", "Interface\\Icons\\Spell_Shadow_AbominationExplosion" } },
	{ name = "Defias Conjurer", level = 19, health = 0.45, colour = "hostile", cast = "Fireball",
		castIcon = "Interface\\Icons\\Spell_Fire_FlameBolt", aggro = true },
	{ name = "Mr. Smite", level = 20, elite = true, health = 0.9, colour = "hostile", cast = "Smite Slam",
		castIcon = "Interface\\Icons\\Ability_Warrior_Cleave", locked = true },
}

local function PaintTest(p, t, db)
	local C = ns.COLOURS
	p.health:SetMinMaxValues(0, 1)
	p.health:SetValue(t.health)
	p.health:SetColor(C[t.colour])
	p.healthText:SetText(db.healthText == "PERCENT" and (math.floor(t.health * 100) .. "%")
		or db.healthText == "NUMBER" and tostring(math.floor(t.health * 2800)) or "")
	p.name:SetText(t.name)
	p.level:SetText(t.level .. (t.elite and "+" or ""))
	p.level:SetTextColor(1, 0.82, 0)
	p.marker:Hide()
	p.target:SetAlpha(1)
	p.target:SetShown(db.targetOutline and t.target or false)
	p:SetAlpha(t.target and 1 or db.fadeOthers / 100)
	p.aggro:SetAlpha(1)
	p.aggro:SetShown(db.aggro and t.aggro or false)
	local shown = 0
	if db.debuffs and t.debuffs then
		for _, icon in ipairs(t.debuffs) do
			if shown >= db.maxDebuffs then break end
			shown = shown + 1
			StzxUI.Auras.Set(p.debuffs[shown], "player",
				{ auraInstanceID = 0, icon = icon, duration = 0, expirationTime = 0, applications = 0, dispelName = "Magic" }, true)
		end
	end
	ns.PlaceDebuffs(p, shown)
	if db.castBar and t.cast then
		local c = t.locked and C.locked or C.cast
		p.cast.casting = false
		p.cast:SetMinMaxValues(0, 1)
		p.cast:SetValue(0.6)
		p.cast:GetStatusBarTexture():SetVertexColor(c.r, c.g, c.b)
		p.castText:SetText(t.cast)
		p.castIcon:SetTexture(t.castIcon)
		p.shield:SetAlpha(t.locked and 1 or 0)
		p.cast:Show()
	else
		p.cast:Hide()
	end
end

function ns.ShowTest(on)
	if on and not ns.testHolder then
		local holder = CreateFrame("Frame", "StzxUINameplateTest", UIParent)
		holder:SetSize(1, 1)
		holder:SetPoint("CENTER", 0, 140)
		holder.plates = {}
		ns.testHolder = holder
	end
	local holder = ns.testHolder
	if not holder then return end
	holder:SetShown(on)
	if not on then return end
	local db = Nameplates.db
	for i, t in ipairs(TESTS) do
		local p = holder.plates[i] or ns.CreatePlate(holder)
		holder.plates[i] = p
		ns.LayoutPlate(p, db)
		p:ClearAllPoints()
		p:SetPoint("CENTER", holder, "CENTER", (i - 2) * (db.width + 40), 0)
		PaintTest(p, t, db)
		p:Show()
	end
end

---------------------------------------------------------------------------
-- Settings, start-up
---------------------------------------------------------------------------

function Nameplates:OnInitialize()
	local page = StzxUI:AddSettingsPage("Nameplates")
	local function Refresh() self:RefreshAll() end
	StzxUI:AddHeader(page, "Plates",
		"StzxUI draws its own plate on each nameplate; clicking and targeting work as before. "
		.. "Friendly players inside dungeons keep Blizzard's plates (the game doesn't let addons change those).")
	StzxUI:AddSlider(page, self, "width", "Width", nil, 80, 220, 2, nil, Refresh)
	StzxUI:AddSlider(page, self, "height", "Height", nil, 6, 24, 1, nil, Refresh)
	StzxUI:AddDropdown(page, self, "healthText", "Health text", nil,
		{ { "PERCENT", "Percent" }, { "NUMBER", "Number" }, { "NONE", "None" } }, Refresh)
	StzxUI:AddCheckbox(page, self, "classColours", "Enemy players in class colours", nil, Refresh)
	StzxUI:AddSlider(page, self, "nameSize", "Name size", "The level text grows with it.", 8, 24, 1, nil, Refresh)
	StzxUI:AddCheckbox(page, self, "showLevel", "Show level", "Coloured by difficulty; + means elite.", Refresh)

	StzxUI:AddHeader(page, "In a fight")
	StzxUI:AddCheckbox(page, self, "targetOutline", "Outline my target", "A StzxUI-blue edge round your target's plate.", Refresh)
	StzxUI:AddSlider(page, self, "fadeOthers", "Other plates while I have a target",
		"How see-through the other plates are. 100% = no fading.", 30, 100, 5,
		function(v) return v .. "%" end, Refresh)
	StzxUI:AddCheckbox(page, self, "aggro", "Red edge when a mob is attacking me", nil, Refresh)
	StzxUI:AddCheckbox(page, self, "castBar", "Cast bars",
		"Yellow: you can interrupt it. Grey with a shield: you can't. Blue: channelled.", Refresh)
	StzxUI:AddSlider(page, self, "castHeight", "Cast bar height", nil, 6, 20, 1, nil, Refresh)
	StzxUI:AddCheckbox(page, self, "debuffs", "My debuffs on enemies", nil, Refresh)
	StzxUI:AddSlider(page, self, "maxDebuffs", "Debuffs shown", nil, 1, 8, 1, nil, Refresh)
	StzxUI:AddSlider(page, self, "debuffSize", "Debuff size", nil, 12, 32, 1, nil, Refresh)
	StzxUI:AddButton(page, "Test plates", "Show / hide", function() StzxUI:ToggleTestMode() end,
		"Three pretend plates in the middle of the screen, drawn with these settings. /stzx test does the same.")
end

function Nameplates:OnEnable()
	events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	for event in pairs(UNIT_EVENTS) do pcall(events.RegisterEvent, events, event) end
	for event in pairs(ALL_EVENTS) do events:RegisterEvent(event) end
	StzxUI:RegisterTestMode("nameplates", ns.ShowTest)
	-- Plates already on screen (after a /reload).
	for _, nameplate in ipairs(C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
		local unit = nameplate.namePlateUnitToken or (nameplate.UnitFrame and nameplate.UnitFrame.unit)
		if unit then Added(unit) end
	end
end

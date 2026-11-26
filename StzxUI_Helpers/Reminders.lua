-- StzxUI Helpers: buff and consumable reminders
--
-- A small list, shown out of combat when something needs doing:
--   * a buff of your own you know but don't have on (Arcane Intellect, your
--     armour, Fortitude, Mark of the Wild, an Aspect, a paladin aura...);
--     a group version from someone else counts (Arcane Brilliance...)
--   * a long buff about to run out: food, elixirs, class buffs (any buff of
--     10 minutes or more with less than the time you choose left)
--   * rogues and shamans: no poison or imbue on your main-hand weapon
--   * herbalists and miners: no gathering tracking on
--   * hunters: ammo running low
-- Checked only out of combat: in a fight the game hides auras from addons.

local ADDON_NAME, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local Skin = StzxUI.Skin

local Reminders = StzxUI:NewModule("Reminders", ADDON_NAME, {
	enabled = true,
	missingBuffs = true,  -- your own buffs you know but don't have on
	expiring = true,      -- long buffs running out
	expiringMinutes = 2,  -- "running out" means less than this left
	weaponBuffs = true,   -- rogue poisons, shaman imbues
	tracking = true,      -- herb / mineral tracking off
	ammo = true,          -- hunters: low ammo
	ammoLow = 200,        -- "low" means fewer than this
	inTowns = false,      -- also while resting (towns, inns)
}, {
	title = "Reminders",
	description = "Missing buffs, food and elixirs running out, weapon poisons, gathering tracking, low ammo.",
})
ns.Reminders = Reminders

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local LONG_BUFF = 600 -- seconds: buffs at least this long count as "long"
local MAX_LINES = 8

-- Your own buffs, by class. need: knowing any of these means you should have
-- one of them on. also: these count too (group versions others cast).
-- Spell IDs are rank 1 (Classic keeps lower ranks known).
local CLASS_BUFFS = {
	MAGE = {
		{ label = "Arcane Intellect", need = { 1459 }, also = { 23028 } },
		{ label = "Armour", need = { 168, 7302, 6117 } }, -- Frost, Ice, Mage Armor
	},
	PRIEST = {
		{ label = "Power Word: Fortitude", need = { 1243 }, also = { 21562 } },
		{ label = "Inner Fire", need = { 588 } },
	},
	WARLOCK = {
		{ label = "Armour", need = { 687, 706 } }, -- Demon Skin, Demon Armor
	},
	DRUID = {
		{ label = "Mark of the Wild", need = { 1126 }, also = { 21849 } },
	},
	SHAMAN = {
		{ label = "Lightning Shield", need = { 324 } },
	},
	HUNTER = {
		{ label = "An Aspect", need = { 13165, 13163, 5118, 13159 } }, -- Hawk, Monkey, Cheetah, Pack
	},
	PALADIN = {
		{ label = "An aura", need = { 465, 7294, 19746, 19876, 19888, 19891 } },
		{ label = "A blessing", need = { 19740, 19742, 20911, 19977, 1038, 20217 },
			also = { 25782, 25894, 25898, 25895, 25890, 25899 } }, -- the Greater versions
	},
}

local GATHER_TRACKING = { 2383, 2580 } -- Find Herbs, Find Minerals
local POISON_LEVEL = 20                 -- rogues: poisons from level 20
local ROCKBITER = 8017                  -- shamans: knowing a weapon imbue

local panel

local function SpellName(id)
	return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
end

local function Knows(id)
	return C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) or false
end

local function HasBuff(name)
	if not name then return false end
	local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
	return ok and aura ~= nil
end

local function MissingBuffs(lines, class)
	for _, family in ipairs(CLASS_BUFFS[class] or {}) do
		local known, on = false, false
		for _, id in ipairs(family.need) do
			if Knows(id) then known = true end
			if HasBuff(SpellName(id)) then on = true end
		end
		for _, id in ipairs(family.also or {}) do
			if HasBuff(SpellName(id)) then on = true end
		end
		if known and not on then lines[#lines + 1] = family.label .. " is missing" end
	end
end

local function Expiring(lines)
	local limit = (Reminders.db.expiringMinutes or 2) * 60
	local ok, list = pcall(C_UnitAuras.GetUnitAuras, "player", "HELPFUL", 40)
	if not ok or type(list) ~= "table" then return end
	for _, aura in ipairs(list) do
		local duration, expires = Plain(aura.duration), Plain(aura.expirationTime)
		local name = Plain(aura.name)
		if name and duration and expires and duration >= LONG_BUFF then
			local left = expires - GetTime()
			if left > 0 and left <= limit then
				lines[#lines + 1] = ("%s runs out in %s"):format(name, left >= 60 and (math.floor(left / 60) .. "m")
					or (math.floor(left) .. "s"))
			end
		end
	end
end

local function WeaponBuff(lines, class)
	local level = Plain(UnitLevel("player")) or 0
	local wants = (class == "ROGUE" and level >= POISON_LEVEL) or (class == "SHAMAN" and Knows(ROCKBITER))
	if not wants or not (C_Item and C_Item.GetWeaponEnchantInfo) then return end
	if not GetInventoryItemID("player", 16) then return end -- no main-hand weapon
	local slot = Enum and Enum.WeaponSlot and Enum.WeaponSlot.MainHand or 0
	for _, enchant in pairs(C_Item.GetWeaponEnchantInfo(slot) or {}) do
		if enchant.hasEnchant then
			local left = (Plain(enchant.timeLeft) or 0) / 1000
			if left > 0 and left <= (Reminders.db.expiringMinutes or 2) * 60 then
				lines[#lines + 1] = class == "ROGUE" and "Weapon poison runs out soon" or "Weapon imbue runs out soon"
			end
			return
		end
	end
	lines[#lines + 1] = class == "ROGUE" and "No poison on your weapon" or "No imbue on your weapon"
end

local function Tracking(lines)
	local knowsOne = false
	for _, id in ipairs(GATHER_TRACKING) do
		if Knows(id) then knowsOne = true end
	end
	if not knowsOne or not (C_Minimap and C_Minimap.GetNumTrackingTypes) then return end
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(i)
		if info and Plain(info.active) then
			for _, id in ipairs(GATHER_TRACKING) do
				if Plain(info.spellID) == id then return end
			end
		end
	end
	lines[#lines + 1] = "No herb or mineral tracking on"
end

local function Ammo(lines, class)
	if class ~= "HUNTER" or not GetInventoryItemID("player", INVSLOT_AMMO or 0) then return end
	local count = Plain(GetInventoryItemCount("player", INVSLOT_AMMO or 0)) or 0
	if count < (Reminders.db.ammoLow or 200) then lines[#lines + 1] = ("Low ammo: %d left"):format(count) end
end

-- What to remind you of right now (also used by the tests).
function Reminders.Lines()
	local db = Reminders.db
	local lines = {}
	if not db.enabled or InCombatLockdown() or Plain(UnitIsDeadOrGhost("player")) or Plain(UnitOnTaxi("player")) then
		return lines
	end
	if not db.inTowns and Plain(IsResting()) then return lines end
	local class = Plain(select(2, UnitClass("player")))
	if db.missingBuffs and class then MissingBuffs(lines, class) end
	if db.expiring then Expiring(lines) end
	if db.weaponBuffs and class then WeaponBuff(lines, class) end
	if db.tracking then Tracking(lines) end
	if db.ammo and class then Ammo(lines, class) end
	return lines
end

local function Update()
	if not panel then return end
	local lines = Reminders.Lines()
	if #lines == 0 then
		panel:Hide()
		return
	end
	local shown = math.min(#lines, MAX_LINES)
	for i = 1, MAX_LINES do
		local text = panel.lines[i]
		if i <= shown then
			text:SetText(lines[i])
			text:Show()
		else
			text:Hide()
		end
	end
	panel:SetHeight(shown * 16 + 26)
	panel:Show()
end
Reminders.Update = Update

local function Build()
	panel = CreateFrame("Frame", "StzxUIReminders", UIParent)
	panel:SetSize(230, 60)
	panel:SetFrameStrata("MEDIUM")
	Skin.Backdrop(panel, { edge = "accent", fill = { 0, 0, 0 }, alpha = 0.75 })
	local title = panel:CreateFontString(nil, "OVERLAY")
	title:SetFont(FONT, 12, "")
	title:SetPoint("TOPLEFT", 8, -6)
	title:SetText("Reminders")
	title:SetTextColor(StzxUI.ACCENT.r, StzxUI.ACCENT.g, StzxUI.ACCENT.b)
	panel.lines = {}
	for i = 1, MAX_LINES do
		local text = panel:CreateFontString(nil, "OVERLAY")
		text:SetFont(FONT, 12, "")
		text:SetPoint("TOPLEFT", 10, -6 - i * 16)
		text:SetWidth(212)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		text:SetTextColor(1, 0.82, 0.25)
		panel.lines[i] = text
	end
	panel:Hide()
	StzxUI:RegisterMover("Reminders", panel, {
		label = "Reminders",
		category = "Helpers",
		default = { "TOP", "TOP", 0, -140 },
		isShown = function() return Reminders.db.enabled end,
	})
end

function Reminders:OnInitialize()
	local page = StzxUI:AddSettingsPage("Reminders")
	StzxUI:AddCheckbox(page, self, "enabled", "Show reminders",
		"A small list, out of combat only, when something needs doing. Place it in move mode.", Update)
	StzxUI:AddCheckbox(page, self, "missingBuffs", "My own buffs missing",
		"A buff you know but don't have on: Arcane Intellect, your armour, Fortitude, Mark of the Wild, an Aspect, "
		.. "a paladin aura or blessing... Someone else's group version counts.", Update)
	StzxUI:AddCheckbox(page, self, "expiring", "Long buffs running out",
		"Food, elixirs and class buffs of 10 minutes or more, near their end.", Update)
	StzxUI:AddSlider(page, self, "expiringMinutes", "\"Running out\" means less than",
		nil, 1, 10, 1, function(value) return ("%d min"):format(value) end, Update)
	StzxUI:AddCheckbox(page, self, "weaponBuffs", "Weapon poisons and imbues",
		"Rogues (from level 20) and shamans: nothing on your main-hand weapon, or it's running out.", Update)
	StzxUI:AddCheckbox(page, self, "tracking", "Gathering tracking off",
		"Herbalists and miners: neither Find Herbs nor Find Minerals is on.", Update)
	StzxUI:AddCheckbox(page, self, "ammo", "Low ammo",
		"Hunters: fewer arrows or bullets than the number below.", Update)
	StzxUI:AddSlider(page, self, "ammoLow", "Low ammo means fewer than", nil, 50, 1000, 50, nil, Update)
	StzxUI:AddCheckbox(page, self, "inTowns", "Also in towns and inns",
		"Off: no reminders while resting.", Update)
end

function Reminders:OnEnable()
	Build()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD",
		"PLAYER_UPDATE_RESTING", "MINIMAP_UPDATE_TRACKING", "UNIT_INVENTORY_CHANGED", "SPELLS_CHANGED" }) do
		events:RegisterEvent(event)
	end
	events:RegisterUnitEvent("UNIT_AURA", "player")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			panel:Hide()
			return
		end
		Update()
	end)
	C_Timer.NewTicker(5, function() if not InCombatLockdown() then Update() end end)
	Update()
end

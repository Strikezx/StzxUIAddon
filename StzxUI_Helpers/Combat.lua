-- StzxUI Helpers: combat helpers
--
--   Combat timer   how long the current fight has run ("1:42"); after the
--                  fight it shows the final time for a few seconds
--   Pet reminder   hunters and warlocks: a warning when your pet is missing
--                  or dead, out of combat (not while mounted, on a flight or
--                  dead yourself; optionally not in towns)
--   Healers' mana  in a group, each healer's mana in a small box. Healers are
--                  the players marked as healers; if nobody is marked, the
--                  classes that can heal (option)
--
-- Forever note: in a fight the game may hide other players' power from
-- addons. The healer box only *shows* it: the game's own percentage goes
-- straight into the text (UnitPowerPercent), StzxUI never does maths on it.

local ADDON_NAME, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local Skin = StzxUI.Skin
local A = StzxUI.ACCENT

local Combat = StzxUI:NewModule("Combat", ADDON_NAME, {
	combatTimer = true,    -- show how long the fight has run
	timerLinger = 5,       -- seconds the final time stays after a fight (0: hide at once)
	petReminder = true,    -- warn when your pet is missing (hunters, warlocks)
	petInTowns = false,    -- also in towns and inns (resting)
	healerMana = true,     -- healers' mana in a group
	healersByClass = true, -- nobody marked as healer: show the classes that can heal
	threatCheck = true,    -- note whether threat is readable in fights (StzxUI.Threat)
}, {
	title = "Combat",
	description = "A combat timer, a reminder when your pet is missing, and your group's healers' mana.",
})
ns.Combat = Combat

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function Box(name, w, h)
	local frame = CreateFrame("Frame", name, UIParent)
	frame:SetSize(w, h)
	frame:SetFrameStrata("MEDIUM")
	Skin.Backdrop(frame, { edge = "accent", fill = { 0, 0, 0 }, alpha = 0.75 })
	return frame
end

---------------------------------------------------------------------------
-- Combat timer
---------------------------------------------------------------------------

local timer
local fightStart, fightEnd

function Combat.TimerText(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
	end
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function UpdateTimer()
	if not fightStart then return end
	timer.text:SetText(Combat.TimerText((fightEnd or GetTime()) - fightStart))
end

local function BuildTimer()
	timer = Box("StzxUICombatTimer", 70, 24)
	timer.text = timer:CreateFontString(nil, "OVERLAY")
	timer.text:SetFont(FONT, 14, "OUTLINE")
	timer.text:SetPoint("CENTER")
	timer:Hide()
	local wait = 0
	timer:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.2
		UpdateTimer()
	end)
	StzxUI:RegisterMover("CombatTimer", timer, {
		label = "Combat timer",
		category = "Helpers",
		default = { "CENTER", "CENTER", 0, 120 },
		isShown = function() return Combat.db.combatTimer end,
	})
end

local function FightStarted()
	fightStart, fightEnd = GetTime(), nil
	if Combat.db.combatTimer then
		UpdateTimer()
		timer.text:SetTextColor(1, 1, 1)
		timer:Show()
	end
end

local function FightEnded()
	if not fightStart then return end
	fightEnd = GetTime()
	UpdateTimer()
	timer.text:SetTextColor(A.r, A.g, A.b)
	local linger = Combat.db.timerLinger or 0
	if linger <= 0 then
		timer:Hide()
		return
	end
	local ended = fightEnd
	C_Timer.After(linger, function()
		if fightEnd == ended then timer:Hide() end -- no new fight since
	end)
end

---------------------------------------------------------------------------
-- Pet reminder
---------------------------------------------------------------------------

local PET_CLASSES = { HUNTER = 10, WARLOCK = 1 } -- class -> level the pet comes at
local petWarning

-- Should the warning show right now? (Also used by the tests.)
function Combat.PetMissing()
	local db = Combat.db
	if not db.petReminder then return false end
	local class = Plain(select(2, UnitClass("player")))
	local fromLevel = class and PET_CLASSES[class]
	if not fromLevel or (Plain(UnitLevel("player")) or 0) < fromLevel then return false end
	if InCombatLockdown() or Plain(UnitIsDeadOrGhost("player")) or Plain(UnitOnTaxi("player"))
		or Plain(IsMounted()) or (UnitHasVehicleUI and Plain(UnitHasVehicleUI("player"))) then
		return false
	end
	if not db.petInTowns and Plain(IsResting()) then return false end
	if not UnitExists("pet") then return true end
	return Plain(UnitIsDead("pet")) == true
end

local function UpdatePetWarning()
	if not petWarning then return end
	if Combat.PetMissing() then
		petWarning.text:SetText(Plain(UnitIsDead("pet")) and "Your pet is dead" or "Your pet is missing")
		petWarning:Show()
	else
		petWarning:Hide()
	end
end

local function BuildPetWarning()
	petWarning = CreateFrame("Frame", "StzxUIPetReminder", UIParent)
	petWarning:SetSize(260, 30)
	petWarning.text = petWarning:CreateFontString(nil, "OVERLAY")
	petWarning.text:SetFont(FONT, 20, "OUTLINE")
	petWarning.text:SetPoint("CENTER")
	petWarning.text:SetTextColor(1, 0.45, 0.2)
	petWarning:Hide()
	StzxUI:RegisterMover("PetReminder", petWarning, {
		label = "Pet reminder",
		category = "Helpers",
		default = { "CENTER", "CENTER", 0, 200 },
		isShown = function()
			local class = Plain(select(2, UnitClass("player")))
			return Combat.db.petReminder and class and PET_CLASSES[class] ~= nil
		end,
	})
end

---------------------------------------------------------------------------
-- Healers' mana
---------------------------------------------------------------------------

local HEALING_CLASSES = { PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true }
local MANA = 0 -- power type
local MAX_ROWS, ROW = 8, 16
local healerBox

local function GroupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
	elseif IsInGroup() then
		units[1] = "player"
		for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
	end
	return units
end

-- The group's healers, as unit tokens (also used by the tests).
function Combat.Healers()
	local units = GroupUnits()
	local marked, guessed = {}, {}
	for _, unit in ipairs(units) do
		if UnitExists(unit) then
			local role = Plain(UnitGroupRolesAssigned(unit))
			if role == "HEALER" then marked[#marked + 1] = unit end
			local class = Plain(select(2, UnitClass(unit)))
			if class and HEALING_CLASSES[class] and Plain(UnitPowerType(unit)) == MANA then guessed[#guessed + 1] = unit end
		end
	end
	if #marked > 0 then return marked end
	if Combat.db.healersByClass then return guessed end
	return {}
end

local function ManaPercent(unit)
	if UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
		return UnitPowerPercent(unit, MANA, false, CurveConstants.ScaleTo100)
	end
	local current, maximum = Plain(UnitPower(unit, MANA)), Plain(UnitPowerMax(unit, MANA))
	if current and maximum and maximum > 0 then return current / maximum * 100 end
	return 0
end

local function UpdateHealers()
	if not healerBox then return end
	local healers = Combat.db.healerMana and Combat.Healers() or {}
	if #healers == 0 then
		healerBox:Hide()
		return
	end
	local shown = math.min(#healers, MAX_ROWS)
	for i = 1, shown do
		local row = healerBox.rows[i]
		local unit = healers[i]
		local class = Plain(select(2, UnitClass(unit)))
		local colour = class and C_ClassColor and C_ClassColor.GetClassColor(class)
		row.name:SetText(UnitName(unit))
		if colour then row.name:SetTextColor(colour.r, colour.g, colour.b) else row.name:SetTextColor(1, 1, 1) end
		if Plain(UnitIsDeadOrGhost(unit)) then
			row.mana:SetText("dead")
		else
			row.mana:SetFormattedText("%.0f%%", ManaPercent(unit))
		end
		row:Show()
	end
	for i = shown + 1, MAX_ROWS do healerBox.rows[i]:Hide() end
	healerBox:SetHeight(shown * ROW + 8)
	healerBox:Show()
end
Combat.UpdateHealers = UpdateHealers

local function BuildHealerBox()
	healerBox = Box("StzxUIHealerMana", 150, MAX_ROWS * ROW + 8)
	healerBox.rows = {}
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Frame", nil, healerBox)
		row:SetSize(140, ROW)
		row:SetPoint("TOPLEFT", 5, -4 - (i - 1) * ROW)
		row.name = row:CreateFontString(nil, "OVERLAY")
		row.name:SetFont(FONT, 11, "")
		row.name:SetPoint("LEFT")
		row.name:SetWidth(95)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.mana = row:CreateFontString(nil, "OVERLAY")
		row.mana:SetFont(FONT, 11, "")
		row.mana:SetPoint("RIGHT")
		row.mana:SetTextColor(0.45, 0.7, 1)
		healerBox.rows[i] = row
	end
	healerBox:Hide()
	StzxUI:RegisterMover("HealerMana", healerBox, {
		label = "Healers' mana",
		category = "Helpers",
		default = { "LEFT", "LEFT", 20, 120 },
		isShown = function() return Combat.db.healerMana end,
	})
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

function Combat:OnInitialize()
	local page = StzxUI:AddSettingsPage("Combat")
	StzxUI:AddHeader(page, "Combat timer")
	StzxUI:AddCheckbox(page, self, "combatTimer", "Show a combat timer",
		"How long the current fight has run. Place it in move mode.")
	StzxUI:AddSlider(page, self, "timerLinger", "Keep the final time for",
		"Seconds the fight's length stays after it ends (0: hide at once).", 0, 30, 1,
		function(value) return ("%d s"):format(value) end)
	StzxUI:AddHeader(page, "Pet")
	StzxUI:AddCheckbox(page, self, "petReminder", "Remind me when my pet is missing",
		"Hunters and warlocks, out of combat: not while mounted, on a flight or dead.", UpdatePetWarning)
	StzxUI:AddCheckbox(page, self, "petInTowns", "Also in towns and inns",
		"Off: no reminder while resting, where you may have dismissed it on purpose.", UpdatePetWarning)
	StzxUI:AddHeader(page, "Taunts, interrupts and other cooldowns",
		"Blizzard's Cooldown Manager shows your cooldowns as icons or bars, in fights too (addons can't read "
		.. "them then). StzxUI gives it StzxUI's look (Skins). Choose which spells it tracks there.")
	StzxUI:AddButton(page, "Cooldown Manager", "Open", function()
		if InCombatLockdown() then
			StzxUI:Say("the Cooldown Manager opens out of combat.")
		elseif CooldownViewerSettings and CooldownViewerSettings.TogglePanel then
			CooldownViewerSettings:TogglePanel()
		else
			StzxUI:Say("Blizzard's Cooldown Manager isn't available here.")
		end
	end, "Blizzard's own settings for it. Its icons and bars are placed with Edit Mode.")
	StzxUI:AddHeader(page, "Threat")
	StzxUI:AddCheckbox(page, self, "threatCheck", "Check whether threat is readable in fights",
		"A moment after a fight starts and again mid-fight, StzxUI looks at your target's threat and notes "
		.. "whether the game lets addons read it. After the fight it says so in chat: the first time, and "
		.. "whenever the answer changes. /stzx threat shows the last fight's answer any time.")
	StzxUI:AddHeader(page, "Healers' mana")
	StzxUI:AddCheckbox(page, self, "healerMana", "Show my group's healers' mana",
		"A small box in groups. Place it in move mode.", UpdateHealers)
	StzxUI:AddCheckbox(page, self, "healersByClass", "Guess healers when nobody is marked",
		"Shows priests, druids, shamans and paladins when no one has the healer role.", UpdateHealers)
end

function Combat:OnEnable()
	BuildTimer()
	BuildPetWarning()
	BuildHealerBox()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_PET", "PLAYER_ENTERING_WORLD",
		"PLAYER_UPDATE_RESTING", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_CONTROL_GAINED", "GROUP_ROSTER_UPDATE",
		"PLAYER_ROLES_ASSIGNED", "UNIT_FLAGS" }) do
		events:RegisterEvent(event)
	end
	events:SetScript("OnEvent", function(_, event, unit)
		if event == "PLAYER_REGEN_DISABLED" then
			FightStarted()
			if Combat.db.threatCheck then StzxUI.Threat.FightStarted() end
			UpdatePetWarning()
		elseif event == "PLAYER_REGEN_ENABLED" then
			FightEnded()
			local said = StzxUI.Threat.FightEnded()
			if said and Combat.db.threatCheck then StzxUI:Say(said) end
			UpdatePetWarning()
		elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
			UpdateHealers()
		elseif event == "UNIT_FLAGS" and unit ~= "pet" and unit ~= "player" then
			return
		else
			UpdatePetWarning()
		end
	end)
	-- Mana changes often: a light refresh a few times a second while in a group.
	C_Timer.NewTicker(0.5, function()
		if healerBox:IsShown() or IsInGroup() then UpdateHealers() end
	end)
	-- Mounting, dying and the pet dying don't all have events: check now and then.
	C_Timer.NewTicker(2, UpdatePetWarning)
	UpdatePetWarning()
	UpdateHealers()
end

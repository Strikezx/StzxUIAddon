-- StzxUI Unit Frames: party and raid frames
--
-- Each group member gets a small "cell":
--
--     party (a row)                        raid (a grid cell)
--     [Name Surname ........ 76%] ▪▪▪      [  Name   ]
--     [=========== power ========]         [   76%  ▪]
--
-- How it works:
--   * Blizzard's secure group header (SecurePartyHeaderTemplate /
--     SecureRaidGroupHeaderTemplate) decides who goes in which button and
--     handles clicks in combat. Left-click targets, right-click opens the menu.
--   * All buttons are made up front, out of combat (5 for party, 40 for raid),
--     so the header never has to create a secure frame mid-fight.
--   * Everything drawn sits on an ordinary child frame ("art") and only ever
--     shows values. Health, range and target checks can be secret in combat:
--     they go straight into bars, text and SetAlphaFromBoolean, never into
--     comparisons.

local _, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local Style = ns.Style
local A = StzxUI.ACCENT

local RANGE_EVERY = 0.5        -- seconds between range checks
local OUT_OF_RANGE_ALPHA = 0.4
local LEADER_ICON = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local MARKER_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- How many buttons each header makes up front.
local BUTTONS = { party = 5, raid = 40 }

local byUnit = {}    -- unit token -> { [button] = true }
local headers = {}   -- kind -> header

---------------------------------------------------------------------------
-- Drawing one button
---------------------------------------------------------------------------

local function UpdateDebuffs(button)
	local settings, unit = button.settings, button.unit
	local icons = button.debuffs
	local used = 0
	if settings.showDebuffs then
		-- "RAID" asks the game for debuffs you can remove; it works in combat.
		local filter = settings.onlyDispellable and "HARMFUL|RAID" or "HARMFUL"
		for _, aura in ipairs(ns.GetAuras(unit, filter, settings.maxDebuffs)) do
			if used >= settings.maxDebuffs or not icons[used + 1] then break end
			used = used + 1
			ns.SetAuraButton(icons[used], unit, aura, true)
		end
	end
	for i = used + 1, #icons do icons[i]:Hide() end
end

-- Highlight around the button of whoever you're targeting.
local function UpdateTarget(button)
	local isTarget = UnitIsUnit(button.unit, "target")
	if issecretvalue and issecretvalue(isTarget) then
		button.highlight:Show()
		button.highlight:SetAlphaFromBoolean(isTarget, 1, 0)
	else
		button.highlight:SetAlpha(1)
		button.highlight:SetShown(isTarget and true or false)
	end
end

local function UpdateIcons(button)
	local unit = button.unit
	button.leader:SetShown(Plain(UnitIsGroupLeader(unit)) == true)
	-- Raid markers are secret in combat; they catch up when it ends.
	local index = Plain(GetRaidTargetIndex(unit))
	if index and SetRaidTargetIconTexture then
		SetRaidTargetIconTexture(button.marker, index)
		button.marker:Show()
	else
		button.marker:Hide()
	end
end

-- Fade members who are too far away to heal.
local function UpdateRange(button)
	local art = button.art
	if not button.settings.rangeFade or button.unit == "player" then
		art:SetAlpha(1)
		return
	end
	local inRange, checked = UnitInRange(button.unit)
	if issecretvalue and issecretvalue(inRange) then
		art:SetAlphaFromBoolean(inRange, 1, OUT_OF_RANGE_ALPHA)
	elseif checked and not inRange then
		art:SetAlpha(OUT_OF_RANGE_ALPHA)
	else
		art:SetAlpha(1)
	end
end

local function UpdateButton(button)
	if not button.unit or not Plain(UnitExists(button.unit)) then return end
	ns.UpdateName(button)
	ns.UpdateHealth(button)
	if button.settings.powerHeight > 0 then ns.UpdatePower(button) end
	UpdateDebuffs(button)
	UpdateTarget(button)
	UpdateIcons(button)
	UpdateRange(button)
end
ns.UpdateGroupButton = UpdateButton

---------------------------------------------------------------------------
-- Layout of one button (size and settings can change, so this re-runs)
---------------------------------------------------------------------------

local function LayoutButton(button)
	local s = button.settings
	local raid = button.kind == "raid"
	local powerHeight = s.powerHeight

	button.health:ClearAllPoints()
	button.health:SetPoint("TOPLEFT")
	button.health:SetPoint("TOPRIGHT")
	button.health:SetPoint("BOTTOM", 0, powerHeight > 0 and (powerHeight + 1) or 0)
	button.power:SetHeight(math.max(powerHeight, 1))
	button.power:SetShown(powerHeight > 0)

	button.nameText:ClearAllPoints()
	button.healthText:ClearAllPoints()
	if raid then
		-- Grid cell: name on top, health text under it, both centred.
		button.nameText:SetPoint("TOP", button.health, "TOP", 0, -3)
		button.nameText:SetJustifyH("CENTER")
		button.healthText:SetPoint("BOTTOM", button.health, "BOTTOM", 0, 3)
	else
		-- Party row: name on the left, health text on the right.
		button.nameText:SetPoint("LEFT", button.health, "LEFT", 5, 0)
		button.nameText:SetJustifyH("LEFT")
		button.healthText:SetPoint("RIGHT", button.health, "RIGHT", -5, 0)
	end
	button.nameText:SetWidth(s.width - (raid and 6 or 50))

	-- Debuffs: inside the bottom-right corner for raid cells, to the right
	-- of the frame for party rows. Make more icons if the setting went up.
	for i = #button.debuffs + 1, s.maxDebuffs do
		button.debuffs[i] = ns.CreateAuraButton(button.art)
		button.debuffs[i]:Hide()
	end
	local size = s.debuffSize
	for i, icon in ipairs(button.debuffs) do
		ns.SizeAuraButton(icon, size)
		icon:ClearAllPoints()
		if raid then
			icon:SetPoint("BOTTOMRIGHT", button.health, "BOTTOMRIGHT", -2 - (i - 1) * (size + 1), 2)
		else
			icon:SetPoint("LEFT", button, "RIGHT", 4 + (i - 1) * (size + 2), 0)
		end
	end
end

-- Turns one of the header's secure buttons into a StzxUI cell. `preview`:
-- an ordinary frame drawn the same way for test frames (no clicks, no unit).
local function StyleButton(button, header, preview)
	button.kind, button.settings = header.kind, header.settings
	button.dims = { width = header.settings.width }
	if not preview then button:RegisterForClicks("AnyUp") end

	-- All the drawing hangs off "art" so range fading never touches the
	-- secure button itself.
	local art = CreateFrame("Frame", nil, button)
	art:SetAllPoints()
	Style.Panel(art)
	button.art = art

	button.health = Style.Bar(art, 10)
	button.power = Style.Bar(art, 4)
	button.power:SetPoint("BOTTOMLEFT")
	button.power:SetPoint("BOTTOMRIGHT")

	local text = CreateFrame("Frame", nil, art) -- keeps text above the bars
	text:SetAllPoints()
	text:SetFrameLevel(button.health:GetFrameLevel() + 2)
	button.nameText = Style.Text(text, header.kind == "raid" and 10 or 12)
	button.healthText = Style.Text(text, header.kind == "raid" and 10 or 11)
	button.powerText = Style.Text(text, 8) -- unused on group cells, kept for UpdatePower

	-- Target highlight: a 2-pixel accent border just outside the cell.
	local highlight = CreateFrame("Frame", nil, art)
	highlight:SetPoint("TOPLEFT", -2, 2)
	highlight:SetPoint("BOTTOMRIGHT", 2, -2)
	highlight:SetFrameLevel(text:GetFrameLevel() + 1)
	for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
		{ "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local line = highlight:CreateTexture(nil, "OVERLAY")
		line:SetColorTexture(A.r, A.g, A.b, 1)
		line:SetPoint(edge[1])
		line:SetPoint(edge[2])
		if edge[1] == "TOPLEFT" and edge[2] == "BOTTOMLEFT" or edge[1] == "TOPRIGHT" then
			line:SetWidth(2)
		else
			line:SetHeight(2)
		end
	end
	highlight:Hide()
	button.highlight = highlight

	button.leader = text:CreateTexture(nil, "OVERLAY")
	button.leader:SetTexture(LEADER_ICON)
	button.leader:SetSize(12, 12)
	button.leader:SetPoint("TOPLEFT", -3, 5)
	button.leader:Hide()

	button.marker = text:CreateTexture(nil, "OVERLAY")
	button.marker:SetTexture(MARKER_ICONS)
	button.marker:SetSize(14, 14)
	button.marker:SetPoint("TOP", 0, 6)
	button.marker:Hide()

	button.debuffs = {}
	if preview then
		LayoutButton(button)
		return
	end

	button:HookScript("OnEnter", function(self)
		if not self.unit then return end
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
		GameTooltip:SetUnit(self.unit)
		GameTooltip:Show()
	end)
	button:HookScript("OnLeave", function() GameTooltip:Hide() end)

	-- The header hands each button its unit through the "unit" attribute.
	button:HookScript("OnAttributeChanged", function(self, name, value)
		if name ~= "unit" then return end
		if self.unit and byUnit[self.unit] then byUnit[self.unit][self] = nil end
		self.unit = value
		if value then
			byUnit[value] = byUnit[value] or {}
			byUnit[value][self] = true
			UpdateButton(self)
		end
	end)
	button.stzxStyled = true
	LayoutButton(button)
end

---------------------------------------------------------------------------
-- Headers
---------------------------------------------------------------------------

-- Header attributes for each growth direction. Offsets in the secure
-- header are signed: negative y goes down, positive x goes right.
local function Growth(direction, spacing)
	if direction == "UP" then return "BOTTOM", 0, spacing end
	if direction == "RIGHT" then return "LEFT", spacing, 0 end
	if direction == "LEFT" then return "RIGHT", -spacing, 0 end
	return "TOP", 0, -spacing -- "DOWN"
end

-- Where the header sits inside its mover box, so it grows away from it.
local CORNER = { DOWN = "TOPLEFT", RIGHT = "TOPLEFT", UP = "BOTTOMLEFT", LEFT = "TOPRIGHT" }

-- The size of the mover box: room for a full party / raid.
function ns.GroupAreaSize(kind, s)
	local across, down
	if kind == "party" then
		local count = s.showPlayer and 5 or 4
		if s.growth == "LEFT" or s.growth == "RIGHT" then across, down = count, 1 else across, down = 1, count end
	elseif s.groupsAcross then
		across, down = 8, 5 -- each group a column
	else
		across, down = 5, 8 -- each group a row
	end
	return across * s.width + (across - 1) * s.spacing, down * s.height + (down - 1) * s.spacing
end

-- Secure code run for each new button (also for any made later in combat).
local function ConfigCode(s)
	return ("self:SetWidth(%d) self:SetHeight(%d) self:SetAttribute('*type1', 'target') "
		.. "self:SetAttribute('*type2', 'togglemenu')"):format(s.width, s.height)
end

local pending = {}
local function ApplyLayout(header)
	if InCombatLockdown() then
		pending[header] = true
		return
	end
	local s, kind = header.settings, header.kind
	header:SetAttribute("_ignore", "attributeChanges") -- one update at the end
	header:SetAttribute("initialConfigFunction", ConfigCode(s))
	if kind == "party" then
		local point, x, y = Growth(s.growth, s.spacing)
		header:SetAttribute("point", point)
		header:SetAttribute("xOffset", x)
		header:SetAttribute("yOffset", y)
		header:SetAttribute("showPlayer", s.showPlayer)
		header:SetAttribute("showSolo", s.showSolo)
		header:ClearAllPoints()
		local corner = CORNER[s.growth] or "TOPLEFT"
		header:SetPoint(corner, header.area, corner)
	else
		if s.groupsAcross then
			-- Members go down, groups go right.
			header:SetAttribute("point", "TOP")
			header:SetAttribute("xOffset", 0)
			header:SetAttribute("yOffset", -s.spacing)
			header:SetAttribute("columnAnchorPoint", "LEFT")
		else
			-- Members go right, groups go down.
			header:SetAttribute("point", "LEFT")
			header:SetAttribute("xOffset", s.spacing)
			header:SetAttribute("yOffset", 0)
			header:SetAttribute("columnAnchorPoint", "TOP")
		end
		header:SetAttribute("columnSpacing", s.spacing)
		header:SetAttribute("groupBy", "GROUP")
		header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
		header:SetAttribute("unitsPerColumn", 5)
		header:SetAttribute("maxColumns", 8)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", header.area, "TOPLEFT")
	end
	header:SetAttribute("_ignore", nil)

	local i = 1
	while header[i] do
		local button = header[i]
		button:SetSize(s.width, s.height)
		button.dims.width = s.width
		LayoutButton(button)
		if button.unit then UpdateButton(button) end
		i = i + 1
	end
	header.area:SetSize(ns.GroupAreaSize(kind, s))
	header:SetAttribute("startingIndex", 1) -- triggers the header to re-place its buttons
	if header.preview and header.preview:IsShown() then ns.LayoutPreview(header) end
end
ns.ApplyGroupLayout = ApplyLayout

local VISIBILITY = {
	party = "[group:raid] hide; [group:party] show; hide",
	partySolo = "[group:raid] hide; show",
	raid = "[group:raid] show; hide",
}

-- kind: "party" or "raid". area: the movable box the header sits in.
function ns.CreateGroupHeader(kind, area, settings)
	local template = kind == "party" and "SecurePartyHeaderTemplate" or "SecureRaidGroupHeaderTemplate"
	local name = kind == "party" and "StzxUIPartyHeader" or "StzxUIRaidHeader"
	-- Parented to its box, so resizing the box in move mode resizes the frames.
	local header = CreateFrame("Frame", name, area, template)
	header.kind, header.area, header.settings = kind, area, settings
	header:SetAttribute("template", "SecureUnitButtonTemplate")
	header:SetAttribute("templateType", "Button")
	header:SetFrameStrata("LOW")
	headers[kind] = header
	ApplyLayout(header)

	-- Make every button now, out of combat: with a negative starting index
	-- the header builds buttons for members that aren't there yet.
	header:Show()
	header:SetAttribute("startingIndex", 1 - BUTTONS[kind])
	header:SetAttribute("startingIndex", 1)
	local i = 1
	while header[i] do
		if not header[i].stzxStyled then StyleButton(header[i], header) end
		i = i + 1
	end

	local visibility = VISIBILITY[kind]
	if kind == "party" and settings.showSolo then visibility = VISIBILITY.partySolo end
	RegisterStateDriver(header, "visibility", visibility)
	return header
end

---------------------------------------------------------------------------
-- Test frames: pretend members drawn exactly like the real cells
---------------------------------------------------------------------------
-- The secure header only ever shows real group members, so test frames are
-- ordinary frames on top, laid out the way the header would, using the same
-- settings. They cover the cases worth seeing: dead, offline, out of range,
-- the leader, a raid marker, your target and some debuffs.

local NAMES = { "Liala", "Gorr", "Tamsin", "Brannoc", "Elowen", "Krag", "Mirel", "Doran", "Sefa", "Thalric" }
local CLASSES = { "DRUID", "WARRIOR", "MAGE", "PALADIN", "PRIEST", "SHAMAN", "ROGUE", "HUNTER", "WARLOCK" }
local DEBUFFS = {
	{ icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", dispelName = "Magic" },
	{ icon = "Interface\\Icons\\Spell_Nature_CorrosiveBreath", dispelName = "Poison", applications = 3 },
	{ icon = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras", dispelName = "Curse" },
	{ icon = "Interface\\Icons\\Spell_Nature_NullifyDisease", dispelName = "Disease" },
}
local GREY = { r = 0.45, g = 0.45, b = 0.45 }
local MANA, RAGE = { r = 0.00, g = 0.44, b = 0.87 }, { r = 0.78, g = 0.25, b = 0.25 }

-- Pretend member number i of a party (5) or raid (40).
function ns.TestMember(kind, i, withPlayer)
	local m = {
		name = NAMES[(i - 1) % #NAMES + 1],
		class = CLASSES[(i - 1) % #CLASSES + 1],
		health = ((i * 37) % 85 + 15) / 100,
	}
	if kind == "raid" and i > #NAMES then m.name = m.name .. " " .. math.ceil(i / #NAMES) end
	if kind == "party" and withPlayer and i == 1 then
		local name = Plain(UnitName("player"))
		local _, class = UnitClass("player")
		m.name, m.class, m.health, m.you = name or "You", Plain(class) or m.class, 1, true
	end
	local leader, dead, offline, target = 2, 3, 5, 2
	local far = { [4] = true }
	local debuffs = { [2] = { 1, 2 }, [4] = { 3 } }
	if kind == "raid" then
		leader, dead, offline, target = 1, 7, 12, 9
		far = { [15] = true, [16] = true, [17] = true, [33] = true }
		debuffs = { [3] = { 1 }, [9] = { 2, 4 }, [21] = { 3 }, [26] = { 1, 2 } }
		if i == 1 then m.marker = 8 elseif i == 4 then m.marker = 7 end
	end
	m.leader, m.dead, m.offline, m.target, m.far = i == leader, i == dead, i == offline, i == target, far[i]
	m.debuffs = debuffs[i]
	return m
end

local function PaintPreview(cell, m)
	local s = cell.settings
	cell.nameText:SetText(m.name)
	cell.nameText:SetTextColor(1, 1, 1)

	local bar, text = cell.health, cell.healthText
	local colour = Style.GREEN
	if s.healthColour ~= "GREEN" then
		colour = (C_ClassColor and C_ClassColor.GetClassColor(m.class)) or Style.GREEN
	end
	bar:SetMinMaxValues(0, 1)
	if m.dead or m.offline then
		bar:SetValue(m.offline and 1 or 0)
		bar:SetColor(GREY)
		text:SetText(m.offline and "Offline" or "Dead")
	else
		bar:SetValue(m.health)
		bar:SetColor(colour)
		local hp, pct = math.floor(m.health * 4200), math.floor(m.health * 100 + 0.5)
		if s.healthText == "NUMBER" then
			text:SetText(hp)
		elseif s.healthText == "PERCENT" then
			text:SetText(pct .. "%")
		elseif s.healthText == "BOTH" then
			text:SetText(("%d | %d%%"):format(hp, pct))
		else
			text:SetText("")
		end
	end

	if s.powerHeight > 0 then
		cell.power:SetMinMaxValues(0, 1)
		cell.power:SetValue((m.dead or m.offline) and 0 or 0.65)
		cell.power:SetColor(m.class == "WARRIOR" and RAGE or MANA)
	end

	local shown = 0
	if s.showDebuffs and m.debuffs and not m.dead then
		for _, index in ipairs(m.debuffs) do
			if shown >= s.maxDebuffs or not cell.debuffs[shown + 1] then break end
			local d = DEBUFFS[index]
			shown = shown + 1
			ns.SetAuraButton(cell.debuffs[shown], "player", { auraInstanceID = 0, icon = d.icon,
				duration = 0, expirationTime = 0, applications = d.applications or 0, dispelName = d.dispelName }, true)
		end
	end
	for i = shown + 1, #cell.debuffs do cell.debuffs[i]:Hide() end

	cell.art:SetAlpha((m.far and s.rangeFade) and OUT_OF_RANGE_ALPHA or 1)
	cell.leader:SetShown(m.leader)
	if m.marker and SetRaidTargetIconTexture then
		SetRaidTargetIconTexture(cell.marker, m.marker)
		cell.marker:Show()
	else
		cell.marker:Hide()
	end
	cell.highlight:SetAlpha(1)
	cell.highlight:SetShown(m.target)
end

-- Place and paint the pretend cells where the header would put real ones.
function ns.LayoutPreview(header)
	local s, kind, preview = header.settings, header.kind, header.preview
	local count = kind == "party" and (s.showPlayer and 5 or 4) or 40
	for i = 1, math.max(count, #preview.cells) do
		local cell = preview.cells[i]
		if i > count then
			if cell then cell:Hide() end
		else
			if not cell then
				cell = CreateFrame("Frame", nil, preview)
				StyleButton(cell, header, true)
				preview.cells[i] = cell
			end
			cell:SetSize(s.width, s.height)
			cell.dims.width = s.width
			LayoutButton(cell)
			cell:ClearAllPoints()
			local stepX, stepY = s.width + s.spacing, s.height + s.spacing
			if kind == "party" then
				local n = i - 1
				if s.growth == "UP" then
					cell:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 0, n * stepY)
				elseif s.growth == "RIGHT" then
					cell:SetPoint("TOPLEFT", preview, "TOPLEFT", n * stepX, 0)
				elseif s.growth == "LEFT" then
					cell:SetPoint("TOPRIGHT", preview, "TOPRIGHT", -n * stepX, 0)
				else
					cell:SetPoint("TOPLEFT", preview, "TOPLEFT", 0, -n * stepY)
				end
				PaintPreview(cell, ns.TestMember("party", s.showPlayer and i or i + 1, s.showPlayer))
			else
				local group, slot = math.floor((i - 1) / 5), (i - 1) % 5
				if s.groupsAcross then
					cell:SetPoint("TOPLEFT", preview, "TOPLEFT", group * stepX, -slot * stepY)
				else
					cell:SetPoint("TOPLEFT", preview, "TOPLEFT", slot * stepX, -group * stepY)
				end
				PaintPreview(cell, ns.TestMember("raid", i))
			end
			cell:Show()
		end
	end
end

local function ShowTest(on)
	for _, header in pairs(headers) do
		if on and not header.preview then
			local preview = CreateFrame("Frame", nil, header.area)
			preview:SetAllPoints()
			preview:SetFrameLevel(header:GetFrameLevel() + 20)
			preview.cells = {}
			header.preview = preview
		end
		if header.preview then
			header.preview:SetShown(on)
			if on then ns.LayoutPreview(header) end
		end
		-- Real members (if you're grouped) step aside while testing. Never in
		-- combat: test frames are switched off before combat starts.
		if not InCombatLockdown() then header:SetAlpha(on and 0 or 1) end
	end
end

---------------------------------------------------------------------------
-- Events: one listener for every group button
---------------------------------------------------------------------------

local function ForUnit(unit, fn)
	local set = unit and byUnit[unit]
	if not set then return end
	for button in pairs(set) do
		if button:IsVisible() then fn(button) end
	end
end

local function ForAll(fn)
	for _, set in pairs(byUnit) do
		for button in pairs(set) do
			if button:IsVisible() then fn(button) end
		end
	end
end

local UNIT_EVENTS = {
	UNIT_HEALTH = ns.UpdateHealth,
	UNIT_MAXHEALTH = ns.UpdateHealth,
	UNIT_CONNECTION = ns.UpdateHealth,
	UNIT_FLAGS = ns.UpdateHealth,
	UNIT_POWER_FREQUENT = function(b) if b.settings.powerHeight > 0 then ns.UpdatePower(b) end end,
	UNIT_MAXPOWER = function(b) if b.settings.powerHeight > 0 then ns.UpdatePower(b) end end,
	UNIT_DISPLAYPOWER = function(b) if b.settings.powerHeight > 0 then ns.UpdatePower(b) end end,
	UNIT_NAME_UPDATE = ns.UpdateName,
	UNIT_AURA = UpdateDebuffs,
}
local ALL_EVENTS = {
	PLAYER_TARGET_CHANGED = UpdateTarget,
	PARTY_LEADER_CHANGED = UpdateIcons,
	RAID_TARGET_UPDATE = UpdateIcons,
	GROUP_ROSTER_UPDATE = UpdateButton,
	PLAYER_ENTERING_WORLD = UpdateButton,
}

local driver = CreateFrame("Frame")
ns.groupDriver = driver
function ns.StartGroupEvents()
	StzxUI:RegisterTestMode("groups", ShowTest)
	for event in pairs(UNIT_EVENTS) do driver:RegisterEvent(event) end
	for event in pairs(ALL_EVENTS) do driver:RegisterEvent(event) end
	driver:RegisterEvent("PLAYER_REGEN_ENABLED")
end
driver:SetScript("OnEvent", function(_, event, unit)
	if UNIT_EVENTS[event] then
		ForUnit(unit, UNIT_EVENTS[event])
	elseif ALL_EVENTS[event] then
		ForAll(ALL_EVENTS[event])
	elseif event == "PLAYER_REGEN_ENABLED" then
		for header in pairs(pending) do
			pending[header] = nil
			ApplyLayout(header)
		end
		ForAll(UpdateIcons) -- raid markers set during combat
	end
end)

local wait = 0
driver:SetScript("OnUpdate", function(_, elapsed)
	wait = wait - elapsed
	if wait > 0 then return end
	wait = RANGE_EVERY
	ForAll(UpdateRange)
end)

-- For the options page: redraw after a setting changes.
function ns.RefreshGroups()
	for _, header in pairs(headers) do ApplyLayout(header) end
end

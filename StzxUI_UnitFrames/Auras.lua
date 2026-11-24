-- StzxUI Unit Frames: buffs and debuffs
-- Small aura icons above (or below) the player and target frames: debuffs
-- first, nearest the frame, then buffs. Each icon shows a duration swipe and
-- a stack count; debuffs get a border in their type's colour.
--
-- Forever note: in combat the game hides aura details from addons ("secret"
-- values). Everything here only *shows* them:
--   * the list comes from C_UnitAuras.GetUnitAuras (the game does the filtering,
--     including "only my debuffs", so it still works in combat)
--   * icons: Texture:SetTexture accepts secret textures
--   * swipe: out of combat from the plain times; in combat the game's own
--     duration object goes straight into the cooldown swipe
--   * stacks: the game's own count text (GetAuraApplicationDisplayCount)

local _, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local Style = ns.Style

local MAX_EACH = 16 -- most buffs / debuffs shown per frame
local SPACING = 2

-- Debuff borders by type; untyped debuffs are red.
local DEBUFF_COLOURS = {
	Magic = { 0.20, 0.60, 1.00 },
	Curse = { 0.60, 0.00, 1.00 },
	Disease = { 0.60, 0.40, 0.00 },
	Poison = { 0.00, 0.60, 0.00 },
	none = { 0.80, 0.00, 0.00 },
}

local SORT = Enum and Enum.UnitAuraSortRule and Enum.UnitAuraSortRule.Expiration

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------

local function ShowTooltip(button)
	GameTooltip:SetOwner(button, "ANCHOR_BOTTOMRIGHT")
	local ok = pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, button.unit, button.auraInstanceID)
	if ok then GameTooltip:Show() else GameTooltip:Hide() end
end

local function CreateButton(container)
	local button = CreateFrame("Frame", nil, container)
	button.border = button:CreateTexture(nil, "BACKGROUND")
	button.border:SetPoint("TOPLEFT", -1, 1)
	button.border:SetPoint("BOTTOMRIGHT", 1, -1)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints()
	button.cooldown:SetReverse(true)
	button.cooldown:SetDrawEdge(false)
	button.count = button:CreateFontString(nil, "OVERLAY")
	button.count:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	button.count:SetPoint("BOTTOMRIGHT", 2, -1)
	button:EnableMouse(true)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return button
end

-- The duration swipe, whatever the game lets us see.
local function SetSwipe(button, unit, aura)
	local cooldown = button.cooldown
	local duration, expires = Plain(aura.duration), Plain(aura.expirationTime)
	if duration and expires then
		if duration > 0 then
			cooldown:SetCooldown(expires - duration, duration)
			cooldown:Show()
		else
			cooldown:Clear()
			cooldown:Hide()
		end
		return
	end
	-- Secret times: hand the game's own duration object to the swipe.
	local ok = pcall(function()
		cooldown:SetCooldownFromDurationObject(C_UnitAuras.GetAuraDuration(unit, aura.auraInstanceID))
	end)
	cooldown:SetShown(ok)
end

local function SetCount(button, unit, aura)
	local stacks = Plain(aura.applications)
	if stacks then
		button.count:SetText(stacks > 1 and stacks or "")
		return
	end
	local ok, text = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, aura.auraInstanceID, 2, 99)
	button.count:SetText(ok and text or "")
end

local function SetBorder(button, harmful, aura)
	if not harmful then
		button.border:SetColorTexture(0, 0, 0, 1)
		return
	end
	local kind = Plain(aura.dispelName)
	local colour = (kind and DEBUFF_COLOURS[kind]) or DEBUFF_COLOURS.none
	button.border:SetColorTexture(colour[1], colour[2], colour[3], 1)
end

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------

-- The unit's auras for a filter, or an empty list if the game says no.
local function GetAuras(unit, filter)
	if not (C_UnitAuras and C_UnitAuras.GetUnitAuras) then return {} end
	local ok, list = pcall(C_UnitAuras.GetUnitAuras, unit, filter, MAX_EACH, SORT)
	if ok and type(list) == "table" then return list end
	return {}
end

function ns.UpdateAuras(frame)
	local container, settings, unit = frame.auraContainer, frame.settings, frame.unit
	if not container then return end
	local size = settings.auraSize or 22
	local left = frame.side == "LEFT"
	local above = settings.auraPosition ~= "BELOW"
	local perRow = math.max(1, math.floor((Style.WIDTH + SPACING) / (size + SPACING)))

	-- Where the icons start: just outside the frame, on the portrait's side.
	container:ClearAllPoints()
	if above then
		container:SetPoint(left and "BOTTOMLEFT" or "BOTTOMRIGHT", frame, left and "TOPLEFT" or "TOPRIGHT", 0, 4)
	else
		container:SetPoint(left and "TOPLEFT" or "TOPRIGHT", frame, left and "BOTTOMLEFT" or "BOTTOMRIGHT", 0, -4)
	end

	local groups = {}
	if settings.showDebuffs then
		local filter = (settings.onlyMine and unit ~= "player") and "HARMFUL|PLAYER" or "HARMFUL"
		table.insert(groups, { harmful = true, auras = GetAuras(unit, filter) })
	end
	if settings.showBuffs then
		table.insert(groups, { harmful = false, auras = GetAuras(unit, "HELPFUL") })
	end

	local used, row, col = 0, 0, 0
	local side = left and "LEFT" or "RIGHT"
	local direction = left and 1 or -1
	for _, group in ipairs(groups) do
		if col > 0 then row, col = row + 1, 0 end -- each group starts on a new row
		for _, aura in ipairs(group.auras) do
			used = used + 1
			local button = container.buttons[used]
			if not button then
				button = CreateButton(container)
				container.buttons[used] = button
			end
			button.unit, button.auraInstanceID = unit, aura.auraInstanceID
			button:SetSize(size, size)
			button:ClearAllPoints()
			local x, y = col * (size + SPACING) * direction, row * (size + SPACING)
			if above then
				button:SetPoint("BOTTOM" .. side, container, "BOTTOM" .. side, x, y)
			else
				button:SetPoint("TOP" .. side, container, "TOP" .. side, x, -y)
			end
			button.icon:SetTexture(aura.icon)
			SetBorder(button, group.harmful, aura)
			SetSwipe(button, unit, aura)
			SetCount(button, unit, aura)
			button:Show()
			col = col + 1
			if col >= perRow then row, col = row + 1, 0 end
		end
	end
	for i = used + 1, #container.buttons do
		container.buttons[i]:Hide()
	end
end

function ns.CreateAuraContainer(frame)
	local container = CreateFrame("Frame", nil, frame)
	container:SetSize(Style.WIDTH, 1)
	container.buttons = {}
	frame.auraContainer = container
	frame:RegisterUnitEvent("UNIT_AURA", frame.unit)
	return container
end

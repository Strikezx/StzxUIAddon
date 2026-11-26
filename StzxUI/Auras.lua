-- StzxUI core: aura icons
-- One small square icon for a buff or debuff, shared by the unit frames,
-- the party and raid frames and the nameplates:
--   * a 1-pixel border inside its own edge (debuffs coloured by type), so
--     the space between icons is a real gap
--   * a duration swipe, and stack and time-left numbers sized to the icon
--
-- Forever note: in combat the game hides aura details from addons ("secret"
-- values). Everything here only *shows* them:
--   * the list comes from C_UnitAuras.GetUnitAuras (the game does the
--     filtering, including "only mine"). Tested on Forever: in a fight the
--     game refuses it outright, so rows keep the icons they had (see Keeping)
--   * icons: Texture:SetTexture accepts secret textures
--   * swipe: out of combat from the plain times; in combat the game's own
--     duration object goes straight into the cooldown swipe
--   * stacks: the game's own count text (GetAuraApplicationDisplayCount)
--
-- In a fight the game refuses addons every unit's auras outright ("Auras
-- cannot be accessed when secret while tainted"), even your own. So a row
-- keeps the icons it had when a fight starts (Keeping), each dropping off
-- when its time runs out, and reads them again when combat ends.
--
-- StzxUI.Auras.Get(unit, filter, max)            -> list of aura data, refused?
-- StzxUI.Auras.Keeping(holder, unit, refused)    -> true: keep what's shown
-- StzxUI.Auras.Create(parent)                     -> icon
-- StzxUI.Auras.Size(icon, size)
-- StzxUI.Auras.Set(icon, unit, aura, harmful)     -> fills it in and shows it

local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local MAX_EACH = 16 -- most buffs / debuffs shown per frame

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

-- Each icon: a 1-pixel border inside its own edge, so the space between
-- icons is a real gap. Its numbers (time left in the middle, stacks in the
-- bottom-right corner) are sized to the icon so they stay inside it.
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function SizeButton(button, size)
	button:SetSize(size, size)
	if button.fontFor == size then return end
	button.fontFor = size
	button.count:SetFont(FONT, math.max(7, math.floor(size * 0.38)), "OUTLINE")
	local countdown = button.cooldown.GetCountdownFontString and button.cooldown:GetCountdownFontString()
	if countdown then
		countdown:SetFont(FONT, math.max(7, math.floor(size * 0.42)), "OUTLINE")
		countdown:ClearAllPoints()
		countdown:SetPoint("CENTER", 0, 1)
	end
end

local function CreateButton(container)
	local button = CreateFrame("Frame", nil, container)
	button.border = button:CreateTexture(nil, "BACKGROUND")
	button.border:SetAllPoints()
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", 1, -1)
	button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetPoint("TOPLEFT", 1, -1)
	button.cooldown:SetPoint("BOTTOMRIGHT", -1, 1)
	button.cooldown:SetReverse(true)
	button.cooldown:SetDrawEdge(false)
	-- Stacks sit above the swipe, tucked inside the corner.
	local text = CreateFrame("Frame", nil, button)
	text:SetAllPoints()
	text:SetFrameLevel(button.cooldown:GetFrameLevel() + 2)
	button.count = text:CreateFontString(nil, "OVERLAY")
	button.count:SetPoint("BOTTOMRIGHT", -1, 2)
	button.count:SetJustifyH("RIGHT")
	SizeButton(button, 22)
	button:EnableMouse(true)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- An icon kept through a fight goes when its time is up (outside fights
	-- the game's own update would remove it anyway).
	button.cooldown:HookScript("OnCooldownDone", function()
		if button.expires and GetTime() >= button.expires - 0.5 then button:Hide() end
	end)
	return button
end

-- The duration swipe, whatever the game lets us see.
local function SetSwipe(button, unit, aura)
	local cooldown = button.cooldown
	local duration, expires = Plain(aura.duration), Plain(aura.expirationTime)
	button.expires = nil
	if duration and expires then
		if duration > 0 then
			button.expires = expires
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

local lastError -- the game's last refusal, for /stzx auras

-- The unit's auras for a filter, or an empty list and true if the game
-- says no. Sorted by time left where the game allows; if a sorted list is
-- refused, asks again unsorted.
local function GetAuras(unit, filter, max)
	if not (C_UnitAuras and C_UnitAuras.GetUnitAuras) then return {}, false end
	local ok, list = pcall(C_UnitAuras.GetUnitAuras, unit, filter, max or MAX_EACH, SORT)
	if not ok and SORT then
		lastError = list
		ok, list = pcall(C_UnitAuras.GetUnitAuras, unit, filter, max or MAX_EACH)
	end
	if not ok then
		lastError = list
		return {}, true
	end
	if type(list) == "table" then return list, false end
	return {}, false
end

-- Whether a row should keep the icons it's showing. Call after reading:
--   * read fine: remembers whose icons these are; false (draw the new list)
--   * refused, same unit as before: true (keep them)
--   * refused, a different unit (a new target mid-fight): false, and the row
--     is drawn empty rather than showing someone else's auras
-- Where the game hides who a unit is (its GUID comes back secret), the row
-- keeps its icons until the frame says the unit changed (Auras.UnitChanged).
local function Keeping(holder, unit, refused)
	local guid = Plain(UnitGUID(unit))
	if not refused then
		holder.auraGUID, holder.auraFresh = guid, true
		return false
	end
	if guid ~= nil then
		if holder.auraGUID == guid then return true end
	elseif holder.auraFresh then
		return true
	end
	holder.auraGUID, holder.auraFresh = nil, false
	return false
end

-- The frame now shows someone else (a new target, a roster change): kept icons go.
local function UnitChanged(holder)
	if holder then holder.auraGUID, holder.auraFresh = nil, false end
end


StzxUI.Auras = {
	Get = function(unit, filter, max) return GetAuras(unit, filter, max) end,
	Keeping = Keeping,
	UnitChanged = UnitChanged,
	LastError = function() return lastError end,
	-- For /stzx auras: one plain unsorted ask. Returns the count, or nil and the game's reason.
	Try = function(unit, filter)
		if not (C_UnitAuras and C_UnitAuras.GetUnitAuras) then return nil, "no C_UnitAuras.GetUnitAuras" end
		local ok, list = pcall(C_UnitAuras.GetUnitAuras, unit, filter, 16)
		if not ok then return nil, tostring(list) end
		return type(list) == "table" and #list or 0
	end,
	Create = CreateButton,
	Size = SizeButton,
	Set = function(button, unit, aura, harmful)
		button.unit, button.auraInstanceID = unit, aura.auraInstanceID
		button.icon:SetTexture(aura.icon)
		SetBorder(button, harmful, aura)
		SetSwipe(button, unit, aura)
		SetCount(button, unit, aura)
		button:Show()
	end,
}

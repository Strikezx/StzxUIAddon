-- StzxUI Unit Frames: one unit frame (player or target)
--
--        [debuff][debuff]  [buff][buff][buff]     (Auras.lua)
--        (portrait)  Name Surname
--        (  icon  )  [=========== health ======== 530 | 76% ]
--        (  (18)  )  [====== power ====== 18.2K / 22K ]
--
-- The frame is a secure unit button: left-click targets the unit, right-click
-- opens its menu, and it works in combat. Everything drawn on it is ordinary
-- (insecure) and only ever *shows* values. Health and power can be "secret"
-- in combat on Forever, so they go straight into bars and text without any
-- maths or comparisons; Blizzard's number formatting accepts secret values.

local _, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local Style = ns.Style
local A = StzxUI.ACCENT

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------

-- The round portrait: accent ring, dark disc, then the class icon or the
-- character's face, and a small level badge.
local function CreatePortrait(frame)
	local size = frame.dims.portrait
	local p = CreateFrame("Frame", nil, frame)
	p:SetSize(size, size)
	p:SetFrameLevel(frame:GetFrameLevel() + 5)

	p.ring = p:CreateTexture(nil, "BACKGROUND", nil, 1)
	p.ring:SetTexture(Style.ROUND_MASK)
	p.ring:SetPoint("CENTER")
	p.ring:SetSize(size + 4, size + 4)
	p.ring:SetVertexColor(A.r, A.g, A.b)

	p.disc = p:CreateTexture(nil, "BACKGROUND", nil, 2)
	p.disc:SetTexture(Style.ROUND_MASK)
	p.disc:SetAllPoints()
	p.disc:SetVertexColor(0.06, 0.07, 0.09)

	p.icon = p:CreateTexture(nil, "ARTWORK")
	p.icon:SetPoint("CENTER")
	p.icon:SetSize(size - 4, size - 4)

	p.face = p:CreateTexture(nil, "ARTWORK")
	p.face:SetPoint("CENTER")
	p.face:SetSize(size - 4, size - 4)
	local mask = p:CreateMaskTexture()
	mask:SetTexture(Style.ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(p.face)
	p.face:AddMaskTexture(mask)

	-- Level badge on the lower edge of the portrait
	local badge = CreateFrame("Frame", nil, p)
	badge:SetSize(20, 20)
	badge:SetFrameLevel(p:GetFrameLevel() + 2)
	badge.ring = badge:CreateTexture(nil, "BACKGROUND", nil, 1)
	badge.ring:SetTexture(Style.ROUND_MASK)
	badge.ring:SetPoint("CENTER")
	badge.ring:SetSize(22, 22)
	badge.ring:SetVertexColor(A.r, A.g, A.b)
	badge.disc = badge:CreateTexture(nil, "BACKGROUND", nil, 2)
	badge.disc:SetTexture(Style.ROUND_MASK)
	badge.disc:SetAllPoints()
	badge.disc:SetVertexColor(0.06, 0.07, 0.09)
	badge.text = badge:CreateFontString(nil, "OVERLAY")
	badge.text:SetFont(FONT, 10, "")
	badge.text:SetPoint("CENTER", 0, 0)
	p.badge = badge
	return p
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------

local function HealthPercent(unit)
	if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
		return UnitHealthPercent(unit, false, CurveConstants.ScaleTo100)
	end
	local current, maximum = Plain(UnitHealth(unit)), Plain(UnitHealthMax(unit))
	if current and maximum and maximum > 0 then return current / maximum * 100 end
	return 0
end

local function UpdateHealth(frame)
	local unit, settings = frame.unit, frame.settings
	local bar, text = frame.health, frame.healthText

	bar:SetMinMaxValues(0, UnitHealthMax(unit))
	bar:SetValue(UnitHealth(unit))

	local offline = Plain(UnitIsConnected(unit)) == false
	local dead = Plain(UnitIsDeadOrGhost(unit))
	if offline or dead then
		bar:SetColor(Style.DEAD)
		text:SetText(offline and "Offline" or (Plain(UnitIsGhost(unit)) and "Ghost" or "Dead"))
		return
	end
	-- Group frames carry their own colour choice; the big frames share one.
	local colourMode = settings.healthColour or ns.module.db.healthColour
	bar:SetColor(colourMode == "GREEN" and Style.GREEN or Style.UnitColour(unit))

	local mode = settings.healthText
	if mode == "NUMBER" then
		text:SetText(AbbreviateLargeNumbers(UnitHealth(unit)))
	elseif mode == "PERCENT" then
		text:SetFormattedText("%.0f%%", HealthPercent(unit))
	elseif mode == "BOTH" then
		text:SetFormattedText("%s | %.0f%%", AbbreviateLargeNumbers(UnitHealth(unit)), HealthPercent(unit))
	else
		text:SetText("")
	end
end

local function UpdatePower(frame)
	local unit = frame.unit
	local bar, text = frame.power, frame.powerText
	local maximum = UnitPowerMax(unit)
	bar:SetMinMaxValues(0, maximum)
	bar:SetValue(UnitPower(unit))
	bar:SetColor(Style.PowerColour(unit))
	if frame.settings.powerText and Plain(maximum) ~= 0 then
		text:SetFormattedText("%s / %s", AbbreviateLargeNumbers(UnitPower(unit)), AbbreviateLargeNumbers(maximum))
	else
		text:SetText("")
	end
end

local function UpdateName(frame)
	local name, surname = UnitName(frame.unit)
	-- Forever names have a surname. A secret value can't be tested, only shown.
	if issecretvalue and issecretvalue(surname) then
		frame.nameText:SetFormattedText("%s %s", name, surname)
	elseif surname and surname ~= "" then
		frame.nameText:SetFormattedText("%s %s", name or "", surname)
	else
		frame.nameText:SetText(name or "")
	end
end

-- Shared with the party and raid frames (Group.lua).
ns.UpdateHealth, ns.UpdatePower, ns.UpdateName = UpdateHealth, UpdatePower, UpdateName

local function UpdateLevel(frame)
	local level = Plain(UnitLevel(frame.unit))
	local kind = Plain(UnitClassification(frame.unit))
	local text = (not level or level < 0) and "??" or tostring(level)
	if kind == "elite" or kind == "rareelite" then text = text .. "+" end
	frame.portrait.badge.text:SetText(text)
end

local function UpdatePortrait(frame)
	local p, mode, unit = frame.portrait, frame.settings.portrait, frame.unit
	if mode == "NONE" then
		p:Hide()
		return
	end
	p:Show()
	local size = frame.dims.portrait

	-- Jiberish icon styles (if that addon is installed). NPCs have no class
	-- icon, so they fall back to their face below.
	local jiberish = ns.JiberishStyleOf(mode)
	if jiberish then
		if ns.ApplyJiberishIcon(p.icon, unit, jiberish) then
			p.icon:SetSize(size, size)
			p.icon:Show()
			p.face:Hide()
			return
		end
		mode = "ICON"
	end

	p.icon:SetSize(size - 4, size - 4)
	local _, class = UnitClass(unit)
	class = Plain(class)
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if mode == "ICON" and Plain(UnitIsPlayer(unit)) and coords then
		p.icon:SetTexture(Style.CLASS_ICONS)
		p.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
		p.icon:Show()
		p.face:Hide()
	else
		-- "Character portrait", and NPCs in icon mode (they have no class icon).
		SetPortraitTexture(p.face, unit)
		p.face:Show()
		p.icon:Hide()
	end
end

-- Positions that depend on settings: portrait on/off and which side it's on.
local function ApplyLayout(frame)
	local left = frame.side == "LEFT"
	local hasPortrait = frame.settings.portrait ~= "NONE"
	local p = frame.portrait
	p:SetShown(hasPortrait)
	p:ClearAllPoints()
	p:SetPoint("CENTER", frame.body, left and "LEFT" or "RIGHT", left and 2 or -2, 0)
	p.badge:ClearAllPoints()
	p.badge:SetPoint("CENTER", p, left and "BOTTOMLEFT" or "BOTTOMRIGHT", left and 6 or -6, 6)

	local outer = hasPortrait and (frame.dims.portrait / 2 + 8) or 6
	frame.nameText:ClearAllPoints()
	frame.nameText:SetPoint(left and "BOTTOMLEFT" or "BOTTOMRIGHT", frame.body, left and "TOPLEFT" or "TOPRIGHT",
		left and outer or -outer, 3)
	frame.nameText:SetJustifyH(left and "LEFT" or "RIGHT")
	frame.nameText:SetWidth(frame.dims.width - outer - 4)

	-- Numbers sit on the inner end, away from the portrait.
	frame.healthText:ClearAllPoints()
	frame.healthText:SetPoint(left and "RIGHT" or "LEFT", frame.health, left and "RIGHT" or "LEFT", left and -6 or 6, 0)
	frame.powerText:ClearAllPoints()
	frame.powerText:SetPoint(left and "RIGHT" or "LEFT", frame.power, left and "RIGHT" or "LEFT", left and -6 or 6, 0)
	-- The target's bars empty towards its portrait, like a mirror image.
	frame.health:SetReverseFill(not left)
	frame.power:SetReverseFill(not left)
end

function ns.UpdateUnitFrame(frame)
	if not frame then return end
	ApplyLayout(frame)
	if not Plain(UnitExists(frame.unit)) then return end
	UpdateName(frame)
	UpdateLevel(frame)
	UpdatePortrait(frame)
	UpdateHealth(frame)
	UpdatePower(frame)
	ns.UpdateAuras(frame)
end

-- A new width for a frame (its bars, name and buffs follow). Secure frame:
-- only out of combat; returns false in combat.
function ns.SetFrameWidth(frame, width)
	if InCombatLockdown() then return false end
	frame.dims.width = width
	frame:SetWidth(width)
	if frame.auraContainer then frame.auraContainer:SetWidth(width) end
	ns.UpdateUnitFrame(frame)
	return true
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local HEALTH_EVENTS = { UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_CONNECTION = true }
local POWER_EVENTS = { UNIT_POWER_FREQUENT = true, UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true }

local function OnEvent(frame, event)
	if HEALTH_EVENTS[event] then
		UpdateHealth(frame)
	elseif POWER_EVENTS[event] then
		UpdatePower(frame)
	elseif event == "UNIT_NAME_UPDATE" then
		UpdateName(frame)
	elseif event == "UNIT_LEVEL" or event == "UNIT_CLASSIFICATION_CHANGED" then
		UpdateLevel(frame)
	elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
		UpdatePortrait(frame)
	elseif event == "UNIT_AURA" or event == "PLAYER_REGEN_ENABLED" then
		ns.UpdateAuras(frame)
	elseif event == "UNIT_FACTION" or event == "UNIT_FLAGS" then
		UpdateHealth(frame) -- colour may change (e.g. tapped, hostile)
	else
		-- New target, focus or pet, or zoning: someone else, so kept aura icons go.
		StzxUI.Auras.UnitChanged(frame.auraContainer)
		ns.UpdateUnitFrame(frame)
	end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

-- Sizes: the full frames (player, target, focus) and a compact one
-- (target-of-target, pet).
ns.SIZES = {
	full = { width = Style.WIDTH, name = Style.NAME_HEIGHT, health = Style.HEALTH_HEIGHT, power = Style.POWER_HEIGHT,
		portrait = Style.PORTRAIT, healthFont = 14, nameFont = 12, powerFont = 9 },
	compact = { width = 130, name = 14, health = 18, power = 5, portrait = 30, healthFont = 11, nameFont = 10, powerFont = 8 },
}

-- These units have no events of their own for every change, so the frame
-- checks them a few times a second while shown.
local POLLED = { targettarget = true, focustarget = true }
local POLL_EVERY = 0.25

-- unit: "player", "target", "focus", "targettarget" or "pet".
-- side: "LEFT" puts the portrait on the left. size: ns.SIZES.full / compact.
function ns.CreateUnitFrame(unit, globalName, side, settings, size)
	-- Each frame has its own copy of the sizes (its width can be changed on its own).
	local dims = {}
	for k, v in pairs(size or ns.SIZES.full) do dims[k] = v end
	if settings.width then dims.width = settings.width end
	local height = dims.name + dims.health + Style.GAP + dims.power
	local frame = CreateFrame("Button", globalName, UIParent, "SecureUnitButtonTemplate")
	frame:SetSize(dims.width, height)
	frame:SetFrameStrata("LOW")
	frame.unit, frame.side, frame.settings, frame.dims = unit, side, settings, dims

	-- Clicks: left targets, right opens the unit's menu (works in combat).
	frame:SetAttribute("unit", unit)
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "togglemenu")
	frame:RegisterForClicks("AnyUp")
	frame:SetScript("OnEnter", function(self)
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
		GameTooltip:SetUnit(self.unit)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Bars sit below a row for the name.
	local body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", 0, -dims.name)
	body:SetPoint("BOTTOMRIGHT")
	Style.Panel(body)
	frame.body = body

	frame.health = Style.Bar(body, dims.health)
	frame.health:SetPoint("TOPLEFT")
	frame.health:SetPoint("TOPRIGHT")
	frame.power = Style.Bar(body, dims.power)
	frame.power:SetPoint("TOPLEFT", frame.health, "BOTTOMLEFT", 0, -Style.GAP)
	frame.power:SetPoint("TOPRIGHT", frame.health, "BOTTOMRIGHT", 0, -Style.GAP)

	frame.healthText = Style.Text(frame.health, dims.healthFont)
	frame.powerText = Style.Text(frame.power, dims.powerFont)
	frame.nameText = Style.Text(frame, dims.nameFont)
	frame.portrait = CreatePortrait(frame)
	ns.CreateAuraContainer(frame) -- buffs and debuffs (Auras.lua)

	-- Events for this unit only.
	for event in pairs(HEALTH_EVENTS) do frame:RegisterUnitEvent(event, unit) end
	for event in pairs(POWER_EVENTS) do frame:RegisterUnitEvent(event, unit) end
	for _, event in ipairs({ "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED",
		"UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_FACTION", "UNIT_FLAGS" }) do
		frame:RegisterUnitEvent(event, unit)
	end
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	if unit == "target" or unit == "targettarget" then
		frame:RegisterEvent("PLAYER_TARGET_CHANGED")
		frame:RegisterUnitEvent("UNIT_TARGET", "target")
	elseif unit == "focus" or unit == "focustarget" then
		frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
	elseif unit == "pet" then
		frame:RegisterUnitEvent("UNIT_PET", "player")
	end
	if unit ~= "player" then
		RegisterUnitWatch(frame) -- shows the frame only while the unit exists
	end
	frame:SetScript("OnEvent", OnEvent)
	frame:SetScript("OnShow", ns.UpdateUnitFrame)
	if POLLED[unit] then
		local wait = 0
		frame:SetScript("OnUpdate", function(self, elapsed)
			wait = wait - elapsed
			if wait <= 0 then
				wait = POLL_EVERY
				ns.UpdateUnitFrame(self)
			end
		end)
	end

	ns.UpdateUnitFrame(frame)
	return frame
end

-- StzxUI Nameplates: one plate
--
--           [debuffs you put on it]
--     15  Defias Pillager
--   X [=========== health ===========  76%]
--     [#][===== cast bar: Fireball =====]
--
-- The plate sits on Blizzard's nameplate frame (which still handles clicks
-- and targeting) and only shows values. In combat the game can make the
-- name, the cast, "is this my target" and threat secret: those go straight
-- into text, bars and *FromBoolean calls, never into comparisons.

local _, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local A = StzxUI.ACCENT

local TEXTURE = "Interface\\Buttons\\WHITE8x8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local COLOURS = {
	hostile = { r = 0.85, g = 0.26, b = 0.26 },
	neutral = { r = 0.92, g = 0.78, b = 0.30 },
	friendly = { r = 0.30, g = 0.76, b = 0.38 },
	tapped = { r = 0.55, g = 0.55, b = 0.55 },
	cast = { r = 0.95, g = 0.75, b = 0.20 },       -- can be interrupted
	locked = { r = 0.55, g = 0.55, b = 0.60 },     -- can't be interrupted
	channel = { r = 0.40, g = 0.75, b = 0.95 },
	interrupted = { r = 0.85, g = 0.20, b = 0.20 },
	aggro = { r = 0.95, g = 0.15, b = 0.15 },
}
ns.COLOURS = COLOURS

local function Colour(c, a) return CreateColor(c.r, c.g, c.b, a or 1) end

-- Is there a value? A secret one counts (it can't even be compared to nil).
local function Has(v)
	if issecretvalue and issecretvalue(v) then return true end
	return v ~= nil
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function Text(parent, size, justify)
	local t = parent:CreateFontString(nil, "OVERLAY")
	t:SetFont(FONT, size, "OUTLINE")
	t:SetJustifyH(justify or "CENTER")
	t:SetWordWrap(false)
	return t
end

local function Bar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(TEXTURE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	-- 1-pixel black edge and a dark background behind it.
	bar.edge = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
	bar.edge:SetPoint("TOPLEFT", -1, 1)
	bar.edge:SetPoint("BOTTOMRIGHT", 1, -1)
	bar.edge:SetColorTexture(0, 0, 0, 1)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0.08, 0.08, 0.10, 0.9)
	function bar:SetColor(c)
		self:SetStatusBarColor(c.r, c.g, c.b)
	end
	return bar
end

-- A coloured outline just outside a frame (2 pixels).
local function Outline(parent, anchor, c)
	local o = CreateFrame("Frame", nil, parent)
	o:SetPoint("TOPLEFT", anchor, "TOPLEFT", -3, 3)
	o:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 3, -3)
	for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
		local line = o:CreateTexture(nil, "OVERLAY")
		line:SetColorTexture(c.r, c.g, c.b, 1)
		line:SetPoint(edge[1])
		line:SetPoint(edge[2])
		if edge[3] then line:SetHeight(2) else line:SetWidth(2) end
	end
	o:Hide()
	return o
end

function ns.CreatePlate(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetFrameStrata("BACKGROUND")
	p:EnableMouse(false) -- clicks go through to Blizzard's nameplate

	p.health = Bar(p)
	p.health:SetPoint("CENTER", p, "CENTER")
	p.healthText = Text(p.health, 9, "RIGHT")
	p.healthText:SetPoint("RIGHT", p.health, "RIGHT", -3, 0)

	p.name = Text(p, 10, "CENTER")
	p.name:SetPoint("BOTTOM", p.health, "TOP", 0, 3)
	p.level = Text(p, 9, "LEFT")
	p.level:SetPoint("BOTTOMLEFT", p.health, "TOPLEFT", 0, 3)

	p.marker = p:CreateTexture(nil, "OVERLAY")
	p.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	p.marker:SetSize(16, 16)
	p.marker:SetPoint("RIGHT", p.health, "LEFT", -4, 0)
	p.marker:Hide()

	p.target = Outline(p, p.health, A)
	p.aggro = Outline(p, p.health, COLOURS.aggro)

	-- Cast bar under the health bar, with the spell's icon at its left.
	p.cast = Bar(p)
	p.cast:SetPoint("TOPRIGHT", p.health, "BOTTOMRIGHT", 0, -3)
	p.castIcon = p.cast:CreateTexture(nil, "OVERLAY")
	p.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	p.castIcon:SetPoint("RIGHT", p.cast, "LEFT", -2, 0)
	p.castText = Text(p.cast, 8, "LEFT")
	p.castText:SetPoint("LEFT", p.cast, "LEFT", 3, 0)
	p.castText:SetPoint("RIGHT", p.cast, "RIGHT", -3, 0)
	p.shield = p.cast:CreateTexture(nil, "OVERLAY")
	p.shield:SetTexture("Interface\\CastingBar\\UI-CastingBar-Small-Shield")
	p.shield:SetPoint("CENTER", p.castIcon, "CENTER", 0, -1)
	p.cast:Hide()
	p.cast:SetScript("OnUpdate", function(bar)
		if bar.casting then bar:SetValue(GetTime() * 1000) end
	end)

	p.debuffs = {}
	return p
end

-- Sizes and which parts show, from the settings.
function ns.LayoutPlate(p, db)
	p:SetSize(db.width, db.height)
	p.health:SetSize(db.width, db.height)
	p.healthText:SetFont(FONT, math.max(7, db.height - 1), "OUTLINE")
	local castHeight = db.castHeight
	p.cast:SetSize(db.width - castHeight - 2, castHeight)
	p.castIcon:SetSize(castHeight, castHeight)
	p.shield:SetSize(castHeight * 1.6, castHeight * 1.9)
	p.level:SetShown(db.showLevel)
	for i = #p.debuffs + 1, db.maxDebuffs do
		local icon = StzxUI.Auras.Create(p)
		icon:EnableMouse(false) -- never in the way of clicking the plate
		icon:Hide()
		p.debuffs[i] = icon
	end
	for _, icon in ipairs(p.debuffs) do StzxUI.Auras.Size(icon, db.debuffSize) end
end

---------------------------------------------------------------------------
-- Updating from a real unit
---------------------------------------------------------------------------

local function HealthPercent(unit)
	if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
		return UnitHealthPercent(unit, false, CurveConstants.ScaleTo100)
	end
	local cur, max = Plain(UnitHealth(unit)), Plain(UnitHealthMax(unit))
	if cur and max and max > 0 then return cur / max * 100 end
	return 0
end

function ns.UnitColour(unit, db)
	if db.classColours and Plain(UnitIsPlayer(unit)) then
		local _, class = UnitClass(unit)
		class = Plain(class)
		local c = class and C_ClassColor and C_ClassColor.GetClassColor(class)
		if c then return c end
	end
	if Plain(UnitIsTapDenied(unit)) then return COLOURS.tapped end
	local reaction = Plain(UnitReaction(unit, "player"))
	if reaction and reaction <= 3 then return COLOURS.hostile end
	if reaction == 4 then return COLOURS.neutral end
	if reaction then return COLOURS.friendly end
	return COLOURS.neutral
end

function ns.UpdateHealth(p)
	local unit, db = p.unit, ns.db()
	p.health:SetMinMaxValues(0, UnitHealthMax(unit))
	p.health:SetValue(UnitHealth(unit))
	p.health:SetColor(ns.UnitColour(unit, db))
	if db.healthText == "PERCENT" then
		p.healthText:SetFormattedText("%.0f%%", HealthPercent(unit))
	elseif db.healthText == "NUMBER" then
		p.healthText:SetText(AbbreviateLargeNumbers(UnitHealth(unit)))
	else
		p.healthText:SetText("")
	end
end

function ns.UpdateName(p)
	p.name:SetText(UnitName(p.unit))
	local level = Plain(UnitLevel(p.unit))
	local class = Plain(UnitClassification(p.unit))
	if not level then
		p.level:SetText("")
		return
	end
	local text = level < 0 and "??" or tostring(level)
	if class == "elite" or class == "rareelite" or class == "worldboss" then text = text .. "+" end
	p.level:SetText(text)
	local c = level > 0 and GetCreatureDifficultyColor and GetCreatureDifficultyColor(level)
	if c then p.level:SetTextColor(c.r, c.g, c.b) else p.level:SetTextColor(1, 0.2, 0.2) end
end

function ns.UpdateMarker(p)
	local index = Plain(GetRaidTargetIndex(p.unit))
	if index and SetRaidTargetIconTexture then
		SetRaidTargetIconTexture(p.marker, index)
		p.marker:Show()
	else
		p.marker:Hide()
	end
end

-- Target outline; other plates fade while you have a target.
function ns.UpdateTarget(p)
	local db = ns.db()
	if not Plain(UnitExists("target")) then
		p.target:Hide()
		p:SetAlpha(1)
		return
	end
	local isTarget = UnitIsUnit(p.unit, "target")
	local fade = db.fadeOthers / 100
	if issecretvalue and issecretvalue(isTarget) then
		p.target:SetShown(db.targetOutline)
		p.target:SetAlphaFromBoolean(isTarget, 1, 0)
		p:SetAlphaFromBoolean(isTarget, 1, fade)
	else
		p.target:SetAlpha(1)
		p.target:SetShown(db.targetOutline and isTarget and true or false)
		p:SetAlpha(isTarget and 1 or fade)
	end
end

-- Red edge when this mob is attacking you.
function ns.UpdateThreat(p)
	local db = ns.db()
	if not (db.aggro and Plain(UnitCanAttack("player", p.unit))) then
		p.aggro:Hide()
		return
	end
	local isTanking = UnitDetailedThreatSituation and UnitDetailedThreatSituation("player", p.unit)
	if issecretvalue and issecretvalue(isTanking) then
		p.aggro:Show()
		p.aggro:SetAlphaFromBoolean(isTanking, 1, 0)
	else
		p.aggro:SetAlpha(1)
		p.aggro:SetShown(isTanking and true or false)
	end
end

function ns.UpdateDebuffs(p)
	local db = ns.db()
	local shown = 0
	if db.debuffs then
		for _, aura in ipairs(StzxUI.Auras.Get(p.unit, "HARMFUL|PLAYER", db.maxDebuffs)) do
			if shown >= db.maxDebuffs then break end
			shown = shown + 1
			StzxUI.Auras.Set(p.debuffs[shown], p.unit, aura, true)
		end
	end
	ns.PlaceDebuffs(p, shown)
end

-- A centred row above the name.
function ns.PlaceDebuffs(p, shown)
	local size = ns.db().debuffSize
	local width = shown * (size + 1) - 1
	for i, icon in ipairs(p.debuffs) do
		if i <= shown then
			icon:ClearAllPoints()
			icon:SetPoint("BOTTOMLEFT", p.health, "TOP", -width / 2 + (i - 1) * (size + 1), 16)
			icon:Show()
		else
			icon:Hide()
		end
	end
end

---------------------------------------------------------------------------
-- Casts
---------------------------------------------------------------------------

-- Colour a cast bar: interruptible, or not (secret in combat: decided by
-- the game through SetVertexColorFromBoolean).
local function ColourCast(p, notInterruptible, channel)
	local texture = p.cast:GetStatusBarTexture()
	local open = channel and COLOURS.channel or COLOURS.cast
	if issecretvalue and issecretvalue(notInterruptible) then
		texture:SetVertexColorFromBoolean(notInterruptible, Colour(COLOURS.locked), Colour(open))
		p.shield:SetAlphaFromBoolean(notInterruptible, 1, 0)
	else
		local c = notInterruptible and COLOURS.locked or open
		texture:SetVertexColor(c.r, c.g, c.b)
		p.shield:SetAlpha(notInterruptible and 1 or 0)
	end
	p.cast:SetStatusBarColor(1, 1, 1)
end

function ns.UpdateCast(p)
	local db = ns.db()
	if not db.castBar then
		p.cast:Hide()
		return
	end
	local unit = p.unit
	local name, _, texture, startMS, endMS, _, _, notInterruptible = UnitCastingInfo(unit)
	local channel = false
	if not Has(name) then
		local cname, _, ctexture, cstart, cend, _, cnotInterruptible = UnitChannelInfo(unit)
		name, texture, startMS, endMS, notInterruptible = cname, ctexture, cstart, cend, cnotInterruptible
		channel = Has(name)
	end
	if not Has(name) then
		p.cast.casting = false
		p.cast:Hide()
		return
	end
	p.cast:SetMinMaxValues(startMS, endMS)
	p.cast:SetValue(GetTime() * 1000)
	p.cast.casting = true
	p.castText:SetText(name)
	p.castText:SetTextColor(1, 1, 1)
	p.castIcon:SetTexture(texture)
	ColourCast(p, notInterruptible, channel)
	p.cast:Show()
end

function ns.CastInterrupted(p)
	if not p.cast:IsShown() then return end
	p.cast.casting = false
	p.cast:SetMinMaxValues(0, 1)
	p.cast:SetValue(1)
	p.cast:GetStatusBarTexture():SetVertexColor(COLOURS.interrupted.r, COLOURS.interrupted.g, COLOURS.interrupted.b)
	p.castText:SetText("Interrupted")
	p.shield:SetAlpha(0)
	local unit = p.unit
	C_Timer.After(0.6, function()
		if p.unit == unit and not p.cast.casting then p.cast:Hide() end
	end)
end

function ns.UpdatePlate(p)
	ns.UpdateHealth(p)
	ns.UpdateName(p)
	ns.UpdateMarker(p)
	ns.UpdateTarget(p)
	ns.UpdateThreat(p)
	ns.UpdateDebuffs(p)
	ns.UpdateCast(p)
end

-- StzxUI Unit Frames: style
-- Sizes, colours and small drawing helpers shared by the frames and cast bars.
-- StzxUI's own look: flat bars on a dark panel, a round portrait with a ring
-- in the accent colour, clean shadowed text.

local _, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local Style = {}
ns.Style = Style

Style.BAR_TEXTURE = "Interface\\Buttons\\WHITE8x8"
Style.ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
Style.CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"

-- Frame layout (UI units, before the frame's own move-mode size)
Style.WIDTH = 230         -- bars
Style.HEALTH_HEIGHT = 26
Style.POWER_HEIGHT = 8
Style.GAP = 2             -- between health and power
Style.NAME_HEIGHT = 16    -- name tab above the bars
Style.PORTRAIT = 46       -- round portrait diameter
Style.CAST_WIDTH = 230
Style.CAST_HEIGHT = 18

Style.PANEL = { 0.06, 0.07, 0.09, 0.85 }

-- Colours for things that aren't players.
Style.REACTION = {
	hostile = { r = 0.85, g = 0.26, b = 0.26 },
	neutral = { r = 0.92, g = 0.78, b = 0.30 },
	friendly = { r = 0.30, g = 0.76, b = 0.38 },
	tapped = { r = 0.55, g = 0.55, b = 0.55 },
}
Style.GREEN = { r = 0.30, g = 0.76, b = 0.38 }
Style.DEAD = { r = 0.40, g = 0.40, b = 0.40 }

-- Power bar colours by power type token.
Style.POWER = {
	MANA = { r = 0.26, g = 0.52, b = 1.00 },
	RAGE = { r = 0.90, g = 0.26, b = 0.26 },
	ENERGY = { r = 1.00, g = 0.85, b = 0.28 },
	FOCUS = { r = 1.00, g = 0.56, b = 0.25 },
	HAPPINESS = { r = 0.30, g = 0.76, b = 0.60 },
}
Style.POWER_OTHER = { r = 0.55, g = 0.60, b = 0.75 }

Style.CAST = {
	normal = nil, -- the accent colour
	locked = { r = 0.55, g = 0.55, b = 0.60 },   -- can't be interrupted
	failed = { r = 0.85, g = 0.26, b = 0.26 },
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- A dark panel behind something, with a 1-unit black edge.
function Style.Panel(frame, inset)
	inset = inset or 1
	local edge = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	edge:SetPoint("TOPLEFT", -inset, inset)
	edge:SetPoint("BOTTOMRIGHT", inset, -inset)
	edge:SetColorTexture(0, 0, 0, 0.9)
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(Style.PANEL))
	return bg
end

-- A flat status bar with a darker copy of its colour behind it.
function Style.Bar(parent, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetHeight(height)
	bar:SetStatusBarTexture(Style.BAR_TEXTURE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetTexture(Style.BAR_TEXTURE)
	function bar:SetColor(colour)
		self:SetStatusBarColor(colour.r, colour.g, colour.b)
		self.bg:SetVertexColor(colour.r * 0.22, colour.g * 0.22, colour.b * 0.22, 0.9)
	end
	return bar
end

-- Text with a soft shadow, in the game's standard font.
function Style.Text(parent, size, layer)
	local text = parent:CreateFontString(nil, layer or "OVERLAY")
	text:SetFont(STANDARD_TEXT_FONT, size, "")
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 1)
	text:SetWordWrap(false)
	return text
end

-- Class colour for a player unit, reaction colour for everything else.
function Style.UnitColour(unit)
	if Plain(UnitIsPlayer(unit)) then
		local _, class = UnitClass(unit)
		class = Plain(class)
		local colour = class and C_ClassColor and C_ClassColor.GetClassColor(class)
		if colour then return colour end
	end
	if Plain(UnitIsTapDenied(unit)) then return Style.REACTION.tapped end
	local reaction = Plain(UnitReaction(unit, "player"))
	if reaction then
		if reaction <= 3 then return Style.REACTION.hostile end
		if reaction == 4 then return Style.REACTION.neutral end
		return Style.REACTION.friendly
	end
	return Style.REACTION.neutral
end

function Style.PowerColour(unit)
	local _, token = UnitPowerType(unit)
	token = Plain(token)
	return (token and Style.POWER[token]) or Style.POWER_OTHER
end

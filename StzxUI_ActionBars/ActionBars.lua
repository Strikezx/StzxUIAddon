-- StzxUI Action Bars: Blizzard's bars in StzxUI's look
--
-- Blizzard's own bars stay in charge of everything that matters in a fight:
-- paging, stances and forms, keybinds, cast-on-key-down, vehicles, and
-- Edit Mode placement (position, size, rows, padding, which bars show, and
-- the gryphon end caps). StzxUI only changes how each button looks:
--
--   * square icons, cropped, with a 1-pixel border (black, or StzxUI's
--     accent colour); empty slots get a dark
--     background instead of Blizzard's rounded frame art
--   * hover, pressed and "active" overlays in the StzxUI accent colour
--   * keybind, stack count, macro name and cooldown numbers resized to fit,
--     with keybinds shortened ("Mouse Button 4" -> M4, "SHIFT-1" -> S1)
--   * optional: icon tinted red when the target is out of range
--
-- How it stays safe: nothing secure is touched (no attributes, no anchors of
-- the buttons themselves). Blizzard redraws its art, hotkeys and colours from
-- time to time; StzxUI repaints right after each of those redraws.

local ADDON_NAME = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local A = StzxUI.ACCENT

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local BASE_SIZE = 45 -- a normal action button's width; small (pet, stance) ones scale from it
local RANGE_RED = { 0.90, 0.25, 0.25 }

-- Every bar whose buttons get restyled.
local BARS = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
	"MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar" }

local ActionBars = StzxUI:NewModule("ActionBars", ADDON_NAME, {
	showKeybinds = true,
	shortKeybinds = true,
	showMacroNames = true,
	rangeTint = true,      -- icon turns red when the target is out of range
	textSize = 11,         -- keybinds and macro names on a full-size button
	cooldownSize = 16,     -- cooldown numbers on a full-size button
	borderColour = "BLACK", -- the 1-pixel edge round each button: BLACK or ACCENT
}, {
	title = "Action Bars",
	description = "Restyles Blizzard's action bars: square icons, StzxUI colours, tidy text. Edit Mode still places them.",
})

local styled = {}   -- button -> true once restyled
local borders = {}  -- button -> its 1-pixel border texture
local outOfRange = setmetatable({}, { __mode = "k" }) -- button -> true

---------------------------------------------------------------------------
-- Keybind text
---------------------------------------------------------------------------

-- Longer names first, so "Mouse Wheel Up" isn't caught by "Mouse".
local SHORT = {
	{ "Middle Mouse", "M3" }, { "Mouse Button ", "M" }, { "Mouse Wheel Up", "WU" }, { "Mouse Wheel Down", "WD" },
	{ "Num Pad ", "N" }, { "Spacebar", "Spc" }, { "Backspace", "BS" }, { "Page Up", "PU" }, { "Page Down", "PD" },
	{ "Insert", "Ins" }, { "Delete", "Del" }, { "Home", "Hm" }, { "Capslock", "Cap" },
	{ "SHIFT%-", "S" }, { "CTRL%-", "C" }, { "ALT%-", "A" }, { "Shift%-", "S" }, { "Ctrl%-", "C" }, { "Alt%-", "A" },
}

function ActionBars.ShortKey(text)
	if type(text) ~= "string" or text == "" or text == RANGE_INDICATOR then return text end
	for _, pair in ipairs(SHORT) do
		text = text:gsub(pair[1], pair[2])
	end
	-- The game's own short modifiers ("s-", "c-", "a-") become capitals.
	text = text:gsub("%f[%w]([sca])%-", function(m) return m:upper() end)
	return text
end

---------------------------------------------------------------------------
-- One button
---------------------------------------------------------------------------

local function Scale(button)
	local width = button:GetWidth()
	if not width or width <= 0 then return 1 end
	return width / BASE_SIZE
end

local function FontSize(base, button)
	return math.max(7, math.floor(base * Scale(button) + 0.5))
end

-- Blizzard's art, hidden again after every redraw (it re-sets atlases).
local function HideArt(button)
	if button.NormalTexture then button.NormalTexture:SetAlpha(0) end
	if button.SlotArt then button.SlotArt:Hide() end
	if button.SlotBackground then button.SlotBackground:Hide() end
	local pushed = button.PushedTexture or (button.GetPushedTexture and button:GetPushedTexture())
	if pushed then
		pushed:SetColorTexture(A.r, A.g, A.b, 0.35)
		pushed:ClearAllPoints()
		pushed:SetPoint("TOPLEFT", 1, -1)
		pushed:SetPoint("BOTTOMRIGHT", -1, 1)
	end
end

local function StyleHotkey(button)
	local db, hotkey = ActionBars.db, button.HotKey
	if not hotkey then return end
	hotkey:SetFont(FONT, FontSize(db.textSize, button), "OUTLINE")
	hotkey:ClearAllPoints()
	hotkey:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -3)
	hotkey:SetWidth(math.max(10, button:GetWidth() - 4))
	hotkey:SetJustifyH("RIGHT")
	if db.shortKeybinds then
		local text = hotkey:GetText()
		local short = ActionBars.ShortKey(text)
		if short ~= text then hotkey:SetText(short) end
	end
	hotkey:SetAlpha(db.showKeybinds and 1 or 0)
end

-- The icon's colour: Blizzard's usable / out-of-mana / unusable colours,
-- with red on top when out of range (if that option is on).
local function ColourIcon(button)
	local icon = button.icon
	if not icon then return end
	if ActionBars.db.rangeTint and outOfRange[button] then
		icon:SetVertexColor(RANGE_RED[1], RANGE_RED[2], RANGE_RED[3])
	end
end

local function RestoreUsableColour(button)
	local icon = button.icon
	if not (icon and button.action and C_ActionBar and C_ActionBar.IsUsableAction) then return end
	local ok, usable, noMana = pcall(C_ActionBar.IsUsableAction, button.action)
	usable, noMana = ok and Plain(usable), ok and Plain(noMana)
	if usable then
		icon:SetVertexColor(1, 1, 1)
	elseif noMana then
		icon:SetVertexColor(0.5, 0.5, 1)
	else
		icon:SetVertexColor(0.4, 0.4, 0.4)
	end
end

local function StyleText(button)
	local db = ActionBars.db
	if button.Count then
		button.Count:SetFont(FONT, FontSize(db.textSize + 2, button), "OUTLINE")
		button.Count:ClearAllPoints()
		button.Count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 3)
	end
	if button.Name then
		button.Name:SetFont(FONT, FontSize(db.textSize - 1, button), "OUTLINE")
		button.Name:ClearAllPoints()
		button.Name:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 3)
		button.Name:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 3)
		button.Name:SetAlpha(db.showMacroNames and 1 or 0)
	end
	local cooldown = button.cooldown
	local countdown = cooldown and cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
	if countdown then
		countdown:SetFont(FONT, FontSize(db.cooldownSize, button), "OUTLINE")
	end
	StyleHotkey(button)
end

local function ColourBorder(button)
	local border = borders[button]
	if not border then return end
	if ActionBars.db.borderColour == "ACCENT" then
		border:SetColorTexture(A.r, A.g, A.b, 1)
	else
		border:SetColorTexture(0, 0, 0, 1)
	end
end

local function StyleButton(button)
	if styled[button] then return end
	styled[button] = true

	-- Square icon, cropped, inset by the border.
	local icon = button.icon
	if icon then
		if button.IconMask and icon.RemoveMaskTexture then icon:RemoveMaskTexture(button.IconMask) end
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", 1, -1)
		icon:SetPoint("BOTTOMRIGHT", -1, 1)
	end
	if button.cooldown then
		button.cooldown:ClearAllPoints()
		button.cooldown:SetPoint("TOPLEFT", 1, -1)
		button.cooldown:SetPoint("BOTTOMRIGHT", -1, 1)
		if button.cooldown.SetSwipeColor then button.cooldown:SetSwipeColor(0, 0, 0, 0.75) end
	end

	-- Our own background (seen in empty slots) and 1-pixel border.
	-- A colour underneath the whole button: the 1-pixel edge round the icon.
	local border = button:CreateTexture(nil, "BACKGROUND", nil, -8)
	border:SetAllPoints()
	borders[button] = border
	ColourBorder(button)
	-- A dark fill inside it, seen in empty slots. The icon covers it otherwise.
	local bg = button:CreateTexture(nil, "BACKGROUND", nil, -7)
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(0.08, 0.09, 0.11, 0.9)

	-- Hover and "active" (auto-attack, current spell) in StzxUI's colours.
	local highlight = button.HighlightTexture or (button.GetHighlightTexture and button:GetHighlightTexture())
	if highlight then
		highlight:SetColorTexture(1, 1, 1, 0.15)
		highlight:ClearAllPoints()
		highlight:SetPoint("TOPLEFT", 1, -1)
		highlight:SetPoint("BOTTOMRIGHT", -1, 1)
	end
	local checked = button.CheckedTexture or (button.GetCheckedTexture and button:GetCheckedTexture())
	if checked then
		checked:SetColorTexture(A.r, A.g, A.b, 0.3)
		checked:ClearAllPoints()
		checked:SetPoint("TOPLEFT", 1, -1)
		checked:SetPoint("BOTTOMRIGHT", -1, 1)
	end

	HideArt(button)
	StyleText(button)

	-- Repaint after Blizzard's own redraws.
	if button.UpdateButtonArt then hooksecurefunc(button, "UpdateButtonArt", HideArt) end
	if button.UpdateHotkeys then hooksecurefunc(button, "UpdateHotkeys", StyleHotkey) end
	if button.UpdateUsable then hooksecurefunc(button, "UpdateUsable", ColourIcon) end
end

---------------------------------------------------------------------------
-- All bars
---------------------------------------------------------------------------

function ActionBars.Buttons()
	local list = {}
	for _, name in ipairs(BARS) do
		local bar = _G[name]
		for _, button in ipairs(bar and bar.actionButtons or {}) do list[#list + 1] = button end
	end
	return list
end

function ActionBars:StyleAll()
	if InCombatLockdown() then
		self.pending = true
		return
	end
	for _, button in ipairs(ActionBars.Buttons()) do StyleButton(button) end
end

-- Settings changes: re-apply text and colours to every button.
function ActionBars:Refresh()
	for button in pairs(styled) do
		StyleText(button)
		ColourBorder(button)
		if not (self.db.rangeTint and outOfRange[button]) then RestoreUsableColour(button) end
		ColourIcon(button)
	end
end

---------------------------------------------------------------------------
-- Settings, start-up
---------------------------------------------------------------------------

function ActionBars:OnInitialize()
	local page = StzxUI:AddSettingsPage("Action Bars")
	local function Refresh() self:Refresh() end
	StzxUI:AddHeader(page, "Look",
		"Blizzard's bars restyled. Place them, size them and hide the gryphons in Blizzard's Edit Mode.")
	StzxUI:AddDropdown(page, self, "borderColour", "Button border",
		"The thin edge round each button. The accent colour follows StzxUI > General > Accent colour.",
		{ { "BLACK", "Black" }, { "ACCENT", "StzxUI accent colour" } }, Refresh)
	StzxUI:AddCheckbox(page, self, "showKeybinds", "Show keybinds", nil, Refresh)
	StzxUI:AddCheckbox(page, self, "shortKeybinds", "Short keybinds",
		"\"Mouse Button 4\" shows as M4, \"SHIFT-1\" as S1, \"Num Pad 5\" as N5.", function(on)
			self:Refresh()
			if not on then StzxUI:Say("full keybind names come back after a /reload.") end
		end)
	StzxUI:AddCheckbox(page, self, "showMacroNames", "Show macro names", nil, Refresh)
	StzxUI:AddCheckbox(page, self, "rangeTint", "Red icons when out of range",
		"Blizzard only turns the keybind red; this tints the whole icon.", Refresh)
	StzxUI:AddSlider(page, self, "textSize", "Text size",
		"Keybinds, stack counts and macro names, on a full-size button. Smaller buttons scale it down.",
		8, 16, 1, nil, Refresh)
	StzxUI:AddSlider(page, self, "cooldownSize", "Cooldown number size", nil, 10, 24, 1, nil, Refresh)
	StzxUI:AddButton(page, "Place and size the bars", "Edit Mode", function()
		StzxUI:Say("open Edit Mode from the game menu (Esc > Edit Mode). StzxUI move mode opens with it.")
	end, "Blizzard's Edit Mode places the bars. StzxUI only changes their look.")
end

function ActionBars:OnEnable()
	-- Range: Blizzard's range check, then our tint on top.
	if ActionButton_UpdateRangeIndicator then
		hooksecurefunc("ActionButton_UpdateRangeIndicator", function(button, checksRange, inRange)
			if not styled[button] then return end
			checksRange, inRange = Plain(checksRange), Plain(inRange)
			local far = (checksRange and inRange == false) and true or nil
			if far == outOfRange[button] then return end
			outOfRange[button] = far
			if far then ColourIcon(button) else RestoreUsableColour(button) end
		end)
	end
	-- Keybind changes need nothing extra: Blizzard redraws each hotkey, and
	-- the UpdateHotkeys hook shortens it again.
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function()
		if self.pending then
			self.pending = false
			self:StyleAll()
		end
	end)
	self:StyleAll()
end

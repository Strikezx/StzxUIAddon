-- StzxUI Welcome: the branded splash screen
--
-- The StzxUI welcome art (the hex lockup, the /stzx command cards) across the
-- screen: at login if you like, any time with /stzx splash. A click anywhere,
-- a right-click, or Esc closes it — it's only ever a greeting, never a wall.
--
-- The art itself lives in the core's Media folder (StzxUI/Media/) so other
-- parts of StzxUI can use the same files (the options window, a minimap
-- button). Sizes are powers of two, as the game likes.

local ADDON_NAME = ...
local StzxUI = _G.StzxUI

local Welcome = StzxUI:NewModule("Welcome", ADDON_NAME, {
	showOnLogin = true,
	size = 50,   -- % of the biggest 2:1 box the screen allows
	dim = 0.6,   -- how dark the screen behind it goes (0 = not at all)
}, {
	title = "Welcome",
	description = "The StzxUI splash screen at login, and /stzx splash any time.",
})

-- PNG files need their ".png" written out (the game finds .tga and .blp
-- without it, but not .png).
local ART = "Interface\\AddOns\\StzxUI\\Media\\welcome-2048.png"

local splash

-- The art is 2:1 (twice as wide as tall). Take the biggest 2:1 box the
-- screen allows, whichever way it's shaped, then the "Size" setting's share of it.
local function Layout()
	if not splash then return end
	local w = UIParent:GetWidth()
	local maxW = UIParent:GetHeight() * 2
	if w > maxW then w = maxW end
	w = w * (Welcome.db.size or 50) / 100
	splash.art:SetSize(w, w / 2)
	splash.dim:SetColorTexture(0, 0, 0, Welcome.db.dim or 0.6)
end

local function Build()
	local f = CreateFrame("Button", "StzxUIWelcome", UIParent)
	f:SetFrameStrata("HIGH")
	f:SetAllPoints()
	f:EnableMouse(true)
	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f:SetScript("OnClick", function() f:Hide() end)

	f.dim = f:CreateTexture(nil, "BACKGROUND")
	f.dim:SetAllPoints()

	f.art = f:CreateTexture(nil, "ARTWORK")
	f.art:SetTexture(ART)
	f.art:SetPoint("CENTER", f, "CENTER")

	f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.hint:SetPoint("TOP", f.art, "BOTTOM", 0, -10)
	f.hint:SetText("click anywhere, or press Esc, to close")

	f:SetScript("OnShow", Layout)
	f:Hide()

	-- Esc closes us, like a dialog. (The game looks the frame up by name.)
	table.insert(UISpecialFrames, "StzxUIWelcome")
	return f
end

local function Show()
	if not splash then splash = Build() end
	splash:Show()
end

function Welcome:OnInitialize()
	local page = StzxUI:AddSettingsPage("Welcome")
	StzxUI:AddHeader(page, "Welcome screen", "StzxUI's splash: the hex mark and the slash-command cards.")
	StzxUI:AddCheckbox(page, self, "showOnLogin", "Show when you log in",
		"It opens a beat after the loading screen; a click or Esc closes it.")
	StzxUI:AddSlider(page, self, "size", "Size",
		"How big the welcome art is, as a share of the most the screen can fit.", 25, 100, 5,
		function(value) return ("%d%%"):format(value) end, Layout)
	StzxUI:AddSlider(page, self, "dim", "Screen dimming",
		"How dark the screen behind the welcome art goes. 0% leaves it as it is.", 0, 0.9, 0.1,
		function(value) return ("%d%%"):format(value * 100 + 0.5) end, Layout)
	StzxUI:AddButton(page, "See it again", "Show splash", Show,
		"Opens the welcome screen right now. /stzx splash does the same.")
end

-- At login only, not after a /reload (StzxUI asks for reloads when you
-- switch accent, profile or sections, and the splash every time would wear thin).
function Welcome.OnEnteringWorld(isInitialLogin)
	if not (isInitialLogin and Welcome.db.showOnLogin) then return end
	-- Give the UI a moment to settle before covering it.
	C_Timer.After(1, Show)
end

function Welcome:OnEnable()
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", function(frame, _, isInitialLogin)
		frame:UnregisterEvent("PLAYER_ENTERING_WORLD") -- only the first one after loading counts
		Welcome.OnEnteringWorld(isInitialLogin)
	end)
end

---------------------------------------------------------------------------
-- /stzx splash
---------------------------------------------------------------------------

StzxUI.slashCommands.splash = {
	help = "show the StzxUI welcome screen",
	run = function()
		if not StzxUI:IsModuleOn("Welcome") then
			StzxUI:Say("the Welcome section is switched off (StzxUI > Look > Welcome).")
			return
		end
		Show()
	end,
}

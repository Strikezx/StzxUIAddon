-- StzxUI Skins: round two (other addons, and the quest tracker)
--
--   Questie   its settings window and "My Journey" window get StzxUI's
--             window look; its quest tracker's backdrop becomes flat with
--             a thin edge in the skin colour (Questie's own backdrop and
--             border switches still decide whether they show)
--   DBM       its options window gets StzxUI's window look; its timer bars
--             get a thin black edge and square-cropped icons (DBM's own bar
--             texture and colours stay; set those in DBM)
--   Tracker   Blizzard's quest tracker: its gold header art goes, headers
--             get a dark strip with an accent line, white and accent text
--
-- Only looks change. Other addons build their windows when they like (often
-- the first time you open them), so StzxUI looks for them every couple of
-- seconds, and skins each the moment it exists. Frame names were read from
-- the addons themselves (Questie, DBM); none of their code is used.

local StzxUI = _G.StzxUI
local Skin = StzxUI.Skin
local Skins = StzxUI:GetModule("Skins")

local FLAT = "Interface\\Buttons\\WHITE8x8"
local done = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- Questie
---------------------------------------------------------------------------

-- Its quest tracker: a flat backdrop with a 1-pixel edge. Questie sets the
-- colours itself (and fades them); StzxUI turns the edge to the skin colour,
-- keeping Questie's alpha (0 when its border is switched off).
local function SkinQuestieTracker(frame)
	if done[frame] or not frame.SetBackdrop then return end
	done[frame] = true
	local r, g, b, a = frame:GetBackdropColor()
	frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
	if r then frame:SetBackdropColor(r, g, b, a) end
	local painting = false
	hooksecurefunc(frame, "SetBackdropBorderColor", function(self, _, _, _, alpha)
		if painting then return end
		painting = true
		local er, eg, eb = Skin.EdgeColour()
		self:SetBackdropBorderColor(er, eg, eb, alpha or 1)
		painting = false
	end)
	frame:SetBackdropBorderColor(1, 1, 1, select(4, frame:GetBackdropBorderColor()) or 0)
end

local function QuestieWindows()
	if not Skins.db.questie then return end
	if _G.Questie_BaseFrame then SkinQuestieTracker(_G.Questie_BaseFrame) end
	if InCombatLockdown() then return end -- windows: out of combat, like Blizzard's
	local settings = _G.QuestieStandaloneSettings
	if settings and not Skin.IsSkinned(settings) then pcall(Skin.Window, settings, { controls = Skins.db.controls }) end
	local journey = _G.QuestieJourneyFrame -- an AceGUI widget: the real frame is .frame
	journey = type(journey) == "table" and (journey.frame or journey)
	if journey and journey.GetObjectType and not Skin.IsSkinned(journey) then
		pcall(Skin.Window, journey, { controls = Skins.db.controls })
	end
end

---------------------------------------------------------------------------
-- DBM
---------------------------------------------------------------------------

local nextBar = 1 -- DBM names its bars DBT_Bar_1, DBT_Bar_2... as it makes them

local function SkinDBMBar(frame)
	local name = frame:GetName()
	local bar = _G[name .. "Bar"]
	if not bar or done[frame] then return end
	done[frame] = true
	local edge = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
	edge:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(0, 0, 0, 1)
	for _, key in ipairs({ "BarIcon1", "BarIcon2" }) do
		local icon = _G[name .. key]
		if icon and icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	end
end

local function DBMWindows()
	if not Skins.db.dbm then return end
	local options = _G.DBM_GUI_OptionsFrame
	if options and not Skin.IsSkinned(options) and not InCombatLockdown() then pcall(Skin.Window, options, { controls = Skins.db.controls }) end
	while _G["DBT_Bar_" .. nextBar] do
		SkinDBMBar(_G["DBT_Bar_" .. nextBar])
		nextBar = nextBar + 1
	end
end

---------------------------------------------------------------------------
-- Blizzard's quest tracker
---------------------------------------------------------------------------

local function SkinHeader(header, main)
	if not header or done[header] then return end
	done[header] = true
	local strip = header:CreateTexture(nil, "BACKGROUND", nil, -7)
	strip:SetPoint("TOPLEFT", 0, -2)
	strip:SetPoint("BOTTOMRIGHT", 0, 2)
	strip:SetColorTexture(0, 0, 0, main and 0.75 or 0.55)
	local line = header:CreateTexture(nil, "BORDER")
	line:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT")
	line:SetHeight(1)
	local A = StzxUI.ACCENT
	line:SetColorTexture(A.r, A.g, A.b, main and 1 or 0.6)
end

local function PaintTracker()
	local tracker = _G.ObjectiveTrackerFrame
	if not (Skins.db.tracker and tracker) then return end
	local A = StzxUI.ACCENT
	local headers = { { tracker.Header, true } }
	for _, module in ipairs(tracker.modules or {}) do headers[#headers + 1] = { module.Header, false } end
	for _, entry in ipairs(headers) do
		local header, main = entry[1], entry[2]
		if header then
			SkinHeader(header, main)
			if header.Background then header.Background:SetAlpha(0) end
			if header.Text and header.Text.SetTextColor then
				if main then header.Text:SetTextColor(1, 1, 1) else header.Text:SetTextColor(A.r, A.g, A.b) end
			end
		end
	end
end

local trackerHooked = false
local function HookTracker()
	local tracker = _G.ObjectiveTrackerFrame
	if trackerHooked or not (Skins.db.tracker and tracker and tracker.Update) then return end
	trackerHooked = true
	hooksecurefunc(tracker, "Update", PaintTracker)
	PaintTracker()
end

---------------------------------------------------------------------------

local watching = false
function Skins.SkinOtherAddons()
	HookTracker()
	QuestieWindows()
	DBMWindows()
	if watching or not (Skins.db.questie or Skins.db.dbm) then return end
	watching = true
	-- Their windows appear when first opened: look every couple of seconds
	-- (a handful of name lookups: no cost worth noticing).
	C_Timer.NewTicker(2, function()
		QuestieWindows()
		DBMWindows()
	end)
end

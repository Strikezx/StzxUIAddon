-- StzxUI Quests
--   * Forever quest tint: quests that are new to WoW: Forever (not in original
--     Classic) get a coloured glow rising from the bottom of the parchment,
--     in the quest giver's window and on the quest log's detail page.
--   * Quest item sparkles: keeps the game's loot sparkle on quest items
--     switched on, even after a graphics preset turns it off.
--
-- Which quests are new? Every original Classic quest has an ID of 9665 or
-- lower. Forever's own quests use later IDs (its new Scholomance quests, for
-- example, are 27146 and up), so anything above 9665 counts as new. No quest
-- list is needed, so nothing is copied from other addons.

local ADDON_NAME, ns = ...
local StzxUI = _G.StzxUI

local LAST_CLASSIC_QUEST = 9665
local SPARKLE_CVAR = "outlineModeShowLootEffectWhenDisabled"

local Quests = StzxUI:NewModule("Quests", ADDON_NAME, {
	tint = true,
	tintColour = "TEAL",  -- see COLOURS
	tintStrength = 45,    -- % opacity at the bottom of the page
	tintHeight = 70,      -- % of the page the glow reaches up
	sparkles = true,
	partyStatus = true,   -- party panel beside the open quest
}, {
	title = "Quests",
	description = "Tints quests that are new to WoW: Forever; keeps quest items sparkling; shows who in your party is on a quest.",
})
ns.Quests = Quests

local COLOURS = {
	TEAL = { 0.25, 0.85, 0.80 },   -- the Forever logo's teal
	ACCENT = "accent",             -- StzxUI blue, or your class colour
	GOLD = { 1.00, 0.78, 0.25 },
	PURPLE = { 0.70, 0.45, 1.00 },
}

-- Is this quest new to Forever? nil when there's no quest.
function Quests.IsNewToForever(questID)
	questID = tonumber(questID)
	if not questID or questID <= 0 then return nil end
	return questID > LAST_CLASSIC_QUEST
end

---------------------------------------------------------------------------
-- The tint
---------------------------------------------------------------------------

local glows = {} -- every glow made, so settings changes can repaint them

local function Colour(db)
	local c = COLOURS[db.tintColour] or COLOURS.TEAL
	if c == "accent" then
		local A = StzxUI.ACCENT
		return A.r, A.g, A.b
	end
	return c[1], c[2], c[3]
end

-- A glow texture over a parchment background texture.
local function MakeGlow(parent, page)
	local glow = parent:CreateTexture(nil, "ARTWORK", nil, 7)
	glow:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT")
	glow:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT")
	glow:SetColorTexture(1, 1, 1, 1)
	glow.page = page
	glow:Hide()
	table.insert(glows, glow)
	return glow
end

local function Paint(glow, db)
	local r, g, b = Colour(db)
	local bottom = db.tintStrength / 100
	glow:SetGradient("VERTICAL", CreateColor(r, g, b, bottom), CreateColor(r, g, b, 0))
	local height = glow.page:GetHeight() or 0
	glow:SetHeight(math.max(1, height * db.tintHeight / 100))
end

local function ShowGlow(glow, questID)
	local db = Quests.db
	if glow and db.tint and Quests.IsNewToForever(questID) then
		Paint(glow, db)
		glow:Show()
	elseif glow then
		glow:Hide()
	end
end

-- The quest giver's window: detail, progress and reward pages.
local giverGlows = {}
local function UpdateGiver()
	local questID = GetQuestID and GetQuestID()
	for _, glow in ipairs(giverGlows) do ShowGlow(glow, questID) end
end

-- The quest log's detail page (beside the world map).
local logGlow
local function UpdateLog()
	local details = QuestMapFrame and QuestMapFrame.DetailsFrame
	ShowGlow(logGlow, details and details.questID)
end

local function SetUpTint()
	for _, name in ipairs({ "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel" }) do
		local panel = _G[name]
		if panel and panel.Bg then
			table.insert(giverGlows, MakeGlow(panel, panel.Bg))
			panel:HookScript("OnShow", UpdateGiver)
		end
	end
	local details = QuestMapFrame and QuestMapFrame.DetailsFrame
	if details and details.Bg then
		logGlow = MakeGlow(details, details.Bg)
	end
	if QuestMapFrame_ShowQuestDetails then hooksecurefunc("QuestMapFrame_ShowQuestDetails", UpdateLog) end
	if QuestMapFrame_CloseQuestDetails then hooksecurefunc("QuestMapFrame_CloseQuestDetails", UpdateLog) end
end

function Quests:Repaint()
	UpdateGiver()
	UpdateLog()
end

---------------------------------------------------------------------------
-- Quest item sparkles
---------------------------------------------------------------------------

local function KeepSparkles()
	if not Quests.db.sparkles then return end
	if C_CVar.GetCVar(SPARKLE_CVAR) ~= "1" then
		pcall(C_CVar.SetCVar, SPARKLE_CVAR, "1")
	end
end

local function SetSparkles(on)
	if on then
		KeepSparkles()
	else
		-- The game remembers this itself, so switch it back off; it takes
		-- effect after restarting the game.
		pcall(C_CVar.SetCVar, SPARKLE_CVAR, "0")
		StzxUI:ShowDialog({
			title = "Quest item sparkles",
			text = "The sparkle goes away after you restart the game (a /reload isn't enough).",
		})
	end
end

---------------------------------------------------------------------------
-- Settings, events, command
---------------------------------------------------------------------------

function Quests:OnInitialize()
	local page = StzxUI:AddSettingsPage("Quests")
	local function Repaint() self:Repaint() end
	StzxUI:AddHeader(page, "Forever quest tint",
		"Quests that weren't in original Classic get a coloured glow on the parchment.")
	StzxUI:AddCheckbox(page, self, "tint", "Tint quests new to Forever",
		"In the quest giver's window and on the quest log's detail page.", Repaint)
	StzxUI:AddDropdown(page, self, "tintColour", "Colour", nil, {
		{ "TEAL", "Forever teal" }, { "ACCENT", "StzxUI accent" }, { "GOLD", "Gold" }, { "PURPLE", "Purple" },
	}, Repaint)
	StzxUI:AddSlider(page, self, "tintStrength", "Strength", "How strong the glow is at the bottom of the page.",
		10, 90, 5, function(v) return v .. "%" end, Repaint)
	StzxUI:AddSlider(page, self, "tintHeight", "Height", "How far up the page the glow reaches.",
		20, 100, 5, function(v) return v .. "%" end, Repaint)
	StzxUI:AddHeader(page, "Party quest status")
	StzxUI:AddCheckbox(page, self, "partyStatus", "Show who in my party is on a quest",
		"A small panel beside the quest giver's window and the quest log's detail page, while you're in a party. "
		.. "The quest log one has Share and Share all buttons. /stzx shareall shares every quest you can.",
		function() if ns.PartyQuests then ns.PartyQuests.RefreshAll() end end)
	StzxUI:AddHeader(page, "Quest item sparkles")
	StzxUI:AddCheckbox(page, self, "sparkles", "Keep quest items sparkling",
		"Graphics presets switch the loot sparkle off; this keeps it on. Quest givers sparkle too: the game uses one setting for both.",
		SetSparkles)
end

function Quests:OnEnable()
	SetUpTint()
	ns.PartyQuests.SetUp()
	KeepSparkles()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "CVAR_UPDATE" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "CVAR_UPDATE" then KeepSparkles() else UpdateGiver() end
	end)
end

StzxUI.slashCommands.quest = {
	help = "say whether the open quest is new to Forever",
	run = function()
		local details = QuestMapFrame and QuestMapFrame.DetailsFrame
		local questID = (QuestFrame and QuestFrame:IsShown() and GetQuestID()) or (details and details.questID)
		local new = Quests.IsNewToForever(questID)
		if new == nil then
			StzxUI:Print("open a quest first (quest giver window or quest log).")
		else
			StzxUI:Print(("quest %d is %s."):format(questID, new and "new to Forever" or "from original Classic"))
		end
	end,
}

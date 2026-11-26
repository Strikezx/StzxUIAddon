-- StzxUI Skins: Blizzard's windows in StzxUI's look
--
-- Every Blizzard window on the list below gets StzxUI's look (see
-- StzxUI/Skin.lua): a dark fill, a thin edge in the skin colour, a title
-- strip with an accent line, flat tabs, buttons, close button and scrollbars.
--
-- Windows that Blizzard only loads when you first open them (talents,
-- professions, the auction house, the macro window...) are skinned the
-- moment they load. Skinning waits for combat to end.
--
-- Only looks change, so turning the section off (or a window you'd rather
-- keep Blizzard's) needs a reload to bring Blizzard's art back.

local ADDON_NAME = ...
local StzxUI = _G.StzxUI
local Skin = StzxUI.Skin

local Skins = StzxUI:NewModule("Skins", ADDON_NAME, {
	colour = "ACCENT",   -- edge colour: ACCENT (StzxUI's accent), CLASS (your class colour), BLACK
	opacity = 92,        -- window background, %
	controls = true,     -- also flatten the buttons and scrollbars inside windows
	level = "FULL",      -- FULL: everything inside windows too; FRAMES: frames, tabs, buttons only
	zygor = true,        -- Zygor Guides' window in StzxUI's colours
	auras = true,        -- Blizzard's buff bar and Cooldown Manager in StzxUI's look (AuraSkins.lua)
	questie = true,      -- Questie's windows and tracker (OtherSkins.lua)
	dbm = true,          -- DBM's options window and timer bars
	tracker = true,      -- Blizzard's quest tracker headers
	textColour = "WHITE", -- quest, gossip, book and letter text: WHITE, LIGHT (grey), ACCENT, BLIZZARD (its brown)
	textSize = 15,        -- that text's size (Blizzard's is about 13); titles 3 bigger
	skip = {},           -- window name -> true: keep Blizzard's look
}, {
	title = "Skins",
	description = "Blizzard's windows in StzxUI's look: dark, flat, with a thin accent edge.",
})

-- Blizzard's windows, by their global names. Not every one exists on
-- Forever; the ones that don't are simply passed over.
Skins.WINDOWS = {
	-- Character and spells
	"CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "ProfessionsBookFrame", "InspectFrame",
	"DressUpFrame", "TabardFrame",
	-- Social
	"FriendsFrame", "SocialUIFrame", "CommunitiesFrame", "RaidInfoFrame", "GuildRegistrarFrame", "PetitionFrame",
	-- Questing and NPCs
	"QuestFrame", "GossipFrame", "QuestLogPopupDetailFrame", "MerchantFrame", "ClassTrainerFrame",
	"TaxiFrame", "StableFrame", "ItemTextFrame", "BarberShopFrame",
	-- Items and money
	"MailFrame", "OpenMailFrame", "CooldownViewerSettings", "BankFrame", "GuildBankFrame", "TradeFrame", "LootFrame",
	"AuctionHouseFrame", "ProfessionsFrame", "ItemSocketingFrame", "ItemUpgradeFrame",
	"ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2", "ContainerFrame3", "ContainerFrame4",
	"ContainerFrame5", "ContainerFrame6",
	-- Groups and PvP
	"LFGParentFrame", "PVEFrame", "PVPUIFrame", "PVPFrame", "HonorFrame",
	-- Collections, journals, calendar
	"CollectionsJournal", "EncounterJournal", "AchievementFrame", "CalendarFrame", "TimeManagerFrame",
	-- System
	"GameMenuFrame", "AddonList", "MacroFrame", "ClickBindingFrame", "HelpFrame", "ChatConfigFrame",
	"ColorPickerFrame", "LegacySystemFrame", "SettingsPanel", "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
}

-- Windows that need something kept (see Skin.Window): the flight map is
-- painted onto TaxiFrame's background, and its routes are drawn on TaxiRouteMap.
Skins.WINDOW_OPTIONS = {
	TaxiFrame = { keep = { "InsetBg" }, leave = { "TaxiRouteMap" } },
}

local pending = false -- something to skin once combat ends

-- Skin every listed window that exists now and isn't done yet.
function Skins:SkinAll()
	if InCombatLockdown() then
		pending = true
		return 0
	end
	pending = false
	local count = 0
	for _, name in ipairs(Skins.WINDOWS) do
		local frame = _G[name]
		if frame and type(frame) == "table" and frame.GetObjectType and not self.db.skip[name]
			and not (frame.IsForbidden and frame:IsForbidden()) and not Skin.IsSkinned(frame) then
			local extra = Skins.WINDOW_OPTIONS[name] or {}
			local opts = { controls = self.db.controls, keep = extra.keep, leave = extra.leave }
			local ok = pcall(Skin.Window, frame, opts)
			if ok then count = count + 1 end
		end
	end
	return count
end

---------------------------------------------------------------------------
-- Other addons: Zygor Guides
---------------------------------------------------------------------------
-- Zygor draws its window with its own skin (Skins\Default\Skin.lua:
-- ZGV.Frame:ApplySkin() sets ZGV.Frame.Border's backdrop from its style).
-- Its "Stealth" style is already flat and dark with a 1-pixel edge, so
-- StzxUI only re-colours it right after each ApplySkin: the edge in the
-- skin colour, the background in StzxUI's dark fill. Zygor's own opacity
-- setting (the colours' alpha) is kept. Zygor builds its window late, so
-- StzxUI checks for it every second for a while.
local ZYGOR_FILL = { 0.06, 0.065, 0.075 }

local function ZygorFrame()
	local zgv = _G.ZygorGuidesViewer or _G.ZGV
	return type(zgv) == "table" and zgv.Frame or nil
end

function Skins.ColourZygor()
	if not Skins.db.zygor then return end
	local frame = ZygorFrame()
	local border = frame and frame.Border
	if not (border and border.SetBackdropBorderColor and border.GetBackdropBorderColor) then return end
	local r, g, b = Skin.EdgeColour()
	local _, _, _, edgeAlpha = border:GetBackdropBorderColor()
	border:SetBackdropBorderColor(r, g, b, edgeAlpha or 1)
	local _, _, _, fillAlpha = border:GetBackdropColor()
	border:SetBackdropColor(ZYGOR_FILL[1], ZYGOR_FILL[2], ZYGOR_FILL[3], fillAlpha or 1)
end

local zygorHooked = false
local function WatchZygor()
	if zygorHooked or not Skins.db.zygor then return end
	local tries = 0
	local ticker
	ticker = C_Timer.NewTicker(1, function()
		tries = tries + 1
		local frame = ZygorFrame()
		if frame and frame.ApplySkin then
			zygorHooked = true
			hooksecurefunc(frame, "ApplySkin", Skins.ColourZygor)
			Skins.ColourZygor()
			ticker:Cancel()
		elseif tries >= 180 then -- no Zygor (or a very different one): stop looking
			ticker:Cancel()
		end
	end)
end

local function ApplyLook()
	Skin.SetLevel(Skins.db.level)
	Skin.SetColourMode(Skins.db.colour)
	Skin.SetOpacity(Skins.db.opacity / 100)
	Skins.ColourZygor()
end

function Skins:OnInitialize()
	local page = StzxUI:AddSettingsPage("Skins")
	StzxUI:AddHeader(page, "Blizzard's windows",
		"Character, spells, social, quests, merchants, mail, bank, auction house, professions, the game menu and more.")
	StzxUI:AddDropdown(page, self, "level", "How much to restyle",
		"Full: panels, bars, checkboxes and list rows inside windows too. Frames only: the window, its tabs and "
		.. "buttons. Items, spells and talents are never touched. Changes apply after a reload.",
		{ { "FULL", "Full" }, { "FRAMES", "Frames only" } },
		function() StzxUI:AskReload("The new restyle level applies after a reload.") end)
	StzxUI:AddDropdown(page, self, "colour", "Edge colour",
		"The thin edge and accent lines round skinned windows (and the tooltip).",
		{ { "ACCENT", "StzxUI accent colour" }, { "CLASS", "My class colour" }, { "BLACK", "Black" } }, ApplyLook)
	StzxUI:AddSlider(page, self, "opacity", "Window background", "How solid the dark background is.",
		60, 100, 2, function(value) return ("%d%%"):format(value) end, ApplyLook)
	StzxUI:AddCheckbox(page, self, "controls", "Flatten buttons and scrollbars inside windows",
		"Changes apply after a reload.", function() StzxUI:AskReload("Buttons and scrollbars change after a reload.") end)
	StzxUI:AddCheckbox(page, self, "auras", "Blizzard's buffs and Cooldown Manager in StzxUI's look",
		"Your buffs and debuffs by the minimap and the Cooldown Manager's icons and bars: square icons with a thin "
		.. "edge, flat bars. These are Blizzard's own, so they keep working in fights (the game refuses addons "
		.. "auras then). Turning it off needs a reload.",
		function(value)
			if value then Skins.SkinBlizzardAuras() else StzxUI:AskReload("Blizzard's buff look comes back after a reload.") end
		end)
	StzxUI:AddDropdown(page, self, "textColour", "Dialogue text colour",
		"Quest, gossip, book and letter text. Blizzard's own is dark brown, made for its parchment: hard to read on black. "
		.. "Going back to Blizzard's needs a reload.",
		{ { "WHITE", "White" }, { "LIGHT", "Light grey" }, { "ACCENT", "StzxUI blue (accent colour)" },
			{ "BLIZZARD", "Blizzard's own" } },
		function(value)
			if value == "BLIZZARD" then
				StzxUI:AskReload("Blizzard's dialogue colours come back after a reload.")
			else
				Skins.LightText()
			end
		end)
	StzxUI:AddSlider(page, self, "textSize", "Dialogue text size",
		"Quest, gossip, book and letter text (Blizzard's is about 13). Titles are 3 bigger.",
		11, 22, 1, nil, function() Skins.LightText() end)
	StzxUI:AddHeader(page, "Other addons")
	StzxUI:AddCheckbox(page, self, "zygor", "Zygor Guides in StzxUI's colours",
		"Zygor's window edge and background in StzxUI's colours. Looks best with Zygor's \"Stealth\" style. Off needs a reload.",
		function(on)
			if on then WatchZygor() else StzxUI:AskReload("Zygor's own colours come back after a reload.") end
		end)
	local function Other(on)
		if on then Skins.SkinOtherAddons() else StzxUI:AskReload("Their own look comes back after a reload.") end
	end
	StzxUI:AddCheckbox(page, self, "questie", "Questie in StzxUI's look",
		"Questie's settings and My Journey windows like Blizzard's skinned windows; its quest tracker's backdrop flat "
		.. "with a thin edge (Questie's own backdrop and border options still decide whether they show). Off needs a reload.",
		Other)
	StzxUI:AddCheckbox(page, self, "dbm", "DBM in StzxUI's look",
		"DBM's options window like Blizzard's skinned windows; its timer bars get a thin black edge and square icons "
		.. "(pick the bar texture and colours in DBM). Off needs a reload.", Other)
	StzxUI:AddHeader(page, "Quest tracker")
	StzxUI:AddCheckbox(page, self, "tracker", "Blizzard's quest tracker in StzxUI's look",
		"Its gold header art goes; headers get a dark strip with an accent line. Off needs a reload.", Other)
end

-- Light text: Blizzard's dark "parchment" fonts made light, and quest text
-- brightened again right after Blizzard's quest code colours it.
local TEXT_COLOURS = { WHITE = { 1, 1, 1 }, LIGHT = { 0.85, 0.85, 0.87 } }

function Skins.ApplyTextColour()
	local choice = Skins.db.textColour
	if choice == "BLIZZARD" then return end
	local c = TEXT_COLOURS[choice]
	if choice == "ACCENT" then
		local A = StzxUI.ACCENT
		c = { A.r, A.g, A.b }
	end
	c = c or TEXT_COLOURS.WHITE
	Skin.SetTextColour(c[1], c[2], c[3])
end

-- The hooks that keep quest text in the chosen colour (installed once, the
-- first time a colour other than Blizzard's is in use).
local textHooked = false
local function HookQuestText()
	if textHooked then return end
	textHooked = true
	if QuestFrame_SetTextColor then hooksecurefunc("QuestFrame_SetTextColor", Skin.Brighten) end
	if QuestFrame_SetTitleTextColor then
		hooksecurefunc("QuestFrame_SetTitleTextColor", function(fontString) fontString:SetTextColor(1, 0.82, 0.25) end)
	end
	if QuestInfo_Display then
		hooksecurefunc("QuestInfo_Display", function() Skin.BrightenText(_G.QuestInfoFrame) end)
	end
	-- The gossip window (the first window at a trainer or quest giver) colours
	-- its own text through Blizzard's "quest text contrast" setting, and does
	-- it again whenever its list is rebuilt: follow it each time.
	local gossip = _G.GossipFrame
	if gossip then
		local function GossipText(frame)
			for fontString in pairs(frame.fontStrings or {}) do Skin.ForceBright(fontString) end
		end
		if gossip.RegisterFontString then
			hooksecurefunc(gossip, "RegisterFontString", function(_, fontString) Skin.ForceBright(fontString) end)
		end
		if gossip.UpdateFontStrings then hooksecurefunc(gossip, "UpdateFontStrings", GossipText) end
		if gossip.Update then hooksecurefunc(gossip, "Update", GossipText) end
	end
	-- Some quest givers open a quest list instead: its quest names are
	-- written in black inside the text itself.
	local greeting = _G.QuestFrameGreetingPanel
	if greeting and greeting.HookScript then
		greeting:HookScript("OnShow", function(panel)
			if not (panel.titleButtonPool and panel.titleButtonPool.EnumerateActive) then return end
			for button in panel.titleButtonPool:EnumerateActive() do
				Skin.ForceBright(button.GetFontString and button:GetFontString())
			end
		end)
	end
end

local function LightText()
	if Skins.db.textColour == "BLIZZARD" then return end
	HookQuestText()
	Skin.SetTextSize(Skins.db.textSize)
	Skins.ApplyTextColour()
end
Skins.LightText = LightText

function Skins:OnEnable()
	ApplyLook()
	LightText()
	local events = CreateFrame("Frame")
	-- Windows Blizzard loads later (when first opened) arrive with their addon.
	events:RegisterEvent("ADDON_LOADED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function(_, event, name)
		if event == "ADDON_LOADED" and not (name and name:find("^Blizzard_")) then return end
		if event == "PLAYER_REGEN_ENABLED" and not pending then return end
		Skins:SkinAll()
		Skins.SkinBlizzardAuras()
	end)
	self:SkinAll()
	Skins.SkinBlizzardAuras()
	WatchZygor()
	Skins.SkinOtherAddons()
end

StzxUI.slashCommands.skins = {
	help = "skin any Blizzard windows not skinned yet (they're normally done as they load)",
	run = function()
		local count = Skins:SkinAll()
		StzxUI:Say(InCombatLockdown() and "after combat." or (("%d more windows skinned."):format(count)))
	end,
}

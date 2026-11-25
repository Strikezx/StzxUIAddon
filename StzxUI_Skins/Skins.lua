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
	zygor = true,        -- Zygor Guides' window in StzxUI's colours
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
	"MailFrame", "OpenMailFrame", "BankFrame", "GuildBankFrame", "TradeFrame", "LootFrame",
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

local pending = false -- something to skin once combat ends

-- Skin every listed window that exists now and isn't done yet.
function Skins:SkinAll()
	if InCombatLockdown() then
		pending = true
		return 0
	end
	pending = false
	local count = 0
	local opts = { controls = self.db.controls }
	for _, name in ipairs(Skins.WINDOWS) do
		local frame = _G[name]
		if frame and type(frame) == "table" and frame.GetObjectType and not self.db.skip[name]
			and not (frame.IsForbidden and frame:IsForbidden()) and not Skin.IsSkinned(frame) then
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
	Skin.SetColourMode(Skins.db.colour)
	Skin.SetOpacity(Skins.db.opacity / 100)
	Skins.ColourZygor()
end

function Skins:OnInitialize()
	local page = StzxUI:AddSettingsPage("Skins")
	StzxUI:AddHeader(page, "Blizzard's windows",
		"Character, spells, social, quests, merchants, mail, bank, auction house, professions, the game menu and more.")
	StzxUI:AddDropdown(page, self, "colour", "Edge colour",
		"The thin edge and accent lines round skinned windows (and the tooltip).",
		{ { "ACCENT", "StzxUI accent colour" }, { "CLASS", "My class colour" }, { "BLACK", "Black" } }, ApplyLook)
	StzxUI:AddSlider(page, self, "opacity", "Window background", "How solid the dark background is.",
		60, 100, 2, function(value) return ("%d%%"):format(value) end, ApplyLook)
	StzxUI:AddCheckbox(page, self, "controls", "Flatten buttons and scrollbars inside windows",
		"Changes apply after a reload.", function() StzxUI:AskReload("Buttons and scrollbars change after a reload.") end)
	StzxUI:AddHeader(page, "Other addons")
	StzxUI:AddCheckbox(page, self, "zygor", "Zygor Guides in StzxUI's colours",
		"Zygor's window edge and background in StzxUI's colours. Looks best with Zygor's \"Stealth\" style. Off needs a reload.",
		function(on)
			if on then WatchZygor() else StzxUI:AskReload("Zygor's own colours come back after a reload.") end
		end)
end

function Skins:OnEnable()
	ApplyLook()
	local events = CreateFrame("Frame")
	-- Windows Blizzard loads later (when first opened) arrive with their addon.
	events:RegisterEvent("ADDON_LOADED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function(_, event, name)
		if event == "ADDON_LOADED" and not (name and name:find("^Blizzard_")) then return end
		if event == "PLAYER_REGEN_ENABLED" and not pending then return end
		Skins:SkinAll()
	end)
	self:SkinAll()
	WatchZygor()
end

StzxUI.slashCommands.skins = {
	help = "skin any Blizzard windows not skinned yet (they're normally done as they load)",
	run = function()
		local count = Skins:SkinAll()
		StzxUI:Say(InCombatLockdown() and "after combat." or (("%d more windows skinned."):format(count)))
	end,
}

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
	"FriendsFrame", "CommunitiesFrame", "RaidInfoFrame", "GuildRegistrarFrame", "PetitionFrame",
	-- Questing and NPCs
	"QuestFrame", "GossipFrame", "QuestLogPopupDetailFrame", "MerchantFrame", "ClassTrainerFrame",
	"TaxiFrame", "StableFrame", "ItemTextFrame", "BarberShopFrame",
	-- Items and money
	"MailFrame", "OpenMailFrame", "BankFrame", "GuildBankFrame", "TradeFrame", "LootFrame",
	"AuctionHouseFrame", "ProfessionsFrame", "ItemSocketingFrame", "ItemUpgradeFrame",
	"ContainerFrameCombinedBags",
	-- Groups and PvP
	"LFGParentFrame", "PVEFrame", "PVPUIFrame", "PVPFrame", "HonorFrame",
	-- Collections, journals, calendar
	"CollectionsJournal", "EncounterJournal", "AchievementFrame", "CalendarFrame", "TimeManagerFrame",
	-- System
	"GameMenuFrame", "AddonList", "MacroFrame", "ClickBindingFrame", "HelpFrame", "ChatConfigFrame",
	"ColorPickerFrame",
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

local function ApplyLook()
	Skin.SetColourMode(Skins.db.colour)
	Skin.SetOpacity(Skins.db.opacity / 100)
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
end

StzxUI.slashCommands.skins = {
	help = "skin any Blizzard windows not skinned yet (they're normally done as they load)",
	run = function()
		local count = Skins:SkinAll()
		StzxUI:Say(InCombatLockdown() and "after combat." or (("%d more windows skinned."):format(count)))
	end,
}

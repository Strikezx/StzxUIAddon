-- StzxUI Blizzard Frames: move the Blizzard frames Edit Mode can't
--
-- Edit Mode already places most of Blizzard's HUD (bars, minimap, chat,
-- buffs, tooltip, loot window, durability, breath timer, raid warnings, ...).
-- This adds the rest to StzxUI move mode, in a "Blizzard" group:
--
--   Alerts          achievement and loot toasts (they stack up from here)
--   Error messages  the red "Not enough mana" text
--   Zone text       the big zone name (and the sub-zone under it)
--   Top widgets     capture bars and battleground scores at the top
--   Boss banner     the boss-kill loot banner
--   Toasts          level-up and "new spell" messages
--
-- Each box starts exactly where Blizzard puts the frame, so nothing moves
-- until you drag it. Mouse wheel resizes, as with StzxUI's own frames.
--
-- Left alone on purpose: the loot roll frames and the widgets under the
-- minimap. Blizzard's own layout keeps moving those, and fighting it can
-- cause "action blocked" errors.

local ADDON_NAME = ...
local StzxUI = _G.StzxUI

-- key, setting, label, Blizzard frame, which point is kept, Blizzard's spot, box size
local FRAMES = {
	{ key = "BlizzAlerts", option = "alerts", label = "Alerts", frame = "AlertFrame", anchor = "BOTTOM",
		default = { "BOTTOM", "BOTTOM", 0, 128 }, width = 300, height = 60 },
	{ key = "BlizzErrors", option = "errors", label = "Error messages", frame = "UIErrorsFrame", anchor = "TOP",
		default = { "TOP", "TOP", 0, -122 }, width = 512, height = 60 },
	{ key = "BlizzZoneText", option = "zoneText", label = "Zone text", frame = "ZoneTextFrame", anchor = "TOP",
		default = { "TOP", "TOP", 0, -128 }, width = 420, height = 70 },
	{ key = "BlizzTopWidgets", option = "topWidgets", label = "Capture bars and scores", frame = "UIWidgetTopCenterContainerFrame",
		anchor = "TOP", default = { "TOP", "TOP", 0, -15 }, width = 260, height = 50 },
	{ key = "BlizzBossBanner", option = "bossBanner", label = "Boss banner", frame = "BossBanner", anchor = "TOP",
		default = { "TOP", "TOP", 0, -120 }, width = 420, height = 140 },
	{ key = "BlizzToasts", option = "toasts", label = "Level-up toasts", frame = "EventToastManagerFrame", anchor = "TOP",
		default = { "TOP", "TOP", 0, -190 }, width = 420, height = 80 },
}

local defaults = {}
for _, spec in ipairs(FRAMES) do defaults[spec.option] = true end

local BlizzardFrames = StzxUI:NewModule("BlizzardFrames", ADDON_NAME, defaults, {
	title = "Blizzard Frames",
	description = "Move and resize the Blizzard frames Edit Mode can't: alerts, error messages, zone text, capture bars, boss banner, level-up toasts.",
})
BlizzardFrames.FRAMES = FRAMES

function BlizzardFrames:OnInitialize()
	local page = StzxUI:AddSettingsPage("Blizzard Frames")
	StzxUI:AddHeader(page, "Movable in StzxUI move mode",
		"These Blizzard frames get a box in move mode (the Blizzard group). Everything else Blizzard "
		.. "places is in Edit Mode, which opens StzxUI move mode with it. Switching one off puts it back after a reload.")
	for _, spec in ipairs(FRAMES) do
		StzxUI:AddCheckbox(page, self, spec.option, spec.label, nil, function()
			StzxUI:AskReload(("%s goes back to Blizzard's spot (or becomes movable) after a reload."):format(spec.label))
		end)
	end
	StzxUI:AddButton(page, "Place them", "Move mode", function() StzxUI:EnterMoveMode() end,
		"Drag the boxes in the Blizzard group. Mouse wheel resizes; right-click puts one back.")
end

function BlizzardFrames:OnEnable()
	for _, spec in ipairs(FRAMES) do
		local frame = _G[spec.frame]
		if self.db[spec.option] and frame then
			StzxUI:RegisterMover(spec.key, frame, {
				label = spec.label,
				category = "Blizzard",
				default = spec.default,
				width = spec.width,
				height = spec.height,
				anchor = spec.anchor,
			})
		end
	end
end

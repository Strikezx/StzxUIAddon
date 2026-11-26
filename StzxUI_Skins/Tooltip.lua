-- StzxUI Tooltip: the game's tooltips in StzxUI's look, plus a few extras
--
-- Look: StzxUI's dark background and thin edge (the Skins edge colour). The
-- edge takes the item's quality colour for items and the class colour for
-- players. A slim flat health bar under unit tooltips. One text size for all
-- tooltips.
--
-- Extras (each can be switched off):
--   * Target: who the unit is targeting (out of combat: names are hidden
--     from addons in a fight)
--   * Item level on gear
--   * Item and spell IDs (handy for setting things up; off by default)
--   * Gathering: the skill a herb, ore vein or skinnable corpse needs (Gathering.lua)
--   * Tooltip at the mouse instead of the corner (off by default)
--
-- Safe: Blizzard's tooltip art is only made invisible (it shows and hides
-- it, but never changes its alpha), StzxUI's backdrop goes underneath, and
-- extra lines are added after Blizzard fills the tooltip.

local ADDON_NAME = ...
local StzxUI = _G.StzxUI
local Skin = StzxUI.Skin
local Plain = StzxUI.Plain

local Tooltip = StzxUI:NewModule("Tooltip", ADDON_NAME, {
	style = true,         -- StzxUI look
	qualityEdge = true,   -- edge in the item's quality / player's class colour
	textSize = 13,        -- normal tooltip text (title +2, small text -2); Blizzard's is 12
	showTarget = true,
	showItemLevel = false,
	showIDs = false,
	gathering = true,     -- skill needed for herbs, ore and skinning (Gathering.lua)
	atCursor = false,
}, {
	title = "Tooltip",
	description = "The game's tooltips in StzxUI's look, bigger text, and a few optional extras.",
})

local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
	"ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }
local FONTS = { { "GameTooltipHeaderText", 2 }, { "GameTooltipText", 0 }, { "GameTooltipTextSmall", -2 } }

local backdrops = setmetatable({}, { __mode = "k" }) -- tooltip -> its StzxUI backdrop

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------

local function StyleTooltip(tooltip)
	if not tooltip or backdrops[tooltip] then return end
	if tooltip.NineSlice then tooltip.NineSlice:SetAlpha(0) end
	backdrops[tooltip] = Skin.Backdrop(tooltip)
end

local function StyleHealthBar()
	local bar = _G.GameTooltipStatusBar
	if not bar or Skin.IsSkinned(bar) then return end
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	bar:SetHeight(5)
	Skin.Backdrop(bar, { edge = "soft", fill = { 0, 0, 0 }, alpha = 0.7 })
end

local function ApplyFonts()
	for _, entry in ipairs(FONTS) do
		local font = _G[entry[1]]
		if font and font.GetFont then
			local file, _, flags = font:GetFont()
			font:SetFont(file or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", Tooltip.db.textSize + entry[2], flags or "")
		end
	end
end

local function EdgeTo(tooltip, r, g, b)
	local backdrop = backdrops[tooltip]
	if backdrop and Tooltip.db.qualityEdge then Skin.SetEdgeColour(backdrop, r, g, b) end
end

---------------------------------------------------------------------------
-- Items, units, spells
---------------------------------------------------------------------------

local function OnItem(tooltip, data)
	local db = Tooltip.db
	local id = data and Plain(data.id)
	if not id then return end
	if db.style then
		local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
		if quality and quality >= 2 and C_Item.GetItemQualityColor then -- uncommon and up; grey/white keep the skin edge
			local r, g, b = C_Item.GetItemQualityColor(quality)
			if r then EdgeTo(tooltip, r, g, b) end
		end
	end
	if db.showItemLevel and C_Item.GetDetailedItemLevelInfo then
		local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
		if classID == 2 or classID == 4 then -- weapons and armour
			local link
			if tooltip.GetItem then link = select(2, tooltip:GetItem()) end
			local level = C_Item.GetDetailedItemLevelInfo(link or id)
			if level and level > 1 then tooltip:AddLine(("Item level %d"):format(level), 1, 0.82, 0) end
		end
	end
	if db.showIDs then tooltip:AddDoubleLine("Item ID", tostring(id), 0.6, 0.6, 0.6, 1, 1, 1) end
end

local function ClassColour(unit)
	local _, class = UnitClass(unit)
	class = Plain(class)
	return class and C_ClassColor and C_ClassColor.GetClassColor(class)
end

local function OnUnit(tooltip)
	local db = Tooltip.db
	local _, unit = tooltip:GetUnit()
	unit = Plain(unit)
	if not unit then return end
	if db.style and Plain(UnitIsPlayer(unit)) then
		local c = ClassColour(unit)
		if c then EdgeTo(tooltip, c.r, c.g, c.b) end
	end
	-- Names are hidden from addons in a fight: then there's no target line.
	if db.showTarget and not InCombatLockdown() then
		local target = unit .. "target"
		local name = Plain(UnitName(target))
		if name and Plain(UnitExists(target)) then
			local you = Plain(UnitIsUnit(target, "player"))
			local c = Plain(UnitIsPlayer(target)) and ClassColour(target)
			local text = you and ">> YOU <<" or name
			tooltip:AddLine("Target: " .. text, c and c.r or 1, c and c.g or 1, c and c.b or 1)
		end
	end
	if Tooltip.SkinningLine then Tooltip.SkinningLine(tooltip, unit) end
end

local function OnSpell(tooltip, data)
	local id = data and Plain(data.id)
	if Tooltip.db.showIDs and id then tooltip:AddDoubleLine("Spell ID", tostring(id), 0.6, 0.6, 0.6, 1, 1, 1) end
end

---------------------------------------------------------------------------
-- Settings and start-up
---------------------------------------------------------------------------

function Tooltip:OnInitialize()
	local page = StzxUI:AddSettingsPage("Tooltip")
	StzxUI:AddHeader(page, "Look")
	StzxUI:AddCheckbox(page, self, "style", "StzxUI look",
		"Dark background with a thin edge in the Skins edge colour. Off needs a reload.",
		function(on) if not on then StzxUI:AskReload("Blizzard's tooltip look comes back after a reload.") end end)
	StzxUI:AddCheckbox(page, self, "qualityEdge", "Edge in the item's quality or the player's class colour", nil)
	StzxUI:AddSlider(page, self, "textSize", "Text size", "Blizzard's is 12. Titles are 2 bigger, small text 2 smaller.",
		10, 20, 1, nil, ApplyFonts)
	StzxUI:AddCheckbox(page, self, "atCursor", "Show at the mouse", "Instead of the bottom-right corner.")
	StzxUI:AddHeader(page, "Extra lines")
	StzxUI:AddCheckbox(page, self, "showTarget", "Who they're targeting",
		"Out of combat only: the game hides names from addons in a fight.")
	StzxUI:AddCheckbox(page, self, "showItemLevel", "Item level on gear", nil)
	StzxUI:AddCheckbox(page, self, "showIDs", "Item and spell IDs", nil)
	StzxUI:AddCheckbox(page, self, "gathering", "Gathering skill needed",
		"Herbs, ore veins and skinnable corpses: the skill they need, coloured by yours (red: not yet, "
		.. "grey: no more skill-ups). Out of combat.")
end

function Tooltip:OnEnable()
	local db = self.db
	if db.style then
		for _, name in ipairs(TOOLTIPS) do StyleTooltip(_G[name]) end
		StyleHealthBar()
		-- Blizzard re-applies its frame art each time; keep it invisible.
		if SharedTooltip_SetBackdropStyle then
			hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip)
				if backdrops[tooltip] and tooltip.NineSlice then tooltip.NineSlice:SetAlpha(0) end
			end)
		end
		-- Back to the skin colour when a tooltip is cleared for its next use.
		for tooltip in pairs(backdrops) do
			tooltip:HookScript("OnTooltipCleared", function(cleared) Skin.ResetEdges(backdrops[cleared]) end)
		end
	end
	ApplyFonts()
	if GameTooltip_SetDefaultAnchor then
		hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
			if db.atCursor and tooltip == GameTooltip then tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", 24, 4) end
		end)
	end
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
		local T = Enum.TooltipDataType
		if T.Item then TooltipDataProcessor.AddTooltipPostCall(T.Item, OnItem) end
		if T.Unit then TooltipDataProcessor.AddTooltipPostCall(T.Unit, OnUnit) end
		if T.Spell then TooltipDataProcessor.AddTooltipPostCall(T.Spell, OnSpell) end
		if T.Object and Tooltip.OnObject then TooltipDataProcessor.AddTooltipPostCall(T.Object, Tooltip.OnObject) end
	end
end

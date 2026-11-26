-- StzxUI Info: travel (the hearthstone readout)
--
-- The hearthstone readout knows every way home (or away) this character has:
--   * Hearthstone (everyone), Astral Recall (shamans: your inn, its own timer)
--   * Teleport: Moonglade (druids)
--   * Mage teleports and portals to the capitals
--   * Engineering's Dimensional Ripper - Everlook and Ultrasafe Transporter:
--     Gadgetzan (when equipped)
-- Only the ones this character knows or carries are shown.
--
--   Readout   "Hearth: Ironforge" when your hearthstone is ready; if it's on
--             its cooldown but Astral Recall isn't, "Recall: Ironforge";
--             otherwise the time until the first one is ready
--   Hover     every travel option you have, where it goes, ready or not
--   Click     a small menu: one row per option; click a row to cast it or
--             use the item, exactly like an action button
--
-- The menu's rows are Blizzard's secure action buttons (the only way an addon
-- may cast a spell for you). The game lets addons set those up only out of
-- combat, so the menu opens out of combat and closes when a fight starts.

local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local Skin = StzxUI.Skin
local Info = StzxUI:GetModule("Info")

local Travel = {}
Info.Travel = Travel

-- In menu order. home: goes to your hearthstone's inn. equipped: a trinket
-- that only works while worn.
local OPTIONS = {
	{ item = 6948, label = "Hearthstone", home = true },
	{ spell = 556, label = "Astral Recall", home = true, short = "Recall" },
	{ spell = 18960, label = "Teleport: Moonglade", where = "Moonglade" },
	{ spell = 3561, label = "Teleport: Stormwind", where = "Stormwind" },
	{ spell = 3562, label = "Teleport: Ironforge", where = "Ironforge" },
	{ spell = 3565, label = "Teleport: Darnassus", where = "Darnassus" },
	{ spell = 3567, label = "Teleport: Orgrimmar", where = "Orgrimmar" },
	{ spell = 3563, label = "Teleport: Undercity", where = "Undercity" },
	{ spell = 3566, label = "Teleport: Thunder Bluff", where = "Thunder Bluff" },
	{ spell = 10059, label = "Portal: Stormwind", where = "Stormwind (group)" },
	{ spell = 11416, label = "Portal: Ironforge", where = "Ironforge (group)" },
	{ spell = 11419, label = "Portal: Darnassus", where = "Darnassus (group)" },
	{ spell = 11417, label = "Portal: Orgrimmar", where = "Orgrimmar (group)" },
	{ spell = 11418, label = "Portal: Undercity", where = "Undercity (group)" },
	{ spell = 11420, label = "Portal: Thunder Bluff", where = "Thunder Bluff (group)" },
	{ item = 18984, label = "Dimensional Ripper - Everlook", where = "Everlook", equipped = true },
	{ item = 18986, label = "Ultrasafe Transporter: Gadgetzan", where = "Gadgetzan", equipped = true },
}
Travel.OPTIONS = OPTIONS

local GREEN, YELLOW = "|cff7fdf7f", "|cffffd166"

local function Duration(seconds)
	if seconds >= 3600 then
		return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
	end
	if seconds >= 60 then return ("%dm"):format(math.floor(seconds / 60)) end
	return ("%ds"):format(math.max(1, math.floor(seconds)))
end

local function BindLocation()
	return (GetBindLocation and Plain(GetBindLocation())) or "?"
end

-- Does this character have it?
function Travel.Has(option)
	if option.spell then
		return C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(option.spell) or false
	end
	if option.equipped then
		return C_Item and C_Item.IsEquippedItem and C_Item.IsEquippedItem(option.item) or false
	end
	local count = C_Item and C_Item.GetItemCount and Plain(C_Item.GetItemCount(option.item))
	return (count or 0) > 0
end

-- The options this character has, in menu order.
function Travel.Available()
	local list = {}
	for _, option in ipairs(OPTIONS) do
		if Travel.Has(option) then list[#list + 1] = option end
	end
	return list
end

-- Seconds until it's ready (0: ready now). 1.5 s or less is just the global cooldown.
function Travel.Cooldown(option)
	local start, duration
	if option.spell then
		local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(option.spell)
		if info then start, duration = Plain(info.startTime), Plain(info.duration) end
	elseif C_Container and C_Container.GetItemCooldown then
		start, duration = C_Container.GetItemCooldown(option.item)
		start, duration = Plain(start), Plain(duration)
	end
	if not (start and duration) or start <= 0 or duration <= 1.5 then return 0 end
	return math.max(0, start + duration - GetTime())
end

function Travel.Name(option)
	local name
	if option.spell then
		name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(option.spell)
	else
		name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(option.item)
	end
	return Plain(name) or option.label
end

function Travel.Icon(option)
	local icon
	if option.spell then
		icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(option.spell)
	else
		icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(option.item)
	end
	return Plain(icon) or 134400 -- the question-mark icon
end

function Travel.Where(option)
	return option.home and BindLocation() or option.where
end

-- The readout: your hearthstone, or whichever way home is ready first.
function Travel.Text()
	local homes = {}
	for _, option in ipairs(Travel.Available()) do
		if option.home then homes[#homes + 1] = option end
	end
	if #homes == 0 then return ("Hearth: %s%s|r"):format(GREEN, BindLocation()) end
	local soonest, soonestLeft
	for _, option in ipairs(homes) do
		local left = Travel.Cooldown(option)
		if left <= 0 then
			return ("%s: %s%s|r"):format(option.short or "Hearth", GREEN, BindLocation())
		end
		if not soonestLeft or left < soonestLeft then soonest, soonestLeft = option, left end
	end
	return ("%s %s%s|r"):format(soonest.short or "Hearth", YELLOW, Duration(soonestLeft))
end

local function Update(frame) frame.text:SetText(Travel.Text()) end

local function Tooltip(frame)
	GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM", 0, -4)
	GameTooltip:ClearLines()
	GameTooltip:AddLine("Travel", 1, 1, 1)
	for _, option in ipairs(Travel.Available()) do
		local left = Travel.Cooldown(option)
		local ready = left > 0 and (YELLOW .. Duration(left) .. "|r") or (GREEN .. "ready|r")
		GameTooltip:AddDoubleLine(Travel.Name(option) .. "  |cff9a9a9a" .. (Travel.Where(option) or "") .. "|r", ready,
			1, 1, 1, 1, 1, 1)
	end
	if Info.db.travelMenu then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Click for the travel menu (out of combat).", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- The menu
---------------------------------------------------------------------------

local ROW_W, ROW_H = 260, 26
local menu, anchorFrame
local rows = {}

local function MakeRow(i)
	-- A secure action button: the game casts the spell / uses the item on click.
	local row = CreateFrame("Button", "StzxUITravelButton" .. i, menu, "SecureActionButtonTemplate")
	row:SetSize(ROW_W - 8, ROW_H - 2)
	row:RegisterForClicks("AnyUp")
	-- Act on the mouse release, whatever "cast on key down" is set to: the
	-- menu closes after the click (PostClick), so only one half may cast.
	row:SetAttribute("useOnKeyDown", false)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_H - 6, ROW_H - 6)
	row.icon:SetPoint("LEFT", 3, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetPoint("RIGHT", -60, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.ready = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.ready:SetPoint("RIGHT", -4, 0)
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(StzxUI.ACCENT.r, StzxUI.ACCENT.g, StzxUI.ACCENT.b, 0.25)
	row:SetScript("PostClick", function()
		if not InCombatLockdown() then menu:Hide() end
	end)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.option.spell then GameTooltip:SetSpellByID(self.option.spell) else GameTooltip:SetItemByID(self.option.item) end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = row
	return row
end

local function RefreshTimes()
	for _, row in ipairs(rows) do
		if row:IsShown() and row.option then
			local left = Travel.Cooldown(row.option)
			row.ready:SetText(left > 0 and (YELLOW .. Duration(left) .. "|r") or (GREEN .. "ready|r"))
			row.icon:SetDesaturated(left > 0)
		end
	end
end

local function BuildMenu()
	menu = CreateFrame("Frame", "StzxUITravelMenu", UIParent)
	menu:SetFrameStrata("DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	Skin.Backdrop(menu, { edge = "accent", fill = { 0, 0, 0 }, alpha = 0.92 })
	menu:Hide()
	local wait = 0
	menu:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.5
		RefreshTimes()
	end)
	-- Close when a fight starts (this event comes just before the game locks
	-- secure frames), or on a click anywhere else.
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("GLOBAL_MOUSE_DOWN")
	events:SetScript("OnEvent", function(_, event)
		if not menu:IsShown() or InCombatLockdown() then return end
		if event == "GLOBAL_MOUSE_DOWN" and (menu:IsMouseOver() or (anchorFrame and anchorFrame:IsMouseOver())) then return end
		menu:Hide()
	end)
	table.insert(UISpecialFrames, "StzxUITravelMenu") -- Escape closes it
end

function Travel.Open(anchor)
	if InCombatLockdown() then
		StzxUI:Say("the travel menu opens out of combat.")
		return false
	end
	if not menu then BuildMenu() end
	local list = Travel.Available()
	if #list == 0 then return false end
	for i, option in ipairs(list) do
		local row = rows[i] or MakeRow(i)
		row.option = option
		if option.spell then
			row:SetAttribute("type", "spell")
			row:SetAttribute("spell", option.spell)
			row:SetAttribute("item", nil)
		else
			row:SetAttribute("type", "item")
			row:SetAttribute("item", "item:" .. option.item)
			row:SetAttribute("spell", nil)
		end
		row.icon:SetTexture(Travel.Icon(option))
		row.name:SetText(Travel.Name(option))
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * ROW_H)
		row:Show()
	end
	for i = #list + 1, #rows do rows[i]:Hide() end
	menu:SetSize(ROW_W, #list * ROW_H + 8)
	-- Under the readout (above it if there's no room below), placed on the screen
	-- itself rather than on the readout: secure frames shouldn't hang off ours.
	anchorFrame = anchor
	local scale = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local left, bottom, top = (anchor:GetLeft() or 0) * scale, (anchor:GetBottom() or 0) * scale, (anchor:GetTop() or 0) * scale
	menu:ClearAllPoints()
	if bottom - menu:GetHeight() - 4 > 0 then
		menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, bottom - 4)
	else
		menu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, top + 4)
	end
	RefreshTimes()
	menu:Show()
	return true
end

function Travel.Toggle(anchor)
	if menu and menu:IsShown() then
		if not InCombatLockdown() then menu:Hide() end
		return
	end
	Travel.Open(anchor)
end

-- Plug into the hearthstone readout.
for _, def in ipairs(Info.READOUTS) do
	if def.id == "hearth" then
		def.label = "Info: hearthstone and travel"
		def.update = Update
		def.tooltip = Tooltip
		def.events = { "HEARTHSTONE_BOUND", "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED" }
		def.click = function(frame, button)
			if button == "LeftButton" and Info.db.travelMenu then
				GameTooltip:Hide()
				Travel.Toggle(frame)
			end
		end
	end
end

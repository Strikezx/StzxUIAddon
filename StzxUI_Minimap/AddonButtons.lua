-- StzxUI Minimap: addon buttons in a fly-out
--
-- Addons put their buttons around the edge of the minimap. StzxUI gathers
-- them into a small panel instead, opened by a little square button in the
-- minimap's bottom-right corner. Click it again (or press Escape) to close.
--
-- Which buttons are gathered:
--   * every button made with LibDBIcon (most addons use it)
--   * if "Also gather other addons' buttons" is on: other named, button-sized
--     buttons that an addon (not Blizzard) put on the minimap. Map pins
--     (Questie, HandyNotes and so on, through HereBeDragons) are left alone.
-- Blizzard's own minimap buttons (tracking, mail, calendar...) always stay.
--
-- Gathered buttons stay the addon's own: StzxUI only moves them. LibDBIcon
-- re-places its buttons around the minimap now and then (at login, or when
-- you change that addon's settings); StzxUI notices and puts them back.
-- Turning gathering off hands every button back where it was.

local _, ns = ...
local StzxUI = _G.StzxUI
local A = StzxUI.ACCENT

local CELL = 33 -- space for one button (LibDBIcon buttons are 31 wide)
local PAD = 4

local toggle, panel
local collected = {} -- button -> what to put back when released
local order = {} -- gathered buttons, sorted by name
local hooked = {} -- buttons we've hooked once (hooks can't be undone)
local placing = false -- true while StzxUI itself is moving buttons

local function DB() return ns.module.db end

local function Libs()
	local LibStub = _G.LibStub
	if not LibStub then return nil, nil end
	return LibStub("LibDBIcon-1.0", true), LibStub("HereBeDragons-Pins-2.0", true)
end

-- LibDBIcon's name for the button ("LibDBIcon10_Questie" -> "Questie").
local function IconName(button)
	local name = button:GetName()
	return name and name:match("^LibDBIcon10_(.+)$")
end

-- An addon's button that isn't a LibDBIcon one: gather it?
local function IsOtherAddonButton(frame, pins)
	if frame == toggle or frame == panel or collected[frame] then return false end
	local name = frame:GetName()
	if not name or IconName(frame) then return false end
	if frame:GetObjectType() ~= "Button" then return false end
	-- Globals Blizzard's own code made are "secure"; an addon's are not.
	if issecurevariable(_G, name) then return false end
	if frame:IsProtected() then return false end
	if pins and ((pins.minimapPins and pins.minimapPins[frame]) or
		(pins.activeMinimapPins and pins.activeMinimapPins[frame])) then return false end
	local w, h = frame:GetWidth(), frame:GetHeight()
	return w >= 14 and w <= 40 and h >= 14 and h <= 40
end

---------------------------------------------------------------------------
-- Laying out the panel
---------------------------------------------------------------------------
local function Shown()
	local list = {}
	for _, button in ipairs(order) do
		if button:IsShown() then list[#list + 1] = button end
	end
	return list
end

local function Layout()
	local list = Shown()
	local cols = math.max(1, math.min(DB().buttonColumns, #list))
	local rows = math.max(1, math.ceil(#list / cols))
	placing = true
	for i, button in ipairs(list) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		button:ClearAllPoints()
		button:SetPoint("CENTER", panel, "TOPLEFT", PAD + CELL / 2 + col * CELL, -(PAD + CELL / 2 + row * CELL))
		-- No dragging around the minimap while it's in the panel.
		button:SetScript("OnDragStart", nil)
		button:SetScript("OnDragStop", nil)
	end
	placing = false
	panel:SetSize(PAD * 2 + cols * CELL, PAD * 2 + rows * CELL)
end

local OPEN_TOWARDS = {
	LEFT = { "BOTTOMRIGHT", "BOTTOMLEFT", -4, 0 },
	RIGHT = { "BOTTOMLEFT", "BOTTOMRIGHT", 4, 0 },
	DOWN = { "TOPRIGHT", "BOTTOMRIGHT", 0, -4 },
	UP = { "BOTTOMRIGHT", "TOPRIGHT", 0, 4 },
}

local function PlacePanel()
	local p = OPEN_TOWARDS[DB().buttonsOpen] or OPEN_TOWARDS.LEFT
	panel:ClearAllPoints()
	panel:SetPoint(p[1], _G.Minimap, p[2], p[3], p[4])
end

local function UpdateToggle()
	toggle:SetShown(DB().collectButtons and #order > 0)
	toggle.glyph:SetText(panel:IsShown() and "-" or "+")
end

---------------------------------------------------------------------------
-- Gathering and handing back
---------------------------------------------------------------------------
local function Collect(button)
	local saved = { parent = button:GetParent(), points = {},
		dragStart = button:GetScript("OnDragStart"), dragStop = button:GetScript("OnDragStop"),
		fade = button.showOnMouseover }
	for i = 1, button:GetNumPoints() do saved.points[i] = { button:GetPoint(i) } end
	collected[button] = saved
	order[#order + 1] = button
	-- LibDBIcon's "only show on mouse-over" would leave it invisible in the panel.
	if button.showOnMouseover then
		button.showOnMouseover = false
		if button.fadeOut then button.fadeOut:Stop() end
	end
	button:SetAlpha(1)
	button:SetParent(panel)
	if not hooked[button] then
		hooked[button] = true
		-- The addon moved it back to the minimap's edge: put it back in the panel.
		hooksecurefunc(button, "SetPoint", function(self)
			if collected[self] and not placing then Layout() end
		end)
		button:HookScript("OnClick", function(self)
			if collected[self] and DB().closeOnClick then panel:Hide() end
		end)
	end
end

local function Release(button)
	local saved = collected[button]
	collected[button] = nil
	button:SetParent(saved.parent)
	placing = true
	button:ClearAllPoints()
	for _, p in ipairs(saved.points) do button:SetPoint(unpack(p)) end
	placing = false
	button:SetScript("OnDragStart", saved.dragStart)
	button:SetScript("OnDragStop", saved.dragStop)
	button.showOnMouseover = saved.fade
	-- LibDBIcon puts its own buttons back exactly (position, dragging, mouse-over).
	local dbi = Libs()
	local name = IconName(button)
	if dbi and name and dbi:IsRegistered(name) then dbi:Refresh(name) end
end

local function SortByName()
	table.sort(order, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end)
end

-- Look for buttons to gather (cheap; done at login and whenever the panel opens).
local function Scan()
	if not DB().collectButtons then return end
	local dbi, pins = Libs()
	if dbi then
		for _, name in ipairs(dbi:GetButtonList()) do
			local button = dbi:GetMinimapButton(name)
			if button and not collected[button] then Collect(button) end
		end
	end
	if DB().collectOtherButtons then
		for _, parent in ipairs({ _G.Minimap, _G.MinimapBackdrop }) do
			for _, child in ipairs({ parent:GetChildren() }) do
				if IsOtherAddonButton(child, pins) then Collect(child) end
			end
		end
	end
	SortByName()
	Layout()
	UpdateToggle()
end
ns.ScanAddonButtons = Scan

local function ReleaseAll()
	panel:Hide()
	for i = #order, 1, -1 do Release(order[i]) end
	order = {}
	UpdateToggle()
end

local function Refresh()
	if DB().collectButtons then Scan() else ReleaseAll() end
end

---------------------------------------------------------------------------
-- The corner button and the panel
---------------------------------------------------------------------------
local function AccentEdges(frame)
	local edges = {}
	for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
		local line = frame:CreateTexture(nil, "OVERLAY")
		line:SetPoint(edge[1])
		line:SetPoint(edge[2])
		if edge[3] then line:SetHeight(1) else line:SetWidth(1) end
		line:SetColorTexture(A.r, A.g, A.b, 1)
		edges[#edges + 1] = line
	end
	return edges
end

local function Build()
	local map = _G.Minimap
	panel = CreateFrame("Frame", "StzxUIMinimapButtons", UIParent)
	panel:SetFrameStrata("HIGH")
	panel:SetClampedToScreen(true)
	panel:Hide()
	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
	AccentEdges(panel)
	table.insert(UISpecialFrames, "StzxUIMinimapButtons") -- Escape closes it
	panel:SetScript("OnShow", function() Scan(); UpdateToggle() end)
	-- Placed from the start, not only when opened: gathered buttons must
	-- always have a place on screen, because their addons may ask where
	-- they are (Zygor does at start-up, and errored when they had none).
	PlacePanel()
	panel:SetScript("OnHide", function() UpdateToggle() end)

	toggle = CreateFrame("Button", nil, map)
	toggle:SetSize(16, 16)
	toggle:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", -3, 3)
	toggle:SetFrameLevel(map:GetFrameLevel() + 10)
	local fill = toggle:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(0.05, 0.05, 0.05, 0.85)
	toggle.fill = fill
	AccentEdges(toggle)
	toggle.glyph = toggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	toggle.glyph:SetPoint("CENTER", 0, 1)
	toggle:SetScript("OnClick", function()
		if panel:IsShown() then panel:Hide() else PlacePanel(); panel:Show() end
	end)
	toggle:SetScript("OnEnter", function(self)
		self.fill:SetColorTexture(A.r * 0.4, A.g * 0.4, A.b * 0.4, 0.9)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Addon buttons")
		local n = #Shown()
		GameTooltip:AddLine(n == 1 and "1 button." or (n .. " buttons."), 1, 1, 1)
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", function(self)
		self.fill:SetColorTexture(0.05, 0.05, 0.05, 0.85)
		GameTooltip:Hide()
	end)
	toggle:Hide()
end

---------------------------------------------------------------------------
-- /stzx buttons: what's in the panel (to track down odd-looking buttons)
---------------------------------------------------------------------------
local function Describe(button)
	local name = IconName(button)
	local parts = { (name or button:GetName() or "?") .. (name and " (LibDBIcon)" or " (other)") }
	parts[#parts + 1] = ("see-through %d%%"):format(math.floor((1 - button:GetAlpha()) * 100 + 0.5))
	local icon = button.icon
	if icon and icon.GetVertexColor then
		local r, g, b = icon:GetVertexColor()
		if r and (r < 0.99 or g < 0.99 or b < 0.99) then
			parts[#parts + 1] = ("icon tinted %.2f %.2f %.2f"):format(r, g, b)
		end
	end
	if icon and icon.IsDesaturated and icon:IsDesaturated() then parts[#parts + 1] = "icon greyed out" end
	if not button:IsShown() then parts[#parts + 1] = "hidden" end
	return table.concat(parts, ", ")
end

StzxUI.slashCommands.buttons = {
	help = "list the addon buttons gathered from the minimap",
	run = function()
		if #order == 0 then
			StzxUI:Say("no addon buttons gathered.")
			return
		end
		StzxUI:Say(("%d addon buttons gathered:"):format(#order))
		for _, button in ipairs(order) do StzxUI:Say("  " .. Describe(button)) end
	end,
}

---------------------------------------------------------------------------
-- Settings and start-up
---------------------------------------------------------------------------
function ns.AddButtonSettings(page, module)
	StzxUI:AddHeader(page, "Addon buttons",
		"Gather addons' minimap buttons into a small panel, opened from the minimap's bottom-right corner.")
	StzxUI:AddCheckbox(page, module, "collectButtons", "Gather addon buttons",
		"Off: every button goes back around the minimap.", function() if panel then Refresh() end end)
	StzxUI:AddCheckbox(page, module, "collectOtherButtons", "Also gather other addons' buttons",
		"Buttons not made with LibDBIcon. Turn this off if something that isn't a minimap button gets gathered.",
		function() if panel then ReleaseAll(); Refresh() end end)
	StzxUI:AddSlider(page, module, "buttonColumns", "Buttons per row", nil, 1, 8, 1, nil,
		function() if panel then Layout() end end)
	StzxUI:AddDropdown(page, module, "buttonsOpen", "Panel opens", nil, {
		{ "LEFT", "Left of the minimap" }, { "RIGHT", "Right of the minimap" },
		{ "DOWN", "Below the minimap" }, { "UP", "Above the minimap" },
	}, function() if panel then PlacePanel() end end)
	StzxUI:AddCheckbox(page, module, "closeOnClick", "Close the panel after clicking a button", nil)
end

function ns.StartAddonButtons()
	if not _G.Minimap then return end
	Build()
	-- Addons make their buttons as they load: look now, after login, and
	-- whenever LibDBIcon makes a new one.
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		C_Timer.After(2, Scan)
	end)
	local dbi = Libs()
	if dbi and dbi.RegisterCallback then
		dbi.RegisterCallback(ns, "LibDBIcon_IconCreated", function() C_Timer.After(0, Scan) end)
	end
	Scan()
end

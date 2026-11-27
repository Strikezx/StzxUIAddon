-- StzxUI Move Mode  (/stzx move)
-- Dims the screen, draws a grid from the screen centre, and shows a labelled
-- box over every StzxUI frame. Drag a box to move its frame.
--   Left-drag          move (lines up with nearby frames, else snaps to the grid)
--   Shift + drag       place freely, no snapping
--   Mouse wheel        make the frame bigger or smaller
--   Right-click        put that frame back where it started, at normal size
--   Arrow keys         nudge 1 unit (Shift: one grid step) while hovering a box
-- The toolbar's "Show" row hides whole groups of boxes (e.g. Info).
-- Combat closes move mode straight away.

local StzxUI = _G.StzxUI
local A = StzxUI.ACCENT

local grid, toolbar
local gridLines = {}

---------------------------------------------------------------------------
-- The box drawn over each frame
---------------------------------------------------------------------------

local ARROWS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }

function StzxUI:BuildMoverOverlay(holder)
	local box = CreateFrame("Button", nil, holder)
	box:SetAllPoints()
	box:SetFrameStrata("DIALOG")
	box:Hide()

	local fill = box:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(A.r, A.g, A.b, 0.25)
	box.fill = fill

	-- 1-unit outline
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local edge = box:CreateTexture(nil, "BORDER")
		edge:SetColorTexture(A.r, A.g, A.b, 0.9)
		if side == "TOP" or side == "BOTTOM" then
			edge:SetPoint(side .. "LEFT")
			edge:SetPoint(side .. "RIGHT")
			edge:SetHeight(1)
		else
			edge:SetPoint("TOP" .. side)
			edge:SetPoint("BOTTOM" .. side)
			edge:SetWidth(1)
		end
	end

	local label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	box.label = label
	box.UpdateLabel = function()
		local scale = StzxUI:GetMoverScale(holder)
		if scale ~= 1 then
			label:SetFormattedText("%s  |cffaaaaaa%d%%|r", holder.label, math.floor(scale * 100 + 0.5))
		else
			label:SetText(holder.label)
		end
	end
	box:UpdateLabel()

	box:RegisterForDrag("LeftButton")
	box:RegisterForClicks("RightButtonUp")
	box:SetScript("OnDragStart", function() holder:StartMoving() end)
	box:SetScript("OnDragStop", function()
		holder:StopMovingOrSizing()
		StzxUI:SaveMoverPosition(holder, IsShiftKeyDown())
	end)
	box:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			StzxUI:ResetMover(holder.key)
			box:UpdateLabel()
		end
	end)
	box:EnableMouseWheel(true)
	box:SetScript("OnMouseWheel", function(_, delta)
		if InCombatLockdown() then return end
		if holder.widthWheel and IsControlKeyDown() then
			holder.widthWheel(delta)
			box:UpdateLabel()
			return
		end
		if not holder.scalable then return end
		StzxUI:ScaleMover(holder, delta > 0 and 0.05 or -0.05)
		box:UpdateLabel()
	end)

	box:SetScript("OnEnter", function(button)
		button.fill:SetColorTexture(A.r, A.g, A.b, 0.45)
		button:EnableKeyboard(true)
		button:SetPropagateKeyboardInput(true) -- only arrow keys are kept back
		GameTooltip:SetOwner(button, "ANCHOR_TOP")
		GameTooltip:AddLine(holder.label, A.r, A.g, A.b)
		GameTooltip:AddLine("Drag to move. Shift-drag: no snapping.", 1, 1, 1)
		GameTooltip:AddLine("Arrow keys: nudge. Right-click: reset.", 1, 1, 1)
		if holder.scalable then
			GameTooltip:AddLine("Mouse wheel: bigger or smaller.", 1, 1, 1)
		end
		if holder.widthWheel then
			GameTooltip:AddLine("Ctrl + mouse wheel: wider or narrower.", 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	box:SetScript("OnLeave", function(button)
		button.fill:SetColorTexture(A.r, A.g, A.b, 0.25)
		button:EnableKeyboard(false)
		GameTooltip:Hide()
	end)
	box:SetScript("OnKeyDown", function(button, key)
		local arrow = ARROWS[key]
		if arrow and not InCombatLockdown() then
			local step = IsShiftKeyDown() and (StzxUI.db.core.gridSize or 16) or 1
			StzxUI:NudgeMover(holder, arrow[1] * step, arrow[2] * step)
			button:SetPropagateKeyboardInput(false)
		elseif not InCombatLockdown() then
			button:SetPropagateKeyboardInput(true) -- every other key still reaches the game
		end
	end)

	holder.overlay = box
end

local function ShowBox(holder)
	local wanted = (not holder.isShown or holder.isShown())
		and not StzxUI.db.core.hiddenCategories[holder.category]
	holder.overlay:SetShown(wanted)
	if wanted then holder.overlay:UpdateLabel() end
end

local function ShowBoxes()
	for _, key in ipairs(StzxUI.moverOrder) do
		ShowBox(StzxUI.movers[key])
	end
end

---------------------------------------------------------------------------
-- Grid
---------------------------------------------------------------------------

local function BuildGrid()
	grid = CreateFrame("Frame", nil, UIParent)
	grid:SetAllPoints(UIParent)
	grid:SetFrameStrata("BACKGROUND")
	grid:Hide()
	local shade = grid:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0, 0, 0, 0.35)
	return grid
end

---------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------

local function EditModeActive()
	local manager = _G.EditModeManagerFrame
	return manager and manager.IsEditModeActive and manager:IsEditModeActive() or false
end
StzxUI.EditModeActive = EditModeActive

-- Edit Mode's grid spacing while Edit Mode is open with its grid showing, else nil.
function StzxUI:EditModeGridSize()
	if not EditModeActive() then return nil end
	local manager = _G.EditModeManagerFrame
	if not (manager.Grid and manager.Grid:IsShown()) then return nil end
	local ok, spacing = pcall(manager.GetAccountSettingValue, manager, Enum.EditModeAccountSetting.GridSpacing)
	spacing = ok and tonumber(spacing)
	return spacing and spacing > 0 and spacing or nil
end

function StzxUI:RefreshGrid()
	if not grid or not self.moveMode then return end
	-- Edit Mode draws its own grid from the screen centre, like ours: show only one.
	local editGrid = self:EditModeGridSize()
	grid:SetShown(not editGrid)
	if toolbar then
		toolbar.gridButton:SetText(editGrid and ("Grid: %d (Edit Mode)"):format(editGrid)
			or ("Grid: %d"):format(self.db.core.gridSize or 16))
		toolbar.gridButton:SetEnabled(not editGrid)
	end
	if editGrid then return end
	for _, line in ipairs(gridLines) do line:Hide() end

	local step = math.max(4, self.db.core.gridSize or 16)
	local used = 0
	local function Line(vertical, offset, centre)
		used = used + 1
		local line = gridLines[used]
		if not line then
			line = grid:CreateTexture(nil, "BORDER")
			gridLines[used] = line
		end
		line:ClearAllPoints()
		if vertical then
			line:SetPoint("TOP", grid, "TOP", offset, 0)
			line:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
			line:SetWidth(centre and 2 or 1)
		else
			line:SetPoint("LEFT", grid, "LEFT", 0, offset)
			line:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
			line:SetHeight(centre and 2 or 1)
		end
		if centre then
			line:SetColorTexture(A.r, A.g, A.b, 0.8)
		else
			line:SetColorTexture(1, 1, 1, 0.12)
		end
		line:Show()
	end

	-- Lines run out from the centre, so the centre lines are always on the grid.
	Line(true, 0, true)
	Line(false, 0, true)
	local halfWidth, halfHeight = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
	for k = 1, math.floor(halfWidth / step) do
		Line(true, k * step)
		Line(true, -k * step)
	end
	for k = 1, math.floor(halfHeight / step) do
		Line(false, k * step)
		Line(false, -k * step)
	end
end

---------------------------------------------------------------------------
-- Toolbar
---------------------------------------------------------------------------

local GRID_STEPS = { 8, 16, 32, 64 }

local function NextGridSize(current)
	for _, size in ipairs(GRID_STEPS) do
		if size > current then return size end
	end
	return GRID_STEPS[1]
end

local function BuildToolbar()
	local bar = CreateFrame("Frame", "StzxUIMoveToolbar", UIParent)
	bar:SetSize(700, 96)
	bar:SetPoint("TOP", 0, -48)
	bar:SetFrameStrata("FULLSCREEN_DIALOG")
	bar:SetClampedToScreen(true)
	bar:SetMovable(true)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", bar.StartMoving)
	bar:SetScript("OnDragStop", bar.StopMovingOrSizing)
	bar:Hide()

	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.06, 0.07, 0.09, 0.95)
	local line = bar:CreateTexture(nil, "BORDER")
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	line:SetHeight(2)
	line:SetColorTexture(A.r, A.g, A.b, 1)

	local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText("StzxUI move mode")
	title:SetTextColor(A.r, A.g, A.b)

	local hint = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("LEFT", title, "RIGHT", 10, 0)
	hint:SetText("Drag boxes. Shift: free. Wheel: size. Right-click: reset. Arrows: nudge.")
	hint:SetTextColor(0.8, 0.8, 0.8)

	-- Row 1: snapping switches.
	local function Switch(text, key, anchor)
		local check = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
		check:SetSize(24, 24)
		if anchor then
			check:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
		else
			check:SetPoint("TOPLEFT", 8, -30)
		end
		local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("LEFT", check, "RIGHT", 2, 0)
		label:SetText(text)
		check:SetScript("OnClick", function(button)
			StzxUI.db.core[key] = button:GetChecked() and true or false
		end)
		check.key = key
		return check, label
	end
	local snapLabel, framesLabel
	bar.snap, snapLabel = Switch("Snap to grid", "snapToGrid")
	bar.snapFrames, framesLabel = Switch("Snap to frames", "snapToFrames", snapLabel)

	-- Test frames: pretend party and raid members (and anything else that
	-- registers a test mode) so there's something to place.
	local test = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
	test:SetSize(24, 24)
	test:SetPoint("LEFT", framesLabel, "RIGHT", 12, 0)
	test.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	test.label:SetPoint("LEFT", test, "RIGHT", 2, 0)
	test.label:SetText("Test frames")
	test:SetScript("OnClick", function(button)
		local on = button:GetChecked() and true or false
		StzxUI:SetTestMode(on)
		StzxUI.testFromMoveMode = on
	end)
	bar.test = test

	-- Row 2: "Show:" one switch per category, built when move mode opens.
	local showLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	showLabel:SetPoint("BOTTOMLEFT", 12, 14)
	showLabel:SetText("Show:")
	showLabel:SetTextColor(0.8, 0.8, 0.8)
	bar.showLabel = showLabel
	bar.filters = {}

	local done = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
	done:SetSize(80, 24)
	done:SetPoint("TOPRIGHT", -10, -30)
	done:SetText("Done")
	done:SetScript("OnClick", function() StzxUI:ExitMoveMode() end)

	local reset = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
	reset:SetSize(90, 24)
	reset:SetPoint("RIGHT", done, "LEFT", -6, 0)
	reset:SetText("Reset all")
	reset:SetScript("OnClick", function()
		StzxUI:ShowDialog({
			title = "Reset all positions",
			text = ("Put every StzxUI frame back where it started, in the profile '%s'?"):format(StzxUI.profileName),
			accept = "Reset all",
			onAccept = function() StzxUI:ResetAllMovers() return true end,
		})
	end)

	local gridButton = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
	gridButton:SetSize(90, 24)
	gridButton:SetPoint("RIGHT", reset, "LEFT", -6, 0)
	gridButton:SetScript("OnClick", function(self)
		StzxUI.db.core.gridSize = NextGridSize(StzxUI.db.core.gridSize or 16)
		self:SetText(("Grid: %d"):format(StzxUI.db.core.gridSize))
		StzxUI:RefreshGrid()
	end)
	bar.gridButton = gridButton

	-- Escape closes move mode.
	bar:SetScript("OnHide", function()
		if StzxUI.moveMode then StzxUI:ExitMoveMode() end
	end)
	table.insert(UISpecialFrames, "StzxUIMoveToolbar")
	return bar
end

-- One "Show" switch per category of frames, e.g. [x] Info  [x] Unit frames.
local function RefreshFilters(bar)
	local hidden = StzxUI.db.core.hiddenCategories
	local anchor = bar.showLabel
	for i, category in ipairs(StzxUI:GetMoverCategories()) do
		local filter = bar.filters[i]
		if not filter then
			filter = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
			filter:SetSize(20, 20)
			filter.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			filter.label:SetPoint("LEFT", filter, "RIGHT", 1, 0)
			filter:SetScript("OnClick", function(button)
				hidden[button.category] = (not button:GetChecked()) or nil
				ShowBoxes()
			end)
			bar.filters[i] = filter
		end
		filter:ClearAllPoints()
		filter:SetPoint("LEFT", anchor, "RIGHT", i == 1 and 6 or 8, 0)
		filter.category = category
		filter.label:SetText(category)
		filter:SetChecked(not hidden[category])
		filter:Show()
		filter.label:Show()
		anchor = filter.label
	end
	for i = #StzxUI:GetMoverCategories() + 1, #bar.filters do
		bar.filters[i]:Hide()
		bar.filters[i].label:Hide()
	end
end

---------------------------------------------------------------------------
-- On and off
---------------------------------------------------------------------------

function StzxUI:EnterMoveMode()
	if self.moveMode then return end
	if InCombatLockdown() then
		self:Say("frames can't be moved in combat.")
		return
	end
	if #self.moverOrder == 0 then
		self:Say("nothing to move yet. Switch on a section with frames (StzxUI > Sections), then /reload.")
		return
	end
	if SettingsPanel and SettingsPanel:IsShown() then SettingsPanel:Close(true) end

	grid = grid or BuildGrid()
	toolbar = toolbar or BuildToolbar()
	self.moveMode = true

	grid:Show()
	toolbar.snap:SetChecked(self.db.core.snapToGrid and true or false)
	toolbar.snapFrames:SetChecked(self.db.core.snapToFrames and true or false)
	local hasTests = next(self.testModes) ~= nil
	toolbar.test:SetShown(hasTests)
	toolbar.test.label:SetShown(hasTests)
	toolbar.test:SetChecked(self.testMode and true or false)
	RefreshFilters(toolbar)
	self:PlaceToolbar()
	toolbar:Show()
	self:RefreshGrid()
	ShowBoxes()
end

-- Edit Mode's own panel sits at the top centre, so with both open the
-- toolbar moves to the top-left corner (it can still be dragged).
function StzxUI:PlaceToolbar()
	if not toolbar then return end
	toolbar:ClearAllPoints()
	if EditModeActive() then
		toolbar:SetPoint("TOPLEFT", 16, -16)
	else
		toolbar:SetPoint("TOP", 0, -48)
	end
end

function StzxUI:ExitMoveMode()
	if not self.moveMode then return end
	self.moveMode = false
	for _, key in ipairs(self.moverOrder) do
		self.movers[key].overlay:Hide()
	end
	if grid then grid:Hide() end
	if toolbar and toolbar:IsShown() then toolbar:Hide() end
	-- Test frames switched on from the toolbar go away with move mode.
	if self.testFromMoveMode then
		self.testFromMoveMode = false
		self:SetTestMode(false)
	end
	GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Test frames
---------------------------------------------------------------------------

-- Modules register a function(on) that shows or hides pretend frames.
StzxUI.testModes = {}
StzxUI.testMode = false

function StzxUI:RegisterTestMode(name, fn)
	self.testModes[name] = fn
end

-- Returns false when it can't (in combat).
function StzxUI:SetTestMode(on)
	on = on and true or false
	if on and InCombatLockdown() then
		self:Say("test frames can't be shown in combat.")
		if toolbar then toolbar.test:SetChecked(false) end
		return false
	end
	self.testMode = on
	for _, fn in pairs(self.testModes) do fn(on) end
	if toolbar then toolbar.test:SetChecked(on) end
	return true
end

function StzxUI:ToggleTestMode()
	if not next(self.testModes) then
		self:Say("nothing has test frames: Party & Raid, Nameplates and Threat Meter are all switched off.")
		return
	end
	self.testFromMoveMode = false
	if not self:SetTestMode(not self.testMode) then return end
	self:Say(self.testMode and "test frames on. /stzx test again to hide them." or "test frames off.")
end

function StzxUI:ToggleMoveMode()
	if self.moveMode then self:ExitMoveMode() else self:EnterMoveMode() end
end

-- Edit Mode opens and closes move mode with it (setting "Open with Edit
-- Mode"). Blizzard calls these through its callback registry, which keeps
-- our code apart from its secure code.
local openedByEditMode = false
if EventRegistry and EventRegistry.RegisterCallback then
	EventRegistry:RegisterCallback("EditMode.Enter", function()
		if StzxUI.moveMode then
			StzxUI:PlaceToolbar()
			StzxUI:RefreshGrid()
		elseif StzxUI.db and StzxUI.db.core.withEditMode and #StzxUI.moverOrder > 0 and not InCombatLockdown() then
			StzxUI:EnterMoveMode()
			openedByEditMode = StzxUI.moveMode
		end
	end, "StzxUIMoveModeEnter")
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		if openedByEditMode and StzxUI.moveMode then
			StzxUI:ExitMoveMode()
		else
			StzxUI:PlaceToolbar()
			StzxUI:RefreshGrid()
		end
		openedByEditMode = false
	end, "StzxUIMoveModeExit")
end

-- Edit Mode's grid switch and spacing slider: keep our grid in step.
local gridHooked = false
local function HookEditModeGrid()
	local manager = _G.EditModeManagerFrame
	if not manager or gridHooked then return end
	gridHooked = true
	for _, method in ipairs({ "SetGridShown", "SetGridSpacing" }) do
		if manager[method] then
			hooksecurefunc(manager, method, function() StzxUI:RefreshGrid() end)
		end
	end
end
HookEditModeGrid()

-- Combat closes move mode and test frames at once (this event comes just
-- before the game locks secure frames).
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
	if StzxUI.moveMode then
		StzxUI:ExitMoveMode()
		StzxUI:Say("move mode closed for combat.")
	end
	if StzxUI.testMode then
		StzxUI:SetTestMode(false)
		StzxUI:Say("test frames hidden for combat.")
	end
end)

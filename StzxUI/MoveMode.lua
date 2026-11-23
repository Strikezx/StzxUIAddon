-- StzxUI Move Mode  (/stzx move)
-- Dims the screen, draws a grid from the screen centre, and shows a labelled
-- box over every StzxUI frame. Drag a box to move its frame.
--   Left-drag          move (snaps to the grid when snapping is on)
--   Shift + drag       place freely, no snapping
--   Right-click        put that frame back where it started
--   Arrow keys         nudge 1 unit (Shift: one grid step) while hovering a box
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
	label:SetText(holder.label)
	box.label = label

	box:RegisterForDrag("LeftButton")
	box:RegisterForClicks("RightButtonUp")
	box:SetScript("OnDragStart", function() holder:StartMoving() end)
	box:SetScript("OnDragStop", function()
		holder:StopMovingOrSizing()
		StzxUI:SaveMoverPosition(holder, IsShiftKeyDown())
	end)
	box:SetScript("OnClick", function(_, button)
		if button == "RightButton" then StzxUI:ResetMover(holder.key) end
	end)

	box:SetScript("OnEnter", function(button)
		button.fill:SetColorTexture(A.r, A.g, A.b, 0.45)
		button:EnableKeyboard(true)
		button:SetPropagateKeyboardInput(true) -- only arrow keys are kept back
		GameTooltip:SetOwner(button, "ANCHOR_TOP")
		GameTooltip:AddLine(holder.label, A.r, A.g, A.b)
		GameTooltip:AddLine("Drag to move. Shift-drag: no snapping.", 1, 1, 1)
		GameTooltip:AddLine("Arrow keys: nudge. Right-click: reset.", 1, 1, 1)
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
	local wanted = not holder.isShown or holder.isShown()
	holder.overlay:SetShown(wanted)
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

function StzxUI:RefreshGrid()
	if not grid or not grid:IsShown() then return end
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
	bar:SetSize(520, 66)
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
	hint:SetText("Drag boxes. Shift: no snap. Right-click: reset. Arrows: nudge.")
	hint:SetTextColor(0.8, 0.8, 0.8)

	local snap = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
	snap:SetSize(24, 24)
	snap:SetPoint("BOTTOMLEFT", 8, 8)
	local snapLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	snapLabel:SetPoint("LEFT", snap, "RIGHT", 2, 0)
	snapLabel:SetText("Snap to grid")
	snap:SetScript("OnClick", function(self)
		StzxUI.db.core.snapToGrid = self:GetChecked() and true or false
	end)
	bar.snap = snap

	local done = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
	done:SetSize(80, 24)
	done:SetPoint("BOTTOMRIGHT", -10, 8)
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
	self:RefreshGrid()
	toolbar.snap:SetChecked(self.db.core.snapToGrid and true or false)
	toolbar.gridButton:SetText(("Grid: %d"):format(self.db.core.gridSize or 16))
	toolbar:Show()
	for _, key in ipairs(self.moverOrder) do
		ShowBox(self.movers[key])
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
	GameTooltip:Hide()
end

function StzxUI:ToggleMoveMode()
	if self.moveMode then self:ExitMoveMode() else self:EnterMoveMode() end
end

-- Combat closes move mode at once.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
	if StzxUI.moveMode then
		StzxUI:ExitMoveMode()
		StzxUI:Say("move mode closed for combat.")
	end
end)

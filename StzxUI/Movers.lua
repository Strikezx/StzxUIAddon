-- StzxUI Movers
-- How a frame becomes movable. Every movable StzxUI frame is pinned to an
-- invisible "holder". The holder is what gets dragged in move mode and what
-- the profile remembers; the real frame just follows it. This keeps our own
-- drag-and-drop away from the real frames (important for secure unit frames
-- and action bars, which can't be touched in combat).
--
--   StzxUI:RegisterMover("InfoStats", frame, {
--       label = "Info: stats",                        -- shown in move mode
--       category = "Info",                            -- move-mode filter group
--       default = { "TOPRIGHT", "TOPRIGHT", -16, -16 }, -- point, UIParent point, x, y
--       width = 160, height = 20,                     -- optional, else the frame's size
--       isShown = function() return db.showStats end, -- optional: hide its box in move mode
--       scalable = false,                             -- optional: no mouse-wheel resizing
--   })
--
-- Saved per profile:
--   positions[key] = { x = , y = }  the holder's top-left corner from the screen centre
--   scales[key]    = 1.2            the frame's size (mouse wheel in move mode)

local StzxUI = _G.StzxUI

StzxUI.movers = {}     -- [key] = holder
StzxUI.moverOrder = {} -- keys, in registration order

local MIN_SCALE, MAX_SCALE = 0.5, 2
local SNAP_DISTANCE = 10 -- how close (UI units) an edge must be to snap to another frame

local waitingForCombat = {} -- holders to re-place once combat ends
local events = CreateFrame("Frame")

local function Round(value)
	return math.floor(value + 0.5)
end

local function ScaleOf(holder)
	local scale = tonumber(StzxUI.profile.scales[holder.key])
	if not scale or not holder.scalable then return 1 end
	return math.min(MAX_SCALE, math.max(MIN_SCALE, scale))
end

-- Put a holder where the profile says (or its default spot), at its saved size.
local function Place(holder)
	if InCombatLockdown() then
		waitingForCombat[holder] = true
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	local scale = ScaleOf(holder)
	holder.target:SetScale(scale)
	holder:SetSize(holder.baseWidth * scale, holder.baseHeight * scale)

	holder:ClearAllPoints()
	local saved = StzxUI.profile.positions[holder.key]
	if type(saved) == "table" and tonumber(saved.x) and tonumber(saved.y) then
		holder:SetPoint("TOPLEFT", UIParent, "CENTER", saved.x, saved.y)
	else
		local d = holder.default
		holder:SetPoint(d[1], UIParent, d[2] or d[1], d[3] or 0, d[4] or 0)
	end
end

events:SetScript("OnEvent", function()
	events:UnregisterEvent("PLAYER_REGEN_ENABLED")
	for holder in pairs(waitingForCombat) do
		waitingForCombat[holder] = nil
		Place(holder)
	end
end)

function StzxUI:RegisterMover(key, frame, opts)
	assert(type(key) == "string", "StzxUI:RegisterMover needs a key")
	assert(not self.movers[key], "StzxUI mover registered twice: " .. key)
	opts = opts or {}

	local holder = CreateFrame("Frame", "StzxUIMover_" .. key, UIParent)
	holder.key = key
	holder.label = opts.label or key
	holder.category = opts.category or "Other"
	holder.default = opts.default or { "CENTER", "CENTER", 0, 0 }
	holder.isShown = opts.isShown
	holder.scalable = opts.scalable ~= false
	holder.target = frame
	holder.baseWidth = opts.width or frame:GetWidth()
	holder.baseHeight = opts.height or frame:GetHeight()
	holder:SetClampedToScreen(true)
	holder:SetMovable(true)
	if holder.SetDontSavePosition then holder:SetDontSavePosition(true) end
	Place(holder)

	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", holder, "TOPLEFT")

	self.movers[key] = holder
	table.insert(self.moverOrder, key)
	self:BuildMoverOverlay(holder) -- MoveMode.lua
	return holder
end

-- When a frame's normal size changes (e.g. a setting), keep its holder matching.
function StzxUI:SetMoverSize(key, width, height)
	local holder = self.movers[key]
	if not holder then return end
	holder.baseWidth, holder.baseHeight = width, height
	Place(holder)
end

-- Where is the holder now, as the profile stores it?
local function CurrentOffset(holder)
	local left, top = holder:GetLeft(), holder:GetTop()
	local centerX, centerY = UIParent:GetCenter()
	if not (left and top and centerX and centerY) then return 0, 0 end
	-- The holder sits directly on UIParent at scale 1, so both use the same units.
	return left - centerX, top - centerY
end

-- Snap to other frames: if an edge or centre line of this frame is within
-- SNAP_DISTANCE of another visible frame's edge or centre line, line them up.
-- Returns the corrected left / top, or nil on an axis with nothing close.
-- A frame's edges in UIParent's units (Blizzard's frames can have their own
-- scale). nil when it isn't on screen.
local function Rect(frame)
	if not (frame and frame:IsVisible()) then return nil end
	local left, bottom, width, height = frame:GetRect()
	if not left then return nil end
	local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return left * s, (bottom + height) * s, (left + width) * s, bottom * s
end

-- Everything a frame can line up with: the other StzxUI boxes, plus the
-- Blizzard frames Edit Mode places (action bars, minimap, chat, ...).
local function SnapTargets(holder)
	local rects = {}
	for _, key in ipairs(StzxUI.moverOrder) do
		local other = StzxUI.movers[key]
		if other ~= holder and other.overlay:IsShown() then
			local l, t, r, b = Rect(other)
			if l then rects[#rects + 1] = { l, t, r, b } end
		end
	end
	local manager = _G.EditModeManagerFrame
	for _, system in ipairs(manager and manager.registeredSystemFrames or {}) do
		local l, t, r, b = Rect(system)
		if l then rects[#rects + 1] = { l, t, r, b } end
	end
	return rects
end

local function SnapToFrames(holder, left, top)
	local width, height = holder:GetWidth(), holder:GetHeight()
	local bestX, bestY, bestDX, bestDY
	for _, rect in ipairs(SnapTargets(holder)) do
		local oLeft, oTop, oRight, oBottom = rect[1], rect[2], rect[3], rect[4]
		local oMidX, oMidY = (oLeft + oRight) / 2, (oTop + oBottom) / 2
		-- Horizontal: our left, right or middle against theirs.
		for _, ours in ipairs({ 0, width, width / 2 }) do
			for _, theirs in ipairs({ oLeft, oRight, oMidX }) do
				local d = math.abs(left + ours - theirs)
				if d <= SNAP_DISTANCE and (not bestDX or d < bestDX) then
					bestDX, bestX = d, theirs - ours
				end
			end
		end
		-- Vertical: our top, bottom or middle against theirs.
		for _, ours in ipairs({ 0, height, height / 2 }) do
			for _, theirs in ipairs({ oTop, oBottom, oMidY }) do
				local d = math.abs(top - ours - theirs)
				if d <= SNAP_DISTANCE and (not bestDY or d < bestDY) then
					bestDY, bestY = d, theirs + ours
				end
			end
		end
	end
	return bestX, bestY
end

-- Store the holder's position. Unless `free` (Shift held): line up with other
-- frames where one is close, otherwise snap to the grid.
function StzxUI:SaveMoverPosition(holder, free)
	local core = self.db.core
	local x, y = CurrentOffset(holder)
	if free then
		x, y = Round(x), Round(y)
	else
		local snappedX, snappedY
		if core.snapToFrames then
			local centerX, centerY = UIParent:GetCenter()
			local frameX, frameY = SnapToFrames(holder, x + centerX, y + centerY)
			snappedX = frameX and Round(frameX - centerX)
			snappedY = frameY and Round(frameY - centerY)
		end
		-- With Edit Mode open and its grid showing, use its spacing so both line up.
		local grid = self:EditModeGridSize() or core.gridSize or 16
		local useGrid = core.snapToGrid and grid > 0
		x = snappedX or (useGrid and Round(x / grid) * grid or Round(x))
		y = snappedY or (useGrid and Round(y / grid) * grid or Round(y))
	end
	self.profile.positions[holder.key] = { x = x, y = y }
	Place(holder)
end

-- Move by a few units (arrow keys in move mode).
function StzxUI:NudgeMover(holder, dx, dy)
	local x, y = CurrentOffset(holder)
	self.profile.positions[holder.key] = { x = Round(x + dx), y = Round(y + dy) }
	Place(holder)
end

-- Grow or shrink (mouse wheel in move mode). Keeps the top-left corner still.
function StzxUI:ScaleMover(holder, step)
	if not holder.scalable then return end
	local scale = ScaleOf(holder) + step
	scale = math.min(MAX_SCALE, math.max(MIN_SCALE, math.floor(scale * 20 + 0.5) / 20))
	local x, y = CurrentOffset(holder)
	self.profile.positions[holder.key] = { x = Round(x), y = Round(y) }
	self.profile.scales[holder.key] = (scale ~= 1) and scale or nil
	Place(holder)
	return scale
end

function StzxUI:GetMoverScale(holder)
	return ScaleOf(holder)
end

-- Back to where it started, at normal size.
function StzxUI:ResetMover(key)
	local holder = self.movers[key]
	if not holder then return end
	self.profile.positions[key] = nil
	self.profile.scales[key] = nil
	Place(holder)
end

function StzxUI:ResetAllMovers()
	for _, key in ipairs(self.moverOrder) do
		self:ResetMover(key)
	end
end

-- Categories that have at least one mover, sorted (for the move-mode filter).
function StzxUI:GetMoverCategories()
	local seen, list = {}, {}
	for _, key in ipairs(self.moverOrder) do
		local category = self.movers[key].category
		if not seen[category] then
			seen[category] = true
			table.insert(list, category)
		end
	end
	table.sort(list)
	return list
end

-- StzxUI Movers
-- How a frame becomes movable. Every movable StzxUI frame is pinned to an
-- invisible "holder". The holder is what gets dragged in move mode and what
-- the profile remembers; the real frame just follows it. This keeps our own
-- drag-and-drop away from the real frames (important later for secure unit
-- frames and action bars, which can't be touched in combat).
--
--   StzxUI:RegisterMover("InfoStats", frame, {
--       label = "Info: FPS and latency",          -- shown in move mode
--       default = { "TOPRIGHT", "TOPRIGHT", -16, -16 }, -- point, UIParent point, x, y
--       width = 160, height = 20,                 -- optional, else the frame's size
--       isShown = function() return db.showStats end, -- optional: hide its box in move mode
--   })
--
-- Saved positions: profile.positions[key] = { x = , y = }, the holder's
-- top-left corner measured from the centre of the screen, in UI units.

local StzxUI = _G.StzxUI

StzxUI.movers = {}     -- [key] = holder
StzxUI.moverOrder = {} -- keys, in registration order

local waitingForCombat = {} -- holders to re-place once combat ends
local events = CreateFrame("Frame")

local function Round(value)
	return math.floor(value + 0.5)
end

-- Put a holder where the profile says, or at its default spot.
local function Place(holder)
	if InCombatLockdown() then
		waitingForCombat[holder] = true
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
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
	holder.default = opts.default or { "CENTER", "CENTER", 0, 0 }
	holder.isShown = opts.isShown
	holder.target = frame
	holder:SetSize(opts.width or frame:GetWidth(), opts.height or frame:GetHeight())
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

-- When a frame changes size (e.g. more text), keep its holder matching.
function StzxUI:SetMoverSize(key, width, height)
	local holder = self.movers[key]
	if holder and not InCombatLockdown() then holder:SetSize(width, height) end
end

-- Where is the holder now, as the profile stores it?
local function CurrentOffset(holder)
	local left, top = holder:GetLeft(), holder:GetTop()
	local centerX, centerY = UIParent:GetCenter()
	if not (left and top and centerX and centerY) then return 0, 0 end
	-- The holder sits directly on UIParent at scale 1, so both use the same units.
	return left - centerX, top - centerY
end

-- Store the holder's position, snapped to the grid unless `free` is true.
function StzxUI:SaveMoverPosition(holder, free)
	local x, y = CurrentOffset(holder)
	local grid = self.db.core.gridSize or 16
	if self.db.core.snapToGrid and not free and grid > 0 then
		x, y = Round(x / grid) * grid, Round(y / grid) * grid
	else
		x, y = Round(x), Round(y)
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

function StzxUI:ResetMover(key)
	local holder = self.movers[key]
	if not holder then return end
	self.profile.positions[key] = nil
	Place(holder)
end

function StzxUI:ResetAllMovers()
	for _, key in ipairs(self.moverOrder) do
		self:ResetMover(key)
	end
end

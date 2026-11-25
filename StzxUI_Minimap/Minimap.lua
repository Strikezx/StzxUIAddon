-- StzxUI Minimap: Blizzard's minimap in StzxUI's look
--
--   * square, with a 1-pixel border (black, or StzxUI's accent colour)
--   * the round frame art and compass ring hidden
--   * the + and - zoom buttons hidden (the mouse wheel already zooms: that's
--     Blizzard's own)
--
-- Edit Mode still places and sizes the minimap. StzxUI repaints right after
-- Blizzard's own minimap setup (which runs again when you turn on "rotate
-- minimap"), and tells minimap-button addons the map is square, so their
-- buttons move to the corners. For a clock and coordinates under the map,
-- place StzxUI's Info readouts there in move mode.

local ADDON_NAME = ...
local StzxUI = _G.StzxUI
local A = StzxUI.ACCENT

local MinimapModule = StzxUI:NewModule("Minimap", ADDON_NAME, {
	square = true,
	accentBorder = false, -- border in StzxUI's accent colour instead of black
	hideZoomButtons = true,
}, {
	title = "Minimap",
	description = "A square minimap with a thin border and less clutter. Edit Mode still places it.",
})

local border

local function Paint()
	local db = MinimapModule.db
	local map = _G.Minimap
	if not map then return end
	if db.square then
		map:SetMaskTexture("Interface\\Buttons\\WHITE8x8")
		if MinimapCompassTexture then MinimapCompassTexture:SetAlpha(0) end
		if MinimapCompassTextureUnderlay then MinimapCompassTextureUnderlay:SetAlpha(0) end
		if border then
			local c = db.accentBorder and A or { r = 0, g = 0, b = 0 }
			for _, edge in ipairs(border.edges) do edge:SetColorTexture(c.r, c.g, c.b, 1) end
			border:Show()
		end
	elseif border then
		border:Hide()
	end
	local hide = db.hideZoomButtons
	for _, key in ipairs({ "ZoomIn", "ZoomOut" }) do
		local button = map[key]
		if button then
			button:SetAlpha(hide and 0 or 1)
			button:EnableMouse(not hide)
		end
	end
end
MinimapModule.Paint = Paint

-- Minimap-button addons ask this to know where buttons can go.
local function SquareShape()
	if MinimapModule.db.square then return "SQUARE" end
	return "ROUND"
end

function MinimapModule:OnInitialize()
	local page = StzxUI:AddSettingsPage("Minimap")
	StzxUI:AddHeader(page, "Look", "Place and size the minimap in Edit Mode.")
	StzxUI:AddCheckbox(page, self, "square", "Square minimap",
		"Switching back to round needs a reload.", function(on)
			if on then Paint() else StzxUI:AskReload("The round minimap comes back after a reload.") end
		end)
	StzxUI:AddCheckbox(page, self, "accentBorder", "Border in StzxUI's accent colour", "Black otherwise.", Paint)
	StzxUI:AddCheckbox(page, self, "hideZoomButtons", "Hide the + and - buttons",
		"The mouse wheel zooms the minimap anyway.", Paint)
end

function MinimapModule:OnEnable()
	local map = _G.Minimap
	if not map then return end
	border = CreateFrame("Frame", nil, map)
	border:SetAllPoints()
	border:SetFrameLevel(map:GetFrameLevel() + 5)
	border.edges = {}
	for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
		local line = border:CreateTexture(nil, "OVERLAY")
		line:SetPoint(edge[1])
		line:SetPoint(edge[2])
		if edge[3] then line:SetHeight(1) else line:SetWidth(1) end
		border.edges[#border.edges + 1] = line
	end
	_G.GetMinimapShape = SquareShape
	if MinimapCluster and MinimapCluster.UpdateMinimapConfig then
		hooksecurefunc(MinimapCluster, "UpdateMinimapConfig", Paint)
	end
	Paint()
end

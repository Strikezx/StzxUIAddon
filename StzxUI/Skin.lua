-- StzxUI core: Skin
-- StzxUI's look for frames StzxUI didn't make: Blizzard's windows (the
-- Skins section), the tooltip, and later other addons' windows.
--
-- The look: a dark fill, a 1-pixel edge in the skin colour (StzxUI's
-- accent, your class colour, or black), a darker title strip with an accent
-- line under it, flat tabs and buttons, a flat close button and slim
-- scrollbars.
--
-- How it stays safe:
--   * only looks change: Blizzard's art is made invisible (alpha 0) and
--     StzxUI's own textures are added underneath. No secure attributes, no
--     anchors of Blizzard's frames, no scripts replaced (only hooked).
--   * nothing is written onto Blizzard's frames: StzxUI keeps its own notes
--     in tables keyed by frame, so Blizzard's code never reads anything of ours.
--   * callers skin out of combat (the Skins section waits for combat to end).
--
-- StzxUI.Skin.Window(frame)          a whole window: frame art, title, close button, inset, tabs, and
--                                    (unless controls == false) the buttons and scrollbars inside it
-- StzxUI.Skin.Backdrop(frame, opts)  fill + edge on any frame; returns the backdrop
-- StzxUI.Skin.Button / CloseButton / Tab / ScrollBar / Inset (frame)
-- StzxUI.Skin.SetColourMode("ACCENT" | "CLASS" | "BLACK"); StzxUI.Skin.SetOpacity(0.5 .. 1)

local StzxUI = _G.StzxUI

local Skin = {}
StzxUI.Skin = Skin

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FILL = { 0.06, 0.065, 0.075 }
local TITLE = { 0.03, 0.03, 0.035 }
local SOFT_EDGE = { 0.22, 0.22, 0.25 } -- buttons, tabs, insets: a quieter edge

local skinned = setmetatable({}, { __mode = "k" })  -- frame -> what it was skinned as
local edges = setmetatable({}, { __mode = "k" })    -- texture -> "accent" | "soft"
local fills = setmetatable({}, { __mode = "k" })    -- texture -> its base alpha (scaled by opacity)
local tabs = setmetatable({}, { __mode = "k" })     -- tab -> its StzxUI parts
local mode, opacity = "ACCENT", 0.92

---------------------------------------------------------------------------
-- Colours
---------------------------------------------------------------------------

function Skin.EdgeColour()
	if mode == "BLACK" then return 0, 0, 0 end
	if mode == "CLASS" then
		local _, class = UnitClass("player")
		local c = class and C_ClassColor and C_ClassColor.GetClassColor(class)
		if c then return c.r, c.g, c.b end
	end
	local A = StzxUI.ACCENT
	return A.r, A.g, A.b
end

local function PaintEdge(texture)
	if edges[texture] == "soft" then
		texture:SetColorTexture(SOFT_EDGE[1], SOFT_EDGE[2], SOFT_EDGE[3], 1)
	else
		local r, g, b = Skin.EdgeColour()
		texture:SetColorTexture(r, g, b, 1)
	end
end

local function PaintFill(texture)
	local f = fills[texture]
	texture:SetColorTexture(f.r, f.g, f.b, f.a * opacity)
end

-- Re-colour everything StzxUI has skinned (after a settings change).
function Skin.Refresh()
	for texture in pairs(edges) do PaintEdge(texture) end
	for texture in pairs(fills) do PaintFill(texture) end
	for tab in pairs(tabs) do Skin.PaintTab(tab) end
end

-- One backdrop's edge in a colour of its own (e.g. a tooltip in its item's
-- quality colour), and back to the skin colour.
function Skin.SetEdgeColour(backdrop, r, g, b)
	for _, line in ipairs(backdrop.edges) do line:SetColorTexture(r, g, b, 1) end
end
function Skin.ResetEdges(backdrop)
	for _, line in ipairs(backdrop.edges) do PaintEdge(line) end
end

function Skin.SetColourMode(newMode) mode = newMode or "ACCENT"; Skin.Refresh() end
function Skin.SetOpacity(value) opacity = math.max(0.3, math.min(1, value or 0.92)); Skin.Refresh() end
function Skin.IsSkinned(frame) return skinned[frame] ~= nil end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------

local function Hide(region)
	if region and region.SetAlpha then region:SetAlpha(0) end
end

local function Fill(frame, layer, sub, colour, alpha)
	local texture = frame:CreateTexture(nil, layer, nil, sub)
	fills[texture] = { r = colour[1], g = colour[2], b = colour[3], a = alpha }
	PaintFill(texture)
	return texture
end

-- Four 1-pixel lines round `frame`'s edge, drawn on `host`.
local function Edges(host, frame, kind)
	local list = {}
	for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
		local line = host:CreateTexture(nil, "BORDER", nil, 7)
		line:SetPoint(e[1], frame, e[1])
		line:SetPoint(e[2], frame, e[2])
		if e[3] then line:SetHeight(1) else line:SetWidth(1) end
		edges[line] = kind or "accent"
		PaintEdge(line)
		list[#list + 1] = line
	end
	return list
end

-- A dark fill with a 1-pixel edge, drawn underneath `frame`'s own content.
-- opts: { edge = "accent" | "soft", fill = {r,g,b}, alpha = 0.92 }
function Skin.Backdrop(frame, opts)
	opts = opts or {}
	local fill = Fill(frame, "BACKGROUND", -8, opts.fill or FILL, opts.alpha or 1)
	fill:SetAllPoints(frame)
	return { fill = fill, edges = Edges(frame, frame, opts.edge) }
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

local function HoverEdges(frame, list)
	frame:HookScript("OnEnter", function()
		local r, g, b = Skin.EdgeColour()
		for _, line in ipairs(list) do line:SetColorTexture(r, g, b, 1) end
	end)
	frame:HookScript("OnLeave", function()
		for _, line in ipairs(list) do PaintEdge(line) end
	end)
end

-- Blizzard's red panel button (Left / Middle / Right pieces): flat instead.
function Skin.Button(button)
	if not button or skinned[button] then return end
	skinned[button] = "button"
	for _, key in ipairs({ "Left", "Middle", "Right", "LeftSeparator", "RightSeparator" }) do Hide(button[key]) end
	if button.GetNormalTexture then Hide(button:GetNormalTexture()) end
	if button.GetPushedTexture then Hide(button:GetPushedTexture()) end
	if button.GetDisabledTexture then Hide(button:GetDisabledTexture()) end
	if button.GetHighlightTexture then Hide(button:GetHighlightTexture()) end
	local back = Skin.Backdrop(button, { edge = "soft", fill = { 0.12, 0.125, 0.14 } })
	HoverEdges(button, back.edges)
end

-- The red X in a window's corner: a flat square with an x.
function Skin.CloseButton(button)
	if not button or skinned[button] then return end
	skinned[button] = "close"
	if button.GetNormalTexture then Hide(button:GetNormalTexture()) end
	if button.GetPushedTexture then Hide(button:GetPushedTexture()) end
	if button.GetDisabledTexture then Hide(button:GetDisabledTexture()) end
	if button.GetHighlightTexture then Hide(button:GetHighlightTexture()) end
	-- Its own box, a little inside the button's (Blizzard's is 24 px with padding).
	local box = CreateFrame("Frame", nil, button)
	box:SetPoint("TOPLEFT", 4, -4)
	box:SetPoint("BOTTOMRIGHT", -4, 4)
	box:EnableMouse(false)
	local back = Skin.Backdrop(box, { edge = "soft", fill = { 0.10, 0.10, 0.11 } })
	local x = box:CreateFontString(nil, "OVERLAY")
	x:SetFont(FONT, 12, "")
	x:SetPoint("CENTER", 0, 1)
	x:SetText("x")
	x:SetTextColor(0.8, 0.8, 0.8)
	button:HookScript("OnEnter", function()
		local r, g, b = Skin.EdgeColour()
		x:SetTextColor(r, g, b)
		for _, line in ipairs(back.edges) do line:SetColorTexture(r, g, b, 1) end
	end)
	button:HookScript("OnLeave", function()
		x:SetTextColor(0.8, 0.8, 0.8)
		for _, line in ipairs(back.edges) do PaintEdge(line) end
	end)
end

-- A window tab: flat, with an accent line along the top of the chosen one.
local function TabSelected(tab)
	if tab.LeftActive then return tab.LeftActive:IsShown() end
	if tab.IsEnabled then return not tab:IsEnabled() end -- old tabs: the chosen one is disabled
	return false
end

function Skin.PaintTab(tab)
	local parts = tabs[tab]
	if not parts then return end
	local selected = TabSelected(tab)
	parts.top:SetShown(selected)
	local f = fills[parts.back.fill]
	if selected then f.r, f.g, f.b = 0.14, 0.145, 0.165 else f.r, f.g, f.b = 0.07, 0.075, 0.085 end
	PaintFill(parts.back.fill)
	local text = tab.Text or (tab.GetFontString and tab:GetFontString())
	if text then
		if selected then text:SetTextColor(1, 1, 1) else text:SetTextColor(0.65, 0.65, 0.68) end
	end
end

local tabHooked = false
local function HookTabs()
	if tabHooked then return end
	tabHooked = true
	if PanelTemplates_SelectTab then hooksecurefunc("PanelTemplates_SelectTab", Skin.PaintTab) end
	if PanelTemplates_DeselectTab then hooksecurefunc("PanelTemplates_DeselectTab", Skin.PaintTab) end
end

function Skin.Tab(tab)
	if not tab or skinned[tab] then return end
	skinned[tab] = "tab"
	HookTabs()
	for _, texture in ipairs(tab.TabTextures or {}) do Hide(texture) end
	for _, key in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
		"LeftHighlight", "MiddleHighlight", "RightHighlight", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
		Hide(tab[key])
	end
	if tab.GetHighlightTexture then Hide(tab:GetHighlightTexture()) end
	-- Inset a little so neighbouring tabs don't touch.
	local box = CreateFrame("Frame", nil, tab)
	box:SetPoint("TOPLEFT", 3, -3)
	box:SetPoint("BOTTOMRIGHT", -3, 3)
	box:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
	box:EnableMouse(false)
	local back = Skin.Backdrop(box, { edge = "soft", fill = { 0.07, 0.075, 0.085 } })
	local top = box:CreateTexture(nil, "OVERLAY")
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(2)
	edges[top] = "accent"
	PaintEdge(top)
	tabs[tab] = { back = back, top = top }
	Skin.PaintTab(tab)
end

-- Modern scrollbars (Track and Thumb, each with Begin / Middle / End pieces).
function Skin.ScrollBar(bar)
	if not bar or skinned[bar] or not (bar.Track or bar.Thumb) then return end
	skinned[bar] = "scrollbar"
	local track = bar.Track
	if track then
		for _, key in ipairs({ "Begin", "Middle", "End" }) do Hide(track[key]) end
		local line = Fill(track, "BACKGROUND", -8, { 0, 0, 0 }, 0.5)
		line:SetPoint("TOP")
		line:SetPoint("BOTTOM")
		line:SetWidth(4)
	end
	local thumb = (track and track.Thumb) or bar.Thumb
	if thumb then
		for _, key in ipairs({ "Begin", "Middle", "End" }) do Hide(thumb[key]) end
		local knob = thumb:CreateTexture(nil, "ARTWORK")
		knob:SetPoint("TOP", 0, -1)
		knob:SetPoint("BOTTOM", 0, 1)
		knob:SetWidth(4)
		edges[knob] = "accent"
		PaintEdge(knob)
	end
end

-- A window's inner panel (InsetFrameTemplate): a slightly darker well.
function Skin.Inset(inset)
	if not inset or skinned[inset] then return end
	skinned[inset] = "inset"
	Hide(inset.NineSlice)
	Hide(inset.Bg)
	Skin.Backdrop(inset, { edge = "soft", fill = { 0, 0, 0 }, alpha = 0.35 })
end

---------------------------------------------------------------------------
-- Whole windows
---------------------------------------------------------------------------

-- The window's own decorative textures (old-style windows draw their frame
-- art straight onto the window, in its background and border layers).
local function HideOwnArt(frame, keep)
	for _, region in ipairs({ frame:GetRegions() }) do
		if not keep[region] and region.GetObjectType and region:GetObjectType() == "Texture" then
			local layer = region.GetDrawLayer and region:GetDrawLayer()
			if layer == "BACKGROUND" or layer == "BORDER" then Hide(region) end
		end
	end
end

-- Buttons and scrollbars inside a window (a few levels down).
local function IsPanelButton(child)
	return child.GetObjectType and child:GetObjectType() == "Button" and child.Left and child.Right and child.Middle
end

function Skin.Controls(frame, depth)
	depth = depth or 4
	if depth <= 0 or not frame.GetChildren then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		if not skinned[child] and not (child.IsForbidden and child:IsForbidden()) then
			if IsPanelButton(child) then
				Skin.Button(child)
			elseif child.Track and (child.Track.Thumb or child.Thumb) then
				Skin.ScrollBar(child)
			elseif child.layoutType == "InsetFrameTemplate" then
				Skin.Inset(child)
				Skin.Controls(child, depth - 1)
			else
				Skin.Controls(child, depth - 1)
			end
		end
	end
end

-- opts: { controls = true }
function Skin.Window(frame, opts)
	if not frame or skinned[frame] then return false end
	opts = opts or {}
	skinned[frame] = "window"
	-- Blizzard's frame art.
	Hide(frame.NineSlice)
	Hide(frame.Border)
	Hide(frame.Bg)
	Hide(frame.TopTileStreaks)
	Hide(frame.PortraitContainer)
	Hide(frame.portrait)
	if frame.GetName and frame:GetName() then
		Hide(_G[frame:GetName() .. "Portrait"])
		Hide(_G[frame:GetName() .. "Bg"])
	end
	local back = Skin.Backdrop(frame, { alpha = 1 })
	local keep = { [back.fill] = true }
	for _, line in ipairs(back.edges) do keep[line] = true end
	HideOwnArt(frame, keep)
	-- A darker title strip with an accent line under it.
	local title = Fill(frame, "BACKGROUND", -7, TITLE, 1)
	title:SetPoint("TOPLEFT", 1, -1)
	title:SetPoint("TOPRIGHT", -1, -1)
	title:SetHeight(22)
	local line = frame:CreateTexture(nil, "BORDER", nil, 6)
	line:SetPoint("TOPLEFT", title, "BOTTOMLEFT")
	line:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT")
	line:SetHeight(1)
	edges[line] = "accent"
	PaintEdge(line)
	local titleText = (frame.TitleContainer and frame.TitleContainer.TitleText) or frame.TitleText
		or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "TitleText"])
	if titleText and titleText.SetTextColor then titleText:SetTextColor(1, 1, 1) end

	Skin.CloseButton(frame.CloseButton or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "CloseButton"]))
	if frame.Inset then Skin.Inset(frame.Inset) end
	for _, tab in ipairs(frame.Tabs or {}) do Skin.Tab(tab) end
	-- Old-style tabs are named <Window>Tab1, Tab2...
	local name = frame.GetName and frame:GetName()
	if name then
		for i = 1, 12 do
			local tab = _G[name .. "Tab" .. i]
			if not tab then break end
			Skin.Tab(tab)
		end
	end
	if opts.controls ~= false then
		Skin.Controls(frame)
		-- Some windows make their buttons only when first opened (the game
		-- menu does): look again each time it opens, out of combat.
		frame:HookScript("OnShow", function(shown)
			if not InCombatLockdown() then Skin.Controls(shown) end
		end)
	end
	return true
end

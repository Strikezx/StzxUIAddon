-- StzxUI core: Skin
-- StzxUI's look for frames StzxUI didn't make: Blizzard's windows (the
-- Skins section), the tooltip, and later other addons' windows.
--
-- The look: a near-black fill, a 1-pixel edge in the skin colour (StzxUI's
-- accent, your class colour, or black) drawn above everything in the window,
-- a darker title strip with an accent line under it, flat tabs and buttons,
-- a flat close button and slim scrollbars. With the "full" level, everything
-- inside a window too: panels get black backgrounds with softer accent
-- edges, bars go flat, checkboxes become flat boxes, list rows lose their
-- art. Anything with an icon (items, spells, talents) and anything
-- protected is never touched.
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
local FLAT = "Interface\\Buttons\\WHITE8x8"
local FILL = { 0.025, 0.028, 0.035 }
local TITLE = { 0, 0, 0 }
local SOFT_ALPHA = 0.45 -- buttons, tabs, panels: the skin colour, quieter

local skinned = setmetatable({}, { __mode = "k" })  -- frame -> what it was skinned as
local edges = setmetatable({}, { __mode = "k" })    -- texture -> "accent" | "soft"
local fills = setmetatable({}, { __mode = "k" })    -- texture -> its base alpha (scaled by opacity)
local tabs = setmetatable({}, { __mode = "k" })     -- tab -> its StzxUI parts
local sideTabs = setmetatable({}, { __mode = "k" }) -- side tab -> its backdrop
local PaintSideTab -- defined with the side tabs, below
local mode, opacity = "ACCENT", 0.92
local level = "FULL" -- FULL: everything inside windows too; FRAMES: window frames, tabs, buttons only

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
	local r, g, b = Skin.EdgeColour()
	if edges[texture] == "soft" then
		if mode == "BLACK" then r, g, b = 0.22, 0.22, 0.25 end -- black on black wouldn't show
		texture:SetColorTexture(r, g, b, SOFT_ALPHA)
	else
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
	for tab in pairs(sideTabs) do PaintSideTab(tab) end
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
function Skin.SetLevel(newLevel) level = newLevel or "FULL" end
function Skin.SetOpacity(value) opacity = math.max(0.3, math.min(1, value or 0.92)); Skin.Refresh() end
function Skin.IsSkinned(frame) return skinned[frame] ~= nil end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------

-- A frame of StzxUI's own inside someone else's (marked, so the deep pass
-- never strips it).
local function OwnFrame(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:EnableMouse(false)
	skinned[f] = "stzxui"
	return f
end

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
	local back = Skin.Backdrop(button, { edge = "soft", fill = { 0.05, 0.055, 0.07 } })
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
	local box = OwnFrame(button)
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
	if selected then f.r, f.g, f.b = 0.08, 0.09, 0.11 else f.r, f.g, f.b = 0.02, 0.022, 0.028 end
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
	local box = OwnFrame(tab)
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

-- Side tabs (LargeSideTabButtonTemplate: the round icon tabs down the side of
-- the Character window): a square, cropped icon in a black box; the chosen
-- one edged in the full skin colour. Re-painted after Blizzard's SetChecked.
function PaintSideTab(tab)
	local back = sideTabs[tab]
	if not back then return end
	local chosen = tab.SelectedTexture and tab.SelectedTexture:IsShown()
	for _, line in ipairs(back.edges) do
		if chosen then
			local r, g, b = Skin.EdgeColour()
			line:SetColorTexture(r, g, b, 1)
		else
			PaintEdge(line)
		end
	end
end

function Skin.SideTab(tab)
	if not tab or skinned[tab] then return end
	skinned[tab] = "sidetab"
	Hide(tab.Background)
	Hide(tab.SelectedTexture)
	local icon = tab.Icon
	if icon then
		if tab.Mask and icon.RemoveMaskTexture then icon:RemoveMaskTexture(tab.Mask) end
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	local box = OwnFrame(tab)
	if icon then
		box:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
		box:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
	else
		box:SetAllPoints()
	end
	box:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
	sideTabs[tab] = Skin.Backdrop(box, { edge = "soft", fill = { 0, 0, 0 }, alpha = 0.85 })
	if tab.SetChecked then hooksecurefunc(tab, "SetChecked", PaintSideTab) end
	PaintSideTab(tab)
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

-- Inside a window ------------------------------------------------------

local function IsPanelButton(child)
	return child.GetObjectType and child:GetObjectType() == "Button" and child.Left and child.Right and child.Middle
end

-- Never restyled: anything showing an icon (item slots, spells, talents,
-- action buttons) and anything protected (it may cast or use something).
local function Untouchable(f)
	if (f.IsForbidden and f:IsForbidden()) or (f.IsProtected and f:IsProtected()) then return true end
	return f.icon ~= nil or f.Icon ~= nil or f.IconTexture ~= nil or f.IconBorder ~= nil
		or f.GetItemButtonIconTexture ~= nil
end

-- A bar (reputation, skill...): flat, on black, with a thin edge. Keeps
-- Blizzard's colour.
function Skin.StatusBar(bar)
	if skinned[bar] then return end
	skinned[bar] = "bar"
	local texture = bar:GetStatusBarTexture()
	for _, region in ipairs({ bar:GetRegions() }) do
		if region ~= texture and region:GetObjectType() == "Texture" then Hide(region) end
	end
	for _, key in ipairs({ "LeftTexture", "RightTexture", "MiddleTexture", "BarBG", "Background", "Border" }) do
		Hide(bar[key])
	end
	local r, g, b, a = bar:GetStatusBarColor()
	bar:SetStatusBarTexture(FLAT)
	if r then bar:SetStatusBarColor(r, g, b, a) end
	Skin.Backdrop(bar, { edge = "soft", fill = { 0, 0, 0 }, alpha = 0.7 })
end

-- A checkbox: a flat box with a square of the skin colour when ticked.
function Skin.CheckBox(box)
	if skinned[box] then return end
	skinned[box] = "checkbox"
	Hide(box:GetNormalTexture())
	Hide(box:GetPushedTexture())
	Hide(box:GetHighlightTexture())
	Hide(box:GetDisabledTexture())
	local size = math.max(10, math.min(16, math.floor(math.min(box:GetWidth(), box:GetHeight()) * 0.5)))
	local square = OwnFrame(box)
	square:SetSize(size, size)
	square:SetPoint("CENTER")
	square:EnableMouse(false)
	local back = Skin.Backdrop(square, { edge = "soft", fill = { 0, 0, 0 }, alpha = 0.8 })
	HoverEdges(box, back.edges)
	box:SetCheckedTexture(FLAT)
	local tick = box:GetCheckedTexture()
	if tick then
		tick:ClearAllPoints()
		tick:SetPoint("TOPLEFT", square, "TOPLEFT", 3, -3)
		tick:SetPoint("BOTTOMRIGHT", square, "BOTTOMRIGHT", -3, 3)
		edges[tick] = "accent" -- coloured with the edges
		PaintEdge(tick)
	end
	if box.GetDisabledCheckedTexture and box:GetDisabledCheckedTexture() then
		local grey = box:GetDisabledCheckedTexture()
		grey:SetTexture(FLAT)
		grey:SetVertexColor(0.4, 0.4, 0.4)
		grey:ClearAllPoints()
		grey:SetPoint("TOPLEFT", square, "TOPLEFT", 3, -3)
		grey:SetPoint("BOTTOMRIGHT", square, "BOTTOMRIGHT", -3, 3)
	end
end

-- Scrollbar arrows: Blizzard's gold arrows toned to grey.
local function GreyArrows(bar)
	for _, key in ipairs({ "Back", "Forward", "ScrollUpButton", "ScrollDownButton" }) do
		local button = bar[key]
		if button and button.GetRegions then
			for _, region in ipairs({ button:GetRegions() }) do
				if region:GetObjectType() == "Texture" and region.SetDesaturated then
					region:SetDesaturated(true)
					region:SetVertexColor(0.75, 0.75, 0.78)
				end
			end
		end
	end
end

-- A panel's own frame art: Blizzard's usual names, and (old-style panels)
-- textures drawn straight onto it in its background and border layers.
-- Returns true if it had any.
local PANEL_PARTS = { "NineSlice", "Border", "Bg", "Background", "TopTileStreaks", "BackgroundTexture" }
local function StripPanel(f)
	local had = false
	for _, key in ipairs(PANEL_PARTS) do
		local part = f[key]
		if type(part) == "table" and part.SetAlpha and part ~= f then
			Hide(part)
			had = true
		end
	end
	for _, region in ipairs({ f:GetRegions() }) do
		if region:GetObjectType() == "Texture" then
			local layer = region:GetDrawLayer()
			if layer == "BACKGROUND" or layer == "BORDER" then
				Hide(region)
				had = true
			end
		end
	end
	return had
end

-- Everything inside a window, `depth` levels down. FRAMES level: only panel
-- buttons, scrollbars and insets; FULL: panels, bars, checkboxes, rows too.
function Skin.Controls(frame, depth)
	depth = depth or (level == "FULL" and 8 or 4)
	if depth <= 0 or not frame.GetChildren then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		if not skinned[child] and not Untouchable(child) then
			local kind = child:GetObjectType()
			if IsPanelButton(child) then
				Skin.Button(child)
			elseif child.Track and (child.Track.Thumb or child.Thumb) then
				Skin.ScrollBar(child)
				GreyArrows(child)
			elseif child.layoutType == "InsetFrameTemplate" then
				Skin.Inset(child)
				Skin.Controls(child, depth - 1)
			elseif level ~= "FULL" then
				Skin.Controls(child, depth - 1)
			elseif kind == "StatusBar" then
				Skin.StatusBar(child)
			elseif kind == "CheckButton" then
				Skin.CheckBox(child)
			elseif kind == "Slider" or kind == "EditBox" or kind == "ScrollFrame" or kind == "Model"
				or kind == "PlayerModel" or kind == "ModelScene" then
				-- Leave these as they are (sliders and text boxes have their own
				-- art that shows how to use them); look inside scroll frames.
				if kind == "ScrollFrame" then Skin.Controls(child, depth - 1) end
			else
				if child.ScrollUpButton or child.ScrollDownButton then GreyArrows(child) end
				local had = StripPanel(child)
				-- Panels (not small things like rows) get a black background and an edge.
				if had and kind == "Frame" and child:GetWidth() >= 60 and child:GetHeight() >= 40 then
					skinned[child] = "panel"
					Skin.Backdrop(child, { edge = "soft", fill = { 0, 0, 0 }, alpha = 0.45 })
				end
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
	-- The background on the window itself; its edge on a layer above
	-- everything inside, so panels can't cover it.
	local fill = Fill(frame, "BACKGROUND", -8, FILL, 1)
	fill:SetAllPoints(frame)
	HideOwnArt(frame, { [fill] = true })
	local overlay = OwnFrame(frame)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(frame:GetFrameLevel() + 40)
	overlay:EnableMouse(false)
	Edges(overlay, frame)
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
	for _, tab in ipairs(frame.Tabs or {}) do
		if tab.SelectedTexture and tab.Icon then Skin.SideTab(tab) else Skin.Tab(tab) end
	end
	-- The Character window's side tabs (Forever: CharacterFrame.ModeTabs).
	for _, tab in ipairs(frame.ModeTabs and frame.ModeTabs.Tabs or {}) do Skin.SideTab(tab) end
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

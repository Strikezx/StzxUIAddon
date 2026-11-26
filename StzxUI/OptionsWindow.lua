-- StzxUI's own options window (/stzx)
--
--   +--------------------------------------------------------------+
--   | StzxUI                                              v...  [x] |
--   | [search.......] |  Unit Frames                                |
--   |  General        |  Player                                     |
--   |  Sections       |  [x] Show the player frame                  |
--   | - Frames        |  Portrait ............. [ Class icon v ]    |
--   |    Unit Frames <|  Buff and debuff size  [-----o----] 24 px   |
--   |    ...          |  ...                                        |
--   | + Look          |                                             |
--   | + Gameplay      |                                             |
--   | + PvP           |                                             |
--   | + History       |                                             |
--   |  Profiles       |                                             |
--   | [Move] [Test]   |                                             |
--   +--------------------------------------------------------------+
--
-- The sections' pages sit in folders (FOLDERS below); one folder is open at
-- a time, and the folder of the page you're on opens by itself.
--
-- It draws itself from StzxUI.optionPages (filled in by the Settings.lua
-- helpers) and writes through the very same settings as Blizzard's panel,
-- so both always agree and run the same reload prompts.

local StzxUI = _G.StzxUI
local A = StzxUI.ACCENT

local WIDTH, HEIGHT = 780, 560
local SIDEBAR = 180
local ROW = 30
local CONTROL_X = 300 -- where controls start inside the page

local window
local current -- the page entry shown, or nil while searching
local openFolder -- the sidebar folder that's open
local pools = {}

---------------------------------------------------------------------------
-- Pages in sidebar order: General, Sections, the modules, Profiles
---------------------------------------------------------------------------

-- Sidebar folders, in order, and the pages in each (by page title). A page
-- no folder names goes in "More" (shown only when something is in it).
local FOLDERS = {
	{ name = "Frames", pages = { "Unit Frames", "Party & Raid", "Nameplates", "Action Bars", "Minimap", "Blizzard Frames" } },
	{ name = "Look", pages = { "Skins", "Tooltip", "Info" } },
	{ name = "Gameplay", pages = { "Quests", "Helpers", "Combat", "Reminders", "Rare Alerts", "Social" } },
	{ name = "PvP", pages = { "World PvP", "Battlegrounds" } },
	{ name = "History", pages = { "Runs", "Fishing", "Inventory" } },
}
local OTHER = "More"
StzxUI.OPTION_FOLDERS = FOLDERS

-- Which folder a page sits in (nil for General, Sections and Profiles).
function StzxUI:OptionFolderOf(title)
	if title == "General" or title == "Sections" or title == "Profiles" then return nil end
	for _, folder in ipairs(FOLDERS) do
		for _, page in ipairs(folder.pages) do
			if page == title then return folder.name end
		end
	end
	return OTHER
end

function StzxUI:OptionPagesInOrder()
	local first, middle, last = {}, {}, {}
	for _, entry in ipairs(self.optionPages) do
		if entry.title == "General" or entry.title == "Sections" then
			first[#first + 1] = entry
		elseif entry.title == "Profiles" then
			last[#last + 1] = entry
		elseif #entry.items > 0 then
			middle[#middle + 1] = entry
		end
	end
	table.sort(first, function(a, b) return a.title == "General" and b.title ~= "General" end)
	local list = {}
	for _, group in ipairs({ first, middle, last }) do
		for _, entry in ipairs(group) do list[#list + 1] = entry end
	end
	return list
end

-- Every option whose label or tooltip has the words in it.
function StzxUI:SearchOptions(text)
	text = (text or ""):lower():match("^%s*(.-)%s*$")
	local found = {}
	if text == "" then return found end
	for _, entry in ipairs(self:OptionPagesInOrder()) do
		for _, item in ipairs(entry.items) do
			if item.kind ~= "header" then
				local haystack = ((item.label or "") .. " " .. (item.tooltip or "")):lower()
				if haystack:find(text, 1, true) then found[#found + 1] = { page = entry, item = item } end
			end
		end
	end
	return found
end

---------------------------------------------------------------------------
-- Controls (pooled: pages reuse them)
---------------------------------------------------------------------------

local function Acquire(kind, make)
	pools[kind] = pools[kind] or { list = {}, used = 0 }
	local pool = pools[kind]
	pool.used = pool.used + 1
	local widget = pool.list[pool.used]
	if not widget then
		widget = make()
		pool.list[pool.used] = widget
	end
	widget:Show()
	return widget
end

local function ReleaseAll()
	for _, pool in pairs(pools) do
		for _, widget in ipairs(pool.list) do widget:Hide() end
		pool.used = 0
	end
end

local function ShowTip(owner, title, text)
	if not text or text == "" then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(title, 1, 1, 1)
	GameTooltip:AddLine(text, 0.85, 0.85, 0.85, true)
	GameTooltip:Show()
end

-- A row: label on the left (hover for the tooltip), control on the right.
local function Row(content)
	local row = CreateFrame("Frame", nil, content)
	row:SetHeight(ROW)
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.label:SetPoint("LEFT", 8, 0)
	row.label:SetWidth(CONTROL_X - 16)
	row.label:SetJustifyH("LEFT")
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self) ShowTip(self, self.item.label, self.item.tooltip) end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function Refresh() if window and window:IsShown() then StzxUI:RefreshOptionsWindow() end end

local MAKERS = {}

function MAKERS.header(content)
	local h = CreateFrame("Frame", nil, content)
	h.title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	h.title:SetPoint("TOPLEFT", 4, -6)
	h.title:SetTextColor(A.r, A.g, A.b)
	h.text = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	h.text:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -4)
	h.text:SetJustifyH("LEFT")
	h.text:SetTextColor(0.75, 0.75, 0.75)
	return h
end

function MAKERS.checkbox(content)
	local row = Row(content)
	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetSize(26, 26)
	row.check:SetPoint("LEFT", row, "LEFT", CONTROL_X, 0)
	row.check:SetScript("OnClick", function(self)
		row.item.setting:SetValue(self:GetChecked() and true or false)
		Refresh()
	end)
	return row
end

function MAKERS.button(content)
	local row = Row(content)
	row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.button:SetSize(140, 24)
	row.button:SetPoint("LEFT", row, "LEFT", CONTROL_X, 0)
	row.button:SetScript("OnClick", function() row.item.onClick() Refresh() end)
	return row
end

local function Choices(item)
	return type(item.choices) == "function" and item.choices() or item.choices or {}
end

local function ChoiceLabel(item, value)
	for _, choice in ipairs(Choices(item)) do
		if choice[1] == value then return choice[2] end
	end
	return tostring(value or "")
end

function MAKERS.dropdown(content)
	local row = Row(content)
	row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.button:SetSize(200, 24)
	row.button:SetPoint("LEFT", row, "LEFT", CONTROL_X, 0)
	row.button:SetScript("OnClick", function(self)
		local item = row.item
		local list = Choices(item)
		-- The game's own pop-up menu where there is one; otherwise step to the next choice.
		if MenuUtil and MenuUtil.CreateContextMenu then
			MenuUtil.CreateContextMenu(self, function(_, root)
				for _, choice in ipairs(list) do
					root:CreateRadio(choice[2],
						function() return item.setting:GetValue() == choice[1] end,
						function() item.setting:SetValue(choice[1]) Refresh() end)
				end
			end)
			return
		end
		local now, nextValue = item.setting:GetValue(), list[1] and list[1][1]
		for i, choice in ipairs(list) do
			if choice[1] == now and list[i + 1] then nextValue = list[i + 1][1] end
		end
		if nextValue ~= nil then item.setting:SetValue(nextValue) end
		Refresh()
	end)
	return row
end

function MAKERS.slider(content)
	local row = Row(content)
	local slider = CreateFrame("Slider", nil, row)
	slider:SetOrientation("HORIZONTAL")
	slider:SetSize(200, 14)
	slider:SetPoint("LEFT", row, "LEFT", CONTROL_X, 0)
	slider:SetObeyStepOnDrag(true)
	slider:EnableMouse(true)
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetColorTexture(0.25, 0.27, 0.3, 1)
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(10, 16)
	thumb:SetColorTexture(A.r, A.g, A.b, 1)
	slider:SetThumbTexture(thumb)
	row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.value:SetPoint("LEFT", slider, "RIGHT", 10, 0)
	slider:SetScript("OnValueChanged", function(self, value, userInput)
		local item = row.item
		local step = item.step or 1
		value = math.floor(value / step + 0.5) * step
		row.value:SetText(item.format and item.format(value) or tostring(value))
		if userInput and value ~= item.setting:GetValue() then item.setting:SetValue(value) end
	end)
	row.slider = slider
	return row
end

---------------------------------------------------------------------------
-- Drawing a page (or search results)
---------------------------------------------------------------------------

local function Place(widget, y, height)
	widget:ClearAllPoints()
	widget:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, -y)
	widget:SetPoint("RIGHT", window.content, "RIGHT", 0, 0)
	widget:SetHeight(height)
	return y + height
end

local function Draw(item, y)
	local widget = Acquire(item.kind, function() return MAKERS[item.kind](window.content) end)
	widget.item = item
	if item.kind == "header" then
		widget.title:SetText(item.label)
		widget.text:SetWidth(WIDTH - SIDEBAR - 60)
		widget.text:SetText(item.tooltip or "")
		local extra = (item.tooltip and item.tooltip ~= "") and 30 or 4
		return Place(widget, y + (y > 0 and 10 or 0), 28 + extra)
	end
	widget.label:SetText(item.label)
	if item.kind == "checkbox" then
		widget.check:SetChecked(item.setting:GetValue() and true or false)
	elseif item.kind == "button" then
		widget.button:SetText(item.buttonText)
	elseif item.kind == "dropdown" then
		widget.button:SetText(ChoiceLabel(item, item.setting:GetValue()))
	elseif item.kind == "slider" then
		widget.slider:SetMinMaxValues(item.min, item.max)
		widget.slider:SetValueStep(item.step or 1)
		local value = item.setting:GetValue()
		widget.slider:SetValue(value)
		widget.value:SetText(item.format and item.format(value) or tostring(value))
	end
	return Place(widget, y, ROW)
end

function StzxUI:RefreshOptionsWindow()
	if not window then return end
	ReleaseAll()
	local y = 0
	local query = window.search:GetText()
	if query and query:match("%S") then
		local results = self:SearchOptions(query)
		window.pageTitle:SetText(("Search: %d found"):format(#results))
		local lastPage
		for _, hit in ipairs(results) do
			if hit.page ~= lastPage then
				y = Draw({ kind = "header", label = hit.page.title }, y)
				lastPage = hit.page
			end
			y = Draw(hit.item, y)
		end
		if #results == 0 then y = Draw({ kind = "header", label = "Nothing matches", tooltip = "Try a shorter word." }, y) end
	elseif current then
		window.pageTitle:SetText(current.title)
		for _, item in ipairs(current.items) do y = Draw(item, y) end
	end
	window.content:SetHeight(math.max(y + 10, 1))
	window.scroll:SetVerticalScroll(0)
	for _, b in ipairs(window.tabs) do
		b.selected:SetShown(b.entry == current and not (query and query:match("%S")))
	end
end

-- Lay out the sidebar: top pages, each folder (its pages under it when open), Profiles.
local SIDE_TOP, SIDE_STEP, INDENT = -76, 26, 16
local function LayoutSidebar()
	if not window then return end
	local y = SIDE_TOP
	local function Put(button, indent)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 6 + (indent or 0), y)
		button:SetWidth(SIDEBAR - 12 - (indent or 0))
		button:Show()
		y = y - SIDE_STEP
	end
	for _, b in ipairs(window.tabs) do b:Hide() end
	for _, b in ipairs(window.tabs) do
		if not b.folder and b.entry.title ~= "Profiles" then Put(b) end
	end
	for _, folder in ipairs(window.folders) do
		if #folder.pages > 0 then
			local open = folder.name == openFolder
			folder.button.sign:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
			Put(folder.button)
			if open then
				for _, b in ipairs(folder.pages) do Put(b, INDENT) end
			end
		else
			folder.button:Hide()
		end
	end
	for _, b in ipairs(window.tabs) do
		if b.entry.title == "Profiles" then Put(b) end
	end
end

-- Open one folder (and close the others); the open one again closes it.
function StzxUI:ToggleOptionFolder(name)
	openFolder = (openFolder ~= name) and name or nil
	LayoutSidebar()
end

function StzxUI:ShowOptionsPage(title)
	if not window then return end
	for _, entry in ipairs(self:OptionPagesInOrder()) do
		if entry.title == title then current = entry end
	end
	local folder = current and self:OptionFolderOf(current.title)
	if folder then openFolder = folder end -- the page's folder stays open
	LayoutSidebar()
	window.search:SetText("")
	self:RefreshOptionsWindow()
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function Build()
	local f = CreateFrame("Frame", "StzxUIOptions", UIParent)
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH") -- below StzxUI's pop-ups (reload prompts) and move mode
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	table.insert(UISpecialFrames, "StzxUIOptions") -- Escape closes it

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.06, 0.08, 0.97)
	local side = f:CreateTexture(nil, "BORDER")
	side:SetPoint("TOPLEFT", 0, -36)
	side:SetPoint("BOTTOMLEFT")
	side:SetWidth(SIDEBAR)
	side:SetColorTexture(0.08, 0.09, 0.12, 1)
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	line:SetHeight(2)
	line:SetColorTexture(A.r, A.g, A.b, 1)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("StzxUI")
	title:SetTextColor(A.r, A.g, A.b)
	local version = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	version:SetPoint("LEFT", title, "RIGHT", 8, -1)
	version:SetText(StzxUI.version or "dev")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	-- Search.
	local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	search:SetSize(SIDEBAR - 28, 22)
	search:SetPoint("TOPLEFT", 18, -46)
	search:SetAutoFocus(false)
	search:SetScript("OnTextChanged", function() StzxUI:RefreshOptionsWindow() end)
	search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	f.search = search
	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", search, "LEFT", 2, 0)
	hint:SetText("Search")
	search:HookScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)

	-- Sidebar: a button per page, and a button per folder (laid out by LayoutSidebar).
	local function SideButton(label)
		local b = CreateFrame("Button", nil, f)
		b:SetSize(SIDEBAR - 12, 24)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		b.text:SetPoint("LEFT", 10, 0)
		b.text:SetText(label)
		local hover = b:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.06)
		return b
	end
	f.folders = {}
	local folderByName = {}
	for _, spec in ipairs(FOLDERS) do
		local folder = { name = spec.name, pages = {} }
		f.folders[#f.folders + 1] = folder
		folderByName[spec.name] = folder
	end
	local other = { name = OTHER, pages = {} }
	f.folders[#f.folders + 1] = other
	folderByName[OTHER] = other
	for _, folder in ipairs(f.folders) do
		local b = SideButton(folder.name)
		b.text:SetPoint("LEFT", 26, 0)
		b.text:SetTextColor(A.r, A.g, A.b)
		b.sign = b:CreateTexture(nil, "OVERLAY")
		b.sign:SetSize(14, 14)
		b.sign:SetPoint("LEFT", 8, 0)
		b:SetScript("OnClick", function() StzxUI:ToggleOptionFolder(folder.name) end)
		folder.button = b
	end
	f.tabs = {}
	for i, entry in ipairs(StzxUI:OptionPagesInOrder()) do
		local b = SideButton(entry.title)
		b.entry = entry
		b.selected = b:CreateTexture(nil, "BACKGROUND")
		b.selected:SetAllPoints()
		b.selected:SetColorTexture(A.r, A.g, A.b, 0.25)
		b.selected:Hide()
		b:SetScript("OnClick", function() StzxUI:ShowOptionsPage(entry.title) end)
		local folderName = StzxUI:OptionFolderOf(entry.title)
		if folderName then
			b.folder = folderByName[folderName]
			table.insert(b.folder.pages, b)
		end
		f.tabs[i] = b
	end
	-- Pages inside a folder in the folder's own order (unknown ones at the end).
	for _, folder in ipairs(f.folders) do
		local order = {}
		for _, spec in ipairs(FOLDERS) do
			if spec.name == folder.name then
				for n, pageTitle in ipairs(spec.pages) do order[pageTitle] = n end
			end
		end
		table.sort(folder.pages, function(a, b)
			local oa, ob = order[a.entry.title] or 99, order[b.entry.title] or 99
			if oa ~= ob then return oa < ob end
			return a.entry.title < b.entry.title
		end)
	end

	-- Quick buttons at the bottom of the sidebar.
	local move = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	move:SetSize(SIDEBAR - 24, 24)
	move:SetPoint("BOTTOMLEFT", 12, 40)
	move:SetText("Move mode")
	move:SetScript("OnClick", function() f:Hide() StzxUI:EnterMoveMode() end)
	local test = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	test:SetSize(SIDEBAR - 24, 24)
	test:SetPoint("BOTTOMLEFT", 12, 12)
	test:SetText("Test frames")
	test:SetScript("OnClick", function() StzxUI:ToggleTestMode() end)

	-- The page: a scrolling area (mouse wheel).
	f.pageTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.pageTitle:SetPoint("TOPLEFT", SIDEBAR + 20, -46)
	f.pageTitle:SetTextColor(1, 1, 1)
	local scroll = CreateFrame("ScrollFrame", nil, f)
	scroll:SetPoint("TOPLEFT", SIDEBAR + 16, -80)
	scroll:SetPoint("BOTTOMRIGHT", -16, 12)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange() or 0
		local y = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40))
		self:SetVerticalScroll(y)
	end)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - SIDEBAR - 40, 1)
	scroll:SetScrollChild(content)
	f.scroll, f.content = scroll, content
	window = f
	LayoutSidebar()
	return f
end

function StzxUI:OpenOptionsWindow(title)
	window = window or Build()
	if title then
		self:ShowOptionsPage(title)
	elseif not current then
		self:ShowOptionsPage("General")
	else
		self:RefreshOptionsWindow()
	end
	window:Show()
	return window
end

function StzxUI:ToggleOptionsWindow()
	if window and window:IsShown() then window:Hide() else self:OpenOptionsWindow() end
end

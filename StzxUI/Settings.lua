-- StzxUI Settings
-- One "StzxUI" entry in Esc > Options > AddOns:
--   StzxUI            welcome page: what StzxUI is, and a button into StzxUI's own window
--   StzxUI > General  move mode, grid, notices, and Sections (switch modules on/off)
--   StzxUI > Social   (and one page per module)
--   StzxUI > Profiles choose, copy, reset, delete, export, import
-- Built on Blizzard's own Settings API so options look like the game's own.
--
-- Every helper below also notes what it made in StzxUI.optionPages, and
-- StzxUI's own options window (OptionsWindow.lua) draws itself from that
-- list. Both write through the same settings, so they always agree.

local StzxUI = _G.StzxUI

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------

-- Each option needs a name that is unique across the whole game.
local function VariableName(owner, key)
	return ("STZXUI_%s_%s"):format(owner.name:upper(), key:upper())
end

local function LayoutFor(page)
	return (StzxUI.layouts and StzxUI.layouts[page]) or SettingsPanel:GetLayout(page)
end

-- The list the StzxUI window draws from: { { title, items = { ... } }, ... }
StzxUI.optionPages = {}
local pageOf = {}

function StzxUI:NoteOptionPage(page, title)
	if pageOf[page] then return pageOf[page] end
	local entry = { title = title, items = {} }
	table.insert(self.optionPages, entry)
	pageOf[page] = entry
	return entry
end

-- item: { kind = "header" | "button" | "checkbox" | "dropdown" | "slider", label, tooltip, ... }
function StzxUI:NoteOption(page, item)
	local entry = pageOf[page] or self:NoteOptionPage(page, "StzxUI")
	table.insert(entry.items, item)
end

-- A sub-page under StzxUI, e.g. StzxUI > Social.
function StzxUI:AddSettingsPage(title)
	local page, layout = Settings.RegisterVerticalLayoutSubcategory(self.settingsCategory, title)
	self.layouts[page] = layout
	self:NoteOptionPage(page, title)
	return page
end

-- A section title inside a page.
function StzxUI:AddHeader(page, title, tooltip)
	LayoutFor(page):AddInitializer(CreateSettingsListSectionHeaderInitializer(title, tooltip))
	self:NoteOption(page, { kind = "header", label = title, tooltip = tooltip })
end

-- A button row: label on the left, button on the right.
function StzxUI:AddButton(page, label, buttonText, onClick, tooltip)
	LayoutFor(page):AddInitializer(CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true))
	self:NoteOption(page, { kind = "button", label = label, buttonText = buttonText, onClick = onClick, tooltip = tooltip })
end

-- On/off option that writes straight into owner.db[key].
function StzxUI:AddCheckbox(page, owner, key, label, tooltip, onChange)
	local setting = Settings.RegisterAddOnSetting(page, VariableName(owner, key), key, owner.db,
		Settings.VarType.Boolean, label, owner.defaults[key])
	if onChange then
		setting:SetValueChangedCallback(function(_, value) onChange(value) end)
	end
	Settings.CreateCheckbox(page, setting, tooltip)
	self:NoteOption(page, { kind = "checkbox", setting = setting, label = label, tooltip = tooltip })
	return setting
end

-- Pick-one option. `choices` is a list of { value, label } pairs, or a
-- function returning one (for lists that depend on what's installed).
function StzxUI:AddDropdown(page, owner, key, label, tooltip, choices, onChange)
	local setting = Settings.RegisterAddOnSetting(page, VariableName(owner, key), key, owner.db,
		Settings.VarType.String, label, owner.defaults[key])
	if onChange then
		setting:SetValueChangedCallback(function(_, value) onChange(value) end)
	end
	local function Options()
		local container = Settings.CreateControlTextContainer()
		local list = type(choices) == "function" and choices() or choices
		for _, choice in ipairs(list) do
			container:Add(choice[1], choice[2])
		end
		return container:GetData()
	end
	Settings.CreateDropdown(page, setting, Options, tooltip)
	self:NoteOption(page, { kind = "dropdown", setting = setting, label = label, tooltip = tooltip, choices = choices })
	return setting
end

-- Number option on a slider. `format` turns the value into its label text.
function StzxUI:AddSlider(page, owner, key, label, tooltip, minValue, maxValue, step, format, onChange)
	local setting = Settings.RegisterAddOnSetting(page, VariableName(owner, key), key, owner.db,
		Settings.VarType.Number, label, owner.defaults[key])
	if onChange then
		setting:SetValueChangedCallback(function(_, value) onChange(value) end)
	end
	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	if format then
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
	end
	Settings.CreateSlider(page, setting, options, tooltip)
	self:NoteOption(page, { kind = "slider", setting = setting, label = label, tooltip = tooltip,
		min = minValue, max = maxValue, step = step, format = format })
	return setting
end

---------------------------------------------------------------------------
-- The main StzxUI page (created when the core loads)
---------------------------------------------------------------------------

-- The welcome page: the first thing you see under Esc > Options > AddOns >
-- StzxUI. A big title, what StzxUI does, and buttons into StzxUI's own window.
local LANDING_FONT = "Fonts\\FRIZQT__.TTF"

local function LandingText(parent, size, r, g, b)
	local text = parent:CreateFontString(nil, "ARTWORK")
	text:SetFont(LANDING_FONT, size, "")
	text:SetTextColor(r or 1, g or 1, b or 1)
	text:SetJustifyH("CENTER")
	return text
end

local function LandingButton(parent, label, width, height, fontSize, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, height)
	button:SetText(label)
	local text = button:GetFontString()
	if text then text:SetFont(LANDING_FONT, fontSize, "") end
	button:SetScript("OnClick", onClick)
	return button
end

local function AddonVersion()
	local version = C_AddOns.GetAddOnMetadata("StzxUI", "Version")
	if not version or version:find("project%-version") then return "development copy" end
	return version
end

-- Which sections are switched on, e.g. "Unit Frames, Minimap".
local function SectionsOn(self)
	local on = {}
	for _, name in ipairs(self.moduleOrder or {}) do
		local module = self.modules[name]
		if module.enabled then on[#on + 1] = module.title end
	end
	return #on > 0 and table.concat(on, ", ") or "none"
end

function StzxUI:CreateLandingPage()
	local A = self.ACCENT
	local hex = ("%02x%02x%02x"):format(A.r * 255, A.g * 255, A.b * 255)
	local page = CreateFrame("Frame", "StzxUISettingsLanding")
	page:Hide()

	local title = LandingText(page, 72)
	title:SetPoint("TOP", page, "TOP", 0, -60)
	title:SetText(("|cff%sStzx|rUI"):format(hex))

	local tagline = LandingText(page, 18)
	tagline:SetPoint("TOP", title, "BOTTOM", 0, -6)
	tagline:SetText("A complete UI for WoW: Forever")

	local version = LandingText(page, 13, 0.7, 0.7, 0.7)
	version:SetPoint("TOP", tagline, "BOTTOM", 0, -6)

	local about = LandingText(page, 14, 0.9, 0.9, 0.9)
	about:SetPoint("TOP", version, "BOTTOM", 0, -22)
	about:SetWidth(540)
	about:SetWordWrap(true)
	about:SetText("Unit frames, party and raid frames, nameplates, a restyled minimap and action bars, "
		.. "quest helpers, fishing and dungeon-run tools, and more. Switch each part on or off, keep "
		.. "your setup in profiles you can share, and place everything in move mode alongside "
		.. "Blizzard's Edit Mode.")

	local open = LandingButton(page, "Open StzxUI options", 320, 46, 20, function()
		if SettingsPanel and SettingsPanel:IsShown() then SettingsPanel:Close(true) end
		self:OpenOptionsWindow()
	end)
	open:SetPoint("TOP", about, "BOTTOM", 0, -30)
	page.open = open

	local hint = LandingText(page, 13, 0.7, 0.7, 0.7)
	hint:SetPoint("TOP", open, "BOTTOM", 0, -10)
	hint:SetText("or type /stzx in chat")

	local move = LandingButton(page, "Move mode", 150, 26, 13, function() self:EnterMoveMode() end)
	move:SetPoint("TOPRIGHT", hint, "BOTTOM", -6, -22)
	page.move = move
	local test = LandingButton(page, "Test frames", 150, 26, 13, function() self:ToggleTestMode() end)
	test:SetPoint("TOPLEFT", hint, "BOTTOM", 6, -22)
	page.test = test

	local sections = LandingText(page, 12, 0.7, 0.7, 0.7)
	sections:SetPoint("TOP", move, "BOTTOMRIGHT", 6, -28)
	sections:SetWidth(540)
	sections:SetWordWrap(true)
	page.sections = sections

	-- Version and sections can change (a reload, a new build), so fill them in on show.
	page:SetScript("OnShow", function()
		version:SetText("Version: " .. AddonVersion())
		sections:SetText(("|cff%sSections on:|r %s"):format(hex, SectionsOn(self)))
	end)
	return page
end

function StzxUI:CreateSettingsPanel()
	-- The top entry is the welcome page; the options themselves are on sub-pages.
	local category = Settings.RegisterCanvasLayoutCategory(self:CreateLandingPage(), "StzxUI")
	self.settingsCategory = category
	local general, layout = Settings.RegisterVerticalLayoutSubcategory(category, "General")
	self.generalPage = general
	self.layouts = { [general] = layout }
	self:NoteOptionPage(general, "General")
	category = general

	-- The core's own options live in StzxUIDB.core (same on every character).
	local core = { name = "Core", db = self.db.core, defaults = self.CORE_DEFAULTS }

	self:AddHeader(category, "Move mode")
	self:AddButton(category, "Move StzxUI frames", "Unlock",
		function() self:EnterMoveMode() end,
		"Shows every StzxUI frame with a label so you can drag it into place. Type /stzx move to do the same.")
	self:AddCheckbox(category, core, "snapToGrid", "Snap to grid",
		"Frames line up with the grid as you drop them. Hold Shift while dragging to place freely.")
	self:AddCheckbox(category, core, "snapToFrames", "Snap to other frames",
		"A frame dropped close to another lines up with its edges or centre. Hold Shift to place freely.")
	self:AddCheckbox(category, core, "withEditMode", "Open with Edit Mode",
		"Opening Blizzard's Edit Mode opens StzxUI move mode too, so you can place both at once. "
		.. "While both are open, StzxUI uses Edit Mode's grid size and its frames snap to Blizzard's.")
	self:AddSlider(category, core, "gridSize", "Grid size",
		"Space between grid lines in move mode.", 8, 64, 8,
		function(value) return ("%d px"):format(value) end,
		function() self:RefreshGrid() end)

	self:AddHeader(category, "General")
	self:AddDropdown(category, core, "accent", "Accent colour",
		"The colour of StzxUI's highlights: move mode, windows, frame rings. Changes apply after a reload.",
		{ { "STZX", "StzxUI blue" }, { "CLASS", "My class colour" },
			{ "RED", "Red (#CC1111, on #0D0D0D black)" }, { "BRIGHTRED", "Bright red (#FF3333, on #0D0D0D black)" } },
		function() self:AskReload("The accent colour changes after a reload.") end)
	self:AddCheckbox(category, core, "chatMessages", "Show StzxUI notices in chat",
		"Short messages such as \"Declined a duel from ...\". Replies to /stzx commands always show.")
end

---------------------------------------------------------------------------
-- Added at login, once every module has registered
---------------------------------------------------------------------------

-- StzxUI > Sections: one switch per module. Stored in the profile, so a
-- shared profile also carries which parts are on.
local function AddSectionSwitches(self)
	local category = self.generalPage
	LayoutFor(category):AddInitializer(CreateSettingsListSectionHeaderInitializer("Sections",
		"Switch whole parts of StzxUI on or off for this profile. Changes apply after a reload."))
	-- In the StzxUI window, Sections is a page of its own.
	local sections = self:NoteOptionPage("SECTIONS", "Sections")
	table.insert(sections.items, { kind = "header", label = "Sections",
		tooltip = "Switch whole parts of StzxUI on or off for this profile. Changes apply after a reload." })
	for _, name in ipairs(self.moduleOrder) do
		local module = self.modules[name]
		local setting = Settings.RegisterProxySetting(category, "STZXUI_SECTION_" .. name:upper(),
			Settings.VarType.Boolean, module.title, true,
			function() return self:IsModuleOn(name) end,
			function(value)
				-- Only "off" is stored; on is the default.
				if value then
					self.profile.enabled[name] = nil
				else
					self.profile.enabled[name] = false
				end
				self:AskReload(("%s will be switched %s."):format(module.title, value and "on" or "off"))
			end)
		local tooltip = (module.description and (module.description .. "\n\n") or "") .. "Changes apply after a reload."
		Settings.CreateCheckbox(category, setting, tooltip)
		table.insert(sections.items, { kind = "checkbox", setting = setting, label = module.title, tooltip = tooltip })
	end
end

local function AddProfilesPage(self)
	local page = self:AddSettingsPage("Profiles")

	self:AddHeader(page, "This character",
		"Profiles hold module options, frame positions and which sections are on.")
	local chosen = Settings.RegisterProxySetting(page, "STZXUI_PROFILE_ACTIVE", Settings.VarType.String,
		"Profile", self.DEFAULT_PROFILE,
		function() return self:GetChosenProfile() end,
		function(value) self:SwitchProfile(value) end)
	local function ProfileOptions()
		local container = Settings.CreateControlTextContainer()
		for _, name in ipairs(self:GetProfileNames()) do container:Add(name, name) end
		return container:GetData()
	end
	Settings.CreateDropdown(page, chosen, ProfileOptions, "Which profile this character uses.")
	self:NoteOption(page, { kind = "dropdown", setting = chosen, label = "Profile", tooltip = "Which profile this character uses.",
		choices = function()
			local list = {}
			for _, name in ipairs(self:GetProfileNames()) do list[#list + 1] = { name, name } end
			return list
		end })

	self:AddButton(page, "New profile from this one", "New",
		function()
			self:ShowDialog({
				title = "New profile",
				text = ("Name for a copy of '%s'. This character will switch to it."):format(self.profileName),
				input = "line",
				accept = "Create",
				onAccept = function(text)
					local name, problem = self:CreateProfile(text, self.profileName)
					if not name then return false, problem end
					self:SwitchProfile(name)
					return true
				end,
			})
		end,
		"Copies the current profile under a new name, e.g. one for healing and one for questing.")

	self:AddButton(page, "Reset this profile", "Reset",
		function()
			self:ShowDialog({
				title = "Reset profile",
				text = ("Put '%s' back to its defaults? Options, frame positions and sections all reset."):format(self.profileName),
				accept = "Reset",
				onAccept = function() self:ResetProfile() return true end,
			})
		end,
		"Back to the defaults, for this profile only.")

	self:AddButton(page, "Delete this profile", "Delete",
		function()
			if self.profileName == self.DEFAULT_PROFILE then
				self:ShowDialog({ title = "Delete profile", text = "The Default profile can't be deleted." })
				return
			end
			self:ShowDialog({
				title = "Delete profile",
				text = ("Delete '%s' for good? Characters using it go back to Default."):format(self.profileName),
				accept = "Delete",
				onAccept = function() return self:DeleteProfile(self.profileName) end,
			})
		end,
		"Removes the current profile. Default can't be deleted.")

	self:AddHeader(page, "Sharing",
		"A profile as one line of text you can paste to a friend or keep as a backup.")
	self:AddButton(page, "Export this profile", "Export",
		function()
			local text, problem = self:ExportProfile()
			self:ShowDialog({
				title = "Export profile",
				text = text and "Press Ctrl+C to copy, then paste it wherever you like."
					or (problem or "Export failed."),
				input = text and "box" or nil,
				value = text,
				selectAll = true,
			})
		end,
		"Turns the current profile into a text string.")
	self:AddButton(page, "Import a profile", "Import",
		function()
			self:ShowDialog({
				title = "Import profile",
				text = "Paste a StzxUI profile string (Ctrl+V). Next you'll name it; it becomes a new profile and this character switches to it.",
				input = "box",
				accept = "Next",
				onAccept = function(text)
					local data, problem, sharedName = self:DecodeProfile(text)
					if not data then return false, problem end
					-- Step two: name it (suggested: the name it was shared under).
					self:ShowDialog({
						title = "Name the imported profile",
						text = "What should this profile be called?",
						input = "line",
						value = self:FreeProfileName(sharedName),
						selectAll = true,
						accept = "Import",
						onAccept = function(name)
							local made, nameProblem = self:ImportProfile(text, name)
							if not made then return false, nameProblem end
							return true
						end,
					})
					return true
				end,
			})
		end,
		"Adds a shared profile without touching your existing ones.")
end

function StzxUI:FinishSettingsPanel()
	if self.settingsRegistered or not self.settingsCategory then return end
	AddSectionSwitches(self)
	AddProfilesPage(self)
	Settings.RegisterAddOnCategory(self.settingsCategory)
	self.settingsRegistered = true
end

-- /stzx and the minimap-style shortcuts open StzxUI's own window.
function StzxUI:OpenSettings()
	self:OpenOptionsWindow()
end

-- Blizzard's Esc > Options > AddOns > StzxUI.
function StzxUI:OpenBlizzardSettings()
	if self.settingsCategory then
		Settings.OpenToCategory(self.settingsCategory:GetID())
	end
end

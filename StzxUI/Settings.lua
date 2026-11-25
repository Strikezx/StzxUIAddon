-- StzxUI Settings
-- One "StzxUI" entry in Esc > Options > AddOns:
--   StzxUI            move mode, grid, notices, and Sections (switch modules on/off)
--   StzxUI > Social   (and one page per module)
--   StzxUI > Profiles choose, copy, reset, delete, export, import
-- Built on Blizzard's own Settings API so options look like the game's own.

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

-- A sub-page under StzxUI, e.g. StzxUI > Social.
function StzxUI:AddSettingsPage(title)
	local page, layout = Settings.RegisterVerticalLayoutSubcategory(self.settingsCategory, title)
	self.layouts[page] = layout
	return page
end

-- A section title inside a page.
function StzxUI:AddHeader(page, title, tooltip)
	LayoutFor(page):AddInitializer(CreateSettingsListSectionHeaderInitializer(title, tooltip))
end

-- A button row: label on the left, button on the right.
function StzxUI:AddButton(page, label, buttonText, onClick, tooltip)
	LayoutFor(page):AddInitializer(CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true))
end

-- On/off option that writes straight into owner.db[key].
function StzxUI:AddCheckbox(page, owner, key, label, tooltip, onChange)
	local setting = Settings.RegisterAddOnSetting(page, VariableName(owner, key), key, owner.db,
		Settings.VarType.Boolean, label, owner.defaults[key])
	if onChange then
		setting:SetValueChangedCallback(function(_, value) onChange(value) end)
	end
	Settings.CreateCheckbox(page, setting, tooltip)
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
	return setting
end

---------------------------------------------------------------------------
-- The main StzxUI page (created when the core loads)
---------------------------------------------------------------------------

function StzxUI:CreateSettingsPanel()
	local category, layout = Settings.RegisterVerticalLayoutCategory("StzxUI")
	self.settingsCategory = category
	self.layouts = { [category] = layout }

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
		{ { "STZX", "StzxUI blue" }, { "CLASS", "My class colour" } },
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
	local category = self.settingsCategory
	self:AddHeader(category, "Sections",
		"Switch whole parts of StzxUI on or off for this profile. Changes apply after a reload.")
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
		Settings.CreateCheckbox(category, setting,
			(module.description and (module.description .. "\n\n") or "") .. "Changes apply after a reload.")
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

function StzxUI:OpenSettings()
	if self.settingsCategory then
		Settings.OpenToCategory(self.settingsCategory:GetID())
	end
end

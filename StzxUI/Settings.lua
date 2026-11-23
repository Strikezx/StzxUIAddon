-- StzxUI Settings
-- One "StzxUI" entry in Esc > Options > AddOns, with a page per module.
-- Built on Blizzard's own Settings API (the vertical-list kind), so every
-- option looks and behaves like the game's own options.

local StzxUI = _G.StzxUI

-- Called when the core addon loads: the main page and its own options.
function StzxUI:CreateSettingsPanel()
	local category = Settings.RegisterVerticalLayoutCategory("StzxUI")
	self.settingsCategory = category

	local core = { name = "Core", db = self.db.core, defaults = { chatMessages = true } }
	self:AddCheckbox(category, core, "chatMessages",
		"Show StzxUI notices in chat",
		"Short messages such as \"Declined a duel from ...\". Replies to /stzx commands always show.")
end

-- Called at login, after every module has added its page.
function StzxUI:FinishSettingsPanel()
	if self.settingsRegistered or not self.settingsCategory then return end
	Settings.RegisterAddOnCategory(self.settingsCategory)
	self.settingsRegistered = true
end

function StzxUI:OpenSettings()
	if self.settingsCategory then
		Settings.OpenToCategory(self.settingsCategory:GetID())
	end
end

---------------------------------------------------------------------------
-- Helpers modules use to build their page
---------------------------------------------------------------------------

-- A sub-page under StzxUI, e.g. StzxUI > Social.
function StzxUI:AddSettingsPage(title)
	return Settings.RegisterVerticalLayoutSubcategory(self.settingsCategory, title)
end

-- Each option needs a name that is unique across the whole game.
local function VariableName(module, key)
	return ("STZXUI_%s_%s"):format(module.name:upper(), key:upper())
end

-- On/off option that writes straight into module.db[key].
function StzxUI:AddCheckbox(page, module, key, label, tooltip, onChange)
	local setting = Settings.RegisterAddOnSetting(page, VariableName(module, key), key, module.db,
		Settings.VarType.Boolean, label, module.defaults[key])
	if onChange then
		setting:SetValueChangedCallback(function(_, value) onChange(value) end)
	end
	Settings.CreateCheckbox(page, setting, tooltip)
	return setting
end

-- Pick-one option. `choices` is a list of { value, label } pairs.
function StzxUI:AddDropdown(page, module, key, label, tooltip, choices, onChange)
	local setting = Settings.RegisterAddOnSetting(page, VariableName(module, key), key, module.db,
		Settings.VarType.String, label, module.defaults[key])
	if onChange then
		setting:SetValueChangedCallback(function(_, value) onChange(value) end)
	end
	local function Options()
		local container = Settings.CreateControlTextContainer()
		for _, choice in ipairs(choices) do
			container:Add(choice[1], choice[2])
		end
		return container:GetData()
	end
	Settings.CreateDropdown(page, setting, Options, tooltip)
	return setting
end

-- Number option on a slider. `format` turns the value into its label text.
function StzxUI:AddSlider(page, module, key, label, tooltip, minValue, maxValue, step, format)
	local setting = Settings.RegisterAddOnSetting(page, VariableName(module, key), key, module.db,
		Settings.VarType.Number, label, module.defaults[key])
	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	if format then
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
	end
	Settings.CreateSlider(page, setting, options, tooltip)
	return setting
end

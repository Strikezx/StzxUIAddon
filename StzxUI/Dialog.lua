-- StzxUI Dialog
-- One small pop-up window, reused for everything that needs a question or a
-- text box: naming a profile, copying an export string, pasting an import,
-- "reload now?". Our own window (not Blizzard's StaticPopup) so StzxUI never
-- touches Blizzard's shared popup code.
--
--   StzxUI:ShowDialog({
--       title = "New profile",
--       text = "Name for the new profile:",
--       input = "line" | "box" | nil,   -- one-line field, big text box, or none
--       value = "starting text",
--       selectAll = true,               -- highlight the text (for copying)
--       accept = "Create",              -- left button (nil = only a Close button)
--       cancel = "Cancel",
--       onAccept = function(text) return true end, -- return false, "why" to stay open
--   })

local StzxUI = _G.StzxUI

local WIDTH = 440
local dialog

local function MakeButton(parent, label)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(110, 24)
	button:SetText(label)
	return button
end

local function BuildDialog()
	local f = CreateFrame("Frame", "StzxUIDialog", UIParent)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetPoint("CENTER", 0, 120)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()

	-- Flat dark panel with an accent line on top.
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	local back = StzxUI.BACKGROUND
	bg:SetColorTexture(back.r + 0.03, back.g + 0.03, back.b + 0.04, 0.96)
	local line = f:CreateTexture(nil, "BORDER")
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	line:SetHeight(2)
	local a = StzxUI.ACCENT
	line:SetColorTexture(a.r, a.g, a.b, 1)

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", 16, -14)
	f.title:SetTextColor(a.r, a.g, a.b)

	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -10)
	f.text:SetWidth(WIDTH - 32)
	f.text:SetJustifyH("LEFT")

	f.problem = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.problem:SetTextColor(1, 0.4, 0.4)
	f.problem:SetJustifyH("LEFT")
	f.problem:SetWidth(WIDTH - 32)

	-- One-line field
	f.line = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	f.line:SetSize(WIDTH - 40, 24)
	f.line:SetAutoFocus(false)
	f.line:SetMaxLetters(64)

	-- Big text box (for profile strings)
	f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	f.scroll:SetSize(WIDTH - 56, 150)
	local boxBg = f:CreateTexture(nil, "ARTWORK")
	boxBg:SetPoint("TOPLEFT", f.scroll, -4, 4)
	boxBg:SetPoint("BOTTOMRIGHT", f.scroll, 4, -4)
	boxBg:SetColorTexture(0, 0, 0, 0.5)
	f.boxBg = boxBg
	f.box = CreateFrame("EditBox", nil, f.scroll)
	f.box:SetMultiLine(true)
	f.box:SetAutoFocus(false)
	f.box:SetFontObject("ChatFontNormal")
	f.box:SetWidth(WIDTH - 60)
	f.scroll:SetScrollChild(f.box)

	for _, box in ipairs({ f.line, f.box }) do
		box:SetScript("OnEscapePressed", function() f:Hide() end)
	end
	f.line:SetScript("OnEnterPressed", function() f.acceptButton:Click() end)

	f.acceptButton = MakeButton(f, "OK")
	f.cancelButton = MakeButton(f, "Cancel")
	f.cancelButton:SetScript("OnClick", function() f:Hide() end)
	f.acceptButton:SetScript("OnClick", function()
		local options = f.options or {}
		local text
		if options.input == "line" then text = f.line:GetText()
		elseif options.input == "box" then text = f.box:GetText() end
		local keepOpen, problem = false, nil
		if options.onAccept then
			local ok, why = options.onAccept(text)
			if ok == false then keepOpen, problem = true, why end
		end
		if keepOpen then
			f.problem:SetText(problem or "")
		elseif f.options == options then
			-- Only close if onAccept didn't open a follow-up (e.g. "Reload now?").
			f:Hide()
		end
	end)

	-- Escape closes it.
	table.insert(UISpecialFrames, "StzxUIDialog")
	return f
end

function StzxUI:ShowDialog(options)
	dialog = dialog or BuildDialog()
	local f = dialog
	f.options = options
	f.title:SetText(options.title or "StzxUI")
	f.text:SetText(options.text or "")
	f.problem:SetText("")

	f.line:Hide()
	f.scroll:Hide()
	f.boxBg:Hide()
	local below = f.text
	if options.input == "line" then
		f.line:ClearAllPoints()
		f.line:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 6, -10)
		f.line:SetText(options.value or "")
		f.line:Show()
		below = f.line
	elseif options.input == "box" then
		f.scroll:ClearAllPoints()
		f.scroll:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 4, -12)
		f.box:SetText(options.value or "")
		f.scroll:Show()
		f.boxBg:Show()
		below = f.scroll
	end
	f.problem:ClearAllPoints()
	f.problem:SetPoint("TOPLEFT", below, "BOTTOMLEFT", options.input == "line" and -6 or -4, -8)

	-- Buttons along the bottom right.
	f.cancelButton:SetText(options.cancel or (options.accept and "Cancel" or "Close"))
	f.cancelButton:ClearAllPoints()
	f.cancelButton:SetPoint("BOTTOMRIGHT", -14, 12)
	if options.accept then
		f.acceptButton:SetText(options.accept)
		f.acceptButton:ClearAllPoints()
		f.acceptButton:SetPoint("RIGHT", f.cancelButton, "LEFT", -8, 0)
		f.acceptButton:Show()
	else
		f.acceptButton:Hide()
	end

	local height = 104 + (f.text:GetStringHeight() or 14)
	if options.input == "line" then height = height + 40 end
	if options.input == "box" then height = height + 172 end
	f:SetSize(WIDTH, height)
	f:Show()

	local focus = (options.input == "line" and f.line) or (options.input == "box" and f.box) or nil
	if focus then
		focus:SetFocus()
		if options.selectAll then focus:HighlightText() end
	end
end

-- "Reload now?" Reloading swaps in the new profile or section choices.
function StzxUI:AskReload(reason)
	self:ShowDialog({
		title = "Reload needed",
		text = (reason and (reason .. "\n\n") or "") .. "Reload the interface now to apply it?",
		accept = "Reload now",
		cancel = "Later",
		onAccept = function() C_UI.Reload() end,
	})
end

-- StzxUI Social: recent mail names
--
-- A small list beside the Send Mail tab:
--
--     Recent              My characters
--     Liala Brightwood    Wrenzx Goathwyn
--     Gorr                Sorchawyn ...
--
-- Click a name to put it in the "To:" box. Right-click a recent name to
-- forget it. Names are saved for the whole account (StzxUISocialDB), so
-- every character sees the same list, and your own characters are noted
-- as you log in to each one.
--
-- How a name gets saved: Blizzard's send step runs (StzxUI never touches the
-- send itself, which the game restricts); right after it, StzxUI notes the
-- name in the "To:" box, and saves it once the game says the mail went.

local _, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local A = StzxUI.ACCENT

local WIDTH, ROW = 170, 16
local MAX_ROWS = 20

local Mail = {}
ns.Mail = Mail

local function Data()
	StzxUISocialDB = StzxUISocialDB or {}
	StzxUISocialDB.recentMail = StzxUISocialDB.recentMail or {}
	StzxUISocialDB.characters = StzxUISocialDB.characters or {}
	return StzxUISocialDB
end

local function Same(a, b) return a:lower() == b:lower() end

local function MyName()
	local first, surname = UnitName("player")
	first, surname = Plain(first), Plain(surname)
	if not first then return nil end
	if surname and surname ~= "" then return first .. " " .. surname end
	return first
end

-- Put a name at the top of the recent list (no repeats, newest first).
function Mail.Remember(name)
	name = name and strtrim(name)
	if not name or name == "" then return end
	local list = Data().recentMail
	for i = #list, 1, -1 do
		if Same(list[i], name) then table.remove(list, i) end
	end
	table.insert(list, 1, name)
	local keep = ns.Social.db.mailKeep or 10
	for i = #list, keep + 1, -1 do list[i] = nil end
end

function Mail.Forget(name)
	local list = Data().recentMail
	for i = #list, 1, -1 do
		if Same(list[i], name) then table.remove(list, i) end
	end
end

-- Your other characters you can mail (same faction), sorted by name. From
-- StzxUI's character list (core, every character you log in on), plus any
-- noted here before that list existed.
function Mail.Alts()
	local me = MyName()
	local faction = Plain(UnitFactionGroup("player"))
	local seen, alts = {}, {}
	local function Add(name)
		local key = name:lower()
		if seen[key] or (me and Same(name, me)) then return end
		seen[key] = true
		alts[#alts + 1] = name
	end
	for _, char in ipairs(StzxUI:Characters({ faction = faction })) do Add(char.name) end
	local known = StzxUIDB and StzxUIDB.characters or {}
	for name in pairs(Data().characters) do
		local entry = known[name]
		if not (entry and faction and entry.faction and entry.faction ~= faction) then Add(name) end
	end
	table.sort(alts)
	return alts
end

-- A character's class colour, if StzxUI knows their class.
local function ClassColour(name)
	local entry = (StzxUIDB and StzxUIDB.characters and StzxUIDB.characters[name]) or Data().characters[name]
	local colour = entry and entry.class and C_ClassColor and C_ClassColor.GetClassColor(entry.class)
	if colour then return colour.r, colour.g, colour.b end
	return 1, 1, 1
end

---------------------------------------------------------------------------
-- The list beside Send Mail
---------------------------------------------------------------------------

local panel

local function NameButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(WIDTH - 16, ROW)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetAllPoints()
	b.text:SetJustifyH("LEFT")
	b.text:SetWordWrap(false)
	local hover = b:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(A.r, A.g, A.b, 0.2)
	b:SetScript("OnClick", function(self, mouse)
		if mouse == "RightButton" then
			if self.recent then
				Mail.Forget(self.name)
				Mail.Refresh()
			end
			return
		end
		SendMailNameEditBox:SetText(self.name)
		SendMailNameEditBox:SetCursorPosition(0)
		SendMailSubjectEditBox:SetFocus()
	end)
	b:SetScript("OnEnter", function(self)
		if not self.recent then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Right-click to forget", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function Build()
	local p = CreateFrame("Frame", "StzxUIMailNames", SendMailFrame)
	p:SetWidth(WIDTH)
	p:SetPoint("TOPLEFT", MailFrame or SendMailFrame, "TOPRIGHT", 6, -24)
	p:SetClampedToScreen(true)
	p:SetFrameStrata("HIGH")
	-- StzxUI's box: a thin accent edge all round, the usual dark fill, and a
	-- thicker accent bar along the top.
	local back = StzxUI.BACKGROUND
	StzxUI.Skin.Backdrop(p, { edge = "accent", fill = { back.r, back.g, back.b }, alpha = 0.94 })
	local line = p:CreateTexture(nil, "BORDER")
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	line:SetHeight(2)
	line:SetColorTexture(A.r, A.g, A.b, 1)

	-- A heading with a faint accent line under it.
	local function Heading()
		local h = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		h:SetTextColor(A.r, A.g, A.b)
		h.rule = p:CreateTexture(nil, "ARTWORK")
		h.rule:SetHeight(1)
		h.rule:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -2)
		h.rule:SetPoint("RIGHT", p, "RIGHT", -8, 0)
		h.rule:SetColorTexture(A.r, A.g, A.b, 0.35)
		return h
	end
	p.recentTitle = Heading()
	p.recentTitle:SetText("Recent")
	p.altsTitle = Heading()
	p.altsTitle:SetText("My characters")
	p.buttons = {}
	p:SetScript("OnShow", function() Mail.Refresh() end)
	return p
end

function Mail.Refresh()
	if not panel then return end
	if not ns.Social.db.mailRecent then
		panel:Hide()
		return
	end
	local recent, alts = Data().recentMail, Mail.Alts()
	local used, y = 0, -8
	local function Place(name, isRecent)
		used = used + 1
		if used > MAX_ROWS then return end
		local b = panel.buttons[used] or NameButton(panel)
		panel.buttons[used] = b
		b.name, b.recent = name, isRecent
		b.text:SetText(name)
		if isRecent then b.text:SetTextColor(1, 1, 1) else b.text:SetTextColor(ClassColour(name)) end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 8, y)
		b:Show()
		y = y - ROW
	end
	local function Section(title, names, isRecent)
		if #names == 0 then
			title:Hide()
			title.rule:Hide()
			return
		end
		title.rule:Show()
		title:ClearAllPoints()
		title:SetPoint("TOPLEFT", 8, y)
		title:Show()
		y = y - 18
		for _, name in ipairs(names) do Place(name, isRecent) end
		y = y - 6
	end
	Section(panel.recentTitle, recent, true)
	Section(panel.altsTitle, alts, false)
	for i = used + 1, #panel.buttons do panel.buttons[i]:Hide() end
	if used == 0 then
		panel:Hide()
		return
	end
	panel:SetHeight(-y + 4)
	panel:Show()
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------

local pending
local function SetUp()
	if panel or not SendMailFrame then return end
	panel = Build()
	SendMailFrame:HookScript("OnShow", function() Mail.Refresh() end)
	Mail.Refresh()
	hooksecurefunc("SendMailFrame_SendMail", function()
		pending = SendMailNameEditBox:GetText()
	end)
end

function ns.EnableMail()
	-- Note this character, so the others can mail it.
	local me = MyName()
	if me then
		local _, class = UnitClass("player")
		Data().characters[me] = { class = class }
	end
	local events = CreateFrame("Frame")
	events:RegisterEvent("MAIL_SEND_SUCCESS")
	events:RegisterEvent("MAIL_FAILED")
	events:RegisterEvent("ADDON_LOADED")
	events:SetScript("OnEvent", function(_, event, name)
		if event == "ADDON_LOADED" then
			if name == "Blizzard_MailFrame" then SetUp() end
		elseif event == "MAIL_SEND_SUCCESS" then
			if pending and ns.Social.db.mailRecent then
				Mail.Remember(pending)
				Mail.Refresh()
			end
			pending = nil
		else
			pending = nil
		end
	end)
	SetUp()
end

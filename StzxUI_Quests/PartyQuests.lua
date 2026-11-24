-- StzxUI Quests: party quest status
--
-- A small panel beside the quest you're looking at (the quest giver's window,
-- or the quest log's detail page) that lists your party:
--
--     Party
--     Liala          On it
--     Gorr       Not on it
--     [Share]  [Share all]
--
-- The game answers "is this party member on quest X?" itself
-- (C_QuestLog.IsUnitOnQuest), so this needs no data and no messages
-- between addons. "Share" offers the quest to your party; "Share all"
-- offers every quest in your log that can be shared, one a second.

local _, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local A = StzxUI.ACCENT

local WIDTH, ROW = 190, 16
local SHARE_EVERY = 1 -- seconds between quests when sharing them all
local ON = { 0.40, 0.90, 0.40 }
local OFF = { 0.60, 0.60, 0.60 }

local Party = {}
ns.PartyQuests = Party

local panels = {} -- "giver" and "log"

---------------------------------------------------------------------------
-- Who's on what
---------------------------------------------------------------------------

-- Status of one party member for a quest: "on", "off", "offline" or nil
-- (no such member, or the game won't say).
function Party.Status(unit, questID)
	if not Plain(UnitExists(unit)) then return nil end
	if Plain(UnitIsConnected(unit)) == false then return "offline" end
	local on = Plain(C_QuestLog.IsUnitOnQuest(unit, questID))
	if on == nil then return nil end
	return on and "on" or "off"
end

local function ClassColour(unit)
	local _, class = UnitClass(unit)
	local c = class and C_ClassColor and C_ClassColor.GetClassColor(class)
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

---------------------------------------------------------------------------
-- Sharing
---------------------------------------------------------------------------

local function Share(questID)
	local index = questID and C_QuestLog.GetLogIndexForQuestID(questID)
	if index and Plain(C_QuestLog.IsPushableQuest(questID)) then
		QuestLogPushQuest(index)
		return true
	end
	return false
end
Party.Share = Share

local shareTicker
function Party.ShareAll()
	if not IsInGroup() then
		StzxUI:Say("join a party first.")
		return 0
	end
	local queue = {}
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID and Plain(C_QuestLog.IsPushableQuest(info.questID)) then
			queue[#queue + 1] = info.questID
		end
	end
	if shareTicker then shareTicker:Cancel() end
	if #queue == 0 then
		StzxUI:Say("none of your quests can be shared.")
		return 0
	end
	StzxUI:Say(("sharing %d %s with your party."):format(#queue, #queue == 1 and "quest" or "quests"))
	-- One at a time: the game refuses shares sent too close together.
	Share(queue[1])
	local n = 1
	if #queue > 1 then
		shareTicker = C_Timer.NewTicker(SHARE_EVERY, function()
			n = n + 1
			Share(queue[n])
		end, #queue - 1)
	end
	return #queue
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local function Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 20)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function MakePanel(kind, parent, questIDFn)
	local p = CreateFrame("Frame", "StzxUIPartyQuests" .. kind, parent)
	p:SetSize(WIDTH, 40)
	p:SetPoint("TOPLEFT", parent, "TOPRIGHT", 6, -24)
	p:SetClampedToScreen(true)
	p:SetFrameStrata("HIGH")
	p.kind, p.questID = kind, questIDFn

	local bg = p:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.05, 0.07, 0.92)
	local line = p:CreateTexture(nil, "BORDER")
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	line:SetHeight(2)
	line:SetColorTexture(A.r, A.g, A.b, 1)

	p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	p.title:SetPoint("TOPLEFT", 8, -8)
	p.title:SetText("Party")
	p.title:SetTextColor(A.r, A.g, A.b)

	p.rows = {}
	for i = 1, 4 do
		local name = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		name:SetPoint("TOPLEFT", 8, -10 - i * ROW)
		name:SetJustifyH("LEFT")
		name:SetWidth(WIDTH - 80)
		local status = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		status:SetPoint("TOPRIGHT", -8, -10 - i * ROW)
		status:SetJustifyH("RIGHT")
		p.rows[i] = { name = name, status = status }
	end

	if kind == "log" then
		p.share = Button(p, "Share", 80, function() Share(p.questID()) end)
		p.share:SetPoint("BOTTOMLEFT", 8, 8)
		p.shareAll = Button(p, "Share all", 86, function() Party.ShareAll() end)
		p.shareAll:SetPoint("BOTTOMRIGHT", -8, 8)
	end

	p:SetScript("OnShow", function(self) Party.Refresh(self) end)
	panels[kind] = p
	return p
end

-- Fill a panel in (or hide it when there's nothing to show).
function Party.Refresh(p)
	local db = ns.Quests.db
	local questID = p.questID()
	if not (db.partyStatus and IsInGroup() and questID and questID > 0) then
		p:Hide()
		return
	end
	local shown = 0
	for i = 1, 4 do
		local unit = "party" .. i
		if Plain(UnitExists(unit)) then
			local status = Party.Status(unit, questID)
			shown = shown + 1
			local row = p.rows[shown]
			row.name:SetText(UnitName(unit))
			row.name:SetTextColor(ClassColour(unit))
			local text, colour = "?", OFF
			if status == "on" then
				text, colour = "On it", ON
			elseif status == "off" then
				text = "Not on it"
			elseif status == "offline" then
				text = "Offline"
			end
			row.status:SetText(text)
			row.status:SetTextColor(colour[1], colour[2], colour[3])
			row.name:Show()
			row.status:Show()
		end
	end
	for i = shown + 1, 4 do
		p.rows[i].name:Hide()
		p.rows[i].status:Hide()
	end
	local height = 30 + shown * ROW
	if p.share then
		p.share:SetEnabled(Plain(C_QuestLog.IsPushableQuest(questID)) == true)
		height = height + 28
	end
	p:SetHeight(height)
	p:Show()
end

function Party.RefreshAll()
	for _, p in pairs(panels) do
		if p:GetParent():IsVisible() then Party.Refresh(p) end
	end
end

function Party.SetUp()
	if QuestFrame then
		MakePanel("giver", QuestFrame, function() return GetQuestID and GetQuestID() end)
	end
	local details = QuestMapFrame and QuestMapFrame.DetailsFrame
	if details then
		MakePanel("log", details, function() return details.questID end)
	end
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_LOG_UPDATE",
		"QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
		pcall(events.RegisterEvent, events, event)
	end
	-- QUEST_LOG_UPDATE can come in bursts: refresh at most every half second.
	local pending = false
	events:SetScript("OnEvent", function()
		if pending then return end
		pending = true
		C_Timer.After(0.5, function()
			pending = false
			Party.RefreshAll()
		end)
	end)
	if QuestMapFrame_ShowQuestDetails then
		hooksecurefunc("QuestMapFrame_ShowQuestDetails", function() Party.RefreshAll() end)
	end
end

StzxUI.slashCommands.shareall = {
	help = "share every quest you can with your party",
	run = function() Party.ShareAll() end,
}

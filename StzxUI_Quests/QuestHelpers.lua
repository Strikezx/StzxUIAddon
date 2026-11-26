-- StzxUI Quests: quest helpers
--
--   Auto quests    accept quests when a quest giver offers them, and hand in
--                  finished ones, with no clicks. Hold Shift when you talk
--                  to the NPC to do it yourself. Never chooses between reward
--                  choices, never accepts PvP-flagging quests, never pays
--                  gold to hand in, and (option) skips grey quests.
--   Reward value   when you choose a reward, each choice shows what a vendor
--                  would pay for it; the most valuable gets a gold coin.
--
-- Only does what clicking the buttons would do.

local _, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local QuestHelpers = {}
ns.QuestHelpers = QuestHelpers

local function Paused() return IsShiftKeyDown() end

---------------------------------------------------------------------------
-- Auto accept and hand in
---------------------------------------------------------------------------

local function Trivial(questID)
	return C_QuestLog and C_QuestLog.IsQuestTrivial and questID and C_QuestLog.IsQuestTrivial(questID) or false
end

-- Quest giver's detail page: accept.
function QuestHelpers.OnDetail(db)
	if not db.autoAccept or Paused() then return end
	if QuestGetAutoAccept and QuestGetAutoAccept() then return end -- the game accepts those itself
	if QuestFlagsPVP and QuestFlagsPVP() then return end           -- flags you for PvP: your call
	if db.skipTrivial and Trivial(Plain(GetQuestID())) then return end
	AcceptQuest()
end

-- "Do you have the items?" page: complete when it can be.
function QuestHelpers.OnProgress(db)
	if not db.autoTurnIn or Paused() then return end
	if IsQuestCompletable() then CompleteQuest() end
end

-- Reward page: take the reward if there's no choice to make and nothing to pay.
function QuestHelpers.OnComplete(db)
	if not db.autoTurnIn or Paused() then return end
	local choices = GetNumQuestChoices() or 0
	if choices > 1 then return end
	if (GetQuestMoneyToGet() or 0) > 0 then return end
	GetQuestReward(choices == 1 and 1 or 0)
end

-- Gossip (an NPC with chat options): hand in a finished quest, else take a new one.
function QuestHelpers.OnGossip(db)
	if Paused() then return end
	if db.autoTurnIn then
		for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
			if Plain(quest.isComplete) and quest.questID then
				C_GossipInfo.SelectActiveQuest(quest.questID)
				return
			end
		end
	end
	if db.autoAccept then
		for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
			if quest.questID and not (db.skipTrivial and Plain(quest.isTrivial)) then
				C_GossipInfo.SelectAvailableQuest(quest.questID)
				return
			end
		end
	end
end

-- Old-style quest giver list (no chat options).
function QuestHelpers.OnGreeting(db)
	if Paused() then return end
	if db.autoTurnIn then
		for i = 1, (GetNumActiveQuests() or 0) do
			local _, isComplete = GetActiveTitle(i)
			if isComplete then
				SelectActiveQuest(i)
				return
			end
		end
	end
	if db.autoAccept then
		for i = 1, (GetNumAvailableQuests() or 0) do
			local isTrivial = GetAvailableQuestInfo(i)
			if not (db.skipTrivial and isTrivial) then
				SelectAvailableQuest(i)
				return
			end
		end
	end
end

---------------------------------------------------------------------------
-- Reward value
---------------------------------------------------------------------------

local GOLD_ICON = "Interface\\MoneyFrame\\UI-GoldIcon"
local marks = setmetatable({}, { __mode = "k" }) -- reward button -> { text, coin }

local function SellPrice(link)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not (getInfo and link) then return nil end
	return select(11, getInfo(link))
end

local function Mark(button)
	local m = marks[button]
	if m then return m end
	m = {}
	m.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
	m.coin = button:CreateTexture(nil, "OVERLAY")
	m.coin:SetTexture(GOLD_ICON)
	m.coin:SetSize(14, 14)
	m.coin:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3)
	marks[button] = m
	return m
end

local function HideMarks()
	for _, m in pairs(marks) do
		m.text:Hide()
		m.coin:Hide()
	end
end

-- Values of each reward choice: { [index] = copper } (nil where unknown yet), best index.
function QuestHelpers.ChoiceValues()
	local values, best, bestValue = {}, nil, 0
	for i = 1, (GetNumQuestChoices() or 0) do
		local _, _, count = GetQuestItemInfo("choice", i)
		local price = SellPrice(GetQuestItemLink("choice", i))
		if price then
			values[i] = price * math.max(1, count or 1)
			if values[i] > bestValue then best, bestValue = i, values[i] end
		end
	end
	return values, best
end

local retried = false
function QuestHelpers.ShowValues(db)
	HideMarks()
	if not db.rewardValue or not (QuestFrame and QuestFrame:IsShown()) or (GetNumQuestChoices() or 0) < 2 then return end
	local frame = QuestInfoFrame and QuestInfoFrame.rewardsFrame or _G.QuestInfoRewardsFrame
	if not (frame and frame.RewardButtons) then return end
	local values, best = QuestHelpers.ChoiceValues()
	local missing = false
	for _, button in ipairs(frame.RewardButtons) do
		if button.type == "choice" and button:IsShown() then
			local index = button:GetID()
			local m = Mark(button)
			if values[index] then
				m.text:SetText(GetCoinTextureString(values[index]))
				m.text:Show()
				m.coin:SetShown(index == best)
			else
				missing = true
			end
		end
	end
	-- Item details not loaded yet: look again in a moment (once).
	if missing and not retried then
		retried = true
		C_Timer.After(0.5, function() QuestHelpers.ShowValues(db) end)
	else
		retried = false
	end
end

---------------------------------------------------------------------------

function QuestHelpers.Settings(page, module)
	StzxUI:AddHeader(page, "Quest helpers")
	StzxUI:AddCheckbox(page, module, "autoAccept", "Accept quests automatically",
		"Takes quests when a quest giver offers them. Hold Shift when you talk to the NPC to choose yourself. "
		.. "Never accepts quests that flag you for PvP.")
	StzxUI:AddCheckbox(page, module, "autoTurnIn", "Hand in finished quests automatically",
		"Completes quests you've finished. Never picks between reward choices and never pays gold to hand in. "
		.. "Hold Shift to do it yourself.")
	StzxUI:AddCheckbox(page, module, "skipTrivial", "Not grey (low-level) quests",
		"Leaves quests far below your level for you to accept by hand.")
	StzxUI:AddCheckbox(page, module, "rewardValue", "Show what reward choices sell for",
		"Each reward choice shows its vendor price; the most valuable gets a gold coin.")
end

function QuestHelpers.Enable(module)
	local db = module.db
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING" }) do
		events:RegisterEvent(event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "QUEST_DETAIL" then QuestHelpers.OnDetail(db)
		elseif event == "QUEST_PROGRESS" then QuestHelpers.OnProgress(db)
		elseif event == "QUEST_COMPLETE" then QuestHelpers.OnComplete(db)
		elseif event == "GOSSIP_SHOW" then QuestHelpers.OnGossip(db)
		elseif event == "QUEST_GREETING" then QuestHelpers.OnGreeting(db)
		end
	end)
	if QuestInfo_Display then
		hooksecurefunc("QuestInfo_Display", function() QuestHelpers.ShowValues(db) end)
	end
end

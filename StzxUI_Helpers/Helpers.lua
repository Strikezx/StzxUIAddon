-- StzxUI Helpers: small things that save clicks every day
--
--   Vendor     sell grey items and repair when you open a merchant (guild
--              funds first if you like), with a line in chat saying what it did
--   Looting    the loot window empties at once (when auto loot is on)
--   NPC chat   an NPC with one chat option and no quests (flight master,
--              banker...) goes straight to it; hold Shift to see the chat
--   Errors     hides the red "Not enough mana", "Out of range"... errors that
--              repeat all through a fight (each kind can be kept on)
--   Bank fix   stops a Blizzard error (BankFrame.lua:43, FetchNumPurchasedBankTabs)
--              that fires when your gold changes after you've used the bank
--
-- Everything here only does what you could click yourself, out of combat
-- where the game requires it. Each has its own switch.

local ADDON_NAME, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local Helpers = StzxUI:NewModule("Helpers", ADDON_NAME, {
	sellGreys = true,      -- sell grey items at merchants
	repair = true,         -- repair at merchants that can
	repairGuild = false,   -- use guild bank funds first, when allowed
	vendorReport = true,   -- say in chat what was sold and spent
	fastLoot = true,       -- take all loot at once (auto loot)
	skipGossip = true,     -- one chat option, no quests: pick it
	errorFilter = true,    -- hide repeating combat errors
	bankMoneyFix = true,   -- stop Blizzard's bank money-display error
}, {
	title = "Helpers",
	description = "Sell greys and repair, faster looting, skip one-option NPC chat, quieter error messages.",
})
ns.Helpers = Helpers

local function Money(copper)
	return GetCoinTextureString and GetCoinTextureString(copper) or (("%dc"):format(copper))
end

---------------------------------------------------------------------------
-- Vendor: sell greys, repair
---------------------------------------------------------------------------

local BAGS = { 0, 1, 2, 3, 4 }
local SELL_PER_STEP, STEP = 10, 0.2 -- a few at a time: the server drops a flood
local POOR = 0 -- grey quality

local merchantOpen = false
local selling -- the ticker selling greys

local function SellPrice(itemID)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not (getInfo and itemID) then return 0 end
	return select(11, getInfo(itemID)) or 0
end

-- Grey items worth something: { { bag, slot, value }, ... }
function Helpers.GreyItems()
	local list = {}
	for _, bag in ipairs(BAGS) do
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and Plain(info.quality) == POOR and not Plain(info.hasNoValue) and not Plain(info.isLocked) then
				local value = SellPrice(Plain(info.itemID)) * (Plain(info.stackCount) or 1)
				if value > 0 then list[#list + 1] = { bag, slot, value } end
			end
		end
	end
	return list
end

local function SellGreys()
	if selling then return end
	local items = Helpers.GreyItems()
	if #items == 0 then return end
	local index, sold, earned = 1, 0, 0
	selling = C_Timer.NewTicker(STEP, function(ticker)
		for _ = 1, SELL_PER_STEP do
			local item = items[index]
			if not item or not merchantOpen then
				ticker:Cancel()
				selling = nil
				if sold > 0 and Helpers.db.vendorReport then
					StzxUI:Say(("sold %d grey item%s for %s."):format(sold, sold == 1 and "" or "s", Money(earned)))
				end
				return
			end
			index = index + 1
			C_Container.UseContainerItem(item[1], item[2])
			sold, earned = sold + 1, earned + item[3]
		end
	end)
end

local function Repair()
	if not (CanMerchantRepair and CanMerchantRepair()) then return end
	local cost, canRepair = GetRepairAllCost()
	cost = Plain(cost) or 0
	if not canRepair or cost <= 0 then return end
	local report = Helpers.db.vendorReport
	if Helpers.db.repairGuild and CanGuildBankRepair and CanGuildBankRepair() then
		RepairAllItems(true)
		if report then StzxUI:Say("repaired with guild funds for", Money(cost) .. ".") end
		return
	end
	if (Plain(GetMoney()) or 0) < cost then
		if report then StzxUI:Say("not enough gold to repair (" .. Money(cost) .. ").") end
		return
	end
	RepairAllItems(false)
	if report then StzxUI:Say("repaired for", Money(cost) .. ".") end
end

---------------------------------------------------------------------------
-- Faster looting
---------------------------------------------------------------------------

local lastLoot = 0

-- Auto loot on (or the key that flips it held): take every slot at once.
local function FastLoot()
	local auto = GetCVarBool("autoLootDefault")
	if IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") then auto = not auto end
	if not auto or GetTime() - lastLoot < 0.3 then return end
	lastLoot = GetTime()
	for slot = GetNumLootItems(), 1, -1 do LootSlot(slot) end
end

---------------------------------------------------------------------------
-- NPC chat with a single option
---------------------------------------------------------------------------

function Helpers.SkipGossip()
	if IsShiftKeyDown() or (C_GossipInfo.ForceGossip and C_GossipInfo.ForceGossip()) then return false end
	if (C_GossipInfo.GetNumAvailableQuests() or 0) > 0 or (C_GossipInfo.GetNumActiveQuests() or 0) > 0 then return false end
	local options = C_GossipInfo.GetOptions() or {}
	if #options ~= 1 or options[1].selectOptionWhenOnlyOption then return false end -- Blizzard picks those itself
	local index = Plain(options[1].orderIndex)
	if not index then return false end
	C_GossipInfo.SelectOptionByIndex(index)
	return true
end

---------------------------------------------------------------------------
-- Quieter errors
---------------------------------------------------------------------------
-- The red errors that repeat all through a fight. Blizzard's error frame has
-- a switch per kind of message; StzxUI turns these off (and back on).
local NOISY_ERRORS = {
	"LE_GAME_ERR_OUT_OF_MANA", "LE_GAME_ERR_OUT_OF_RAGE", "LE_GAME_ERR_OUT_OF_ENERGY", "LE_GAME_ERR_OUT_OF_FOCUS",
	"LE_GAME_ERR_OUT_OF_COMBO_POINTS", "LE_GAME_ERR_OUT_OF_RANGE", "LE_GAME_ERR_SPELL_OUT_OF_RANGE",
	"LE_GAME_ERR_SPELL_COOLDOWN", "LE_GAME_ERR_ABILITY_COOLDOWN", "LE_GAME_ERR_ITEM_COOLDOWN",
	"LE_GAME_ERR_SPELL_FAILED_ANOTHER_IN_PROGRESS", "LE_GAME_ERR_GENERIC_NO_VALID_TARGETS",
	"LE_GAME_ERR_NO_ATTACK_TARGET", "LE_GAME_ERR_INVALID_ATTACK_TARGET", "LE_GAME_ERR_GENERIC_NO_TARGET",
	"LE_GAME_ERR_BADATTACKFACING", "LE_GAME_ERR_BADATTACKPOS",
}

function Helpers.ApplyErrorFilter()
	local frame = _G.UIErrorsFrame
	if not (frame and frame.SetMessageTypeEnabled) then return end
	for _, name in ipairs(NOISY_ERRORS) do
		local messageType = _G[name]
		if messageType then frame:SetMessageTypeEnabled(messageType, not Helpers.db.errorFilter) end
	end
end

---------------------------------------------------------------------------
-- Blizzard's bank error
---------------------------------------------------------------------------
-- Forever's bank window has a small "cost of the next bank tab" money
-- display. It listens for every change to your gold, even while the bank is
-- closed, and then asks the bank which tab is open; with the bank closed the
-- answer is "none" and Blizzard's code errors (BankFrame.lua:43). While the
-- bank is closed StzxUI tells that one display to stop listening; Blizzard's
-- own code starts it listening again when the bank opens (its OnShow).

local function BankMoneyDisplay()
	local bank = _G.BankFrame
	return bank, bank and bank.BankPanel and bank.BankPanel.MoneyDisplay
end

function Helpers.QuietBankMoney()
	if not Helpers.db.bankMoneyFix then return end
	local bank, display = BankMoneyDisplay()
	if bank and display and display.UnregisterEvent and not bank:IsShown() then
		display:UnregisterEvent("PLAYER_MONEY")
	end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

function Helpers:OnInitialize()
	local page = StzxUI:AddSettingsPage("Helpers")
	StzxUI:AddHeader(page, "Merchants")
	StzxUI:AddCheckbox(page, self, "sellGreys", "Sell grey items",
		"When you open a merchant, your grey (junk) items are sold, a few at a time.")
	StzxUI:AddCheckbox(page, self, "repair", "Repair",
		"When you open a merchant who can repair, everything is repaired (if you have the gold).")
	StzxUI:AddCheckbox(page, self, "repairGuild", "Use guild funds first",
		"Repairs from the guild bank when your guild lets you.")
	StzxUI:AddCheckbox(page, self, "vendorReport", "Say what was sold and spent",
		"A line in chat after selling or repairing.")
	StzxUI:AddHeader(page, "Looting and NPCs")
	StzxUI:AddCheckbox(page, self, "fastLoot", "Faster looting",
		"With auto loot on, everything is taken at once, so the loot window barely shows.")
	StzxUI:AddCheckbox(page, self, "skipGossip", "Skip one-option NPC chat",
		"Flight masters, bankers and the like open their window straight away when they have one chat option "
		.. "and no quests. Hold Shift when you talk to them to see the chat.")
	StzxUI:AddHeader(page, "Errors")
	StzxUI:AddCheckbox(page, self, "errorFilter", "Hide repeating combat errors",
		"The red \"Not enough mana\", \"Out of range\", \"Not ready yet\" and similar messages that repeat "
		.. "through every fight. Other errors still show.", Helpers.ApplyErrorFilter)
	StzxUI:AddCheckbox(page, self, "bankMoneyFix", "Fix Blizzard's bank error",
		"Stops a Blizzard error (BankFrame.lua:43) that pops up when your gold changes after you've used the bank. "
		.. "Turning it off needs a reload.", function(on)
			if on then Helpers.QuietBankMoney() else StzxUI:AskReload() end
		end)
end

function Helpers:OnEnable()
	local db = self.db
	Helpers.ApplyErrorFilter()
	local events = CreateFrame("Frame")
	events:RegisterEvent("MERCHANT_SHOW")
	events:RegisterEvent("MERCHANT_CLOSED")
	events:RegisterEvent("LOOT_READY")
	events:RegisterEvent("GOSSIP_SHOW")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("BANKFRAME_CLOSED")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" or event == "BANKFRAME_CLOSED" then
			-- After Blizzard has closed its window (it hides on this same event).
			C_Timer.After(0, Helpers.QuietBankMoney)
			return
		end
		if event == "MERCHANT_SHOW" then
			merchantOpen = true
			if db.repair then Repair() end
			if db.sellGreys then SellGreys() end
		elseif event == "MERCHANT_CLOSED" then
			merchantOpen = false
		elseif event == "LOOT_READY" then
			if db.fastLoot then FastLoot() end
		elseif event == "GOSSIP_SHOW" then
			if db.skipGossip then Helpers.SkipGossip() end
		end
	end)
end

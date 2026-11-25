-- StzxUI Inventory: your items on every character
--
-- StzxUI notes what each of your characters carries:
--   bags      whenever they change
--   gear      what's equipped
--   bank      each time you open the bank (the game only shows it there)
--   account bank (shared by all your characters) the same way
--
-- Then:
--   * item tooltips get a line per character that has it:
--       Sorchawyn Ashvale: 12 (bags 2, bank 10)
--   * /stzx items opens a window to search everything (InventoryWindow.lua)
--
-- Saved for the whole account in StzxUIInventoryDB. Read-only: it never
-- moves or uses an item.

local ADDON_NAME, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local BAGS = { 0, 1, 2, 3, 4, 5 }                       -- backpack, four bags, reagent bag
local BANK = { 6, 7, 8, 9, 10, 11, 12, 13, 14 }          -- character bank tabs
local ACCOUNT_BANK = { 15, 16, 17, 18, 19, 20, 21, 22, 23 } -- account bank tabs
local EQUIPPED = 19                                     -- inventory slots 1-19
local ACCOUNT = "Account bank"

local Inventory = StzxUI:NewModule("Inventory", ADDON_NAME, {
	tooltips = true,
	tooltipThisCharacter = false, -- also list the character you're on
}, {
	title = "Inventory",
	description = "Remembers the bags, bank and gear of all your characters: tooltips say who else has an item; /stzx items searches them all.",
})
ns.Inventory = Inventory

---------------------------------------------------------------------------
-- Saved data: chars[name] = { class, updated, bags = {[id]=n}, bank = {...}, equipped = {...} }
---------------------------------------------------------------------------

function ns.Data()
	StzxUIInventoryDB = StzxUIInventoryDB or {}
	local db = StzxUIInventoryDB
	db.chars = db.chars or {}
	db.links = db.links or {} -- [itemID] = a link to show it with
	return db
end

local function MyName()
	local first, surname = UnitName("player")
	first, surname = Plain(first), Plain(surname)
	if not first then return nil end
	if surname and surname ~= "" then return first .. " " .. surname end
	return first
end
ns.MyName = MyName

local function Record(name)
	local chars = ns.Data().chars
	local r = chars[name] or {}
	chars[name] = r
	return r
end

-- Count every item in a list of containers.
local function Scan(containers)
	local counts, links = {}, ns.Data().links
	for _, bag in ipairs(containers) do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and Plain(info.itemID)
			if id then
				counts[id] = (counts[id] or 0) + (Plain(info.stackCount) or 1)
				links[id] = Plain(info.hyperlink) or links[id]
			end
		end
	end
	return counts
end

function ns.ScanBags()
	local me = MyName()
	if not me then return end
	local r = Record(me)
	local _, class = UnitClass("player")
	r.class, r.updated = Plain(class), time()
	r.bags = Scan(BAGS)
	local equipped = {}
	for slot = 1, EQUIPPED do
		local id = GetInventoryItemID("player", slot)
		if id then
			equipped[id] = (equipped[id] or 0) + 1
			local link = GetInventoryItemLink("player", slot)
			if link then ns.Data().links[id] = link end
		end
	end
	r.equipped = equipped
end

function ns.ScanBank()
	local me = MyName()
	if not me then return end
	local r = Record(me)
	r.bank, r.bankSeen = Scan(BANK), time()
	local account = Scan(ACCOUNT_BANK)
	if next(account) or not ns.Data().chars[ACCOUNT] then
		local a = Record(ACCOUNT)
		a.bank, a.bankSeen, a.account = account, time(), true
	end
end

---------------------------------------------------------------------------
-- Who has an item
---------------------------------------------------------------------------

-- { { name, class, total, bags, bank, equipped }, ... } sorted by total.
function ns.WhoHas(itemID)
	local list = {}
	for name, r in pairs(ns.Data().chars) do
		local bags = r.bags and r.bags[itemID] or 0
		local bank = r.bank and r.bank[itemID] or 0
		local equipped = r.equipped and r.equipped[itemID] or 0
		local total = bags + bank + equipped
		if total > 0 then
			list[#list + 1] = { name = name, class = r.class, total = total, bags = bags, bank = bank,
				equipped = equipped, account = r.account }
		end
	end
	table.sort(list, function(a, b)
		if a.total ~= b.total then return a.total > b.total end
		return a.name < b.name
	end)
	return list
end

-- "12 (bags 2, bank 10)"
function ns.Describe(entry)
	local parts = {}
	if entry.bags > 0 then parts[#parts + 1] = "bags " .. entry.bags end
	if entry.bank > 0 then parts[#parts + 1] = "bank " .. entry.bank end
	if entry.equipped > 0 then parts[#parts + 1] = "equipped" end
	if #parts == 1 and entry.equipped == 0 then
		return ("%d (%s)"):format(entry.total, parts[1]:match("^%a+"))
	end
	return ("%d (%s)"):format(entry.total, table.concat(parts, ", "))
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------

function ns.TooltipLines(itemID)
	local lines = {}
	if not (Inventory.db.tooltips and itemID) then return lines end
	local me = MyName()
	for _, entry in ipairs(ns.WhoHas(itemID)) do
		if entry.name ~= me or Inventory.db.tooltipThisCharacter then
			local c = entry.class and C_ClassColor and C_ClassColor.GetClassColor(entry.class)
			lines[#lines + 1] = { left = entry.name .. ":", right = ns.Describe(entry),
				r = c and c.r or 0.8, g = c and c.g or 0.8, b = c and c.b or 0.8 }
		end
	end
	return lines
end

local function AddToTooltip(tooltip, data)
	local id = data and Plain(data.id)
	if not id or tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	for _, line in ipairs(ns.TooltipLines(id)) do
		tooltip:AddDoubleLine(line.left, line.right, line.r, line.g, line.b, 1, 1, 1)
	end
end

---------------------------------------------------------------------------
-- Settings, events, command
---------------------------------------------------------------------------

function Inventory:OnInitialize()
	local page = StzxUI:AddSettingsPage("Inventory")
	StzxUI:AddHeader(page, "Your items on every character",
		"Bags and gear are noted as they change; the bank each time you open it. Log in on each character "
		.. "(and open its bank) once so StzxUI knows what it has.")
	StzxUI:AddCheckbox(page, self, "tooltips", "Item tooltips list who else has it", nil)
	StzxUI:AddCheckbox(page, self, "tooltipThisCharacter", "Include the character I'm on", nil)
	StzxUI:AddButton(page, "Search all characters", "Open", function() ns.OpenWindow() end, "/stzx items does the same.")
	StzxUI:AddButton(page, "Forget a character", "Choose",
		function()
			StzxUI:ShowDialog({
				title = "Forget a character",
				text = "Type the character's name exactly as listed (e.g. a deleted one).",
				input = "line",
				accept = "Forget",
				onAccept = function(text)
					text = (text or ""):match("^%s*(.-)%s*$")
					local chars = ns.Data().chars
					if not chars[text] then return false, "No character by that name is saved." end
					chars[text] = nil
					return true
				end,
			})
		end)
end

function Inventory:OnEnable()
	ns.Data()
	local bankOpen = false
	local pending = false
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
		"BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, bag)
		if event == "BANKFRAME_OPENED" then
			bankOpen = true
			ns.ScanBank()
		elseif event == "BANKFRAME_CLOSED" then
			bankOpen = false
		elseif event == "BAG_UPDATE" then
			-- Bank tabs change while it's open: rescan once things settle.
			if bankOpen and type(bag) == "number" and bag >= 6 and not pending then
				pending = true
				C_Timer.After(0.5, function() pending = false ns.ScanBank() end)
			end
		elseif event == "PLAYERBANKSLOTS_CHANGED" then
			if bankOpen then ns.ScanBank() end
		else
			ns.ScanBags()
		end
	end)
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddToTooltip)
	end
	ns.ScanBags()
end

StzxUI.slashCommands.items = {
	help = "search the items on all your characters",
	run = function(rest) ns.OpenWindow(rest) end,
}

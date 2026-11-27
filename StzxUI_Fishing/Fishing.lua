-- StzxUI Fishing
--   * Lure timer: while you hold a fishing pole, a small movable readout
--     shows the lure's time left ("Lure 4:32"), turning red in the last
--     30 seconds, with a sound when it runs out. "No lure" when there isn't one.
--   * Catch log: everything you fish up is counted per zone. Hover the
--     readout to see this zone's catches; /stzx fishing lists them in chat.
--   * Easy cast: while you hold a fishing pole, double right-click the world
--     to cast Fishing (out of combat). A single right-click still loots the
--     bobber. How: on the second click StzxUI briefly binds right-click to a
--     secure button that casts Fishing (the only way an addon may cast for
--     you), then takes the binding off again.
--   * Auto lure: when there's no lure on the pole, that double right-click
--     puts one on first (the best one you can use, or the weakest first if
--     you'd rather save the good ones); the next double right-click casts.
--   * Tackle box: hover the readout to see which lures you carry, how many,
--     and which your Fishing skill can use yet.
--
-- All from the game itself: the lure is a weapon enchant on the pole, and
-- the loot window says when loot came from fishing. The log is saved for
-- the whole account (StzxUIFishingDB), so every character adds to it.

local ADDON_NAME = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local A = StzxUI.ACCENT

local WEAPON, FISHING_POLE = 2, 20 -- item class and subclass
local MAIN_HAND = 16                -- inventory slot
local WARN_AT = 30                  -- seconds left when the timer turns red
local LURE_SOUND = 8959             -- the game's "raid warning" chime

local Fishing = StzxUI:NewModule("Fishing", ADDON_NAME, {
	lureTimer = true,
	lureSound = true,
	catchLog = true,
	easyCast = true,   -- double right-click to cast while holding a pole
	autoLure = true,   -- ...and put a lure on first when there's none
	lureChoice = "BEST", -- "BEST" (biggest bonus you can use) or "WEAKEST" (save the good ones)
}, {
	title = "Fishing",
	description = "A lure timer while you hold a fishing pole, and a log of what you catch in each zone.",
})

local function Data()
	StzxUIFishingDB = StzxUIFishingDB or {}
	StzxUIFishingDB.zones = StzxUIFishingDB.zones or {}
	return StzxUIFishingDB
end

---------------------------------------------------------------------------
-- Pole and lure
---------------------------------------------------------------------------

function Fishing.HoldingPole()
	local itemID = GetInventoryItemID("player", MAIN_HAND)
	if not itemID then return false end
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	return classID == WEAPON and subclassID == FISHING_POLE
end

-- Seconds of lure left on the pole, or nil for none.
function Fishing.LureLeft()
	local ok, enchants = pcall(C_Item.GetWeaponEnchantInfo, Enum.WeaponSlot.MainHand)
	if not ok or type(enchants) ~= "table" then return nil end
	for _, enchant in pairs(enchants) do
		local has, left = Plain(enchant.hasEnchant), Plain(enchant.timeLeft)
		if has and left then return left / 1000 end
	end
	return nil
end

---------------------------------------------------------------------------
-- Lures and the tackle box
---------------------------------------------------------------------------

-- Forever's lures: item, Fishing bonus, Fishing skill needed to use it.
local LURES = {
	{ id = 6529, name = "Shiny Bauble", bonus = 25, need = 1 },
	{ id = 6530, name = "Nightcrawlers", bonus = 50, need = 50 },
	{ id = 6811, name = "Aquadynamic Fish Lens", bonus = 50, need = 50 },
	{ id = 6532, name = "Bright Baubles", bonus = 75, need = 100 },
	{ id = 7307, name = "Flesh Eating Worm", bonus = 75, need = 100 },
	{ id = 6533, name = "Aquadynamic Fish Attractor", bonus = 100, need = 100 },
}
Fishing.LURES = LURES
local FISHING_SKILL = 356 -- skill line

-- Your Fishing skill (without bonuses), or nil if the game won't say.
function Fishing.Skill()
	if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then return nil end
	local info = C_SkillInfo.GetSkillLineInfoByID(FISHING_SKILL)
	return info and Plain(info.rank)
end

-- The lures in your bags: { { lure, count, usable }, ... } in LURES order.
function Fishing.TackleBox()
	local skill = Fishing.Skill() or 1
	local box = {}
	for _, lure in ipairs(LURES) do
		local count = Plain(C_Item.GetItemCount(lure.id)) or 0
		if count > 0 then box[#box + 1] = { lure = lure, count = count, usable = skill >= lure.need } end
	end
	return box
end

-- The lure to put on next (per the "which lure" setting), or nil for none.
function Fishing.PickLure()
	local pick
	for _, entry in ipairs(Fishing.TackleBox()) do
		if entry.usable then
			local better = not pick
			if pick and Fishing.db.lureChoice == "WEAKEST" then better = entry.lure.bonus < pick.bonus
			elseif pick then better = entry.lure.bonus > pick.bonus end
			if better then pick = entry.lure end
		end
	end
	return pick
end

-- A lure is wanted now: auto lure on, no lure on the pole, and one to use.
-- Never blocks casting: with no lure you can use, or if putting one on
-- didn't take (StzxUI tried in the last 20 seconds and the pole still has
-- none), the double right-click simply casts.
local LURE_RETRY = 20 -- seconds
local lureTriedAt
function Fishing.LureToApply()
	if not Fishing.db.autoLure or Fishing.LureLeft() then return nil end
	if lureTriedAt and GetTime() - lureTriedAt < LURE_RETRY then return nil end
	return Fishing.PickLure()
end

---------------------------------------------------------------------------
-- Easy cast
---------------------------------------------------------------------------

local FISHING_SPELLS = { 131474, 18248, 7732, 7731, 7620 } -- Fishing, highest rank first
local DOUBLE_CLICK = 0.4 -- seconds between the two right-clicks
local castButton
local lastRight = 0

function Fishing.FishingSpell()
	for _, id in ipairs(FISHING_SPELLS) do
		if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) then return id end
	end
	return nil
end

local function Unbind()
	if castButton and castButton.bound and not InCombatLockdown() then
		ClearOverrideBindings(castButton)
		castButton.bound = false
	end
end

-- After the click: only once the button is let go, so the release lands on
-- our button too (not on the camera's "stop turning").
local function AfterClick(_, _, down)
	if not down then Unbind() end
end

-- A right mouse press on the world (also used by the tests).
function Fishing.WorldRightClick()
	if not Fishing.db.easyCast or InCombatLockdown() or not Fishing.HoldingPole() then return false end
	if GameTooltip:IsShown() then -- the mouse is over the bobber (or something else to click)
		lastRight = 0
		return false
	end
	local now = GetTime()
	if now - lastRight > DOUBLE_CLICK then
		lastRight = now
		return false
	end
	lastRight = 0
	local lure = Fishing.LureToApply()
	if lure then
		-- Use the lure, then "use" the pole: the game's way to put a lure on it.
		lureTriedAt = GetTime()
		castButton:SetAttribute("type", "macro")
		castButton:SetAttribute("macrotext", ("/use item:%d\n/use %d"):format(lure.id, MAIN_HAND))
	else
		local spell = Fishing.FishingSpell()
		if not spell then return false end
		castButton:SetAttribute("type", "spell")
		castButton:SetAttribute("spell", spell)
	end
	SetOverrideBindingClick(castButton, true, "BUTTON2", "StzxUIFishingCast")
	castButton.bound = true
	C_Timer.After(1, Unbind) -- in case the click never reaches it
	return true
end

local function SetUpEasyCast()
	castButton = CreateFrame("Button", "StzxUIFishingCast", UIParent, "SecureActionButtonTemplate")
	castButton:RegisterForClicks("AnyUp", "AnyDown")
	-- Cast on the release, whatever "cast on key down" is set to: that works
	-- whether the game hands our button the whole click or only its release.
	castButton:SetAttribute("useOnKeyDown", false)
	castButton:SetScript("PostClick", AfterClick)
	-- A fight starting with right-click still ours: give it back just before
	-- the lockdown (PLAYER_REGEN_DISABLED comes first), and check again after.
	castButton:RegisterEvent("PLAYER_REGEN_DISABLED")
	castButton:RegisterEvent("PLAYER_REGEN_ENABLED")
	castButton:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_REGEN_DISABLED" then
			if self.bound then ClearOverrideBindings(self); self.bound = false end
		else
			Unbind()
		end
	end)
	WorldFrame:HookScript("OnMouseDown", function(_, button)
		if button == "RightButton" then Fishing.WorldRightClick() end
	end)
end

---------------------------------------------------------------------------
-- Catch log
---------------------------------------------------------------------------

local function Zone()
	return Plain(GetRealZoneText()) or "Unknown"
end

local sessionCatches = 0 -- everything fished up since you logged in
function Fishing.SessionCatches() return sessionCatches end

-- Count one catch: zones[zone] = { total = n, items = { [name] = { count, link } } }
function Fishing.AddCatch(zone, link, count)
	local name = link and link:match("%[(.-)%]")
	if not name then return end
	local zones = Data().zones
	local z = zones[zone] or { total = 0, items = {} }
	zones[zone] = z
	local item = z.items[name] or { count = 0 }
	z.items[name] = item
	item.count, item.link = item.count + (count or 1), link
	z.total = z.total + (count or 1)
	sessionCatches = sessionCatches + (count or 1)
end

-- This zone's catches, most common first: { { name, link, count, percent }, ... }
function Fishing.Catches(zone)
	local z = Data().zones[zone or Zone()]
	local list = {}
	if not z then return list, 0 end
	for name, item in pairs(z.items) do
		list[#list + 1] = { name = name, link = item.link, count = item.count,
			percent = math.floor(item.count / z.total * 100 + 0.5) }
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.name < b.name
	end)
	return list, z.total
end

local function ReadLoot()
	if not (Fishing.db.catchLog and IsFishingLoot and IsFishingLoot()) then return end
	local zone = Zone()
	for slot = 1, GetNumLootItems() do
		local link = Plain(GetLootSlotLink(slot))
		local _, _, quantity = GetLootSlotInfo(slot)
		if link then Fishing.AddCatch(zone, link, Plain(quantity) or 1) end
	end
end

---------------------------------------------------------------------------
-- The readout
---------------------------------------------------------------------------

local readout, warned

local function Clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(seconds / 60, seconds % 60)
end

function Fishing.ReadoutText()
	local left = Fishing.LureLeft()
	local _, total = Fishing.Catches()
	local text = left and ("Lure " .. Clock(left)) or "No lure"
	local upNext = not left and Fishing.LureToApply()
	if upNext and Fishing.db.easyCast then text = text .. " (" .. upNext.name .. " next)" end
	if total > 0 then text = text .. ("  %d caught here"):format(total) end
	return text, left
end

function Fishing:Update()
	if not readout then return end
	local show = self.db.lureTimer and Fishing.HoldingPole()
	readout:SetShown(show)
	if not show then
		warned = nil -- no chime for a lure that ran out while the pole was put away
		return
	end
	local text, left = Fishing.ReadoutText()
	readout.text:SetText(text)
	if left and left <= WARN_AT then
		readout.text:SetTextColor(1, 0.3, 0.3)
	else
		readout.text:SetTextColor(1, 1, 1)
	end
	-- A chime when a lure runs out (once per lure).
	if left and left > 1 then
		warned = false
	elseif not left and warned == false then
		warned = true
		if self.db.lureSound then PlaySound(LURE_SOUND, "Master") end
	end
end

local function ShowTooltip(frame)
	GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
	local list, total = Fishing.Catches()
	GameTooltip:AddLine(("Fishing in %s"):format(Zone()), A.r, A.g, A.b)
	if total == 0 then
		GameTooltip:AddLine("Nothing caught here yet.", 0.8, 0.8, 0.8)
	end
	for i, item in ipairs(list) do
		if i > 12 then break end
		GameTooltip:AddDoubleLine(item.link or item.name, ("%d  (%d%%)"):format(item.count, item.percent),
			1, 1, 1, 0.8, 0.8, 0.8)
	end
	if sessionCatches > 0 then
		GameTooltip:AddLine(("%d caught this session (all zones)"):format(sessionCatches), 0.8, 0.8, 0.8)
	end
	-- The tackle box.
	GameTooltip:AddLine(" ")
	local skill = Fishing.Skill()
	GameTooltip:AddDoubleLine("Tackle box", skill and ("Fishing " .. skill) or "", A.r, A.g, A.b, 0.8, 0.8, 0.8)
	local box = Fishing.TackleBox()
	if #box == 0 then GameTooltip:AddLine("No lures in your bags.", 0.8, 0.8, 0.8) end
	for _, entry in ipairs(box) do
		local right = ("+%d  x%d"):format(entry.lure.bonus, entry.count)
		if entry.usable then
			GameTooltip:AddDoubleLine(entry.lure.name, right, 1, 1, 1, 0.8, 0.8, 0.8)
		else
			GameTooltip:AddDoubleLine(entry.lure.name .. (" (needs Fishing %d)"):format(entry.lure.need), right,
				0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
		end
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Settings, start-up, command
---------------------------------------------------------------------------

function Fishing:OnInitialize()
	local page = StzxUI:AddSettingsPage("Fishing")
	local function Update() self:Update() end
	StzxUI:AddCheckbox(page, self, "lureTimer", "Show the lure timer while I hold a fishing pole",
		"A small readout you can move in move mode. Hover it to see what you've caught in this zone.", Update)
	StzxUI:AddCheckbox(page, self, "lureSound", "Chime when the lure runs out", nil)
	StzxUI:AddCheckbox(page, self, "catchLog", "Log what I catch in each zone",
		"Saved for all your characters. /stzx fishing lists this zone's catches.")
	StzxUI:AddCheckbox(page, self, "easyCast", "Double right-click to cast",
		"While you hold a fishing pole and aren't in a fight, double right-click the world to cast Fishing. "
		.. "A single right-click still loots the bobber.")
	StzxUI:AddCheckbox(page, self, "autoLure", "Put a lure on first when there's none",
		"With double right-click casting: if your pole has no lure and you carry one you can use, the double "
		.. "right-click puts it on (a few seconds), and the next one casts. Hover the lure timer to see your "
		.. "tackle box.", Update)
	StzxUI:AddDropdown(page, self, "lureChoice", "Which lure",
		"Which lure to put on when you carry more than one.",
		{ { "BEST", "The best one I can use" }, { "WEAKEST", "The weakest first (save the good ones)" } }, Update)
	StzxUI:AddButton(page, "Clear the catch log", "Clear", function()
		StzxUI:ShowDialog({
			title = "Clear catch log",
			text = "Forget every catch in every zone?",
			accept = "Clear",
			onAccept = function() wipe(Data().zones) self:Update() return true end,
		})
	end)
end

function Fishing:OnEnable()
	Data()
	SetUpEasyCast()
	readout = CreateFrame("Frame", "StzxUIFishing", UIParent)
	readout:SetSize(200, 20)
	readout.text = readout:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	readout.text:SetPoint("CENTER")
	readout.text:SetShadowOffset(1, -1)
	readout:EnableMouse(true)
	readout:SetScript("OnEnter", ShowTooltip)
	readout:SetScript("OnLeave", function() GameTooltip:Hide() end)
	readout:Hide()
	StzxUI:RegisterMover("Fishing", readout, {
		label = "Fishing: lure timer",
		category = "Info",
		default = { "CENTER", "CENTER", 0, 160 },
		isShown = function() return self.db.lureTimer end,
	})

	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "LOOT_READY",
		"ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "LOOT_READY" then ReadLoot() end
		self:Update()
	end)
	C_Timer.NewTicker(1, function() self:Update() end)
	self:Update()
end

StzxUI.slashCommands.fishing = {
	help = "list what you've caught in this zone",
	run = function()
		local box = {}
		for _, entry in ipairs(Fishing.TackleBox()) do
			box[#box + 1] = ("%s x%d%s"):format(entry.lure.name, entry.count, entry.usable and "" or " (can't use yet)")
		end
		StzxUI:Say("tackle box:", #box > 0 and table.concat(box, ", ") or "no lures")
		local list, total = Fishing.Catches()
		if total == 0 then
			StzxUI:Say(("nothing caught in %s yet."):format(Zone()))
			return
		end
		StzxUI:Say(("%d caught in %s:"):format(total, Zone()))
		for i, item in ipairs(list) do
			if i > 10 then break end
			StzxUI:Say(("  %s x%d (%d%%)"):format(item.link or item.name, item.count, item.percent))
		end
	end,
}

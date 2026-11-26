-- StzxUI core: your characters
-- A short note on each character you play, kept for the whole account so
-- other characters can use it: the gold readout's tooltip (all characters'
-- gold) and the "send to your alts" list beside Send Mail.
--
-- Saved in StzxUIDB.characters (account-wide, not part of any profile):
--   ["Strikezx Kincrag"] = { class = "WARLOCK", faction = "Alliance", level = 18, money = 123456, updated = time() }
-- Names are "First Surname" (Forever's two-part names: mail needs both).

local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local function Store()
	StzxUIDB = StzxUIDB or {}
	StzxUIDB.characters = StzxUIDB.characters or {}
	return StzxUIDB.characters
end

-- "First Surname" for the character you're on (nil if the game won't say).
function StzxUI:MyCharacterName()
	local first, surname = UnitName("player")
	first, surname = Plain(first), Plain(surname)
	if not first then return nil end
	if surname and surname ~= "" then return first .. " " .. surname end
	return first
end

-- Note the character you're on now (at login, and when gold or level change).
function StzxUI:NoteCharacter()
	local name = self:MyCharacterName()
	if not name then return end
	local chars = Store()
	local entry = chars[name] or {}
	chars[name] = entry
	entry.class = Plain(select(2, UnitClass("player"))) or entry.class
	entry.faction = Plain(UnitFactionGroup("player")) or entry.faction
	entry.level = Plain(UnitLevel("player")) or entry.level
	entry.money = Plain(GetMoney()) or entry.money
	entry.updated = time()
end

-- Every character noted, sorted by name: { { name = , class = , faction = , level = , money = }, ... }.
-- opts.faction: only that faction's. opts.others: leave out the one you're on.
function StzxUI:Characters(opts)
	opts = opts or {}
	local me = self:MyCharacterName()
	local list = {}
	for name, entry in pairs(Store()) do
		if type(entry) == "table" and not (opts.others and name == me)
			and not (opts.faction and entry.faction and entry.faction ~= opts.faction) then
			list[#list + 1] = { name = name, class = entry.class, faction = entry.faction, level = entry.level,
				money = entry.money or 0 }
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

-- Forget a character (deleted, or renamed).
function StzxUI:ForgetCharacter(name)
	Store()[name] = nil
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function() StzxUI:NoteCharacter() end)

-- StzxUI Helpers: world PvP (enemies nearby, kill-on-sight)
--
--   Enemies nearby   a small list of enemy players you've seen in the last
--                    couple of minutes: name, level, class (coloured), how
--                    long ago. Seen = their nameplate shows, you target them
--                    or put your mouse over them. Shift-click a name to put it
--                    in chat; right-click it to add it to (or take it off)
--                    your kill-on-sight list.
--   Kill-on-sight    your own list of names. When one is seen: a warning in
--                    the middle of the screen, a sound and a chat line (at
--                    most once a minute per name), and their tooltip says so.
--                    /stzx kos add Name Surname, /stzx kos remove ..., or the
--                    button on the World PvP page to edit the whole list.
--
-- Forever note: in fights and PvP the game can hide players' names and
-- classes from addons. StzxUI only notes what the game shows it (StzxUI.Plain),
-- so some enemies may only appear once things calm down. No combat log:
-- StzxUI can't tell who killed you.
--
-- The list is saved for the whole account in StzxUIWorldPvPDB.

local ADDON_NAME, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local Skin = StzxUI.Skin

local WorldPvP = StzxUI:NewModule("WorldPvP", ADDON_NAME, {
	nearby = true,       -- the enemies nearby list
	recent = 120,        -- seconds an enemy stays on the list
	newSound = false,    -- a sound when a new enemy appears
	kos = true,          -- kill-on-sight alerts
	kosSound = true,     -- ...with a sound
}, {
	title = "World PvP",
	description = "Enemy players seen nearby, and your kill-on-sight list with alerts.",
})
ns.WorldPvP = WorldPvP

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local MAX_ROWS, ROW = 10, 16
local ALERT_EVERY = 60 -- seconds between alerts for the same name

local seen = {}       -- lower-case name -> { name, level, class, guild, last }
local alerted = {}    -- lower-case name -> GetTime() of the last alert
local panel

local function Data()
	StzxUIWorldPvPDB = StzxUIWorldPvPDB or {}
	StzxUIWorldPvPDB.kos = StzxUIWorldPvPDB.kos or {}
	return StzxUIWorldPvPDB
end

local function Key(name) return name and (name:lower():match("^%s*(.-)%s*$")) end

---------------------------------------------------------------------------
-- Kill-on-sight list
---------------------------------------------------------------------------

-- Is this name on the list? A name saved without a surname matches any surname.
function WorldPvP.OnList(name)
	if not name then return nil end
	local kos = Data().kos
	local key = Key(name)
	if kos[key] then return kos[key] end
	local first = key:match("^(%S+)")
	local entry = kos[first]
	if entry and not entry.name:find(" ") then return entry end
	return nil
end

function WorldPvP.Add(name, note)
	name = name and name:match("^%s*(.-)%s*$")
	if not name or name == "" then return false end
	Data().kos[Key(name)] = { name = name, note = note, added = time() }
	return true
end

function WorldPvP.Remove(name)
	local key = Key(name or "")
	if not Data().kos[key] then return false end
	Data().kos[key] = nil
	return true
end

-- The list's names, sorted.
function WorldPvP.Names()
	local names = {}
	for _, entry in pairs(Data().kos) do names[#names + 1] = entry.name end
	table.sort(names)
	return names
end

local function Alert(entry, info)
	local key = Key(entry.name)
	if alerted[key] and GetTime() - alerted[key] < ALERT_EVERY then return end
	alerted[key] = GetTime()
	local text = ("Kill on sight: %s%s"):format(info.name, info.level and (" (" .. info.level .. ")") or "")
	StzxUI:Warn(text, 1, 0.2, 0.2)
	if WorldPvP.db.kosSound and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
	StzxUI:Say(("|cffff4040%s|r spotted%s."):format(text, entry.note and (" (" .. entry.note .. ")") or ""))
end

---------------------------------------------------------------------------
-- Enemies nearby
---------------------------------------------------------------------------

-- Note an enemy player if the game shows us who they are (also used by the tests).
function WorldPvP.Note(unit)
	if not (unit and UnitExists(unit)) then return nil end
	if not Plain(UnitIsPlayer(unit)) or not Plain(UnitIsEnemy("player", unit)) then return nil end
	local first, surname = UnitName(unit)
	first, surname = Plain(first), Plain(surname)
	if not first or first == "" then return nil end
	local name = (surname and surname ~= "") and (first .. " " .. surname) or first
	local key = Key(name)
	local isNew = not seen[key] or GetTime() - seen[key].last > WorldPvP.db.recent
	local info = seen[key] or {}
	info.name = name
	info.level = Plain(UnitLevel(unit)) or info.level
	info.class = Plain(select(2, UnitClass(unit))) or info.class
	info.guild = (GetGuildInfo and Plain((GetGuildInfo(unit)))) or info.guild
	info.last = GetTime()
	seen[key] = info
	local entry = WorldPvP.db.kos and WorldPvP.OnList(name)
	if entry then Alert(entry, info) end
	if isNew and WorldPvP.db.newSound and not entry and PlaySound and SOUNDKIT and SOUNDKIT.UI_BNET_TOAST then
		PlaySound(SOUNDKIT.UI_BNET_TOAST)
	end
	WorldPvP.Update()
	return info
end

-- Enemies seen recently, newest first.
function WorldPvP.Recent()
	local list = {}
	for _, info in pairs(seen) do
		if GetTime() - info.last <= WorldPvP.db.recent then list[#list + 1] = info end
	end
	table.sort(list, function(a, b) return a.last > b.last end)
	return list
end

local function Ago(seconds)
	if seconds < 60 then return ("%ds"):format(math.floor(seconds)) end
	return ("%dm"):format(math.floor(seconds / 60))
end

local function ClassCode(class)
	local colour = class and C_ClassColor and C_ClassColor.GetClassColor(class)
	if not colour then return "|cffffffff" end
	return ("|cff%02x%02x%02x"):format(colour.r * 255, colour.g * 255, colour.b * 255)
end

function WorldPvP.Update()
	if not panel then return end
	local list = WorldPvP.db.nearby and WorldPvP.Recent() or {}
	if #list == 0 then
		panel:Hide()
		return
	end
	panel.title:SetText(("Enemies nearby (%d)"):format(#list))
	local shown = math.min(#list, MAX_ROWS)
	for i = 1, MAX_ROWS do
		local row = panel.rows[i]
		local info = list[i]
		if i <= shown then
			row.info = info
			local mark = WorldPvP.OnList(info.name) and "|cffff4040KoS|r " or ""
			row.name:SetText(mark .. ClassCode(info.class) .. info.name .. "|r")
			row.level:SetText((info.level and info.level > 0) and info.level or "??")
			row.ago:SetText(Ago(GetTime() - info.last))
			row:Show()
		else
			row:Hide()
		end
	end
	panel:SetHeight(shown * ROW + 28)
	panel:Show()
end

local function RowClick(row, button)
	local info = row.info
	if not info then return end
	if button == "RightButton" then
		if WorldPvP.OnList(info.name) then
			WorldPvP.Remove(info.name)
			StzxUI:Say(info.name, "is off your kill-on-sight list.")
		else
			WorldPvP.Add(info.name)
			StzxUI:Say(info.name, "is on your kill-on-sight list.")
		end
		WorldPvP.Update()
	elseif IsShiftKeyDown() and ChatEdit_InsertLink then
		ChatEdit_InsertLink(info.name)
	end
end

local function Build()
	panel = CreateFrame("Frame", "StzxUIEnemiesNearby", UIParent)
	panel:SetSize(220, 60)
	panel:SetFrameStrata("MEDIUM")
	Skin.Backdrop(panel, { edge = "accent", fill = { 0, 0, 0 }, alpha = 0.75 })
	panel.title = panel:CreateFontString(nil, "OVERLAY")
	panel.title:SetFont(FONT, 12, "")
	panel.title:SetPoint("TOPLEFT", 8, -6)
	panel.title:SetTextColor(1, 0.35, 0.35)
	panel.rows = {}
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Button", nil, panel)
		row:SetSize(204, ROW)
		row:SetPoint("TOPLEFT", 8, -6 - i * ROW)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.name = row:CreateFontString(nil, "OVERLAY")
		row.name:SetFont(FONT, 11, "")
		row.name:SetPoint("LEFT")
		row.name:SetWidth(140)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.level = row:CreateFontString(nil, "OVERLAY")
		row.level:SetFont(FONT, 11, "")
		row.level:SetPoint("LEFT", 146, 0)
		row.ago = row:CreateFontString(nil, "OVERLAY")
		row.ago:SetFont(FONT, 11, "")
		row.ago:SetPoint("RIGHT")
		row.ago:SetTextColor(0.6, 0.6, 0.6)
		local hover = row:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.06)
		row:SetScript("OnClick", RowClick)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local info = self.info
			GameTooltip:AddLine(info.name, 1, 1, 1)
			if info.guild then GameTooltip:AddLine("<" .. info.guild .. ">", 0.7, 0.7, 0.7) end
			GameTooltip:AddLine("Right-click: add to / take off your kill-on-sight list", 0.6, 0.6, 0.6)
			GameTooltip:AddLine("Shift-click: put the name in chat", 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:Hide()
		panel.rows[i] = row
	end
	panel:Hide()
	StzxUI:RegisterMover("EnemiesNearby", panel, {
		label = "Enemies nearby",
		category = "Helpers",
		default = { "RIGHT", "RIGHT", -260, 120 },
		isShown = function() return WorldPvP.db.nearby end,
	})
end

---------------------------------------------------------------------------
-- Editing the list
---------------------------------------------------------------------------

function WorldPvP.EditList()
	StzxUI:ShowDialog({
		title = "Kill-on-sight list",
		text = "One name per line (\"First Surname\", or just the first name to match any surname).",
		input = "box",
		value = table.concat(WorldPvP.Names(), "\n"),
		accept = "Save",
		onAccept = function(text)
			local keep = {}
			for line in (text or ""):gmatch("[^\r\n]+") do
				local name = line:match("^%s*(.-)%s*$")
				if name ~= "" then keep[Key(name)] = name end
			end
			local kos = Data().kos
			for key in pairs(kos) do if not keep[key] then kos[key] = nil end end
			for key, name in pairs(keep) do
				if not kos[key] then kos[key] = { name = name, added = time() } end
			end
			WorldPvP.Update()
			return true
		end,
	})
end

-- Player tooltips: "Kill on sight" in red.
local function OnUnitTooltip(tooltip)
	if not WorldPvP.db.kos or tooltip ~= GameTooltip then return end
	local _, unit = tooltip:GetUnit()
	unit = Plain(unit)
	if not unit or not Plain(UnitIsPlayer(unit)) then return end
	local first, surname = UnitName(unit)
	first, surname = Plain(first), Plain(surname)
	if not first then return end
	local entry = WorldPvP.OnList((surname and surname ~= "") and (first .. " " .. surname) or first)
	if entry then tooltip:AddLine("Kill on sight" .. (entry.note and (": " .. entry.note) or ""), 1, 0.25, 0.25) end
end

---------------------------------------------------------------------------

function WorldPvP:OnInitialize()
	local page = StzxUI:AddSettingsPage("World PvP")
	StzxUI:AddHeader(page, "Enemies nearby")
	StzxUI:AddCheckbox(page, self, "nearby", "Show enemy players nearby",
		"A small list of enemy players you've seen (their nameplate, your target or your mouse). "
		.. "Right-click a name for your kill-on-sight list. Place it in move mode.", WorldPvP.Update)
	StzxUI:AddSlider(page, self, "recent", "Keep them on the list for", nil, 30, 600, 30,
		function(value) return value < 60 and (value .. " s") or (("%d min"):format(value / 60)) end, WorldPvP.Update)
	StzxUI:AddCheckbox(page, self, "newSound", "A sound when a new enemy appears", nil)
	StzxUI:AddHeader(page, "Kill on sight")
	StzxUI:AddCheckbox(page, self, "kos", "Warn me when someone on my list is seen",
		"A warning in the middle of the screen and a chat line (once a minute per name), and \"Kill on sight\" "
		.. "on their tooltip.")
	StzxUI:AddCheckbox(page, self, "kosSound", "...with a sound", nil)
	StzxUI:AddButton(page, "Your kill-on-sight list", "Edit", WorldPvP.EditList,
		"One name per line. Also /stzx kos add Name Surname and /stzx kos remove Name Surname.")
end

function WorldPvP:OnEnable()
	Build()
	local events = CreateFrame("Frame")
	events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	events:RegisterEvent("PLAYER_TARGET_CHANGED")
	events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	events:SetScript("OnEvent", function(_, event, unit)
		if not (self.db.nearby or self.db.kos) then return end
		if event == "PLAYER_TARGET_CHANGED" then unit = "target" elseif event == "UPDATE_MOUSEOVER_UNIT" then unit = "mouseover" end
		WorldPvP.Note(unit)
	end)
	-- Ages tick, and names drop off the list.
	C_Timer.NewTicker(5, WorldPvP.Update)
	if TooltipDataProcessor and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
	end
end

StzxUI.slashCommands.kos = {
	help = "your kill-on-sight list: \"/stzx kos add Name\", \"/stzx kos remove Name\", or just /stzx kos to edit it",
	run = function(arg)
		local verb, name = (arg or ""):match("^(%S*)%s*(.-)%s*$")
		verb = verb:lower()
		if verb == "add" and name ~= "" then
			WorldPvP.Add(name)
			StzxUI:Say(name, "is on your kill-on-sight list.")
		elseif (verb == "remove" or verb == "del") and name ~= "" then
			if WorldPvP.Remove(name) then StzxUI:Say(name, "is off your kill-on-sight list.")
			else StzxUI:Say(name, "isn't on your kill-on-sight list.") end
		else
			WorldPvP.EditList()
		end
		WorldPvP.Update()
	end,
}

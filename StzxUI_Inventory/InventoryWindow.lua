-- StzxUI Inventory: the search window (/stzx items [words])
--
--   Items on all characters                                  [x]
--   [search............]                       3 characters saved
--   [icon] Copper Ore           18   Sorchawyn 12, Wrenzx 6
--   [icon] Linen Cloth          40   Account bank 40
--   ...
-- Hover a row for the item's tooltip (with who has it). Mouse wheel scrolls.

local _, ns = ...
local StzxUI = _G.StzxUI
local A = StzxUI.ACCENT

local WIDTH, ROWS, ROW_HEIGHT = 560, 14, 24
local window
local offset = 0
local results = {}

local function NameOf(id)
	local link = ns.Data().links[id]
	return link and link:match("%[(.-)%]") or ("item " .. id)
end

-- Every item on any character matching the words, most copies first.
function ns.Search(text)
	text = (text or ""):lower():match("^%s*(.-)%s*$")
	local seen, list = {}, {}
	for _, r in pairs(ns.Data().chars) do
		for _, place in ipairs({ r.bags or {}, r.bank or {}, r.equipped or {} }) do
			for id in pairs(place) do
				if not seen[id] then
					seen[id] = true
					local name = NameOf(id)
					if text == "" or name:lower():find(text, 1, true) then
						local who = ns.WhoHas(id)
						local total = 0
						for _, entry in ipairs(who) do total = total + entry.total end
						list[#list + 1] = { id = id, name = name, total = total, who = who }
					end
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a.total ~= b.total then return a.total > b.total end
		return a.name < b.name
	end)
	return list
end

function ns.WhoText(who)
	local parts = {}
	for _, entry in ipairs(who) do
		parts[#parts + 1] = ("%s %d"):format(entry.name:match("^(%S+)") or entry.name, entry.total)
	end
	return table.concat(parts, ", ")
end

local function Fill()
	for i, row in ipairs(window.rows) do
		local item = results[offset + i]
		row.item = item
		if item then
			row.icon:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.id) or 134400)
			row.name:SetText(ns.Data().links[item.id] or item.name)
			row.total:SetText(item.total)
			row.who:SetText(ns.WhoText(item.who))
			row:Show()
		else
			row:Hide()
		end
	end
	local count = 0
	for _ in pairs(ns.Data().chars) do count = count + 1 end
	window.status:SetText(("%d items  -  %d characters saved"):format(#results, count))
end

function ns.RefreshWindow()
	if not (window and window:IsShown()) then return end
	results = ns.Search(window.search:GetText())
	offset = 0
	Fill()
end

local function Build()
	local f = CreateFrame("Frame", "StzxUIItems", UIParent)
	f:SetSize(WIDTH, 92 + ROWS * ROW_HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	table.insert(UISpecialFrames, "StzxUIItems")

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.06, 0.08, 0.96)
	local line = f:CreateTexture(nil, "BORDER")
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	line:SetHeight(2)
	line:SetColorTexture(A.r, A.g, A.b, 1)
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText("Items on all characters")
	title:SetTextColor(A.r, A.g, A.b)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	f.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	f.search:SetSize(220, 22)
	f.search:SetPoint("TOPLEFT", 18, -40)
	f.search:SetAutoFocus(false)
	f.search:SetScript("OnTextChanged", function() ns.RefreshWindow() end)
	f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.status:SetPoint("TOPRIGHT", -14, -46)

	f.rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, f)
		row:SetSize(WIDTH - 24, ROW_HEIGHT - 2)
		row:SetPoint("TOPLEFT", 12, -70 - (i - 1) * ROW_HEIGHT)
		row:EnableMouse(true)
		local shade = row:CreateTexture(nil, "BACKGROUND")
		shade:SetAllPoints()
		shade:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
		row.icon:SetPoint("LEFT", 2, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.name:SetWidth(210)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.total = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.total:SetPoint("LEFT", 240, 0)
		row.total:SetWidth(40)
		row.total:SetJustifyH("RIGHT")
		row.who = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.who:SetPoint("LEFT", 292, 0)
		row.who:SetWidth(WIDTH - 24 - 296)
		row.who:SetJustifyH("LEFT")
		row.who:SetWordWrap(false)
		row:SetScript("OnEnter", function(self)
			local link = self.item and ns.Data().links[self.item.id]
			if not link then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(link)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.rows[i] = row
	end
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, math.min(math.max(0, #results - ROWS), offset - delta * 3))
		Fill()
	end)
	return f
end

function ns.OpenWindow(text)
	window = window or Build()
	ns.ScanBags()
	window:Show()
	window.search:SetText(text or "")
	ns.RefreshWindow()
end

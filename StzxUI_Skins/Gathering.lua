-- StzxUI Tooltip: gathering skill needed
--
-- Hover a herb, an ore vein or a skinnable corpse and the tooltip says the
-- skill it needs, coloured by your own skill the way the game colours
-- recipes: red (can't yet), orange, yellow, green, grey (no more skill-ups).
--   herbs and ore   by the node's name (the classic nodes; English names)
--   skinning        by the creature's level (level x 5 from 21 up; below,
--                   (level - 10) x 10, at least 1)
-- Out of combat only (tooltip text is hidden from addons in a fight).

local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local Tooltip = StzxUI:GetModule("Tooltip")

local MINING, HERBALISM, SKINNING = 186, 182, 393 -- skill line IDs
local SKILL_NAMES = { [MINING] = "Mining", [HERBALISM] = "Herbalism", [SKINNING] = "Skinning" }

local NODES = {
	-- Mining
	["Copper Vein"] = { MINING, 1 }, ["Tin Vein"] = { MINING, 65 }, ["Incendicite Mineral Vein"] = { MINING, 65 },
	["Silver Vein"] = { MINING, 75 }, ["Ooze Covered Silver Vein"] = { MINING, 75 },
	["Lesser Bloodstone Deposit"] = { MINING, 75 }, ["Iron Deposit"] = { MINING, 125 },
	["Indurium Mineral Vein"] = { MINING, 150 }, ["Gold Vein"] = { MINING, 155 }, ["Ooze Covered Gold Vein"] = { MINING, 155 },
	["Mithril Deposit"] = { MINING, 175 }, ["Ooze Covered Mithril Deposit"] = { MINING, 175 },
	["Truesilver Deposit"] = { MINING, 230 }, ["Ooze Covered Truesilver Deposit"] = { MINING, 230 },
	["Dark Iron Deposit"] = { MINING, 230 }, ["Small Thorium Vein"] = { MINING, 245 },
	["Ooze Covered Thorium Vein"] = { MINING, 245 }, ["Rich Thorium Vein"] = { MINING, 275 },
	["Ooze Covered Rich Thorium Vein"] = { MINING, 275 }, ["Hakkari Thorium Vein"] = { MINING, 275 },
	["Small Obsidian Chunk"] = { MINING, 305 }, ["Large Obsidian Chunk"] = { MINING, 305 },
	-- Herbalism
	["Peacebloom"] = { HERBALISM, 1 }, ["Silverleaf"] = { HERBALISM, 1 }, ["Earthroot"] = { HERBALISM, 15 },
	["Mageroyal"] = { HERBALISM, 50 }, ["Briarthorn"] = { HERBALISM, 70 }, ["Stranglekelp"] = { HERBALISM, 85 },
	["Bruiseweed"] = { HERBALISM, 100 }, ["Wild Steelbloom"] = { HERBALISM, 115 }, ["Grave Moss"] = { HERBALISM, 120 },
	["Kingsblood"] = { HERBALISM, 125 }, ["Liferoot"] = { HERBALISM, 150 }, ["Fadeleaf"] = { HERBALISM, 160 },
	["Goldthorn"] = { HERBALISM, 170 }, ["Khadgar's Whisker"] = { HERBALISM, 185 }, ["Wintersbite"] = { HERBALISM, 195 },
	["Firebloom"] = { HERBALISM, 205 }, ["Purple Lotus"] = { HERBALISM, 210 }, ["Arthas' Tears"] = { HERBALISM, 220 },
	["Sungrass"] = { HERBALISM, 230 }, ["Blindweed"] = { HERBALISM, 235 }, ["Ghost Mushroom"] = { HERBALISM, 245 },
	["Gromsblood"] = { HERBALISM, 250 }, ["Golden Sansam"] = { HERBALISM, 260 }, ["Dreamfoil"] = { HERBALISM, 270 },
	["Mountain Silversage"] = { HERBALISM, 280 }, ["Plaguebloom"] = { HERBALISM, 285 }, ["Icecap"] = { HERBALISM, 290 },
	["Black Lotus"] = { HERBALISM, 300 },
}
Tooltip.GATHER_NODES = NODES

-- Your rank in a skill line (nil if you don't have it).
function Tooltip.SkillRank(skillID)
	-- By ID first: works even with the Professions header folded up in the skills list.
	if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
		local info = C_SkillInfo.GetSkillLineInfoByID(skillID)
		local rank = info and Plain(info.rank)
		if rank then return rank end
	end
	if not (C_SkillInfo and C_SkillInfo.GetNumSkillLines) then return nil end
	for i = 1, C_SkillInfo.GetNumSkillLines() do
		local info = C_SkillInfo.GetSkillLineInfo(i)
		if info and Plain(info.skillID) == skillID then return Plain(info.rank) end
	end
	return nil
end

-- The colour for a skill you have against what's needed (the recipe colours).
function Tooltip.SkillColour(rank, need)
	if not rank then return 0.8, 0.8, 0.8 end
	if rank < need then return 1, 0.1, 0.1 end
	if rank < need + 25 then return 1, 0.5, 0.25 end
	if rank < need + 50 then return 1, 1, 0 end
	if rank < need + 100 then return 0.25, 0.75, 0.25 end
	return 0.5, 0.5, 0.5
end

-- Skinning skill a creature of this level needs.
function Tooltip.SkinningNeeded(level)
	if level > 20 then return level * 5 end
	return math.max(1, (level - 10) * 10)
end

local function AddNeed(tooltip, skillID, need)
	tooltip:AddLine(("Requires %s %d"):format(SKILL_NAMES[skillID], need), Tooltip.SkillColour(Tooltip.SkillRank(skillID), need))
end

local function FirstLine(tooltip, data)
	local line = data and data.lines and data.lines[1]
	local text = line and Plain(line.leftText)
	if text then return text end
	local name = tooltip.GetName and tooltip:GetName()
	local region = name and _G[name .. "TextLeft1"]
	return region and Plain(region:GetText())
end

-- Herb and ore nodes (world objects).
function Tooltip.OnObject(tooltip, data)
	if not Tooltip.db.gathering or InCombatLockdown() then return end
	local node = NODES[FirstLine(tooltip, data) or ""]
	if node then AddNeed(tooltip, node[1], node[2]) end
end

-- Skinnable corpses: the tooltip has Blizzard's "Skinnable" line.
function Tooltip.SkinningLine(tooltip, unit)
	if not Tooltip.db.gathering or InCombatLockdown() or not Plain(UnitIsDead(unit)) then return end
	local skinnable = _G.UNIT_SKINNABLE_LEATHER or "Skinnable"
	local name = tooltip.GetName and tooltip:GetName()
	if not name then return end
	for i = 2, tooltip:NumLines() do
		local region = _G[name .. "TextLeft" .. i]
		if region and Plain(region:GetText()) == skinnable then
			local level = Plain(UnitLevel(unit))
			if level and level > 0 then AddNeed(tooltip, SKINNING, Tooltip.SkinningNeeded(level)) end
			return
		end
	end
end

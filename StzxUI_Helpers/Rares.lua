-- StzxUI Helpers: rare and treasure alerts
--
-- A warning in the middle of the screen, a sound and a chat line when:
--   * a rare (or rare elite) creature's nameplate appears near you, or
--   * the game puts a rare, treasure or event marker on your minimap
--     (Blizzard's "vignettes"; whether Forever marks its rares this way is
--     for the game to show: the nameplate check works either way)
-- Each one alerts once (again after 5 minutes). Dead rares are skipped.

local ADDON_NAME, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain

local Rares = StzxUI:NewModule("Rares", ADDON_NAME, {
	rares = true,      -- rare creatures
	treasures = true,  -- treasure markers
	sound = true,
}, {
	title = "Rare Alerts",
	description = "A warning when a rare creature or a treasure is near.",
})
ns.Rares = Rares

local AGAIN_AFTER = 300 -- seconds before the same one alerts again
local NORMAL = 0        -- Enum.VignetteType.Normal: rares (and some event markers, which have no rare name)
local TREASURE = 3      -- Enum.VignetteType.Treasure
local alerted = {}      -- key -> GetTime()

-- Alert once per key (also used by the tests). Returns true if it alerted.
function Rares.Alert(key, kind, name, level)
	if not key or not name or name == "" then return false end
	if alerted[key] and GetTime() - alerted[key] < AGAIN_AFTER then return false end
	alerted[key] = GetTime()
	local text = ("%s: %s%s"):format(kind, name, level and level > 0 and (" (" .. level .. ")") or "")
	StzxUI:Warn(text, 1, 0.82, 0.25)
	if Rares.db.sound and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
	StzxUI:Say("|cffffd166" .. text .. "|r nearby.")
	return true
end

-- A nameplate: rare or rare elite, alive.
function Rares.CheckUnit(unit)
	if not Rares.db.rares or not unit then return false end
	local class = Plain(UnitClassification(unit))
	if class ~= "rare" and class ~= "rareelite" then return false end
	if Plain(UnitIsDead(unit)) or Plain(UnitIsPlayer(unit)) then return false end
	local name = Plain(UnitName(unit))
	local key = Plain(UnitGUID(unit)) or name
	return Rares.Alert(key, class == "rareelite" and "Rare elite" or "Rare", name, Plain(UnitLevel(unit)))
end

-- A minimap marker.
function Rares.CheckVignette(guid)
	if not (guid and C_VignetteInfo and C_VignetteInfo.GetVignetteInfo) then return false end
	local info = C_VignetteInfo.GetVignetteInfo(guid)
	if not info or Plain(info.isDead) or not Plain(info.onMinimap) then return false end
	local kind = Plain(info.type)
	if kind ~= NORMAL and kind ~= TREASURE then return false end -- PvP bounties and the like
	local isTreasure = kind == TREASURE
	if isTreasure and not Rares.db.treasures then return false end
	if not isTreasure and not Rares.db.rares then return false end
	return Rares.Alert(Plain(info.vignetteID) and ("v" .. Plain(info.vignetteID) .. ":" .. tostring(Plain(info.objectGUID)))
		or guid, isTreasure and "Treasure" or "Rare", Plain(info.name))
end

local function CheckAllVignettes()
	if not (C_VignetteInfo and C_VignetteInfo.GetVignettes) then return end
	for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do Rares.CheckVignette(guid) end
end

function Rares:OnInitialize()
	local page = StzxUI:AddSettingsPage("Rare Alerts")
	StzxUI:AddCheckbox(page, self, "rares", "Warn me about rare creatures",
		"When a rare or rare elite's nameplate appears, or the game marks a rare on your minimap. Once each, "
		.. "again after 5 minutes. Nameplates need to be on to see them.")
	StzxUI:AddCheckbox(page, self, "treasures", "Warn me about treasures",
		"When the game marks a treasure on your minimap (if Forever marks them).")
	StzxUI:AddCheckbox(page, self, "sound", "Play a sound", nil)
end

function Rares:OnEnable()
	local events = CreateFrame("Frame")
	events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	events:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
	events:RegisterEvent("VIGNETTES_UPDATED")
	events:SetScript("OnEvent", function(_, event, arg)
		if event == "NAME_PLATE_UNIT_ADDED" then
			Rares.CheckUnit(arg)
		elseif event == "VIGNETTE_MINIMAP_UPDATED" then
			Rares.CheckVignette(arg)
		else
			CheckAllVignettes()
		end
	end)
end

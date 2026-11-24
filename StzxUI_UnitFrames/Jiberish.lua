-- StzxUI Unit Frames: optional JiberishUI Icons support
-- If the separate "Jiberish Fabled Icons" addon is installed, its class and
-- race icon styles appear as extra portrait choices. StzxUI never ships or
-- copies those icons: it asks the installed addon for them through its own
-- public table (JiberishIcons) and function (GetUnitIcon). Without the
-- addon, those choices simply don't show and frames use the class icon.
--
-- JiberishUI Icons is (c) JiberishUI, LLC; the icon art belongs to its artists.

local _, ns = ...

local PREFIX = "JI:" -- portrait setting values look like "JI:fabledrealm"

-- The installed addon's main object, or nil.
local function Jiberish()
	local engine = _G.JiberishIcons
	local JI = type(engine) == "table" and engine[1]
	if type(JI) == "table" and JI.GetUnitIcon and type(JI.mergedStylePacks) == "table" then
		return JI
	end
end

-- Extra portrait choices: { { "JI:fabled", "Jiberish: Fabled" }, ... }
function ns.JiberishStyles()
	local JI, list = Jiberish(), {}
	if not JI then return list end
	for _, kind in ipairs({ "class", "race" }) do
		local group = JI.mergedStylePacks[kind]
		if type(group) == "table" and type(group.styles) == "table" then
			for key, data in pairs(group.styles) do
				local name = type(data) == "table" and data.name or key
				table.insert(list, { PREFIX .. key, ("Jiberish: %s%s"):format(name, kind == "race" and " (race)" or "") })
			end
		end
	end
	table.sort(list, function(a, b) return a[2] < b[2] end)
	return list
end

-- The style name inside a portrait setting, or nil if it isn't a Jiberish one.
function ns.JiberishStyleOf(mode)
	return type(mode) == "string" and mode:match("^" .. PREFIX .. "(.+)$") or nil
end

-- Put the unit's Jiberish icon on `texture`. Returns true if it did; false
-- for NPCs (no class) or when the addon isn't there or has no such style.
function ns.ApplyJiberishIcon(texture, unit, style)
	local JI = Jiberish()
	if not JI then return false end
	local ok, icon, path = pcall(JI.GetUnitIcon, JI, unit, style)
	if not ok or type(icon) ~= "table" or type(icon.texCoords) ~= "table" or not path then
		return false
	end
	texture:SetTexture(path)
	texture:SetTexCoord(unpack(icon.texCoords))
	return true
end

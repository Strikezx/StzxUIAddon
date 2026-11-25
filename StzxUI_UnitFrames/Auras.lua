-- StzxUI Unit Frames: buffs and debuffs
-- Small aura icons above (or below) the player and target frames: debuffs
-- first, nearest the frame, then buffs. Each icon shows a duration swipe and
-- a stack count; debuffs get a border in their type's colour.
--
-- Forever note: in combat the game hides aura details from addons ("secret"
-- values). Everything here only *shows* them:
--   * the list comes from C_UnitAuras.GetUnitAuras (the game does the filtering,
--     including "only my debuffs", so it still works in combat)
--   * icons: Texture:SetTexture accepts secret textures
--   * swipe: out of combat from the plain times; in combat the game's own
--     duration object goes straight into the cooldown swipe
--   * stacks: the game's own count text (GetAuraApplicationDisplayCount)

local _, ns = ...
local StzxUI = _G.StzxUI
local Auras = StzxUI.Auras -- the icons themselves live in the core (StzxUI/Auras.lua)

-- Shared with the party and raid frames (Group.lua).
ns.GetAuras = Auras.Get
ns.CreateAuraButton = Auras.Create
ns.SizeAuraButton = Auras.Size
ns.SetAuraButton = Auras.Set
local GetAuras, CreateButton, SizeButton = Auras.Get, Auras.Create, Auras.Size

function ns.UpdateAuras(frame)
	local container, settings, unit = frame.auraContainer, frame.settings, frame.unit
	if not container then return end
	local size = settings.auraSize or 24
	local SPACING = settings.auraSpacing or 1
	local left = frame.side == "LEFT"
	local above = settings.auraPosition ~= "BELOW"
	local perRow = math.max(1, math.floor((frame.dims.width + SPACING) / (size + SPACING)))

	-- Where the icons start: just outside the frame, on the portrait's side.
	container:ClearAllPoints()
	if above then
		container:SetPoint(left and "BOTTOMLEFT" or "BOTTOMRIGHT", frame, left and "TOPLEFT" or "TOPRIGHT", 0, 4)
	else
		container:SetPoint(left and "TOPLEFT" or "TOPRIGHT", frame, left and "BOTTOMLEFT" or "BOTTOMRIGHT", 0, -4)
	end

	local groups = {}
	if settings.showDebuffs then
		local filter = (settings.onlyMine and unit ~= "player") and "HARMFUL|PLAYER" or "HARMFUL"
		table.insert(groups, { harmful = true, auras = GetAuras(unit, filter) })
	end
	if settings.showBuffs then
		table.insert(groups, { harmful = false, auras = GetAuras(unit, "HELPFUL") })
	end

	local used, row, col = 0, 0, 0
	local side = left and "LEFT" or "RIGHT"
	local direction = left and 1 or -1
	for _, group in ipairs(groups) do
		if col > 0 then row, col = row + 1, 0 end -- each group starts on a new row
		for _, aura in ipairs(group.auras) do
			used = used + 1
			local button = container.buttons[used]
			if not button then
				button = CreateButton(container)
				container.buttons[used] = button
			end
			SizeButton(button, size)
			button:ClearAllPoints()
			local x, y = col * (size + SPACING) * direction, row * (size + SPACING)
			if above then
				button:SetPoint("BOTTOM" .. side, container, "BOTTOM" .. side, x, y)
			else
				button:SetPoint("TOP" .. side, container, "TOP" .. side, x, -y)
			end
			ns.SetAuraButton(button, unit, aura, group.harmful)
			col = col + 1
			if col >= perRow then row, col = row + 1, 0 end
		end
	end
	for i = used + 1, #container.buttons do
		container.buttons[i]:Hide()
	end
end

function ns.CreateAuraContainer(frame)
	local container = CreateFrame("Frame", nil, frame)
	container:SetSize(frame.dims.width, 1)
	container.buttons = {}
	frame.auraContainer = container
	frame:RegisterUnitEvent("UNIT_AURA", frame.unit)
	return container
end

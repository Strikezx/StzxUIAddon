-- StzxUI Skins: Blizzard's buff bar and Cooldown Manager in StzxUI's look
--
-- In a fight the game refuses addons every unit's auras (tested on Forever),
-- even your own, so StzxUI can't draw your buffs itself then. Blizzard's own
-- displays can, because Blizzard's code may read them:
--   * the buff and debuff bar (by the minimap; Edit Mode places it)
--   * the Cooldown Manager: tracked buffs (icons and bars) and cooldowns
-- Here they get StzxUI's look: square, cropped icons with a thin edge (debuffs
-- edged in their type's colour where the game lets us see it, red if not),
-- no round masks or gold rings, flat bars. Only looks change: Blizzard still
-- fills them in and lays them out, so they always work, fights included.

local StzxUI = _G.StzxUI
local Skin = StzxUI.Skin
local Plain = StzxUI.Plain
local Skins = StzxUI:GetModule("Skins")

local FLAT = "Interface\\Buttons\\WHITE8x8"
local styled = setmetatable({}, { __mode = "k" }) -- buttons / items already done
local edgeOf = setmetatable({}, { __mode = "k" }) -- Blizzard's debuff border -> its button
local dispelOf = setmetatable({}, { __mode = "k" }) -- aura button -> its debuff type (nil: none or hidden)

-- Debuff edges by type (as on StzxUI's own icons); untyped or hidden: red.
local DEBUFF_COLOURS = {
	Magic = { 0.20, 0.60, 1.00 },
	Curse = { 0.60, 0.00, 1.00 },
	Disease = { 0.60, 0.40, 0.00 },
	Poison = { 0.00, 0.60, 0.00 },
}
local DEBUFF_DEFAULT = { 0.80, 0.00, 0.00 }
local ENCHANT = { 0.60, 0.20, 0.90 } -- weapon enchants (poisons, oils)

local function Crop(icon)
	if icon and icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
end

-- Blizzard's round mask off an icon: square again.
local function Unmask(icon)
	if not (icon and icon.GetNumMaskTextures) then return end
	for i = icon:GetNumMaskTextures(), 1, -1 do
		local mask = icon:GetMaskTexture(i)
		if mask then icon:RemoveMaskTexture(mask) end
	end
end

-- A 1-pixel edge round `icon`, behind it on `host`.
local function Edge(host, icon)
	local edge = host:CreateTexture(nil, "BACKGROUND", nil, -8)
	edge:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(0, 0, 0, 1)
	return edge
end

-- The Cooldown Manager's gold ring (an unnamed texture with this atlas).
local RING = "UI-HUD-CoolDownManager-IconOverlay"
local function HideRings(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetAtlas and region:GetAtlas() == RING then region:SetAlpha(0) end
	end
end

---------------------------------------------------------------------------
-- The buff and debuff bar
---------------------------------------------------------------------------

-- After Blizzard fills a button in: the edge in the right colour.
local function PaintAuraButton(button)
	local edge = styled[button]
	if type(edge) ~= "table" then return end
	local colour = { 0, 0, 0 }
	if button.auraType == "Debuff" or button.auraType == "DeadlyDebuff" then
		colour = DEBUFF_COLOURS[dispelOf[button] or ""] or DEBUFF_DEFAULT
	elseif button.auraType == "TempEnchant" then
		colour = ENCHANT
	end
	edge:SetColorTexture(colour[1], colour[2], colour[3], 1)
end

local function StyleAuraButton(button)
	if styled[button] or not button.Icon or button.isAuraAnchor then return end
	Crop(button.Icon)
	styled[button] = Edge(button, button.Icon)
	if button.DebuffBorder then
		button.DebuffBorder:SetAlpha(0)
		edgeOf[button.DebuffBorder] = button
	end
	if button.TempEnchantBorder then button.TempEnchantBorder:SetAlpha(0) end
	if button.Update then hooksecurefunc(button, "Update", PaintAuraButton) end
	PaintAuraButton(button)
end

local function StyleAuraFrame(frame)
	if not (frame and frame.auraFrames) then return end
	for _, button in ipairs(frame.auraFrames) do StyleAuraButton(button) end
end

-- Blizzard sets a debuff's border by its type: note the type (if the game
-- shows it to us) for our edge. Hidden (secret) types stay red.
local borderHooked = false
local function HookDebuffTypes()
	if borderHooked or not (AuraUtil and AuraUtil.SetAuraBorderAtlas) then return end
	borderHooked = true
	hooksecurefunc(AuraUtil, "SetAuraBorderAtlas", function(border, dispelType)
		local button = edgeOf[border]
		if button then dispelOf[button] = Plain(dispelType) end
	end)
end

---------------------------------------------------------------------------
-- The Cooldown Manager
---------------------------------------------------------------------------

local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }

local function StyleItem(item)
	if styled[item] then return end
	styled[item] = true
	-- Icon items hold the picture as .Icon; bar items hold it one level down.
	local host, icon = item, item.Icon
	if icon and icon.GetObjectType and icon:GetObjectType() ~= "Texture" then host, icon = icon, icon.Icon end
	if icon then
		Unmask(icon)
		Crop(icon)
		Edge(host, icon)
	end
	HideRings(item)
	if host ~= item then HideRings(host) end
	if item.Cooldown and item.Cooldown.SetSwipeTexture then item.Cooldown:SetSwipeTexture(FLAT) end
	if item.Bar and item.Bar.GetStatusBarTexture then Skin.StatusBar(item.Bar) end
end

local function StyleViewer(viewer)
	if not viewer or styled[viewer] or not viewer.itemFramePool then return end
	styled[viewer] = true
	for item in viewer.itemFramePool:EnumerateActive() do StyleItem(item) end
	-- New items as Blizzard makes them (when you change what it tracks).
	if viewer.OnAcquireItemFrame then
		hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, item) StyleItem(item) end)
	end
end

---------------------------------------------------------------------------

function Skins.SkinBlizzardAuras()
	if not Skins.db.auras then return end
	HookDebuffTypes()
	StyleAuraFrame(_G.BuffFrame)
	StyleAuraFrame(_G.DebuffFrame)
	for _, name in ipairs(VIEWERS) do StyleViewer(_G[name]) end
end

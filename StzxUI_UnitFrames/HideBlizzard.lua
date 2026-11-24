-- StzxUI Unit Frames: hiding Blizzard's player and target frames
-- When StzxUI's frames replace Blizzard's, Blizzard's are switched off: they
-- stop listening to events and are tucked inside a hidden parent, so nothing
-- Blizzard does can show them again. This only happens out of combat (the
-- player and target frames are protected), and only for frames StzxUI has
-- replaced. Turning the option off brings them back after a reload.

local _, ns = ...

local hiddenParent
local waiting = {}

local function Tuck(frame)
	if not frame or frame.stzxHidden then return end
	if InCombatLockdown() then
		waiting[frame] = true
		return
	end
	hiddenParent = hiddenParent or CreateFrame("Frame", nil, UIParent)
	hiddenParent:Hide()
	frame:UnregisterAllEvents()
	frame:Hide()
	frame:SetParent(hiddenParent)
	frame.stzxHidden = true
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
	for frame in pairs(waiting) do
		waiting[frame] = nil
		Tuck(frame)
	end
end)

-- which: "player", "target", "focus", "pet" or "targettarget"
function ns.HideBlizzardFrames(which)
	if which == "player" then
		Tuck(_G.PlayerFrame)
		Tuck(_G.PlayerCastingBarFrame)
	elseif which == "target" then
		Tuck(_G.TargetFrame)
		Tuck(_G.TargetFrameSpellBar)
	elseif which == "focus" then
		Tuck(_G.FocusFrame)
		Tuck(_G.FocusFrameSpellBar)
	elseif which == "pet" then
		Tuck(_G.PetFrame)
	elseif which == "targettarget" then
		Tuck(_G.TargetFrameToT)
	end
end

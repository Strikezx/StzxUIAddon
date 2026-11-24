-- StzxUI Unit Frames: cast bar (player or target)
--
--   [icon][====== Holy Light ================ 1.2 ]
--
-- Each cast bar is its own movable frame. It listens to the unit's spellcast
-- events and fills from the cast's start and end times.
--
-- Forever note: in some situations the game makes cast times "secret". The
-- bar can still be given secret start/end times (SetMinMaxValues accepts
-- them) and fill correctly, but we can't do maths with them, so the
-- countdown text is left blank then.

local _, ns = ...
local StzxUI = _G.StzxUI
local Plain = StzxUI.Plain
local Style = ns.Style
local A = StzxUI.ACCENT

local FADE_TIME = 0.4  -- seconds to fade out after a cast ends
local HOLD_FAILED = 0.6 -- seconds "Interrupted" stays up before fading

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) or false
end

-- Show a cast or channel that is already under way (or just started).
local function Begin(bar, channel)
	local unit = bar.unit
	local name, _, texture, startMS, endMS, notInterruptible
	if channel then
		name, _, texture, startMS, endMS, _, notInterruptible = UnitChannelInfo(unit)
	else
		local castID
		name, _, texture, startMS, endMS, _, castID, notInterruptible = UnitCastingInfo(unit)
		bar.castID = castID
	end
	if not IsSecret(name) and not name then return false end

	bar.channel = channel
	bar.active = true
	bar.fading = nil
	bar:SetAlpha(1)
	bar.text:SetText(name)
	pcall(bar.icon.SetTexture, bar.icon, texture)

	local locked = not IsSecret(notInterruptible) and notInterruptible
	local colour = locked and Style.CAST.locked or A
	bar.bar:SetStatusBarColor(colour.r, colour.g, colour.b)
	bar.bar.bg:SetVertexColor(colour.r * 0.22, colour.g * 0.22, colour.b * 0.22, 0.9)

	local start, finish = Plain(startMS), Plain(endMS)
	if start and finish then
		-- Normal: we know the times, so we can count down.
		bar.startTime, bar.endTime = start / 1000, finish / 1000
		bar.secretTimes = false
		bar.bar:SetMinMaxValues(0, math.max(bar.endTime - bar.startTime, 0.001))
	else
		-- Secret times: let the bar do the work, no countdown text.
		bar.secretTimes = true
		bar.bar:SetMinMaxValues(startMS, endMS)
		bar.time:SetText("")
	end
	bar:Show()
	return true
end

-- Cast finished (or stopped): fade out.
local function Finish(bar)
	if not bar.active then return end
	bar.active = false
	if not bar.secretTimes then
		bar.bar:SetMinMaxValues(0, 1)
		bar.bar:SetValue(bar.channel and 0 or 1)
	end
	bar.time:SetText("")
	bar.fading = FADE_TIME
end

-- Cast failed or interrupted: red, the reason, then fade.
local function Fail(bar, reason)
	if not bar.active then return end
	bar.active = false
	local red = Style.CAST.failed
	bar.bar:SetMinMaxValues(0, 1)
	bar.bar:SetValue(1)
	bar.bar:SetStatusBarColor(red.r, red.g, red.b)
	bar.text:SetText(reason)
	bar.time:SetText("")
	bar.fading = FADE_TIME + HOLD_FAILED
end

local function OnUpdate(bar, elapsed)
	if bar.active then
		local now = GetTime()
		if bar.secretTimes then
			bar.bar:SetValue(now * 1000)
		else
			local total = bar.endTime - bar.startTime
			local done = math.min(math.max(now - bar.startTime, 0), total)
			-- Casts fill up; channels drain.
			bar.bar:SetValue(bar.channel and (total - done) or done)
			bar.time:SetFormattedText("%.1f", math.max(bar.endTime - now, 0))
		end
	elseif bar.fading then
		bar.fading = bar.fading - elapsed
		if bar.fading <= 0 then
			bar.fading = nil
			bar:Hide()
		elseif bar.fading < FADE_TIME then
			bar:SetAlpha(bar.fading / FADE_TIME)
		end
	end
end

-- Pick up whatever the unit is casting right now (new target, login, settings).
function ns.RefreshCastBar(bar)
	if not bar then return end
	bar.active, bar.fading = false, nil
	bar:Hide()
	if not bar.enabled() then return end
	if not Begin(bar, false) then Begin(bar, true) end
end

local function OnEvent(bar, event, unit, castID)
	if not bar.enabled() then return end
	if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
		ns.RefreshCastBar(bar)
	elseif event == "UNIT_SPELLCAST_START" then
		Begin(bar, false)
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		Begin(bar, true)
	elseif event == "UNIT_SPELLCAST_DELAYED" then
		if bar.active and not bar.channel then Begin(bar, false) end
	elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		if bar.active and bar.channel then Begin(bar, true) end
	elseif event == "UNIT_SPELLCAST_STOP" then
		-- Ignore the stop of an older cast after a new one started.
		local sameCast = IsSecret(castID) or IsSecret(bar.castID) or castID == bar.castID
		if bar.active and not bar.channel and sameCast then Finish(bar) end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if bar.active and bar.channel then Finish(bar) end
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
		Fail(bar, "Interrupted")
	elseif event == "UNIT_SPELLCAST_FAILED" then
		local sameCast = IsSecret(castID) or IsSecret(bar.castID) or castID == bar.castID
		if not bar.channel and sameCast then Fail(bar, "Failed") end
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		if bar.active then
			local colour = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" and Style.CAST.locked or A
			bar.bar:SetStatusBarColor(colour.r, colour.g, colour.b)
		end
	end
end

-- enabled: function returning whether this cast bar is switched on.
function ns.CreateCastBar(unit, globalName, enabled)
	local bar = CreateFrame("Frame", globalName, UIParent)
	bar:SetSize(Style.CAST_WIDTH, Style.CAST_HEIGHT)
	bar:SetFrameStrata("MEDIUM")
	bar.unit, bar.enabled = unit, enabled
	bar:Hide()

	-- Square spell icon on the left, then the bar.
	bar.icon = bar:CreateTexture(nil, "ARTWORK")
	bar.icon:SetPoint("TOPLEFT")
	bar.icon:SetSize(Style.CAST_HEIGHT, Style.CAST_HEIGHT)
	bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon border

	local holder = CreateFrame("Frame", nil, bar)
	holder:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 2, 0)
	holder:SetPoint("BOTTOMRIGHT")
	Style.Panel(holder)
	bar.bar = Style.Bar(holder, Style.CAST_HEIGHT)
	bar.bar:SetAllPoints()
	local iconEdge = bar:CreateTexture(nil, "BACKGROUND")
	iconEdge:SetPoint("TOPLEFT", bar.icon, -1, 1)
	iconEdge:SetPoint("BOTTOMRIGHT", bar.icon, 1, -1)
	iconEdge:SetColorTexture(0, 0, 0, 0.9)

	bar.text = Style.Text(bar.bar, 11)
	bar.text:SetPoint("LEFT", 6, 0)
	bar.text:SetPoint("RIGHT", -40, 0)
	bar.text:SetJustifyH("LEFT")
	bar.time = Style.Text(bar.bar, 11)
	bar.time:SetPoint("RIGHT", -6, 0)

	for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
		"UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
		"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do
		bar:RegisterUnitEvent(event, unit)
	end
	bar:RegisterEvent("PLAYER_ENTERING_WORLD")
	if unit == "target" then bar:RegisterEvent("PLAYER_TARGET_CHANGED") end
	bar:SetScript("OnEvent", OnEvent)
	bar:SetScript("OnUpdate", OnUpdate)
	return bar
end

-- StzxUI: starter layouts
--
-- Ready-made setups a new StzxUI user can start from, on the Profiles page:
--
--   * a StzxUI profile string: one click adds it as a new profile (your own
--     profiles stay as they are) and switches to it;
--   * a Blizzard Edit Mode layout string: shown in a box to copy into Edit
--     Mode's own Import. StzxUI doesn't write Edit Mode layouts itself:
--     changing Edit Mode from addon code can "taint" it and cause "action
--     blocked" errors in fights, and Blizzard's Import is the safe way in.
--
-- To update a layout: export it again (/stzx > Profiles > Export; Edit Mode >
-- Layout > Share > Copy to Clipboard) and replace its string below.

local StzxUI = _G.StzxUI

StzxUI.STARTER_LAYOUTS = {
	{
		by = "Strikezx",
		screen = "2560x1440",
		profileName = "Strikezx's StzxUI layout",
		editModeName = "Strikezx's EditMode layout",
		profile = [==[!STZX1!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]==],
		editMode = [==[5 0 59 0 0 0 4 4 UIParent 0.0 -552.5 -1 ##$$%/&&'%)$+#,$ 0 1 0 8 2 MainActionBar 0.0 4.0 -1 ##$$%/&&'%(#,$ 0 2 0 8 2 MultiBarBottomLeft 0.0 4.0 -1 ##$$%/&&'%(#,$ 0 3 0 4 4 UIParent 300.0 -520.8 -1 ##$&%/&%'%(#,$ 0 4 0 4 4 UIParent -300.0 -519.2 -1 ##$&%/&%'%(#,$ 0 5 1 1 4 UIParent 0.0 0.0 -1 ##$$%/&('%(#,$ 0 6 1 1 4 UIParent 0.0 -50.0 -1 ##$$%/&('%(#,$ 0 7 1 1 4 UIParent 0.0 -100.0 -1 ##$$%/&('%(#,$ 0 10 0 8 2 MultiBarBottomRight 0.0 4.0 -1 ##$$&%'% 0 11 0 1 1 UIParent -515.2 -802.0 -1 ##$%&&'%,# 0 12 0 6 0 MultiBarBottomRight 0.0 4.0 -1 ##$$&%'% 1 -1 0 4 4 UIParent 0.0 -144.0 -1 ##$#%# 2 -1 0 0 0 UIParent 1883.7 -36.3 -1 #$$#%'&( 3 0 0 1 1 UIParent -398.0 -686.0 -1 $#3# 3 1 0 1 1 UIParent 400.0 -686.0 -1 %#3# 3 2 0 1 1 UIParent 573.5 -789.5 -1 %#&#3# 3 3 0 0 0 UIParent 768.7 -956.0 -1 '#(#)#-=.+/#1$3#5#6(7-7$8(9( 3 4 0 0 0 UIParent 682.7 -0.0 -1 ,%-;.+/#0%1#2(3#5#6(7-7$8(9( 3 5 0 2 2 UIParent -350.7 -315.3 -1 &#*$3# 3 6 1 5 5 UIParent 0.0 0.0 -1 -=.+/#4$5#6(7-7$8(9( 3 7 1 4 4 UIParent 0.0 0.0 -1 3# 4 -1 1 7 7 UIParent 0.0 -4.0 -1 # 5 -1 1 7 7 UIParent 0.0 -4.0 -1 # 6 0 0 4 4 UIParent -692.5 500.0 -1 ##$#%$&/(')( 6 1 0 0 6 BuffFrame 0.0 -4.0 -1 ##$#%$'-(')(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 1 7 7 UIParent 0.0 -4.0 -1 # 8 -1 0 7 7 UIParent -799.8 34.0 -1 #'$($$%%&4 9 -1 0 6 0 MultiBarLeft 0.0 4.0 -1 # 10 -1 1 0 0 UIParent 16.0 -116.0 -1 # 11 -1 0 1 1 UIParent 373.0 -152.0 -1 # 12 -1 0 1 1 UIParent 934.7 -302.0 -1 #:$<%% 13 -1 0 8 2 BagsBar 0.0 4.0 -1 ##$#%$ 14 -1 0 7 7 UIParent 947.0 1.5 -1 ##$#%# 15 0 0 4 4 UIParent 0.0 -584.7 -1 &$ 15 1 0 7 7 UIParent 0.0 2.0 -1 &# 16 -1 0 8 6 BagsBar -3.5 0.5 -1 #( 17 -1 0 1 1 UIParent 0.0 -202.0 -1 ## 18 -1 1 5 5 UIParent 0.0 0.0 -1 #- 19 -1 1 7 7 UIParent 0.0 0.0 -1 ## 20 0 0 1 1 UIParent 167.0 -702.0 -1 #$$-%$&$'%(-($)#+$,$-$ 20 1 0 1 1 UIParent -167.0 -702.0 -1 #$$*%$&('%(-($)#+$,$-$ 20 2 0 7 7 UIParent -216.0 502.0 -1 ##$$%$&&''(-($)#+$,$-$ 20 3 0 0 0 UIParent 1568.6 -624.3 -1 #$$$%#&&''(A)#*#+$,$-$.-.$ 21 -1 0 1 1 UIParent -0.0 -151.6 -1 ##%#&#'((()#*-*$+%,$-#.#/(0#1# 22 0 1 8 7 UIParent -457.0 336.0 -1 #$$$%#&('((#)U*$+%,$-#.#/U0% 22 1 1 1 1 UIParent 0.0 -40.0 -1 &('()U*#+% 22 2 1 1 1 UIParent 0.0 -90.0 -1 &('()U*#+% 22 3 1 1 1 UIParent 0.0 -130.0 -1 &('()U*#+% 23 -1 0 8 2 MicroMenuContainer 0.0 4.0 -1 ##$%%$&1&$'j(%)P+$,$-$.(/P 24 -1 1 1 1 UIParent 0.0 -182.0 -1 # 25 -1 0 1 1 UIParent -317.0 -802.0 -1 # 26 0 0 8 6 MultiBarLeft 30.0 -2.0 -1 #$ 26 1 0 7 7 UIParent 1229.2 0.0 -1 #$ 27 -1 1 4 4 Minimap -68.0 -68.0 -1 #- 28 -1 1 4 4 UIParent 0.0 0.0 -1 #& 29 0 1 7 7 UIParent 0.0 450.0 -1 #($U%#&D&%'2($)$ 29 1 1 7 7 UIParent 0.0 425.0 -1 #($U%#&D&%'2($)$ 29 2 1 7 7 UIParent 0.0 400.0 -1 #($U%#&D&%'2($)$]==],
	},
}

-- Settings that belong to one character or class, never shipped with a
-- starter layout (whatever the string holds, they start empty).
local function MakeImpersonal(data)
	local group = data.modules and data.modules.GroupFrames
	if group then group.clickCast = nil end -- click-cast spells are class-specific
	return data
end

-- Add `layout`'s StzxUI profile as a new profile and switch to it (asks to
-- reload). Returns the new profile's name, or nil plus a reason.
function StzxUI:UseStarterLayout(layout)
	local data, problem = self:DecodeProfile(layout.profile)
	if not data then return nil, problem end
	local name = self:FreeProfileName(layout.profileName)
	self.db.profiles[name] = MakeImpersonal(data) -- (the click-cast table refills with empty defaults on load)
	self:SwitchProfile(name)
	return name
end

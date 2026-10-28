--------------------------------------------------------------------------------
-- MelloUI - Dark Mode, the painted reskin's part (one look, stage I:
-- DarkMode.lua's OLDSCHOOL block): the reskin's brightness under Dark Mode,
-- one of Dark Mode's parts (MelloUI.ModuleParts: its keys and option ids).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI

-- OLDSCHOOL BEGIN: the painted reskin's brightness under Dark Mode, a part of Dark Mode's settings (M:AddPart: the same
-- key and option id, DarkMode.kitShade). Moves to MelloUI_Oldschool at stage I; it uses only the header's locals and
-- public tables.
do
local Dark = MelloUI:GetModule("DarkMode")
-- the kit darkened as one (Kit:SetShade, its hue kept: the gems stay red) by
-- Dark Mode's one Brightness while it is on (1.2.4, the user: one slider for
-- the whole UI; Reskin Brightness, kitShade, was this part's own), at full
-- brightness when it is off
local function ShadeKit(db)
	local kit = MelloUI.Kit
	if kit and kit.SetShade then
		kit:SetShade((Dark.isEnabled and db) and tonumber(db.shade) or 1)
	end
end
if Dark and Dark.AddPart then
	Dark:AddPart({
		Enabled = ShadeKit,
		Disabled = function()
			ShadeKit(nil)
		end,
		Setting = function(key, _, db)
			if key == "shade" then
				ShadeKit(db)
			end
			return false
		end,
	})
end
end
-- OLDSCHOOL END

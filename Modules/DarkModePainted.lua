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
-- Reskin Brightness while Dark Mode is on, at full brightness when it is off
local function ShadeKit(db)
	local kit = MelloUI.Kit
	if kit and kit.SetShade then
		kit:SetShade((Dark.isEnabled and db) and db.kitShade or 1)
	end
end
if Dark and Dark.AddPart then
	Dark:AddPart({
		defaults = { kitShade = 0.6 },   -- brightness of the painted reskin's pieces (Kit:SetShade)
		options = {
			{ type = "slider", key = "kitShade", name = "Reskin Brightness", min = 0.2, max = 1, step = 0.05, percent = true,
			  after = "desaturate",
			  desc = "How bright the painted reskin is while Dark Mode is on: every kit piece (stone, iron, plates, brackets) is darkened by this much; the red gems keep their colour. The default art above is darkened where the reskin is off." },
		},
		Enabled = ShadeKit,
		Disabled = function()
			ShadeKit(nil)
		end,
		Setting = function(key, _, db)
			if key == "kitShade" then
				ShadeKit(db)
				return true
			end
			return false
		end,
	})
end
end
-- OLDSCHOOL END

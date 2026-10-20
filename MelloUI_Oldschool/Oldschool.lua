--------------------------------------------------------------------------------
-- MelloUI Oldschool - the version guard (one look, stage I)
--
-- MelloUI's painted reskin is an addon of its own: the painted engine, the
-- painted parts of UI Modifications, Dark Mode and the quest ink, and the
-- painted skins of the game's windows and HUD. It ships on its own (its own
-- CurseForge project), so a player can have it from another MelloUI version
-- than the MelloUI beside it. Such a folder dresses nothing: its files still
-- load (their settings stay in MelloUIDB, MelloUI's own saved settings), but
-- the painted reskin stays off -- no painted skin comes on, no area of the
-- kit's reads the reskin as on (UI Modifications' painted part and the Kit's
-- Reskin() ask MelloUI.Oldschool.refused) -- and it is said as UI
-- Modifications comes on, a notice Chat Notices can mute (the Companions.lua
-- pattern). A development copy without a version ("dev") takes any.
--   MelloUI.Oldschool = { version = its TOC's Version or nil,
--                         refused = the sentence why, or nil }
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Text = MelloUI.Safe.Text
local ADDON = "MelloUI_Oldschool"

local function Version(addon)
	local Meta = C_AddOns and C_AddOns.GetAddOnMetadata
	if not Meta then
		return nil
	end
	local ok, version = pcall(Meta, addon, "Version")
	version = ok and Text(version) or nil
	return version ~= "" and version or nil
end

local mine, theirs = MelloUI.version, Version(ADDON)
MelloUI.Oldschool = { version = theirs }
if theirs and mine and mine ~= "dev" and theirs ~= mine then
	MelloUI.Oldschool.refused = string.format("MelloUI Oldschool is from MelloUI %s, not %s", theirs, tostring(mine))
end

--------------------------------------------------------------------------------
-- MelloUI - ManaRise compatibility (2.1.71; the user, 2026-11-22: "manarise addon full compatibility")
--
-- ManaRise (Natetrix, CurseForge; All Rights Reserved: nothing of it copied, only its public calls used) fills the
-- icons of the game's action buttons -- and of the bar addons it knows (Bartender4, Dominos, ElvUI, EllesmereUI) --
-- with the mana, rage, energy or focus their spells need, and flashes them once castable. While MelloUI's Action
-- Bars 1-8 are MelloUI's own buttons (Modules/OwnActionBars.lua) it never finds them: the game's buttons it fills
-- are hidden under ours. Its one call for other bar addons, ManaRise_RegisterBarAddon(def), takes ours:
--   name     "MelloUI" (its /mr status and /mr scan name it so)
--   buttons  our buttons now (MR.Buttons): Action Bars 1-8 while they are ours, and the controller bars' picture
--            buttons (Modules/OwnPadBars.lua) while those show -- read again at each of its discovers
--   slot     each one's own action slot (MR.Slot): a button's page and ID (B.CalcAction), a picture button's slot
-- and ManaRise_RefreshBarAddons() whenever ours are built again (the bus 'ownbars' "actions", 'ownbars:padslots'):
-- it looks for new buttons out of a fight (its own rule). It re-reads every slot on the page, bonus bar, form and
-- slot events that page our bars too. Its fill is its own frames on our buttons, under their cooldowns and texts,
-- clipped by their icon masks; nothing of ours is written by it, nor anything of its by us.
-- The Addons page's switch (Use with MelloUI, Core/Integrations.lua): off, ours are never registered (from the next
-- /reload: a registration stays for the session). Nothing at login but a look at its call (PLAYER_LOGIN).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local OB = MelloUI.OwnBars
local Perf = MelloUI.Perf:Scope("ManaRise compatibility")
local Finite = MelloUI.Safe.Finite

local MR = { NAME = "MelloUI", registered = false }
MelloUI.ManaRiseCompat = MR   -- (the tests, the Addons page's part check)

-- our buttons now (a fresh list each ask: ManaRise asks at its discovers, out of a fight, never per frame)
function MR.Buttons()
	local out = {}
	local A = OB and OB.Actions
	if not (A and OB.On and OB.On("actions")) then
		return out
	end
	for _, b in ipairs(A.buttons or {}) do
		out[#out + 1] = b
	end
	if OB.Pad and OB.Pad.on then
		for _, b in ipairs(A.shows or {}) do
			out[#out + 1] = b
		end
	end
	return out
end

-- a button's action slot now: its page and ID as the game's CalculateAction reads them (a picture button: the slot it
-- shows); none: an empty one
function MR.Slot(button)
	local slot
	local calc = type(button) == "table" and button.CalcAction
	if type(calc) == "function" then
		local ok, v = pcall(calc, button)
		slot = ok and Finite(v) or nil
	end
	slot = slot or Finite(type(button) == "table" and button.action or nil)
	if slot and slot > 0 then
		return slot
	end
	return nil, "empty-slot"
end

-- registered once (true: it took ours); never while the Addons page's switch is off or ManaRise is not there
function MR.Register()
	if MR.registered then
		return true
	end
	local I = MelloUI.Integrations
	if I and I.Use and not I.Use("ManaRise") then
		return false
	end
	local reg = rawget(_G, "ManaRise_RegisterBarAddon")
	if type(reg) ~= "function" then
		return false
	end
	local ok, done = pcall(reg, { name = MR.NAME, buttons = MR.Buttons, slot = MR.Slot })
	MR.registered = ok and done == true
	return MR.registered
end

-- ours built again (or ManaRise just loaded): registered if not yet, then told to look for them
function MR.Refresh()
	if not MR.Register() then
		return
	end
	local refresh = rawget(_G, "ManaRise_RefreshBarAddons")
	if type(refresh) == "function" then
		pcall(refresh)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
Perf.SetScript(events, "OnEvent", function(_, event, addon)
	if event == "PLAYER_LOGIN" then
		events:UnregisterEvent("PLAYER_LOGIN")
		MR.Refresh()
	elseif addon == "ManaRise" then
		MR.Refresh()
	end
end)
MelloUI:On("ownbars", function(part)
	if part == "actions" then
		MR.Refresh()
	end
end, "ManaRise compatibility")
MelloUI:On("ownbars:padslots", MR.Refresh, "ManaRise compatibility: controller slots")

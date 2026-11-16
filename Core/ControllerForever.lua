--------------------------------------------------------------------------------
-- MelloUI - Controller Forever (2.1.55, stage 1 of docs/plans/controller-forever.md; the user, 2026-11-16: "we will
-- need to redo the whole controller setup with another Addon called Controller Forever, and make full integration
-- with MelloUI", then: "Our Controller code, but we need to make sure that Controller Forever users (which will be
-- all of them) have the full MelloUI Compatibility, that means navigation trough our menus, map, quest tracker etc").
--
-- Controller Forever is the controller's engine. It is All Rights Reserved: met at run time only, nothing of it
-- copied, nothing of it called. Stage 1 is the two addons stepping aside for each other, each way on ONE name of its
-- own that is looked at before it is used (it updates every other day; with a name gone that way steps back to what
-- MelloUI did without it, and the Addons page says which):
--
--   Its buttons step aside for a MelloUI window. It keeps a list of frame names "the pad belongs to" while one of
--   them shows (ControllerForever.RuleBar.extraMenuFrames, read live by its own code; the game's menus are on it).
--   The list gets one name, HOLD: a plain frame of MelloUI's own, shown while MelloUI's navigation holds the pad's
--   buttons (the bus's "gamepad:nav") and hidden when it lets go, a fight included. Measured in the real client
--   without this, 2026-11-16: with the configurator open, A was MelloUI's at first and its own again 30 s later.
--
--   Its parts step back where MelloUI has the part. It keeps a table of who takes which of its parts
--   (ControllerForever.Compat.TAKEN, read live by its takenBy: a taken part is switched off without touching the
--   player's setting, its menu row says "Off (<addon>)", one login line of its own says what it left to whom).
--   The table gets MelloUI's row for each part whose MelloUI module is on.
--
--   MelloUI's own pad bars are not built while it is in use (Modules/OwnPadBars.lua asks C.Used()).
--
-- The rows go in while this file loads (it loads before MelloUI, and its parts ask from their first moment), every
-- one of them; C.Sync at the login takes out what MelloUI does not have on, or all of them with its switch on the
-- Addons page off.
--
--   C.Used() -> bool        it is loaded and its switch on the Addons page is on
--   C.Holds() -> bool|nil   its buttons step aside for MelloUI's windows (HOLD is on its list); nil: no such list
--   C.Parts() -> list|nil   { part, label, taken }: its parts MelloUI may have, and whether MelloUI's row is in;
--                           nil: no such table
--   C.Sync()                the rows and the name as the switch and MelloUI's modules say now
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Plain = MelloUI.Safe.Value

local C = {}
MelloUI.ControllerForever = C

local FOLDER, KEY, NAME, HOLD = "ControllerForever", "ControllerForever", "MelloUI", "MelloUIPadHold"

-- its part -> MelloUI's module that is that part, and the words for it
local PARTS = {
	{ "frames", "UnitFrames", "Unit frames" },
	{ "party", "HealerFrames", "Party and raid frames" },
	{ "minimap", "MinimapPanel", "Minimap" },
	{ "chat", "Chat", "Chat" },
	{ "damagemeter", "Meter", "Damage meter" },
	{ "bags", "BagWindow", "Bags" },
	{ "quests", "QuestAuto", "Automatic quests" },
}

local function Loaded()
	local fn = C_AddOns and C_AddOns.IsAddOnLoaded
	if not fn then
		return false
	end
	local ok, on = pcall(fn, FOLDER)
	return ok and Plain(on) == true
end

-- a table of its own by two names from its global (ControllerForever.<a>.<b>), or nil
local function Its(a, b)
	local addon = rawget(_G, "ControllerForever")
	local part = type(addon) == "table" and rawget(addon, a) or nil
	local t = type(part) == "table" and rawget(part, b) or nil
	return type(t) == "table" and t or nil
end

function C.Used()
	if not (Loaded() and type(rawget(_G, "ControllerForever")) == "table") then
		return false
	end
	local I = MelloUI.Integrations
	return I == nil or I.Use(KEY)
end

--------------------------------------------------------------------------------
-- Its buttons step aside for a MelloUI window
--------------------------------------------------------------------------------

local hold = nil

local function Listed(list)
	for i = 1, #list do
		if list[i] == HOLD then
			return i
		end
	end
	return nil
end

function C.Holds()
	local list = Its("RuleBar", "extraMenuFrames")
	if not list then
		return nil
	end
	return Listed(list) ~= nil
end

local function PutHold(on)
	local list = Its("RuleBar", "extraMenuFrames")
	if not list then
		return
	end
	local at = Listed(list)
	-- (FIRST on its list, never last. Seen in the real client, 2026-11-16: its check asks the names in order inside
	-- one protected call, and one of its own names, the shop's window, may not be asked by an addon -- the call ends
	-- there, and no name after it is ever looked at. At the list's end MelloUI's name did nothing: its answer stayed
	-- "no window" with the configurator open)
	if on and at ~= 1 then
		if at then
			table.remove(list, at)
		end
		table.insert(list, 1, HOLD)
	elseif at and not on then
		table.remove(list, at)
	end
end

-- (a plain frame, never a secure one: shown and hidden in a fight too. Made at the first window that takes the pad
-- while Controller Forever is in use, not at the login)
MelloUI:On("gamepad:nav", function(on)
	local show = on and C.Used() and C.Holds() == true
	if show and not hold then
		hold = CreateFrame("Frame", HOLD)
		hold:SetSize(1, 1)
		hold:Hide()
	end
	if hold then
		hold:SetShown(show and true or false)
	end
end, "Controller Forever: a MelloUI window holds the pad")

--------------------------------------------------------------------------------
-- Its parts step back where MelloUI has the part
--------------------------------------------------------------------------------

local function Mine(list)
	for i = 1, #list do
		local row = list[i]
		if type(row) == "table" and row.melloui then
			return i
		end
	end
	return nil
end

-- a part its table does not know (another version of it) is left alone: no list is made in its table
local function PutPart(part, on)
	local taken = Its("Compat", "TAKEN")
	local list = taken and rawget(taken, part) or nil
	if type(list) ~= "table" then
		return
	end
	local at = Mine(list)
	if on and not at then
		list[#list + 1] = { NAME, NAME, melloui = true }
	elseif at and not on then
		table.remove(list, at)
	end
end

function C.Parts()
	local taken = Its("Compat", "TAKEN")
	if not taken then
		return nil
	end
	local out = {}
	for _, p in ipairs(PARTS) do
		local list = rawget(taken, p[1])
		if type(list) == "table" then
			out[#out + 1] = { part = p[1], label = p[3], taken = Mine(list) ~= nil }
		end
	end
	return out
end

-- `all`: every row, whatever MelloUI's modules say (while this file loads: the settings are not read yet)
local function Lay(all)
	local used = all or C.Used()
	PutHold(used)
	for _, p in ipairs(PARTS) do
		PutPart(p[1], used and (all or MelloUI:IsModuleEnabled(p[2])) and true or false)
	end
end

function C.Sync()
	if type(rawget(_G, "ControllerForever")) ~= "table" then
		return
	end
	Lay(false)
end

-- (C.Sync is called by Core.lua's login, once this character's settings are read)
if Loaded() and type(rawget(_G, "ControllerForever")) == "table" then
	Lay(true)
end

--------------------------------------------------------------------------------
-- MelloUI - Controller Forever (2.1.55, stage 1 of docs/plans/controller-forever.md; the user, 2026-11-16: "we will
-- need to redo the whole controller setup with another Addon called Controller Forever, and make full integration
-- with MelloUI", then: "Our Controller code, but we need to make sure that Controller Forever users (which will be
-- all of them) have the full MelloUI Compatibility, that means navigation trough our menus, map, quest tracker etc").
--
-- Controller Forever is the controller's engine. It is All Rights Reserved: met at run time only, nothing of it
-- copied, and nothing of it called but its bind manager's claimant (C.Claim, below). Stage 1 is the two addons stepping aside for each other, each way on ONE name of its
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
--   MelloUI's navigation tells its bind manager every key it binds (C.Claim, below): the one place something of
--   its is called.
--
--   C.Used() -> bool        it is loaded and its switch on the Addons page is on
--   C.Claim(key, action)    a key MelloUI's navigation binds, told to its bind manager; C.Claim(): all let go
--   C.Claims() -> bool|nil  its bind manager takes them (nil: not asked yet)
--   C.Frames() -> bool|nil  its healer mode's list of frames starts with MelloUI's group frames (nil: no such list)
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
-- MelloUI's keys through its one bind manager
--
-- (the user's PS5 pad, 2026-11-16, his dump with the configurator open: the D-pad and B were MelloUI's, A, X and Y
-- still its own slots -- with only the name on its window list its face buttons do not step aside) Its bind manager
-- (ControllerForever.Binds) takes what each part wants on a key through a claimant and sets one winner a key on one
-- frame; a claimant made `exclusive`, as its own windows', stands every lower one down while it holds a key. So
-- MelloUI's navigation tells it each key it binds: C.Claim(key, action) ("CLICK Button:MouseButton"; false: the key
-- let go), C.Claim() with nothing: every key let go. One commit a frame. The ONE place MelloUI calls something of
-- its: claimant, then the handle's set / unset / clear / commit, each looked at first and run protected; without
-- them the navigation's own override bindings and the name on its list are all there is, as before.
--------------------------------------------------------------------------------

local claim, committing = nil, false

local function Handle()
	if claim ~= nil then
		return claim or nil
	end
	claim = false
	local addon = rawget(_G, "ControllerForever")
	local binds = type(addon) == "table" and rawget(addon, "Binds") or nil
	if type(binds) ~= "table" or type(binds.claimant) ~= "function" then
		return nil
	end
	local levels = rawget(binds, "PRIORITY") or binds.PRIORITY
	local level = type(levels) == "table" and tonumber(levels.ourwindow) or 100
	local ok, handle = pcall(binds.claimant, binds, "melloui", level, { exclusive = true, overGame = true, outOfFight = true })
	if ok and type(handle) == "table" and type(handle.set) == "function" and type(handle.unset) == "function"
		and type(handle.clear) == "function" and type(handle.commit) == "function" then
		claim = handle
	end
	return claim or nil
end

-- (never inside a fight: the game locks the bindings then -- its manager's attempt would be a blocked action, and its
-- keys stay as they were)
local function Commit()
	committing = false
	if InCombatLockdown() then
		return
	end
	local handle = Handle()
	if handle then
		pcall(handle.commit)
	end
end

-- true: its bind manager takes MelloUI's keys; false: it has none MelloUI can use; nil: not asked yet
function C.Claims()
	if claim == nil then
		return nil
	end
	return claim ~= false
end

-- -> true when its bind manager took it
function C.Claim(key, action)
	if not C.Used() then
		return false
	end
	local handle = Handle()
	if not handle or InCombatLockdown() then
		return false
	end
	if key == nil then
		-- (the user with his pad, 2026-11-16: "looking at the map with the controller, then got aggroed ... got the
		-- error and couldnt use any spells while using the controller" -- the keys were let go a frame after the fight
		-- had started: the game had locked the bindings by then, its manager's commit was a blocked action, and its
		-- frame kept MelloUI's keys on the buttons for the whole fight) every key let go NOW, in this same call: the
		-- navigation lets go as a fight starts (PLAYER_REGEN_DISABLED), the last moment a binding may still be set
		pcall(handle.clear)
		committing = false
		pcall(handle.commit)
		return true
	elseif action then
		pcall(handle.set, key, action)
	else
		pcall(handle.unset, key)
	end
	if not committing then
		committing = true
		C_Timer.After(0, Commit)
	end
	return true
end

--------------------------------------------------------------------------------
-- Its healer mode finds MelloUI's group frames
--
-- (the user, 2026-11-16: "Controller Forever has a healer function, where it can target Party members and cast heals
-- on it ... did we make sure that our group frames are able to be targeted?") Its healer mode picks a member and
-- casts by the party's slots through buttons of its own, whatever frames show. But the picked member's highlight, the
-- arrows and its party frame glow go by the member's FRAME, looked up by name in a list of its own
-- (ControllerForever.HealFocus.candidateFrames(): the game's party and raid frames, EllesmereUI's, PlayerFrame), the
-- first one shown and seen whose unit is the member's. MelloUI's party and raid frames are named unit buttons of the
-- same kind: while they are on, their names stand at the FRONT of that list (the game's own frames, faded by MelloUI,
-- are passed over by its own "seen" test). Seen in a party of two (2026-11-16): its outline on MelloUI's frame of the
-- picked member, the order from MelloUI's frames. Not reached by this, both its side:
--   * what it reads from any SHOWN frame, seen or not (the order its D-pad walks the party in): the game's classic
--     party frames (PartyFrame's members), shown at alpha 0 under MelloUI's, are asked BEFORE the list, so with those
--     the order is the game's; with the game's raid-style party frames the list is asked, and the order is MelloUI's;
--   * with ONE party member it reads row or column from the game's own compact party frame of the player, by name:
--     MelloUI's column of two reads as a row (left / right pick, up / down its Focus and Self jumps).
--------------------------------------------------------------------------------

local groupNames = nil
local function GroupNames()
	if groupNames then
		return groupNames
	end
	local t = { "MelloUIGroupSoloParty" }
	for i = 1, 5 do
		t[#t + 1] = "MelloUIGroupPartyHeaderUnitButton" .. i
	end
	for i = 1, 4 do
		t[#t + 1] = "MelloUIGroupPartyMember" .. i
	end
	for i = 1, 40 do
		t[#t + 1] = "MelloUIGroupRaidHeaderUnitButton" .. i
	end
	groupNames = t
	return t
end

-- its list (the table its own lookup walks), or nil
local function Candidates()
	local addon = rawget(_G, "ControllerForever")
	local heal = type(addon) == "table" and rawget(addon, "HealFocus") or nil
	local fn = type(heal) == "table" and rawget(heal, "candidateFrames") or nil
	if type(fn) ~= "function" then
		return nil
	end
	local ok, list = pcall(fn)
	return ok and type(list) == "table" and list or nil
end

local function PutFrames(on)
	local list = Candidates()
	if not list then
		return
	end
	local names, mine = GroupNames(), {}
	for i = 1, #names do
		mine[names[i]] = true
	end
	for i = #list, 1, -1 do
		if mine[list[i]] then
			table.remove(list, i)
		end
	end
	if on then
		for i = #names, 1, -1 do
			table.insert(list, 1, names[i])
		end
	end
end

-- true: its healer mode's list starts with MelloUI's group frames; false: they are not on it; nil: no such list
function C.Frames()
	local list = Candidates()
	if not list then
		return nil
	end
	return list[1] == GroupNames()[1]
end

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
	-- (2.1.55, the user's PS5 pad and the test VM, 2026-11-16: MelloUI's name on its window list made it treat a
	-- MelloUI window as one of the game's -- its D-pad and B let go, its A, X and Y slots stayed bound, and it set them
	-- again over the keys its own bind manager had just given MelloUI. The claim there (C.Claim) is the one hand-over;
	-- the name is taken off the list wherever an earlier build of this file left it)
	PutHold(false)
	PutFrames(used and (all or MelloUI:IsModuleEnabled("HealerFrames")) and true or false)
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

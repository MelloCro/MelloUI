--------------------------------------------------------------------------------
-- MelloUI - Fader (0.17.0)
--
-- The Fader page (the user, 2026-10-01; docs/plans/fader-0.17.md): which
-- parts of the UI fade away and when they come back. Each element has ONE
-- choice, Show: Always (the default), In Combat (faded out of combat, back in
-- a fight) or On Mouseover (faded all the time, shown while you point at it).
-- Fade Everything puts every element on In Combat, Fade Nothing on Always.
-- The engine is Core/Fader.lua (MelloUI.Fader: one fader for all); this
-- module holds its settings and the element list, each element's frames
-- found by name when first needed (none at login):
--   Frames      Player Frame (+ Pet Frame Too), Target Frame, Party Frames,
--               Raid Frames, Buffs & Debuffs (the game's, and MelloUI's own
--               rows by the minimap column)
--   Bars        Main Action Bar, Action Bar 2 to 8 (one row each), Stance &
--               Pet Bar, Micro Menu, Bag Bar, Experience & Reputation Bars
--   Chat & Map  the chat windows (their tabs on the dock, their buttons and
--               edit boxes are their children), the minimap (its cluster: the
--               Services row is the map's), the Quest Tracker, the game's
--               Objective Tracker
-- Also (the user's test, 2026-10-01): the reminders by the portrait, the
-- widget column and Route's arrow and World Marker, on hosts (Fader:Host).
-- Left out on purpose (they only come up when they matter): Gains, the cast
-- bar, the damage meter's race bar and summary, Combat Text, the notices.
--
-- The player frame's own reasons are Unit Frames' Fade Out Of Combat's
-- (0.14.0, lifted here with its engine; that option, Faded Opacity and Pet
-- Frame Too carried over by Core.lua's MergeSettings): its health below
-- full, its mana below full while the bar shows mana, dead or a ghost; a
-- health or mana this client hands over SECRET (always, the RC5 fix) is
-- never compared: a change of it heard lately stands for "below full"
-- (RECENT; a spell's cost keeps the mana's window open CAST seconds, the
-- five-second rule). The pet frame follows the player frame's choice while
-- Pet Frame Too is on and comes back for its own health too. The chat comes
-- back while you type in it.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("FaderModule")
local C_Timer = Perf.C_Timer
local Shared = Perf.Shared

local Secret = MelloUI.Safe.IsSecret
local Finite = MelloUI.Safe.Finite
local Fader = MelloUI.Fader
local pcall, type, ipairs = pcall, type, ipairs

local NEW = "0.17.0"

-- the elements, in the page's order: key, label, tab, desc
local LIST = {
	{ "player", "Player Frame", "Frames", "Your own frame. It also comes back while your health or mana is below full and when you are dead." },
	{ "target", "Target Frame", "Frames", "Your target's frame (and its target's)." },
	{ "party", "Party Frames", "Frames", "The party frames, the game's and the raid-style ones." },
	{ "raid", "Raid Frames", "Frames", "The raid frames." },
	{ "buffs", "Buffs & Debuffs", "Frames", "Your own buffs and debuffs, the game's or MelloUI's rows by the minimap." },
	{ "reminders", "Reminders", "Frames", "The round reminders beside your portrait (restock, mail, your buffs, the weapon's poison...)." },
	{ "bar1", "Main Action Bar", "Bars", "Action Bar 1. Its keys work while it is faded." },
	{ "bar2", "Action Bar 2", "Bars", "Its keys work while it is faded." },
	{ "bar3", "Action Bar 3", "Bars", "Its keys work while it is faded." },
	{ "bar4", "Action Bar 4", "Bars", "Its keys work while it is faded." },
	{ "bar5", "Action Bar 5", "Bars", "Its keys work while it is faded." },
	{ "bar6", "Action Bar 6", "Bars", "Its keys work while it is faded." },
	{ "bar7", "Action Bar 7", "Bars", "Its keys work while it is faded." },
	{ "bar8", "Action Bar 8", "Bars", "Its keys work while it is faded." },
	{ "stance", "Stance & Pet Bar", "Bars", "The stance, form and aura bar, and your pet's bar." },
	{ "micro", "Micro Menu", "Bars", "The small buttons for the game's windows." },
	{ "bags", "Bag Bar", "Bars", "Your bags' buttons." },
	{ "xp", "Experience & Reputation Bars", "Bars", "The bars of your experience and the reputation you watch." },
	{ "chat", "Chat", "Chat & Map", "The chat windows with their tabs, buttons, the Friends button and the line you type in. They come back while you type." },
	{ "minimap", "Minimap", "Chat & Map", "The minimap with its zone band and the Services row." },
	{ "tracker", "Quest Tracker", "Chat & Map", "MelloUI's Quest Tracker." },
	{ "objectives", "Objective Tracker", "Chat & Map", "The game's own objective tracker." },
	{ "widgets", "Widget Column", "Chat & Map", "The column of widgets: loot rolls, summons, Voice Over, whispers and the rest. On Mouseover hides a loot roll or a summons until you point at the column." },
	{ "route", "World Marker", "Chat & Map", "Route's World Marker over the destination (the Direction Arrow is a row of the Widget Column: it fades with the column)." },
}

local SHOW = { { value = "always", label = "Always" }, { value = "combat", label = "In Combat" },
	{ value = "mouseover", label = "On Mouseover" } }
local SHOW_TIP = " Always: never faded. In Combat: faded out of combat, back in a fight. On Mouseover: faded all the time, shown while you point at it."

local defaults = { alpha = 0, after = Fader.T.AFTER, speed = Fader.T.SPEED, target = true, mouse = true, petToo = true }
local options = {}
for _, e in ipairs(LIST) do
	defaults["show_" .. e[1]] = "always"
end

local M   -- (the module, below)

local function SetAll(value)
	local db = M and M.db
	if not db then
		return
	end
	for _, e in ipairs(LIST) do
		db["show_" .. e[1]] = value
		MelloUI:NotifySettingChanged("Fader", "show_" .. e[1], value)
	end
end

options[#options + 1] = { type = "button", name = "Fade Everything", text = "Fade", new = NEW,
	search = "hide out of combat whole ui",
	desc = "Every element below on In Combat: the whole interface fades away out of combat and comes back in a fight.",
	onClick = function() SetAll("combat") end }
options[#options + 1] = { type = "button", name = "Fade Nothing", text = "Reset", new = NEW,
	desc = "Every element below on Always: nothing fades.",
	onClick = function() SetAll("always") end }
options[#options + 1] = { type = "slider", key = "alpha", name = "Faded Opacity", min = 0, max = Fader.T.MAX, step = 0.05,
	percent = true, new = NEW,
	desc = "How much of an element stays while it is faded. At 0 % it is gone until it is needed (an On Mouseover bar at 0 % still shows when you point at it)." }
options[#options + 1] = { type = "slider", key = "after", name = "Fade After", min = 0, max = 10, step = 0.5, new = NEW,
	format = function(v) return string.format("%.1f s", v) end,
	desc = "How long an element waits before it fades: after a fight ends, after you let go of your target or point away." }
options[#options + 1] = { type = "slider", key = "speed", name = "Fade Speed", min = 0.2, max = 3, step = 0.1, new = NEW,
	format = function(v) return string.format("%.1f s", v) end,
	desc = "How long the fade itself takes. Coming back is always quick. Reduce Motion: at once." }
options[#options + 1] = { type = "toggle", key = "target", name = "Show With A Target", new = NEW,
	desc = "In Combat elements come back while you have a target, a friend too." }
options[#options + 1] = { type = "toggle", key = "mouse", name = "Also Show On Mouseover", new = NEW,
	search = "show on hover",
	desc = "In Combat elements come back while you point at them, too. (On Mouseover elements always do.)" }
for _, e in ipairs(LIST) do
	options[#options + 1] = { type = "dropdown", key = "show_" .. e[1], name = e[2], values = SHOW, new = NEW,
		desc = e[4] .. SHOW_TIP }
	if e[1] == "player" then
		options[#options + 1] = { type = "toggle", key = "petToo", name = "Pet Frame Too", new = NEW,
			desc = "Your pet's frame fades and comes back with the player frame, and also comes back while your pet is hurt. Off: the pet frame always stays." }
	end
end

M = MelloUI:RegisterModule("Fader", {
	title = "Fader",
	desc = "Fade parts of the interface away while you do not need them: out of combat, or until you point at them. Pick for each frame, bar, the chat, the minimap and the trackers.",
	icon = "Interface\\Icons\\Spell_Magic_LesserInvisibilty",
	flavour = "Your interface, only when you need it.",
	-- (a look: how the interface shows, off by default; the installer's
	-- setups leave it as it is, no Features row of its own)
	role = "look",
	enabledByDefault = false,
	new = NEW,
	defaults = defaults,
	options = options,
})
M.LIST = LIST

--------------------------------------------------------------------------------
-- Frames by name (looked up when the element needs them: never at login)
--------------------------------------------------------------------------------

local function G(name)
	local f = rawget(_G, name)
	return type(f) == "table" and type(f.SetAlpha) == "function" and f or nil
end

local function Add(out, f)
	if f and type(f) == "table" and type(f.SetAlpha) == "function" then
		out[#out + 1] = f
	end
	return out
end

-- a frame's children that take the pointer, down to `depth` (at most CAP):
-- for an element whose buttons are made by the game as it needs them
local CAP = 120
local Mice
local function Kids(out, depth, ...)
	for i = 1, select("#", ...) do
		Mice(out, (select(i, ...)), depth)
	end
end

Mice = function(out, frame, depth)
	if not frame or #out >= CAP or type(frame.GetChildren) ~= "function" then
		return out
	end
	local ok, mouse = pcall(frame.IsMouseEnabled, frame)
	if ok and mouse == true then
		out[#out + 1] = frame
	end
	if depth > 0 then
		Kids(out, depth - 1, frame:GetChildren())
	end
	return out
end

local function Named(prefix, n, out)
	out = out or {}
	for i = 1, n do
		Add(out, G(prefix .. i))
	end
	return out
end

local BARS = {
	bar1 = { { "MainActionBar", "MainMenuBar" }, "ActionButton" },
	bar2 = { { "MultiBarBottomLeft" }, "MultiBarBottomLeftButton" },
	bar3 = { { "MultiBarBottomRight" }, "MultiBarBottomRightButton" },
	bar4 = { { "MultiBarRight" }, "MultiBarRightButton" },
	bar5 = { { "MultiBarLeft" }, "MultiBarLeftButton" },
	bar6 = { { "MultiBar5" }, "MultiBar5Button" },
	bar7 = { { "MultiBar6" }, "MultiBar6Button" },
	bar8 = { { "MultiBar7" }, "MultiBar7Button" },
}

local function BarFrame(key)
	for _, name in ipairs(BARS[key][1]) do
		local f = G(name)
		if f then
			return f
		end
	end
end

-- the chat windows and the dock their tabs sit on; the line you type in and
-- the Friends button are UIParent's (the game parents the line there itself)
local function ChatFrames()
	local out = {}
	Add(out, G("GeneralDockManager"))
	for i = 1, tonumber(rawget(_G, "NUM_CHAT_WINDOWS")) or 10 do
		Add(out, G("ChatFrame" .. i))
		Add(out, G("ChatFrame" .. i .. "EditBox"))
	end
	Add(out, G("QuickJoinToastButton"))
	return out
end

local function Auras()
	local out = {}
	Add(out, G("BuffFrame"))
	Add(out, G("DebuffFrame"))
	local A = MelloUI:GetModule("Auras")
	if A and type(A.PlayerRows) == "function" then
		local ok, rows = pcall(A.PlayerRows)
		if ok then
			Add(out, rows)
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- The player frame's and the pet frame's own reasons (Unit Frames' Fade Out
-- Of Combat, 0.14.0, as it was; its timings RECENT, CAST, PAIR)
--------------------------------------------------------------------------------

local RECENT, CAST, PAIR = 2.5, 7.5, 0.5
local HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
local POWER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_SPELLCAST_SUCCEEDED" }
local UNIT_EVENTS = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }

-- player, pet: watched; mana: the power bar shows mana; hpUntil, manaUntil,
-- petUntil: a secret value's "below full" window's end; manaAt, castAt: the
-- last power event and cast (PAIR); armed: the windows' timer pending
local P = { player = false, pet = false, mana = false, hpUntil = 0, manaUntil = 0, petUntil = 0,
	manaAt = -math.huge, castAt = -math.huge, armed = false, events = nil }
M.reasons = P   -- (read only: the tests')

local function Yes(fn, unit)
	if type(fn) ~= "function" then
		return false
	end
	local ok, v = pcall(fn, unit)
	return ok and not Secret(v) and v and true or false
end

local RecentTimer = Shared("the Fader: a secret health / mana window ended", function()
	P.armed = false
	Fader:Poke()
end)

-- a secret value's window still open: not full; the one timer armed to look
-- again when it ends, RECENT ahead at most (one pending at most)
local function Open(untilAt)
	local now = GetTime()
	if now >= untilAt then
		return false
	end
	if not P.armed then
		P.armed = true
		local wait = untilAt - now
		C_Timer.After(wait < RECENT and wait or RECENT, RecentTimer)
	end
	return true
end

-- cur below max; a secret or refused answer is never compared: its window
local function Below(curFn, maxFn, unit, kind, untilAt)
	if type(curFn) ~= "function" or type(maxFn) ~= "function" then
		return false
	end
	local okC, cur = pcall(curFn, unit, kind)
	local okM, max = pcall(maxFn, unit, kind)
	if not (okC and okM) or Secret(cur) or Secret(max) then
		return Open(untilAt)
	end
	cur, max = tonumber(cur), tonumber(max)
	if not (cur and max) or max <= 0 then
		return false
	end
	return cur < max
end

local function ManaType()
	local types = type(Enum) == "table" and Enum.PowerType
	return type(types) == "table" and Finite(types.Mana) or 0
end

local function OnMana()
	local fn = _G.UnitPowerType
	if type(fn) ~= "function" then
		return false
	end
	local ok, kind = pcall(fn, "player")
	if not ok or Secret(kind) then
		return false
	end
	return kind == ManaType()
end

local function PlayerNeeded()
	if Yes(_G.UnitIsDeadOrGhost, "player") then
		return true
	end
	if Below(UnitHealth, UnitHealthMax, "player", nil, P.hpUntil) then
		return true
	end
	return P.mana and Below(UnitPower, _G.UnitPowerMax, "player", ManaType(), P.manaUntil) or false
end

local function PetNeeded()
	return Yes(UnitExists, "pet") and Below(UnitHealth, UnitHealthMax, "pet", nil, P.petUntil)
end

local function ManaUntil(t)
	if t > P.manaUntil then
		P.manaUntil = t
	end
end

-- a change heard: its window opened from now (false: nothing to look at)
local function Stamp(event, unit, kind)
	local now = GetTime()
	if event == "UNIT_HEALTH" then
		if not Secret(unit) and unit == "pet" then
			if not P.pet then
				return false
			end
			P.petUntil = now + RECENT
		else
			P.hpUntil = now + RECENT
		end
	elseif event == "UNIT_POWER_UPDATE" then
		if not Secret(kind) and kind ~= nil and kind ~= "MANA" then
			return false
		end
		P.manaAt = now
		ManaUntil(now + RECENT)
		if now - P.castAt <= PAIR then
			ManaUntil(P.castAt + CAST)
		end
	else   -- UNIT_SPELLCAST_SUCCEEDED
		P.castAt = now
		if now - P.manaAt <= PAIR then
			ManaUntil(now + CAST)
		end
		return false
	end
	return true
end

-- the values not known yet (switched on, the world entered, a fight over,
-- back alive): the windows of a frame not faded open for RECENT
local function Seed()
	local t = GetTime() + RECENT
	if Fader:Shown("player") then
		if t > P.hpUntil then
			P.hpUntil = t
		end
		ManaUntil(t)
	end
	if Fader:Shown("pet") and t > P.petUntil then
		P.petUntil = t
	end
end

local function RegisterUnits()
	local f = P.events
	if not f then
		return
	end
	for i = 1, #HEALTH_EVENTS do
		if P.pet then
			f:RegisterUnitEvent(HEALTH_EVENTS[i], "player", "pet")
		else
			f:RegisterUnitEvent(HEALTH_EVENTS[i], "player")
		end
	end
	P.mana = OnMana()
	for i = 1, #POWER_EVENTS do
		if P.mana then
			f:RegisterUnitEvent(POWER_EVENTS[i], "player")
		else
			f:UnregisterEvent(POWER_EVENTS[i])
		end
	end
end

local function OnUnitEvent(_, event, unit, kind)
	if event == "UNIT_HEALTH" or event == "UNIT_POWER_UPDATE" or event == "UNIT_SPELLCAST_SUCCEEDED" then
		if not Stamp(event, unit, kind) then
			return
		end
	elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_ALIVE"
		or event == "PLAYER_UNGHOST" then
		Seed()
	elseif event == "UNIT_DISPLAYPOWER" then
		RegisterUnits()
	elseif event == "UNIT_MAXHEALTH" and not P.pet and not Secret(unit) and unit == "pet" then
		return
	end
	Fader:Poke()
end

-- the events while the player frame (or the pet's) is faded by choice
local function Watch(which, on)
	P[which] = on and true or false
	if P.player or P.pet then
		if not P.events then
			P.events = CreateFrame("Frame")
			Perf.SetScript(P.events, "OnEvent", OnUnitEvent)
		end
		local f = P.events
		for i = 1, #UNIT_EVENTS do
			f:RegisterEvent(UNIT_EVENTS[i])
		end
		f:RegisterUnitEvent("UNIT_PET", "player")
		f:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
		RegisterUnits()
		if on then
			Seed()
		end
	elseif P.events then
		P.events:UnregisterAllEvents()
	end
end

--------------------------------------------------------------------------------
-- The chat: back while you type
--------------------------------------------------------------------------------

local chat = { hooked = {} }

local function Typing()
	local util = rawget(_G, "ChatFrameUtil")
	local fn = type(util) == "table" and util.GetActiveWindow or rawget(_G, "ChatEdit_GetActiveWindow")
	if type(fn) ~= "function" then
		return false
	end
	local ok, box = pcall(fn)
	return ok and box ~= nil and not Secret(box)
end

local OnFocus = Shared("OnEditFocusGained / Lost on a chat line: the Fader", function()
	Fader:Poke()
end, "script")

local function ChatWatch(on)
	if not on then
		return
	end
	for i = 1, tonumber(rawget(_G, "NUM_CHAT_WINDOWS")) or 10 do
		local box = G("ChatFrame" .. i .. "EditBox")
		if box and not chat.hooked[box] and box.HookScript then
			chat.hooked[box] = true
			Perf.HookScript(box, "OnEditFocusGained", OnFocus)
			Perf.HookScript(box, "OnEditFocusLost", OnFocus)
		end
	end
end

--------------------------------------------------------------------------------
-- The elements
--------------------------------------------------------------------------------

local function Register()
	local F = Fader
	F:Register({ key = "player",
		frames = function() return Add({}, G("PlayerFrame")) end,
		mouse = function()
			local pf = G("PlayerFrame")
			local main = pf and pf.PlayerFrameContent and pf.PlayerFrameContent.PlayerFrameContentMain
			local bars = main and main.HealthBarsContainer
			local mana = main and main.ManaBarArea
			return Add(Add(Add({}, pf), bars and bars.HealthBar), mana and mana.ManaBar)
		end,
		needed = PlayerNeeded,
		own = function() return Add(Add({}, G("PetFrame")), G("PlayerCastingBarFrame")) end,
		watch = function(on) Watch("player", on) end })
	F:Register({ key = "pet", follows = "player", followsWhen = "petToo",
		frames = function() return Add({}, G("PetFrame")) end,
		mouse = function() return Add(Add(Add({}, G("PetFrame")), G("PetFrameHealthBar")), G("PetFrameManaBar")) end,
		needed = PetNeeded,
		watch = function(on) Watch("pet", on) end })
	F:Register({ key = "target",
		frames = function() return Add({}, G("TargetFrame")) end,
		mouse = function() return Mice({}, G("TargetFrame"), 4) end })
	F:Register({ key = "party",
		-- (the raid-style party frames are PartyFrame's child: they fade with it;
		-- Preview Party's stand-ins too, Core/ConfigPreview.lua)
		frames = function() return Add(Add({}, G("PartyFrame")), G("MelloUIPreviewParty")) end,
		mouse = function() return Mice({}, G("PartyFrame"), 4) end })
	F:Register({ key = "raid",
		frames = function() return Add({}, G("CompactRaidFrameContainer")) end,
		mouse = function() return Mice({}, G("CompactRaidFrameContainer"), 3) end })
	F:Register({ key = "buffs", frames = Auras,
		mouse = function()
			local out = {}
			for _, f in ipairs(Auras()) do
				Mice(out, f, 3)
			end
			return out
		end })
	for i = 1, 8 do
		local key = "bar" .. i
		F:Register({ key = key,
			frames = function() return Add({}, BarFrame(key)) end,
			mouse = function() return Named(BARS[key][2], 12, Add({}, BarFrame(key))) end })
	end
	F:Register({ key = "stance",
		frames = function() return Add(Add(Add({}, G("StanceBar")), G("PetActionBar")), G("PossessActionBar")) end,
		mouse = function() return Named("PossessButton", 2, Named("PetActionButton", 10, Named("StanceButton", 10))) end })
	F:Register({ key = "micro",
		frames = function() return Add({}, G("MicroMenuContainer") or G("MicroMenu")) end,
		mouse = function() return Mice({}, G("MicroMenu") or G("MicroMenuContainer"), 2) end })
	F:Register({ key = "bags",
		frames = function() return Add({}, G("BagsBar")) end,
		mouse = function() return Mice({}, G("BagsBar"), 2) end })
	F:Register({ key = "xp",
		frames = function()
			return Add(Add(Add({}, G("MainStatusTrackingBarContainer")), G("SecondaryStatusTrackingBarContainer")),
				not G("MainStatusTrackingBarContainer") and G("StatusTrackingBarManager") or nil)
		end,
		mouse = function()
			local out = Mice({}, G("MainStatusTrackingBarContainer"), 3)
			return Mice(out, G("SecondaryStatusTrackingBarContainer"), 3)
		end })
	F:Register({ key = "chat", frames = ChatFrames,
		mouse = function()
			local out = {}
			for _, f in ipairs(ChatFrames()) do
				Mice(out, f, 2)
			end
			return out
		end,
		needed = Typing,
		-- (MelloUI keeps the chat's line, tabs and buttons at full alpha: ChatPanel)
		fixedBase = 1,
		watch = ChatWatch })
	F:Register({ key = "minimap",
		frames = function() return Add({}, G("MinimapCluster")) end,
		-- (the cluster's own buttons; the map's pins are the map's: a pointer
		-- on one is still on the map's rect)
		mouse = function() return Mice(Add({}, G("Minimap")), G("MinimapCluster"), 1) end })
	F:Register({ key = "tracker",
		frames = function() return Add({}, G("MelloUIQuestTracker")) end,
		mouse = function() return Mice({}, G("MelloUIQuestTracker"), 4) end })
	F:Register({ key = "objectives",
		frames = function() return Add({}, G("ObjectiveTrackerFrame")) end,
		mouse = function() return Mice({}, G("ObjectiveTrackerFrame"), 3) end })
	-- (the user's test, 2026-10-01: MelloUI's own parts that fade their own
	-- alpha, on hosts the Fader fades: Fader:Host)
	F:Register({ key = "reminders",
		frames = function() return Add({}, F:Host("reminders")) end,
		mouse = function() return Mice({}, G("MelloUIReminders"), 3) end })
	F:Register({ key = "widgets",
		frames = function() return Add({}, F:Host("widgets")) end,
		mouse = function() return Mice({}, G("MelloUIWidgets"), 4) end })
	F:Register({ key = "route",
		frames = function() return Add({}, F:Host("route")) end,
		mouse = function() return Mice({}, G("MelloUIRouteMarker"), 2) end })
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local registered = false

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db
	if not registered then
		registered = true
		Register()
	end
	Fader:Start(db)
end

function M:OnDisable()
	Fader:Stop()
end

function M:OnSettingChanged(key, _, db)
	self.db = db
	Fader:Changed(key)
end

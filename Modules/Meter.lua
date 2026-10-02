--------------------------------------------------------------------------------
-- MelloUI - Damage Meter (0.17.0)
--
-- MelloUI's damage meter IN PLACE OF the game's (the user, 2026-10-01: "make
-- sure it knows that this is a replacement of the default damage meters, and
-- not have the original shown when using these custom ones"; the plan and
-- every decision: docs/plans/meter-and-gains.md, the sketches in
-- MelloUI-BuildData/output/meter_sketch). The module's switch is the master
-- switch, "Use MelloUI's Damage Meter (replaces the game's)", on:
--   * the game's meter is switched off by its own switch while it is on --
--     the CVar damageMeterEnabled (Settings > Advanced, "Enable Damage
--     Meter"), 0 out of combat, the user's value noted first and put back
--     when the module goes off. The game's data (C_DamageMeter) keeps
--     recording with it off (the user's check, 2026-10-01). The game's meter
--     windows never show then (DamageMeterMixin:ShouldBeShown), except while
--     Edit Mode edits them
--   * the values by the frames: three numbers per player -- the sword this
--     fight's damage per second (gold), the hourglass this run's (the text
--     colour), the cross healing per second (green); a zero a dim dash.
--     Yours on top of your frame, over its name plate (the user, 2026-10-01:
--     "on top of the Unitframe, or at least be moveable"), on MelloUI's one
--     mover ("metervalues", Your Values: Edit Layout moves it, Reset puts it
--     back on the frame); the party's ON TOP of each party frame, from the
--     room of the game's own spacing: Party Values switches the game's Show
--     Party Pets on (26 px between the frames instead of 10; the user's value
--     put back when off). MelloUI never moves or spaces the frames itself
--   * the race bar in a fight (Modules/MeterBar.lua), the summary in the
--     widget column after it, and the Fight History window with its chat
--     button (Modules/MeterHistory.lua)
-- The data: the game's own (C_DamageMeter; pets are merged into their owner
-- by the game, a pet's attacks are its owner's spells "Claw (Wolf)": never a
-- pet row, never counted twice; never ResetAllCombatSessions):
--   live      the Current session's damage and healing, read at most 4 times
--             a second while its updates come (a timer, no OnUpdate). In a
--             fight its amounts, names and GUIDs are SECRET: they only ever go
--             to FontString:SetText (Meter.Format: the game's own
--             abbreviation, one decimal) and StatusBar:SetMinMaxValues /
--             SetValue; the list's ORDER gives the ranks, isLocalPlayer and
--             classFilename are never secret. Your line is live by
--             isLocalPlayer; a party member's by their class while it is the
--             only one of it in the group, else a dash until the fight ends
--   the fight its record when it ends (PLAYER_REGEN_ENABLED, then the next
--             session update or RECORD_WAIT; all plain by then): its name
--             (the game's session name, else the first foe), time, length,
--             zone, run, won or lost, every source's name, class, damage,
--             DPS, healing and HPS, and your top 8 spells. A session already
--             recorded or with nothing done is not recorded again
--   the run   MelloUI's own, from its records: a new one at a dungeon or raid
--             entered alive (a ghost's corpse run keeps it), a change of the
--             group, or the first fight in another place; out in the world,
--             one since login. Run DPS = the run's damage / the run's fight
--             time. In a fight the hourglass shows it as of the last fight
-- Kept per character (MelloUIFights, SavedVariablesPerCharacter): the last
-- Fights Kept fights of THIS login, over a /reload, dropped at the next login
-- (isInitialLogin, and the login's own stamp for a module switched on later).
-- Nothing is made at login: one event frame with OnEnable; the lines with
-- the first placement after login (your frame) or in a group (the party's);
-- the race bar with the first fight; the History with its first open.
--
-- The shared table ns.Meter (MeterBar.lua and MeterHistory.lua):
--   Meter.M, Meter.TEXT, Meter.Store(), Meter.Fights() (oldest first),
--   Meter.Run(id), Meter.RunStats(id), Meter.Format(v) (plain or secret),
--   Meter.Plain(v), Meter.Big(v), Meter.Clock(seconds), Meter.Ordinal(n),
--   Meter.ClassIcon(classFile), Meter.KeyOf(source), Meter.Session(kind),
--   Meter.KIND, Meter.Last() -> the last record, Meter.Clear(),
--   Meter.Sources(kind) -> the Current session's sources (in a fight: secret
--   amounts), Meter.InFight()
-- /mello meter test: a made-up fight recorded (the summary, the History).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Meter")
local C_Timer = Perf.C_Timer
local Safe = MelloUI.Safe
local Secret, Num, Text, Finite = Safe.IsSecret, Safe.Number, Safe.Text, Safe.Finite
local W = MelloUI.Widgets
-- (0.17.1, docs/plans/game-look.md) the look of MelloUI's own parts: the
-- painted one with the reskin, the game's own without
local Look = MelloUI.Look
local pcall, type, pairs, ipairs, tostring = pcall, type, pairs, ipairs, tostring
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local tremove, sort, wipe = table.remove, table.sort, wipe

local NEW = "0.17.0"
local OWNER = "Meter"

-- the shared table (MeterBar.lua, MeterHistory.lua)
local Meter = { NEW = NEW, OWNER = OWNER }
ns.Meter = Meter

-- (one table: the file's main chunk stays far from Lua 5.1's 200 locals)
local T = {
	COALESCE = 0.25,        -- the live read: at most 4 a second
	RECORD_WAIT = 0.6,      -- the record this long after the fight, when no update came first
	RECORD_TRIES = 3,       -- ... tried again a second apart while a value still reads secret
	SPELLS = 8,             -- your spells kept per fight
	HISTORY = 100, HISTORY_MIN = 10, HISTORY_MAX = 200,
	PINS = 5, PINS_MIN = 2, PINS_MAX = 10,
	SUMMARY_HOLD = 8,       -- the summary's time in the column after a fight (user, 2026-10-01: "only few seconds
	                        -- before fading"); longer while the pointer is on it or its list is open
	LOGIN_SLACK = 10,       -- the login's stamp read again: within this, the same login
	-- the values lines
	SIZE = 11, GLYPH = 10, GAP = 6, INNER = 2, HEIGHT = 12, DIM = 0.45,
	-- yours on top of your frame (user, 2026-10-01): over the name plate,
	-- from the name's left; the row's width (its plate in Edit Layout)
	ME_Y = 6, ME_X = 46, MINE_W = 150,
	-- the party's on top of each member frame: from the name's left (46)
	PARTY_X = 46, PARTY_Y = 1,
}
Meter.T = T

-- the in-game strings (read only by convention)
local TEXT = {
	dash = "\226\128\147",          -- an en dash: a zero, or not known yet
	won = "Fight won",
	lost = "You died",
	you = "You",
	summaryLabel = "Fight summary",
	mineLabel = "Your Values",
	summaryHint = "Click: this fight in the Fight History",
	summaryText = "You %s \194\183 %s/s \194\183 #%d of %d",
	summarySolo = "You %s \194\183 %s/s",
	summaryHeal = "You %s healed \194\183 %s/s \194\183 #%d of %d",
	topFive = "The top five",
	topFiveDesc = "Everyone in the fight, best first.",
	history = "Fight History",
	historyDesc = "Every fight of this session.",
	trayFoot = "Click: the Fight History",
	world = "Out in the world",
	runOf = "%s, run %d",
	someone = "Someone",
	test = "A made-up fight was recorded: see the summary and the Fight History.",
	testCombat = "Not in a fight.",
	-- the preview's made-up fight (Core/Preview.lua)
	pvFoe = "Defias Pillager",
	pvClick = "A preview: this fight is made up and not in your Fight History.",
}
Meter.TEXT = TEXT

local M = MelloUI:RegisterModule("Meter", {
	title = "Damage Meter",
	desc = "MelloUI's damage meter in place of the game's: three numbers by every frame (this fight, this run, healing), a race bar for the group in a fight, a summary after it and a Fight History window. The game's own damage meter is switched off while it is on, and comes back as you had it when it is off.",
	icon = "Interface\\Icons\\Ability_DualWield",
	flavour = "How the fight went, where you already look.",
	role = "replaces",
	enabledByDefault = true,
	new = NEW,
	-- the player's own game settings, given back when off (the game's meter,
	-- the party's pets): never in a profile
	keep = { "savedMeter", "savedPets" },
	defaults = {
		values = true,
		party = true,
		bar = true,
		metric = "auto",
		pins = T.PINS,
		barWidth = 260,
		barHeight = 10,
		summary = true,
		history = true,
		historySize = T.HISTORY,
		raid = true,
	},
	options = {
		{ type = "toggle", key = "values", name = "Your Values", new = NEW,
		  desc = "Three numbers on top of your frame: the sword this fight's damage per second, the hourglass this run's, the cross your healing per second. Live in a fight, the last fight's after it. Move them in Edit Layout (Your Values)." },
		{ type = "toggle", key = "party", name = "Party Values", new = NEW,
		  desc = "The same three numbers on top of each party frame. To make room, the game's own Show Party Pets setting is switched on while this is on (the party frames stand a little further apart, and party pets show under them); your own setting comes back when it is off. With raid-style party frames: On Raid-Style Frames." },
		{ type = "toggle", key = "raid", name = "On Raid-Style Frames", new = "0.17.1",
		  desc = "A small DPS or healing number on the right of each raid-style or raid frame, beside the health. In a fight, players MelloUI cannot tell apart stay empty until it ends. Point at a frame for all three numbers." },
		{ type = "toggle", key = "bar", name = "Race Bar", new = NEW,
		  desc = "In a fight, one bar for the group: the top player at its right end with their value, everyone else a class icon at their share of the top, you the gold pin with the bar filled up to you. It fades in when the fight starts and out when it ends. The pointer on it lists everyone. Move it in Edit Layout." },
		{ type = "dropdown", key = "metric", name = "Race Bar Shows", new = NEW,
		  values = { { value = "auto", label = "Auto" }, { value = "dps", label = "Damage" }, { value = "hps", label = "Healing" } },
		  desc = "What the race bar races. Auto: healing while your group role is healer, else damage." },
		{ type = "slider", key = "pins", name = "Race Bar Pins", new = NEW, min = T.PINS_MIN, max = T.PINS_MAX, step = 1,
		  desc = "The most players on the race bar: the best ones, and always you." },
		{ type = "slider", key = "barWidth", name = "Race Bar Width", new = NEW, min = 150, max = 600, step = 10,
		  desc = "How wide the race bar is. Also in Edit Layout: right-click the race bar." },
		{ type = "slider", key = "barHeight", name = "Race Bar Height", new = NEW, min = 4, max = 24, step = 1,
		  desc = "How tall the race bar is (its pins and labels keep their size). Also in Edit Layout: right-click the race bar." },
		{ type = "toggle", key = "summary", name = "Fight Summary", new = NEW,
		  desc = "After a fight, for a few seconds in the widget column (longer while you point at it): won or lost and its length, your damage, DPS and rank, the ring your share of the group. The pointer on it shows the top five; a click opens the fight in the Fight History." },
		{ type = "toggle", key = "history", name = "Fight History", new = NEW,
		  desc = "The Fight History window: every fight of this session, grouped by run, with the damage, healing and your spells of each. It opens from its button in the chat's button column and from the summary. It takes the place of the game's meter windows." },
		{ type = "slider", key = "historySize", name = "Fights Kept", new = NEW, min = T.HISTORY_MIN, max = T.HISTORY_MAX, step = 10,
		  desc = "How many fights the history keeps, the oldest dropped first. Kept over a /reload; a new login starts it empty." },
	},
})
Meter.M = M

--------------------------------------------------------------------------------
-- Reads (secret-safe; a missing API is nil)
--------------------------------------------------------------------------------

local function EnumValue(group, name, fallback)
	local e = type(Enum) == "table" and Enum[group]
	local v = type(e) == "table" and e[name]
	return type(v) == "number" and v or fallback
end

local SESSION_CURRENT = EnumValue("DamageMeterSessionType", "Current", 1)
local KIND = {
	damage = EnumValue("DamageMeterType", "DamageDone", 0),
	healing = EnumValue("DamageMeterType", "HealingDone", 2),
}
Meter.KIND = KIND

local function Api(name)
	local api = _G.C_DamageMeter
	local fn = type(api) == "table" and api[name]
	return type(fn) == "function" and fn or nil
end

-- the Current session of a kind (in a fight: its amounts secret), or nil
function Meter.Session(kind)
	local fn = Api("GetCombatSessionFromType")
	if not fn then
		return nil
	end
	local ok, s = pcall(fn, SESSION_CURRENT, kind)
	if ok and type(s) == "table" then
		return s
	end
	return nil
end

-- its sources (the game's order: the best first), or nil
function Meter.Sources(kind)
	local s = Meter.Session(kind)
	local list = s and s.combatSources
	return type(list) == "table" and list or nil, s
end

function Meter.InFight()
	return MelloUI.InCombat() and true or false
end

local function Ask(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
	if ok then
		return a, b, c, d, e, f, g, h
	end
	return nil
end

-- a real frame (a widget's methods are functions)
local function IsFrame(f)
	return type(f) == "table" and type(f.GetObjectType) == "function"
end
Meter.IsFrame = IsFrame

local function MyGUID()
	return Text((Ask(_G.UnitGUID, "player")))
end

-- a source's key: its GUID, else its name (plain), else nil
function Meter.KeyOf(source)
	if type(source) ~= "table" then
		return nil
	end
	return Text(source.sourceGUID) or Text(source.name)
end

function Meter.ClassIcon(classFile)
	classFile = Text(classFile)
	return classFile and MelloUI.ClassIconPath and MelloUI:ClassIconPath(classFile) or nil
end

--------------------------------------------------------------------------------
-- Numbers: one decimal, the game's own abbreviation for a secret
--------------------------------------------------------------------------------

-- the breakpoints for a secret amount: "41.8", "1.2k", "3.4m" (the game's
-- AbbreviateNumbers, NumberAbbrevOptions; probed with a plain number the
-- first time, else the game's own meter's AbbreviateLargeNumbers)
local ABBREV = {
	breakpointData = {
		{ breakpoint = 1000000, abbreviation = "m", significandDivisor = 100000, fractionDivisor = 10, abbreviationIsGlobal = false },
		{ breakpoint = 1000, abbreviation = "k", significandDivisor = 100, fractionDivisor = 10, abbreviationIsGlobal = false },
		{ breakpoint = 0, abbreviation = "", significandDivisor = 0.1, fractionDivisor = 10, abbreviationIsGlobal = false },
	},
}
local abbrev = { probed = false, ok = false }

-- a plain amount as the lines say it
function Meter.Plain(v)
	v = Finite(v)
	if not v then
		return TEXT.dash
	end
	if v >= 1000000 then
		return ("%.1fm"):format(v / 1000000)
	elseif v >= 1000 then
		return ("%.1fk"):format(v / 1000)
	end
	return ("%.1f"):format(v)
end

local function Probe()
	abbrev.probed = true
	local fn = _G.AbbreviateNumbers
	if type(fn) ~= "function" then
		return
	end
	local ok1, a = pcall(fn, 41.83, ABBREV)
	local ok2, b = pcall(fn, 1234, ABBREV)
	abbrev.ok = ok1 and ok2 and Text(a) == "41.8" and Text(b) == "1.2k"
end

-- an amount (plain or secret) as text for SetText; nil for none
function Meter.Format(v)
	if v == nil then
		return nil
	end
	if not Secret(v) then
		return Meter.Plain(v)
	end
	if not abbrev.probed then
		Probe()
	end
	if abbrev.ok then
		local ok, s = pcall(_G.AbbreviateNumbers, v, ABBREV)
		if ok then
			return s
		end
	end
	local large = _G.AbbreviateLargeNumbers
	if type(large) == "function" then
		local ok, s = pcall(large, v)
		if ok then
			return s
		end
	end
	return nil
end

-- a plain total with the game's thousands ("2,510")
function Meter.Big(v)
	v = Finite(v)
	if not v then
		return TEXT.dash
	end
	v = floor(v + 0.5)
	local fn = _G.BreakUpLargeNumbers
	if type(fn) == "function" then
		local ok, s = pcall(fn, v)
		if ok and Text(s) then
			return s
		end
	end
	return tostring(v)
end

function Meter.Clock(seconds)
	seconds = Finite(seconds) or 0
	seconds = floor(seconds + 0.5)
	return ("%d:%02d"):format(floor(seconds / 60), seconds % 60)
end

local ORDINAL = { "1st", "2nd", "3rd" }
function Meter.Ordinal(n)
	return ORDINAL[n] or (n .. "th")
end

--------------------------------------------------------------------------------
-- The store: this login's fights (MelloUIFights, per character)
--------------------------------------------------------------------------------

local store = nil

-- this login's stamp: when it began (the same over a /reload)
local function LoginStamp()
	local since = Num((Ask(_G.GetSessionTime)))
	local now = Num((Ask(_G.time)))
	if since and now then
		return now - since
	end
	return nil
end

local function Drop(sv)
	wipe(sv.fights)
	wipe(sv.runs)
	sv.run, sv.session = nil, nil
end

function Meter.Store()
	if store then
		return store
	end
	local sv = rawget(_G, "MelloUIFights")
	if type(sv) ~= "table" then
		sv = {}
		_G.MelloUIFights = sv
	end
	if type(sv.fights) ~= "table" then
		sv.fights = {}
	end
	if type(sv.runs) ~= "table" then
		sv.runs = {}
	end
	local login = LoginStamp()
	if login and (type(sv.login) ~= "number" or abs(sv.login - login) > T.LOGIN_SLACK) then
		Drop(sv)
	end
	sv.login = login or sv.login
	store = sv
	return sv
end

function Meter.Fights()
	return Meter.Store().fights
end

function Meter.Run(id)
	return id and Meter.Store().runs[id] or nil
end

function Meter.Last()
	local fights = Meter.Fights()
	return fights[#fights]
end

-- the run's sums, made again when a fight joins or leaves it
local runCache = {}

function Meter.RunStats(id)
	if not id then
		return nil
	end
	local c = runCache[id]
	if c then
		return c
	end
	c = { dur = 0, fights = 0, by = {}, first = nil, last = nil }
	for _, f in ipairs(Meter.Fights()) do
		if f.run == id then
			c.fights = c.fights + 1
			c.dur = c.dur + (f.dur or 0)
			c.first = c.first or f
			c.last = f
			for _, s in ipairs(f.src) do
				local e = c.by[s.k]
				if not e then
					e = { d = 0, h = 0, n = s.n, c = s.c, me = s.me }
					c.by[s.k] = e
				end
				e.d, e.h = e.d + (s.d or 0), e.h + (s.h or 0)
			end
		end
	end
	runCache[id] = c
	return c
end

-- a player's run DPS / HPS (plain), or nil
local function RunRate(key, healing)
	local st = Meter.Store()
	local c = Meter.RunStats(st.run)
	local e = c and key and c.by[key]
	if not (e and c.dur > 0) then
		return nil
	end
	return (healing and e.h or e.d) / c.dur
end
Meter.RunRate = RunRate

function Meter.Clear()
	Drop(Meter.Store())
	wipe(runCache)
	MelloUI:Fire("meter", "clear")
end

--------------------------------------------------------------------------------
-- Where a fight is: the run's place and group
--------------------------------------------------------------------------------

local S = {
	ready = false, fighting = false, fightAt = 0, due = false, tries = 0, waiting = false,
	foe = nil, newRun = false, sig = nil, liveDue = false, summaryAt = nil, summary = nil,
	gameMeter = false, pets = false, cvarDue = false, linesOn = false, partyOn = false,
}

-- the instance's id while in a dungeon or raid, else "world"; and its name
local function Place()
	local name, kind, _, _, _, _, _, id = Ask(_G.GetInstanceInfo)
	kind = Text(kind)
	if (kind == "party" or kind == "raid") and Num(id) then
		return tostring(Num(id)), Text(name)
	end
	return "world", Text((Ask(_G.GetRealZoneText))) or Text((Ask(_G.GetZoneText)))
end

local PARTY_UNITS = { "party1", "party2", "party3", "party4" }
local RAID_UNITS = {}
for i = 1, 40 do
	RAID_UNITS[i] = "raid" .. i
end

-- the group's members as one text (sorted GUIDs); a secret one keeps the last
local sigParts = {}
local function GroupSig()
	wipe(sigParts)
	local raid = Ask(_G.IsInRaid)
	local units = (raid == true) and RAID_UNITS or PARTY_UNITS
	for i = 1, #units do
		local guid = Ask(_G.UnitGUID, units[i])
		if guid ~= nil then
			if Secret(guid) then
				return S.sig or ""
			end
			sigParts[#sigParts + 1] = guid
		end
	end
	sort(sigParts)
	S.sig = table.concat(sigParts, ",")
	return S.sig
end

-- the run a new fight belongs to (a new one at another place, another
-- group, or a dungeon entered alive)
local function RunFor(zone)
	local st = Meter.Store()
	local key, placeName = Place()
	local sig = GroupSig()
	local run = st.run and st.runs[st.run]
	if run and run.key == key and run.sig == sig and not S.newRun then
		return run.id
	end
	S.newRun = false
	local label = placeName or zone or TEXT.world
	local n = 1
	for _, r in ipairs(st.runs) do
		if r.zone == label then
			n = n + 1
		end
	end
	run = { id = #st.runs + 1, key = key, sig = sig, zone = label, n = n, instance = key ~= "world" }
	st.runs[run.id] = run
	st.run = run.id
	return run.id
end

-- a run's name as the History groups it ("The Deadmines, run 1"; out in
-- the world, the zone where it began)
function Meter.RunName(id)
	local run = Meter.Run(id)
	if not run then
		return TEXT.world
	end
	if run.instance then
		return TEXT.runOf:format(run.zone, run.n)
	end
	return run.zone
end

--------------------------------------------------------------------------------
-- The fight's record
--------------------------------------------------------------------------------

-- the game's name for its latest session, and its id (plain after a fight)
local function LatestSession()
	local fn = Api("GetAvailableCombatSessions")
	if not fn then
		return nil, nil
	end
	local ok, list = pcall(fn)
	if not (ok and type(list) == "table") then
		return nil, nil
	end
	local last = list[#list]
	if type(last) ~= "table" then
		return nil, nil
	end
	return Num(last.sessionID), Text(last.name)
end

local function SpellName(id)
	id = Num(id)
	if not id then
		return nil
	end
	local C_Spell = _G.C_Spell
	if type(C_Spell) == "table" and C_Spell.GetSpellName then
		local name = Text((Ask(C_Spell.GetSpellName, id)))
		if name then
			return name
		end
	end
	return Text((Ask(_G.GetSpellInfo, id)))
end

-- your top spells this fight (a pet's under its own name, as the game says it)
local function MySpells(guid)
	local fn = Api("GetCombatSessionSourceFromType")
	if not (fn and guid) then
		return {}
	end
	local ok, src = pcall(fn, SESSION_CURRENT, KIND.damage, guid)
	local spells = ok and type(src) == "table" and src.combatSpells
	local list = {}
	if type(spells) ~= "table" then
		return list
	end
	for _, sp in ipairs(spells) do
		local amount = Num(sp.totalAmount)
		local name = SpellName(sp.spellID)
		if amount and amount > 0 and name then
			local creature = Text(sp.creatureName)
			if creature and creature ~= "" then
				local fmt = Text(_G.DAMAGE_METER_SPELL_ENTRY_CREATURE) or "%s (%s)"
				local okF, joined = pcall(string.format, fmt, name, creature)
				name = okF and joined or name
			end
			list[#list + 1] = { n = name, a = amount }
		end
	end
	sort(list, function(a, b) return a.a > b.a end)
	for i = #list, T.SPELLS + 1, -1 do
		list[i] = nil
	end
	return list
end

-- the sources of both kinds merged by player: nil while a value still reads
-- secret (tried again), else the list, best damage first
local function MergedSources(dur)
	local dmg = Meter.Sources(KIND.damage)
	local heal = Meter.Sources(KIND.healing)
	local by, list = {}, {}
	local function Take(sources, healing)
		for _, src in ipairs(sources or {}) do
			local key = Meter.KeyOf(src)
			local amount = Num(src.totalAmount)
			if not (key and amount) then
				return false
			end
			local e = by[key]
			if not e then
				e = { k = key, n = Text(src.name) or TEXT.someone, c = Text(src.classFilename), d = 0, h = 0,
					me = src.isLocalPlayer == true or nil }
				by[key] = e
				list[#list + 1] = e
			end
			local rate = Num(src.amountPerSecond) or (dur > 0 and amount / dur or 0)
			if healing then
				e.h, e.hps = amount, rate
			else
				e.d, e.dps = amount, rate
			end
		end
		return true
	end
	if not (Take(dmg, false) and Take(heal, true)) then
		return nil
	end
	sort(list, function(a, b) return a.d > b.d end)
	return list
end

local Record   -- (below: the summary and the lines told)

local function TryRecord()
	if not S.due then
		return
	end
	S.waiting = false
	if MelloUI.InCombat() then
		-- (a new fight began first: this one's numbers are its now)
		S.due = false
		return
	end
	local sessionID, sessionName = LatestSession()
	local st = Meter.Store()
	if sessionID and st.session == sessionID then
		S.due = false   -- (no new session: nothing was done)
		return
	end
	local _, session = Meter.Sources(KIND.damage)
	local dur = Finite(session and session.durationSeconds)
	if not dur or dur <= 0 then
		dur = max(1, GetTime() - S.fightAt)
	end
	local sources = MergedSources(dur)
	if not sources then
		S.tries = S.tries + 1
		if S.tries < T.RECORD_TRIES then
			S.waiting = true
			C_Timer.After(1, TryRecord)
		else
			S.due = false
		end
		return
	end
	S.due = false
	local done = 0
	for _, s in ipairs(sources) do
		done = done + s.d + s.h
	end
	if done <= 0 then
		return
	end
	st.session = sessionID or st.session
	local _, zoneName = Place()
	local dead = Ask(_G.UnitIsDeadOrGhost, "player")
	local fight = {
		at = Num((Ask(_G.time))) or 0,
		clock = Text((Ask(_G.date, "%H:%M"))) or "",
		dur = dur,
		name = (sessionName and sessionName ~= "" and sessionName) or S.foe or zoneName or TEXT.world,
		zone = zoneName,
		won = dead ~= true,
		src = sources,
		sp = MySpells(MyGUID()),
	}
	fight.run = RunFor(zoneName)
	Record(fight)
end

local RecordSoon = function()
	if S.due and not S.waiting then
		S.waiting = true
		C_Timer.After(0.1, TryRecord)
	end
end

-- the fight's record kept: the history's cap, the run's sums, the summary
Record = function(fight)
	local st = Meter.Store()
	local fights = st.fights
	fights[#fights + 1] = fight
	local cap = Num(M.db and M.db.historySize) or T.HISTORY
	while #fights > cap do
		tremove(fights, 1)
	end
	wipe(runCache)
	S.summary, S.summaryAt = fight, GetTime()
	Meter.Summary()
	Meter.LinesAfter()
	MelloUI:Fire("meter", "fight", fight)
end

--------------------------------------------------------------------------------
-- The game's meter switched off while ours is on (its own CVar), and the
-- party frames' room (the game's Show Party Pets) while Party Values is on.
-- Both out of combat only: in a fight they wait for its end.
--------------------------------------------------------------------------------

local CVAR = { meter = "damageMeterEnabled", pets = "showPartyPets" }

-- one CVar held at `want` while `on` (its value noted in db[savedKey] the
-- first time), put back when not: MelloUI:HoldCVar (Core, 0.17.1: lifted
-- from here for the swing timers)
local function Hold(name, savedKey, on, want)
	MelloUI:HoldCVar(M.db, name, savedKey, on, want)
end

local Events   -- (below)

function Meter.Switches()
	if MelloUI.InCombat() then
		S.cvarDue = true
		Events()
		return
	end
	S.cvarDue = false
	local on = M.isEnabled and true or false
	Hold(CVAR.meter, "savedMeter", on, "0")
	Hold(CVAR.pets, "savedPets", on and M.db and M.db.party ~= false or false, "1")
end

--------------------------------------------------------------------------------
-- The values lines: yours under your frame's stack, the party's on top of
-- each party frame. Anchors only (laid by one pass at the events that move
-- the stack); the texts set at most 4 times a second in a fight
--------------------------------------------------------------------------------

local Lines = { me = nil, party = {} }
Meter.Lines = Lines
local PARTS = { "sword", "hourglass", "heal" }

-- a part's colours: the sword gold, the hourglass the text colour, the
-- cross healing's green (the meaning colour Combat Text's heals wear; the
-- game's gold, white and green in its look: MelloUI.Look)
local TINT = { sword = "gold", hourglass = "text", heal = "heal" }
local function PaintPart(p)
	local tint = TINT[p.kind] or "text"
	Look.Paint(p.glyph, tint, "vertex")
	Look.Tint(p.text, tint)
end

Meter.PaintPart = PaintPart   -- (the raid-style frames' number: Modules/MeterRaid.lua)

local BAND = { alpha = 0.6, feather = 10 }

local function NewLine(parent, align)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(1, T.HEIGHT)
	f:EnableMouse(false)
	local line = { frame = f, align = align, parts = {} }
	for i, kind in ipairs(PARTS) do
		local g = f:CreateTexture(nil, "ARTWORK")
		W.Glyph(g, kind)
		g:SetSize(T.GLYPH, T.GLYPH)
		local fs = f:CreateFontString(nil, "OVERLAY")
		Look.Text(fs, "text", T.SIZE)
		fs:SetShadowOffset(1, -1)
		fs:SetText(TEXT.dash)
		local p = { glyph = g, text = fs, kind = kind }
		PaintPart(p)
		line.parts[i] = p
	end
	-- chained by anchors: a secret text has no width to read, the engine
	-- lays it
	local prev = nil
	if align == "LEFT" then
		for _, p in ipairs(line.parts) do
			if prev then
				p.glyph:SetPoint("LEFT", prev.text, "RIGHT", T.GAP, 0)
			else
				p.glyph:SetPoint("LEFT", f, "LEFT", 0, 0)
			end
			p.text:SetPoint("LEFT", p.glyph, "RIGHT", T.INNER, 0)
			prev = p
		end
	else
		for i = #line.parts, 1, -1 do
			local p = line.parts[i]
			if prev then
				p.text:SetPoint("RIGHT", prev.glyph, "LEFT", -T.GAP, 0)
			else
				p.text:SetPoint("RIGHT", f, "RIGHT", 0, 0)
			end
			p.glyph:SetPoint("RIGHT", p.text, "LEFT", -T.INNER, 0)
			prev = p
		end
	end
	local band = MelloUI.Shade:Band(f, BAND)
	if band then
		band:Anchor(line.parts[1].glyph, line.parts[#line.parts].text, 6, MelloUI.Shade:LinePadY(T.SIZE))
		Look.Hide(band)   -- (the soft band is the painted look's: none in the game's)
	end
	line.band = band
	return line
end

-- a value: a plain or secret number, nil for "none" (a dim dash)
local function SetPart(p, v)
	if v ~= nil and not Secret(v) and (Finite(v) or 0) <= 0 then
		v = nil
	end
	local text = Meter.Format(v)
	if text == nil then
		p.text:SetText(TEXT.dash)
		p.text:SetAlpha(T.DIM)
	else
		p.text:SetText(text)
		p.text:SetAlpha(1)
	end
end

local function SetLine(line, fight, run, heal)
	if not line then
		return
	end
	SetPart(line.parts[1], fight)
	SetPart(line.parts[2], run)
	SetPart(line.parts[3], heal)
end

-- the last fight's entry for a key (plain), or nil (Meter.LastEntry)
local function LastEntry(key)
	local last = Meter.Last()
	if not (last and key) then
		return nil
	end
	for _, s in ipairs(last.src) do
		if s.k == key then
			return s
		end
	end
	return nil
end

Meter.LastEntry = LastEntry

-- the last fight's numbers on a line (out of a fight, or the party's in one
-- when they cannot be told apart)
local function LineFromRecord(line, key)
	local e = LastEntry(key)
	SetLine(line, e and e.dps, RunRate(key, false), e and e.hps)
end

-- the party's units and their keys (plain GUIDs out of a fight)
local function UnitKey(unit)
	local guid = Ask(_G.UnitGUID, unit)
	if guid ~= nil and not Secret(guid) then
		return guid
	end
	return Text((Ask(_G.UnitName, unit)))
end

local function MemberFrame(i)
	local pf = _G.PartyFrame
	local f = IsFrame(pf) and pf["MemberFrame" .. i]
	return IsFrame(f) and f or nil
end

local function PartyLine(i)
	local line = Lines.party[i]
	if line then
		return line
	end
	local member = MemberFrame(i)
	if not member then
		return nil
	end
	line = NewLine(member, "LEFT")
	line.frame:SetPoint("BOTTOMLEFT", member, "TOPLEFT", T.PARTY_X, T.PARTY_Y)
	Lines.party[i] = line
	return line
end

-- after a fight (and at a placement): every line from the records
function Meter.LinesAfter()
	if Meter.Raid and Meter.Raid.After then
		Meter.Raid.After()
	end
	if not S.linesOn then
		return
	end
	local me = MyGUID()
	if Lines.me and M.db.values ~= false then
		LineFromRecord(Lines.me, me)
	end
	if S.partyOn then
		for i = 1, #PARTY_UNITS do
			local line = Lines.party[i]
			if line then
				LineFromRecord(line, UnitKey(PARTY_UNITS[i]))
			end
		end
	end
end

-- Who is who in a fight (0.17.1: one way for the party lines and the
-- raid-style frames, Modules/MeterRaid.lua). The game hides a source's name
-- and GUID in a fight; its class and isLocalPlayer stay plain. A unit is its
-- source when it is you (isLocalPlayer), or when its class is the only one
-- of its kind in the group (yours counted); else nil (nothing shown).
--   Meter.WhoCount()              the group's classes counted (once per read)
--   Meter.SourceFor(unit, sources) -> the unit's source, or nil
local whoCount = {}

function Meter.WhoCount()
	wipe(whoCount)
	local raid = Ask(_G.IsInRaid) == true
	local units, n = PARTY_UNITS, #PARTY_UNITS
	if raid then
		units, n = RAID_UNITS, math.min(40, Num((Ask(_G.GetNumGroupMembers))) or 0)
	end
	for i = 1, n do
		local _, class = Ask(_G.UnitClass, units[i])
		class = Text(class)
		if class then
			whoCount[class] = (whoCount[class] or 0) + 1
		end
	end
	if not raid then
		-- (yours: a raid's units hold you already)
		local _, mine = Ask(_G.UnitClass, "player")
		mine = Text(mine)
		if mine then
			whoCount[mine] = (whoCount[mine] or 0) + 1
		end
	end
end

function Meter.SourceFor(unit, sources)
	if type(unit) ~= "string" or type(sources) ~= "table" then
		return nil
	end
	local me = unit == "player"
	if not me then
		local same = Ask(_G.UnitIsUnit, unit, "player")
		me = not Secret(same) and same == true
	end
	if me then
		for _, src in ipairs(sources) do
			if src.isLocalPlayer == true then
				return src
			end
		end
		return nil
	end
	local _, class = Ask(_G.UnitClass, unit)
	class = Text(class)
	if not class or whoCount[class] ~= 1 then
		return nil
	end
	for _, src in ipairs(sources) do
		if src.isLocalPlayer ~= true and Text(src.classFilename) == class then
			return src
		end
	end
	return nil
end

-- in a fight: yours live (isLocalPlayer); a party member's by Meter.SourceFor
-- (their class while no one else in the group has it), else a dash
local function LinesLive(dmg, heal)
	if not S.linesOn then
		return
	end
	local mine, myHeal = nil, nil
	for _, src in ipairs(dmg or {}) do
		if src.isLocalPlayer == true then
			mine = src
			break
		end
	end
	for _, src in ipairs(heal or {}) do
		if src.isLocalPlayer == true then
			myHeal = src
			break
		end
	end
	if Lines.me and M.db.values ~= false then
		SetLine(Lines.me, mine and mine.amountPerSecond, RunRate(MyGUID(), false), myHeal and myHeal.amountPerSecond)
	end
	if not S.partyOn then
		return
	end
	for i, unit in ipairs(PARTY_UNITS) do
		local line = Lines.party[i]
		if line then
			local d, h = Meter.SourceFor(unit, dmg), Meter.SourceFor(unit, heal)
			SetLine(line, d and d.amountPerSecond, RunRate(UnitKey(unit), false), h and h.amountPerSecond)
		end
	end
end

-- yours: on top of your frame, over its name plate, from the name's left as
-- the party's are (the home of its mover: Edit Layout moves it)
local function MineHome(f)
	f:ClearAllPoints()
	local name, pf = _G.PlayerName, _G.PlayerFrame
	if IsFrame(name) then
		f:SetPoint("BOTTOMLEFT", name, "TOPLEFT", 0, T.ME_Y)
	elseif IsFrame(pf) then
		f:SetPoint("BOTTOMLEFT", pf, "TOPLEFT", T.ME_X, 0)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
	end
end

local function MineWanted()
	return M.isEnabled and M.db and M.db.values ~= false or false
end

-- a frame of ours on UIParent (so Edit Layout can move it), following your
-- frame: shown with it, faded with it (post-hooks on the player frame,
-- copying only)
local function MineFollow()
	local line = Lines.me
	local pf = _G.PlayerFrame
	if not (line and IsFrame(pf)) then
		return
	end
	local ok, shown = pcall(pf.IsVisible, pf)
	line.frame:SetShown(S.linesOn and MineWanted() and (not ok or shown ~= false))
	local okA, a = pcall(pf.GetAlpha, pf)
	a = okA and Num(a) or 1
	if line.alpha ~= a then
		line.alpha = a
		line.frame:SetAlpha(a)
	end
end

local function MakeMine()
	local line = NewLine(UIParent, "LEFT")
	line.frame:SetSize(T.MINE_W, T.HEIGHT)
	line.frame:SetFrameStrata("LOW")
	Lines.me = line
	MineHome(line.frame)
	line.entry = MelloUI:RegisterMover(line.frame, line.frame, { key = "metervalues", default = MineHome,
		min = 0.5, max = 2, base = 1, label = TEXT.mineLabel, page = "BarsMeters", when = MineWanted })
	if not MelloUI:RestorePosition("metervalues", line.frame) then
		MineHome(line.frame)
	end
	local pf = _G.PlayerFrame
	if IsFrame(pf) then
		Perf.HookScript(pf, "OnShow", MineFollow)
		-- (hidden with it: told directly, a frame may still read shown in
		-- its own OnHide)
		Perf.HookScript(pf, "OnHide", function()
			if Lines.me then
				Lines.me.frame:Hide()
			end
		end)
		Perf.hooksecurefunc(pf, "SetAlpha", MineFollow)
	end
	return line
end

-- the one placement pass: the lines made where wanted, shown or hidden, laid
function Meter.PlaceLines()
	if not S.linesOn then
		return
	end
	local db = M.db
	if db.values ~= false and not Lines.me and IsFrame(_G.PlayerFrame) then
		MakeMine()
	end
	MineFollow()
	local grouped = Ask(_G.IsInGroup) == true and Ask(_G.IsInRaid) ~= true
	for i = 1, #PARTY_UNITS do
		local want = S.partyOn and grouped
		local line = want and PartyLine(i) or Lines.party[i]
		if line then
			line.frame:SetShown(want and true or false)
		end
	end
	if S.fighting then
		local dmg = Meter.Sources(KIND.damage)
		local heal = Meter.Sources(KIND.healing)
		LinesLive(dmg, heal)
	else
		Meter.LinesAfter()
	end
end

local function HideLines()
	if Lines.me then
		Lines.me.frame:Hide()
	end
	for _, line in pairs(Lines.party) do
		line.frame:Hide()
	end
end

local function Repaint()
	local function Each(line)
		for _, p in ipairs(line.parts) do
			PaintPart(p)
		end
	end
	if Lines.me then
		Each(Lines.me)
	end
	for _, line in pairs(Lines.party) do
		Each(line)
	end
end

--------------------------------------------------------------------------------
-- The live read: at most 4 a second while the session's updates come
--------------------------------------------------------------------------------

local function LiveRead()
	S.liveDue = false
	if not (M.isEnabled and S.fighting) then
		return
	end
	local dmg = Meter.Sources(KIND.damage)
	local heal = Meter.Sources(KIND.healing)
	Meter.WhoCount()
	LinesLive(dmg, heal)
	if Meter.Bar and Meter.Bar.Live then
		Meter.Bar.Live(dmg, heal)
	end
	if Meter.Raid and Meter.Raid.Live then
		Meter.Raid.Live(dmg, heal)
	end
end

local function LiveSoon()
	if S.liveDue then
		return
	end
	S.liveDue = true
	C_Timer.After(T.COALESCE, LiveRead)
end

--------------------------------------------------------------------------------
-- The summary: a row of the widget column after a fight (Core/Reminders.lua)
--------------------------------------------------------------------------------

local SUMMARY_KEY = "meterSummary"
local function Rem()
	return MelloUI.Reminders
end

-- your entry in a fight, your rank and the group's count (by damage, or by
-- healing for a healer's fight)
local function Mine(fight)
	if not fight then
		return nil
	end
	for i, s in ipairs(fight.src) do
		if s.me then
			local healing = s.d <= 0 and s.h > 0
			if healing then
				local rank = 1
				for _, o in ipairs(fight.src) do
					if o ~= s and o.h > s.h then
						rank = rank + 1
					end
				end
				return s, rank, #fight.src, true
			end
			return s, i, #fight.src, false
		end
	end
	return nil
end
Meter.Mine = Mine

local function SummaryShare()
	local fight = S.summary
	local s, _, _, healing = Mine(fight)
	if not s then
		return nil
	end
	local total = 0
	for _, o in ipairs(fight.src) do
		total = total + (healing and o.h or o.d)
	end
	if total <= 0 then
		return nil
	end
	return min(1, (healing and s.h or s.d) / total)
end

-- the top five, best first (the tray and the tooltip)
local function TopFive(fight)
	local list = {}
	for i = 1, min(5, #(fight and fight.src or {})) do
		list[i] = fight.src[i]
	end
	return list
end

local function OpenHistory(fight)
	if fight and fight.preview then
		MelloUI:Announce(TEXT.pvClick, "info")
		return
	end
	if Meter.OpenHistory then
		Meter.OpenHistory(fight)
	end
end

-- the summary's row under the pointer, or its list open
local function SummaryHeld()
	local r = Rem()
	local col = r and r.Column and r:Column()
	for _, row in ipairs(col and col.rows or {}) do
		if row.key == SUMMARY_KEY and row:IsShown() then
			local ok, over = pcall(row.IsMouseOver, row)
			return (ok and over == true) or row.trayOpen == true
		end
	end
	return false
end

-- up for SUMMARY_HOLD seconds after the fight, out of combat; held while
-- looked at, and two seconds more after the pointer leaves
local function SummaryUp()
	if not (S.summary and S.summaryAt) or MelloUI.InCombat() then
		return false
	end
	if GetTime() - S.summaryAt < T.SUMMARY_HOLD then
		return true
	end
	if SummaryHeld() then
		S.summaryAt = GetTime() - T.SUMMARY_HOLD + 2
		return true
	end
	return false
end

local SUMMARY = {
	key = SUMMARY_KEY, column = true, label = TEXT.summaryLabel, hint = TEXT.summaryHint,
	enabled = function()
		return M.isEnabled and M.db and M.db.summary ~= false or false
	end,
	check = SummaryUp,
	title = function()
		local fight = S.summary
		return fight and (fight.won and TEXT.won or TEXT.lost) or TEXT.summaryLabel
	end,
	text = function()
		local fight = S.summary
		local s, rank, of, healing = Mine(fight)
		if not s then
			return ""
		end
		local amount, rate = healing and s.h or s.d, healing and s.hps or s.dps
		if healing then
			return TEXT.summaryHeal:format(Meter.Big(amount), Meter.Plain(rate), rank, of)
		elseif of <= 1 then
			return TEXT.summarySolo:format(Meter.Big(amount), Meter.Plain(rate))
		end
		return TEXT.summaryText:format(Meter.Big(amount), Meter.Plain(rate), rank, of)
	end,
	time = function()
		local fight = S.summary
		return fight and Meter.Clock(fight.dur) or nil
	end,
	icon = function()
		local s = Mine(S.summary)
		local _, class = Ask(_G.UnitClass, "player")
		return Meter.ClassIcon(s and s.c or class) or "Interface\\Icons\\Ability_DualWield"
	end,
	fraction = SummaryShare,
	onClick = function()
		OpenHistory(S.summary)
	end,
	tray = function(_, rows)
		local fight = S.summary
		local list = TopFive(fight)
		for i, s in ipairs(list) do
			local r = rows[i] or {}
			rows[i] = r
			r.glyph, r.onClick = nil, nil
			r.icon = Meter.ClassIcon(s.c)
			r.text = Meter.Ordinal(i) .. "  " .. (s.me and TEXT.you or s.n)
			r.right = Meter.Big(s.d) .. "  " .. Meter.Plain(s.dps) .. "/s"
		end
		rows.n = #list
		return TEXT.trayFoot
	end,
	tooltip = function(_, tip)
		local QI = MelloUI.QuestInk
		local tr, tg, tb = Look.RoleColour("text")   -- (the palette's text, the game's white)
		for i, s in ipairs(TopFive(S.summary)) do
			local r, g, b = tr, tg, tb
			local cr, cg, cb
			if QI and QI.ClassColour then
				cr, cg, cb = QI.ClassColour(s.c)
			end
			if cr then
				r, g, b = cr, cg, cb
			end
			tip:AddDoubleLine(Meter.Ordinal(i) .. " " .. (s.me and TEXT.you or s.n),
				Meter.Big(s.d) .. "  " .. Meter.Plain(s.dps) .. "/s", r, g, b, tr, tg, tb)
		end
	end,
	actions = {
		{ glyph = "list", tip = TEXT.topFive, desc = TEXT.topFiveDesc, tray = true },
		{ glyph = "chart", tip = TEXT.history, desc = TEXT.historyDesc, fn = function() OpenHistory(S.summary) end },
	},
}

Meter.SUMMARY = SUMMARY   -- (read only: the tests')
local summary = { registered = false, timer = false }

local SummaryRefresh   -- (below)

-- one timer at a time: the summary looked at again after `delay`
local function SummaryLater(delay)
	if not summary.timer then
		summary.timer = true
		C_Timer.After(delay, SummaryRefresh)
	end
end

SummaryRefresh = function()
	summary.timer = false
	local r = Rem()
	if r and summary.registered then
		r:Refresh(SUMMARY_KEY)
	end
	-- (still up: its hold not over, or the pointer on it -- looked at again)
	if summary.registered and SummaryUp() then
		SummaryLater(1)
	end
end

function Meter.Summary()
	local r = Rem()
	local want = M.isEnabled and M.db and M.db.summary ~= false and true or false
	if want ~= summary.registered and r then
		summary.registered = want
		if want then
			r:Register(SUMMARY)
		else
			r:Unregister(SUMMARY_KEY)
		end
	end
	if want and r then
		local up = SummaryUp()
		r:Refresh(SUMMARY_KEY, S.summary ~= nil and up)
		if up then
			SummaryLater(T.SUMMARY_HOLD + 0.1)
		end
	end
end

--------------------------------------------------------------------------------
-- Events: the module's one frame
--------------------------------------------------------------------------------

local events = nil
local FIGHT_EVENTS = { "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_COMBAT_SESSION_UPDATED" }

local function FightStart()
	S.fighting, S.fightAt, S.due = true, GetTime(), false
	local foe = Ask(_G.UnitName, "target")
	local hostile = Ask(_G.UnitCanAttack, "player", "target")
	S.foe = hostile == true and Text(foe) or nil
	if summary.registered and Rem() then
		Rem():Refresh(SUMMARY_KEY)
	end
	if Meter.Bar and Meter.Bar.Fight then
		Meter.Bar.Fight(true)
	end
	if Meter.Raid and Meter.Raid.Fight then
		Meter.Raid.Fight()
	end
	LiveSoon()
end

local function FightEnd()
	S.fighting = false
	-- (the record at the next session update, else after RECORD_WAIT)
	S.due, S.tries, S.waiting = true, 0, false
	C_Timer.After(T.RECORD_WAIT, TryRecord)
	if Meter.Bar and Meter.Bar.Fight then
		Meter.Bar.Fight(false)
	end
	if S.cvarDue then
		Meter.Switches()
	end
end

local function OnEvent(_, event, a1, a2)
	if not M.isEnabled then
		-- (switched off in a fight: the game's meter and Show Party Pets
		-- back at its end)
		if event == "PLAYER_REGEN_ENABLED" and S.cvarDue then
			Meter.Switches()
			Events()
		end
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		if a1 == true then
			-- (a new login: the last one's fights go)
			Drop(Meter.Store())
			wipe(runCache)
		elseif a2 ~= true then
			-- a dungeon or raid entered alive: a new run (a ghost's corpse
			-- run, or a /reload, keeps it)
			local key = Place()
			local ghost = Ask(_G.UnitIsDeadOrGhost, "player")
			if key ~= "world" and ghost ~= true then
				S.newRun = true
			end
		end
		if S.ready then
			Meter.Switches()
			Meter.PlaceLines()
		end
		return
	end
	if not S.ready then
		return   -- (the login's own frames: Ready comes after them)
	end
	if event == "PLAYER_REGEN_DISABLED" then
		FightStart()
	elseif event == "PLAYER_REGEN_ENABLED" then
		FightEnd()
		Meter.PlaceLines()
	elseif event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" or event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
		if S.fighting then
			LiveSoon()
		elseif S.due then
			RecordSoon()
		end
	elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then
		if not MelloUI.InCombat() then
			Meter.PlaceLines()
		end
	elseif event == "DAMAGE_METER_RESET" then
		LiveSoon()
	elseif event == "CVAR_UPDATE" then
		-- the game's meter switched on again (its settings), or Show Party
		-- Pets off, while ours holds them: held again (out of combat)
		if (a1 == CVAR.meter or a1 == CVAR.pets) and not MelloUI.InCombat() then
			Meter.Switches()
		end
	end
end

Events = function()
	if not events then
		events = CreateFrame("Frame")
		Perf.SetScript(events, "OnEvent", OnEvent)
	end
	if not M.isEnabled then
		events:UnregisterAllEvents()
		if S.cvarDue then
			events:RegisterEvent("PLAYER_REGEN_ENABLED")
		end
		return
	end
	for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
		"GROUP_ROSTER_UPDATE", "DAMAGE_METER_RESET", "CVAR_UPDATE" }) do
		pcall(events.RegisterEvent, events, e)
	end
	for _, e in ipairs(FIGHT_EVENTS) do
		pcall(events.RegisterEvent, events, e)
	end
	pcall(events.RegisterUnitEvent, events, "UNIT_PET", "player")
end

--------------------------------------------------------------------------------
-- A made-up fight (/mello meter test): the summary and the History to see
--------------------------------------------------------------------------------

local SAMPLE = {
	{ n = "Fellaria", c = "MAGE", d = 2184, h = 0 },
	{ n = "Shadeleaf", c = "HUNTER", d = 1946, h = 0 },
	{ n = "Tarnok", c = "SHAMAN", d = 1402, h = 120 },
	{ n = "Brightwood", c = "PRIEST", d = 388, h = 2734 },
}

function Meter.TestFight()
	if MelloUI.InCombat() then
		MelloUI:Print(TEXT.testCombat)
		return
	end
	local dur = 42
	local _, class = Ask(_G.UnitClass, "player")
	local me = { k = MyGUID() or "me", n = Text((Ask(_G.UnitName, "player"))) or TEXT.you,
		c = Text(class), d = 2510, h = 0, me = true }
	local src = { me }
	for _, s in ipairs(SAMPLE) do
		src[#src + 1] = { k = "sample:" .. s.n, n = s.n, c = s.c, d = s.d, h = s.h }
	end
	for _, s in ipairs(src) do
		s.dps, s.hps = s.d / dur, s.h / dur
	end
	sort(src, function(a, b) return a.d > b.d end)
	local _, zoneName = Place()
	local fight = {
		at = Num((Ask(_G.time))) or 0, clock = Text((Ask(_G.date, "%H:%M"))) or "", dur = dur,
		name = "Defias Pillager", zone = zoneName, won = true, src = src,
		sp = { { n = "Mortal Strike", a = 1020 }, { n = "Auto Attack", a = 690 }, { n = "Rend", a = 412 },
			{ n = "Heroic Strike", a = 388 } },
	}
	fight.run = RunFor(zoneName)
	Record(fight)
	MelloUI:Print(TEXT.test)
end

-- /mello meter test
function M:SlashTest()
	Meter.TestFight()
end

--------------------------------------------------------------------------------
-- The preview (0.17.0, Core/Preview.lua): a made-up fight that is never
-- recorded. Your numbers tick over your frame on the scene's hits; in a party
-- scene the stand-ins' numbers (Core/ConfigPreview.lua) and the race bar too;
-- after its kill the summary row shows it (a click says it is made up). Its
-- stop puts the last real fight back on every line and the summary's own
-- state back.
--------------------------------------------------------------------------------

local pv = { fight = nil, saved = nil, savedAt = nil, lines = {}, bar = {} }
local PV_ME = { dps = 48, hps = 0 }

local function ByDamage(a, b)
	return a.d > b.d
end

local function PvFight(mode)
	local P = MelloUI.Preview
	local _, class = Ask(_G.UnitClass, "player")
	local src = { { k = "preview:me", n = Text((Ask(_G.UnitName, "player"))) or TEXT.you, c = Text(class),
		rate = PV_ME.dps, hrate = PV_ME.hps, d = 0, h = 0, dps = 0, hps = 0, me = true } }
	if mode == "party" and P then
		for i, m in ipairs(P.PARTY) do
			src[#src + 1] = { k = "preview:" .. i, n = m.name, c = m.class, rate = m.dps, hrate = m.hps,
				d = 0, h = 0, dps = 0, hps = 0, party = i }
		end
	end
	return { preview = true, name = TEXT.pvFoe, zone = "", won = true, dur = 0, src = src, sp = {} }
end

-- the made-up fight after hit n: its time and every amount, best first
local function PvAt(n)
	local f = pv.fight
	local P = MelloUI.Preview
	local every = P and P.T and P.T.HIT_EVERY or 1
	f.dur = math.max(1, n * every)
	-- (the pull: nothing dealt yet, every line at its dash)
	local k = n > 0 and 1 or 0
	for _, s in ipairs(f.src) do
		s.dps, s.hps = s.rate * k, s.hrate * k
		s.d, s.h = math.floor(s.rate * f.dur * k + 0.5), math.floor(s.hrate * f.dur * k + 0.5)
	end
	sort(f.src, ByDamage)
end

-- a stand-in's line (Core/Preview.lua's), as a party frame's (PartyLine), on
-- the stand-ins' holder
local function PvLine(i)
	local P = MelloUI.Preview
	local stand = P and P.StandIn and P:StandIn(i)
	if not stand then
		return nil
	end
	local line = pv.lines[i]
	if not line then
		line = NewLine(stand:GetParent(), "LEFT")
		pv.lines[i] = line
	end
	line.frame:ClearAllPoints()
	line.frame:SetPoint("BOTTOMLEFT", stand, "TOPLEFT", T.PARTY_X * stand:GetScale(), T.PARTY_Y)
	line.frame:Show()
	return line
end

-- the numbers on every line, and the race bar's pins
local function PvShow(mode)
	local f = pv.fight
	for _, s in ipairs(f.src) do
		if s.me then
			if Lines.me and M.db.values ~= false then
				SetLine(Lines.me, s.dps, s.dps, s.hps)
			end
		elseif s.party and mode == "party" and S.partyOn then
			local line = PvLine(s.party)
			if line then
				SetLine(line, s.dps, s.dps, s.hps)
			end
		end
	end
	if mode == "party" and Meter.Bar and Meter.Bar.Preview then
		local list = pv.bar
		for i, s in ipairs(f.src) do
			local e = list[i] or {}
			list[i] = e
			e.name, e.classFilename = s.me and TEXT.you or s.n, s.c
			e.totalAmount, e.amountPerSecond, e.isLocalPlayer = s.d, s.dps, s.me or nil
		end
		for i = #f.src + 1, #list do
			list[i] = nil
		end
		Meter.Bar.Preview(true, list)
	end
end

local function OnPreview(beat, mode, n)
	if not (M.isEnabled and S.linesOn) then
		return
	end
	if beat == "start" then
		local P = MelloUI.Preview
		if not (P and P:Plays("meter")) then
			return
		end
		pv.fight = PvFight(mode)
		pv.saved, pv.savedAt = S.summary, S.summaryAt
	elseif not pv.fight then
		return
	elseif beat == "pull" then
		PvAt(0)
		PvShow(mode)
	elseif beat == "hit" then
		PvAt(n)
		PvShow(mode)
	elseif beat == "kill" then
		if Meter.Bar and Meter.Bar.Preview then
			Meter.Bar.Preview(false)
		end
		S.summary, S.summaryAt = pv.fight, GetTime()
		Meter.Summary()
	elseif beat == "stop" then
		pv.fight = nil
		for _, line in pairs(pv.lines) do
			line.frame:Hide()
		end
		if Meter.Bar and Meter.Bar.Preview then
			Meter.Bar.Preview(false)
		end
		S.summary, S.summaryAt = pv.saved, pv.savedAt
		pv.saved, pv.savedAt = nil, nil
		Meter.Summary()
		Meter.LinesAfter()
	end
end

--------------------------------------------------------------------------------
-- Turning it on and off
--------------------------------------------------------------------------------

local function Apply()
	local on = M.isEnabled and true or false
	if on and not S.ready then
		Events()
		return
	end
	S.linesOn = on
	S.partyOn = on and M.db and M.db.party ~= false or false
	Events()
	Meter.Switches()
	if on then
		Meter.PlaceLines()
	else
		HideLines()
		S.fighting, S.due = false, false
	end
	Meter.Summary()
	if Meter.Bar and Meter.Bar.Apply then
		Meter.Bar.Apply()
	end
	if Meter.HistoryApply then
		Meter.HistoryApply()
	end
	if Meter.Raid and Meter.Raid.Apply then
		Meter.Raid.Apply()
	end
end

local function OnEditLayout()
	if Meter.Bar and Meter.Bar.Samples then
		Meter.Bar.Samples()
	end
end

function M:OnInit(db)
	self.db = db
	-- (the preview's made-up fight: OnPreview, above)
	MelloUI:On("preview", OnPreview, "Meter: preview")
end

-- after the login's own frames (at once for a module switched on later)
local function Ready()
	if not M.isEnabled then
		return
	end
	S.ready = true
	S.fighting = MelloUI.InCombat() and true or false
	Apply()
end

function M:OnEnable(db)
	self.db = db
	MelloUI:On("palette", Repaint, OWNER)
	MelloUI:On("editlayout", OnEditLayout, OWNER)
	-- (the events now: the login's PLAYER_ENTERING_WORLD drops the last
	-- login's fights; the rest waits for Ready)
	Events()
	MelloUI:AfterLogin(Ready)
end

function M:OnDisable()
	MelloUI:Off(OWNER)
	Apply()   -- (the game's meter and Show Party Pets back as they were)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "values" or key == "party" then
		Apply()
	elseif key == "raid" then
		if Meter.Raid and Meter.Raid.Apply then
			Meter.Raid.Apply()
		end
	elseif key == "summary" then
		Meter.Summary()
	elseif key == "historySize" then
		local fights = Meter.Fights()
		local cap = Num(value) or T.HISTORY
		while #fights > cap do
			tremove(fights, 1)
		end
		wipe(runCache)
		MelloUI:Fire("meter", "clear")
	elseif key == "bar" or key == "metric" or key == "pins" or key == "barWidth" or key == "barHeight" then
		if Meter.Bar and Meter.Bar.Apply then
			Meter.Bar.Apply()
		end
	elseif key == "history" then
		if Meter.HistoryApply then
			Meter.HistoryApply()
		end
	end
end

--------------------------------------------------------------------------------
-- MelloUI - the quests' source (2.1.39; the user, 2026-11-10: "we currently have systems that rely on our quest
-- databse, however i would like to step away from that, to instead push people to download questie for those systems
-- to work, like a compatibility feature"; docs/plans/questie-data.md)
--
-- One reader for every quest system (the Quest List, Route, Voice Over, Dungeon Info, the objectives' marks): the
-- quests are Questie's. (2.1.52, stage 2; the user, 2026-11-14: "i want to step away of having to Maintain Quest Data
-- and leave it to Questie", "Current and Future addons are the Engine, MelloUI Provides the Look") MelloUI ships no
-- quest data of its own any more. Three states, the user's:
--   "none"     Questie is not installed: no quests anywhere, and a plain "get Questie" line where they would show
--   "questie"  Questie with its switch on the Addons page (MelloUI's look) off: Questie's own icons and tracker, on
--              MelloUI's map too; MelloUI draws no quest marks of its own, and its Quest List and Route to a quest
--              still read Questie's data
--   "look"     Questie with the switch on: Questie's data in MelloUI's look
--   QS.State() -> one of those     QS.Questie() -> not "none"     QS.Look() -> "look"
-- "Questie" is the addon itself, loaded, with its database readable: QuestieDB alone, without Questie, is "none".
--
--   * QuestieDB is a public library (its src/api.lua: "Another addon can read entity fields ... Questie is the first
--     consumer, but nothing here assumes it"): the global LibQuestieDB, read only through its Quest / Npc / Object /
--     Item .Get and its quests' .GetAllIds. No code of Questie's runs for MelloUI, nothing of it is hooked, and none
--     of its data ships with MelloUI (it is the player's own copy, read where it is).
--   * Taken by what it offers, never by a version (the user, 2026-11-16: "every version, past and future should load
--     normally, dont ever bind addon compatibility addons to specific versions"): its contract number is not asked
--     (until 2.1.55 QS.Lib asked RequireContract(3), and a QuestieDB outside that range was "no Questie"). The reader
--     was written against 1.0.5's fields; every read is protected, so a field another release lacks or keeps another
--     way is that quest's or that part's loss (QS.counts.failed), never the whole library's.
--   * The rows are in the Quest List's own field order (QuestList.lua's QL.F_*), so its systems read them as before:
--     id, title, level, required level, side, class, quest zone, giver zone, giver, x, y, kind, event, chain, dungeon,
--     attunement (0: none is known), previous, continent, world x, world y, giver NPC, turn-in, its NPC, its zone, its
--     continent, its world x, its world y, origin (1). The event is the quest's seasonal sort when the data names it
--     (MelloUI_QuestListData.events), the dungeon its zone when the data names it (.dungeons), the chain the id of the
--     chain's first quest (the quests before it: preQuestSingle / preQuestGroup), named by that quest.
--   * A quest QuestieDB does not know shows nowhere; a giver it has no place for is listed without one.
--   * The rows are made after the login, a few milliseconds a frame (the 1000 ms budget, rule 7), the first time a
--     system asks (QS.WhenReady); they become MelloUI_QuestListData.quests (with .needs and .chains) and 'questsource'
--     is told on the bus.
--   * A place in QuestieDB is a zone's percentages; the client turns it into world yards (C_Map.GetWorldPosFromMapPos)
--     through the zone's map (MelloUI_AreaMaps, Media/PlaceData.lua, from the client's own UiMapAssignment).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local QS = {}
MelloUI.QuestSource = QS

QS.STEP_MS = 2      -- at most this many ms a frame while the rows are made
QS.STARTERS = 4      -- at most this many rows for one quest (one per giver: MelloUI lists a quest at each giver)
QS.CHAIN_DEPTH = 60  -- a chain followed back at most this many quests

-- the row's fields the build reads back (QuestList.lua's QL.F_*)
local F_ID, F_TITLE, F_CHAIN, F_PREV = 1, 2, 14, 17

local lib = nil        -- LibQuestieDB once asked: the library, or false (none this session)
local state = "idle"   -- "idle", "building", "ready"
local waiting = {}     -- functions to run once the rows are ready
QS.counts = nil        -- after the build: { questie = quests made, failed = quests that broke }

-- a database that can be asked: its quests listed and read (whatever its version or contract number: see the header)
local function Readable(L)
	local Q = L.Quest
	return type(Q) == "table" and type(Q.Get) == "function" and type(Q.GetAllIds) == "function"
end

-- QuestieDB, while Questie itself is loaded and its database can be asked; else nil. Whatever Questie's switch says:
-- the switch is the look (QS.Look). None found is kept as none only once the login is over (every addon has loaded by
-- then); found is kept
function QS.Lib()
	if lib == nil then
		local L = rawget(_G, "LibQuestieDB")
		local found
		if type(rawget(_G, "Questie")) == "table" and type(L) == "table" then
			local ok, fine = pcall(Readable, L)
			found = ok and fine and L or nil
		end
		if found then
			lib = found
		elseif MelloUI.initialized then
			lib = false
		end
		return found
	end
	return lib or nil
end

function QS.Questie()
	return QS.Lib() ~= nil
end

-- Questie's switch on the Addons page, MelloUI's look (Core/Integrations.lua): on until switched off
function QS.Look()
	if not QS.Lib() then
		return false
	end
	local I = rawget(MelloUI, "Integrations")
	return not (I and not I.Use("Questie"))
end

function QS.State()
	return not QS.Lib() and "none" or (QS.Look() and "look" or "questie")
end

function QS.Ready()
	return state == "ready"
end

-- "QuestieDB" when the rows are QuestieDB's, else "none" (no Questie, or not ready yet)
function QS.Name()
	return (state == "ready" and QS.counts and QS.counts.questie > 0) and "QuestieDB" or "none"
end

--------------------------------------------------------------------------------
-- Places: a zone's percentages to world yards
--------------------------------------------------------------------------------

local vec = nil

-- the world map id and yards of (x, y) percent on area `zone`; nil when the zone has no map here
function QS.World(zone, x, y)
	local maps = rawget(_G, "MelloUI_AreaMaps")
	local uiMap = type(maps) == "table" and maps[zone]
	if not uiMap or type(x) ~= "number" or type(y) ~= "number" or x < 0 or y < 0
		or not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
		return nil
	end
	vec = vec or CreateVector2D(0, 0)
	vec:SetXY(x / 100, y / 100)
	local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, uiMap, vec)
	if not ok or type(cont) ~= "number" or type(pos) ~= "table" or type(pos.x) ~= "number" then
		return nil
	end
	return cont, math.floor(pos.x * 10 + 0.5) / 10, math.floor(pos.y * 10 + 0.5) / 10
end

-- an NPC's or object's spawn for a quest: in `prefer` when it stands there and that zone has a map, else in the
-- lowest-numbered zone with a map; zone, x, y (nil when it has none)
local function Spawn(spawns, prefer)
	if type(spawns) ~= "table" then
		return nil
	end
	local maps = rawget(_G, "MelloUI_AreaMaps") or {}
	local function first(zone)
		local list = spawns[zone]
		local p = type(list) == "table" and list[1]
		if type(p) == "table" and type(p[1]) == "number" and p[1] >= 0 then
			return zone, p[1], p[2]
		end
	end
	if prefer and maps[prefer] then
		local z, x, y = first(prefer)
		if z then
			return z, x, y
		end
	end
	local best
	for zone in pairs(spawns) do
		if type(zone) == "number" and maps[zone] and first(zone) and (not best or zone < best) then
			best = zone
		end
	end
	if best then
		return first(best)
	end
end

--------------------------------------------------------------------------------
-- A quest of QuestieDB's as MelloUI's rows
--------------------------------------------------------------------------------

local function Side(L, races)
	if type(races) ~= "number" or races == 0 then
		return 3
	end
	local masks = L.Enum and L.Enum.factionRaceMasks
	if type(masks) ~= "table" then
		return 3
	end
	local a = masks.Alliance and bit.band(races, masks.Alliance) ~= 0
	local h = masks.Horde and bit.band(races, masks.Horde) ~= 0
	if a and not h then
		return 1
	elseif h and not a then
		return 2
	end
	return 3
end

local function FirstID(list)
	if type(list) == "table" then
		for _, id in ipairs(list) do
			if type(id) == "number" then
				return id
			end
		end
	end
end

-- who: { kind, id } -- 1 an NPC, 2 an object; its name, zone, x, y and world place
local function Place(L, kind, id, prefer)
	local entity = kind == 1 and L.Npc or L.Object
	local name = entity.Get(id, "name")
	local zone, x, y = Spawn(entity.Get(id, "spawns"), prefer)
	local cont, wx, wy
	if zone then
		cont, wx, wy = QS.World(zone, x, y)
	end
	return type(name) == "string" and name or "", zone, x, y, cont, wx, wy
end

-- the rows of quest `id` into `out` (one per giver, at most QS.STARTERS); `names`: the data's events and dungeons by
-- their sort and zone ({ events = {}, dungeons = {} }). The chain is set by the build, once every quest is in
local function Rows(L, id, names, out)
	local q = L.Quest
	local title = q.Get(id, "name")
	if type(title) ~= "string" or title == "" then
		return 0
	end
	local level, req = q.Get(id, "questLevel"), q.Get(id, "requiredLevel")
	req = type(req) == "number" and req > 0 and req or 1
	level = type(level) == "number" and level > 0 and level or req
	local zoneOrSort = q.Get(id, "zoneOrSort")
	local questZone = type(zoneOrSort) == "number" and zoneOrSort > 0 and zoneOrSort or nil
	-- (a seasonal quest: its sort is one the data names; a dungeon's: its zone is one the data names)
	local event = (type(zoneOrSort) == "number" and zoneOrSort < 0 and names.events[zoneOrSort]) and zoneOrSort or 0
	local dungeon = (questZone and names.dungeons[questZone]) and questZone or 0
	local side, class = Side(L, q.Get(id, "requiredRaces")), q.Get(id, "requiredClasses")
	class = type(class) == "number" and class or 0
	local prev = FirstID(q.Get(id, "preQuestSingle")) or FirstID(q.Get(id, "preQuestGroup")) or 0
	-- who takes it back: an NPC first, else an object
	local ender, enderNPC, enderZone, enderCont, enderWX, enderWY = "", 0, 0, -1, 0, 0
	local finished = q.Get(id, "finishedBy")
	local fNPC = type(finished) == "table" and FirstID(finished[1])
	local fObj = type(finished) == "table" and FirstID(finished[2])
	if fNPC or fObj then
		local name, zone, _, _, cont, wx, wy = Place(L, fNPC and 1 or 2, fNPC or fObj, questZone)
		ender, enderNPC, enderZone = name, fNPC or 0, zone or 0
		if cont then
			enderCont, enderWX, enderWY = cont, wx, wy
		end
	end
	-- the givers: NPCs, then objects (a quest only an item starts has nobody to pick it up from: no row)
	local started = q.Get(id, "startedBy")
	local givers = {}
	if type(started) == "table" then
		for kind = 1, 2 do
			for _, gid in ipairs(type(started[kind]) == "table" and started[kind] or {}) do
				if #givers < QS.STARTERS and type(gid) == "number" then
					givers[#givers + 1] = { kind, gid }
				end
			end
		end
	end
	local made = 0
	for _, g in ipairs(givers) do
		-- (a giver QuestieDB has no place for -- inside an instance, a zone of its own numbering -- is listed without one)
		local name, zone, x, y, cont, wx, wy = Place(L, g[1], g[2], questZone)
		out[#out + 1] = {
			id, title, level, req, side, class, questZone or zone or 0, zone or 0, name or "", x or 0, y or 0,
			g[1] == 1 and 1 or 2, event, 0, dungeon, 0, prev, cont or -1, wx or 0, wy or 0, g[1] == 1 and g[2] or 0,
			ender, enderNPC, enderZone, enderCont, enderWX, enderWY, 1,
		}
		made = made + 1
	end
	return made
end
QS.Rows = Rows   -- (the tests)

--------------------------------------------------------------------------------
-- What the game asks before it offers a quest (2.1.39; the plan's step 2): QuestieDB's rules in the Quest List's own
-- `needs` shape (QuestList.lua's QL.Closed / QL.Unmet read it), as Questie's QuestieDB.IsDoable reads them:
--   races      requiredRaces                       maxLevel   requiredMaxLevel
--   breadcrumbs  breadcrumbForQuestId (closed once its quest is taken or done)
--   crumbsTo   breadcrumbs (not while one of them is in the log)
--   exclusiveOf  [id] = { id, exclusiveTo... }    (closed once one of them is taken or done)
--   reps       { min faction, value, max faction, value }   skills  requiredSkill { skill line, value }
--   nextChain  nextQuestInChain (closed once it is taken or done)
--   after      the quests first, as choices of which one must be met in full (an id done, a negative id in the log):
--              preQuestSingle (any one done), else preQuestGroup (all done; one of an exclusive group done counts,
--              a negative one only itself), parentQuest (in the log), availableStartingWith (taken or done)
--   spells     requiredSpell (known; a negative one: not known)
--   untilDone  availableUntilCompleted (closed once it is done)    disabledBy  disabledByQuest (not while in the log)
-- (2.1.52: MelloUI's own `cond` -- the server's conditions, from classic-db -- and its exclusive groups went with its
-- quest data; QuestieDB has no conditions.)
--------------------------------------------------------------------------------

QS.CHOICES = 16   -- at most this many ways to meet a quest's `after`

local NEED_FIELDS = { "races", "maxLevel", "breadcrumbs", "crumbsTo", "reps", "nextChain", "skills", "after", "spells",
	"untilDone", "disabledBy", "exclusiveOf" }

local function Ids(list)
	local out = {}
	if type(list) == "table" then
		for _, id in ipairs(list) do
			if type(id) == "number" and id ~= 0 then
				out[#out + 1] = id
			end
		end
	end
	return out
end

local function Positive(v)
	return type(v) == "number" and v > 0 and v or nil
end

-- every way of meeting all of `reqs` (each a list of atoms, any one of which meets it): a list of atom lists
local function Choices(reqs)
	local choices = { {} }
	for _, alternatives in ipairs(reqs) do
		local nextList = {}
		for _, c in ipairs(choices) do
			for _, atom in ipairs(alternatives) do
				if #nextList < QS.CHOICES then
					local copy = { unpack(c) }
					copy[#copy + 1] = atom
					nextList[#nextList + 1] = copy
				end
			end
		end
		choices = nextList
	end
	return choices
end

local function Needs(L, id, needs)
	local q = L.Quest
	local races = q.Get(id, "requiredRaces")
	if type(races) == "number" and races ~= 0 then
		needs.races[id] = races
	end
	needs.maxLevel[id] = Positive(q.Get(id, "requiredMaxLevel"))
	needs.breadcrumbs[id] = Positive(q.Get(id, "breadcrumbForQuestId"))
	local crumbs = Ids(q.Get(id, "breadcrumbs"))
	if #crumbs > 0 then
		needs.crumbsTo[id] = crumbs
	end
	local exclusive = Ids(q.Get(id, "exclusiveTo"))
	if #exclusive > 0 then
		table.insert(exclusive, 1, id)
		needs.exclusiveOf[id] = exclusive
	end
	local minRep, maxRep = q.Get(id, "requiredMinRep"), q.Get(id, "requiredMaxRep")
	minRep = type(minRep) == "table" and type(minRep[1]) == "number" and minRep or nil
	maxRep = type(maxRep) == "table" and type(maxRep[1]) == "number" and maxRep or nil
	if minRep or maxRep then
		needs.reps[id] = { minRep and minRep[1] or 0, minRep and minRep[2] or 0, maxRep and maxRep[1] or 0,
			maxRep and maxRep[2] or 0 }
	end
	needs.nextChain[id] = Positive(q.Get(id, "nextQuestInChain"))
	local skill = q.Get(id, "requiredSkill")
	if type(skill) == "table" and type(skill[1]) == "number" then
		needs.skills[id] = { skill[1], type(skill[2]) == "number" and skill[2] or 0 }
	end
	local spell = q.Get(id, "requiredSpell")
	if type(spell) == "number" and spell ~= 0 then
		needs.spells[id] = spell
	end
	needs.untilDone[id] = Positive(q.Get(id, "availableUntilCompleted"))
	needs.disabledBy[id] = Positive(q.Get(id, "disabledByQuest"))
	-- the quests first
	local reqs = {}
	local single = Ids(q.Get(id, "preQuestSingle"))
	if #single > 0 then
		local any = {}
		for _, pre in ipairs(single) do
			any[#any + 1] = math.abs(pre)
		end
		reqs[#reqs + 1] = any
	else
		for _, pre in ipairs(Ids(q.Get(id, "preQuestGroup"))) do
			if pre < 0 then
				reqs[#reqs + 1] = { -pre }
			else
				local any = { pre }
				for _, other in ipairs(Ids(q.Get(pre, "exclusiveTo"))) do
					any[#any + 1] = math.abs(other)
				end
				reqs[#reqs + 1] = any
			end
		end
	end
	local parent = Positive(q.Get(id, "parentQuest"))
	if parent then
		reqs[#reqs + 1] = { -parent }
	end
	local from = Positive(q.Get(id, "availableStartingWith"))
	if from then
		reqs[#reqs + 1] = { from, -from }
	end
	if #reqs > 0 then
		needs.after[id] = Choices(reqs)
	end
end
QS.Needs = Needs   -- (the tests)

--------------------------------------------------------------------------------
-- The build: after the login, a few ms a frame
--------------------------------------------------------------------------------

local function Done(counts)
	state = "ready"
	QS.counts = counts
	local list = waiting
	waiting = {}
	for _, fn in ipairs(list) do
		local ok, err = pcall(fn)
		if not ok then
			geterrorhandler()(err)
		end
	end
	MelloUI:Fire("questsource", QS.Name(), counts)
end

-- The chains, once every quest's rows are in: a quest's chain is the first quest of the line it stands in (its
-- `previous` followed back while that quest is known), the chain's key that quest's id and its name that quest's
-- title; a line of one quest is no chain. Returns the names, { [first quest's id] = its title }
local function Chains(out)
	local first, title = {}, {}   -- [quest id] = its first row; its title
	for _, row in ipairs(out) do
		local id = row[F_ID]
		if not first[id] then
			first[id], title[id] = row, row[F_TITLE]
		end
	end
	local rootOf, members = {}, {}
	local function Root(id)
		local root = rootOf[id]
		if root then
			return root
		end
		local cur = id
		for _ = 1, QS.CHAIN_DEPTH do
			local prev = first[cur] and first[cur][F_PREV] or 0
			if prev == 0 or prev == cur or not first[prev] then
				break
			end
			cur = prev
		end
		rootOf[id] = cur
		return cur
	end
	for id in pairs(first) do
		local root = Root(id)
		members[root] = (members[root] or 0) + 1
	end
	local names = {}
	for _, row in ipairs(out) do
		local root = rootOf[row[F_ID]]
		if (members[root] or 0) > 1 then
			row[F_CHAIN] = root
			names[root] = title[root]
		end
	end
	return names
end

-- No Questie: no quests at all (the data's quest parts made empty, whatever an older data file still holds)
local function Empty(data)
	if type(data) == "table" then
		data.quests, data.chains = {}, {}
		data.needs = {}
	end
	Done({ questie = 0, failed = 0 })
end

local function Build()
	local L = QS.Lib()
	local data = rawget(_G, "MelloUI_QuestListData")
	if not L or type(data) ~= "table" then
		Empty(data)
		return
	end
	local okIds, ids = pcall(L.Quest.GetAllIds)
	if not okIds or type(ids) ~= "table" then
		Empty(data)
		return
	end
	local names = { events = type(data.events) == "table" and data.events or {},
		dungeons = type(data.dungeons) == "table" and data.dungeons or {} }
	local out, asked = {}, {}
	local counts = { questie = 0, failed = 0 }
	local needs = {}
	for _, field in ipairs(NEED_FIELDS) do
		needs[field] = {}
	end
	local i, n = 1, #ids
	local function Step()
		local t0 = debugprofilestop()
		while i <= n do
			local id = ids[i]
			i = i + 1
			if type(id) == "number" and not asked[id] then
				asked[id] = true
				local before = #out
				local ok = pcall(Rows, L, id, names, out)
				if not ok then
					-- (a quest that broke: none of its rows)
					for k = #out, before + 1, -1 do
						out[k] = nil
					end
					counts.failed = counts.failed + 1
				elseif #out > before then
					counts.questie = counts.questie + 1
					-- (its rules; one that breaks leaves the quest without them, never the build)
					pcall(Needs, L, id, needs)
				end
			end
			if debugprofilestop() - t0 >= QS.STEP_MS then
				break
			end
		end
		if i <= n then
			C_Timer.After(0, Step)
			return
		end
		data.chains = Chains(out)
		data.quests = out
		data.needs = needs
		Done(counts)
	end
	Step()
end

--------------------------------------------------------------------------------
-- Objectives (2.1.39): where a quest's objectives are done, from QuestieDB, in MelloUI.QuestObjectives' shape --
-- { kind, name, alt, world map, x1, y1, x2, y2, ... } (kind 1 creature, 2 object, 3 item, 4 area; places in world
-- yards) -- and their sources in QO.Sources' ({ from, name, lowest level, highest level, chance }; from 1 a creature,
-- 2 an object, 3 a vendor; QuestieDB has no drop chances: 0). The places thinned as Tools/build_quest_objectives.py
-- does: one a GRID-yard cell, at most CAP. Made when asked for (a quest in the log, a mark's tooltip), the last few kept.
--------------------------------------------------------------------------------

QS.GRID, QS.CAP = 40, 30
QS.SOURCES = 4       -- the sources named per objective
QS.DROPPERS = 12     -- the creatures and objects an item's places are gathered from, at most
QS.WORLD_DROP = 20   -- more kinds of creature than this drop it: a world drop (the build tool's rule), sold: its vendors
-- (2.1.60; two players, 2026-11-18: "getting lots of hitching ingame now", "fps dropping each time when i get a quest
-- item") the conversions kept: the whole quest log's and some more. Four were (2.1.39), and the log's readers -- the
-- counts' read, the minimap's and the maps' marks, Route -- ask for every quest of the log after each change of it:
-- with more than four quests every ask converted again, every spawn QuestieDB has for every quest, twice a change
-- (measured with 12 quests: 24 conversions and 5.6 MB of garbage in two frames for one item picked up). QuestieDB does
-- not change in a session, so a conversion stays good; past OBJ_KEPT the one asked for longest ago goes. A quest with
-- nothing placed is remembered so for OBJ_NONE seconds only (a place the client cannot name yet at the login).
--   objKept[questID] = { entries or false, sources, used (objUsed at its last ask), again (GetTime: a `false` asked anew) }
local objKept, OBJ_KEPT, OBJ_NONE = {}, 48, 30
local objCount, objUsed = 0, 0

-- every spawn of `id` (an Npc or Object of QuestieDB) into `into` as { world map, x, y }; how many
local function Spawns(entity, id, into)
	local spawns = entity.Get(id, "spawns")
	local n = 0
	if type(spawns) == "table" then
		for zone, list in pairs(spawns) do
			if type(zone) == "number" and type(list) == "table" then
				for _, p in ipairs(list) do
					if type(p) == "table" then
						local cont, wx, wy = QS.World(zone, p[1], p[2])
						if cont then
							into[#into + 1] = { cont, wx, wy }
							n = n + 1
						end
					end
				end
			end
		end
	end
	return n
end

-- the points thinned: one per cell, sorted, at most CAP evenly through them; { [world map] = { x1, y1, ... } }, maps
local function Thin(points)
	local cells, kept = {}, {}
	for _, p in ipairs(points) do
		local key = p[1] .. ":" .. math.floor(p[2] / QS.GRID) .. ":" .. math.floor(p[3] / QS.GRID)
		if not cells[key] then
			cells[key] = true
			kept[#kept + 1] = { p[1], math.floor(p[2] + 0.5), math.floor(p[3] + 0.5) }
		end
	end
	table.sort(kept, function(a, b)
		if a[1] ~= b[1] then
			return a[1] < b[1]
		elseif a[2] ~= b[2] then
			return a[2] < b[2]
		end
		return a[3] < b[3]
	end)
	if #kept > QS.CAP then
		local step, out = #kept / QS.CAP, {}
		for i = 0, QS.CAP - 1 do
			out[#out + 1] = kept[math.floor(i * step) + 1]
		end
		kept = out
	end
	local byMap, maps = {}, {}
	for _, c in ipairs(kept) do
		local list = byMap[c[1]]
		if not list then
			list = {}
			byMap[c[1]] = list
			maps[#maps + 1] = c[1]
		end
		list[#list + 1] = c[2]
		list[#list + 1] = c[3]
	end
	return byMap, maps
end

local function Levels(L, npc)
	local lo, hi = L.Npc.Get(npc, "minLevel"), L.Npc.Get(npc, "maxLevel")
	lo = type(lo) == "number" and lo or 0
	return lo, type(hi) == "number" and hi or lo
end

local function Convert(L, questID)
	local entries, sources = {}, {}
	local function Add(kind, name, alt, points, from)
		local byMap, maps = Thin(points)
		for _, map in ipairs(maps) do
			local e = { kind, name or "", alt or "", map }
			for _, v in ipairs(byMap[map]) do
				e[#e + 1] = v
			end
			entries[#entries + 1] = e
			sources[#sources + 1] = from
		end
	end
	local objectives = L.Quest.Get(questID, "objectives")
	objectives = type(objectives) == "table" and objectives or {}
	-- creatures, then objects: their own spawns
	for kind = 1, 2 do
		local entity = kind == 1 and L.Npc or L.Object
		for _, o in ipairs(type(objectives[kind]) == "table" and objectives[kind] or {}) do
			local id = type(o) == "table" and o[1]
			if type(id) == "number" then
				local points = {}
				Spawns(entity, id, points)
				local name = entity.Get(id, "name")
				local from = {}
				if kind == 1 then
					local lo, hi = Levels(L, id)
					from[1] = { 1, type(name) == "string" and name or "", lo, hi, 0 }
				end
				Add(kind, name, type(o[2]) == "string" and o[2] or "", points, from)
			end
		end
	end
	-- items: where the creatures and objects that drop them stand (the ones with places; those in the quest's own zone
	-- first), their names the sources; a world drop that is sold (more than WORLD_DROP kinds of creature drop it) or
	-- one nothing drops: where it is sold (QuestieDB has no drop chances to tell a rare drop by)
	local zoneOrSort = L.Quest.Get(questID, "zoneOrSort")
	local home = type(zoneOrSort) == "number" and zoneOrSort > 0 and zoneOrSort or nil
	local function Ordered(entity, list)
		local inZone, rest = {}, {}
		for _, id in ipairs(type(list) == "table" and list or {}) do
			if type(id) == "number" then
				local spawns = home and entity.Get(id, "spawns")
				local into = (type(spawns) == "table" and spawns[home]) and inZone or rest
				into[#into + 1] = id
			end
		end
		for _, id in ipairs(rest) do
			inZone[#inZone + 1] = id
		end
		return inZone
	end
	for _, o in ipairs(type(objectives[3]) == "table" and objectives[3] or {}) do
		local item = type(o) == "table" and o[1]
		if type(item) == "number" then
			local points, from = {}, {}
			local drops, objects = L.Item.Get(item, "npcDrops"), L.Item.Get(item, "objectDrops")
			local vendors = L.Item.Get(item, "vendors")
			local nDrops = type(drops) == "table" and #drops or 0
			local nObjects = type(objects) == "table" and #objects or 0
			local sold = type(vendors) == "table" and #vendors > 0
			local groups
			if sold and (nDrops > QS.WORLD_DROP or nDrops + nObjects == 0) then
				groups = { { 3, L.Npc, vendors } }
			else
				groups = { { 1, L.Npc, drops }, { 2, L.Object, objects } }
			end
			for _, g in ipairs(groups) do
				local from_, entity = g[1], g[2]
				for i, id in ipairs(Ordered(entity, g[3])) do
					if i > QS.DROPPERS then
						break
					end
					if Spawns(entity, id, points) > 0 and #from < QS.SOURCES then
						local name = entity.Get(id, "name")
						name = type(name) == "string" and name or ""
						local lo, hi = 0, 0
						if from_ == 1 then
							lo, hi = Levels(L, id)
						end
						-- (one name once: several objects of one name -- a Solid Chest each -- one source)
						local same
						for _, s in ipairs(from) do
							if s[1] == from_ and s[2] == name then
								same = s
								break
							end
						end
						if same then
							same[3] = (same[3] > 0 and lo > 0) and math.min(same[3], lo) or math.max(same[3], lo)
							same[4] = math.max(same[4], hi)
						else
							from[#from + 1] = { from_, name, lo, hi, 0 }
						end
					end
				end
			end
			Add(3, L.Item.Get(item, "name"), type(o[2]) == "string" and o[2] or "", points, from)
		end
	end
	-- a kill another creature stands in for (killCredit: { { creature ids }, the creature named, text })
	for _, o in ipairs(type(objectives[5]) == "table" and objectives[5] or {}) do
		if type(o) == "table" and type(o[1]) == "table" then
			local points = {}
			for _, id in ipairs(o[1]) do
				if type(id) == "number" then
					Spawns(L.Npc, id, points)
				end
			end
			local base = type(o[2]) == "number" and o[2] or o[1][1]
			local name = type(base) == "number" and L.Npc.Get(base, "name") or ""
			Add(1, name, type(o[3]) == "string" and o[3] or "", points, {})
		end
	end
	-- a place to reach (triggerEnd: { text, { [zone] = { { x, y }, ... } } })
	local trigger = L.Quest.Get(questID, "triggerEnd")
	if type(trigger) == "table" and type(trigger[2]) == "table" then
		local points = {}
		for zone, list in pairs(trigger[2]) do
			for _, p in ipairs(type(list) == "table" and list or {}) do
				local cont, wx, wy = QS.World(zone, type(p) == "table" and p[1], type(p) == "table" and p[2])
				if cont then
					points[#points + 1] = { cont, wx, wy }
				end
			end
		end
		Add(4, "", type(trigger[1]) == "string" and trigger[1] or "", points, {})
	end
	return entries, sources
end
QS.Convert = Convert   -- (the tests)

-- QuestieDB's objective entries and sources of a quest it knows (nil, nil when it does not, or has none placed)
local function ObjectivesOf(questID)
	local L = QS.Lib()
	if not L or type(questID) ~= "number" then
		return nil
	end
	local now = type(GetTime) == "function" and GetTime() or 0
	local kept = objKept[questID]
	objUsed = objUsed + 1
	if kept then
		kept[3] = objUsed
		if kept[1] then
			return kept[1], kept[2]
		elseif now < kept[4] then
			return nil
		end
	end
	-- (its own "is there such a quest", where it has one: a release without it is asked for the quest itself)
	local Exists = L.Quest.Exists
	local known = true
	if type(Exists) == "function" then
		local okE, exists = pcall(Exists, questID)
		known = (okE and exists) and true or false
	end
	local entries, sources
	if known then
		local ok, made, from = pcall(Convert, L, questID)
		if ok and type(made) == "table" and #made > 0 then
			entries, sources = made, from
		end
	end
	if not kept then
		-- room for it: the one asked for longest ago goes (a scan of the kept ones, only when a new quest comes in full)
		if objCount >= OBJ_KEPT then
			local oldest, least
			for id, k in pairs(objKept) do
				if not least or k[3] < least then
					oldest, least = id, k[3]
				end
			end
			if oldest then
				objKept[oldest] = nil
				objCount = objCount - 1
			end
		end
		kept = { false, nil, objUsed, 0 }
		objKept[questID] = kept
		objCount = objCount + 1
	end
	if entries then
		kept[1], kept[2], kept[4] = entries, sources, 0
		return entries, sources
	end
	kept[1], kept[2], kept[4] = false, nil, now + OBJ_NONE
	return nil
end
-- (the tests) how many conversions are kept, and the most
function QS.ObjectivesKept()
	return objCount, OBJ_KEPT
end

function QS.Objectives(questID)
	return (ObjectivesOf(questID))
end

function QS.Sources(questID)
	local _, sources = ObjectivesOf(questID)
	return sources
end

-- run `fn` once the rows are ready: at once when they are, else after the build (started now, after the login)
function QS.WhenReady(fn)
	if state == "ready" then
		fn()
		return
	end
	if state == "idle" and not QS.Lib() then
		-- (no Questie: no quests, ready at once; `fn` run as the caller's own code, its errors its own. Before the
		-- login is over this is not kept: Questie may still be loading, and the next ask looks again)
		if not MelloUI.initialized then
			fn()
			return
		end
		Build()
		fn()
		return
	end
	waiting[#waiting + 1] = fn
	if state == "idle" then
		state = "building"
		Build()
	end
end

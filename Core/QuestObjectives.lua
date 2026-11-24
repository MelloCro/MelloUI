--------------------------------------------------------------------------------
-- MelloUI - Quest objectives: where a quest's objectives are done (0.19.5)
--
-- One reader of the objective places for every user: Route (the route to the
-- nearest open objective) and the objective marks on the map and the minimap
-- (the user, 2026-10-06, of Questie and Carbonite: where each objective of the
-- quests in the log is done). Lifted out of Route.lua (its ObjectivesOf and
-- its objective lines): one system per job.
-- (2.1.52, stage 2 of docs/plans/questie-data.md; the user, 2026-11-14: "i want
-- to step away of having to Maintain Quest Data and leave it to Questie") The
-- places are Questie's: Core/QuestSource.lua's QS.Objectives, read from the
-- player's QuestieDB. MelloUI_Companion's own objective data, its needed items
-- (an entry's .gates) and made marks went with MelloUI's quest data. Without
-- Questie there are none: QO.Of answers nil, the learned places too.
--   QO.Of(questID)       the quest's entries { { kind, name, alt, map, x1, y1,
--                        x2, y2, ... }, ... } (kind 1 creature, 2 object, 3
--                        item, 4 area; map the world map; places in yards), the
--                        places learned in game (below) after Questie's; nil
--                        when there are none, or no Questie
--   QO.Has(questID)      whether it has any, without making the list
--   QO.Sources(questID)  per entry (Questie's, in Of's order), its sources:
--                        { { from, name, lowest level, highest level, chance },
--                        ... } (from 1 creature, 2 object, 3 vendor; chance 0:
--                        QuestieDB has none), or nil
--   QO.Lines(questID)    the game's objective lines: a list of { lower text,
--                        finished, index, left, type, text, have, need } (left:
--                        what is still lacking when it counts more than one) and
--                        all of them as one string ("text+" / "text-"); every
--                        value read secret-safe
--   QO.ItemLine(data, lines)  the quest's one item line, when the data has
--                        exactly one item objective (2026-10-04, Traditions of
--                        the Bluff: the incense made, its line done, Route went
--                        back to the vendors): false or nil otherwise
--   QO.Match(entry, lines, itemLine)  the game line an entry is: its name (or
--                        alt) in a line's text, an item never taking a line of
--                        another type, else the quest's one item line; nil
--   QO.Game(questID)     (2.1.74) a quest with no places: the game's own point
--                        for it and its open objective's kind (below)
--   QO.Traced(questID)   (2.1.74) the game's own areas of a quest with none of
--                        Questie's, traced into places of the data's shape
--                        (.game true); QO.Of hands them out (below)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Plain = MelloUI.Safe.Value

local QO = {}
MelloUI.QuestObjectives = QO

-- Questie's entries of a quest (Core/QuestSource.lua keeps the last few it made); nil without Questie
local function DataOf(questID)
	local QS = MelloUI.QuestSource
	return QS and QS.Objectives(questID) or nil
end

-- the learned entries of a quest (MelloUIQuestPlaces, below), in the data's
-- shape, or nil
local function LearnedOf(questID)
	local store = rawget(_G, "MelloUIQuestPlaces")
	local q = type(store) == "table" and type(store.quests) == "table" and store.quests[questID]
	if type(q) ~= "table" then
		return nil
	end
	return q
end

-- Questie's entries, then the learned ones (a list of its own, made again
-- when one is learned: QO.learnedLists)
QO.learnedLists = {}
function QO.Has(questID)
	return DataOf(questID) and true or false
end

function QO.Of(questID)
	local QS = MelloUI.QuestSource
	if not (QS and QS.Lib()) then
		-- (2.1.77) no Questie at all: the game's own areas for every quest in the log (QS.GameOnly); a Questie whose data
		-- cannot be read: none (its own icons show)
		if QS and QS.GameOnly() then
			return QO.Traced(questID)
		end
		return nil
	end
	local data, learned = DataOf(questID), LearnedOf(questID)
	if not learned then
		return data or QO.Traced(questID)   -- (2.1.74: none of Questie's: the game's own areas, traced -- below)
	end
	local list = QO.learnedLists[questID]
	if list and list.data == data then
		return list
	end
	list = { data = data }
	for _, entry in ipairs(data or {}) do
		list[#list + 1] = entry
	end
	for _, entry in pairs(learned) do
		if type(entry) == "table" and #entry > 4 then
			list[#list + 1] = entry
		end
	end
	QO.learnedLists[questID] = list
	return #list > 0 and list or data
end

-- Questie's sources, in its entries' order. Not kept: asked for when a mark's tooltip shows.
function QO.Sources(questID)
	local QS = MelloUI.QuestSource
	return QS and QS.Objectives(questID) and QS.Sources(questID) or nil
end

function QO.Lines(questID)
	local lines, joined = {}, {}
	if C_QuestLog and C_QuestLog.GetQuestObjectives then
		local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
		if ok and type(list) == "table" then
			for i, o in ipairs(list) do
				local text = Plain(o.text)
				if type(text) == "string" then
					local finished = Plain(o.finished) and true or false
					local need, have = Plain(o.numRequired), Plain(o.numFulfilled)
					need = type(need) == "number" and need or nil
					have = type(have) == "number" and have or nil
					local left = need and need > 1 and have and need - have or nil
					lines[#lines + 1] = { text:lower(), finished, i, left, Plain(o.type), text, have, need }
					joined[#joined + 1] = text .. (finished and "+" or "-")
				end
			end
		end
	end
	return lines, table.concat(joined, "\n")
end

function QO.ItemLine(data, lines)
	local items, itemLine = 0, nil
	for _, entry in ipairs(data) do
		if entry[1] == 3 then
			items = items + 1
		end
	end
	if items ~= 1 then
		return nil
	end
	for _, t in ipairs(lines) do
		if t[5] == "item" then
			itemLine = itemLine == nil and t or false
		end
	end
	return itemLine
end

local function MatchName(name, kind, lines)
	if not name or name == "" then
		return nil
	end
	name = name:lower()
	for _, t in ipairs(lines) do
		if t[1]:find(name, 1, true) and not (kind == 3 and t[5] and t[5] ~= "item") then
			return t
		end
	end
	return nil
end

function QO.Match(entry, lines, itemLine)
	local kind = entry[1]
	return MatchName(entry[2], kind, lines) or MatchName(entry[3], kind, lines) or (kind == 3 and itemLine) or nil
end

-- an objective's kind from the game's type (C_QuestLog.GetQuestObjectives): the data's kinds -- 1 creature, 2 object,
-- 3 item; anything else an area (4). The places learned in game (below) and the game's own places (QO.Game) alike
QO.KIND_OF = { monster = 1, object = 2, item = 3 }

--------------------------------------------------------------------------------
-- (2.1.74) The game's own place for a quest Questie has none for (docs/plans/game-quest-areas.md; the user,
-- 2026-11-23 in Riverglades: "why cant we in those cases just use the blizzards own map areas and quest locations and
-- just skin them in MelloUI Style?", then look A of BuildData/output/game_quest_areas_sketch): while MelloUI's look of
-- Questie's quests is on (QS.Look) and a quest in the log has no places (QO.Of: none of Questie's, none learned),
-- the game's own marker point for it -- C_QuestLog.GetQuestsOnMap on its zone (GetQuestUiMapID), else
-- C_QuestLog.GetNextWaypoint; the turn-in once it is complete -- and the kind of its first open objective. For
-- MelloUI's map (its area the game's own drawing: MapObjectives) and the minimap alike. Read when asked, nothing kept
--   QO.Game(questID, done) -> map, x, y, kind | nil   (done: its turn-in, only for a quest QuestieDB does not know at
--       all -- QS.Knows: Questie draws the turn-in of one it knows, places or none; the user, 2026-11-23 in Booty Bay:
--       a done quest's "?" twice)
-- (2.1.80; the user, 2026-11-24, without Questie: "some Quests are shown some are not", then: "when no questie is
-- enabled i want the default quest poi to show on the whole map just reskinned in melloui, if questie is enabled it
-- shows questie poi and fills the gap where questie has no quest data with default poi locations") The game lists a
-- quest's place on the map its objective is ON, and GetQuestUiMapID does not always name that map (none for some
-- quests, another for others): asked on that one map alone, such a quest got nothing. So the game's places are read
-- as the game's own map shows them, a zone at a time, from EVERY zone's list (the scan, below, with the tracer) and
-- kept for each quest's state:
--   QO.points[questID] = { sig = its state, map, x, y } | { sig, false }
--------------------------------------------------------------------------------
QO.points = {}
local AskScan   -- (every zone's list read over the next frames: with the tracer, below)

-- a quest's state for a kept answer of the game's: its objectives' done flags, and "!" once it is complete (the game's
-- point is its turn-in then)
local function StateOf(questID)
	local s = {}
	for i, t in ipairs((QO.Lines(questID))) do
		s[i] = t[2] and "+" or "-"
	end
	local api = rawget(_G, "C_QuestLog")
	if type(api) == "table" and api.IsComplete then
		local ok, complete = pcall(api.IsComplete, questID)
		if ok and Plain(complete) == true then
			s[#s + 1] = "!"
		end
	end
	return table.concat(s)
end

function QO.Game(questID, done)
	local Finite = MelloUI.Safe.Finite
	local id = Finite(questID)
	if not id or id <= 0 then
		return nil
	end
	local QS = MelloUI.QuestSource
	if (QS and not QS.Marks()) or QO.Of(id) ~= nil then   -- (Questie's places, the learned ones or the traced: areas)
		return nil
	end
	if done and QS and QS.Look() and QS.Knows and QS.Knows(id) then
		return nil   -- (its turn-in Questie's own "?")
	end
	local api = rawget(_G, "C_QuestLog")
	if type(api) ~= "table" then
		return nil
	end
	local map, x, y
	local mapOf = rawget(_G, "GetQuestUiMapID")
	if mapOf then
		local ok, m = pcall(mapOf, id)
		map = ok and Finite(m) or nil
	end
	if map and map > 0 and api.GetQuestsOnMap then
		local ok, list = pcall(api.GetQuestsOnMap, map)
		for _, info in ipairs(ok and type(list) == "table" and list or {}) do
			if type(info) == "table" and Finite(info.questID) == id then
				x, y = Finite(info.x), Finite(info.y)
				break
			end
		end
	end
	if not (x and y) and api.GetNextWaypoint then
		local ok, m, wx, wy = pcall(api.GetNextWaypoint, id)
		if ok and Finite(m) and Finite(wx) and Finite(wy) then
			map, x, y = Finite(m), Finite(wx), Finite(wy)
		end
	end
	if not (map and map > 0 and x and y) then
		-- (2.1.80) not on the map the game names for it: the place the scan of every zone's list found, kept for the
		-- quest's state; none kept yet: the scan asked for (the maps are told when it found something new)
		local p = QO.points[id]
		if not (p and p.sig == StateOf(id)) then
			AskScan(id)
			return nil
		end
		if not p[1] then
			return nil
		end
		map, x, y = p[1], p[2], p[3]
	end
	local kind = 4
	if api.GetQuestObjectives then
		local ok, list = pcall(api.GetQuestObjectives, id)
		for _, o in ipairs(ok and type(list) == "table" and list or {}) do
			if type(o) == "table" and not Plain(o.finished) then
				kind = QO.KIND_OF[Plain(o.type)] or 4
				break
			end
		end
	end
	return map, x, y, kind
end

-- the same in the world's coordinates, as the data's places (the continent, world yards: the minimap's marks carry
-- them to Route's yards), or nil
--   QO.GameWorld(questID, done) -> continent, wx, wy, kind | nil
function QO.GameWorld(questID, done)
	local map, x, y, kind = QO.Game(questID, done)
	local api, Vec = rawget(_G, "C_Map"), rawget(_G, "CreateVector2D")
	if not (map and type(api) == "table" and api.GetWorldPosFromMapPos and Vec) then
		return nil
	end
	local Finite = MelloUI.Safe.Finite
	local ok, cont, world = pcall(api.GetWorldPosFromMapPos, map, Vec(x, y))
	cont = ok and Finite(cont) or nil
	if not (cont and type(world) == "table" and world.GetXY) then
		return nil
	end
	local okXY, wx, wy = pcall(world.GetXY, world)
	wx, wy = okXY and Finite(wx) or nil, okXY and Finite(wy) or nil
	if not (wx and wy) then
		return nil
	end
	return cont, wx, wy, kind
end

--------------------------------------------------------------------------------
-- (2.1.74) The game's own quest areas, traced (docs/plans/game-quest-areas.md; the user's pick A: "like our areas").
-- The game draws a quest's areas itself (the QuestPOIFrame frame type, its map's QuestBlobPinTemplate) and takes no
-- picture of an addon's for their edge (the user, 2026-11-23, in game: the edge a missing picture's green), so
-- MelloUI draws them as its own areas: one hidden frame (alpha 0: nothing of it seen) draws the areas of a zone's
-- quests that have no places, and its hit test -- UpdateMouseOverTooltip, the quest under a point of the map (the
-- user's test in Riverglades, 2026-11-23: it answers the quest) -- is asked on a grid TRACE.STEP yards apart over the
-- zone, TRACE.PER_FRAME points a frame. Each quest's cells are grouped into areas (touching cells); an area's places
-- stand on a lattice two steps apart at least two steps inside its edge (MelloUI's areas reach about their RADIUS
-- round their places: QuestAreas), or along its middle where it is thinner; in the data's own shape -- { kind, name,
-- "", continent, x1, y1, ... } in world yards, .game true -- so every reader of QO.Of (MelloUI's map, the minimap,
-- Route) takes them as Questie's. Traced when first asked for, kept while the quest's objectives stay open or done as
-- they were (a count going up keeps them), traced again when one is done; the bus's "questareas:ready" once done, for
-- the maps to lay again. Nothing at login; a frame's work only while tracing
--   QO.Traced(questID) -> entries | nil   (nil: none, or not traced yet -- asked for then)
--------------------------------------------------------------------------------
local TRACE = { STEP = 40, PER_FRAME = 600, MAX_CELLS = 140 * 140, SIZE = 256,
	RETRY = 2,      -- (2.1.80) an empty answer asked again this often a state, when the client says its places changed
	AGAIN = 0.3 }   -- seconds after that word (its events come in bursts)
QO.TRACE = TRACE
QO.traced = {}   -- [questID] = { sig = its objectives' done flags, entries = list | false }
-- (2.1.80) tries[questID] = { sig, n }: its empty trace asked again; timer: the client's places changed
-- (QUEST_POI_UPDATE), looked at soon
-- emptyOn[questID] = { sig, [map] = true }: the maps its trace came back empty on, this state
QO.trace = { queue = {}, queued = {}, job = nil, frame = nil, driver = nil, tries = {}, timer = false, emptyOn = {} }
local EMPTY = {}

-- (2.1.80) The scan: every zone's own list of the quests placed on it (C_QuestLog.GetQuestsOnMap), SCAN.PER_FRAME
-- zones a frame -- the maps the game names for the log's quests and the zone the player is in first, then every zone
-- under the world map. A quest's place is kept (QO.points) with its state -- the one on its own map, else the one
-- most inside its zone (a zone's list holds its neighbours' quests near its edge too); the bus's "questareas:ready"
-- when a place came, went or moved, so the maps lay again. Asked for when a quest's place is not known for its state
-- (AskScan) and when the client says its places changed (QUEST_POI_UPDATE); nothing at login, a frame's work only
-- while it reads
local SCAN = { PER_FRAME = 6, WORLD = 947 }
QO.SCAN = SCAN
QO.scan = { zones = nil, job = nil, dirty = false, asked = {}, again = false }
local Kick

-- every zone under the world map (the client's list, read once), or none where the client has no such list
local function Zones()
	local S = QO.scan
	if S.zones then
		return S.zones
	end
	local zones = {}
	local maps, kinds, Finite = rawget(_G, "C_Map"), rawget(_G, "Enum"), MelloUI.Safe.Finite
	local zone = type(kinds) == "table" and type(kinds.UIMapType) == "table" and kinds.UIMapType.Zone or 3
	if type(maps) == "table" and maps.GetMapChildrenInfo then
		local root = SCAN.WORLD
		if maps.GetFallbackWorldMapID then
			local okR, id = pcall(maps.GetFallbackWorldMapID)
			root = okR and Finite(id) or root
		end
		local ok, list = pcall(maps.GetMapChildrenInfo, root, zone, true)
		for _, info in ipairs(ok and type(list) == "table" and list or EMPTY) do
			local id = type(info) == "table" and Finite(info.mapID) or nil
			if id and id > 0 then
				zones[#zones + 1] = id
			end
		end
	end
	S.zones = zones
	return zones
end

-- the quests of the log, each once
local function LogIDs()
	local out = {}
	local api, Finite = rawget(_G, "C_QuestLog"), MelloUI.Safe.Finite
	if type(api) == "table" and api.GetNumQuestLogEntries and api.GetInfo then
		local okN, n = pcall(api.GetNumQuestLogEntries)
		for i = 1, okN and Finite(n) or 0 do
			local ok, info = pcall(api.GetInfo, i)
			local id = ok and type(info) == "table" and not Plain(info.isHeader) and Finite(info.questID) or nil
			if id and id > 0 then
				out[#out + 1] = id
			end
		end
	end
	return out
end

-- a scan begun: its maps in order -- the log's quests' own maps and the player's zone first (a place found there
-- wins), then every zone
local function ScanJob()
	local list, seen, Finite = {}, {}, MelloUI.Safe.Finite
	local function Add(map)
		map = Finite(map)
		if map and map > 0 and not seen[map] then
			seen[map] = true
			list[#list + 1] = map
		end
	end
	local quests = LogIDs()
	local own = {}   -- [questID] = the map the game names for it
	local mapOf = rawget(_G, "GetQuestUiMapID")
	for _, q in ipairs(mapOf and quests or EMPTY) do
		local ok, map = pcall(mapOf, q)
		if ok then
			own[q] = Finite(map)
			Add(map)
		end
	end
	local maps = rawget(_G, "C_Map")
	if type(maps) == "table" and maps.GetBestMapForUnit then
		local ok, map = pcall(maps.GetBestMapForUnit, "player")
		if ok then
			Add(map)
		end
	end
	for _, map in ipairs(Zones()) do
		Add(map)
	end
	return { list = list, i = 0, found = {}, quests = quests, own = own }
end

-- its next zones read; true once every one is in and the places are kept
local function ScanStep(job)
	local S, api, Finite = QO.scan, rawget(_G, "C_QuestLog"), MelloUI.Safe.Finite
	local last = math.min(#job.list, job.i + SCAN.PER_FRAME)
	for k = job.i + 1, last do
		local map = job.list[k]
		local ok, list = false, nil
		if type(api) == "table" and api.GetQuestsOnMap then
			ok, list = pcall(api.GetQuestsOnMap, map)
		end
		for _, info in ipairs(ok and type(list) == "table" and list or EMPTY) do
			local id = type(info) == "table" and Finite(info.questID) or nil
			local x, y = id and Finite(info.x) or nil, id and Finite(info.y) or nil
			if x and y and not Plain(info.isMapIndicatorQuest) then
				-- (a zone's list holds its neighbours' quests near its edge too: a quest's place on its own map
				-- before any other's, else the one most inside its zone)
				local score = job.own[id] == map and 2 or math.min(x, 1 - x, y, 1 - y)
				local best = job.found[id]
				if not best or score > best[4] then
					job.found[id] = { map, x, y, score }
				end
			end
		end
	end
	job.i = last
	if last < #job.list then
		return false
	end
	-- every zone in: each quest of the log (and each one asked for meanwhile) kept with its state
	local changed = false
	local function Keep(q)
		local at, was = job.found[q], QO.points[q]
		local sig = StateOf(q)
		if at then
			if not (was and was[1] == at[1] and was[2] == at[2] and was[3] == at[3]) then
				changed = true
				-- (a place where none was, or on another zone: an empty trace of before is asked again there)
				local t = QO.traced[q]
				if t and t.entries == false and t.map ~= at[1] then
					QO.traced[q] = nil
				end
			end
			QO.points[q] = { sig = sig, at[1], at[2], at[3] }
		else
			if was and was[1] then
				changed = true
			end
			QO.points[q] = { sig = sig, false }
		end
	end
	local kept = {}
	for _, q in ipairs(job.quests) do
		kept[q] = true
		Keep(q)
	end
	for q in pairs(S.asked) do
		if not kept[q] then
			kept[q] = true
			Keep(q)
		end
		S.asked[q] = nil
	end
	for q in pairs(QO.points) do
		if not kept[q] then
			QO.points[q] = nil   -- (no longer in the log)
		end
	end
	return true, changed
end

AskScan = function(questID)
	local S = QO.scan
	if questID then
		S.asked[questID] = true
	end
	S.dirty = true
	Kick()
end

-- its objectives' done flags ("-+-"): what changes the game's areas (a count going up does not)
local function DoneSig(questID)
	local lines = QO.Lines(questID)
	local s = {}
	for i, t in ipairs(lines) do
		s[i] = t[2] and "+" or "-"
	end
	return table.concat(s)
end

-- the kind and the name (its line without the count: QO.Match finds it as it counts up) of its first open objective
local function FirstOpen(questID)
	for _, t in ipairs((QO.Lines(questID))) do
		if not t[2] then
			local name = t[6]:gsub("%s*%d+%s*/%s*%d+%s*", ""):gsub("^[%s:]+", ""):gsub("[%s:]+$", "")
			return QO.KIND_OF[t[5]] or 4, name ~= "" and name or t[6]
		end
	end
	return 4, ""
end

-- a map's 0..1 to world yards: its corner and its two edges (three of the client's answers), or nil
local function MapWorld(map)
	local api, Vec, Finite = rawget(_G, "C_Map"), rawget(_G, "CreateVector2D"), MelloUI.Safe.Finite
	if not (type(api) == "table" and api.GetWorldPosFromMapPos and Vec) then
		return nil
	end
	local function At(u, v)
		local ok, cont, w = pcall(api.GetWorldPosFromMapPos, map, Vec(u, v))
		if not (ok and Finite(cont) and type(w) == "table" and w.GetXY) then
			return nil
		end
		local okXY, x, y = pcall(w.GetXY, w)
		x, y = okXY and Finite(x) or nil, okXY and Finite(y) or nil
		return x and y and Finite(cont) or nil, x, y
	end
	local c, x0, y0 = At(0, 0)
	local c1, x1, y1 = At(1, 0)
	local c2, x2, y2 = At(0, 1)
	if not (c and c == c1 and c == c2) then
		return nil
	end
	return { cont = c, x0 = x0, y0 = y0, ux = x1 - x0, uy = y1 - y0, vx = x2 - x0, vy = y2 - y0 }
end

-- one quest's cells into its areas' entries (the grid nx by ny, cells by index; w its map's world transform)
local function Entries(questID, cells, nx, ny, w)
	local kind, name = FirstOpen(questID)
	local list, seen = {}, {}
	for start in pairs(cells) do
		if not seen[start] then
			-- the area: the touching cells (a flood fill), then each one's depth from its edge (a fill inward)
			local area, stack = {}, { start }
			seen[start] = true
			while #stack > 0 do
				local k = table.remove(stack)
				area[#area + 1] = k
				local cx, cy = (k - 1) % nx, math.floor((k - 1) / nx)
				for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
					local x, y = cx + d[1], cy + d[2]
					local n = y * nx + x + 1
					if x >= 0 and x < nx and y >= 0 and y < ny and cells[n] and not seen[n] then
						seen[n] = true
						stack[#stack + 1] = n
					end
				end
			end
			local depth, front, deepest = {}, {}, 0
			for _, k in ipairs(area) do
				local cx, cy = (k - 1) % nx, math.floor((k - 1) / nx)
				local edge = cx == 0 or cx == nx - 1 or cy == 0 or cy == ny - 1 or not cells[k - 1] or not cells[k + 1]
					or not cells[k - nx] or not cells[k + nx]
				if edge then
					depth[k] = 1
					front[#front + 1] = k
				end
			end
			while #front > 0 do
				local nextFront = {}
				for _, k in ipairs(front) do
					local d = depth[k]
					deepest = math.max(deepest, d)
					for _, n in ipairs({ k - 1, k + 1, k - nx, k + nx }) do
						if cells[n] and not depth[n] then
							depth[n] = d + 1
							nextFront[#nextFront + 1] = n
						end
					end
				end
				front = nextFront
			end
			-- its places: on the two-step lattice at least two steps in; thinner, along its deepest cells
			local keep = {}
			for _, k in ipairs(area) do
				local cx, cy = (k - 1) % nx, math.floor((k - 1) / nx)
				if depth[k] >= 2 and cx % 2 == 0 and cy % 2 == 0 then
					keep[#keep + 1] = k
				end
			end
			if #keep == 0 then
				for i, k in ipairs(area) do
					if depth[k] == deepest and i % 2 == 1 then
						keep[#keep + 1] = k
					end
				end
			end
			local entry = { kind, name, "", w.cont, game = true }
			for _, k in ipairs(keep) do
				local u, v = ((k - 1) % nx + 0.5) / nx, (math.floor((k - 1) / nx) + 0.5) / ny
				entry[#entry + 1] = w.x0 + w.ux * u + w.vx * v
				entry[#entry + 1] = w.y0 + w.uy * u + w.vy * v
			end
			if #entry > 4 then
				list[#list + 1] = entry
			end
		end
	end
	return #list > 0 and list or false
end

local Again

local function Driver()
	local T, S = QO.trace, QO.scan
	-- (2.1.80) the scan first: a trace's zone may be the one it finds
	if S.job or S.dirty then
		if not S.job then
			S.dirty = false
			S.job = ScanJob()
		end
		local done, changed = ScanStep(S.job)
		if not done then
			return
		end
		S.job = nil
		if S.again then   -- (the client's places changed: the empty traces asked again, a bounded number of times)
			S.again = false
			Again()
			changed = true
		end
		if changed then
			MelloUI:Fire("questareas:ready")
		end
		return
	end
	local job = T.job
	if not job then
		-- the next zone waiting: its quests' areas drawn on the hidden frame, its grid asked from the next frame
		local map, quests = next(T.queue)
		if not map then
			T.driver:SetScript("OnUpdate", nil)
			return
		end
		T.queue[map] = nil
		local w = MapWorld(map)
		local f = T.frame
		if not f then
			local ok, made = pcall(CreateFrame, "QuestPOIFrame", nil, UIParent)
			f = ok and type(made) == "table" and made or false
			if f then
				f:SetSize(TRACE.SIZE, TRACE.SIZE)
				f:SetPoint("CENTER")
				f:SetAlpha(0)
				f:EnableMouse(false)
				pcall(f.SetFillAlpha, f, 0)
				pcall(f.SetBorderAlpha, f, 0)
			end
			T.frame = f
		end
		local width = w and math.sqrt(w.ux * w.ux + w.uy * w.uy) or 0
		local height = w and math.sqrt(w.vx * w.vx + w.vy * w.vy) or 0
		local nx, ny = math.ceil(width / TRACE.STEP), math.ceil(height / TRACE.STEP)
		local k = (nx * ny > TRACE.MAX_CELLS) and math.sqrt(TRACE.MAX_CELLS / (nx * ny)) or 1
		nx, ny = math.max(1, math.floor(nx * k)), math.max(1, math.floor(ny * k))
		local want = {}
		for _, q in ipairs(quests) do
			want[q] = {}
			T.queued[q] = nil
		end
		if not (f and w and nx * ny > 1 and pcall(f.SetMapID, f, map)) then
			for _, q in ipairs(quests) do
				QO.traced[q] = { sig = DoneSig(q), entries = false, map = map }
			end
			MelloUI:Fire("questareas:ready")
			return
		end
		pcall(f.DrawNone, f)
		for _, q in ipairs(quests) do
			pcall(f.DrawBlob, f, q, true)
		end
		T.job = { map = map, w = w, nx = nx, ny = ny, i = 0, want = want, quests = quests, wait = true }
		return
	end
	if job.wait then
		job.wait = nil   -- (the frame drawn: asked from this frame on)
		return
	end
	local f, Finite = T.frame, MelloUI.Safe.Finite
	local n = job.nx * job.ny
	local last = math.min(n, job.i + TRACE.PER_FRAME)
	for k = job.i + 1, last do
		local u, v = ((k - 1) % job.nx + 0.5) / job.nx, (math.floor((k - 1) / job.nx) + 0.5) / job.ny
		local ok, q = pcall(f.UpdateMouseOverTooltip, f, u, v)
		q = ok and Finite(q) or nil
		local cells = q and job.want[q]
		if cells then
			cells[k] = true
		end
	end
	job.i = last
	if last < n then
		return
	end
	-- done: each quest's areas kept (or none), the maps told
	pcall(f.DrawNone, f)
	for _, q in ipairs(job.quests) do
		local entries = Entries(q, job.want[q], job.nx, job.ny, job.w)
		local sig = DoneSig(q)
		QO.traced[q] = { sig = sig, entries = entries, map = job.map }
		if entries then
			T.tries[q], T.emptyOn[q] = nil, nil
		else
			-- (no area on this map: noted, and asked once more -- on the zone the scan found its place on, where
			-- that is another; the scan asked for where it has not read the quest yet)
			local e = T.emptyOn[q]
			if not (e and e.sig == sig) then
				e = { sig = sig }
				T.emptyOn[q] = e
			end
			e[job.map] = true
			local p = QO.points[q]
			if not (p and p.sig == StateOf(q)) then
				AskScan(q)
			elseif p[1] and not e[p[1]] then
				QO.traced[q] = nil
			end
		end
	end
	T.job = nil
	MelloUI:Fire("questareas:ready")
end

-- (2.1.80) the client's quest places changed (QUEST_POI_UPDATE: they arrive a moment after a login or a quest
-- taken; the game's own map draws again on it): every zone's list is read again, and every EMPTY trace is forgotten,
-- so the maps' next lay asks for it again -- at most TRACE.RETRY times a quest's state, so one that stays empty (a
-- quest with a point and no area) is not traced for ever. TRACE.AGAIN seconds after the word (its events come in
-- bursts)
local function TryAgain(T, q)
	local sig = StateOf(q)
	local tried = T.tries[q]
	local n = (tried and tried.sig == sig) and tried.n or 0
	if n >= TRACE.RETRY then
		return false
	end
	T.tries[q] = { sig = sig, n = n + 1 }
	return true
end

Again = function()
	local T = QO.trace
	for q, t in pairs(QO.traced) do
		if t.entries == false and TryAgain(T, q) then
			QO.traced[q] = nil
		end
	end
end

local function Soon()
	local T, S = QO.trace, QO.scan
	T.timer = false
	local QS = MelloUI.QuestSource
	if QS and not QS.Marks() then
		return
	end
	S.again = true
	AskScan()
end

local function OnPlaces()
	local T = QO.trace
	if not T.timer then
		T.timer = true
		C_Timer.After(TRACE.AGAIN, Soon)
	end
end

-- a frame of the driver's work. An error of it is caught: told once (the game's error handler), kept for /qlmap game,
-- and the work put down -- an error a frame for ever otherwise
function QO.trace.Beat(self)
	local ok, err = pcall(Driver)
	if not ok then
		local T = QO.trace
		T.failed = tostring(err)
		T.job, QO.scan.job = nil, nil
		self:SetScript("OnUpdate", nil)
		local handler = rawget(_G, "geterrorhandler")
		handler = handler and handler()
		if handler then
			pcall(handler, err)
		end
	end
end

-- the driver frame, made at the first ask: it hears the client's word, and works a frame at a time while asked
Kick = function()
	local T = QO.trace
	if not T.driver then
		T.driver = CreateFrame("Frame")
		pcall(T.driver.RegisterEvent, T.driver, "QUEST_POI_UPDATE")
		T.driver:SetScript("OnEvent", OnPlaces)
	end
	T.driver:SetScript("OnUpdate", QO.trace.Beat)
end

-- a quest asked for: queued on its zone's list once (its zone's quests traced together). Its zone is the map the game
-- NAMES for it (GetQuestUiMapID: the map the game draws its area on -- the user, 2026-11-24, after a build that
-- traced on the zone the scan found first: "yes but what about the areas?"); where the game names none, or that map
-- traced empty for this state, the zone the scan found its place on; neither known yet: the scan asked for, nothing
-- kept meanwhile (the maps lay again when it found the place)
local function Request(questID)
	local T = QO.trace
	if T.queued[questID] then
		return
	end
	local Finite = MelloUI.Safe.Finite
	local sig = DoneSig(questID)
	local e = T.emptyOn[questID]
	if e and e.sig ~= sig then
		e = nil
		T.emptyOn[questID] = nil
	end
	local map
	local mapOf = rawget(_G, "GetQuestUiMapID")
	if mapOf then
		local ok, m = pcall(mapOf, questID)
		map = ok and Finite(m) or nil
	end
	if not (map and map > 0) or (e and e[map]) then
		local p = QO.points[questID]
		if not (p and p.sig == StateOf(questID)) then
			AskScan(questID)
			return
		end
		map = p[1] or nil
		if not map or (e and e[map]) then
			QO.traced[questID] = { sig = sig, entries = false, map = map or nil }   -- (no area the game draws)
			return
		end
	end
	T.queued[questID] = true
	local list = T.queue[map]
	if not list then
		list = {}
		T.queue[map] = list
	end
	list[#list + 1] = questID
	Kick()
end

-- /qlmap game (2.1.80): the game's place for every quest of the log, asked for now -- every zone's list read and each
-- open quest's area traced -- and reported when the reader is through: the map the game names for the quest, whether
-- that map's own list holds it, the zone the scan found its place on, and its traced areas. (Its first form listed
-- only what had been asked before: typed right after a /reload it said "not read yet" for every quest)
function QO.Dump()
	local api, Finite = rawget(_G, "C_QuestLog"), MelloUI.Safe.Finite
	local QS = MelloUI.QuestSource
	local marks = (QS and QS.Marks()) and true or false
	local ids = LogIDs()
	MelloUI:Print("The game's quest places: MelloUI's marks %s, Questie %s, %d quests in your log, %d zones. Reading ...",
		marks and "on" or "off", (QS and QS.GameOnly()) and "not there" or "there", #ids, #Zones())
	if type(api) ~= "table" or not marks then
		return
	end
	local T, S = QO.trace, QO.scan
	T.failed = nil
	AskScan()
	local beats = 0
	local function Report()
		beats = beats + 1
		for _, id in ipairs(ids) do
			QO.Traced(id)   -- (each open quest's area asked for; again where the scan named another zone)
		end
		local busy = S.job or S.dirty or T.job or next(T.queue)
		if busy and not T.failed and beats < 80 then
			C_Timer.After(0.25, Report)
			return
		end
		if T.failed then
			MelloUI:Print("  The reader stopped on an error: %s", T.failed)
		elseif busy then
			MelloUI:Print("  The reader is not through after %d seconds (zones %s, areas %s).", beats / 4,
				(S.job or S.dirty) and "still read" or "read", (T.job or next(T.queue)) and "still traced" or "traced")
		end
		local mapOf = rawget(_G, "GetQuestUiMapID")
		local placed, bare = 0, 0
		for _, id in ipairs(ids) do
			local okM, map = false, nil
			if mapOf then
				okM, map = pcall(mapOf, id)
			end
			map = okM and Finite(map) or 0
			local listed = false
			if map > 0 and api.GetQuestsOnMap then
				local okL, list = pcall(api.GetQuestsOnMap, map)
				for _, q in ipairs(okL and type(list) == "table" and list or EMPTY) do
					if type(q) == "table" and Finite(q.questID) == id then
						listed = true
						break
					end
				end
			end
			local okT, title = false, nil
			if api.GetTitleForQuestID then
				okT, title = pcall(api.GetTitleForQuestID, id)
			end
			local okC, complete = false, nil
			if api.IsComplete then
				okC, complete = pcall(api.IsComplete, id)
			end
			local t, p = QO.traced[id], QO.points[id]
			local zone = p and p[1] or nil
			local areas = t and t.entries and #t.entries or 0
			if listed or zone or areas > 0 then
				placed = placed + 1
			else
				bare = bare + 1
			end
			MelloUI:Print("  %s (%d)%s: the game's map %d, on that map's list: %s, found on zone: %s, areas: %s",
				tostring(okT and Plain(title) or "?"), id, (okC and Plain(complete) == true) and ", complete" or "", map,
				listed and "yes" or "no", zone and tostring(zone) or (p and "none" or "not read"),
				t and (areas > 0 and (areas .. " on map " .. tostring(t.map)) or "none") or "not traced")
		end
		MelloUI:Print("  %d quests with a place from the game, %d without any.", placed, bare)
	end
	C_Timer.After(0.25, Report)
end

function QO.Traced(questID)
	local QS = MelloUI.QuestSource
	if not (QS and QS.Marks()) then   -- (2.1.77: Questie in MelloUI's look, or no Questie at all)
		return nil
	end
	local api, Finite = rawget(_G, "C_QuestLog"), MelloUI.Safe.Finite
	local ok, index = false, nil
	if type(api) == "table" and api.GetLogIndexForQuestID then
		ok, index = pcall(api.GetLogIndexForQuestID, questID)
	end
	if not (ok and Finite(index)) then
		return nil   -- (not in the log: the game draws no area of it)
	end
	if api.IsComplete then
		local okC, complete = pcall(api.IsComplete, questID)
		if okC and Plain(complete) == true then
			return nil   -- (done: no area to trace, its turn-in a mark -- QO.Game)
		end
	end
	local t = QO.traced[questID]
	if not (t and t.sig == DoneSig(questID)) then
		Request(questID)   -- (meanwhile the areas traced before, if any)
	end
	return t and t.entries or nil
end

--------------------------------------------------------------------------------
-- Places learned in game (0.19.5; the user, 2026-10-06, of Questie: Forever's
-- own quests, which no database places). When the count of an objective the
-- data has no place for goes up, where the player stands is kept for that
-- quest and objective, account-wide, in MelloUIQuestPlaces (SavedVariables):
-- { v = 1, quests = { [questID] = { [objective index] = { kind, name, "",
-- map, x1, y1, x2, y2, ... } } } } -- the data's own entry shape (kind 1
-- creature, 2 object, 3 item, 4 area, from the objective's type; the name its
-- line's text without the count, so QO.Match finds it; places in the world's
-- yards, as the data's), one place LEARN.APART yards from the others, at most
-- LEARN.MAX an objective. The counts are read from the quest log after a
-- QUEST_LOG_UPDATE burst (LEARN.WAIT seconds after its last), only with
-- Questie (so what it places is known); the first read after a login
-- or a reload only notes the counts. Nothing at login; nothing a frame.
--------------------------------------------------------------------------------
local LEARN = { APART = 30, MAX = 24, WAIT = 0.4, KIND = QO.KIND_OF }
QO.learn = { counts = {}, seeded = false, queued = false }

local function Store()
	local s = rawget(_G, "MelloUIQuestPlaces")
	if type(s) ~= "table" then
		s = { v = 1 }
		_G.MelloUIQuestPlaces = s
	end
	if type(s.quests) ~= "table" then
		s.quests = {}
	end
	return s
end

-- where the player stands: the world map's id and the place in yards, or nil
-- (an instance, a place the client will not say)
function QO.PlayerWorld()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then
		return nil
	end
	local okM, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	mapID = okM and Plain(mapID) or nil
	if type(mapID) ~= "number" then
		return nil
	end
	local okP, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	if not okP or not pos then
		return nil
	end
	local okW, cont, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos)
	cont = okW and Plain(cont) or nil
	if type(cont) ~= "number" or not world or not world.GetXY then
		return nil
	end
	local okXY, x, y = pcall(world.GetXY, world)
	x, y = okXY and Plain(x) or nil, okXY and Plain(y) or nil
	if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then
		return nil
	end
	return cont, x, y
end

-- one place kept for a quest's objective (index i, its game line t)
function QO.Learn(questID, i, t, cont, x, y)
	local q = Store().quests[questID]
	if not q then
		q = {}
		Store().quests[questID] = q
	end
	local entry = q[i]
	if entry and entry[4] ~= cont then
		return false   -- (one world map an objective, as the data's entries: the places kept stay)
	end
	if not entry then
		local name = (t[6] or ""):gsub("%s*:%s*%d+%s*/%s*%d+%s*$", ""):gsub("^%d+%s*/%s*%d+%s+", "")
		entry = { LEARN.KIND[t[5]] or 4, name, "", cont }
		q[i] = entry
	end
	local n = (#entry - 4) / 2
	if n >= LEARN.MAX then
		return false
	end
	for k = 5, #entry - 1, 2 do
		local dx, dy = entry[k] - x, entry[k + 1] - y
		if dx * dx + dy * dy < LEARN.APART * LEARN.APART then
			return false
		end
	end
	entry[#entry + 1] = math.floor(x * 10 + 0.5) / 10
	entry[#entry + 1] = math.floor(y * 10 + 0.5) / 10
	QO.learnedLists[questID] = nil   -- (QO.Of's list made again)
	return true
end

-- the quest log read: every count noted; one that went up, of an objective
-- the data does not place, learned where the player stands
function QO.ReadCounts()
	local L = QO.learn
	L.queued = false
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
		return
	end
	local QS = MelloUI.QuestSource
	-- (only with Questie: what it places is known, and without it no quest shows anywhere)
	local learnNow = L.seeded and QS ~= nil and QS.Lib() ~= nil
	L.seeded = true
	local okN, n = pcall(C_QuestLog.GetNumQuestLogEntries)
	n = okN and Plain(n) or 0
	local cont, x, y
	for e = 1, type(n) == "number" and n or 0 do
		local ok, info = pcall(C_QuestLog.GetInfo, e)
		local questID = ok and type(info) == "table" and not Plain(info.isHeader) and Plain(info.questID)
		if type(questID) == "number" and questID > 0 then
			local lines = QO.Lines(questID)
			local was = L.counts[questID]
			if not was then
				was = {}
				L.counts[questID] = was
			end
			-- (2.1.60) the quest's data asked for only when one of its counts went up: this read comes after every change
			-- of the log, and asked for every quest of the log it was the conversion of them all each time (QuestSource)
			local data, itemLine, asked
			for _, t in ipairs(lines) do
				local i, have = t[3], t[7]
				if type(have) == "number" then
					local before = was[i]
					was[i] = have
					if learnNow and before and have > before then
						if not asked then
							asked = true
							data = DataOf(questID)
							itemLine = data and QO.ItemLine(data, lines) or nil
						end
						local placed = false
						for _, entry in ipairs(data or {}) do
							if QO.Match(entry, lines, itemLine) == t then
								placed = true
								break
							end
						end
						if not placed then
							if not cont then
								cont, x, y = QO.PlayerWorld()
							end
							if cont then
								QO.Learn(questID, i, t, cont, x, y)
							end
						end
					end
				end
			end
		end
	end
end

QO.learnFrame = CreateFrame("Frame")
QO.learnFrame:RegisterEvent("QUEST_LOG_UPDATE")
QO.learnFrame:SetScript("OnEvent", function()
	local L = QO.learn
	if not L.queued then
		L.queued = true
		C_Timer.After(LEARN.WAIT, QO.ReadCounts)
	end
end)

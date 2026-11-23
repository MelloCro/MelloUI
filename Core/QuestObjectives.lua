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
--------------------------------------------------------------------------------
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
		return nil
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
local TRACE = { STEP = 40, PER_FRAME = 600, MAX_CELLS = 140 * 140, SIZE = 256 }
QO.TRACE = TRACE
QO.traced = {}   -- [questID] = { sig = its objectives' done flags, entries = list | false }
QO.trace = { queue = {}, queued = {}, job = nil, frame = nil, driver = nil }

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

local function Driver()
	local T = QO.trace
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
				QO.traced[q] = { sig = DoneSig(q), entries = false }
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
		QO.traced[q] = { sig = DoneSig(q), entries = Entries(q, job.want[q], job.nx, job.ny, job.w) }
	end
	T.job = nil
	MelloUI:Fire("questareas:ready")
end

-- a quest asked for: queued on its zone's list once (its zone's quests traced together)
local function Request(questID)
	local T = QO.trace
	if T.queued[questID] then
		return
	end
	local mapOf, Finite = rawget(_G, "GetQuestUiMapID"), MelloUI.Safe.Finite
	local ok, map = false, nil
	if mapOf then
		ok, map = pcall(mapOf, questID)
	end
	map = ok and Finite(map) or nil
	if not (map and map > 0) then
		QO.traced[questID] = { sig = DoneSig(questID), entries = false }
		return
	end
	T.queued[questID] = true
	local list = T.queue[map]
	if not list then
		list = {}
		T.queue[map] = list
	end
	list[#list + 1] = questID
	if not T.driver then
		T.driver = CreateFrame("Frame")
	end
	T.driver:SetScript("OnUpdate", Driver)
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

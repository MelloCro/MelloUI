--------------------------------------------------------------------------------
-- MelloUI - Guide: the quest records at runtime
--
-- The planner's quest records (GuidePlan.lua's record shape), made in the
-- game from the Quest List's data (MelloUI_QuestListData, read through the
-- Quest List's own readers: QL.RowByID, QL.F_*, QL.Closed, QL.ZoneOf) and
-- the Companion's objective places (MelloUI.QuestObjectives). Nothing of
-- Mello's tables is copied into the guide's files: what is derived here
-- lives for the session only.
--
--   Data.records(side, classFile, minLevel, maxLevel[, playerLevel])
--                       -> { record }, { dropped = n, droppedIDs = { id },
--                       objectives = false when the Companion's places were
--                       not there (the records then have givers only) }
--   Data.state()        -> done, log, unknown: the quests turned in and the
--                       quests in the log as sets ([questID] = true), only
--                       those the data knows; unknown = { done = n, log = n },
--                       the ones it does not (Forever's newest), left out
--   Data.areaTitles()   -> { [areaKey] = name }, for the planner's ctx
--   Data.otherStarts(side, done, here) -> { [areaKey] = true }: the other
--     races' starting areas and their capitals (not the character's own)
--   Data.foreignAreas(side) -> { [areaKey] = true }: the other side's
--                       territory, left out of the cards and the session
--                       (the steps drop these areas' records before they
--                       plan). An area is the other side's when more than
--                       half of its quests in the data (any level and class;
--                       world event and dungeon quests left out; the area as
--                       the records take it) are that side's only (2 for the
--                       Alliance, 1 for the Horde) and fewer than 10 are this
--                       side's only: The Barrens and Durotar are the Horde's
--                       though a few of their quests are open to both,
--                       Hillsbrad (Southshore's 18 quests beside Tarren
--                       Mill's 40) stays both sides'. Made once a session.
--
-- Field by field (which source wins):
--   area        the quest's own zone (the data's quest zone: where it is
--               done, The Killing Fields is Westfall's though it is picked
--               up at Elwynn's edge); a quest with none, or one that is no
--               zone of the data, takes the Quest List's pick-up zone
--               (QL.ZoneOf: the client's placement once resolved)
--   level       the data's level; 0 or below (a quest that scales) counts
--               as the character's level
--   giver       the data's giver place in world yards, when it has one; for
--               a quest begun by an item (kind 3 dropped, 4 picked up) that
--               is the item's densest spot already
--   turnIn      the data's turn-in place, when it has one
--   chain, prev the data's chain and previous quest
--   needs       the data's `needs.after`: of its choices, the first one met
--               now, else the first; a choice "in the log" (a negative id)
--               is asked for as turned in (the planner knows no other way)
--   objectives  one place per objective of the Companion's data: the point
--               with the most of the objective's points within 250 yards
--               (the planner's camp)
--   xpLo, xpHi  GuideXP.estimate at the character's level
--   elite       not known yet (the open data has no quest's creatures)
-- A quest with neither a giver place nor an objective place cannot be led to:
-- it is dropped, and counted.
-- Left out: other sides and classes, the quests the Quest List says are never
-- offered to this character (QL.Closed), world event quests, dungeon quests,
-- quests begun only inside an instance.
--------------------------------------------------------------------------------

local _, ns = ...

local Data = {}
ns.Data = Data

local floor, abs, ceil = math.floor, math.abs, math.ceil

local SIDES = { Alliance = 1, Horde = 2 }   -- the data's sides; 0 and 3 are both
local CAMP = 250                            -- yards: an objective's place is its densest spot within this
local CENTRES = 32                          -- at most this many of an objective's points tried as its centre

-- (looked up when asked, not bound at load)
local function QL()
	return MelloUI and MelloUI.QuestList
end

local function Plain(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return v
end

local function PlayerLevel()
	local ok, level = pcall(UnitLevel, "player")
	level = ok and Plain(level) or nil
	return type(level) == "number" and level > 0 and level or 1
end

--------------------------------------------------------------------------------
-- Objective places
--------------------------------------------------------------------------------

-- [questID] = { { cont, x, y }, ... } (empty when the data has none), made
-- once a session from the Companion's data
local places = {}

-- the Companion's objective places, loaded when they are not yet (it loads on
-- demand: Route asks for it too); false when the game would not load it now
local function CompanionReady()
	if rawget(_G, "MelloUI_QuestObjectiveData") then
		return true
	end
	if MelloUI and MelloUI.LoadCompanion then
		pcall(MelloUI.LoadCompanion, MelloUI)
	end
	return rawget(_G, "MelloUI_QuestObjectiveData") ~= nil
end

-- an entry's densest point: of its points (from entry[5] on, x and y in
-- turn), the one with the most others within CAMP yards; the first wins a tie
local function Densest(entry)
	local n = floor((#entry - 4) / 2)
	if n < 1 then
		return nil
	end
	local step = ceil(n / CENTRES)
	local bestI, bestN = 1, -1
	for i = 1, n, step do
		local x, y = entry[3 + 2 * i], entry[4 + 2 * i]
		local count = 0
		for j = 1, n do
			local dx, dy = entry[3 + 2 * j] - x, entry[4 + 2 * j] - y
			if dx * dx + dy * dy <= CAMP * CAMP then
				count = count + 1
			end
		end
		if count > bestN then
			bestI, bestN = i, count
		end
	end
	return { cont = entry[4], x = entry[3 + 2 * bestI], y = entry[4 + 2 * bestI] }
end

local function ObjectivePlaces(questID)
	local list = places[questID]
	if list then
		return list
	end
	list = {}
	local QO = MelloUI and MelloUI.QuestObjectives
	local entries = QO and QO.Of(questID)
	for _, entry in ipairs(entries or {}) do
		-- (one kept for a needed item alone has no coordinates)
		if type(entry) == "table" and #entry > 5 and type(entry[4]) == "number" then
			local p = Densest(entry)
			if p then
				list[#list + 1] = p
			end
		end
	end
	places[questID] = list
	return list
end

--------------------------------------------------------------------------------
-- The records
--------------------------------------------------------------------------------

-- the character's class bit in the data's masks, nil for a class it does not
-- know (then no class quest is kept)
local function ClassBit(data, classFile)
	for mask, file in pairs(data.classes or {}) do
		if file == classFile then
			return mask
		end
	end
	return nil
end

-- one of `needs.after`'s choices met now: a quest turned in (a negative id: in
-- the log), or every quest of a list
local function ChoiceMet(q, choice)
	if type(choice) == "table" then
		for _, id in ipairs(choice) do
			if not ChoiceMet(q, id) then
				return false
			end
		end
		return true
	end
	if choice < 0 then
		return q.IsOnQuest(-choice)
	end
	return q.IsCompleted(choice)
end

-- the planner's needs: the quest IDs of one choice (one, or a list)
local function NeedsOf(q, after)
	if after == nil then
		return nil
	end
	local list = type(after) == "table" and after or { after }
	local pick = list[1]
	for _, choice in ipairs(list) do
		if ChoiceMet(q, choice) then
			pick = choice
			break
		end
	end
	if type(pick) == "table" then
		local ids = {}
		for i, id in ipairs(pick) do
			ids[i] = abs(id)
		end
		return ids
	end
	return type(pick) == "number" and abs(pick) or nil
end

local function AreaOf(q, data, row)
	local zone = row[q.F_ZONE]
	if zone and zone ~= 0 and data.zones and data.zones[zone] and not (data.dungeons and data.dungeons[zone]) then
		return zone
	end
	zone = q.ZoneOf(row)
	return zone ~= 0 and zone or nil
end

local function Place(cont, x, y)
	if type(cont) ~= "number" or cont < 0 or type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	return { cont = cont, x = x, y = y }
end

function Data.records(side, classFile, minLevel, maxLevel, playerLevel)
	local q = QL()
	local data = q and q.Data()
	local out, stats = {}, { dropped = 0, droppedIDs = {}, objectives = true }
	if type(data) ~= "table" or type(data.quests) ~= "table" then
		stats.objectives = false
		return out, stats
	end
	playerLevel = playerLevel or PlayerLevel()
	minLevel, maxLevel = minLevel or 1, maxLevel or playerLevel + 2
	local sideID = SIDES[side]
	local classBit = ClassBit(data, classFile)
	local after = data.needs and data.needs.after or {}
	-- (QL.Closed tests a quest's races only once the Quest List has built its
	-- index, which it does when the module is on: it has no public way to ask
	-- for the character's race bit or to build the index. With the module off,
	-- a quest for other races stays in.)
	local companion = CompanionReady()
	stats.objectives = companion
	local XP = ns.XP
	for _, row in ipairs(data.quests) do
		local rowSide, mask = row[q.F_SIDE], row[q.F_CLASS]
		local level = row[q.F_LEVEL]
		if not level or level <= 0 then
			level = playerLevel
		end
		if level >= minLevel and level <= maxLevel
			and (rowSide == 0 or rowSide == 3 or rowSide == sideID)
			and (mask == 0 or (classBit and bit.band(mask, classBit) ~= 0))
			and row[q.F_EVENT] == 0 and row[q.F_DUNGEON] == 0 and not q.InstanceStart(row)
			and not q.Closed(row) then
			local id = row[q.F_ID]
			local giver = Place(row[q.F_CONT], row[q.F_WX], row[q.F_WY])
			if giver then
				local npc = row[q.F_NPC]
				giver.npc = (npc and npc ~= 0) and npc or nil
				giver.kind = row[q.F_KIND]
			end
			local objectives = companion and ObjectivePlaces(id) or {}
			if not giver and #objectives == 0 then
				stats.dropped = stats.dropped + 1
				stats.droppedIDs[#stats.droppedIDs + 1] = id
			else
				local turnIn = Place(row[q.F_ENDERCONT], row[q.F_ENDERWX], row[q.F_ENDERWY])
				if turnIn then
					local npc = row[q.F_ENDERNPC]
					turnIn.npc = (npc and npc ~= 0) and npc or nil
				end
				local chain, prev = row[q.F_CHAIN], row[q.F_PREV]
				local record = {
					id = id,
					title = row[q.F_TITLE],
					level = level,
					reqLevel = row[q.F_REQ],
					area = AreaOf(q, data, row),
					giver = giver,
					turnIn = turnIn,
					chain = (chain and chain ~= 0) and chain or nil,
					prev = (prev and prev ~= 0) and prev or nil,
					needs = NeedsOf(q, after[id]),
					objectives = objectives,
				}
				if XP then
					record.xpLo, record.xpHi = XP.estimate(record, playerLevel)
				end
				out[#out + 1] = record
			end
		end
	end
	return out, stats
end

--------------------------------------------------------------------------------
-- What the character has done and holds
--------------------------------------------------------------------------------

function Data.state()
	local q = QL()
	local known = q and q.RowByID() or {}
	local done, log, unknown = {}, {}, { done = 0, log = 0 }
	local function Add(set, kind, id)
		id = Plain(id)
		if type(id) ~= "number" then
			return
		end
		if known[id] then
			set[id] = true
		else
			unknown[kind] = unknown[kind] + 1
		end
	end
	if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
		local ok, ids = pcall(C_QuestLog.GetAllCompletedQuestIDs)
		if ok and type(Plain(ids)) == "table" then
			for _, id in ipairs(ids) do
				Add(done, "done", id)
			end
		end
	end
	if q and q.LogQuestIDs then
		local ids = {}
		q.LogQuestIDs(ids)
		for _, id in ipairs(ids) do
			Add(log, "log", id)
		end
	end
	return done, log, unknown
end

function Data.areaTitles()
	local q = QL()
	local data = q and q.Data()
	return type(data) == "table" and data.zones or {}
end

--------------------------------------------------------------------------------
-- The other side's territory
--------------------------------------------------------------------------------

local FOREIGN_SHARE = 0.5   -- more than this share of an area's quests the other side's only ...
local OWN_FEW = 10          -- ... and fewer than this many this side's only: the other side's territory

local foreign = {}          -- [side] = { [areaKey] = true }, made once a session

function Data.foreignAreas(side)
	if foreign[side] then
		return foreign[side]
	end
	local q = QL()
	local data = q and q.Data()
	local own = SIDES[side]
	local out = {}
	if not own or type(data) ~= "table" or type(data.quests) ~= "table" then
		return out   -- (not kept: asked again once the data is there)
	end
	local other = own == 1 and 2 or 1
	local count = {}   -- [areaKey] = { all, other's only, own only }
	for _, row in ipairs(data.quests) do
		if row[q.F_EVENT] == 0 and row[q.F_DUNGEON] == 0 then
			local area = AreaOf(q, data, row)
			if area then
				local c = count[area]
				if not c then
					c = { 0, 0, 0 }
					count[area] = c
				end
				c[1] = c[1] + 1
				local rowSide = row[q.F_SIDE]
				if rowSide == other then
					c[2] = c[2] + 1
				elseif rowSide == own then
					c[3] = c[3] + 1
				end
			end
		end
	end
	for area, c in pairs(count) do
		if c[2] > c[1] * FOREIGN_SHARE and c[3] < OWN_FEW then
			out[area] = true
		end
	end
	foreign[side] = out
	return out
end

--------------------------------------------------------------------------------
-- Other races' starting areas (Denis, 2026-10-18: "Yes, skip other races'
-- starting areas in the cards")
--------------------------------------------------------------------------------

-- A starting area: one with at least START_MIN of this side's quests of level
-- START_LEVEL or below (Elwynn, Dun Morogh, Teldrassil, Zephras Isle for the
-- Alliance in Forever's data). A race's capital goes with its starting area
-- (STARTER_CITY, by the areas' names: the game's own pairs). The character's
-- home start is the starting area holding most of its done quests, else the
-- area it stands in; every other start and its capital are left out of the
-- cards and the sessions. Class quests are not filtered (their givers stand
-- where they stand).
local START_LEVEL, START_MIN = 4, 5
local STARTER_CITY = {
	["Elwynn Forest"] = "Stormwind City", ["Dun Morogh"] = "Ironforge", ["Teldrassil"] = "Darnassus",
	["Durotar"] = "Orgrimmar", ["Mulgore"] = "Thunder Bluff", ["Tirisfal Glades"] = "Undercity",
}

local starters = {}         -- [side] = { [areaKey] = true }, made once a session

local function StarterAreas(side)
	if starters[side] then
		return starters[side]
	end
	local q = QL()
	local data = q and q.Data()
	local own = SIDES[side]
	local out = {}
	if not own or type(data) ~= "table" or type(data.quests) ~= "table" then
		return out
	end
	local low = {}
	for _, row in ipairs(data.quests) do
		local rowSide = row[q.F_SIDE]
		if row[q.F_EVENT] == 0 and row[q.F_DUNGEON] == 0 and (rowSide == own or rowSide == 3)
			and (tonumber(row[q.F_LEVEL]) or 99) <= START_LEVEL then
			local area = AreaOf(q, data, row)
			if area then
				low[area] = (low[area] or 0) + 1
			end
		end
	end
	for area, n in pairs(low) do
		if n >= START_MIN then
			out[area] = true
		end
	end
	starters[side] = out
	return out
end

-- Data.otherStarts(side, done, here) -> { [areaKey] = true }: the starting
-- areas (and their capitals) that are not the character's own
function Data.otherStarts(side, done, here)
	local q = QL()
	local data = q and q.Data()
	local starts = StarterAreas(side)
	local out = {}
	if not (q and type(data) == "table") then
		return out
	end
	-- home: the start holding most of the done quests, else where it stands
	local home, best = nil, 0
	local count = {}
	for id in pairs(done or {}) do
		local row = q.RowByID()[id]
		local area = row and AreaOf(q, data, row)
		if area and starts[area] then
			count[area] = (count[area] or 0) + 1
			if count[area] > best then
				home, best = area, count[area]
			end
		end
	end
	if not home and here and starts[here] then
		home = here
	end
	local zones = data.zones or {}
	local byName = {}
	for key, name in pairs(zones) do
		byName[name] = key
	end
	for area in pairs(starts) do
		if area ~= home then
			out[area] = true
			local city = STARTER_CITY[zones[area] or ""]
			if city and byName[city] then
				out[byName[city]] = true
			end
		end
	end
	return out
end

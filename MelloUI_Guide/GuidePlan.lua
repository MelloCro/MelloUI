--------------------------------------------------------------------------------
-- MelloUI - Guide: the planner
--
-- Where to go next and in which order, from the character's level, XP and
-- rested XP, the quests it has done and has in its log, and the guide's quest
-- records (GuideData.lua builds them at runtime from the Quest List's data
-- and the open tables). Plain Lua 5.1 and no game API at all, so it runs
-- under plain LuaJIT in the specs: everything it knows comes in through ctx,
-- and the travel cost between two places through ctx.cost (Route's
-- CostBetween in the game).
--
--   Plan.areas(ctx)                   -> { area }, the choice cards, best first
--   Plan.session(ctx, areaKey, mode)  -> { steps, breakReason, seconds, levels }
--
-- ctx     { level, xp, xpMax, rested, side, classFile, done = set, log = set,
--           pos = { cont, x, y }, records = { record }, cost = function(a, b)
--           -> seconds, estimated; optional: xpByLevel = { [level] = xp to
--           the next }, areaTitles = { [key] = title }, chosen = { areaKey },
--           mode }
-- record  { id, title, level, reqLevel, area, giver = { cont, x, y, npc,
--           kind }, turnIn = { cont, x, y, npc }, chain, prev, needs,
--           objectives = { { cont, x, y } }, xpLo, xpHi, elite; optional:
--           side, classes }
-- area    { key, title, levelsFrom, levelsTo, seconds, quests, chains,
--           travel, estimated, tag = "Recommended" | "Short stay" | nil,
--           reason }
-- step    { kind = "take" | "do" | "turnin" | "travel" | "grind", questIDs,
--           place = { cont, x, y }, label, seconds }
-- mode    "fast" (XP per second, travel included), "scenic" (story chains
--           first, less hopping), "zones" (the areas in ctx.chosen, in that
--           order), "complete" (every quest of an area, grey ones too)
--
-- How a stay is planned: in rounds. A round takes every quest the character
-- can do now (level within -5..+2, required level reached, the previous
-- quest of its chain and its needs turned in), bundled by place: every take
-- first (one stop per giver), then each camp where objectives lie together
-- (every quest whose objectives are within 250 yards of the camp's centre),
-- then the turn-ins (one stop per NPC). Places are visited nearest first.
-- The XP of the round's turn-ins may raise the level, and a chain's next
-- quest is only offered once the one before is turned in, so the next round
-- holds what this one opened (a chain's earlier steps always come first).
-- The stay ends at its break point: the area has nothing left the character
-- can do ("dry"), or what is left is grey ("outgrown"). One more quest is
-- then taken when even its lowest XP estimate reaches the next level; when
-- no quest fits at all, a grind step (mobs of the character's level, kill
-- XP doubled while rested) fills the gap ("thin").
--
-- Records are trusted to be the character's side and class (GuideData
-- filters them); a record's side and classes are checked only when present.
--------------------------------------------------------------------------------

local _, ns = ...
ns = ns or {}

local Plan = {}
ns.Plan = Plan

local floor, max, sqrt = math.floor, math.max, math.sqrt

-- The planner's numbers. Every one is INFERRED (our estimate, not a game fact),
-- to be tuned in play.
local WALK = 7              -- yards a second on foot (the straight-line estimate when ctx.cost has no answer)
local CROSSING = 600        -- seconds from one continent to another with no answer: a boat or tram trip plus walking
local OBJECTIVE = 90        -- seconds per objective of a quest (finding the mobs or objects and doing it)
local HANDLE = 10           -- seconds per quest taken or turned in (talking, reading)
local CAMP = 250            -- yards: objectives within this of a camp's centre are one bundle
local NEAR = 30             -- yards: quests begun (or ended) with no NPC this close are one stop
local BELOW, ABOVE = 5, 2   -- the quest levels a character does: its own -5 .. +2
local SHORT = 5             -- fewer quests than this before the stay ends: "Short stay"
local CARDS = 3             -- the most areas offered at once
local KILL = 40             -- seconds per kill while grinding, fight and recovery
local GRIND_RANGE = 1       -- grind mobs of the character's level -1 .. +1
local ROUNDS = 30           -- at most this many rounds in one stay (a guard, never reached by real data)

-- XP from one level to the next (vanilla's table, INFERRED for Forever) for the
-- levels past the current one when ctx.xpByLevel does not have them
local XP_TO_LEVEL = {
	400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
	8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
	25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
	50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
	95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
	153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
}

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function distance(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return sqrt(dx * dx + dy * dy)
end

-- the seconds from a to b and whether they are an estimate: ctx.cost's answer
-- when it has one, else a straight line on foot, or a flat crossing between
-- continents (the coordinates of two continents do not share a frame)
local function travel(ctx, a, b)
	if ctx.cost then
		local seconds, estimated = ctx.cost(a, b)
		if seconds then return seconds, estimated and true or false end
	end
	if a.cont == b.cont then return distance(a, b) / WALK, true end
	return CROSSING, true
end

local function samePlace(a, b, within)
	return a.cont == b.cont and distance(a, b) <= within
end

-- the XP from a level to the next
local function xpFor(ctx, level)
	local own = ctx.xpByLevel and ctx.xpByLevel[level]
	return own or XP_TO_LEVEL[level] or XP_TO_LEVEL[#XP_TO_LEVEL]
end

-- the XP a quest is counted for: its lowest estimate, so a plan never promises
-- a level the quest may not give
local function questXP(r)
	return r.xpLo or r.xpHi or 0
end

local function questLevel(r)
	return r.level or r.reqLevel or 1
end

-- where a quest is taken: its giver, else (an item that starts it with no
-- place) its first objective; nil means the planner cannot lead there
local function takePlace(r)
	if r.giver and r.giver.x then return r.giver end
	return r.objectives and r.objectives[1]
end

local function turnInPlace(r)
	if r.turnIn and r.turnIn.x then return r.turnIn end
	return takePlace(r)
end

-- the middle of a quest's objectives (those on the first one's continent)
local function objectiveCentre(r)
	local list = r.objectives
	if not list or not list[1] then return nil end
	local cont, sx, sy, n = list[1].cont, 0, 0, 0
	for _, o in ipairs(list) do
		if o.cont == cont then sx, sy, n = sx + o.x, sy + o.y, n + 1 end
	end
	return { cont = cont, x = sx / n, y = sy / n }
end

local function titlesOf(list)
	local names = {}
	for i, r in ipairs(list) do names[i] = r.title or ("quest " .. r.id) end
	if #names <= 1 then return names[1] or "" end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

local function idsOf(list)
	local ids = {}
	for i, r in ipairs(list) do ids[i] = r.id end
	return ids
end

local function areaTitle(ctx, key)
	return (ctx.areaTitles and ctx.areaTitles[key]) or tostring(key)
end

local function minutes(seconds)
	local m = floor(seconds / 60 + 0.5)
	if m < 1 then return "under a minute" end
	return m == 1 and "1 min" or (m .. " min")
end

--------------------------------------------------------------------------------
-- The simulated character: level, XP and where it stands, as the plan goes
--------------------------------------------------------------------------------

local function newState(ctx)
	local first = ctx.records and ctx.records[1]
	return {
		level = ctx.level or 1,
		xp = ctx.xp or 0,
		xpMax = ctx.xpMax or xpFor(ctx, ctx.level or 1),
		rested = ctx.rested or 0,
		place = ctx.pos or (first and takePlace(first)) or { cont = 0, x = 0, y = 0 },
		planned = {},     -- [questID] = true: in the plan (taken in it, or from the log)
		turnedIn = {},    -- [questID] = true: turned in by the plan
		steps = {},
		seconds = 0,
		estimated = false,
		quests = 0,
		chains = {},      -- [chain] = true
		xpGained = 0,
		travel = nil,     -- the seconds of the stay's first move (to the area)
	}
end

local function fractionalLevel(st)
	return st.level + (st.xpMax > 0 and st.xp / st.xpMax or 0)
end

local function gain(ctx, st, xp)
	st.xp, st.xpGained = st.xp + xp, st.xpGained + xp
	while st.xp >= st.xpMax do
		st.xp = st.xp - st.xpMax
		st.level = st.level + 1
		st.xpMax = xpFor(ctx, st.level)
	end
end

-- moves the character to place and counts the time
local function moveTo(ctx, st, place)
	local seconds, estimated = travel(ctx, st.place, place)
	st.seconds = st.seconds + seconds
	if estimated then st.estimated = true end
	st.place = place
	if st.travel == nil then st.travel = seconds end
	return seconds
end

local function addStep(st, kind, list, place, label, seconds)
	local step = { kind = kind, questIDs = list and idsOf(list) or {}, place = place, label = label, seconds = seconds or 0 }
	st.steps[#st.steps + 1] = step
	return step
end

-- a "travel" step first when the place is out of the camp's reach (another
-- continent or farther than CAMP yards), then the move itself
local function goTo(ctx, st, place, label)
	if not samePlace(st.place, place, CAMP) then
		local seconds = moveTo(ctx, st, place)
		addStep(st, "travel", nil, place, label, seconds)
		return seconds
	end
	return moveTo(ctx, st, place)
end

--------------------------------------------------------------------------------
-- Which quests the character can do
--------------------------------------------------------------------------------

local function isSet(set, id)
	return set and set[id] and true or false
end

local function finished(ctx, st, id)
	return isSet(ctx.done, id) or st.turnedIn[id] == true
end

-- the quests that must be turned in before this one: the chain's previous one
-- and its needs (a list of quest IDs, or one)
local function prerequisitesMet(ctx, st, r)
	if r.prev and r.prev ~= 0 and not finished(ctx, st, r.prev) then return false end
	local needs = r.needs
	if type(needs) == "number" then
		if needs ~= 0 and not finished(ctx, st, needs) then return false end
	elseif type(needs) == "table" then
		for _, id in ipairs(needs) do
			if not finished(ctx, st, id) then return false end
		end
	end
	return true
end

local function allowed(ctx, r)
	if r.side and ctx.side and r.side ~= ctx.side and r.side ~= "both" then return false end
	if r.classes and ctx.classFile then
		if type(r.classes) == "table" then
			local ok = r.classes[ctx.classFile]
			if not ok then
				for _, c in ipairs(r.classes) do if c == ctx.classFile then ok = true end end
			end
			if not ok then return false end
		elseif r.classes ~= ctx.classFile then
			return false
		end
	end
	return true
end

-- open: not done, not planned, a place to go, its side and class, its chain
-- and needs turned in, and the character's level reached
local function open(ctx, st, r)
	if isSet(ctx.done, r.id) or st.planned[r.id] then return false end
	if not takePlace(r) or not allowed(ctx, r) then return false end
	if not prerequisitesMet(ctx, st, r) then return false end
	if isSet(ctx.log, r.id) then return true end   -- already taken: no level asked
	return (r.reqLevel or 0) <= st.level and questLevel(r) <= st.level + ABOVE
end

local function doable(ctx, st, r, mode)
	if not open(ctx, st, r) then return false end
	if mode == "complete" or isSet(ctx.log, r.id) then return true end
	return questLevel(r) >= st.level - BELOW
end

--------------------------------------------------------------------------------
-- Bundles
--------------------------------------------------------------------------------

-- groups quests into stops ({ place, quests }): one per NPC (Route leads to
-- that NPC), and, for quests with no NPC (an item, an object), the ones whose
-- places are within `within` yards of each other
local function stops(list, placeOf, npcOf, within)
	local out = {}
	for _, r in ipairs(list) do
		local place, npc, stop = placeOf(r), npcOf(r), nil
		for _, s in ipairs(out) do
			if npc and s.npc == npc then stop = s break end
			if not npc and not s.npc and samePlace(s.place, place, within) then stop = s break end
		end
		if stop then
			stop.quests[#stop.quests + 1] = r
		else
			out[#out + 1] = { place = place, npc = npc, quests = { r } }
		end
	end
	return out
end

-- the camps: every quest whose objectives' centre lies within CAMP yards of a
-- camp's centre joins it; the centre follows its members
local function camps(list)
	local out = {}
	for _, r in ipairs(list) do
		local c = objectiveCentre(r)
		if c then
			local camp
			for _, k in ipairs(out) do
				if samePlace(k.place, c, CAMP) then camp = k break end
			end
			if camp then
				local n = #camp.quests
				camp.quests[n + 1] = r
				camp.place = { cont = camp.place.cont, x = (camp.place.x * n + c.x) / (n + 1), y = (camp.place.y * n + c.y) / (n + 1) }
			else
				out[#out + 1] = { place = c, quests = { r } }
			end
		end
	end
	return out
end

-- visits the stops nearest first from where the character stands
local function nearestFirst(ctx, st, list, visit)
	local left = {}
	for i, s in ipairs(list) do left[i] = s end
	while #left > 0 do
		local best, bestCost = 1, nil
		for i, s in ipairs(left) do
			local seconds = travel(ctx, st.place, s.place)
			if not bestCost or seconds < bestCost then best, bestCost = i, seconds end
		end
		visit(table.remove(left, best))
	end
end

local function objectiveCount(list)
	local n = 0
	for _, r in ipairs(list) do n = n + (r.objectives and #r.objectives or 0) end
	return n
end

local function giverNpc(r) return r.giver and r.giver.npc end
local function turnInNpc(r) return (r.turnIn and r.turnIn.npc) or (r.giver and r.giver.npc) end

-- plans one bundle of quests: every take, every camp, every turn-in
local function bundle(ctx, st, list, areaLabel, note)
	for _, r in ipairs(list) do
		st.planned[r.id] = true
		st.quests = st.quests + 1
		if r.chain and r.chain ~= 0 then st.chains[r.chain] = true end
	end
	local toTake = {}
	for _, r in ipairs(list) do
		if not isSet(ctx.log, r.id) then toTake[#toTake + 1] = r end
	end
	nearestFirst(ctx, st, stops(toTake, takePlace, giverNpc, NEAR), function(s)
		if #st.steps == 0 and areaLabel then goTo(ctx, st, s.place, "Travel to " .. areaLabel) else moveTo(ctx, st, s.place) end
		local seconds = HANDLE * #s.quests
		st.seconds = st.seconds + seconds
		addStep(st, "take", s.quests, s.place, "Take " .. titlesOf(s.quests) .. (note or ""), seconds)
	end)
	nearestFirst(ctx, st, camps(list), function(k)
		goTo(ctx, st, k.place, "Go to the camp of " .. titlesOf(k.quests))
		local seconds = OBJECTIVE * objectiveCount(k.quests)
		st.seconds = st.seconds + seconds
		addStep(st, "do", k.quests, k.place, "Do " .. titlesOf(k.quests), seconds)
	end)
	nearestFirst(ctx, st, stops(list, turnInPlace, turnInNpc, NEAR), function(s)
		goTo(ctx, st, s.place, "Back to turn in " .. titlesOf(s.quests))
		local seconds = HANDLE * #s.quests
		st.seconds = st.seconds + seconds
		addStep(st, "turnin", s.quests, s.place, "Turn in " .. titlesOf(s.quests), seconds)
		for _, r in ipairs(s.quests) do
			st.turnedIn[r.id] = true
			gain(ctx, st, questXP(r))
		end
	end)
end

--------------------------------------------------------------------------------
-- A stay in one area, the "one more quest" rule and grinding
--------------------------------------------------------------------------------

local function recordsOf(ctx, key)
	local list = {}
	for _, r in ipairs(ctx.records or {}) do
		if key == nil or r.area == key then list[#list + 1] = r end
	end
	return list
end

-- one round: every quest of the area the character can do now; false when none
local function round(ctx, st, key, mode)
	local list = {}
	for _, r in ipairs(recordsOf(ctx, key)) do
		if doable(ctx, st, r, mode) then list[#list + 1] = r end
	end
	if #list == 0 then return false end
	table.sort(list, function(a, b) return a.id < b.id end)
	bundle(ctx, st, list, key ~= nil and areaTitle(ctx, key) or nil)
	return true
end

-- why the stay ends: what is left of the area is grey, or nothing is left
local function breakReason(ctx, st, key, mode)
	for _, r in ipairs(recordsOf(ctx, key)) do
		if mode ~= "complete" and open(ctx, st, r) and questLevel(r) < st.level - BELOW then return "outgrown" end
	end
	return "dry"
end

local function stay(ctx, st, key, mode)
	local rounds = 0
	while rounds < ROUNDS and round(ctx, st, key, mode) do rounds = rounds + 1 end
	return rounds
end

-- one more quest: when even the lowest XP estimate of a quest the character
-- can take (grey ones too, from any area) reaches the next level, it is taken
-- now, the nearest of them
local function oneMore(ctx, st)
	local need = st.xpMax - st.xp
	local best, bestCost
	for _, r in ipairs(ctx.records or {}) do
		if open(ctx, st, r) and questXP(r) >= need then
			local seconds = travel(ctx, st.place, takePlace(r))
			if not bestCost or seconds < bestCost or (seconds == bestCost and r.id < best.id) then best, bestCost = r, seconds end
		end
	end
	if not best then return false end
	bundle(ctx, st, { best }, nil, ": one more quest for level " .. (st.level + 1))
	return true
end

-- kill XP of a mob of the character's level: 45 + 5 x level (vanilla's rule
-- for Azeroth, INFERRED for Forever), doubled while rested XP lasts; rested
-- XP is used up by the bonus. Returns the kills and seconds to the next level.
local function grindTime(st)
	local per = 45 + 5 * st.level
	local need, rested, kills = st.xpMax - st.xp, st.rested, 0
	while need > 0 do
		if rested >= per then
			need, rested = need - 2 * per, rested - per
		else
			need = need - per
		end
		kills = kills + 1
	end
	return kills, kills * KILL, rested
end

-- the grind spot: where most quest objectives of quests of the character's
-- level (-1..+1, done or not) lie close together, in the area when it has
-- some, else anywhere. INFERRED: the records carry no mob places, and a quest's
-- objectives at its level are where mobs of that level are.
local function grindSpot(ctx, st, key)
	local function points(list)
		local out = {}
		for _, r in ipairs(list) do
			local lvl = questLevel(r)
			if lvl >= st.level - GRIND_RANGE and lvl <= st.level + GRIND_RANGE then
				for _, o in ipairs(r.objectives or {}) do out[#out + 1] = o end
			end
		end
		return out
	end
	local list = points(recordsOf(ctx, key))
	if #list == 0 and key ~= nil then list = points(ctx.records or {}) end
	local best, bestN
	for _, p in ipairs(list) do
		local n = 0
		for _, q in ipairs(list) do
			if samePlace(p, q, CAMP) then n = n + 1 end
		end
		if not bestN or n > bestN then best, bestN = p, n end
	end
	return best
end

local function grind(ctx, st, key)
	-- no travel step of its own: the grind step's place is where Route leads
	local spot = grindSpot(ctx, st, key) or st.place
	moveTo(ctx, st, spot)
	local kills, seconds, rested = grindTime(st)
	local target = st.level + 1
	st.seconds = st.seconds + seconds
	addStep(st, "grind", nil, spot, string.format("Grind level %d-%d mobs here: about %s to level %d",
		max(1, st.level - GRIND_RANGE), st.level + GRIND_RANGE, minutes(seconds), target), seconds).kills = kills
	st.rested = rested
	gain(ctx, st, st.xpMax - st.xp)
end

-- the whole session in an area: its stay, then one more quest when it reaches
-- the next level; when nothing fits at all, one grind step to the next level
-- and the stay again
local function plan(ctx, key, mode)
	local st = newState(ctx)
	local from = fractionalLevel(st)
	local reason
	if stay(ctx, st, key, mode) > 0 then
		reason = breakReason(ctx, st, key, mode)
		oneMore(ctx, st)
	elseif oneMore(ctx, st) then
		reason = breakReason(ctx, st, key, mode)
	else
		grind(ctx, st, key)
		if stay(ctx, st, key, mode) > 0 then
			reason = breakReason(ctx, st, key, mode)
			oneMore(ctx, st)
		else
			reason = "thin"
		end
	end
	st.breakReason = reason
	st.levelsFrom, st.levelsTo = from, fractionalLevel(st)
	return st
end

--------------------------------------------------------------------------------
-- The choice cards
--------------------------------------------------------------------------------

local function chainCount(st)
	local n = 0
	for _ in pairs(st.chains) do n = n + 1 end
	return n
end

local function plural(n, one, many)
	return n .. " " .. (n == 1 and one or many)
end

-- how good a stay is: XP per second, travel included (fast); story chains
-- weigh more and long travel less (scenic); the most quests (complete)
local function score(st, mode)
	local perSecond = st.xpGained / max(st.seconds, 1)
	if mode == "scenic" then
		local share = st.quests > 0 and chainCount(st) / st.quests or 0
		return perSecond * (1 + share) / (1 + (st.travel or 0) / max(st.seconds, 1))
	elseif mode == "complete" then
		return st.quests + perSecond
	end
	return perSecond
end

-- one line for the card: "about 2.5 levels, 14 quests, 3 chains, 4 min travel"
local function reasonLine(st, short)
	local travelText = minutes(st.travel or 0) .. " travel" .. (st.estimated and " (estimated)" or "")
	local levels = st.levelsTo - st.levelsFrom
	if short then
		return string.format("only %s before you outgrow it, about %.1f levels, %s", plural(st.quests, "quest", "quests"), levels, travelText)
	end
	return string.format("about %.1f levels, %s, %s, %s", levels, plural(st.quests, "quest", "quests"),
		plural(chainCount(st), "chain", "chains"), travelText)
end

function Plan.areas(ctx)
	local mode = ctx.mode or "fast"
	local keys, seen = {}, {}
	if mode == "zones" and ctx.chosen then
		for _, key in ipairs(ctx.chosen) do keys[#keys + 1] = key end
	else
		for _, r in ipairs(ctx.records or {}) do
			if r.area ~= nil and not seen[r.area] then seen[r.area] = true; keys[#keys + 1] = r.area end
		end
	end
	local full, short = {}, {}
	for order, key in ipairs(keys) do
		local st = newState(ctx)
		local from = fractionalLevel(st)
		if stay(ctx, st, key, mode) > 0 then
			st.levelsFrom, st.levelsTo = from, fractionalLevel(st)
			local isShort = st.quests < SHORT
			local area = {
				key = key, title = areaTitle(ctx, key),
				levelsFrom = st.levelsFrom, levelsTo = st.levelsTo,
				seconds = st.seconds, quests = st.quests, chains = chainCount(st),
				travel = st.travel or 0, estimated = st.estimated,
				reason = reasonLine(st, isShort),
				score = score(st, mode), order = order,
			}
			if isShort then area.tag = "Short stay" end
			local list = isShort and short or full
			list[#list + 1] = area
		end
	end
	-- the player's own order in "zones"; else the best first, ties in data order
	local function better(a, b)
		if mode == "zones" or a.score == b.score then return a.order < b.order end
		return a.score > b.score
	end
	table.sort(full, better)
	table.sort(short, better)
	if full[1] then full[1].tag = "Recommended" end
	-- a short stay only fills the cards that full areas leave
	local out = {}
	for _, a in ipairs(full) do if #out < CARDS then out[#out + 1] = a end end
	for _, a in ipairs(short) do if #out < CARDS then out[#out + 1] = a end end
	return out
end

--------------------------------------------------------------------------------
-- The session plan
--------------------------------------------------------------------------------

-- the session to the next break point in the area (nil: the best area, or,
-- when none has quests, wherever grinding is best)
function Plan.session(ctx, areaKey, mode)
	mode = mode or ctx.mode or "fast"
	if areaKey == nil then
		local best = Plan.areas(ctx)[1]
		areaKey = best and best.key
	end
	local st = plan(ctx, areaKey, mode)
	return {
		area = areaKey,
		steps = st.steps,
		breakReason = st.breakReason,
		seconds = st.seconds,
		levels = st.levelsTo - st.levelsFrom,
		level = st.level,
		estimated = st.estimated,
	}
end

Plan.WALK, Plan.CROSSING, Plan.CAMP = WALK, CROSSING, CAMP

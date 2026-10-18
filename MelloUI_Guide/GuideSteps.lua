--------------------------------------------------------------------------------
-- MelloUI - Guide: steps, saved progress, Route
--
-- The session plan (GuidePlan.lua) led one step at a time. The planner's
-- ctx is made here from the game (level, XP, rested XP, the quests done and
-- in the log, where the character stands) and the guide's records
-- (GuideData.lua), less the other side's territory (Data.foreignAreas) and
-- the class quests' chains, which are class steps of their own. Around the
-- planner's steps go the class help's (GuideClass.lua): a "train" step when
-- new spells can be learned, a "class" step when a class quest opens.
--
--   Steps.Login(M)          at login: the saved plan picked up, else a new one
--   Steps.Check(M)          the current step against the game: finished ones
--                           passed, a stale plan planned again, the step led to
--   Steps.Replan(M, reason) a new session in the chosen area from where the
--                           character is now
--   Steps.Choose(M, key)    the session in an area (a choice card's pick)
--   Steps.Arrived(M, d)     Route's "arrived": a travel or train step reached
--   Steps.Allows(M, id, kind)  Quest Auto's filter: the plan's quests only
--
-- What finishes each step, asked of the game (never of the plan):
--   take    every quest of it in the log or turned in
--   do      every quest of it ready to turn in, or turned in
--   turnin  every quest of it turned in
--   travel  Route's arrival at its place, or the character within ARRIVE
--           yards of it
--   train   Route's arrival at the trainer, the trainer's window closed
--           there (TRAINER_CLOSED), or the character within ARRIVE yards
--   grind   the level it grinds to reached
--   class   every quest of the chain turned in; meanwhile its place and
--           label follow the chain's open quest (its giver to take it, its
--           objective to do it, its turn-in once ready)
-- A plan is stale, and planned again, when a quest of a step still to come
-- was turned in already (out of the plan's order), when a quest a "do" or
-- "turnin" step needs in the log left it unfinished (abandoned) and no step
-- before it takes it again, when a quest the plan does not hold is turned in,
-- and at every level up (a level opens quests, spells and class quests). So
-- no step ever asks for a quest that is done or gone.
-- The session's end is a break point: the choice cards ("guide" "choice"),
-- or the one area offered, chosen at once. So is an area used up -- its
-- session would hold no quest or open with a grind step: a grind step is
-- led only when no area at all has quests for the character. At login with
-- no plan of its own the area the character stands in is chosen without a
-- choice when it is offered and not a short stay (a new character in
-- Northshire carries on).
--
-- Saved per character: MelloUIGuideChar = { version = 1, area, mode, plan =
-- the session (Plan.session's, with the steps as led here), index = the
-- current step, at = time() of the save, trained = the level last trained
-- at }, written at every step. (trained is beside the plan's five fields:
-- without it a train step would come back at every replan; a character new
-- to the guide counts as trained at its level.) Another version is dropped and planned anew;
-- a saved plan whose step no longer holds is planned again.
--
-- Travel costs: Route's CostBetween answers later than the planner asks
-- (it searches its graph in the frames after), so the planner's ctx.cost
-- answers from a cache of Route's answers. A pair not known yet is asked of
-- Route (at most ASKS a plan) and answers nil now: the planner's own
-- straight-line estimate. So the first plan after login is mostly estimated;
-- each plan after it uses the real costs Route has given since.
--------------------------------------------------------------------------------

local _, ns = ...

local Steps = {}
ns.Steps = Steps

local floor, sqrt, huge = math.floor, math.sqrt, math.huge

local VERSION = 1           -- MelloUIGuideChar's format; another one is dropped
local ARRIVE = 25           -- yards: a travel or train step's place reached (Route's own Arrived Within default)
local ASKS = 40             -- Route's costs asked at most this many times a plan
local GRID = 25             -- yards: the cost cache's places rounded to this
local AHEAD = 5             -- the records reach this many levels above the character's (the stay levels it)
local TRAINER_NEAR = 300    -- yards: a trainer this close to a coming stop is visited there (INFERRED: our call)
local FIGHT, GROUP = 3, 5   -- levels above the character: a quest that needs the fight tip, or a group (INFERRED)
local OWN_AREA = 1000       -- yards: with no zone from the Quest List, the nearest giver this close names the area

local PENDING, NONE = {}, {}   -- the cost cache's "asked" and "no way"

local function Plain(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return v
end

local function QL()
	return MelloUI and MelloUI.QuestList
end

local function Route()
	local R = MelloUI and MelloUI.Route
	return R and R.isEnabled and R or nil
end

local function Number(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, ...)
	v = ok and Plain(v) or nil
	return type(v) == "number" and v or nil
end

local function PlayerLevel()
	local level = Number(UnitLevel, "player")
	return level and level > 0 and level or 1
end

local function Side()
	local ok, side = pcall(UnitFactionGroup, "player")
	side = ok and Plain(side) or nil
	return (side == "Horde" or side == "Alliance") and side or "Alliance"
end

local function ClassFile()
	local ok, _, file = pcall(UnitClass, "player")
	return ok and Plain(file) or nil
end

local function IsDone(id)
	local q = QL()
	return q and q.IsCompleted(id) or false
end

local function OnQuest(id)
	local q = QL()
	return q and q.IsOnQuest(id) or false
end

local function Ready(id)
	local q = QL()
	return OnQuest(id) and q.IsReadyForTurnIn(id) or false
end

local function Dist(a, b)
	if not (a and b) or a.cont ~= b.cont then
		return huge
	end
	local dx, dy = a.x - b.x, a.y - b.y
	return sqrt(dx * dx + dy * dy)
end

-- where the character stands, in the data's frame: the world map id and world yards
local function PlayerPlace()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then
		return nil
	end
	local mapID = Number(C_Map.GetBestMapForUnit, "player")
	if not mapID then
		return nil
	end
	local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	if not ok or type(pos) ~= "table" then
		return nil
	end
	local okW, cont, w = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos)
	cont = okW and Plain(cont) or nil
	if type(cont) ~= "number" or type(w) ~= "table" then
		return nil
	end
	local x, y = Plain(w.x), Plain(w.y)
	if type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	return { cont = cont, x = x, y = y }
end

--------------------------------------------------------------------------------
-- Travel costs from Route, cached
--------------------------------------------------------------------------------

local costs = {}   -- [key] = seconds, PENDING or NONE
local asks = 0     -- Route asked this many times in this plan

local function CostKey(a, b)
	return a.cont .. ":" .. floor(a.x / GRID) .. ":" .. floor(a.y / GRID) .. ">"
		.. b.cont .. ":" .. floor(b.x / GRID) .. ":" .. floor(b.y / GRID)
end

local function Cost(a, b)
	local key = CostKey(a, b)
	local known = costs[key]
	if type(known) == "number" then
		return known, false
	end
	if known ~= nil then
		return nil   -- (asked, or no way: the planner's estimate)
	end
	local R = Route()
	if not (R and R.CostBetween) or asks >= ASKS then
		return nil
	end
	asks = asks + 1
	costs[key] = PENDING
	local now
	local ok = pcall(R.CostBetween, R, { cont = a.cont, x = a.x, y = a.y }, { cont = b.cont, x = b.x, y = b.y },
		function(seconds)
			costs[key] = type(seconds) == "number" and seconds or NONE
			now = costs[key]
		end)
	if not ok then
		costs[key] = NONE
	end
	if type(now) == "number" then
		return now, false   -- (answered at once: a place Route had priced)
	end
	return nil
end

--------------------------------------------------------------------------------
-- The planner's ctx
--------------------------------------------------------------------------------

local function ClassOf(classFile)
	return classFile and ns.Class and ns.Class[classFile] or nil
end

-- the class quests' IDs, which only class steps lead to
local function ClassQuestIDs(class)
	local ids = {}
	for _, key in ipairs(class and class.pets or {}) do
		for _, entry in ipairs(class.classQuests[key]) do
			for _, id in ipairs(type(entry) == "table" and entry or { entry }) do
				ids[id] = true
			end
		end
	end
	return ids
end

local function Context(M)
	local level, side, classFile = PlayerLevel(), Side(), ClassFile()
	local list = ns.Data.records(side, classFile, 1, level + AHEAD, level)
	local byID = {}
	for _, r in ipairs(list) do
		byID[r.id] = r
	end
	M.records = byID
	local skip = ClassQuestIDs(ClassOf(classFile))
	local foreign = ns.Data.foreignAreas(side)
	local done, log = ns.Data.state()
	-- other races' starting areas and capitals out (Data.otherStarts); here: the area the character stands in
	local q = MelloUI.QuestList
	-- (asked through pcall: the Quest List answers only once its index is built, i.e. while its module is on)
	local okHere, here = false, nil
	if q and q.CurrentAreaID then
		okHere, here = pcall(q.CurrentAreaID)
	end
	here = okHere and here or nil
	local others = ns.Data.otherStarts(side, done, here)
	local records = {}
	for _, r in ipairs(list) do
		if not skip[r.id] and not (r.area and (foreign[r.area] or others[r.area])) then
			records[#records + 1] = r
		end
	end
	asks = 0
	return {
		level = level,
		xp = Number(UnitXP, "player") or 0,
		xpMax = Number(UnitXPMax, "player"),
		rested = Number(GetXPExhaustion) or 0,
		side = side,
		classFile = classFile,
		done = done,
		log = log,
		pos = PlayerPlace(),
		records = records,
		cost = Cost,
		areaTitles = ns.Data.areaTitles(),
		mode = M.db and M.db.mode or "fast",
	}
end
Steps.Context = Context   -- (the choice window's Change route: the areas from where the character is now)

--------------------------------------------------------------------------------
-- Class help: class steps, train steps, fight tips
--------------------------------------------------------------------------------

-- the chain's quest open now: done ones passed; of a list of ways in, the one
-- in the log, else the one whose giver is nearest. nil: the whole chain is
-- done; false: its next quest is none the character can take now (no record)
local function ChainOpen(M, chain, from)
	for _, entry in ipairs(chain) do
		local list = type(entry) == "table" and entry or { entry }
		local done = false
		for _, id in ipairs(list) do
			if IsDone(id) then
				done = true
			end
		end
		if not done then
			for _, id in ipairs(list) do
				if OnQuest(id) then
					return id
				end
			end
			local best, bestD
			for _, id in ipairs(list) do
				local r = M.records and M.records[id]
				if r and r.giver then
					local d = Dist(r.giver, from)
					if not best or d < bestD then
						best, bestD = id, d
					end
				end
			end
			return best or false
		end
	end
	return nil
end

local function ChainIDs(chain)
	local ids = {}
	for _, entry in ipairs(chain) do
		for _, id in ipairs(type(entry) == "table" and entry or { entry }) do
			ids[#ids + 1] = id
		end
	end
	return ids
end

-- a class step's place and label from its chain's open quest; false when the
-- chain is done or cannot go on now
local function DressClass(M, step)
	local class = ClassOf(ClassFile())
	local chain = class and class.classQuests[step.pet]
	if not chain then
		return false
	end
	local id = ChainOpen(M, chain, PlayerPlace())
	local r = id and M.records and M.records[id]
	if not r then
		return false
	end
	local title = r.title or ("quest " .. id)
	local place, verb
	if not OnQuest(id) then
		place, verb = r.giver or (r.objectives and r.objectives[1]), "take " .. title
	elseif Ready(id) then
		place, verb = r.turnIn or r.giver, "turn in " .. title
	else
		place, verb = (r.objectives and r.objectives[1]) or r.turnIn or r.giver, "do " .. title
	end
	if not place then
		return false
	end
	step.quest, step.place = id, place
	step.label = "Warlock, " .. (chain.title or step.pet) .. ": " .. verb
	return true
end

local function ClassStep(M, key)
	local step = { kind = "class", pet = key, questIDs = {}, seconds = 0 }
	local class = ClassOf(ClassFile())
	step.questIDs = ChainIDs(class.classQuests[key])
	return DressClass(M, step) and step or nil
end

-- the class quest open at this level, the first in the class's order
local function OpenPet(M, class, level)
	for _, key in ipairs(class and class.pets or {}) do
		local chain = class.classQuests[key]
		if chain.level <= level and type(ChainOpen(M, chain, PlayerPlace())) == "number" then
			return key
		end
	end
	return nil
end

-- the class's trainers of the character's side: { name, place }
local function Trainers(class, side)
	local q = QL()
	local data = q and q.Data()
	local out = {}
	local own = side == "Horde" and 2 or 1
	for _, s in ipairs(type(data) == "table" and data.services or {}) do
		if s[1] == "trainer" and s[3] == class.trainer and (s[4] == own or s[4] == 3)
			and type(s[5]) == "number" and s[5] >= 0 then
			out[#out + 1] = { name = s[2], place = { cont = s[5], x = s[6], y = s[7] } }
		end
	end
	return out
end

local function NearestTrainer(list, place)
	local best, bestD
	for _, t in ipairs(list) do
		local d = Dist(t.place, place)
		if not bestD or d < bestD then
			best, bestD = t, d
		end
	end
	return best, bestD or huge
end

-- the highest trainer level reached and not trained at yet
local function TrainDue(M, class, level)
	local due
	for _, l in ipairs(class and class.trainerLevels or {}) do
		if l <= level and l > (M.trained or level) then
			due = l
		end
	end
	return due
end

-- the train step slotted in: right after the first coming stop a trainer
-- stands within TRAINER_NEAR yards of, else at the session's end (its break
-- point); never later. INFERRED: our call of when a trip to town pays.
local function SlotTrain(M, steps, class, side, level)
	local due = TrainDue(M, class, level)
	if not due then
		return
	end
	local list = Trainers(class, side)
	if #list == 0 then
		return
	end
	local at, trainer
	for j, s in ipairs(steps) do
		local t, d = NearestTrainer(list, s.place)
		if t and d <= TRAINER_NEAR then
			at, trainer = j + 1, t
			break
		end
	end
	if not at then
		local last = steps[#steps]
		trainer = NearestTrainer(list, last and last.place or PlayerPlace())
		at = #steps + 1
	end
	if not trainer then
		return
	end
	table.insert(steps, at, { kind = "train", questIDs = {}, place = trainer.place, trainer = trainer.name,
		level = due, seconds = 0, label = "Train at " .. trainer.name .. ": new spells at level " .. due })
end

-- a hard quest's tip on its take and do steps: the class's fight plan 3
-- levels above the character, a group 5 above or for an elite (INFERRED: no
-- data names a quest's mobs, so the quest's level stands for theirs)
local function Tip(M, step, class, level)
	if step.kind ~= "take" and step.kind ~= "do" then
		return
	end
	local worst
	for _, id in ipairs(step.questIDs or {}) do
		local r = M.records and M.records[id]
		if r then
			local over = (r.level or level) - level
			local kind = (r.elite or over >= GROUP) and "group" or (over >= FIGHT and "fight") or nil
			if kind == "group" or (kind and not worst) then
				worst = kind
			end
		end
	end
	if worst then
		local tips = class and class.tips
		step.tip = (tips and tips[worst]) or ns.Class.GROUP
	end
end

--------------------------------------------------------------------------------
-- The session
--------------------------------------------------------------------------------

local function Current(M)
	local s = M.session
	return s and s.steps[M.index] or nil
end
Steps.Current = Current

-- the planner's steps, with the train and class steps around them: a class
-- step right after the current step, or first when it is being led already
-- or the session opens with a trip to its area
local function Dress(M, session, ctx, previous)
	local class = ClassOf(ctx.classFile)
	local steps = session.steps
	for _, s in ipairs(steps) do
		Tip(M, s, class, ctx.level)
	end
	if class then
		SlotTrain(M, steps, class, ctx.side, ctx.level)
		local key = OpenPet(M, class, ctx.level)
		local step = key and ClassStep(M, key)
		if step then
			-- (before a session's opening trip, our call beside the plan's
			-- "right after the current step": not there and straight back)
			local first = (previous and previous.kind == "class" and previous.pet == key)
				or #steps == 0 or steps[1].kind == "travel"
			table.insert(steps, first and 1 or 2, step)
		end
	end
	session.area = session.area or M.area
	return session
end

local function Save(M)
	M.savedIndex = M.index
	MelloUIGuideChar = {
		version = VERSION,
		area = M.area,
		mode = M.db and M.db.mode,
		plan = M.session,
		index = M.index,
		at = time and time() or nil,
		trained = M.trained,
	}
end

local function SyncFilter(M)
	local QA = MelloUI and MelloUI.QuestAuto
	if not (QA and QA.SetFilter) then
		return
	end
	if M.isEnabled and M.db and M.db.autoQuests and M.session then
		QA:SetFilter(M.filter)
	else
		-- (no plan led -- a choice open, the module off: no filter, Quest
		-- Auto as without the guide; our call beside the plan's rule, so a
		-- choice on screen never stops Auto Accept)
		QA:SetFilter(nil)
	end
end
Steps.SyncFilter = SyncFilter

local function Done(M, step)
	local kind = step.kind
	if kind == "take" then
		for _, id in ipairs(step.questIDs) do
			if not (OnQuest(id) or IsDone(id)) then return false end
		end
		return true
	elseif kind == "do" then
		for _, id in ipairs(step.questIDs) do
			if not (Ready(id) or IsDone(id)) then return false end
		end
		return true
	elseif kind == "turnin" then
		for _, id in ipairs(step.questIDs) do
			if not IsDone(id) then return false end
		end
		return true
	elseif kind == "travel" or kind == "train" then
		return step.arrived == true or Dist(PlayerPlace(), step.place) <= ARRIVE
	elseif kind == "grind" then
		step.target = step.target or PlayerLevel() + 1
		return PlayerLevel() >= step.target
	elseif kind == "class" then
		return not DressClass(M, step)
	end
	return true   -- (a kind this version does not know)
end

local function Finish(M, step)
	if step.kind == "train" then
		M.trained = math.max(M.trained or 0, step.level or PlayerLevel())
	end
end

-- why the steps still to come do not hold, or nil
local function Stale(M)
	local steps, at = M.session.steps, M.index
	local willTake = {}
	for j = at, #steps do
		local s = steps[j]
		local kind = s.kind
		if kind == "take" or kind == "do" or kind == "turnin" then
			for _, id in ipairs(s.questIDs) do
				local done = IsDone(id)
				if done and not (j == at and kind == "turnin") then
					return "turned in early"
				end
				if kind == "take" then
					willTake[id] = true
				elseif not done and not OnQuest(id) and not willTake[id] then
					return "abandoned"
				end
			end
		end
	end
	return nil
end

local function HoldsQuest(M, id)
	for _, s in ipairs(M.session and M.session.steps or {}) do
		for _, q in ipairs(s.questIDs or {}) do
			if q == id then return true end
		end
	end
	return false
end
Steps.HoldsQuest = HoldsQuest

-- the planner's session (before the class help goes round it) in an area
-- the character has used up: no quest of it, or it opens with a grind step
-- (no quest of the area fits now; the planner grinds only first)
local function UsedUp(session)
	local first = session.steps[1]
	if not first or first.kind == "grind" then
		return true
	end
	for _, s in ipairs(session.steps) do
		if s.kind == "take" or s.kind == "do" or s.kind == "turnin" then
			return false
		end
	end
	return true
end

-- the current step to Route and the bus, once per step and place
local function Lead(M)
	local s = Current(M)
	if not s or not s.place then
		return
	end
	local key = M.index .. ":" .. s.kind .. ":" .. s.place.cont .. ":" .. floor(s.place.x) .. ":" .. floor(s.place.y)
		.. ":" .. tostring(s.label)
	if M.led == key then
		return
	end
	M.led = key
	local R = Route()
	M.routed = false
	if R and R.SetDestinationTo then
		-- (Route's world candidate: { cont, wx, wy }, as the client tables give them;
		-- false where Route cannot place the point: the step is still the
		-- current one, its label says where)
		local ok, placed = pcall(R.SetDestinationTo, R, { cont = s.place.cont, wx = s.place.x, wy = s.place.y }, s.label, true)
		M.routed = ok and placed == true
	end
	MelloUI:Fire("guide", "step", s, M.index)
end

-- passes the finished steps; true when one is left to lead
local function Advance(M)
	local steps = M.session.steps
	while M.index <= #steps and Done(M, steps[M.index]) do
		Finish(M, steps[M.index])
		M.index = M.index + 1
	end
	return M.index <= #steps
end

local Offer   -- (forward)

-- the guide's own destination let go at a break point (the cards wait: no
-- step leads, so Route's row must not keep pointing at the last one); a
-- destination the player set is not the guide's and stays
local function LetGo(M)
	local R = Route()
	if M.routed then
		-- (the guide's step set the map pin, SetDestinationTo's `pin`: Route reads
		-- the pin back every second, so the pin goes too, then the destination)
		if C_Map and C_Map.ClearUserWaypoint then
			pcall(C_Map.ClearUserWaypoint)
		end
		if R and R.Clear then
			pcall(R.Clear, R)
		end
	end
	M.routed, M.led = false, nil
end

local function Start(M, session)
	M.session, M.index, M.choice, M.led = session, 1, nil, nil
	if not Advance(M) then
		return false
	end
	Save(M)
	SyncFilter(M)
	MelloUI:Fire("guide", "plan", session)
	Lead(M)
	return true
end

function Steps.Choose(M, key, ctx)
	ctx = ctx or Context(M)
	local previous = Current(M)
	local planned = ns.Plan.session(ctx, key, ctx.mode)
	if key ~= nil and UsedUp(planned) then
		-- (Denis, 2026-10-18: a used-up area offers the choice) no grind
		-- step there while another area has quests: a break point
		local areas = ns.Plan.areas(ctx)
		if #areas > 0 then
			return Offer(M, areas, ctx)
		end
	end
	M.area = key
	local session = Dress(M, planned, ctx, previous)
	M.area = session.area
	if not Start(M, session) then
		return Offer(M, ns.Plan.areas(ctx), ctx, true)
	end
end

-- a break point: the cards, or the one area there is chosen at once; none
-- at all: the planner's best (grinding only then, when no area has quests)
Offer = function(M, areas, ctx, ended)
	if #areas == 0 then
		if ended then
			-- (nothing to plan at all: no area, no grind spot; said on the bus)
			M.session, M.index, M.choice = nil, 1, {}
			LetGo(M)
			Save(M)
			SyncFilter(M)
			MelloUI:Fire("guide", "choice", M.choice)
			return
		end
		return Steps.Choose(M, nil, ctx)
	elseif #areas == 1 and not ended then
		return Steps.Choose(M, areas[1].key, ctx)
	end
	M.session, M.index, M.choice = nil, 1, areas
	LetGo(M)
	Save(M)
	SyncFilter(M)
	MelloUI:Fire("guide", "choice", areas)
end

function Steps.Replan(M, reason)
	if M.choice then
		return   -- (the cards are open: the player picks first)
	end
	local ctx = Context(M)
	if M.session == nil and M.area == nil then
		return Steps.First(M, ctx)
	end
	local previous = Current(M)
	local planned = ns.Plan.session(ctx, M.area, ctx.mode)
	M.reason = reason
	if UsedUp(planned) then
		-- the area has nothing left for the character now (a class step
		-- alone keeps no one there): a break point
		local areas = ns.Plan.areas(ctx)
		if #areas > 0 then
			return Offer(M, areas, ctx)
		end
	end
	local session = Dress(M, planned, ctx, previous)
	if not Start(M, session) then
		return Offer(M, ns.Plan.areas(ctx), ctx, true)
	end
end

-- the area the character stands in: the Quest List's zone, else the area of
-- the nearest giver within OWN_AREA yards
local function OwnArea(ctx)
	local q = QL()
	if q and q.CurrentAreaID then
		local ok, area = pcall(q.CurrentAreaID)
		if ok and area then
			return area
		end
	end
	local best, bestD
	for _, r in ipairs(ctx.records) do
		local d = Dist(r.giver, ctx.pos)
		if r.area and d <= OWN_AREA and (not bestD or d < bestD) then
			best, bestD = r.area, d
		end
	end
	return best
end

-- the first plan of a character with none: its own area when that is offered
-- and no short stay, else the cards
function Steps.First(M, ctx)
	ctx = ctx or Context(M)
	local areas = ns.Plan.areas(ctx)
	local own = OwnArea(ctx)
	for _, a in ipairs(areas) do
		if a.key == own and a.tag ~= "Short stay" then
			return Steps.Choose(M, own, ctx)
		end
	end
	return Offer(M, areas, ctx)
end

-- a saved plan that can be led: a table of steps each with a kind and a place
local function Usable(saved)
	local plan = saved.plan
	if type(plan) ~= "table" or type(plan.steps) ~= "table" or type(saved.index) ~= "number" then
		return false
	end
	for _, s in ipairs(plan.steps) do
		if type(s) ~= "table" or type(s.kind) ~= "string" or type(s.questIDs) ~= "table"
			or (s.place ~= nil and type(s.place) ~= "table") then
			return false
		end
	end
	return saved.index >= 1 and saved.index <= #plan.steps
end

function Steps.Login(M)
	local saved = rawget(_G, "MelloUIGuideChar")
	if type(saved) ~= "table" or saved.version ~= VERSION then
		saved = nil   -- (none, or an older format: dropped)
	end
	M.trained = saved and type(saved.trained) == "number" and saved.trained or PlayerLevel()
	M.session, M.index, M.choice, M.led, M.area = nil, 1, nil, nil, nil
	if saved and Usable(saved) then
		M.session, M.index, M.area = saved.plan, saved.index, saved.area
		-- the steps' records (class steps and tips read them)
		Context(M)
		local s = Current(M)
		if s and s.kind == "grind" then
			-- (a grind step saved: planned again, the cards when the area is used up)
			return Steps.Replan(M, "resume: grinding")
		end
		return Steps.Check(M, "resume")
	end
	return Steps.First(M)
end

function Steps.Check(M, reason)
	if not M.session then
		return
	end
	if not Advance(M) then
		-- the session's end: a break point
		local ctx = Context(M)
		return Offer(M, ns.Plan.areas(ctx), ctx)
	end
	local why = Stale(M)
	if why then
		return Steps.Replan(M, (reason and (reason .. ": ") or "") .. why)
	end
	if M.index ~= M.savedIndex then
		M.savedIndex = M.index
		Save(M)
	end
	Lead(M)
end

function Steps.Arrived(M, d)
	local s = Current(M)
	if s and (s.kind == "travel" or s.kind == "train") and d and d.label == s.label then
		s.arrived = true
	end
end

function Steps.Trained(M)
	local s = Current(M)
	if s and s.kind == "train" and Dist(PlayerPlace(), s.place) <= 100 then
		s.arrived = true
	end
end

-- Quest Auto's say: a quest taken only when a step still to come takes it
-- (or a class step's open quest), handed in only when the plan holds it
function Steps.Allows(M, id, kind)
	local session = M.session
	if not session or type(id) ~= "number" then
		return false
	end
	if kind == "turnin" then
		return HoldsQuest(M, id)
	end
	for j = M.index, #session.steps do
		local s = session.steps[j]
		if s.kind == "take" then
			for _, q in ipairs(s.questIDs) do
				if q == id then return true end
			end
		elseif s.kind == "class" and s.quest == id then
			return true
		end
	end
	return false
end

Steps.VERSION, Steps.PlayerPlace = VERSION, PlayerPlace

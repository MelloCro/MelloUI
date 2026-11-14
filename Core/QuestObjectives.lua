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
		return nil   -- (no Questie: no quests anywhere, the learned places too)
	end
	local data, learned = DataOf(questID), LearnedOf(questID)
	if not learned then
		return data
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
local LEARN = { APART = 30, MAX = 24, WAIT = 0.4, KIND = { monster = 1, object = 2, item = 3 } }
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
			local data = learnNow and DataOf(questID) or nil
			local itemLine = data and QO.ItemLine(data, lines) or nil
			for _, t in ipairs(lines) do
				local i, have = t[3], t[7]
				if type(have) == "number" then
					local before = was[i]
					was[i] = have
					if learnNow and before and have > before then
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

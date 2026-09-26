--------------------------------------------------------------------------------
-- MelloUI - Quest List: quest tooltips
--
-- Lines the Quest List adds to the game's own tooltips (0.14.0, the levelling
-- features; user, 2026-09-26: "Turn in here" when a quest is ready, a muted
-- "Quest ends here" while it is in progress):
--   an item one of your quests asks for   Quest: Red Linen Goods (4/6)
--   an NPC that takes one of them back    Turn in here: The People's Militia
--                                         Quest ends here: ...   (muted)
-- Read from your own quest log (the objectives) and the list's data (who
-- takes each quest back: MelloUI_QuestListData, through QL.RowByID), for the
-- quests in the log only (25 or so). The index is made again on the first
-- tooltip that needs it after the log changed -- QuestList.lua counts the
-- QUEST_LOG_UPDATEs in QL.logChanges -- so nothing runs while nothing is
-- hovered: no frame, no event and no timer of its own. A unit frame's tooltip
-- is filled again every 0.2 s while hovered: the last unit's lines are kept
-- and handed out again, no string or table made per fill.
--
-- The tooltips are the game's, filled again on every show: a line takes the
-- palette in use then (selectedTrim for what is open or ready, text for a
-- finished objective and the count line, mutedText only for the user's
-- muted "Quest ends here"), and on the parchment the ink (TooltipPanel)
-- inks it with the game's own lines. Only GameTooltip (and
-- ItemRefTooltip for items): the comparison tooltips get nothing. Options: the
-- Quest List's Tooltips rows (tipQuestItems, tipTurnIn).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("QuestListTips")
local QL = ns.QuestList
local M = QL.M
local Safe = MelloUI.Safe
local IsSecret, Plain, Text, Number = Safe.IsSecret, Safe.Value, Safe.Text, Safe.Number

-- the game's own quest lines in a tooltip's data: an item it already shows
-- a quest for gets no line of ours (it would say it twice)
local LINE_QUEST_OBJECTIVE, LINE_QUEST_TITLE = 8, 17
do
	local types = type(Enum) == "table" and Enum.TooltipDataLineType
	if type(types) == "table" then
		if type(types.QuestObjective) == "number" then
			LINE_QUEST_OBJECTIVE = types.QuestObjective
		end
		if type(types.QuestTitle) == "number" then
			LINE_QUEST_TITLE = types.QuestTitle
		end
	end
end

-- an NPC that takes more of your quests back than this: the rest on one line
local MAX_TURN_INS = 5
-- item ids looked up since the log last changed, kept (their answer, or
-- false) up to this many, then let go
local ITEM_CACHE_MAX = 200

local Tips = {
	logIDs = {},          -- the log's quest ids, as QL.LogQuestIDs gave them (and those a folded header hides)
	seen = {},            -- [questID] = true: met in the log and still in it
	walkedAt = -1,        -- QL.logChanges at the last walk
	turnsAt = -1,         -- ... when the turn-ins were indexed
	itemsAt = -1,         -- ... when the items were indexed
	byNPC = {},           -- [npcID] = { turn-in, ... }  turn-in: { text, ready }
	byName = {},          -- [name] = { turn-in, ... }   the data's turn-ins with a name but no NPC id
	items = {},           -- [item name] = { need, ... } need: { text, done }
	itemsLower = {},      -- the same, by the lower-cased name
	itemCache = {},       -- [itemID] = the list for it, or false
	itemCached = 0,
	-- the last unit shown: its GUID, the index it was read from and its
	-- lists (by NPC id, by name) and the "and N more" line
	lastGUID = nil, lastAt = -1, lastA = nil, lastB = nil, lastMore = nil,
	builds = 0,           -- indexes made (the tests read it)
}
QL.Tips = Tips

--------------------------------------------------------------------------------
-- The index
--------------------------------------------------------------------------------

-- The quests in the log. A folded header hides its quests from the walk: a
-- quest met in an earlier walk stays while the game still has it in the log.
local function Walk()
	if Tips.walkedAt == QL.logChanges then
		return
	end
	Tips.walkedAt = QL.logChanges
	local ids, seen = Tips.logIDs, Tips.seen
	local whole = QL.LogQuestIDs(ids)
	for id in pairs(seen) do
		seen[id] = false
	end
	for i = 1, #ids do
		seen[ids[i]] = true
	end
	for id, inWalk in pairs(seen) do
		if not inWalk then
			if not whole and QL.IsOnQuest(id) then
				ids[#ids + 1] = id
				seen[id] = true
			else
				seen[id] = nil
			end
		end
	end
end

-- the quest's name: the game's (its language), else the data's
local function TitleOf(questID, row)
	local get = C_QuestLog and C_QuestLog.GetTitleForQuestID
	if get then
		local ok, title = pcall(get, questID)
		title = ok and Text(title) or nil
		if title and title ~= "" then
			return title
		end
	end
	return row and row[QL.F_TITLE] or ("Quest " .. questID)
end

local function Add(map, key, entry)
	local list = map[key]
	if not list then
		list = {}
		map[key] = list
	end
	list[#list + 1] = entry
end

-- Who takes the log's quests back: by NPC id, else by name
local function IndexTurnIns()
	Walk()
	if Tips.turnsAt == QL.logChanges then
		return
	end
	Tips.turnsAt = QL.logChanges
	Tips.builds = Tips.builds + 1
	wipe(Tips.byNPC)
	wipe(Tips.byName)
	local rows = QL.RowByID()
	local ids = Tips.logIDs
	for i = 1, #ids do
		local id = ids[i]
		local row = rows[id]
		local name = row and row[QL.F_ENDER]
		if name and name ~= "" then
			local ready = QL.IsReadyForTurnIn(id)
			local entry = { (ready and "Turn in here: " or "Quest ends here: ") .. TitleOf(id, row), ready }
			local npc = row[QL.F_ENDERNPC]
			if npc and npc ~= 0 then
				Add(Tips.byNPC, npc, entry)
			else
				Add(Tips.byName, name, entry)
			end
		end
	end
end

-- An item objective's text as the item's name, and the counts it shows:
-- "Red Linen Bandana: 4/6" and "4/6 Red Linen Bandana" (both forms are met)
local function ItemOfObjective(text)
	local name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)%s*$")
	if not name then
		have, need, name = text:match("^(%d+)%s*/%s*(%d+)%s+(.-)%s*$")
	end
	if not name or name == "" then
		return text, nil, nil
	end
	return name, tonumber(have), tonumber(need)
end

-- The items the log's quests ask for: by name (and lower-cased)
local function IndexItems()
	Walk()
	if Tips.itemsAt == QL.logChanges then
		return
	end
	Tips.itemsAt = QL.logChanges
	Tips.builds = Tips.builds + 1
	wipe(Tips.items)
	wipe(Tips.itemsLower)
	wipe(Tips.itemCache)
	Tips.itemCached = 0
	local objectives = C_QuestLog and C_QuestLog.GetQuestObjectives
	if not objectives then
		return
	end
	local rows = QL.RowByID()
	local ids = Tips.logIDs
	for i = 1, #ids do
		local id = ids[i]
		local ok, list = pcall(objectives, id)
		if ok and type(list) == "table" then
			local title
			for _, o in ipairs(list) do
				local text = type(o) == "table" and Plain(o.type) == "item" and Text(o.text) or nil
				if text then
					local name, have, need = ItemOfObjective(text)
					have, need = Number(o.numFulfilled) or have, Number(o.numRequired) or need
					if name ~= "" and need and need > 0 and have then
						title = title or TitleOf(id, rows[id])
						local done = have >= need
						local entry = { string.format("Quest: %s (%d/%d)", title, done and need or have, need), done }
						Add(Tips.items, name, entry)
						Add(Tips.itemsLower, name:lower(), entry)
					end
				end
			end
		end
	end
end
MelloUI:Profile("QuestList", "quest tooltips: the items index", IndexItems)

--------------------------------------------------------------------------------
-- The lines
--------------------------------------------------------------------------------

-- a line in a palette colour, read as it is added (a palette switch shows
-- on the next tooltip)
local function AddLine(tip, text, role)
	local c = MelloUI.Palette[role]
	tip:AddLine(text, c[1], c[2], c[3])
end

-- Does the game's data already carry a quest's lines?
local function HasQuestLines(data)
	local lines = data.lines
	if type(lines) ~= "table" then
		return false
	end
	for i = 1, #lines do
		local line = lines[i]
		local kind = type(line) == "table" and Plain(line.type) or nil
		if kind == LINE_QUEST_OBJECTIVE or kind == LINE_QUEST_TITLE then
			return true
		end
	end
	return false
end

-- the first line's text of a tooltip's data (an item's or a unit's name)
local function FirstText(data)
	local lines = data.lines
	local first = type(lines) == "table" and lines[1]
	return type(first) == "table" and Text(first.leftText) or nil
end

-- The needs for an item id (or nil), and whether that answer can be kept:
-- an item the client has not loaded yet has no name from C_Item (its
-- tooltip reads "Retrieving item information" until the game fills it
-- again), so a miss then is asked again on that refill
local function NeedsOf(itemID, data)
	local name
	local byID = C_Item and C_Item.GetItemNameByID
	if byID then
		local ok, n = pcall(byID, itemID)
		name = ok and Text(n) or nil
	end
	local known = name ~= nil
	name = name or FirstText(data)
	if not name then
		return nil, known
	end
	return Tips.items[name] or Tips.itemsLower[name:lower()], known
end

local function OnItem(tip, data)
	if not (M.isEnabled and M.db.tipQuestItems) or (tip ~= GameTooltip and tip ~= _G.ItemRefTooltip) or type(data) ~= "table" then
		return
	end
	local itemID = Number(data.id)   -- (secret first, then a number)
	if not itemID or HasQuestLines(data) then
		return
	end
	IndexItems()
	local cache = Tips.itemCache
	local list = cache[itemID]
	if list == nil then
		local known = true
		if next(Tips.items) ~= nil then
			list, known = NeedsOf(itemID, data)
		end
		list = list or false
		if list or known then
			if Tips.itemCached >= ITEM_CACHE_MAX then
				wipe(cache)
				Tips.itemCached = 0
			end
			cache[itemID] = list
			Tips.itemCached = Tips.itemCached + 1
		end
	end
	if not list then
		return
	end
	-- an objective still open in gold; a finished one in the body text
	-- colour (small text: mutedText is for large or bold labels)
	for i = 1, #list do
		local entry = list[i]
		AddLine(tip, entry[1], entry[2] and "text" or "selectedTrim")
	end
end

-- The unit's turn-ins, read again only for another unit (or a new index)
local function ReadUnit(guid, data)
	Tips.lastGUID, Tips.lastAt, Tips.lastMore = guid, Tips.turnsAt, nil
	-- the NPC id: the sixth part of a creature's GUID (one match; a
	-- player's GUID has no such part)
	local npc = tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)") or "")
	Tips.lastA = npc and Tips.byNPC[npc] or nil
	local name = next(Tips.byName) ~= nil and FirstText(data) or nil
	Tips.lastB = name and Tips.byName[name] or nil
	local n = (Tips.lastA and #Tips.lastA or 0) + (Tips.lastB and #Tips.lastB or 0)
	if n > MAX_TURN_INS then
		Tips.lastMore = string.format("and %d more of your quests", n - MAX_TURN_INS)
	end
end

-- the ready ones first (pass 1), then those still in progress (pass 2),
-- MAX_TURN_INS lines in all; returns how many were added
local function AddTurnIns(tip, list, ready, added)
	if not list then
		return added
	end
	for i = 1, #list do
		local entry = list[i]
		if entry[2] == ready and added < MAX_TURN_INS then
			AddLine(tip, entry[1], ready and "selectedTrim" or "mutedText")
			added = added + 1
		end
	end
	return added
end

local function OnUnit(tip, data)
	if not (M.isEnabled and M.db.tipTurnIn) or tip ~= GameTooltip or type(data) ~= "table" then
		return
	end
	local guid = data.guid
	if IsSecret(guid) or type(guid) ~= "string" then
		return
	end
	IndexTurnIns()
	if guid ~= Tips.lastGUID or Tips.lastAt ~= Tips.turnsAt then
		ReadUnit(guid, data)
	end
	local a, b = Tips.lastA, Tips.lastB
	if not (a or b) then
		return
	end
	local added = AddTurnIns(tip, a, true, 0)
	added = AddTurnIns(tip, b, true, added)
	added = AddTurnIns(tip, a, false, added)
	AddTurnIns(tip, b, false, added)
	if Tips.lastMore then
		AddLine(tip, Tips.lastMore, "text")
	end
end

-- The two post-calls, once (QuestList's OnEnable; the settings and the
-- module's state are read in them, as a post-call cannot be taken back)
local installed = false
function QL.InstallTips()
	if installed then
		return
	end
	local processor = TooltipDataProcessor
	local kinds = type(Enum) == "table" and Enum.TooltipDataType
	if type(processor) ~= "table" or type(processor.AddTooltipPostCall) ~= "function" or type(kinds) ~= "table"
		or kinds.Item == nil or kinds.Unit == nil then
		return
	end
	installed = true
	processor.AddTooltipPostCall(kinds.Item, Perf.Shared("quest tooltips: items", OnItem))
	processor.AddTooltipPostCall(kinds.Unit, Perf.Shared("quest tooltips: turn-ins", OnUnit))
end

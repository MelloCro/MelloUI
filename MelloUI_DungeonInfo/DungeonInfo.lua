--------------------------------------------------------------------------------
-- MelloUI - Dungeon Info (1.2.0; docs/plans/dungeon-info.md; the user, 2026-10-22: "Button for dungeons and
-- raids on the Map, something like a Dungeon Journal ... check the bosses inside it and check which boss drops what,
-- an option to also track certain items, something like his Best In slot, and once that item dropps, the Loot Roll
-- Widget has a special effect ... 'Pick Up all the Quests', and then the route leads him in the most time efficient
-- way possible")
--
-- Every dungeon and raid (DungeonInfoData.lua, Tools/build_dungeoninfo.py: the client's bosses in their order, the classic
-- database's drops and chances), your own list of items -- a star on any drop, kept per character -- which the loot
-- roll row marks (Modules/Widgets.lua asks J.IsTracked), the drops of bosses the data does not know learned as they
-- fall in front of you (kept for the account), and a dungeon's quests (MelloUI's quest data) with a trip that picks
-- up the ones you can take in the fastest order (DungeonInfoTrip.lua, Route's). Its pages are the map's column's
-- (MelloUI_Map: the door button over the map, a click on a dungeon's door; DungeonInfoPanel.lua), mounted there as the
-- Quest List's is. Nothing at login: the data is read the first time it is asked for, the events listened to only
-- while the module is on.
--   local J = MelloUI.DungeonInfo
--   J.Get(key) -> the instance (any of its quest data keys) | J.ByMap(mapID) | J.List(kind) -> by level
--   J.IsTracked(itemID), J.SetTracked(itemID, on), J.Tracked() -> { itemID, ... }, J.TrackedIn(inst) -> n
--   J.Quests(inst) -> its quests { row, state }, state "take" (you can now), "log", "done", "later"
--   J.Open([key[, encounterID]]) -> the map, its column on that page (the list without a key)
--   J.ItemName(drop), J.ItemIcon(itemID), J.ItemKind(itemID), J.QualityColour(quality) -> r, g, b
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_DungeonInfo (Dungeon Info)")
local Safe = MelloUI.Safe
local Secret, Num, Text = Safe.IsSecret, Safe.Number, Safe.Text

local J = {}
MelloUI.DungeonInfo = J
ns.DungeonInfo = J

J.TEXT = {
	title = "Dungeon Info",
	mapOff = "Dungeon Info lives in MelloUI's map: switch the map on in /mello (Quests and travel > Map).",
	notFound = "No dungeon or raid called \"%s\".",
	usage = "/dungeoninfo [dungeon]: open Dungeon Info (on that dungeon's page). /dungeoninfo export: the drops you have seen, to send in.",
	learned = "Seen drop",
	trash = "Trash drops",
	exportTitle = "Dungeon Info: the drops you have seen",
	exportNone = "No drops seen yet: they are counted as bosses and other creatures fall in front of you in a dungeon or raid.",
	exportHelp = "Copy all of this (Ctrl+A, Ctrl+C) and post it in MelloUI's Discord or on its CurseForge page: what you saw goes into the next update, for everyone.",
}
local TEXT = J.TEXT

local M = MelloUI:RegisterModule("DungeonInfo", {
	title = "Dungeon Info",
	desc = "Every dungeon and raid on the map: its bosses in order and what each one drops, your own list of items to look out for (the loot roll marks them), and a trip that picks up a dungeon's quests in the fastest order.",
	icon = "Interface\\Icons\\INV_Misc_Book_09",
	flavour = "Every dungeon's bosses and their loot beside the map; star the items you want and a loot roll tells you when one drops.",
	group = "Quests and travel", navOrder = 4,
	role = "feature",
	installer = false,   -- (the Fresh start wizard's Features step is full, both columns at ten: it rides with the Map)
	enabledByDefault = true,
	defaults = {
		doorRow = false,   -- (the user's pick D: off by default, no clutter)
	},
	options = {
		{ type = "button", name = "Open Dungeon Info", text = "Open",
		  desc = "Open Dungeon Info beside MelloUI's map: the door button over the map, a click on a dungeon's door on the map, /dungeoninfo and the key you give it in the game's Key Bindings open it too.",
		  onClick = function() J.Open() end },
		{ type = "toggle", key = "doorRow", name = "At A Dungeon's Door",
		  desc = "When you walk up to a dungeon's door (or into it), a row in the widget column: its bosses, how many of your items drop there, and its page in Dungeon Info and its quests one click away." },
	},
})
J.M = M

--------------------------------------------------------------------------------
-- The data, read the first time it is asked for
--------------------------------------------------------------------------------

local S = { built = false, byKey = {}, byMap = {}, list = {}, kill = nil, version = 0 }
J.S = S

local function Build()
	if S.built then
		return
	end
	S.built = true
	local data = rawget(_G, "MelloUI_DungeonInfoData")
	local rows = type(data) == "table" and data.instances or {}
	for key, r in pairs(rows) do
		local inst = { key = key, map = r[1], kind = r[2], name = r[3], lo = r[4], hi = r[5], players = r[6],
			emblem = r[7], keys = r[8], bosses = {} }
		for i, b in ipairs(r[9]) do
			local boss = { id = b[1], name = b[2], index = i, drops = {}, inst = inst }
			-- (1.2.2) a drop's source: 0 the database, 1 DungeonMaster's list (no chance: -1); quality 0 not known yet
			local d = b[3]
			for j = 1, #d, 7 do
				boss.drops[#boss.drops + 1] = { item = d[j], chance = d[j + 1] >= 0 and d[j + 1] / 10 or nil,
					quality = d[j + 2], name = d[j + 3] ~= "" and d[j + 3] or nil, req = d[j + 4], starts = d[j + 5],
					src = d[j + 6] == 1 and "curated" or "data" }
			end
			inst.bosses[i] = boss
		end
		-- (1.2.2) the trash's drops (a page of their own, as a boss's: its id the instance's key, below zero, never an
		-- encounter's) and the loading screen of an instance with no LFG picture of its own
		local trash = { id = -key, name = TEXT.trash, trash = true, drops = {}, inst = inst }
		local t = type(r[10]) == "table" and r[10] or {}
		for j = 1, #t, 8 do
			trash.drops[#trash.drops + 1] = { item = t[j], chance = t[j + 1] >= 0 and t[j + 1] / 100 or nil,
				quality = t[j + 2], name = t[j + 3] ~= "" and t[j + 3] or nil, req = t[j + 4], starts = t[j + 5],
				mobs = t[j + 6], src = t[j + 7] == 1 and "curated" or "data" }
		end
		inst.trash, inst.pic, inst.picKind = trash, r[11] or 0, r[12] or 0
		-- (1.2.2) Everloot's drop rates, players' data (Data from Everloot, https://everloot.app, CC BY-SA 4.0): a
		-- boss's by his encounter, the trash's with its creatures; quality 0: the game's own, read in game
		local byId = {}
		for _, b in ipairs(inst.bosses) do
			byId[b.id] = b
		end
		local eb = type(r[13]) == "table" and r[13] or {}
		for j = 1, #eb, 6 do
			local b = byId[eb[j]]
			if b then
				b.ever = b.ever or {}
				b.ever[#b.ever + 1] = { item = eb[j + 1], chance = eb[j + 2] / 10, quality = eb[j + 3],
					name = eb[j + 4] ~= "" and eb[j + 4] or nil, req = eb[j + 5], starts = 0, src = "everloot" }
			end
		end
		local et = type(r[14]) == "table" and r[14] or {}
		for j = 1, #et, 6 do
			trash.ever = trash.ever or {}
			trash.ever[#trash.ever + 1] = { item = et[j], chance = et[j + 1] / 100, quality = et[j + 2],
				name = et[j + 3] ~= "" and et[j + 3] or nil, req = et[j + 4], starts = 0, mobs = et[j + 5], src = "everloot" }
		end
		for _, k in ipairs(inst.keys) do
			S.byKey[k] = inst
		end
		S.byKey[key] = inst
		S.byMap[inst.map] = inst
		S.list[#S.list + 1] = inst
	end
	-- (by level: the ones with no levels known last, then by name)
	table.sort(S.list, function(a, b)
		local la, lb = a.lo > 0 and a.lo or 999, b.lo > 0 and b.lo or 999
		if la ~= lb then
			return la < lb
		end
		return a.name < b.name
	end)
end

function J.Get(key)
	Build()
	return key and S.byKey[key] or nil
end

function J.ByMap(mapID)
	Build()
	return mapID and S.byMap[mapID] or nil
end

-- the instances of a kind (1 dungeons, 2 raids) by level; `out` reused
function J.List(kind, out)
	Build()
	out = out or {}
	for i = #out, 1, -1 do
		out[i] = nil
	end
	for _, inst in ipairs(S.list) do
		if inst.kind == kind then
			out[#out + 1] = inst
		end
	end
	return out
end

-- the instance by name (the slash command's): its own name or the start of it
function J.Find(text)
	Build()
	text = (text or ""):lower()
	if text == "" then
		return nil
	end
	for _, inst in ipairs(S.list) do
		local n = inst.name:lower()
		if n == text or n:gsub("^the ", "") == text then
			return inst
		end
	end
	for _, inst in ipairs(S.list) do
		if inst.name:lower():find(text, 1, true) then
			return inst
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Your list of items (per character) and the drops learned (for the account)
--------------------------------------------------------------------------------

local function Char()
	local c = rawget(_G, "MelloUIDungeonInfoChar")
	if type(c) ~= "table" then
		c = {}
		_G.MelloUIDungeonInfoChar = c
	end
	c.tracked = type(c.tracked) == "table" and c.tracked or {}
	return c
end

local function Account()
	local a = rawget(_G, "MelloUIDungeonInfoSaved")
	if type(a) ~= "table" then
		a = {}
		_G.MelloUIDungeonInfoSaved = a
	end
	a.learned = type(a.learned) == "table" and a.learned or {}
	-- (1.2.2) the drops seen, counted: boss[encounter] = { n = kills, i = { [item] = times }, q = { [item] = quality } },
	-- mob[npc] = { k = instance key, name, n = corpses looted, i, q }, roll[instance key] = { i, q } (a roll whose
	-- creature is not known), bossNpc[npc] = encounter
	local s = type(a.seen) == "table" and a.seen or {}
	a.seen = s
	for _, k in ipairs({ "boss", "mob", "roll", "bossNpc" }) do
		s[k] = type(s[k]) == "table" and s[k] or {}
	end
	return a
end

function J.IsTracked(itemID)
	itemID = Num(itemID)
	return itemID ~= nil and Char().tracked[itemID] == true
end

function J.SetTracked(itemID, on)
	itemID = Num(itemID)
	if not itemID then
		return
	end
	Char().tracked[itemID] = on and true or nil
	MelloUI:Fire("dungeonInfo:tracked", itemID, on and true or false)
end

function J.Tracked(out)
	out = out or {}
	for i = #out, 1, -1 do
		out[i] = nil
	end
	for id in pairs(Char().tracked) do
		out[#out + 1] = id
	end
	table.sort(out)
	return out
end

function J.TrackedCount()
	local n = 0
	for _ in pairs(Char().tracked) do
		n = n + 1
	end
	return n
end

-- how many of your items drop in the instance (its bosses and its trash)
function J.TrackedIn(inst)
	local t, n = Char().tracked, 0
	for _, boss in ipairs(inst.bosses) do
		for _, d in ipairs(J.Drops(boss)) do
			if t[d.item] then
				n = n + 1
			end
		end
	end
	for _, d in ipairs(J.Drops(inst.trash)) do
		if t[d.item] then
			n = n + 1
		end
	end
	return n
end

-- where an item drops: the instance and the boss (or its trash), and the drop
function J.WhereDrops(itemID)
	Build()
	for _, inst in ipairs(S.list) do
		for _, boss in ipairs(inst.bosses) do
			for _, d in ipairs(J.Drops(boss)) do
				if d.item == itemID then
					return inst, boss, d
				end
			end
		end
		for _, d in ipairs(J.Drops(inst.trash)) do
			if d.item == itemID then
				return inst, inst.trash, d
			end
		end
	end
	return nil
end

local NONE = {}
-- (1.2.0's) the drops seen from a boss before 1.2.2 counted them: { [itemID] = true }
function J.Learned(boss)
	local l = Account().learned[boss.id]
	return type(l) == "table" and l or NONE
end

--------------------------------------------------------------------------------
-- The items: the game's own name, picture and kind (the data's English name until the game knows the item)
--------------------------------------------------------------------------------

function J.ItemName(item, fallback)
	local name
	if C_Item and C_Item.GetItemNameByID then
		local ok, n = pcall(C_Item.GetItemNameByID, item)
		name = ok and Text(n) or nil
	end
	if not name and C_Item and C_Item.RequestLoadItemDataByID then
		pcall(C_Item.RequestLoadItemDataByID, item)
	end
	return name or fallback or ("item:" .. tostring(item))
end

function J.ItemIcon(item)
	local fn = (C_Item and C_Item.GetItemInfoInstant) or rawget(_G, "GetItemInfoInstant")
	if fn then
		local ok, _, _, _, _, icon = pcall(fn, item)
		if ok and icon and not Secret(icon) then
			return icon
		end
	end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- "One-Hand Sword", "Leather Chest", "Back": the slot's word and the kind (the game's own words)
function J.ItemKind(item)
	local fn = (C_Item and C_Item.GetItemInfoInstant) or rawget(_G, "GetItemInfoInstant")
	if not fn then
		return ""
	end
	local ok, _, itemType, subType, equipLoc, _, classID = pcall(fn, item)
	if not ok then
		return ""
	end
	local slot = type(equipLoc) == "string" and equipLoc ~= "" and rawget(_G, equipLoc) or nil
	slot = type(slot) == "string" and slot or nil
	subType = Text(subType)
	if classID == 2 then   -- (a weapon: its hand and its kind)
		return slot and subType and (slot .. " " .. subType) or slot or subType or ""
	elseif classID == 4 then   -- (armour: its kind before the slot; a cloak, a ring, a trinket: the slot)
		if subType and slot and equipLoc ~= "INVTYPE_CLOAK" and equipLoc ~= "INVTYPE_FINGER"
			and equipLoc ~= "INVTYPE_NECK" and equipLoc ~= "INVTYPE_TRINKET" and subType ~= "Miscellaneous" then
			return subType .. " " .. slot
		end
		return slot or subType or ""
	end
	return subType or Text(itemType) or ""
end

-- (1.2.2) an item's quality as the game knows it (a Forever item the data has none of: the server's), or nil
function J.ItemQuality(item)
	local fn = C_Item and C_Item.GetItemQualityByID
	if fn then
		local ok, q = pcall(fn, item)
		q = ok and Num(q) or nil
		if q then
			return q
		end
	end
	return nil
end

function J.QualityColour(quality)
	local fn = (C_Item and C_Item.GetItemQualityColor) or rawget(_G, "GetItemQualityColor")
	if fn then
		local ok, r, g, b = pcall(fn, quality or 1)
		if ok and Num(r) and Num(g) and Num(b) then
			return r, g, b
		end
	end
	return 1, 1, 1
end

-- an item link's id (a secret or no link: nil)
function J.LinkID(link)
	link = Text(link)
	return link and tonumber(link:match("item:(%d+)")) or nil
end

--------------------------------------------------------------------------------
-- The quests of an instance, from MelloUI's quest data: you can take it now, it is in your log, done, or later (its
-- earlier steps or your level first); your side's and class's only
--------------------------------------------------------------------------------

local F = { ID = 1, TITLE = 2, LEVEL = 3, REQ = 4, SIDE = 5, CLASS = 6, GIVER = 9, KIND = 12, DUNGEON = 15,
	PREV = 17, CONT = 18, WX = 19, WY = 20 }
J.F = F

local function Done(id)
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		local ok, v = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
		return ok and v == true
	end
	return false
end

local function InLog(id)
	if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
		local ok, v = pcall(C_QuestLog.GetLogIndexForQuestID, id)
		return ok and Num(v) ~= nil and v > 0
	end
	return false
end

-- (the quest trip) a quest taken: in your log, or done
function J.Taken(id)
	return InLog(id) or Done(id)
end

local function Side()
	local R = rawget(MelloUI, "Route")
	if type(R) == "table" and R.PlayerSide then
		return R.PlayerSide()
	end
	local f = UnitFactionGroup and UnitFactionGroup("player")
	return f == "Horde" and 2 or 1
end

local function ClassBit()
	local _, _, id = UnitClass("player")
	id = Num(id)
	return id and bit.lshift(1, id - 1) or 0
end

-- the quests of `inst`: { { row = row, state = "take" | "log" | "done" | "later" }, ... } by level; `out` reused
function J.Quests(inst, out)
	out = out or {}
	for i = #out, 1, -1 do
		out[i] = nil
	end
	local data = rawget(_G, "MelloUI_QuestListData")
	local quests = type(data) == "table" and data.quests
	if not (inst and quests) then
		return out
	end
	local want = {}
	for _, k in ipairs(inst.keys) do
		want[k] = true
	end
	local side, cbit, level = Side(), ClassBit(), Num(UnitLevel("player")) or 1
	for _, row in ipairs(quests) do
		if want[row[F.DUNGEON]] and (row[F.SIDE] == 3 or row[F.SIDE] == side)
			and (row[F.CLASS] == 0 or bit.band(row[F.CLASS], cbit) ~= 0) then
			local id, state = row[F.ID], "take"
			if Done(id) then
				state = "done"
			elseif InLog(id) then
				state = "log"
			elseif (row[F.REQ] or 0) > level or ((row[F.PREV] or 0) > 0 and not Done(row[F.PREV])) then
				state = "later"
			end
			out[#out + 1] = { row = row, state = state }
		end
	end
	table.sort(out, function(a, b)
		if a.row[F.LEVEL] ~= b.row[F.LEVEL] then
			return a.row[F.LEVEL] < b.row[F.LEVEL]
		end
		return a.row[F.ID] < b.row[F.ID]
	end)
	return out
end

-- the instance's door: { cont, wx, wy } of the quest data's entrances (yours: a side's own door, the other's not)
function J.Door(inst)
	local data = rawget(_G, "MelloUI_QuestListData")
	local side = Side()
	for _, e in ipairs(type(data) == "table" and data.entrances or NONE) do
		if e[1] == inst.key and (not e[10] or e[10] == 0 or e[10] == side) then
			return { cont = e[3], wx = e[4], wy = e[5], zone = e[6] }
		end
	end
	return nil
end

-- the zone its door stands in, by name: the game's map at the door's world spot (kept; nil: not known)
function J.Zone(inst)
	if inst.zoneName ~= nil then
		return inst.zoneName or nil
	end
	inst.zoneName = false
	local door = J.Door(inst)
	if door and C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D then
		local ok, mapID, pos = pcall(C_Map.GetMapPosFromWorldPos, door.cont, CreateVector2D(door.wx, door.wy))
		mapID = ok and Num(mapID) or nil
		local ok2, info = pcall(C_Map.GetMapInfo, mapID or 0)
		info = ok2 and type(info) == "table" and info or nil
		-- (a continent's answer: the zone at the spot on it)
		if info and Num(info.mapType) and info.mapType <= 2 and pos and C_Map.GetMapInfoAtPosition then
			local x, y = pos.x, pos.y
			if Num(x) and Num(y) then
				local ok3, z = pcall(C_Map.GetMapInfoAtPosition, mapID, x, y)
				info = ok3 and type(z) == "table" and z or info
			end
		end
		inst.zoneName = info and Text(info.name) or false
	end
	return inst.zoneName or nil
end

--------------------------------------------------------------------------------
-- Opening it: the map, its column on Dungeon Info's page
--------------------------------------------------------------------------------

function J.Open(key, encounterID)
	local map = MelloUI:GetModule("Map")
	if not (map and map.isEnabled and map.OpenDungeonInfo) then
		MelloUI:Print(TEXT.mapOff)
		return false
	end
	map:OpenDungeonInfo()
	local P = J.Panel
	if P and P.Show then
		P:Show(key and J.Get(key) or nil, encounterID)
	end
	return true
end

function J.Toggle()
	local map = MelloUI:GetModule("Map")
	if map and map.isEnabled and map.DungeonInfoShown and map:DungeonInfoShown() then
		map:Toggle(false)
		return
	end
	J.Open()
end

SLASH_MELLODUNGEONINFO1 = "/dungeoninfo"
SLASH_MELLODUNGEONINFO2 = "/dinfo"
SlashCmdList.MELLODUNGEONINFO = function(msg)
	msg = strtrim(msg or "")
	if msg == "" then
		J.Open()
		return
	end
	if msg:lower() == "export" then
		local text = J.Export()
		if text then
			MelloUI:ShowText(TEXT.exportTitle, TEXT.exportHelp .. "\n\n" .. text)
		else
			MelloUI:Print(TEXT.exportNone)
		end
		return
	end
	local inst = J.Find(msg)
	if inst then
		J.Open(inst.key)
	else
		MelloUI:Print(TEXT.notFound, msg)
		MelloUI:Print(TEXT.usage)
	end
end

-- the key binding's name (Bindings.xml)
BINDING_NAME_MELLOUI_DUNGEONINFO_TOGGLE = "Open or close Dungeon Info"

--------------------------------------------------------------------------------
-- (1.2.2) The drops: the data's, DungeonJournal's while it is loaded, and the ones seen fall, counted for the account
-- (the user, 2026-10-23: "the loot from the bosses ... we also need to have information about the trash mobs loot
-- since some of them drop valuable loot"; Forever's own dungeons are in no database MelloUI may ship, and other
-- addons' lists are theirs: read in game, never copied). A boss's kills and what each dropped; the trash's corpses
-- looted by creature and their rare drops. /dungeoninfo export puts what you have seen in the copy window, to send
-- in: Tools/build_dungeoninfo.py adds what players sent to the data's `seen`, counted with your own.
--   J.Drops(boss) -> { { item, chance (percent, nil: not known), quality, name, req, starts, mobs, src }, ... }
--     src "data" (the database's), "listed" (DungeonJournal's), "seen" (seen fall only)
--------------------------------------------------------------------------------

local LEARN_FOR = 300   -- s after a kill its loot is his (a slow looter, a long roll)
local TRASH_QUALITY = 3 -- the trash's drops counted: rare and better (the user's pick)
local ROLL_SAME = 10    -- s: a roll for an item the loot window just showed is the same drop
local events = CreateFrame("Frame")

local function Seen()
	return Account().seen
end

-- what the data's `seen` (the players' exports) and your own say of a boss: kills, { [item] = times }, { [item] = q }
local function BossCounts(id)
	local n, times, q = 0, {}, {}
	local data = rawget(_G, "MelloUI_DungeonInfoData")
	local shipped = type(data) == "table" and type(data.seen) == "table" and data.seen.boss
	local f = type(shipped) == "table" and shipped[id]
	if type(f) == "table" then
		n = n + (f[1] or 0)
		for j = 2, #f, 3 do
			times[f[j]] = (times[f[j]] or 0) + f[j + 1]
			q[f[j]] = f[j + 2]
		end
	end
	local own = Seen().boss[id]
	if type(own) == "table" then
		n = n + (Num(own.n) or 0)
		for item, c in pairs(own.i or NONE) do
			times[item] = (times[item] or 0) + c
			q[item] = (own.q or NONE)[item] or q[item]
		end
	end
	return n, times, q
end

-- the trash creatures of an instance, shipped and your own: { [npc] = { name, n = corpses, i = { [item] = times },
-- q = { [item] = quality } } }, and the rolls whose creature is not known: { [item] = times }, { [item] = quality }
local function TrashCounts(key)
	local mobs, rolls, rq = {}, {}, {}
	local function Mob(npc, name)
		local m = mobs[npc]
		if not m then
			m = { name = name, n = 0, i = {}, q = {} }
			mobs[npc] = m
		end
		if (not m.name or m.name == "") and name and name ~= "" then
			m.name = name
		end
		return m
	end
	local data = rawget(_G, "MelloUI_DungeonInfoData")
	local shipped = type(data) == "table" and type(data.seen) == "table" and data.seen or NONE
	for npc, f in pairs(type(shipped.mob) == "table" and shipped.mob or NONE) do
		if f[1] == key then
			local m = Mob(npc, f[2])
			m.n = m.n + (f[3] or 0)
			for j = 4, #f, 3 do
				m.i[f[j]] = (m.i[f[j]] or 0) + f[j + 1]
				m.q[f[j]] = f[j + 2]
			end
		end
	end
	local sr = type(shipped.roll) == "table" and shipped.roll[key]
	for j = 1, type(sr) == "table" and #sr or 0, 3 do
		rolls[sr[j]] = (rolls[sr[j]] or 0) + sr[j + 1]
		rq[sr[j]] = sr[j + 2]
	end
	local s = Seen()
	for npc, o in pairs(s.mob) do
		if type(o) == "table" and o.k == key then
			local m = Mob(npc, o.name)
			m.n = m.n + (Num(o.n) or 0)
			for item, c in pairs(o.i or NONE) do
				m.i[item] = (m.i[item] or 0) + c
				m.q[item] = (o.q or NONE)[item] or m.q[item]
			end
		end
	end
	local own = s.roll[key]
	if type(own) == "table" then
		for item, c in pairs(own.i or NONE) do
			rolls[item] = (rolls[item] or 0) + c
			rq[item] = (own.q or NONE)[item] or rq[item]
		end
	end
	return mobs, rolls, rq
end

--------------------------------------------------------------------------------
-- DungeonJournal's lists, read in game while it is loaded (its own data, never copied: All Rights Reserved), as Route
-- reads the levelling guides: its dungeon by name ("Hall of Thanes" is the client's "The Hall of Thanes"; its
-- Scarlet Monastery's wings are one instance here), its bosses by name or alias (its Magmatus is the client's
-- Infurnus); its trash list and the creatures it lists that are no encounter of the client's go to the trash
--------------------------------------------------------------------------------

local bridged = setmetatable({}, { __mode = "k" })   -- [inst] = { [boss id] = { { item, name, quality, mob }, ... } } | false

local function Norm(s)
	s = type(s) == "string" and s:lower() or ""
	return (s:gsub("^the%s+", ""):gsub("[^%w]", ""))
end

local function BridgeRead(inst, db)
	local want = Norm(inst.name)
	local byName = {}
	for _, b in ipairs(inst.bosses) do
		byName[Norm(b.name)] = b
	end
	local out, found = {}, false
	for name, d in pairs(db) do
		local n = type(name) == "string" and Norm(name) or ""
		if type(d) == "table" and type(d.bosses) == "table" and n ~= ""
			and (n == want or (name:find(":", 1, true) and n:sub(1, #want) == want)) then
			found = true
			for _, e in ipairs(d.bosses) do
				if type(e) == "table" and type(e.loot) == "table" then
					local boss
					if not e.trash then
						boss = byName[Norm(e.name)]
						for _, alias in ipairs(type(e.aliases) == "table" and e.aliases or NONE) do
							boss = boss or byName[Norm(alias)]
						end
					end
					local id = boss and boss.id or inst.trash.id
					local mob = (not boss and not e.trash and type(e.name) == "string") and e.name or nil
					local list = out[id] or {}
					out[id] = list
					for _, l in ipairs(e.loot) do
						local item = type(l) == "table" and tonumber(l[1])
						if item then
							list[#list + 1] = { item = item, name = type(l[2]) == "string" and l[2] or nil,
								quality = tonumber(l[4]) or 2, mob = mob }
						end
					end
				end
			end
		end
	end
	return found and out or false
end

-- DungeonJournal's drops of `inst` by boss id (the trash's: inst.trash.id), or nil: not loaded, or not there
function J.Bridge(inst)
	local b = bridged[inst]
	if b ~= nil then
		return b or nil
	end
	local fdj = rawget(_G, "ForeverDungeonJournal_NS")
	local db = type(fdj) == "table" and rawget(fdj, "DB")
	if type(db) ~= "table" then
		return nil   -- (not kept: it may be loaded later)
	end
	local ok, got = pcall(BridgeRead, inst, db)
	b = ok and got or false
	bridged[inst] = b
	return b or nil
end

--------------------------------------------------------------------------------
-- The drops of a boss or of an instance's trash: the data's first, then DungeonJournal's, then the ones only seen;
-- a chance from the counts where the data has none (kept until a drop is seen again)
--------------------------------------------------------------------------------

local cache = setmetatable({}, { __mode = "k" })   -- [boss] = { v = S.version, list }

local function ChanceOf(times, n)
	if not (times and n and n > 0) then
		return nil
	end
	return math.min(100, times / n * 100)
end

function J.Drops(boss)
	if not boss then
		return NONE
	end
	local c = cache[boss]
	if c and c.v == S.version then
		return c.list
	end
	local list, have = {}, {}
	-- the counts: a boss's kills, or the trash's creatures (each item at its likeliest creature's rate)
	local chance, q, mobsOf = {}, {}, {}
	if boss.trash then
		local mobs, rolls, rq = TrashCounts(-boss.id)
		for _, m in pairs(mobs) do
			for item, times in pairs(m.i) do
				local ch = ChanceOf(times, m.n)
				if ch and ch > (chance[item] or -1) then
					chance[item] = ch
				end
				q[item] = m.q[item] or q[item]
				if m.name and m.name ~= "" then
					mobsOf[item] = mobsOf[item] and (mobsOf[item] .. ", " .. m.name) or m.name
				end
			end
		end
		for item in pairs(rolls) do
			chance[item] = chance[item] or false   -- (seen, no rate)
			q[item] = q[item] or rq[item]
		end
	else
		local n, times, bq = BossCounts(boss.id)
		for item, t in pairs(times) do
			chance[item] = ChanceOf(t, n) or false
			q[item] = bq[item]
		end
		for item in pairs(J.Learned(boss)) do
			chance[item] = chance[item] or false
		end
	end
	-- the data's drops in its order (a curated one with no chance takes the counts' once there are some), then
	-- Everloot's players' rates for an item the data does not list
	for _, d in ipairs(boss.drops) do
		if d.chance == nil and chance[d.item] then
			list[#list + 1] = setmetatable({ chance = chance[d.item] }, { __index = d })
		else
			list[#list + 1] = d
		end
		have[d.item] = true
	end
	for _, d in ipairs(boss.ever or NONE) do
		if not have[d.item] then
			list[#list + 1] = d
			have[d.item] = true
		end
	end
	local B = boss.inst and J.Bridge(boss.inst)
	local listed = B and B[boss.id] or NONE
	local start = #list
	for _, l in ipairs(listed) do
		if not have[l.item] then
			have[l.item] = true
			list[#list + 1] = { item = l.item, name = l.name, quality = l.quality, req = 0, starts = 0, src = "listed",
				chance = chance[l.item] or nil, mobs = l.mob or mobsOf[l.item] }
		end
	end
	for item, ch in pairs(chance) do
		if not have[item] then
			have[item] = true
			list[#list + 1] = { item = item, quality = q[item] or 2, req = 0, starts = 0, src = "seen",
				chance = ch or nil, mobs = mobsOf[item] }
		end
	end
	-- (the data's in its own order; the rest: the better quality first, then the likelier)
	local rest = {}
	for i = start + 1, #list do
		rest[#rest + 1] = list[i]
	end
	table.sort(rest, function(a, b)
		if a.quality ~= b.quality then
			return a.quality > b.quality
		end
		if (a.chance or 0) ~= (b.chance or 0) then
			return (a.chance or 0) > (b.chance or 0)
		end
		return a.item < b.item
	end)
	for i, d in ipairs(rest) do
		list[start + i] = d
	end
	cache[boss] = { v = S.version, list = list }
	return list
end

--------------------------------------------------------------------------------
-- Counting what falls: a boss's kill (ENCOUNTER_END) and its loot -- its corpse (the creatures seen as the boss
-- units in its fight, or else the first corpse looted after the kill) or a roll in the next two minutes; a trash
-- creature's corpse each time one is looted, and its rare drops; a roll away from a kill: the instance's trash, its
-- creature not known. A corpse counts once (its GUID), an item once a kill; a creature counted as trash is never
-- taken for the boss
--------------------------------------------------------------------------------

local looted = {}   -- [corpse GUID] = true (this session)
local nLooted = 0
local recent = {}   -- [item] = when the loot window showed it (a roll for it soon after is the same drop)

local function Here()
	local ok, _, kind, _, _, _, _, _, mapID = pcall(GetInstanceInfo)
	if not ok or (kind ~= "party" and kind ~= "raid") then
		return nil
	end
	return J.ByMap(Num(mapID))
end

-- a creature's id from its GUID ("Creature-0-3132-0-12-261306-0000ABCDEF"), nil for a player, an object, a secret
local function NpcOf(guid)
	if Secret(guid) or type(guid) ~= "string" then
		return nil
	end
	local kind, npc = guid:match("^(%a+)%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-")
	if kind ~= "Creature" and kind ~= "Vehicle" then
		return nil
	end
	return tonumber(npc)
end

-- a creature's name, when the corpse is your target or under the mouse
local function NameOf(guid)
	for _, unit in ipairs({ "mouseover", "target" }) do
		local ok, g = pcall(UnitGUID, unit)
		if ok and not Secret(g) and g == guid then
			local okN, name = pcall(UnitName, unit)
			return okN and Text(name) or nil
		end
	end
	return nil
end

local function Bump()
	S.version = S.version + 1
	local P = J.Panel
	if P and P.Lay then
		P:Lay()
	end
end

-- a boss's drop, once a kill
local function BossItem(kill, item, quality)
	if kill.items[item] then
		return
	end
	kill.items[item] = true
	local b = Seen().boss[kill.id] or { n = 0, i = {}, q = {} }
	Seen().boss[kill.id] = b
	b.i[item] = (b.i[item] or 0) + 1
	b.q[item] = quality
end

local function Kill()
	local kill = S.kill
	if kill and GetTime() - kill.at <= LEARN_FOR then
		return kill
	end
	return nil
end

local function LootReady()
	local inst = Here()
	if not inst then
		return
	end
	local s, kill = Seen(), Kill()
	local n = Num(GetNumLootItems and GetNumLootItems()) or 0
	local changed = false
	local corpses = {}
	for slot = 1, n do
		local okL, link = pcall(GetLootSlotLink, slot)
		local okI, _, _, _, _, quality = pcall(GetLootSlotInfo, slot)
		local item = okL and J.LinkID(link) or nil
		quality = okI and Num(quality) or nil
		local source = rawget(_G, "GetLootSourceInfo")
		local src = source and { pcall(source, slot) } or NONE
		for j = 2, src[1] == true and #src or 0, 2 do
			local guid = src[j]
			local npc = NpcOf(guid)
			if npc then
				if not corpses[guid] then
					corpses[guid] = npc
				end
				if item and quality then
					recent[item] = GetTime()
					local enc = s.bossNpc[npc]
					-- (no boss unit seen in his fight: the first corpse looted after the kill is his)
					if not enc and kill and not kill.npcSet and not s.mob[npc] then
						kill.npcSet = true
						s.bossNpc[npc] = kill.id
						enc = kill.id
					end
					if enc then
						if kill and kill.id == enc and quality >= 2 then
							BossItem(kill, item, quality)
							changed = true
						end
					elseif quality >= TRASH_QUALITY and not looted[guid] then
						local m = s.mob[npc] or { k = inst.key, n = 0, i = {}, q = {} }
						s.mob[npc] = m
						m.i[item] = (m.i[item] or 0) + 1
						m.q[item] = quality
						changed = true
					end
				end
			end
		end
	end
	-- each trash corpse looted counts once (its rate's denominator), its name when it is your target or under the mouse
	for guid, npc in pairs(corpses) do
		if not looted[guid] then
			looted[guid] = true
			nLooted = nLooted + 1
			if not s.bossNpc[npc] then
				local m = s.mob[npc] or { k = inst.key, n = 0, i = {}, q = {} }
				s.mob[npc] = m
				m.n = m.n + 1
				m.name = m.name or NameOf(guid)
				changed = true
			end
		end
	end
	if nLooted > 2000 then
		wipe(looted)   -- (a long session: a corpse looted again after this is counted again, rarely)
		nLooted = 0
	end
	if changed then
		Bump()
	end
end

local function LootRoll(rollID)
	local inst = Here()
	if not inst then
		return
	end
	local okL, link = pcall(GetLootRollItemLink, rollID)
	local okI, _, _, _, quality = pcall(GetLootRollItemInfo, rollID)
	local item = okL and J.LinkID(link) or nil
	quality = okI and Num(quality) or nil
	if not (item and quality) or (recent[item] and GetTime() - recent[item] < ROLL_SAME) then
		return
	end
	local kill = Kill()
	if kill and quality >= 2 then
		BossItem(kill, item, quality)
	elseif quality >= TRASH_QUALITY then
		local s = Seen()
		local r = s.roll[inst.key] or { i = {}, q = {} }
		s.roll[inst.key] = r
		r.i[item] = (r.i[item] or 0) + 1
		r.q[item] = quality
	else
		return
	end
	Bump()
end

local OnEvent = Perf.Shared("OnEvent of Dungeon Info (drops counted)", function(_, event, a1, _, _, _, a5)
	if event == "ENCOUNTER_START" then
		-- the boss units in his fight: their corpses are his
		local id = Num(a1)
		if id then
			local s = Seen()
			for i = 1, 5 do
				local ok, guid = pcall(UnitGUID, "boss" .. i)
				local npc = ok and NpcOf(guid)
				if npc then
					s.bossNpc[npc] = id
				end
			end
		end
	elseif event == "ENCOUNTER_END" then
		if Num(a5) == 1 and Num(a1) then
			local ok, _, _, _, _, _, _, _, mapID = pcall(GetInstanceInfo)
			S.kill = { id = a1, at = GetTime(), map = ok and Num(mapID) or nil, items = {} }
			local b = Seen().boss[a1] or { n = 0, i = {}, q = {} }
			Seen().boss[a1] = b
			b.n = (Num(b.n) or 0) + 1
			Bump()
		end
	elseif event == "LOOT_READY" then
		LootReady()
	elseif event == "START_LOOT_ROLL" then
		LootRoll(a1)
	end
end, "script")
Perf.SetScript(events, "OnEvent", OnEvent)

--------------------------------------------------------------------------------
-- /dungeoninfo export: your own counts as text, to send in (an id of your account's own, made once, so a second
-- export of yours replaces the first instead of counting twice; no name of yours in it)
--   MDI1 <id> <MelloUI version>
--   B <encounter> <kills> <item>:<times>:<quality> ...
--   M <instance key> <npc> <corpses> <item>:<times>:<quality> ...|<name>
--   R <instance key> <item>:<times>:<quality> ...
--   END
--------------------------------------------------------------------------------

local function Pairs(i, q)
	local out = {}
	for item, c in pairs(i or NONE) do
		out[#out + 1] = string.format("%d:%d:%d", item, c, (q or NONE)[item] or 0)
	end
	table.sort(out)
	return table.concat(out, " ")
end

function J.Export()
	local a = Account()
	local s = a.seen
	if type(a.id) ~= "string" then
		a.id = string.format("%08x%04x", math.random(0, 0x7fffffff), math.random(0, 0xffff))
	end
	local lines = { string.format("MDI1 %s %s", a.id, tostring(MelloUI.version)) }
	local n = 0
	for id, b in pairs(s.boss) do
		if type(b) == "table" and ((Num(b.n) or 0) > 0 or next(b.i or NONE)) then
			lines[#lines + 1] = string.format("B %d %d %s", id, Num(b.n) or 0, Pairs(b.i, b.q))
			n = n + 1
		end
	end
	for npc, m in pairs(s.mob) do
		if type(m) == "table" and (Num(m.n) or 0) > 0 then
			lines[#lines + 1] = string.format("M %d %d %d %s|%s", m.k or 0, npc, m.n, Pairs(m.i, m.q),
				(m.name or ""):gsub("[|\n]", " "))
			n = n + 1
		end
	end
	for key, r in pairs(s.roll) do
		if type(r) == "table" and next(r.i or NONE) then
			lines[#lines + 1] = string.format("R %d %s", key, Pairs(r.i, r.q))
			n = n + 1
		end
	end
	lines[#lines + 1] = "END"
	return n > 0 and table.concat(lines, "\n") or nil
end

function M:OnEnable()
	events:RegisterEvent("ENCOUNTER_START")
	events:RegisterEvent("ENCOUNTER_END")
	events:RegisterEvent("LOOT_READY")
	events:RegisterEvent("START_LOOT_ROLL")
	if J.DoorRow then
		J.DoorRow(true)
	end
end

function M:OnDisable()
	events:UnregisterAllEvents()
	if J.DoorRow then
		J.DoorRow(false)
	end
end

function M:OnSettingChanged(key)
	if key == "doorRow" and J.DoorRow then
		J.DoorRow(self.isEnabled)
	end
end

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
	usage = "/dungeoninfo [dungeon]: open Dungeon Info (on that dungeon's page).",
	learned = "Seen drop",
}
local TEXT = J.TEXT

local M = MelloUI:RegisterModule("DungeonInfo", {
	title = "Dungeon Info",
	desc = "Every dungeon and raid on the map: its bosses in order and what each one drops, your own list of items to look out for (the loot roll marks them), and a trip that picks up a dungeon's quests in the fastest order.",
	icon = "Interface\\Icons\\INV_Misc_Book_09",
	flavour = "Every dungeon's bosses and their loot beside the map; star the items you want and a loot roll tells you when one drops.",
	group = "Quests and travel", navOrder = 4,
	role = "feature", new = "1.2.0",
	enabledByDefault = true,
	defaults = {
		doorRow = false,   -- (the user's pick D: off by default, no clutter)
	},
	options = {
		{ type = "button", name = "Open Dungeon Info", text = "Open", new = "1.2.0",
		  desc = "Open Dungeon Info beside MelloUI's map: the door button over the map, a click on a dungeon's door on the map, /dungeoninfo and the key you give it in the game's Key Bindings open it too.",
		  onClick = function() J.Open() end },
		{ type = "toggle", key = "doorRow", name = "At A Dungeon's Door", new = "1.2.0",
		  desc = "When you walk up to a dungeon's door (or into it), a row in the widget column: its bosses, how many of your items drop there, and its page in Dungeon Info and its quests one click away." },
	},
})
J.M = M

--------------------------------------------------------------------------------
-- The data, read the first time it is asked for
--------------------------------------------------------------------------------

local S = { built = false, byKey = {}, byMap = {}, list = {}, kill = nil }
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
			local boss = { id = b[1], name = b[2], index = i, drops = {} }
			local d = b[3]
			for j = 1, #d, 6 do
				boss.drops[#boss.drops + 1] = { item = d[j], chance = d[j + 1] / 10, quality = d[j + 2], name = d[j + 3],
					req = d[j + 4], starts = d[j + 5] }
			end
			inst.bosses[i] = boss
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

-- how many of your items drop in the instance
function J.TrackedIn(inst)
	local t, n = Char().tracked, 0
	for _, boss in ipairs(inst.bosses) do
		for _, d in ipairs(boss.drops) do
			if t[d.item] then
				n = n + 1
			end
		end
		for id in pairs(J.Learned(boss)) do
			if t[id] then
				n = n + 1
			end
		end
	end
	return n
end

-- where an item drops: the instance and the boss (the data's first, then the learned)
function J.WhereDrops(itemID)
	Build()
	for _, inst in ipairs(S.list) do
		for _, boss in ipairs(inst.bosses) do
			for _, d in ipairs(boss.drops) do
				if d.item == itemID then
					return inst, boss, d
				end
			end
			if J.Learned(boss)[itemID] then
				return inst, boss, nil
			end
		end
	end
	return nil
end

local NONE = {}
-- the drops seen from a boss the data does not list: { [itemID] = true }
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
-- Drops learned: a boss killed (ENCOUNTER_END), then his loot (the loot window, a roll) in the next two minutes in
-- the same instance -- for the bosses whose drops the data has not
--------------------------------------------------------------------------------

local LEARN_FOR = 120   -- s after a kill its loot is his
local events = CreateFrame("Frame")

local function Learn(itemID, quality)
	local kill = S.kill
	quality = Num(quality)
	if not (kill and itemID and quality and quality >= 2) or GetTime() - kill.at > LEARN_FOR then
		return
	end
	local inst = J.ByMap(kill.map)
	local boss
	for _, b in ipairs(inst and inst.bosses or NONE) do
		if b.id == kill.id then
			boss = b
		end
	end
	if not boss then
		return
	end
	for _, d in ipairs(boss.drops) do
		if d.item == itemID then
			return   -- (known)
		end
	end
	local l = Account().learned
	l[boss.id] = l[boss.id] or {}
	l[boss.id][itemID] = true
end

local OnEvent = Perf.Shared("OnEvent of Dungeon Info (drops learned)", function(_, event, a1, _, _, _, a5)
	if event == "ENCOUNTER_END" then
		if Num(a5) == 1 and Num(a1) then
			local ok, _, _, _, _, _, _, _, mapID = pcall(GetInstanceInfo)
			S.kill = { id = a1, at = GetTime(), map = ok and Num(mapID) or nil }
		end
	elseif event == "LOOT_READY" then
		if not S.kill then
			return
		end
		local n = Num(GetNumLootItems and GetNumLootItems()) or 0
		for slot = 1, n do
			local ok, link = pcall(GetLootSlotLink, slot)
			local ok2, _, _, _, _, quality = pcall(GetLootSlotInfo, slot)
			if ok and ok2 then
				Learn(J.LinkID(link), quality)
			end
		end
	elseif event == "START_LOOT_ROLL" then
		if not S.kill then
			return
		end
		local ok, link = pcall(GetLootRollItemLink, a1)
		local ok2, _, _, _, quality = pcall(GetLootRollItemInfo, a1)
		if ok and ok2 then
			Learn(J.LinkID(link), quality)
		end
	end
end, "script")
Perf.SetScript(events, "OnEvent", OnEvent)

function M:OnEnable()
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

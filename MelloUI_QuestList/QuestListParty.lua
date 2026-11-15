--------------------------------------------------------------------------------
-- MelloUI - Quest List: your group's quests (2.1.54; a player's wish: "we are in a group, but I can't see who has which
-- quest", on the map and in the list)
--
-- Who in your party or raid has a quest, and how far they are with it, for the Quest List's rows and tooltips and the
-- map's and the minimap's objective marks:
--   * Questie's own group data (QuestieComms, read only: GetQuest(questID) -> { [name] = objectives }, each objective's
--     fulfilled, required, finished, in the quest log's order): the members who run Questie too, with their counts
--   * else the game's C_QuestLog.IsUnitOnQuest(unit, questID), where this client has it: a member on the quest, no count
-- Read when asked (a tooltip, a row laid) and kept for that frame only; nothing of Questie's written, nothing made at
-- login. Solo, nothing at all.
--   QL.Party.On(questID) -> { { name, class, objectives (Questie's, or nil), done, total }, ... } the members on it,
--                           by name; empty when solo or nobody has it
--   QL.Party.TipLines(tip, questID[, index])  a tooltip's lines: a heading, a member a line in their class colour, with
--                           objective `index`'s count (the map's marks) or how many of its objectives are done
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local QL = ns.QuestList
local Safe = MelloUI.Safe
local Plain, Num = Safe.Value, Safe.Number

local P = { cache = {}, at = nil }
QL.Party = P
MelloUI.QuestParty = P   -- (the map's Quests tab, MelloUI_Map/MapQuestLog.lua, another addon, reads it here)

-- a module of Questie's (its loader's; nil when it is not there): as Core/QuestieLook.lua asks it
local function Questie(name)
	local L = rawget(_G, "QuestieLoader")
	if type(L) ~= "table" or type(L.ImportModule) ~= "function" then
		return nil
	end
	local ok, mod = pcall(L.ImportModule, L, name)
	return ok and type(mod) == "table" and mod or nil
end

-- the group's other members' units (reused): a raid's units name you too (one of raid1..raidN is you), a party's never
local units = {}
local function Units()
	local n = 0
	if IsInRaid() then
		for i = 1, Num(GetNumGroupMembers()) or 0 do
			local unit = "raid" .. i
			local ok, me = pcall(UnitIsUnit, unit, "player")
			if not (ok and Plain(me) == true) then
				n = n + 1
				units[n] = unit
			end
		end
	elseif IsInGroup() then
		for i = 1, 4 do
			n = n + 1
			units[n] = "party" .. i
		end
	end
	for i = #units, n + 1, -1 do
		units[i] = nil
	end
	return units
end

-- a member's name as the list shows it and as Questie keys it ("Name" on your realm, "Name-Realm" from another)
local function NameOf(unit)
	local ok, name, realm = pcall(UnitName, unit)
	name, realm = ok and Plain(name) or nil, ok and Plain(realm) or nil
	if type(name) ~= "string" or name == "" or name == rawget(_G, "UNKNOWNOBJECT") then
		return nil
	end
	return name, (type(realm) == "string" and realm ~= "") and (name .. "-" .. realm) or name
end

local function ByName(a, b)
	return a.name < b.name
end

function P.On(questID)
	questID = Num(questID)
	if not questID or not IsInGroup() then
		return {}
	end
	local now = GetTime()
	if P.at ~= now then
		wipe(P.cache)
		P.at = now
	end
	local hit = P.cache[questID]
	if hit then
		return hit
	end
	local list = {}
	local comms = Questie("QuestieComms")
	local remote
	if comms and type(comms.GetQuest) == "function" then
		local ok, r = pcall(comms.GetQuest, comms, questID)
		remote = ok and type(r) == "table" and r or nil
	end
	local CQ = rawget(_G, "C_QuestLog")
	local onQuest = type(CQ) == "table" and CQ.IsUnitOnQuest or nil
	for _, unit in ipairs(Units()) do
		local okE, there = pcall(UnitExists, unit)
		if okE and Plain(there) then
			local short, full = NameOf(unit)
			if short then
				local objectives = remote and (remote[full] or remote[short]) or nil
				local has = type(objectives) == "table"
				if not has and type(onQuest) == "function" then
					local ok, yes = pcall(onQuest, unit, questID)
					has = ok and Plain(yes) == true
				end
				if has then
					local okC, _, class = pcall(UnitClass, unit)
					local done, total = 0, 0
					for _, o in ipairs(type(objectives) == "table" and objectives or {}) do
						if type(o) == "table" then
							total = total + 1
							if o.finished then
								done = done + 1
							end
						end
					end
					list[#list + 1] = { name = short, class = okC and Plain(class) or nil,
						objectives = type(objectives) == "table" and objectives or nil, done = done, total = total }
				end
			end
		end
	end
	table.sort(list, ByName)
	P.cache[questID] = list
	return list
end

-- a member's name in their class colour
local function Painted(m)
	local Colours = MelloUI.Colours
	if m.class and Colours and Colours.Class then
		local r, g, b = Colours.Class(m.class)
		if type(r) == "number" then
			return QL.TipPaint(m.name, r, g, b)
		end
	end
	return m.name
end

function P.TipLines(tip, questID, index)
	local list = P.On(questID)
	if #list == 0 then
		return
	end
	local W = MelloUI.Widgets
	QL.TipLine(tip, W.Tr("In your group"), "selectedTrim")
	for _, m in ipairs(list) do
		local o = index and m.objectives and m.objectives[index]
		local status
		if type(o) == "table" and Num(o.required) then
			status = string.format("%d/%d", Num(o.fulfilled) or 0, Num(o.required))
		elseif m.total > 0 then
			status = m.done >= m.total and W.Tr("ready to hand in") or W.Tr("%d of %d objectives"):format(m.done, m.total)
		end
		QL.TipLine(tip, status and (Painted(m) .. "  " .. status) or Painted(m), "text")
	end
end

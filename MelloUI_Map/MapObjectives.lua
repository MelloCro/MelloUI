--------------------------------------------------------------------------------
-- MelloUI Map - your quests' objectives (docs/plans/seamless-map.md, after M4;
-- the user, 2026-10-20: "Quest objectives", shown by default)
--
-- Where each open objective of the quests in your log is done, on the whole
-- map at once (the Quest List's objective marks on the game's map show the
-- one zone open there). The places are MelloUI.QuestObjectives' (the
-- Companion's data, asked for at the map's first open that has a quest; the
-- places learned in game after it), each objective's in groups (a place
-- joins a group within REACH world units of one of its places):
--   a mark   per group at its middle, from a zone's zoom on: the objective's
--            kind (the quest column's icons: kill, collect, explore); its
--            tooltip and its click the Quest List's own marks' (the quest,
--            the objective and its count, where it drops; a waypoint there,
--            Route's), a plain one without the Quest List
--   a dot    per place from the minimap ground's zoom on (the set's map_dot)
-- A done objective shows nothing, a done quest nothing (its hand-in is the
-- givers' "?"); the quest open on the quest column's page is left to its own
-- marks there. Only The Tracked Quests (the Quest List's setting) followed.
-- Laid at the map's open and half a second after the log's last change while
-- it shows (one flag, one wait: nothing made per event).
--
--   Objectives.Init(canvas, pins)    the layers (the window's first open)
--   Objectives.Open() / Close()      the window shown / hidden
--   Objectives.Soon()                the log changed: laid again on the beat, after the burst
--   Objectives.Tick(elapsed)         the window's beat
--   Objectives.Data()                the Companion's data, asked for once (the quest column's Show too)
--   Objectives.Lay()                 laid now (the tests)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Safe = MelloUI.Safe
local Plain, Finite, Secret = Safe.Value, Safe.Finite, Safe.IsSecret
local ipairs, pcall, type, wipe = ipairs, pcall, type, wipe

local Objectives = {}
ns.Objectives = Objectives

local T = {
	ORDER = { marks = 22, dots = 21 },   -- over the quest givers (20), under the quest column's marks (25)
	MARKS_FROM = 2.5,     -- the marks from a zone's zoom on (the givers' zoom: Layers.T.QUESTS_FROM)
	DOTS_FROM = 5,        -- the places' dots from the minimap ground's zoom on (the canvas's MINI_IN)
	REACH = 4,            -- world units: a place this close to one of a group's places is in it (about the Quest
	                      -- List's 0.06 of a zone's width)
	MARK_SIZE = 20,
	DOT_SIZE = 12,        -- the Quest List's DOT_PX
	WAIT = 0.5,           -- after the log's last change of a burst (a dozen on a turn-in)
	ICONS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\",
	KIND_ICON = { "kill", "pin_collect", "pin_collect", "obj_explore" },   -- QO's kinds: creature, object, item, area
}
Objectives.T = T

local S = { canvas = nil, pins = nil, shown = false, asked = false, wait = nil, xs = {}, ys = {}, quests = {} }
Objectives.S = S

local function QuestList()
	local QL = rawget(MelloUI, "QuestList")
	return (type(QL) == "table" and QL.M and QL.M.isEnabled) and QL or nil
end

-- the Companion's data: asked for once a session (a refusal is the Companion's own notice)
function Objectives.Data()
	if rawget(_G, "MelloUI_QuestObjectiveData") then
		return true
	end
	if S.asked or not MelloUI.LoadCompanion then
		return false
	end
	S.asked = true
	local ok = pcall(MelloUI.LoadCompanion, MelloUI)
	return ok and rawget(_G, "MelloUI_QuestObjectiveData") ~= nil
end

-- the quests in the log to show: not complete, not hidden, (Only The Tracked Quests) watched
local function LogQuests()
	local out = S.quests
	wipe(out)
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
		return out
	end
	local QL = QuestList()
	local trackedOnly = QL and QL.M.db and QL.M.db.objectiveTrackedOnly
	local okN, n = pcall(C_QuestLog.GetNumQuestLogEntries)
	n = okN and Finite(n) or 0
	for i = 1, n do
		local ok, info = pcall(C_QuestLog.GetInfo, i)
		if ok and type(info) == "table" and not Plain(info.isHeader) and not Plain(info.isHidden) then
			local id = Finite(info.questID)
			local okC, complete = pcall(C_QuestLog.IsComplete, id)
			if id and id > 0 and not (okC and Plain(complete)) then
				local watched = true
				if trackedOnly and C_QuestLog.GetQuestWatchType then
					local okW, watch = pcall(C_QuestLog.GetQuestWatchType, id)
					watched = okW and not Secret(watch) and watch ~= nil
				end
				if watched then
					out[#out + 1] = id
				end
			end
		end
	end
	return out
end

-- a mark's tooltip: the Quest List's own (QL.MarkTip, kind "objective"), else the quest and the objective
local function MarkTip(tooltip, pin)
	local d = pin.data
	local QL = QuestList()
	if QL and QL.MarkTip then
		QL.MarkTip(tooltip, "objective", d, true)
		return
	end
	local okT, title = pcall(C_QuestLog.GetTitleForQuestID, d.questID)
	tooltip:SetText(okT and Safe.Text(title) or d.name)
	local t = d.line
	tooltip:AddLine((t and t[6]) or d.name, 1, 1, 1, true)
end

-- its click: the Quest List's (a waypoint there, Route's), else the map's own pin there
local function MarkClick(pin, button)
	if button ~= "LeftButton" then
		return
	end
	local d = pin.data
	local QL = QuestList()
	if QL and QL.Objectives and QL.Objectives.Click and d.mapID then
		QL.Objectives.Click(d)
	elseif ns.Map and ns.Map.PinOn then
		ns.Map:PinOn(pin, d.name)
	end
end

local markSpecs, DOT = {}, nil
local function MarkSpec(kind)
	local icon = T.KIND_ICON[kind] or "obj_explore"
	local spec = markSpecs[icon]
	if not spec then
		spec = { icon = T.ICONS .. icon, size = T.MARK_SIZE, fillTip = MarkTip, click = MarkClick, sub = 1, lift = icon }
		markSpecs[icon] = spec
	end
	return spec
end

-- the places as groups: single linkage within REACH (a few dozen places an objective at most); fn(members)
local groups, seen, stack = {}, {}, {}
local function Groups(xs, ys, fn)
	local n = #xs
	wipe(seen)
	local r2 = T.REACH * T.REACH
	for i = 1, n do
		if not seen[i] then
			wipe(groups)
			seen[i] = true
			stack[1] = i
			local top = 1
			while top > 0 do
				local a = stack[top]
				top = top - 1
				groups[#groups + 1] = a
				for b = 1, n do
					if not seen[b] then
						local dx, dy = xs[a] - xs[b], ys[a] - ys[b]
						if dx * dx + dy * dy <= r2 then
							seen[b] = true
							top = top + 1
							stack[top] = b
						end
					end
				end
			end
			fn(groups)
		end
	end
end

-- every open objective of the quests in the log, laid
function Objectives.Lay()
	local pins = S.pins
	if not pins then
		return
	end
	pins:Clear("objectives")
	pins:Clear("objective_dots")
	S.wait = nil
	local layer = pins.layers.objectives
	if not (layer and layer.on) then
		return
	end
	local list = LogQuests()
	if #list == 0 or not Objectives.Data() then
		return
	end
	local QO = MelloUI.QuestObjectives
	local point = ns.Layers and ns.Layers.WorldPoint
	if not (QO and point) then
		return
	end
	local c = S.canvas
	local log = ns.QuestLog and ns.QuestLog.S
	local showing = log and log.showID
	local xs, ys = S.xs, S.ys
	local n = 0
	for _, questID in ipairs(list) do
		local data = questID ~= showing and QO.Of(questID)
		if type(data) == "table" then
			local lines = QO.Lines(questID)
			local itemLine = QO.ItemLine and QO.ItemLine(data, lines)
			-- (an objective no line names shows only when no line named any, or when it is an area: the Quest List's)
			local anyMatched = false
			for _, entry in ipairs(data) do
				if QO.Match(entry, lines, itemLine) then
					anyMatched = true
					break
				end
			end
			for index, entry in ipairs(data) do
				local t = QO.Match(entry, lines, itemLine)
				local open = (t and not t[2]) or (not t and (entry[1] == 4 or not anyMatched))
				if open and #entry > 4 then
					wipe(xs)
					wipe(ys)
					for k = 5, #entry - 1, 2 do
						local x, y = point(entry[4], entry[k], entry[k + 1])
						if x and y then
							xs[#xs + 1], ys[#ys + 1] = x, y
							n = n + 1
							pins:Set("objective_dots", n, x, y, DOT)
						end
					end
					local spec = MarkSpec(entry[1])
					local g = 0
					Groups(xs, ys, function(members)
						local mx, my = 0, 0
						for _, i in ipairs(members) do
							mx, my = mx + xs[i], my + ys[i]
						end
						mx, my = mx / #members, my / #members
						g = g + 1
						local pin = pins:Set("objectives", questID * 100000 + index * 1000 + g, mx, my, spec)
						if pin then
							-- (the Quest List's mark data: its tooltip and its click take it as their own)
							local p = c:PlaceAt(mx, my)
							local d = pin.data or {}
							d.questID, d.index, d.kind, d.name, d.line = questID, index, entry[1], entry[2], t
							d.mapID = p and p.id or nil
							d.x = p and (mx - p.left) / p.w or nil
							d.y = p and (my - p.top) / p.h or nil
							pin.data = d
						end
					end)
				end
			end
		end
	end
	pins:Lay()
end

function Objectives.Soon()
	if S.shown and not S.wait then
		S.wait = T.WAIT
	end
end

function Objectives.Tick(elapsed)
	local w = S.wait
	if w then
		w = w - (elapsed or 0)
		if w <= 0 then
			Objectives.Lay()
		else
			S.wait = w
		end
	end
end

function Objectives.Init(canvas, pins)
	S.canvas, S.pins = canvas, pins
	pins:Layer("objectives", T.ORDER.marks, { minZ = T.MARKS_FROM })
	pins:Layer("objective_dots", T.ORDER.dots, { minZ = T.DOTS_FROM })
	DOT = { icon = T.ICONS .. "map_dot", size = T.DOT_SIZE, sub = 0 }
end

function Objectives.Open()
	S.shown = true
	Objectives.Lay()
end

function Objectives.Close()
	S.shown = false
	S.wait = nil
	if S.pins then
		S.pins:Clear("objectives")
		S.pins:Clear("objective_dots")
	end
end


return Objectives

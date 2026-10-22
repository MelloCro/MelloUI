--------------------------------------------------------------------------------
-- MelloUI Map - your quests' objectives (docs/plans/seamless-map.md, after M4;
-- the user, 2026-10-20: "Quest objectives", shown by default)
--
-- Where each open objective of the quests in your log is done, on the whole
-- map at once (the Quest List's objective marks on the game's map show the
-- one zone open there). The places are MelloUI.QuestObjectives' (the
-- Companion's data, asked for at the map's first open that has a quest; the
-- places learned in game after it):
--   an area  (1.2.0; the user's look A of BuildData/output/animation_previews/
--            map_marks.html, shown here as on the game's map) the shape of an
--            objective's places, MelloUI.QuestAreas': a lone place a circle,
--            places near each other one smooth area, a gold edge with its
--            glow inside; on the canvas's root (world units: it pans and
--            zooms with the maps), one size on the screen at every zoom and
--            its edge in stretches of about SEG_PX (both again in zoom
--            steps), from a zone's zoom on; only the areas in and round the
--            view are drawn.
--            Objectives with the same places share one area
--   a mark   per loop of its area's edge, at the middle of its places, from a
--            zone's zoom on (objectives sharing the area side by side): the
--            objective's kind (the quest column's icons: kill, collect,
--            explore); its tooltip and its click the Quest List's own marks'
--            (the quest, the objective and its count, where it drops; a
--            waypoint there, Route's), a plain one without the Quest List
--   a dot    per place from the minimap ground's zoom on (the set's map_dot)
-- The motion (1.2.0, the same sketch; one-shot, Reduce Motion the end at
-- once): an area new this session drawn round from its marks as it first
-- comes in, its marks popped in, the nearest to you first; the pin under the
-- cursor lifts (MapPins, every pin) and an objective's mark lights its area,
-- the others stepping back; a lay of the log's change: a count up rings its
-- marks and swells its area, a done objective's marks get a tick and shrink
-- away (ghosts on the effects' layer), its area drawn back into them
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
--   Objectives.View()                the view moved (the areas' width, the ones in view)
--   Objectives.Hover(pin)            the pin under the cursor (an objective's lights its area)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Safe = MelloUI.Safe
local Plain, Finite, Secret = Safe.Value, Safe.Finite, Safe.IsSecret
local ipairs, pcall, type, wipe = ipairs, pcall, type, wipe

local Objectives = {}
ns.Objectives = Objectives

local T = {
	ORDER = { marks = 22, dots = 21, fx = 23 },   -- over the quest givers (20), under the quest column's marks (25)
	MARKS_FROM = 2.5,     -- the marks from a zone's zoom on (the givers' zoom: Layers.T.QUESTS_FROM)
	DOTS_FROM = 5,        -- the places' dots from a zone filling the view on (the zoom the minimap ground came at
	                      -- until 2026-10-21; kept: the dots belong to a zone's close look, painted or not)
	MARK_SIZE = 20,
	DOT_SIZE = 12,        -- the Quest List's DOT_PX
	WAIT = 0.5,           -- after the log's last change of a burst (a dozen on a turn-in)
	ICONS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\",
	KIND_ICON = { "kill", "pin_collect", "pin_collect", "obj_explore" },   -- QO's kinds: creature, object, item, area
	SEG_PX = 5,           -- (1.2.0) the areas' edge in stretches about this long on the screen
	SIDE_PX = 15,         -- marks of objectives sharing an area: this far either side of its middle
	POP_STEP = 0.007,     -- s a world unit from you before a new mark pops (a zone about 66 units), at most POP_MAX
	POP_MAX = 0.45,
	DIM = 0.35,           -- the other areas' alpha while a mark is hovered, their marks' DIM_MARK
	DIM_MARK = 0.55,
}
Objectives.T = T

local S = { canvas = nil, pins = nil, shown = false, asked = false, wait = nil, quests = {},
	-- (1.2.0) the areas: their holder and painter, this lay's groups (by shape), the shapes drawn this session, the
	-- counts, this lay's and the last lay's marks by objective, the ghosts to drive, the edge's zoom, the cull box's
	holder = nil, painter = nil, groups = {}, seen = {}, counts = {}, now = {}, last = {}, ghosts = {}, nghost = 0,
	live = false, k = nil, cuts = nil, hoverKey = nil, stride = nil }
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

-- (1.2.0) world yards to world units: the layers' own carrying (Layers.WorldPoint) at three points by a place, kept
-- by continent: { x0, y0, dx/dwx, dy/dwx, dx/dwy, dy/dwy }, or false (no answer there: asked again at the next one)
local carry = {}
local function Carry(cont, wx, wy)
	local a = carry[cont]
	if a then
		return a
	end
	local point = ns.Layers and ns.Layers.WorldPoint
	if not point then
		return false
	end
	local x0, y0 = point(cont, wx, wy)
	local x1, y1 = point(cont, wx + 50, wy)
	local x2, y2 = point(cont, wx, wy + 50)
	if not (x0 and y0 and x1 and y1 and x2 and y2) then
		return false
	end
	local ax, ay, bx, by = (x1 - x0) / 50, (y1 - y0) / 50, (x2 - x0) / 50, (y2 - y0) / 50
	a = { x0 - wx * ax - wy * bx, y0 - wx * ay - wy * by, ax, ay, bx, by }
	carry[cont] = a
	return a
end

local function At(a, x, y)
	return a[1] + a[3] * x + a[5] * y, a[2] + a[4] * x + a[6] * y
end

-- (1.2.0) the areas' holder: on the canvas's root, in world units (it pans and zooms with the maps, nothing of ours
-- runs for it), over the maps and under the pins; made with the first lay
local function Holder()
	local h = S.holder
	if not h then
		local root = S.canvas.root
		h = CreateFrame("Frame", nil, root)
		h:SetAllPoints(root)
		h:SetFrameLevel(root:GetFrameLevel() + ns.Pins.T.LEVEL - 1)
		h:EnableMouse(false)
		S.holder = h
		S.painter = MelloUI.QuestAreas.Painter(h, "ARTWORK")
	end
	return h
end

-- the areas one size on the screen (world units a pixel) and their edge in stretches of about SEG_PX, written again
-- when the zoom moved by a tenth; true when the stride changed (the areas laid again)
local function Width()
	local c = S.canvas
	if not (c.k1 and c.z) then
		return false   -- (no view yet: the window's first open lays it)
	end
	local k = c.k1 * c.z
	if k > 0 and not (S.k and math.abs(k - S.k) < S.k * 0.1) then
		S.k = k
		S.painter:Scale(1 / k)
		local stride = 1
		local g = S.groups[1]
		if g then
			-- (world units a STEP of yards: the continents' scales alike)
			local a, step = g.a, MelloUI.QuestAreas.T.STEP
			local px = math.sqrt((a[3] * step) ^ 2 + (a[4] * step) ^ 2) * k
			stride = px > 0 and math.max(1, math.ceil(T.SEG_PX / px)) or 1
		end
		if stride ~= S.stride then
			S.stride = stride
			return true
		end
	end
	return false
end

-- the areas in the view's cull box (and round it) drawn, the rest let go: at each lay and each new cull box; a new
-- one (never drawn before this session) drawn round from its marks as it first comes in
local function Areas()
	local painter, c = S.painter, S.canvas
	if not painter then
		return
	end
	Width()
	local stride = S.stride or 1
	local box = c.box
	painter:Begin()
	if box and box[1] then
		for _, g in ipairs(S.groups) do
			if g.x1 >= box[1] and g.x0 <= box[3] and g.y1 >= box[2] and g.y0 <= box[4] then
				local area = painter:Area(g.key, g.shape, g.project, stride)
				if g.fresh then
					g.fresh = false
					MelloUI.QuestAreas.TraceIn(area, MelloUI.QuestAreas.T.TRACE, g.delay or 0)
				end
			end
		end
	end
	painter:End()
	S.cuts = c.cuts
end

-- (1.2.0) a done objective's marks: a ghost of each on the effects' layer (its icon and a tick drawn over it), driven
-- once it is shown: the tick, a ring, then it shrinks away and goes
local TICK, ghostSpecs = nil, {}
local function GhostSpec(kind)
	local icon = T.KIND_ICON[kind] or "obj_explore"
	local spec = ghostSpecs[icon]
	if not spec then
		spec = { icon = T.ICONS .. icon, size = T.MARK_SIZE, sub = 3 }
		ghostSpecs[icon] = spec
	end
	return spec
end

local function TickLook(tex)
	local W = MelloUI.Widgets
	if W and W.Glyph then
		W.Glyph(tex, "check", 0.02)
	end
	if MelloUI.Painter and MelloUI.Painter.Paint then
		MelloUI.Painter.Paint(tex, "text", "vertex")
	end
end

local function GhostStep(g, v)
	local QT = MelloUI.QuestAreas.T
	local t = v * (QT.TICK + QT.HOLD + QT.GONE)
	local draw = math.min(1, t / QT.TICK)
	local tick = g.tick
	local W = MelloUI.Widgets
	if tick and tick.tex and tick.shown and W and W.Glyph then
		local p = draw < 0.02 and 0.02 or draw
		W.Glyph(tick.tex, "check", p)
		tick.tex:SetSize(T.MARK_SIZE * 0.7 * p, T.MARK_SIZE * 0.7)
	end
	local gone = math.max(0, math.min(1, (t - QT.TICK - QT.HOLD) / QT.GONE))
	if gone > 0 and not g.rung then
		g.rung = true
		S.pins:Ring(g)
	end
	if g.tex and g.shown then
		local s = T.MARK_SIZE * (1 - 0.7 * gone * gone)
		g.tex:SetSize(s, s)
		g.tex:SetAlpha(1 - gone)
	end
	if tick and tick.tex and tick.shown then
		tick.tex:SetAlpha(1 - gone)
	end
end

local function GhostDone(g)
	local pins = S.pins
	if g.tick then
		pins:Remove("objective_fx", g.tick.key)
	end
	pins:Remove("objective_fx", g.key)
end

local function Ghosts()
	local Anim = MelloUI.Anim
	local QT = MelloUI.QuestAreas.T
	for i = #S.ghosts, 1, -1 do
		local g = S.ghosts[i]
		S.ghosts[i] = nil
		if Anim and not Anim.reduceMotion and g.shown then
			Anim:Drive(g, GhostStep, QT.TICK + QT.HOLD + QT.GONE, "linear", GhostDone)
		else
			GhostDone(g)
		end
	end
end

-- the objectives gone since the lay before (a lay of the log's change while the map showed): a done one's marks get
-- their tick (its quest still in the log: a turned-in or dropped quest's simply go), its area drawn back into them
-- while no objective keeps it
local function Gone(live)
	local pins, painter = S.pins, S.painter
	if not live then
		return
	end
	local QA = MelloUI.QuestAreas
	local kept = {}
	for _, g in ipairs(S.groups) do
		kept[g.key] = true
	end
	for id, was in pairs(S.last) do
		if not S.now[id] then
			local ok, on = pcall(C_QuestLog.IsOnQuest, was.quest)
			for _, d in ipairs(was) do
				if ok and on == true then
					S.nghost = S.nghost + 1
					local g = pins:Set("objective_fx", "g" .. S.nghost, d[1], d[2], GhostSpec(d[4]))
					local tk = pins:Set("objective_fx", "t" .. S.nghost, d[1], d[2], TICK)
					if g and tk then
						g.dx, tk.dx, g.tick = d[3], d[3], tk
						S.ghosts[#S.ghosts + 1] = g
					end
				end
			end
			local area = painter and painter.areas[was.area]
			if area and not kept[was.area] and not area.hold then
				area.hold = true
				QA.TraceOut(area, QA.T.GONE, Objectives.AreaGone)
			end
		end
	end
end

function Objectives.AreaGone(area)
	area.hold = nil
	local painter = S.painter
	if painter.areas[area.key] == area and area.gen ~= painter.gen then
		MelloUI.QuestAreas.Release(painter, area)
	end
end

-- every open objective of the quests in the log, laid: its area (MelloUI.QuestAreas: the shape of its places; the
-- objectives with the same places one area), a mark a loop of its edge (objectives sharing it side by side), the dots
function Objectives.Lay()
	local pins = S.pins
	if not pins then
		return
	end
	pins:Clear("objectives")
	pins:Clear("objective_dots")
	S.wait = nil
	local live = S.live
	S.live = false
	S.last, S.now = S.now, S.last
	wipe(S.now)
	wipe(S.groups)
	S.k, S.cuts = nil, nil
	Holder()
	local layer = pins.layers.objectives
	local QO = MelloUI.QuestObjectives
	local QA = MelloUI.QuestAreas
	local list = (layer and layer.on) and LogQuests() or S.quests
	if layer and layer.on and #list > 0 and QO and QA and Objectives.Data() then
		local log = ns.QuestLog and ns.QuestLog.S
		local showing = log and log.showID
		local byShape, n = {}, 0
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
						local xs, ys, key = QA.Places(entry)
						local a = #xs > 0 and Carry(entry[4], xs[1], ys[1])
						local shape = a and QA.Shape(key, xs, ys)
						if shape then
							local g = byShape[shape]
							if not g then
								g = { key = key, shape = shape, a = a, objs = {} }
								byShape[shape] = g
								S.groups[#S.groups + 1] = g
								for i = 1, #xs do
									local x, y = At(a, xs[i], ys[i])
									n = n + 1
									pins:Set("objective_dots", n, x, y, DOT)
								end
							end
							g.objs[#g.objs + 1] = { questID, index, entry, t }
						end
					end
				end
			end
		end
		local mx0, my0
		if ns.Layers and ns.Layers.PlayerPoint then
			mx0, my0 = ns.Layers.PlayerPoint()
		end
		local now = GetTime()
		for _, g in ipairs(S.groups) do
			local a = g.a
			g.project = function(x, y)
				local wx, wy = At(a, x, y)
				return wx, -wy
			end
			-- its box in world units (the cull box's test)
			local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
			for _, loop in ipairs(g.shape.loops) do
				for i = 1, #loop - 1, 2 do
					local wx, wy = At(a, loop[i], loop[i + 1])
					if wx < x0 then x0 = wx end
					if wx > x1 then x1 = wx end
					if wy < y0 then y0 = wy end
					if wy > y1 then y1 = wy end
				end
			end
			g.x0, g.y0, g.x1, g.y1 = x0, y0, x1, y1
			g.fresh = not S.seen[g.key]
			S.seen[g.key] = true
			local delay
			-- each objective's count: up since the lay before (a lay of the log's change) -- once an objective
			local bumps = {}
			for j, o in ipairs(g.objs) do
				local id, t = o[1] * 100 + o[2], o[4]
				local have, before = t and t[7], S.counts[id]
				S.counts[id] = have
				bumps[j] = (live and have and before and have > before) and true or false
			end
			for mi, m in ipairs(g.shape.marks) do
				local wx, wy = At(a, m[1], m[2])
				local pop
				if g.fresh then
					local d = mx0 and math.sqrt((wx - mx0) ^ 2 + (wy - my0) ^ 2) or 0
					pop = math.min(T.POP_MAX, d * T.POP_STEP)
					delay = delay and math.min(delay, pop) or pop
				end
				for j, o in ipairs(g.objs) do
					local questID, index, entry, t = o[1], o[2], o[3], o[4]
					local pin = pins:Set("objectives", questID * 100000 + index * 1000 + mi, wx, wy, MarkSpec(entry[1]))
					if pin then
						local dx = (j - (#g.objs + 1) / 2) * 2 * T.SIDE_PX
						pin.dx = dx
						-- (the Quest List's mark data: its tooltip and its click take it as their own)
						local p = S.canvas:PlaceAt(wx, wy)
						local d = pin.data or {}
						d.questID, d.index, d.kind, d.name, d.line, d.area = questID, index, entry[1], entry[2], t, g.key
						d.mapID = p and p.id or nil
						d.x = p and (wx - p.left) / p.w or nil
						d.y = p and (wy - p.top) / p.h or nil
						pin.data = d
						-- the count up: a ring, its area swells
						local id = questID * 100 + index
						local bump = bumps[j]
						if bump then
							g.bump = true
						end
						if pop or bump then
							pin.moment = { pop = pop, ring = bump or nil, at = now }
						end
						local was = S.now[id]
						if not was then
							was = { area = g.key, quest = questID }
							S.now[id] = was
						end
						was[#was + 1] = { wx, wy, dx, entry[1] }
					end
				end
			end
			g.delay = delay or 0
		end
	end
	Gone(live)
	Areas()
	for _, g in ipairs(S.groups) do
		local area = g.bump and S.painter.areas[g.key]
		if area then
			QA.Swell(area)
		end
	end
	pins:Lay()
	Ghosts()
end

-- (Map.lua's canvas.onView) the view moved: the areas shown from the marks' zoom, their edge's width, the areas in
-- the new cull box
function Objectives.View()
	local c, h = S.canvas, S.holder
	if not (h and S.shown) then
		return
	end
	local layer = S.pins.layers.objectives
	local on = (layer and layer.on and (c.z or 0) >= T.MARKS_FROM) and true or false
	if h:IsShown() ~= on then
		h:SetShown(on)
	end
	if not on then
		return
	end
	if Width() or S.cuts ~= c.cuts then
		Areas()
	end
end

-- (Map.lua's PinTip) the pin under the cursor: an objective's mark lights its area, the other areas and their marks
-- step back; none: all back
function Objectives.Hover(pin)
	local data = pin and pin.layer and pin.layer.name == "objectives" and pin.data
	local key = data and data.area or nil
	local Anim = MelloUI.Anim
	if key == S.hoverKey or not Anim then
		return
	end
	S.hoverKey = key
	if S.painter then
		for _, area in pairs(S.painter.areas) do
			if not area.hold then
				Anim:To(area.frame, "alpha", (key == nil or area.key == key) and 1 or T.DIM, 0.15)
				Anim:To(area.glow, "alpha", (key ~= nil and area.key == key) and 1 or MelloUI.QuestAreas.T.GLOW_REST, 0.15)
			end
		end
	end
	local layer = S.pins and S.pins.layers.objectives
	for _, p in pairs(layer and layer.pins or {}) do
		if p ~= pin and p.tex and p.shown then
			Anim:To(p.tex, "alpha", (key == nil or (p.data and p.data.area == key)) and 1 or T.DIM_MARK, 0.15)
		end
	end
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
			S.live = true   -- (1.2.0: this lay moves what changed: progress, done objectives)
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
	pins:Layer("objective_fx", T.ORDER.fx, { minZ = T.MARKS_FROM })
	DOT = { icon = T.ICONS .. "map_dot", size = T.DOT_SIZE, sub = 0 }
	TICK = { icon = T.ICONS .. "map_dot", size = T.MARK_SIZE * 0.7, sub = 4, look = TickLook }
end

function Objectives.Open()
	S.shown = true
	Objectives.Lay()
	Objectives.View()
end

function Objectives.Close()
	S.shown = false
	S.wait = nil
	S.hoverKey = nil
	if S.pins then
		S.pins:Clear("objectives")
		S.pins:Clear("objective_dots")
		S.pins:Clear("objective_fx")
	end
	wipe(S.ghosts)
	if S.holder then
		S.holder:Hide()
	end
end


return Objectives

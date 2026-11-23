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
-- marks there. Only The Tracked Quests (the Quest List's setting) followed;
-- (2.1.68) Focused Quest Only too: the quest followed alone, while one is.
-- (2.1.0, qu-01: the user's pick W1 of BuildData/output/qu01_map_sketch) Zoomed
-- out, until a zone's zoom shows the marks, one pin a quest: an open one (the
-- tracker's "!") at the middle of its first open objective's places (the
-- middle of the densest half: a far place or two never drags it off), a done
-- one (the tracker's "?") at its turn-in (the Quest List's data); quests whose
-- pins touch become one with their count (MapPins' merge); a click shows the
-- quest (its page in the quest column, the map gliding to where it is done)
-- Laid at the map's open and half a second after the log's last change while
-- it shows (one flag, one wait: nothing made per event).
--
--   Objectives.Init(canvas, pins)    the layers (the window's first open)
--   Objectives.Open() / Close()      the window shown / hidden
--   Objectives.Soon()                the log changed: laid again on the beat, after the burst
--   Objectives.FocusChanged()        (2.1.68) another quest followed: Soon, while Focused Quest Only is on
--   Objectives.Tick(elapsed)         the window's beat
--   Objectives.Data()                the Companion's data, asked for once (the quest column's Show too)
--   Objectives.Lay()                 laid now (the tests)
--   Objectives.View()                the view moved (the areas' width, the ones in view)
--   Objectives.Hover(pin)            the pin under the cursor (an objective's lights its area)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Safe = MelloUI.Safe
local W = MelloUI.Widgets
local Plain, Finite, Secret = Safe.Value, Safe.Finite, Safe.IsSecret
local ipairs, pcall, type, wipe = ipairs, pcall, type, wipe
local floor = math.floor

local Objectives = {}
ns.Objectives = Objectives

local T = {
	-- over the quest givers (20), under the quest column's marks (25)
	ORDER = { marks = 22, dots = 21, fx = 23 },
	MARKS_FROM = 2.5,     -- the marks from a zone's zoom on (a zone's zoom)
	DOTS_FROM = 5,        -- the places' dots from a zone filling the view on (the zoom the minimap ground came at
	                      -- until 2026-10-21; kept: the dots belong to a zone's close look, painted or not)
	MARK_SIZE = 20,
	DOT_SIZE = 12,        -- the Quest List's DOT_PX
	WAIT = 0.5,           -- after the log's last change of a burst (a dozen on a turn-in)
	ICONS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\",
	KIND_ICON = MelloUI.QuestAreas.KIND_ICON,   -- QO's kinds: creature, object, item, area (the minimap's too)
	SEG_PX = 5,           -- (1.2.0) the areas' edge in stretches about this long on the screen
	SIDE_PX = 15,         -- marks of objectives sharing an area: this far either side of its middle
	POP_STEP = 0.007,     -- s a world unit from you before a new mark pops (a zone about 66 units), at most POP_MAX
	POP_MAX = 0.45,
	DIM = 0.35,           -- the other areas' alpha while a mark is hovered, their marks' DIM_MARK
	DIM_MARK = 0.55,
}
Objectives.T = T

local S = { canvas = nil, pins = nil, shown = false, asked = false, wait = nil, quests = {}, first = {},
	-- (1.2.0) the areas: their holder and painter, this lay's groups (by shape), the shapes drawn this session, the
	-- counts, this lay's and the last lay's marks by objective, the ghosts to drive, the edge's zoom, the cull box's
	holder = nil, painter = nil, groups = {}, seen = {}, counts = {}, now = {}, last = {}, ghosts = {}, nghost = 0, order = {},
	live = false, k = nil, cuts = nil, hoverKey = nil, stride = nil,
	-- (2.1.74) the complete quests shown (LogQuests: their turn-ins, the game's point of a quest Questie lacks)
	done = {} }
Objectives.S = S

local function QuestList()
	local QL = rawget(MelloUI, "QuestList")
	return (type(QL) == "table" and QL.M and QL.M.isEnabled) and QL or nil
end

-- (2.1.52, stage 2) the objectives' places are Questie's (Core/QuestSource.lua), and this map lays its own marks and
-- areas of them only in MelloUI's look: with Questie's switch off Questie's own objective icons show (MapAddonPins),
-- without Questie there are no quests at all
-- (a world without the quest source -- a test's: the places are whatever MelloUI.QuestObjectives hands out)
function Objectives.Data()
	local QS = MelloUI.QuestSource
	return QS == nil or QS.Look()
end

-- (2.1.68) Focused Quest Only: the one quest to mark (the Quest List's switch and its one reader, QL.Objectives.Focus:
-- the quest followed), or nil for every quest
local function Focus(QL)
	local O = QL and QL.Objectives
	return O and O.Focus and O.Focus() or nil
end

-- the quests in the log to show: not complete, not hidden, (Only The Tracked Quests) watched, or (Focused Quest Only)
-- the one followed. (2.1.52: the complete ones' turn-ins zoomed out, one pin a quest -- 2.1.0's Summary -- went: with
-- Questie the engine they never drew)
local function LogQuests()
	local out = S.quests
	wipe(out)
	wipe(S.done)   -- (2.1.74: the complete ones shown too, for the game's turn-in point of a quest Questie lacks)
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
		return out
	end
	local QL = QuestList()
	local trackedOnly = QL and QL.M.db and QL.M.db.objectiveTrackedOnly
	local focus = Focus(QL)
	local okN, n = pcall(C_QuestLog.GetNumQuestLogEntries)
	n = okN and Finite(n) or 0
	for i = 1, n do
		local ok, info = pcall(C_QuestLog.GetInfo, i)
		if ok and type(info) == "table" and not Plain(info.isHeader) and not Plain(info.isHidden) then
			local id = Finite(info.questID)
			local okC, complete = pcall(C_QuestLog.IsComplete, id)
			complete = okC and Plain(complete) and true or false
			if id and id > 0 then
				local watched = true
				if focus then
					watched = id == focus
				elseif trackedOnly and C_QuestLog.GetQuestWatchType then
					local okW, watch = pcall(C_QuestLog.GetQuestWatchType, id)
					watched = okW and not Secret(watch) and watch ~= nil
				end
				if watched and not complete then
					out[#out + 1] = id
				elseif watched then
					S.done[#S.done + 1] = id
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

-- (2.1.0; the user's pick P1 of qu05_polestar_sketch, 2026-10-31: "MelloUI's marks") the followed guide's goals the map
-- does not show yet (Route's guide bridges, Guide.goals: Polestar's step), as this map's own marks and areas: their
-- tooltip the guide's step, a click the guide's own aim there (Route follows the guide). A goal of a quest whose
-- objectives are laid here, or whose giver or ender the quest givers show, is shown already: nothing twice.
local NONE = {}

-- a mark's goals (one, or several at one place; a mark holding touching ones, MapPins' merge: all of theirs): the
-- first's words, the others' under them, then the step's lines (merged: a click zooms in)
local GUIDE_ZOOM = "Click: zoom in"
local function GuideTip(pin)
	local goals = {}
	for _, m in ipairs(pin.members or { pin }) do
		for _, goal in ipairs(m.data and type(m.data.guide) == "table" and m.data.guide or NONE) do
			goals[#goals + 1] = goal
		end
	end
	local first = goals[1]
	if type(first) ~= "table" then
		return nil
	end
	local lines = {}
	for i = 2, #goals do
		lines[#lines + 1] = goals[i].text
	end
	if pin.members then
		lines[#lines + 1] = first.lines and first.lines[1] or nil
		lines[#lines + 1] = GUIDE_ZOOM
	else
		for _, line in ipairs(first.lines or NONE) do
			lines[#lines + 1] = line
		end
	end
	return first.text, table.concat(lines, "\n")
end

local function GuideClick(pin, button)
	local goals = pin.data and pin.data.guide
	local first = type(goals) == "table" and goals[1]
	if button == "LeftButton" and type(first) == "table" and type(first.Aim) == "function" then
		pcall(first.Aim)
	end
end

local guideSpecs = {}
local function GuideSpec(kind)
	local icon = T.KIND_ICON[kind] or "obj_explore"
	local spec = guideSpecs[icon]
	if not spec then
		spec = { icon = T.ICONS .. icon, size = T.MARK_SIZE, tip = GuideTip, click = GuideClick, sub = 1, lift = icon }
		guideSpecs[icon] = spec
	end
	return spec
end

-- the followed guide's goals, nil without any
local function GuideGoals()
	local R = rawget(MelloUI, "Route")
	local G = type(R) == "table" and rawget(R, "Guide")
	local data = type(G) == "table" and G.goals
	return type(data) == "table" and type(data.goals) == "table" and #data.goals > 0 and data.goals or nil
end

-- (2.1.4) what this map shows of a quest, for other addons' pins of it (MapAddonPins: Questie's, nothing twice):
-- whether its objectives are laid here. (2.1.52: this map has no givers of its own any more -- Questie's are the
-- givers -- so GiversShown went)
function Objectives.Laid(q)
	return S.first[q] ~= nil
end

-- forward: (Lay) each guide goal not shown yet, in a group by its shape (a quest's own when the same); its dots
local GuideGroups

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

function GuideGroups(goals, byShape, n, QA)
	for _, goal in ipairs(goals or NONE) do
		local q, places = goal.quest, goal.places
		-- (a quest whose objectives this map lays: its objective and turn-in goals not twice)
		local shown = q and S.first[q] ~= nil and (goal.verb == "objective" or goal.verb == "turnin")
		if not shown and type(places) == "table" and #places >= 2 and goal.cont then
			-- (its places as the objective data's entry: kind, name, -, continent, x, y, ...)
			local entry = { goal.kind, goal.text, false, goal.cont }
			for k = 1, #places do
				entry[4 + k] = places[k]
			end
			local xs, ys, key = QA.Places(entry)
			local a = #xs > 0 and Carry(goal.cont, xs[1], ys[1])
			local shape = a and QA.Ask(key, xs, ys)
			if shape then
				local g = byShape[shape]
				if not g then
					g = QA.Keep({ key = key, shape = shape, a = a, objs = {} }, xs, ys, goal.cont)
					byShape[shape] = g
					S.groups[#S.groups + 1] = g
					for i = 1, #xs do
						local x, y = At(a, xs[i], ys[i])
						n = n + 1
						S.pins:Set("objective_dots", n, x, y, DOT)
					end
				end
				g.guide = g.guide or {}
				g.guide[#g.guide + 1] = goal
			end
		end
	end
	return n
end

-- (2.1.0) the middle value of a list (its median: a far place or two never drags it off the densest half)
local sorted = {}
local function Middle(list)
	wipe(sorted)
	for i = 1, #list do
		sorted[i] = list[i]
	end
	table.sort(sorted)
	return sorted[floor(#sorted / 2) + 1]
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

-- (2.1.50; Nixxen's report: Redridge with many quests -- the map froze as it opened and drew grey at its middle
-- zooms; 13 quests made 15,324 lines and dabs in the simulator, each area drawn whole however little of it showed)
-- only what can show: each area's edge clipped to the cull box (the view and CULL_MARGIN round it, cut again before
-- the view reaches its side: a stretch with both ends off one side of it left out), each glow dab kept to it. Every
-- piece in it drawn as before: no stretch longer, no glow left out (the user, 2026-11-12: "I dont want any quality
-- loss or glow loss"). The areas are in world units, y flipped (the groups' project)
local function ViewClip(ax, ay, bx, by)
	local b = S.canvas.box
	if (ax < b[1] and bx < b[1]) or (ax > b[3] and bx > b[3]) or (-ay < b[2] and -by < b[2]) or (-ay > b[4] and -by > b[4]) then
		return nil
	end
	return ax, ay, bx, by
end

-- (2.1.50) the areas by their distance from the view's middle (g.dist)
local function NearFirst(a, b)
	if a.dist ~= b.dist then
		return a.dist < b.dist
	end
	return a.key < b.key
end

local function ViewFits(x, y, r)
	local b = S.canvas.box
	return x + r >= b[1] and x - r <= b[3] and -y + r >= b[2] and -y - r <= b[4]
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
		local QA = MelloUI.QuestAreas
		-- (2.1.43) the groups and the joined outlines: a joined group's own area kept out of sight but while one of its
		-- marks is hovered (QA.Lit). (2.1.50) the nearest the view's middle first: past the painter's cap the farthest
		-- wait for the view to come nearer
		local order, mx, my = S.order, c.cx or 0, c.cy or 0
		wipe(order)
		for _, list in ipairs({ S.groups, S.joins or NONE }) do
			for _, g in ipairs(list) do
				if g.x1 >= box[1] and g.x0 <= box[3] and g.y1 >= box[2] and g.y0 <= box[4] then
					local dx, dy = (g.x0 + g.x1) / 2 - mx, (g.y0 + g.y1) / 2 - my
					g.dist = dx * dx + dy * dy
					order[#order + 1] = g
				end
			end
		end
		table.sort(order, NearFirst)
		for _, g in ipairs(order) do
			local area = painter:Area(g.key, g.shape, g.project, stride, ViewClip, nil, ViewFits, g.role)
			area.role = g.role
			QA.Rest(area, S.hoverKey, T.DIM)
			if g.fresh and not area.capped then
				g.fresh = false
				QA.TraceIn(area, QA.T.TRACE, g.delay or 0)
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
--------------------------------------------------------------------------------
-- (2.1.74) The game's own places (docs/plans/game-quest-areas.md; the user, 2026-11-23 in Riverglades: "why cant
-- we in those cases just use the blizzards own map areas and quest locations and just skin them in MelloUI Style?",
-- then look A of BuildData/output/game_quest_areas_sketch): a quest in the log Questie has no places for gets its
-- areas from the game -- traced into places of the data's own shape (MelloUI.QuestObjectives.Traced: QO.Of hands
-- them out), so they are laid above as Questie's, MelloUI's areas and marks (no dots: .game) -- and, while they are
-- being traced or where the game draws none, MelloUI's mark at the game's point for it (QO.Game: its first open
-- objective's kind); complete, the turn-in mark there
--------------------------------------------------------------------------------
T.TURNIN = "turnin_mark"
local TEXT = { ready = "Ready to turn in" }

-- its tooltip: the quest, then its open lines (the game's own words), or that it is ready to turn in
local function GameTip(tooltip, pin)
	local d = pin.data
	local okT, title = pcall(C_QuestLog.GetTitleForQuestID, d.questID)
	tooltip:SetText(okT and Safe.Text(title) or "")
	if d.done then
		tooltip:AddLine(W.Tr(TEXT.ready), 1, 1, 1, true)
		return
	end
	local QO = MelloUI.QuestObjectives
	local lines = QO and QO.Lines and QO.Lines(d.questID)
	for _, t in ipairs(type(lines) == "table" and lines or NONE) do
		if not t[2] and t[6] then
			tooltip:AddLine(t[6], 1, 1, 1, true)
		end
	end
end

local gameSpecs = {}
local function GameSpec(kind, done)
	local icon = done and T.TURNIN or T.KIND_ICON[kind] or "obj_explore"
	local spec = gameSpecs[icon]
	if not spec then
		spec = { icon = T.ICONS .. icon, size = T.MARK_SIZE, fillTip = GameTip, click = MarkClick, sub = 1, lift = icon }
		gameSpecs[icon] = spec
	end
	return spec
end

-- the quests Questie has no places for and the game draws no area of yet (or none): their marks at the game's points
local function Game(on)
	local QO = MelloUI.QuestObjectives
	if not (on and QO and QO.Game and Objectives.Data()) then
		return
	end
	local pins = S.pins
	for pass = 1, 2 do
		local done = pass == 2
		for _, questID in ipairs(done and S.done or S.quests) do
			local map, x, y, kind = QO.Game(questID, done)
			local pin = map and pins:SetAt("objectives", "game:" .. questID, map, x, y, GameSpec(kind, done))
			if pin then
				local d = pin.data or {}
				d.questID, d.game, d.done, d.kind, d.mapID, d.x, d.y = questID, true, done, kind, map, x, y
				pin.data = d
			end
		end
	end
end
Objectives.Game = Game   -- (the tests' way in)

function Objectives.Lay()
	local pins = S.pins
	if not pins then
		return
	end
	pins:Clear("objectives")
	pins:Clear("objective_guide")
	pins:Clear("objective_dots")
	wipe(S.first)
	S.wait = nil
	local live = S.live
	S.live = false
	S.last, S.now = S.now, S.last
	wipe(S.now)
	wipe(S.groups)
	S.joins = NONE
	S.k, S.cuts = nil, nil
	Holder()
	local layer = pins.layers.objectives
	local QO = MelloUI.QuestObjectives
	local QA = MelloUI.QuestAreas
	local list = (layer and layer.on) and LogQuests() or S.quests
	-- (2.1.0) the followed guide's goals: laid with the quests' (GuideGroups), with no quest in the log too
	local guide = layer and layer.on and QA and GuideGoals() or nil
	local quests = (layer and layer.on and #list > 0 and QO and QA and Objectives.Data()) and list or NONE
	if #quests > 0 or guide then
		local log = ns.QuestLog and ns.QuestLog.S
		local showing = log and log.showID
		local byShape, n = {}, 0
		for _, questID in ipairs(quests) do
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
						-- (2.1.0) the quest's pin zoomed out: the middle of its first open objective's places
						if a and not S.first[questID] then
							local mx, my = At(a, Middle(xs), Middle(ys))
							S.first[questID] = { mx, my, index }
						end
						-- (2.1.50) a shape still being built: laid when it is ready ("questareas:ready")
						local shape = a and QA.Ask(key, xs, ys)
						if shape then
							local g = byShape[shape]
							if not g then
								g = QA.Keep({ key = key, shape = shape, a = a, objs = {} }, xs, ys, entry[4])
								byShape[shape] = g
								S.groups[#S.groups + 1] = g
								for i = 1, entry.game and 0 or #xs do   -- (2.1.74: the game's traced places, no dots)
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
		GuideGroups(guide, byShape, n, QA)
		-- (2.1.43, the user's pick B) the areas that touch: one outline at rest (QA.Join)
		S.joins = QA.Join(S.groups)
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
				-- (2.1.0) the followed guide's goals in this area (GuideGroups): one mark, beside the quests' marks, on
				-- a layer of its own whose touching marks merge (MapPins: zoomed in, they part; a click on one zooms in)
				local goals = g.guide
				if goals then
					local pin = pins:Set("objective_guide", "guide:" .. tostring(goals[1].key) .. ":" .. mi, wx, wy,
						GuideSpec(goals[1].kind))
					if pin then
						pin.dx = #g.objs > 0 and (#g.objs + 1 - (#g.objs + 2) / 2) * 2 * T.SIDE_PX or 0
						local d = pin.data or {}
						d.guide, d.area = goals, g.key
						pin.data = d
						if pop then
							pin.moment = { pop = pop, at = now }
						end
					end
				end
			end
			g.delay = delay or 0
		end
		-- each joined outline: in the world as its first member's continent, its box, drawn round with the earliest
		for _, j in ipairs(S.joins) do
			local a = j.members[1].a
			j.a = a
			j.project = function(x, y)
				local wx, wy = At(a, x, y)
				return wx, -wy
			end
			local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
			for _, loop in ipairs(j.shape.loops) do
				for i = 1, #loop - 1, 2 do
					local wx, wy = At(a, loop[i], loop[i + 1])
					if wx < x0 then x0 = wx end
					if wx > x1 then x1 = wx end
					if wy < y0 then y0 = wy end
					if wy > y1 then y1 = wy end
				end
			end
			j.x0, j.y0, j.x1, j.y1 = x0, y0, x1, y1
			j.fresh = not S.seen[j.key]
			S.seen[j.key] = true
			local delay = math.huge
			for _, g in ipairs(j.members) do
				delay = math.min(delay, g.delay or 0)
			end
			j.delay = delay < math.huge and delay or 0
		end
	end
	Gone(live)
	Areas()
	Game(layer and layer.on)   -- (2.1.74: the quests Questie lacks, the game's own areas and points)
	for _, g in ipairs(S.groups) do
		local area = g.bump and S.painter.areas[(g.join or g).key]   -- (a joined one's: its outline swells)
		if area then
			QA.Swell(area)
		end
	end
	pins:Lay()
	Ghosts()
	-- (2.1.4) other addons' pins of these quests looked at again (Questie's: nothing twice)
	local AP = ns.AddonPins
	if AP and AP.Recheck then
		AP.Recheck()
	end
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
	local name = pin and pin.layer and pin.layer.name
	local data = (name == "objectives" or name == "objective_guide") and pin.data
	local key = data and data.area or nil
	local Anim = MelloUI.Anim
	if key == S.hoverKey or not Anim then
		return
	end
	S.hoverKey = key
	if S.painter then
		local QA = MelloUI.QuestAreas
		for _, area in pairs(S.painter.areas) do
			if not area.hold then
				-- (2.1.43) a joined objective's own area shown lit inside its outline, the outline stepped back (QA.Lit)
				QA.Fade(area, key, T.DIM, 0.15)
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

-- (2.1.68; Map.lua's SUPER_TRACKING_CHANGED while the map shows) another quest followed: laid again on the beat while
-- Focused Quest Only is on (its quest is the one marked); with it off nothing changes
function Objectives.FocusChanged()
	local QL = QuestList()
	if QL and QL.M.db and QL.M.db.objectiveFocusedOnly then
		Objectives.Soon()
	end
end

-- (2.1.70; the user, 2026-11-22, of the Quest List's Map rows: "these options dont do anything on the map") one of the
-- Quest List's marks settings changed while this map shows: laid again on the beat. Before, only the game's zone map
-- and the minimap were told (the Quest List's own OnSettingChanged); this map took the change at its next open or the
-- log's next change. A bus listener at load (no frame); nothing while the map is closed (Soon: S.shown)
Objectives.QL_KEYS = { objectiveMarks = true, objectiveTrackedOnly = true, objectiveFocusedOnly = true }
function Objectives.OnSetting(module, key)
	if module == "QuestList" and Objectives.QL_KEYS[key] then
		Objectives.Soon()
	end
end
MelloUI:On("setting", Objectives.OnSetting, "Map: the Quest List's objective marks settings")

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
	-- (2.1.0) the followed guide's goals: its own, touching marks merged with their count
	pins:Layer("objective_guide", T.ORDER.marks, { minZ = T.MARKS_FROM, merge = T.MARK_SIZE })
	-- (2.1.50) the places' dots the first to wait past the map's icon cap (MapPins: the most of them, the least needed)
	pins:Layer("objective_dots", T.ORDER.dots, { minZ = T.DOTS_FROM, priority = 1 })
	pins:Layer("objective_fx", T.ORDER.fx, { minZ = T.MARKS_FROM })
	DOT = { icon = T.ICONS .. "map_dot", size = T.DOT_SIZE, sub = 0 }
	TICK = { icon = T.ICONS .. "map_dot", size = T.MARK_SIZE * 0.7, sub = 4, look = TickLook }
	-- (2.1.0) the followed guide's goals changed (Route's guide bridges): laid again on the beat, as for the log;
	-- (2.1.50) a quest area built across frames is ready (MelloUI.QuestAreas): the same
	if MelloUI.On then
		MelloUI:On("questareas:ready", function()
			if S.shown then
				Objectives.Soon()
			end
		end, "Map: quest areas ready")
		MelloUI:On("guidegoals", function()
			if S.shown then
				Objectives.Soon()
			end
		end, "Map: a guide's goals")
	end
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
		S.pins:Clear("objective_guide")
		S.pins:Clear("objective_dots")
		S.pins:Clear("objective_fx")
	end
	wipe(S.ghosts)
	if S.holder then
		S.holder:Hide()
	end
end


return Objectives

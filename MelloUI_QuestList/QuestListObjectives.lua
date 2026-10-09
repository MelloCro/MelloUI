--------------------------------------------------------------------------------
-- MelloUI - Quest List: objective marks (0.19.5)
--
-- Where the quests in your log are done, on the zone map (the user,
-- 2026-10-06, of Questie and Carbonite: each objective's places shown; their
-- pick: C's behaviour with D's marks of BuildData/output/objective_marks_
-- sketch). For each quest in the log that is not complete, each objective not
-- done yet that has places on the open zone map (MelloUI.QuestObjectives, the
-- Companion's data: asked for with the map's first refresh that has a quest
-- to show, as Route asks for it when it routes):
--   its area   the places in groups (a place joins a group when it lies
--              within REACH of one of its places): a thin outline round each
--              group in the palette's trim on a darker line, and a faint fill
--              (soft spots at FILL_ALPHA: the map's own names read through),
--              drawn on the map's canvas, so they pan and zoom with it
--   its spots  zoomed in (the map's zoom past ZOOMED), a dot per place in the
--              place of the area: a pale gold dot in a black ring (one
--              texture, Media/Textures/MapDot: Tools/make_widget_art.py),
--              DOT_PX on the screen at every zoom (the user, 2026-10-06: the
--              soft spots were "very hard to see"; the sketch's dots); the
--              area and its outline zoomed out only (O.Zoom, on the map's
--              zoom: its zoom percent and canvas scale, read only)
--   its mark   one mark per group (the Quest List's marks, kind "objective":
--              one size on the screen at every zoom): the objective's kind
--              (sword: kill, bag: collect, cog: use, flag: explore) on the
--              palette's dark disc with its progress under it ("4/8"), at
--              the group's middle moved clear of the giver marks and of each
--              other; hover: the quest, the objective and its progress, what
--              drops it and how often; click: a waypoint there (Route's)
-- A done objective shows nothing; a done quest only its hand-in "?" (the
-- giver marks). Laid with the giver marks on the map's refresh and on the
-- log's changes while the map shows; nothing per frame, nothing at login.
-- The minimap (step 2, below): the same marks near you, drawn in Route's
-- minimap layer (Route.WantMinimap: one minimap system).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local QL = ns.QuestList
local Finite = MelloUI.Safe.Finite
local Secret = MelloUI.Safe.IsSecret

local O = { tex = {}, ntex = 0, lines = {}, nlines = 0, asked = false,
	dots = {}, ndots = 0, zoomedIn = nil }
QL.Objectives = O

local REACH = 0.06              -- map widths: a place this close to a group's place is in it
local PAD = 0.012               -- map widths the outline keeps round a group's places
local FILL_SIZE = 0.05          -- a fill spot, in map widths
local FILL_ALPHA = 0.08
local DOT_PX = 10               -- a place's dot on the screen
local MAP_DOT = "Interface\\AddOns\\MelloUI\\Media\\Textures\\MapDot"   -- a white dot in a black ring (the white takes the tint)
local ZOOMED = 0.5              -- the map's zoom percent from which the places show as dots, the areas go
local LINE = 2                  -- the outline, in canvas units (the dark line under it a little wider)
local NEAR = 0.024              -- map units: a mark closer than this to another is moved
local SOFT = "Interface\\AddOns\\MelloUI\\Media\\Textures\\SoftGlowRound"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- (a plain disc: the mark's ring and its dark ground)
local GLYPH = { [1] = "sword", [2] = "cog", [3] = "bag", [4] = "flag" }   -- by the data's kind

-- The quests in the log to show: not complete, and (Only The Tracked Quests)
-- watched; their ids in a list made once and reused
local quests = {}
local function LogQuests(trackedOnly)
	wipe(quests)
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
		return quests
	end
	local okN, n = pcall(C_QuestLog.GetNumQuestLogEntries)
	n = okN and QL.Plain(n) or 0
	for i = 1, type(n) == "number" and n or 0 do
		local ok, info = pcall(C_QuestLog.GetInfo, i)
		if ok and type(info) == "table" and not QL.Plain(info.isHeader) and not QL.Plain(info.isHidden) then
			local id = QL.Plain(info.questID)
			if type(id) == "number" and id > 0 and not QL.IsReadyForTurnIn(id) then
				local watched = true
				if trackedOnly and C_QuestLog.GetQuestWatchType then
					local okW, watch = pcall(C_QuestLog.GetQuestWatchType, id)
					watched = okW and not Secret(watch) and watch ~= nil
				end
				if watched then
					quests[#quests + 1] = id
				end
			end
		end
	end
	return quests
end

-- The data, loaded with the first map that has a quest to show (once a
-- session: a refusal is the Companion's own notice)
local function DataReady()
	if MelloUI_QuestObjectiveData then
		return true
	end
	if O.asked or not MelloUI.LoadCompanion then
		return false
	end
	O.asked = true
	local ok = MelloUI:LoadCompanion()
	return ok and MelloUI_QuestObjectiveData ~= nil
end

-- A world place on the map shown: x, y in 0..1, or nil
local function OnMap(mapID, cont, wx, wy)
	if not (C_Map.GetMapPosFromWorldPos and CreateVector2D) then
		return nil
	end
	local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(wx, wy), mapID)
	if not ok then
		return nil
	end
	local x, y = QL.VectorXY(pos)
	x, y = Finite(x), Finite(y)
	if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
		return x, y
	end
	return nil
end

-- The places as groups: single linkage within REACH (a few dozen places a
-- quest at most: the data keeps 30 an objective)
local function Groups(xs, ys, reach)
	reach = reach or REACH
	local group, n = {}, #xs
	for i = 1, n do
		group[i] = i
	end
	local function Root(i)
		while group[i] ~= i do
			group[i] = group[group[i]]
			i = group[i]
		end
		return i
	end
	for i = 1, n do
		for j = i + 1, n do
			local dx, dy = xs[i] - xs[j], ys[i] - ys[j]
			if dx * dx + dy * dy <= reach * reach then
				group[Root(j)] = Root(i)
			end
		end
	end
	local out, at = {}, {}
	for i = 1, n do
		local r = Root(i)
		local g = at[r]
		if not g then
			g = {}
			at[r] = g
			out[#out + 1] = g
		end
		g[#g + 1] = i
	end
	return out
end

-- The convex hull of a group's places (Andrew's monotone chain), moved out by
-- PAD from its middle: a list of x, y pairs, or nil under three places
local function Hull(xs, ys, members, cx, cy)
	if #members < 3 then
		return nil
	end
	local pts = {}
	for _, i in ipairs(members) do
		pts[#pts + 1] = { xs[i], ys[i] }
	end
	table.sort(pts, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
	local function Cross(o, a, b)
		return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
	end
	local hull = {}
	for _, p in ipairs(pts) do
		while #hull >= 2 and Cross(hull[#hull - 1], hull[#hull], p) <= 0 do
			hull[#hull] = nil
		end
		hull[#hull + 1] = p
	end
	local lower = #hull + 1
	for i = #pts - 1, 1, -1 do
		local p = pts[i]
		while #hull >= lower and Cross(hull[#hull - 1], hull[#hull], p) <= 0 do
			hull[#hull] = nil
		end
		hull[#hull + 1] = p
	end
	hull[#hull] = nil
	if #hull < 3 then
		return nil
	end
	for _, p in ipairs(hull) do
		local dx, dy = p[1] - cx, p[2] - cy
		local d = math.sqrt(dx * dx + dy * dy)
		if d > 0 then
			p[1], p[2] = p[1] + dx / d * PAD, p[2] + dy / d * PAD
		end
	end
	return hull
end

-- The areas' layer: one frame on the canvas (it pans and zooms with it; no
-- frames for the navigation to walk), just above the map's own art and
-- under its pins, as Route's trail (Route.LayerAboveArt: one rule for both).
-- On the canvas itself the map's tiles, frames of their own, drew over the
-- areas (0.19.5, the user's first look).
function O.Layer(canvas)
	local f = O.layer
	if not f then
		f = CreateFrame("Frame", nil, canvas)
		f:SetAllPoints(canvas)
		f:EnableMouse(false)
		O.layer = f
	end
	local R = MelloUI.Route
	if R and R.LayerAboveArt then
		R.LayerAboveArt(f, canvas)
	end
	return f
end

-- the layer's regions, kept and reused
local function Tex(layer)
	local n = O.ntex + 1
	O.ntex = n
	local t = O.tex[n]
	if not t then
		t = layer:CreateTexture(nil, "BORDER")
		O.tex[n] = t
	end
	return t
end

local function CanvasLine(layer)
	local n = O.nlines + 1
	O.nlines = n
	local l = O.lines[n]
	if not l and layer.CreateLine then
		l = layer:CreateLine(nil, "BORDER")
		O.lines[n] = l
	end
	return l
end

function O.Clear()
	for i = 1, O.ntex do
		O.tex[i]:Hide()
	end
	for i = 1, O.nlines do
		O.lines[i]:Hide()
	end
	for i = 1, O.ndots do
		O.dots[i]:Hide()
	end
	O.ntex, O.nlines, O.ndots, O.zoomedIn = 0, 0, 0, nil
end

-- a place's dot: the palette's pale gold (its text) in the texture's black
-- ring (the user, 2026-10-06: "colored dots with black outline"; one piece,
-- crisp at its size: two round masks stacked came out blurred), on the layer
-- at the place (sized and shown by O.Zoom)
local function Dot(layer, W, H, x, y, fill)
	local n = O.ndots + 1
	O.ndots = n
	local dot = O.dots[n]
	if not dot then
		dot = layer:CreateTexture(nil, "ARTWORK", nil, 1)
		dot:SetTexture(MAP_DOT)
		O.dots[n] = dot
	end
	dot:SetVertexColor(fill[1], fill[2], fill[3], 1)
	dot:ClearAllPoints()
	dot:SetPoint("CENTER", layer, "TOPLEFT", x * W, -y * H)
end

-- The map's zoom: zoomed out the areas (fill and outline), zoomed in the
-- dots, DOT_PX on the screen (the canvas's units: DOT_PX / its scale, as
-- Route's trail); the shown state written only when it changes, the dots'
-- size at every step of a zoom
function O.Zoom(map)
	if not map then
		return
	end
	local okZ, z = pcall(map.GetCanvasZoomPercent, map)
	local okS, s = pcall(map.GetCanvasScale, map)
	z, s = okZ and Finite(z) or nil, okS and Finite(s) or nil
	local zoomedIn = (z and z >= ZOOMED) and true or false
	if zoomedIn ~= O.zoomedIn then
		O.zoomedIn = zoomedIn
		for i = 1, O.ntex do
			O.tex[i]:SetShown(not zoomedIn)
		end
		for i = 1, O.nlines do
			O.lines[i]:SetShown(not zoomedIn)
		end
		for i = 1, O.ndots do
			O.dots[i]:SetShown(zoomedIn)
		end
	end
	if zoomedIn and s and s > 0 then
		local size = DOT_PX / s
		for i = 1, O.ndots do
			O.dots[i]:SetSize(size, size)
		end
	end
end

local function Spot(canvas, W, H, x, y, size, r, g, b, a)
	local t = Tex(canvas)
	t:SetTexture(SOFT)
	t:SetVertexColor(r, g, b, a)
	t:SetSize(size * W, size * W)
	t:ClearAllPoints()
	t:SetPoint("CENTER", canvas, "TOPLEFT", x * W, -y * H)
	t:Show()
end

local function Edge(canvas, W, H, x1, y1, x2, y2, width, r, g, b, a)
	local l = CanvasLine(canvas)
	if not l then
		return
	end
	l:SetColorTexture(r, g, b, a)
	l:SetThickness(width)
	l:SetStartPoint("TOPLEFT", canvas, x1 * W, -y1 * H)
	l:SetEndPoint("TOPLEFT", canvas, x2 * W, -y2 * H)
	l:Show()
end

-- a mark's spot moved clear of the marks laid so far (givers first): down,
-- right, up, left in turn, a little further each round
local placed = {}
local function Clear(x, y)
	local function Free(px, py)
		for _, m in ipairs(placed) do
			local dx, dy = px - m[1], py - m[2]
			if dx * dx + dy * dy < NEAR * NEAR then
				return false
			end
		end
		return true
	end
	if Free(x, y) then
		return x, y
	end
	for round = 1, 4 do
		local d = NEAR * round
		for _, o in ipairs({ { 0, d }, { d, 0 }, { 0, -d }, { -d, 0 } }) do
			if Free(x + o[1], y + o[2]) then
				return x + o[1], y + o[2]
			end
		end
	end
	return x, y
end

-- Each open objective of a quest with places: fn(index, entry, line) -- an
-- objective done shows nothing; one no line names shows only when no line
-- named any (another language: every place rather than none) or when it is
-- an area to explore (the zone map's marks and the minimap's alike)
local function EachOpen(questID, fn)
	local QO = MelloUI.QuestObjectives
	local data = QO.Of(questID)
	if not data then
		return
	end
	local lines = QO.Lines(questID)
	local itemLine = QO.ItemLine(data, lines)
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
			fn(index, entry, t)
		end
	end
end

-- The objective marks of the zone map shown (QL.Provider:LayPins, after the
-- givers: their marks are in Marks.list already)
function O.Add(map, mapID)
	O.Clear()
	local list = LogQuests(QL.M.db.objectiveTrackedOnly)
	if #list == 0 or not DataReady() then
		return
	end
	local canvas = map:GetCanvas()
	local W, H = QL.Plain(canvas:GetWidth()), QL.Plain(canvas:GetHeight())
	if not (Finite(W) and Finite(H) and W > 0 and H > 0) then
		return
	end
	canvas = O.Layer(canvas)   -- (the areas drawn on their layer, the same size as the canvas)
	local palette = MelloUI.Look.Palette("questList")
	local trim, under = palette.trim, palette.mainWindow
	wipe(placed)
	for _, m in ipairs(QL.MarkList()) do
		if m.x and m.y then
			placed[#placed + 1] = { m.x, m.y }
		end
	end
	for _, questID in ipairs(list) do
		EachOpen(questID, function(index, entry, t)
			local xs, ys = {}, {}
			for k = 5, #entry - 1, 2 do
				local x, y = OnMap(mapID, entry[4], entry[k], entry[k + 1])
				if x then
					xs[#xs + 1], ys[#ys + 1] = x, y
				end
			end
			for _, members in ipairs(Groups(xs, ys)) do
				local cx, cy = 0, 0
				for _, i in ipairs(members) do
					cx, cy = cx + xs[i], cy + ys[i]
					Spot(canvas, W, H, xs[i], ys[i], FILL_SIZE, trim[1], trim[2], trim[3], FILL_ALPHA)
					Dot(canvas, W, H, xs[i], ys[i], palette.text)
				end
				cx, cy = cx / #members, cy / #members
				local hull = Hull(xs, ys, members, cx, cy)
				if hull then
					for pass = 1, 2 do
						for i = 1, #hull do
							local a, b = hull[i], hull[i % #hull + 1]
							if pass == 1 then
								Edge(canvas, W, H, a[1], a[2], b[1], b[2], LINE + 1.5, under[1], under[2], under[3], 0.55)
							else
								Edge(canvas, W, H, a[1], a[2], b[1], b[2], LINE, trim[1], trim[2], trim[3], 0.9)
							end
						end
					end
				end
				local mx, my = Clear(cx, cy)
				placed[#placed + 1] = { mx, my }
				QL.Marks.Add("objective", { x = mx, y = my, questID = questID, index = index, kind = entry[1],
					name = entry[2], line = t, mapID = mapID })
			end
		end)
	end
	O.Zoom(map)   -- (the areas or the dots, as the map is zoomed now)
end

-- the mark's look: its kind on the palette's dark disc in its gold ring (the
-- goal's mark of Route: one look), its progress under it
function O.Dress(b, data)
	local palette = MelloUI.Look.Palette("questList")
	local ground, ink, gold = palette.innerPanel, palette.text, palette.selectedTrim
	b:SetSize(20, 20)
	local ring = b.Ring
	if not ring then
		ring = b:CreateTexture(nil, "BACKGROUND", nil, -1)
		ring:SetTexture(ROUND)
		ring:SetAllPoints(b)
		b.Ring = ring
	end
	ring:SetVertexColor(gold[1], gold[2], gold[3], 1)
	ring:Show()
	b.Bg:Show()
	b.Bg:SetTexture(ROUND)
	b.Bg:ClearAllPoints()
	b.Bg:SetPoint("TOPLEFT", b, "TOPLEFT", 1.6, -1.6)
	b.Bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1.6, 1.6)
	b.Bg:SetVertexColor(ground[1], ground[2], ground[3], 0.95)
	b.Icon:ClearAllPoints()
	b.Icon:SetPoint("CENTER")
	b.Icon:SetSize(12, 12)
	b.Icon:SetDesaturated(false)
	b.Icon:SetAlpha(1)
	if not MelloUI.Widgets.Glyph(b.Icon, GLYPH[data.kind] or "way") then
		MelloUI.Widgets.Glyph(b.Icon, "way")
	end
	b.Icon:SetVertexColor(ink[1], ink[2], ink[3], 1)
	b.Icon:Show()
	local t = data.line
	local have, need = t and t[7], t and t[8]
	b.Label:ClearAllPoints()
	b.Label:SetPoint("TOP", b, "BOTTOM", 0, 1)
	if need and need > 1 then
		b.Label:SetText(string.format("%d/%d", have or 0, need))
		b.Label:SetTextColor(gold[1], gold[2], gold[3], 1)
		b.Label:Show()
	else
		b.Label:Hide()
	end
end

-- "about 1 in 3" from a drop chance in percent
local function Chance(pct)
	if not pct or pct <= 0 or pct >= 95 then
		return nil
	end
	return string.format("about 1 in %d", math.max(2, math.floor(100 / pct + 0.5)))
end

local FROM = { "From", "In", "Sold by" }   -- a creature drops it, an object holds it, a vendor sells it

-- the mark's tooltip (QuestListMap's MarkEnter, kind "objective")
function O.Tip(tip, data, Line)
	local row = QL.RowByID()[data.questID]
	QL.TipTitle(tip, row and row[QL.F_TITLE] or data.name)
	local t = data.line
	Line(tip, (t and t[6]) or data.name, "text")
	local sources = MelloUI.QuestObjectives.Sources(data.questID)
	for _, s in ipairs(sources and sources[data.index] or {}) do
		local levels = s[3] > 0 and (s[3] == s[4] and string.format(" (level %d)", s[3])
			or string.format(" (level %d-%d)", s[3], s[4])) or ""
		local chance = Chance(s[5])
		Line(tip, string.format("%s %s%s%s", FROM[s[1]] or "From", s[2], levels, chance and (", " .. chance) or ""), "text", true)
	end
	Line(tip, "Click to set a waypoint here.", "pinHint")
end

-- the mark's click: a waypoint (Route's, when it is on) at the mark
function O.Click(data)
	local set, chimed = QL.RouteToPoint(data.mapID, data.x, data.y, data.name)
	if set and not chimed then
		MelloUI:PlayUISound("waypoint_set")
	end
end

-- The log's progress while the map shows: the marks laid again once, half a
-- second after the last QUEST_LOG_UPDATE of a burst (a dozen on a turn-in);
-- one function and one flag, nothing made per event
local queued = false
local function Relay()
	queued = false
	QL.RefreshPins()
end

function O.LogChanged()
	O.MiniSoon()
	if queued or not (QL.M.isEnabled and QL.M.db.objectiveMarks and WorldMapFrame and WorldMapFrame:IsShown()) then
		return
	end
	queued = true
	C_Timer.After(0.5, Relay)
end

--------------------------------------------------------------------------------
-- The game's own quest areas and markers (0.19.5; the user, 2026-10-06, on a
-- character where the game showed them too: "hide the blizzard one on the
-- world map"): off while the objective marks are on and Hide The Game's Quest
-- Areas is, through the game's own Quest Objectives setting -- the questPOI
-- CVar, which its world map's blue areas, its quest markers and its tracker's
-- quest buttons ask (MelloUI:HoldCVar: the player's value kept in the
-- module's savedQuestPOI, never in a profile, and given back when they go).
-- Written out of combat (at the fight's end: Kit:WhenOutOfCombat)
--------------------------------------------------------------------------------
function O.GameMarksWanted()
	local M = QL.M
	return (M.isEnabled and M.db and M.db.objectiveMarks and M.db.hideGameObjectives) and true or false
end

function O.GameMarks()
	local M = QL.M
	if not (M.db and MelloUI.HoldCVar) then
		return
	end
	MelloUI.Kit:WhenOutOfCombat(function()
		MelloUI:HoldCVar(M.db, "questPOI", "savedQuestPOI", O.GameMarksWanted(), "0")
	end, "Quest List: the game's quest areas")
end

--------------------------------------------------------------------------------
-- The minimap (0.19.5, step 2; the sketch's D marks, C's behaviour): the same
-- marks near you, drawn in Route's minimap layer (Route.WantMinimap: one
-- minimap system; Route off, none) while Objective Marks and On The Minimap
-- are on and an open objective has places:
--   the places   each open objective's places, in Route's yards
--                (Route:WorldYards), in groups as on the zone map
--                (MINI.REACH yards), one place a group at its middle; made
--                again half a second after the log's last change, never at
--                login (the first: MINI.WAIT seconds after it), never a tick
--   a tick       (Route's minimap tick) a mark per group on the minimap -- the
--                objective's kind on the dark disc in its gold ring, the
--                goal's mark of Route (Route.GoalMark) -- and, for the
--                MINI.EDGES nearest groups a little beyond it (within
--                MINI.BEYOND of its radius), a smaller mark just inside its
--                edge with a gold chevron outside, turned toward them. No
--                mouse: the minimap's own clicks and pings go through
--------------------------------------------------------------------------------
local MINI = { REACH = 70, WAIT = 10, BEYOND = 1.7, EDGES = 3, MARK = 14, EDGE_MARK = 12, OWNER = "Quest List objectives" }
O.mini = { points = {}, n = 0, marks = {}, edges = {}, chevs = {}, queued = false,
	readyAt = (GetTime and GetTime() or 0) + MINI.WAIT }

function O.MiniWanted()
	local M, R = QL.M, MelloUI.Route
	return (M.isEnabled and M.db and M.db.objectiveMarks and M.db.objectiveMinimap and R and R.WantMinimap) and true or false
end

-- the places again (the log changed, a switch moved): soon, once
function O.MiniSoon()
	local mini = O.mini
	if not O.MiniWanted() then
		mini.n = 0
		local R = MelloUI.Route
		if R and R.WantMinimap then
			R.WantMinimap(MINI.OWNER, nil)
		end
		return
	end
	if mini.queued then
		return
	end
	mini.queued = true
	C_Timer.After(math.max(0.5, mini.readyAt - GetTime()), O.MiniBuild)
end

function O.MiniBuild()
	local mini, R = O.mini, MelloUI.Route
	mini.queued = false
	mini.n = 0
	if O.MiniWanted() and DataReady() then
		for _, questID in ipairs(LogQuests(QL.M.db.objectiveTrackedOnly)) do
			EachOpen(questID, function(_, entry)
				local xs, ys, cont = {}, {}, nil
				for k = 5, #entry - 1, 2 do
					local c, x, y = R:WorldYards(entry[4], entry[k], entry[k + 1])
					if c and (cont == nil or c == cont) then
						cont = c
						xs[#xs + 1], ys[#ys + 1] = x, y
					end
				end
				for _, members in ipairs(Groups(xs, ys, MINI.REACH)) do
					local cx, cy = 0, 0
					for _, i in ipairs(members) do
						cx, cy = cx + xs[i], cy + ys[i]
					end
					mini.n = mini.n + 1
					local p = mini.points[mini.n]
					if not p then
						p = {}
						mini.points[mini.n] = p
					end
					p.cont, p.x, p.y, p.kind = cont, cx / #members, cy / #members, entry[1]
				end
			end)
		end
	end
	if R and R.WantMinimap then
		R.WantMinimap(MINI.OWNER, mini.n > 0 and O.MiniDraw or nil)
	end
end

-- a mark of the pool (the goal's mark of Route, its glyph the kind's, in the
-- palette's text), made the first time it is needed
local function MiniMark(list, i, kind)
	local f = list[i]
	if not f then
		local R = MelloUI.Route
		f = R.GoalMark(R.MinimapFrame())
		f:SetFrameLevel(R.MinimapFrame():GetFrameLevel() + 2)
		MelloUI.Widgets.Paint(f.flag, "text", "vertex", 1)
		list[i] = f
	end
	if f.kind ~= kind then
		f.kind = kind
		MelloUI.Widgets.Glyph(f.flag, GLYPH[kind] or "way")
	end
	return f
end

function O.MiniDraw(cont, round, R, RX, RY)
	local mini, Route = O.mini, MelloUI.Route
	local used, eused = 0, 0
	if cont and Route.MinimapFrame() then
		local Offset, m = Route.MinimapOffset, MINI.MARK / 2 + 1
		local beyond = (round and R or math.max(RX, RY)) * MINI.BEYOND
		-- the nearest beyond the edge, in three slots (no list made a tick)
		local e1, e2, e3, d1, d2, d3 = nil, nil, nil, math.huge, math.huge, math.huge
		for i = 1, mini.n do
			local p = mini.points[i]
			if p.cont == cont then
				local gx, gy = Offset(p.x, p.y)
				local inside
				if round then
					inside = gx * gx + gy * gy <= (R - m) * (R - m)
				else
					inside = math.abs(gx) <= RX - m and math.abs(gy) <= RY - m
				end
				if inside then
					used = used + 1
					Route.MarkPlace(MiniMark(mini.marks, used, p.kind), MINI.MARK, Route.MinimapFrame(), "CENTER", gx, gy)
				else
					local d = math.sqrt(gx * gx + gy * gy)
					if d <= beyond then
						if d < d1 then
							e3, d3, e2, d2, e1, d1 = e2, d2, e1, d1, i, d
						elseif d < d2 then
							e3, d3, e2, d2 = e2, d2, i, d
						elseif d < d3 then
							e3, d3 = i, d
						end
					end
				end
			end
		end
		for _, i in ipairs({ e1, e2, e3 }) do
			local p = mini.points[i]
			local gx, gy = Offset(p.x, p.y)
			eused = eused + 1
			local k = Route.MinimapEdge(gx, gy, round, R, RX, RY, MINI.EDGE_MARK / 2 + 8)
			Route.MarkPlace(MiniMark(mini.edges, eused, p.kind), MINI.EDGE_MARK, Route.MinimapFrame(), "CENTER", gx * k, gy * k)
			local chev = mini.chevs[eused]
			if not chev then
				chev = Route.MinimapFrame():CreateTexture(nil, "OVERLAY", nil, 3)
				chev:SetTexture(Route.TRAIL.CHEVRON)
				chev:SetSize(16, 8)
				MelloUI.Widgets.Paint(chev, "selectedTrim", "vertex", 0.9)
				mini.chevs[eused] = chev
			end
			local kc = Route.MinimapEdge(gx, gy, round, R, RX, RY, 3)
			chev:ClearAllPoints()
			chev:SetPoint("CENTER", Route.MinimapFrame(), "CENTER", gx * kc, gy * kc)
			chev:SetRotation(math.atan2(gy, gx) + math.pi / 2)   -- (the art's V points down)
			chev:Show()
		end
	end
	for i = used + 1, #mini.marks do
		mini.marks[i]:Hide()
	end
	for i = eused + 1, #mini.edges do
		mini.edges[i]:Hide()
		mini.chevs[i]:Hide()
	end
end

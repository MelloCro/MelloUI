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
--   its area   (1.2.0; the user's look A of BuildData/output/animation_
--              previews/map_marks.html, "the custom area circles on the map
--              needs a big rework") the shape of its places, MelloUI.
--              QuestAreas': a lone place a circle, places near each other
--              one smooth area, a gold edge with its glow inside; drawn on
--              the map's canvas (it pans and zooms with it), the edge one
--              size on the screen (O.Zoom); objectives with the same places
--              (Gold Dust and Large Candle: the same kobolds) one area, their
--              marks side by side. Shown at every zoom (the convex outline
--              and a faint ring a place, zoomed out only, until then)
--   its spots  zoomed in (the map's zoom past ZOOMED), a dot per place in the
--              area: the bead of MelloUI's icon set, DOT_PX on the screen at
--              every zoom (O.Zoom, on the map's zoom: its zoom percent and
--              canvas scale, read only)
--   its mark   one mark per area (each loop of its edge: the middle of its
--              places), the Quest List's marks, kind "objective": one size on
--              the screen at every zoom; the objective's kind (MelloUI's icon
--              set: the skull, the bag's pin, the gauntlet's, the compass's)
--              with its progress under it ("4/8"), moved clear of the giver
--              marks and of each other; hover: the quest, the objective and
--              its progress, what drops it and how often; click: a waypoint
--              there (Route's)
-- A done objective shows nothing; a done quest only its hand-in "?" (the
-- giver marks). Laid with the giver marks on the map's refresh and on the
-- log's changes while the map shows; nothing per frame, nothing at login.
-- The motion (1.2.0, the same sketch, "all eight"; MelloUI.QuestAreas, one
-- engine: one-shot, Reduce Motion the end at once):
--   new        an area never drawn before this session (the first open, a
--              quest taken) is drawn round from its mark and its marks pop
--              in, the nearest to you first (POP_STEP a map width, POP_MAX)
--   hover      a mark lifts, its area stays lit and the others step back
--   progress   (a lay while the map stayed open on this zone: the game's
--              refresh on the log's change, or ours) an objective's count
--              up: its marks swell with a ring of light, the count rises into
--              place, its area swells once
--   done       (the same) an objective gone while its quest stays: a tick is
--              drawn on each of its marks, which then shrink away (marks of
--              the lay before, O.ghosts); its area drawn back into them
-- The minimap (step 2, below): the same marks near you, drawn in Route's
-- minimap layer (Route.WantMinimap: one minimap system).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local QL = ns.QuestList
local Finite = MelloUI.Safe.Finite
local Secret = MelloUI.Safe.IsSecret

local O = { dots = {}, ndots = 0, zoomedIn = nil, asked = false, painter = nil, scale = nil, groups = {},
	seen = {}, counts = {}, last = {}, now = {}, lastMap = nil, hidden = true, ghosts = {}, areaOf = {} }
QL.Objectives = O

local DOT_PX = 12               -- a place's dot on the screen (10 until the bead, 0.25.0)
-- (0.25.0, the user's pick) a place's dot: the bead of MelloUI's icon set, white and grey in its dark outline (the
-- white takes the tint); the flat MapDot until then
local MAP_DOT = MelloUI.Widgets.IconPath("map_dot")
local ZOOMED = 0.5              -- the map's zoom percent from which the places show as dots
local NEAR = 0.024              -- map units: a mark closer than this to another is moved
local SEG_PX = 5                -- (1.2.0) the areas' edge in stretches about this long on the screen (its points taken
                                -- every so many: MelloUI.QuestAreas' STEP yards apart)
local SIDE_PX = 15              -- marks of objectives sharing an area: this far either side of its middle
local MARK = 20                 -- a mark's icon (O.Dress)
local POP_STEP, POP_MAX = 0.5, 0.45   -- s a map width from you before a new mark pops, at most
local DIM = 0.35                -- the other areas' alpha while a mark is hovered (their marks: DIM_MARK)
local DIM_MARK = 0.55
-- (0.25.0, the user's picks: MelloUI's icon set) a mark by the data's kind: kill the standalone skull (with its soft
-- shade), use the gauntlet's pin, collect the bag's pin, explore the compass's pin (the widget glyphs sword, cog,
-- bag and flag on a dark disc in a gold ring until then)
local OBJ_ICON = { [1] = "kill", [2] = "obj_use", [3] = "pin_collect", [4] = "obj_explore" }

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

-- (1.2.0) world yards to a map's 0..1: the client's own answer at three points by a place (one ask a point
-- otherwise; the edge's points lie off the map at its borders, where the zone map's own check refuses them), kept by
-- map and continent: { x0, y0, dx/dwx, dy/dwx, dx/dwy, dy/dwy }, or false
local affine = {}
local function Affine(mapID, cont, wx, wy)
	local key = mapID .. ":" .. cont
	local a = affine[key]
	if a ~= nil then
		return a
	end
	a = false
	if C_Map.GetMapPosFromWorldPos and CreateVector2D then
		local function At(x, y)
			local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(x, y), mapID)
			if not ok then
				return nil
			end
			local mx, my = QL.VectorXY(pos)
			return Finite(mx), Finite(my)
		end
		local x0, y0 = At(wx, wy)
		local x1, y1 = At(wx + 50, wy)
		local x2, y2 = At(wx, wy + 50)
		if x0 and y0 and x1 and y1 and x2 and y2 then
			a = { x0 - wx * (x1 - x0) / 50 - wy * (x2 - x0) / 50, y0 - wx * (y1 - y0) / 50 - wy * (y2 - y0) / 50,
				(x1 - x0) / 50, (y1 - y0) / 50, (x2 - x0) / 50, (y2 - y0) / 50 }
			if a[3] == 0 and a[5] == 0 then
				a = false
			end
		end
	end
	-- (no answer at a place: asked again at the next one)
	if a then
		affine[key] = a
	end
	return a
end

local function MapXY(a, wx, wy)
	return a[1] + a[3] * wx + a[5] * wy, a[2] + a[4] * wx + a[6] * wy
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

-- the map's pins cleared: the dots, the areas out of sight (kept for the next lay: what is gone is seen then)
function O.Clear()
	for i = 1, O.ndots do
		O.dots[i]:Hide()
	end
	O.ndots, O.zoomedIn = 0, nil
	if O.painter then
		O.painter:Hide()
	end
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

-- The map's zoom: zoomed in the dots, DOT_PX on the screen (the canvas's
-- units: DOT_PX / its scale, as Route's trail); the areas one size on the
-- screen (MelloUI.QuestAreas' painter:Scale) and their edge in stretches of
-- about SEG_PX (both written when the zoom moved by a tenth: a zoom's
-- steps); the dots' shown state written only when it changes, their size at
-- every step
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
		for i = 1, O.ndots do
			O.dots[i]:SetShown(zoomedIn)
		end
	end
	if s and s > 0 then
		if zoomedIn then
			local size = DOT_PX / s
			for i = 1, O.ndots do
				O.dots[i]:SetSize(size, size)
			end
		end
		if O.painter and not (O.scale and math.abs(s - O.scale) < O.scale * 0.1) then
			O.scale = s
			O.painter:Scale(1 / s)
			for _, g in ipairs(O.groups) do
				local stride = O.Stride(g, s)
				if stride ~= g.stride then
					g.stride = stride
					O.painter:Area(g.key, g.shape, g.project, stride)
				end
			end
		end
	end
end

-- an area's edge points taken every `stride`th: a stretch about SEG_PX on the screen at the canvas's scale `s`
function O.Stride(g, s)
	local px = (g.perStep or 0) * (s or 1)
	return px > 0 and math.max(1, math.ceil(SEG_PX / px)) or 1
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

-- the player's place on the map (0..1), or nil: the new marks' pop goes out from it
local function Me(mapID)
	if not (C_Map.GetPlayerMapPosition) then
		return nil
	end
	local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	if not ok then
		return nil
	end
	local x, y = QL.VectorXY(pos)
	return Finite(x), Finite(y)
end

-- The objective marks of the zone map shown (QL.Provider:LayPins, after the
-- givers: their marks are in Marks.list already)
function O.Add(map, mapID)
	O.Clear()
	local painter = O.painter
	-- (a lay while this map stayed open: the game's own refresh on the log's change, or ours: what changed moves)
	local live = not O.hidden and O.lastMap == mapID
	O.hidden = false
	O.last, O.now = O.now, O.last
	wipe(O.now)
	wipe(O.areaOf)
	local list = LogQuests(QL.M.db.objectiveTrackedOnly)
	local canvas = map:GetCanvas()
	local W, H = QL.Plain(canvas:GetWidth()), QL.Plain(canvas:GetHeight())
	if #list == 0 or not DataReady() or not (Finite(W) and Finite(H) and W > 0 and H > 0) then
		if painter then
			painter:Begin()
			O.Gone(map, mapID, live)
		end
		O.lastMap = mapID
		return
	end
	local layer = O.Layer(canvas)   -- (the areas drawn on their layer, the same size as the canvas)
	if not painter then
		painter = MelloUI.QuestAreas.Painter(layer, "BORDER")
		O.painter = painter
	end
	painter:Begin()
	local QA = MelloUI.QuestAreas
	local palette = MelloUI.Look.Palette()
	wipe(placed)
	for _, m in ipairs(QL.MarkList()) do
		if m.x and m.y then
			placed[#placed + 1] = { m.x, m.y }
		end
	end
	-- the open objectives by their shape: one area a shape, its objectives' marks side by side
	local byShape, order = {}, {}
	for _, questID in ipairs(list) do
		EachOpen(questID, function(index, entry, t)
			local xs, ys, key = QA.Places(entry)
			local a = #xs > 0 and Affine(mapID, entry[4], xs[1], ys[1])
			local shape = a and QA.Shape(key, xs, ys)
			if shape then
				local g = byShape[shape]
				if not g then
					g = { key = key, shape = shape, a = a, objs = {} }
					byShape[shape] = g
					order[#order + 1] = g
					-- the places' dots (zoomed in), those on the map
					for i = 1, #xs do
						local x, y = MapXY(a, xs[i], ys[i])
						if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
							Dot(layer, W, H, x, y, palette.text)
						end
					end
				end
				g.objs[#g.objs + 1] = { questID, index, entry, t }
			end
		end)
	end
	-- (the edge's 10-yard points taken every `stride`th: a stretch about SEG_PX on the screen)
	local step, perStep = QA.T.STEP, nil
	local okS, scale = pcall(map.GetCanvasScale, map)
	scale = okS and Finite(scale) or 1
	wipe(O.groups)
	local meX, meY = Me(mapID)
	for _, g in ipairs(order) do
		local a = g.a
		if not perStep then
			local x1 = MapXY(a, 0, 0)
			local x2 = MapXY(a, step, 0)
			local x3 = MapXY(a, 0, step)
			perStep = math.max(math.abs(x2 - x1), math.abs(x3 - x1)) * W   -- canvas units a STEP
		end
		g.perStep = perStep
		g.project = function(x, y)
			local mx, my = MapXY(a, x, y)
			return mx * W, -my * H
		end
		g.stride = O.Stride(g, scale)
		O.groups[#O.groups + 1] = g
		local area = painter:Area(g.key, g.shape, g.project, g.stride)
		local fresh = not O.seen[g.key]
		O.seen[g.key] = true
		local delay = 0
		-- each objective's count: up since the lay before (a live one) -- its marks' moment, once an objective
		local bumps = {}
		for j, o in ipairs(g.objs) do
			local id, t = o[1] * 100 + o[2], o[4]
			local have, before = t and t[7], O.counts[o[1] * 100 + o[2]]
			O.counts[id] = have
			bumps[j] = (live and have and before and have > before) and before or false
		end
		for _, m in ipairs(g.shape.marks) do
			local mx, my = MapXY(a, m[1], m[2])
			if mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
				mx, my = Clear(mx, my)
				placed[#placed + 1] = { mx, my }
				local d = meX and math.sqrt((mx - meX) ^ 2 + (my - meY) ^ 2) or 0
				local pop = fresh and math.min(POP_MAX, d * POP_STEP) or nil
				if pop and (delay == 0 or pop < delay) then
					delay = pop
				end
				for j, o in ipairs(g.objs) do
					local questID, index, entry, t = o[1], o[2], o[3], o[4]
					local id = questID * 100 + index
					local data = { x = mx, y = my, questID = questID, index = index, kind = entry[1], name = entry[2],
						line = t, mapID = mapID, area = g.key, dx = (j - (#g.objs + 1) / 2) * 2 * SIDE_PX, pop = pop,
						bump = bumps[j] or nil }
					QL.Marks.Add("objective", data)
					local seen = O.now[id]
					if not seen then
						seen = { area = g.key, quest = questID }
						O.now[id] = seen
					end
					seen[#seen + 1] = data
				end
			end
		end
		O.areaOf[g.key] = area
		if fresh then
			QA.TraceIn(area, QA.T.TRACE, delay)
		end
	end
	-- the progress: an area whose count went up swells once
	for _, seen in pairs(O.now) do
		local d = seen[1]
		local area = d and d.bump and O.areaOf[seen.area]
		if area then
			QA.Swell(area)
		end
	end
	O.Gone(map, mapID, live)
	O.lastMap = mapID
	O.Zoom(map)   -- (the dots shown or not, the edge's width, as the map is zoomed now)
end

-- The objectives gone since the lay before (a live lay only: the log changed while this map showed): each mark of a
-- done one gets its tick and shrinks away on a ghost (the marks are laid again from scratch), its area drawn back
-- into it while no objective keeps it; then the areas no lay drew go
function O.Gone(map, mapID, live)
	local painter = O.painter
	local QA = MelloUI.QuestAreas
	if live then
		local n = 0
		for id, was in pairs(O.last) do
			if not O.now[id] then
				local stays = C_QuestLog.IsOnQuest and select(2, pcall(C_QuestLog.IsOnQuest, was.quest))
				for _, d in ipairs(was) do
					if stays == true then
						n = n + 1
						O.Ghost(map, n, d)
					end
				end
				local area = painter.areas[was.area]
				if area and area.gen ~= painter.gen and not area.hold then
					area.hold = true
					area.frame:Show()
					QA.TraceOut(area, QA.T.GONE, O.AreaGone)
				end
			end
		end
	end
	painter:End()
end

function O.AreaGone(area)
	area.hold = nil
	if O.painter.areas[area.key] == area and area.gen ~= O.painter.gen then
		MelloUI.QuestAreas.Release(O.painter, area)
	end
end

-- a ghost: a gone mark's last look, on its own anchor on the canvas, in the marks' clip (made on the first need)
function O.Ghost(map, n, d)
	local clip = QL.Marks.clip
	local canvas = map:GetCanvas()
	local W, H = QL.Plain(canvas:GetWidth()), QL.Plain(canvas:GetHeight())
	if not (clip and W and H) then
		return
	end
	local g = O.ghosts[n]
	if not g then
		g = { anchor = canvas:CreateTexture(nil, "BACKGROUND") }
		g.anchor:SetSize(1, 1)
		g.f = CreateFrame("Frame", nil, clip)
		g.f:SetSize(MARK, MARK)
		g.f:EnableMouse(false)
		g.icon = g.f:CreateTexture(nil, "ARTWORK")
		g.icon:SetPoint("CENTER")
		O.ghosts[n] = g
	end
	g.anchor:ClearAllPoints()
	g.anchor:SetPoint("CENTER", canvas, "TOPLEFT", d.x * W, -d.y * H)
	g.f:SetFrameStrata(clip:GetFrameStrata())
	g.f:SetFrameLevel(clip:GetFrameLevel() + 20)
	g.f:ClearAllPoints()
	g.f:SetPoint("CENTER", g.anchor, "CENTER", d.dx or 0, 0)
	local icon = OBJ_ICON[d.kind] or "goal_pin"
	MelloUI.Widgets.Icon(g.icon, icon)
	g.icon:SetSize(MARK, MARK)
	g.f:Show()
	MelloUI.QuestAreas.MarkTick(g.f, g.icon, MARK, O.GhostDone)
end

function O.GhostDone(f)
	f:Hide()
end

-- (QuestListMap's Marks.End, a mark laid and shown) its moment: a new one's pop, a count's swell and its number risen
-- into place; `same`: the button held this very mark before (its moves under way go on), else it is set at rest
function O.Moment(b, data, same)
	local QA = MelloUI.QuestAreas
	if data.pop then
		QA.MarkPop(b, b.Icon, MARK, data.pop)
	elseif data.bump then
		QA.MarkBump(b, b.Icon, MARK)
		local Anim = MelloUI.Anim
		if Anim and b.Label:IsShown() then
			Anim:From(b.Label, "y", -7, 0.25, "outCubic")
			b.Label:SetAlpha(0)
			Anim:To(b.Label, "alpha", 1, 0.2)
		end
	elseif not same then
		QA.MarkStill(b, b.Icon, MARK)
	end
end

-- (QuestListMap's MarkEnter / MarkLeave) a mark hovered: it lifts, its area stays lit and the other areas and their
-- marks step back; left: all back
function O.Hover(b, on)
	local Anim = MelloUI.Anim
	local data = b.data
	if not (Anim and data and data.area) then
		return
	end
	MelloUI.QuestAreas.MarkLift(b, b.Icon, MARK, on)
	local key = on and data.area or nil
	if O.painter then
		O.painter:Each(function(area)
			if not area.hold then
				Anim:To(area.frame, "alpha", (key == nil or area.key == key) and 1 or DIM, 0.15)
				Anim:To(area.glow, "alpha", (key ~= nil and area.key == key) and 1 or MelloUI.QuestAreas.T.GLOW_REST, 0.15)
			end
		end)
	end
	for _, m in ipairs(QL.Marks.buttons) do
		if m ~= b and m.kind == "objective" and m:IsShown() and m.data then
			Anim:To(m, "alpha", (key == nil or m.data.area == key) and 1 or DIM_MARK, 0.15)
		end
	end
end

-- the mark's look: its kind's icon on its lift (a pin's glow, the skull's soft shade: MelloUI.Shade:Lift, the soft
-- round shade under the skull alone until then), its progress under it
function O.Dress(b, data)
	local gold = MelloUI.Look.Palette().selectedTrim
	b:SetSize(MARK, MARK)
	b.Bg:Hide()
	b.Icon:ClearAllPoints()
	b.Icon:SetPoint("CENTER")
	b.Icon:SetSize(MARK, MARK)
	b.Icon:SetDesaturated(false)
	b.Icon:SetAlpha(1)
	local icon = OBJ_ICON[data.kind] or "goal_pin"
	MelloUI.Widgets.Icon(b.Icon, icon)
	b.Icon:Show()
	MelloUI.Shade:Lift(b.Icon, icon, MARK)
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
--   the areas    (1.2.0; the user's picks of BuildData/output/animation_
--                previews/map_marks.html: look A, on the minimap too, "all
--                eight") each open objective's area as on the maps
--                (MelloUI.QuestAreas: the same shapes), worked out half a
--                second after the log's last change, never at login (the
--                first: MINI.WAIT seconds after it), never a tick; their
--                places carried to Route's yards by Route:WorldYards (an
--                affine of three of its answers a continent)
--   a tick       (Route's minimap tick) the areas round you drawn thin under
--                Route's trail (the edge alone, clipped to the map's round or
--                square), a mark per area loop (the maps' marks; objectives
--                sharing an area side by side) -- the objective's kind -- and,
--                for the three nearest a little beyond the edge (within
--                MINI.BEYOND of its radius), a smaller mark on its edge with a
--                gold chevron outside, turned toward them. (1.2.0) A mark
--                nearing the edge grows smaller over MINI.RIM px into its
--                edge size and slides onto the edge as it passes it, its
--                chevron coming in; one far beyond fades out (from MINI.FADE
--                of the reach): all of it from the distance, no state, no
--                extra work a tick. No mouse: the minimap's own clicks and
--                pings go through
--   moments      (1.2.0) after the first build: an area new since then drawn
--                round from its marks; a count up: its marks swell with a
--                ring (the next tick that shows them); an objective done while
--                its quest stays: a tick drawn on each of its marks, which
--                shrink away (ghosts), its area drawn back into them; you
--                stepping into an area: its edge swells once, its marks lift
--                once
--------------------------------------------------------------------------------
local MINI = { WAIT = 10, BEYOND = 1.7, MARK = 14, EDGE_MARK = 12, OWNER = "Quest List objectives",
	SEG_PX = 6, SIDE_PX = 8, RIM = 10, FADE = 0.85 }
O.mini = { points = {}, n = 0, areas = {}, leaving = {}, ghosts = {}, ghostFrames = {}, counts = {}, of = {}, seen = {},
	queued = false, built = false, painter = nil, holder = nil, readyAt = (GetTime and GetTime() or 0) + MINI.WAIT }

function O.MiniWanted()
	local M, R = QL.M, MelloUI.Route
	return (M.isEnabled and M.db and M.db.objectiveMarks and M.db.objectiveMinimap and R and R.WantMinimap) and true or false
end

-- the places again (the log changed, a switch moved): soon, once
function O.MiniSoon()
	local mini = O.mini
	if not O.MiniWanted() then
		mini.n = 0
		wipe(mini.areas)
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

-- world yards to Route's (Route:WorldYards, linear: three answers by a place), kept by continent with its way back:
-- { cont, x0, y0, ax, ay, bx, by, inverse { ... } }, or false
local yardsOf = {}
local function Yards(R, wcont, wx, wy)
	local a = yardsOf[wcont]
	if a then
		return a
	end
	local c0, x0, y0 = R:WorldYards(wcont, wx, wy)
	local c1, x1, y1 = R:WorldYards(wcont, wx + 50, wy)
	local c2, x2, y2 = R:WorldYards(wcont, wx, wy + 50)
	if not (c0 and c0 == c1 and c0 == c2 and x0 and x1 and x2) then
		return false
	end
	local ax, ay, bx, by = (x1 - x0) / 50, (y1 - y0) / 50, (x2 - x0) / 50, (y2 - y0) / 50
	local det = ax * by - bx * ay
	if det == 0 then
		return false
	end
	a = { cont = c0, x0 - wx * ax - wy * bx, y0 - wx * ay - wy * by, ax, ay, bx, by,
		-- the way back: Route's yards to world yards
		ix = { by / det, -bx / det }, iy = { -ay / det, ax / det } }
	yardsOf[wcont] = a
	return a
end

local function Carry(a, x, y)
	return a[1] + a[3] * x + a[5] * y, a[2] + a[4] * x + a[6] * y
end

local function Back(a, rx, ry)
	local dx, dy = rx - a[1], ry - a[2]
	return a.ix[1] * dx + a.ix[2] * dy, a.iy[1] * dx + a.iy[2] * dy
end

function O.MiniBuild()
	local mini, R = O.mini, MelloUI.Route
	local QA = MelloUI.QuestAreas
	mini.queued = false
	local live = mini.built
	local was = {}
	for _, g in ipairs(mini.areas) do
		was[g.key] = g
	end
	wipe(mini.areas)
	local of, byShape = {}, {}
	if O.MiniWanted() and DataReady() and QA then
		mini.built = true
		for _, questID in ipairs(LogQuests(QL.M.db.objectiveTrackedOnly)) do
			EachOpen(questID, function(index, entry, t)
				local xs, ys, key = QA.Places(entry)
				local a = #xs > 0 and Yards(R, entry[4], xs[1], ys[1])
				local shape = a and QA.Shape(key, xs, ys)
				if shape then
					local g = byShape[shape]
					if not g then
						g = { key = key, shape = shape, a = a, cont = a.cont, objs = {} }
						-- its box in Route's yards (the tick draws the areas near you only)
						local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
						for _, loop in ipairs(shape.loops) do
							for i = 1, #loop - 1, 2 do
								local rx, ry = Carry(a, loop[i], loop[i + 1])
								if rx < x0 then x0 = rx end
								if rx > x1 then x1 = rx end
								if ry < y0 then y0 = ry end
								if ry > y1 then y1 = ry end
							end
						end
						g.x0, g.y0, g.x1, g.y1 = x0, y0, x1, y1
						g.fresh = live and not mini.seen[key]
						mini.seen[key] = true
						byShape[shape] = g
						mini.areas[#mini.areas + 1] = g
					end
					g.objs[#g.objs + 1] = { questID, index, entry, t }
					of[questID * 100 + index] = true
				end
			end)
		end
	end
	-- gone since the last build (the points still as they were): a done objective's marks get their tick (ghosts, the
	-- shown ones), its area drawn back into them
	if live then
		for id, seen in pairs(mini.of) do
			if not of[id] then
				local ok, on = pcall(C_QuestLog.IsOnQuest, seen.quest)
				for _, p in ipairs(seen) do
					if ok and on == true and p.shownAt then
						mini.ghosts[#mini.ghosts + 1] = { cont = p.cont, x = p.x, y = p.y, dx = p.dx, kind = p.kind,
							fresh = true }
					end
				end
				local g = was[seen.area]
				if g and not byShape[g.shape] and not g.leaving then
					g.leaving = true
					mini.leaving[#mini.leaving + 1] = g
				end
			end
		end
	end
	-- the points: a mark a loop of each area, its objectives' side by side
	mini.n = 0
	wipe(mini.of)
	for _, g in ipairs(mini.areas) do
		for j, o in ipairs(g.objs) do
			local questID, index, entry, t = o[1], o[2], o[3], o[4]
			local id = questID * 100 + index
			local have = t and t[7]
			local before = mini.counts[id]
			mini.counts[id] = have
			local bump = (live and have and before and have > before) and true or nil
			local seen = { quest = questID, area = g.key }
			mini.of[id] = seen
			for _, m in ipairs(g.shape.marks) do
				local rx, ry = Carry(g.a, m[1], m[2])
				mini.n = mini.n + 1
				local p = mini.points[mini.n]
				if not p then
					p = {}
					mini.points[mini.n] = p
				end
				p.cont, p.x, p.y, p.kind, p.area = g.cont, rx, ry, entry[1], g
				p.dx = (j - (#g.objs + 1) / 2) * 2 * MINI.SIDE_PX
				p.bump, p.pop, p.shownAt = bump, g.fresh or nil, nil
				seen[#seen + 1] = p
			end
		end
	end
	if R and R.WantMinimap then
		R.WantMinimap(MINI.OWNER, (mini.n > 0 or #mini.leaving > 0 or #mini.ghosts > 0) and O.MiniDraw or nil)
	end
end

-- a mark of a point (its own frame, kept with the point: a moment stays with its mark), `size` big, made the first
-- time it is needed: its kind's icon (as on the map) on its lift (MelloUI.Shade:Lift) -- placed by Route.MarkPlace
local function MiniMark(p, kind, size)
	local f = p.frame
	if not f then
		local R = MelloUI.Route
		f = CreateFrame("Frame", nil, R.MinimapFrame())
		f:SetFrameLevel(R.MinimapFrame():GetFrameLevel() + 2)
		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetPoint("CENTER")
		p.frame = f
	end
	if f.kind ~= kind then
		f.kind = kind
		local icon = OBJ_ICON[kind] or "goal_pin"
		MelloUI.Widgets.Icon(f.icon, icon)
		MelloUI.Shade:Lift(f.icon, icon, MINI.MARK)
	end
	-- (its icon's size: not while a moment drives it)
	if f.atSize ~= size and not (MelloUI.Anim and MelloUI.Anim:IsRunning(f, "drive")) then
		f.atSize = size
		f.icon:SetSize(size, size)
	end
	return f
end

local function Chevron(p)
	local chev = p.chev
	if not chev then
		local Route = MelloUI.Route
		chev = Route.MinimapFrame():CreateTexture(nil, "OVERLAY", nil, 3)
		chev:SetTexture(Route.TRAIL.CHEVRON)   -- (0.25.0: the set's gold arrow, its own colour)
		chev:SetSize(16, 8)
		p.chev = chev
	end
	return chev
end

-- the areas' projection and clip a tick: their upvalues set before each area (no function made a tick)
local mA, mHW, mHH, mRound, mR, mRX, mRY, mCont, mPPY
local function MiniProject(x, y)
	local a = mA
	local gx, gy = MelloUI.Route.MinimapOffset(a[1] + a[3] * x + a[5] * y, a[2] + a[4] * x + a[6] * y)
	return gx + mHW, gy - mHH
end

local function MiniClip(ax, ay, bx, by)
	local Route = MelloUI.Route
	ax, ay, bx, by = ax - mHW, ay + mHH, bx - mHW, by + mHH
	if mRound then
		ax, ay, bx, by = Route.ClipToCircle(ax, ay, bx, by, mR)
	else
		ax, ay, bx, by = Route.ClipToSquare(ax, ay, bx, by, mRX, mRY)
	end
	if not ax then
		return nil
	end
	return ax + mHW, ay - mHH, bx + mHW, by - mHH
end

-- the areas' holder: under Route's own layer (its trail over them), moved with it (Route.MinimapShift)
local function MiniPainter()
	local mini = O.mini
	if not mini.painter then
		local mm = MelloUI.Route.MinimapFrame()
		local h = CreateFrame("Frame", nil, mm:GetParent() or mm)   -- (the minimap: Route's layer's parent)
		h:SetAllPoints(mm)
		h:SetFrameLevel(math.max(0, mm:GetFrameLevel() - 1))
		h:EnableMouse(false)
		mini.holder = h
		mini.painter = MelloUI.QuestAreas.Painter(h, "ARTWORK", true)
	end
	return mini.painter
end

local function MiniAreaGone(area)
	local mini = O.mini
	area.hold = nil
	for i = #mini.leaving, 1, -1 do
		if mini.leaving[i].key == area.key then
			table.remove(mini.leaving, i)
		end
	end
	if mini.painter.areas[area.key] == area and area.gen ~= mini.painter.gen then
		MelloUI.QuestAreas.Release(mini.painter, area)
	end
end

local function MiniGhostDone(f)
	f:Hide()
	f.ghost = nil
end

-- a ghost's frame: one of the pool (free when its tick is over)
local function GhostFrame(parent)
	local mini = O.mini
	for _, f in ipairs(mini.ghostFrames) do
		if not f.ghost and not f:IsShown() then
			return f
		end
	end
	local f = CreateFrame("Frame", nil, parent)
	f:SetFrameLevel(parent:GetFrameLevel() + 3)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("CENTER")
	mini.ghostFrames[#mini.ghostFrames + 1] = f
	return f
end

-- one area drawn this tick (near you), its moments: a new one drawn round, a leaving one drawn back, you stepping in
local function MiniArea(painter, g, px, py, reach)
	if not (g.cont == mCont and g.x1 >= px - reach and g.x0 <= px + reach and g.y1 >= py - reach
		and g.y0 <= py + reach) then
		if g.leaving then
			g.leaving = "far"   -- (out of sight: let go at once)
		end
		return
	end
	local QA = MelloUI.QuestAreas
	mA = g.a
	local stride = math.max(1, math.floor(MINI.SEG_PX / (QA.T.STEP * mPPY) + 0.5))
	-- (the loops near you only: the reach round you, in the shape's world yards)
	local box = g.cullBox
	if not box then
		box = {}
		g.cullBox = box
	end
	local x1, y1 = Back(g.a, px - reach, py - reach)
	local x2, y2 = Back(g.a, px + reach, py - reach)
	local x3, y3 = Back(g.a, px - reach, py + reach)
	local x4, y4 = Back(g.a, px + reach, py + reach)
	box[1], box[2] = math.min(x1, x2, x3, x4), math.min(y1, y2, y3, y4)
	box[3], box[4] = math.max(x1, x2, x3, x4), math.max(y1, y2, y3, y4)
	local area = painter:Area(g.key, g.shape, MiniProject, stride, MiniClip, box)
	if g.fresh and area.new then
		g.fresh = false
		QA.TraceIn(area, QA.T.TRACE)
	end
	if g.leaving and not area.hold then
		area.hold = true
		QA.TraceOut(area, QA.T.GONE, MiniAreaGone)
	end
	-- (1.2.0) you in it: its edge swells once and its marks lift, as you step in (the inside: world yards)
	local inside = false
	if px >= g.x0 and px <= g.x1 and py >= g.y0 and py <= g.y1 then
		local wx, wy = Back(g.a, px, py)
		for _, loop in ipairs(g.shape.loops) do
			if QA.Inside(wx, wy, loop) then
				inside = not inside
			end
		end
	end
	if inside and not g.inside and g.wasNear then
		QA.Swell(area)
		g.stepIn = true
	end
	g.inside, g.wasNear = inside, true
end

function O.MiniDraw(cont, round, R, RX, RY)
	local mini, Route = O.mini, MelloUI.Route
	local QA = MelloUI.QuestAreas
	local frame = Route.MinimapFrame()
	local painter = frame and QA and MiniPainter()
	if painter then
		painter:Begin()
	end
	if cont and frame and painter then
		local Offset, m = Route.MinimapOffset, MINI.MARK / 2 + 1
		local beyond = (round and R or math.max(RX, RY)) * MINI.BEYOND
		local v = Route.mmView
		-- the areas round you: drawn thin, clipped to the map's shape
		local w, h = frame:GetWidth(), frame:GetHeight()
		mHW, mHH, mRound, mR, mRX, mRY = (w or 0) / 2, (h or 0) / 2, round, R, RX, RY
		mCont, mPPY = cont, v.ppy or 1
		local reach = math.max(R, RX, RY) / (v.ppy or 1) + QA.T.RADIUS
		for _, g in ipairs(mini.areas) do
			MiniArea(painter, g, v.px, v.py, reach)
		end
		for i = #mini.leaving, 1, -1 do
			local g = mini.leaving[i]
			MiniArea(painter, g, v.px, v.py, reach)
			if g.leaving == "far" then
				table.remove(mini.leaving, i)
			end
		end
		-- the marks: inside, or among the three nearest beyond the edge
		local e1, e2, e3, d1, d2, d3 = nil, nil, nil, math.huge, math.huge, math.huge
		for i = 1, mini.n do
			local p = mini.points[i]
			p.on = false
			if p.cont == cont then
				local gx, gy = Offset(p.x, p.y)
				gx = gx + (p.dx or 0)
				local room   -- px from the edge's limit, inside (> 0) or past it
				if round then
					room = (R - m) - math.sqrt(gx * gx + gy * gy)
				else
					room = math.min(RX - m - math.abs(gx), RY - m - math.abs(gy))
				end
				p.gx, p.gy, p.room = gx, gy, room
				if room >= 0 then
					p.on = true
				else
					local d = math.sqrt(gx * gx + gy * gy)
					p.d = d
					if d <= beyond then
						if d < d1 then
							e3, d3, e2, d2, e1, d1 = e2, d2, e1, d1, p, d
						elseif d < d2 then
							e3, d3, e2, d2 = e2, d2, p, d
						elseif d < d3 then
							e3, d3 = p, d
						end
					end
				end
			end
		end
		if e1 then e1.on = true end
		if e2 then e2.on = true end
		if e3 then e3.on = true end
		for i = 1, mini.n do
			local p = mini.points[i]
			local f = p.frame
			if p.on then
				local gx, gy, room = p.gx, p.gy, p.room
				local size, alpha
				if room >= 0 then
					-- (nearing the edge: smaller over RIM px into the edge's size)
					local s = math.min(1, room / MINI.RIM)
					size = MINI.EDGE_MARK + (MINI.MARK - MINI.EDGE_MARK) * s * s * (3 - 2 * s)
					alpha = 1
				else
					local k = Route.MinimapEdge(gx, gy, round, R, RX, RY, m)
					local over = p.d * (1 - k)
					gx, gy = gx * k, gy * k
					size = MINI.EDGE_MARK
					local a = math.min(1, over / MINI.RIM)
					local arrow = a * a * (3 - 2 * a)
					local fade = (p.d - MINI.FADE * beyond) / ((1 - MINI.FADE) * beyond)
					fade = fade < 0 and 0 or (fade > 1 and 1 or fade)
					alpha = 1 - fade * fade * (3 - 2 * fade)
					local chev = Chevron(p)
					local kc = Route.MinimapEdge(p.gx, p.gy, round, R, RX, RY, 3)
					chev:ClearAllPoints()
					chev:SetPoint("CENTER", frame, "CENTER", p.gx * kc, p.gy * kc)
					chev:SetRotation(math.atan2(p.gy, p.gx) + math.pi / 2)   -- (the art's V points down)
					chev:SetAlpha(alpha * arrow)
					chev:Show()
				end
				f = MiniMark(p, p.kind, size)
				Route.MarkPlace(f, size, frame, "CENTER", gx, gy)
				if not (MelloUI.Anim and MelloUI.Anim:IsRunning(f, "drive")) then
					f:SetAlpha(alpha)
				end
				-- its moments: a new area's pop, a count's ring, you stepping into its area
				if p.pop then
					p.pop = nil
					QA.MarkPop(f, f.icon, size, 0)
				elseif p.bump then
					p.bump = nil
					QA.MarkBump(f, f.icon, size)
				elseif p.area and p.area.stepIn then
					QA.MarkBump(f, f.icon, size, true)
				end
				p.shownAt = true
			else
				p.shownAt = nil
				if f then
					f:Hide()
				end
			end
			if (not p.on or (p.room or 0) >= 0) and p.chev then
				p.chev:Hide()
			end
		end
		for _, g in ipairs(mini.areas) do
			g.stepIn = nil
		end
		-- the done marks' ghosts: their tick and their way out, where their mark stood
		for i = #mini.ghosts, 1, -1 do
			local gh = mini.ghosts[i]
			if gh.cont == cont then
				local f = gh.frame
				if not f then
					f = GhostFrame(frame)
					gh.frame = f
					f.ghost = true
					local icon = OBJ_ICON[gh.kind] or "goal_pin"
					MelloUI.Widgets.Icon(f.icon, icon)
					f.icon:SetSize(MINI.MARK, MINI.MARK)
				end
				local gx, gy = Offset(gh.x, gh.y)
				Route.MarkPlace(f, MINI.MARK, frame, "CENTER", gx + (gh.dx or 0), gy)
				f:Show()
				if gh.fresh then
					gh.fresh = false
					QA.MarkTick(f, f.icon, MINI.MARK, MiniGhostDone)
				end
				if not f.ghost then
					f:Hide()
					table.remove(mini.ghosts, i)
				end
			end
		end
	else
		for i = 1, mini.n do
			local p = mini.points[i]
			if p.frame then
				p.frame:Hide()
			end
			if p.chev then
				p.chev:Hide()
			end
		end
		for _, f in ipairs(mini.ghostFrames) do
			f:Hide()
			f.ghost = nil
		end
		wipe(mini.ghosts)
	end
	if painter then
		painter:End()
	end
	-- (the points past the list's end: their frames out of sight)
	for i = mini.n + 1, #mini.points do
		local p = mini.points[i]
		if p.frame then
			p.frame:Hide()
		end
		if p.chev then
			p.chev:Hide()
		end
	end
end

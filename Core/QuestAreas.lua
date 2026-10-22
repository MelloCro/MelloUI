--------------------------------------------------------------------------------
-- MelloUI - the quest areas (1.2.0; the user, 2026-10-22: "the custom area
-- circles on the map needs a big rework" -> look A of BuildData/output/
-- animation_previews/map_marks.html; docs/plans/map-marks.md)
--
-- One drawing of where an objective is done, for every map that shows it:
-- the game's zone map (the Quest List's objective marks), MelloUI's own map
-- and the minimap. The shape follows the places:
--   the field   each place a soft hill (a Gaussian, SIGMA yards); the edge
--               where their sum reaches the level a lone place has at RADIUS
--               yards: a lone place a circle, places near each other one
--               smooth area, places far apart areas of their own
--   the edge    the level line by marching squares on a CELL-yard grid (the
--               places split first into parts JOIN yards apart, each its own
--               grid), its loops chained, smoothed (Chaikin, twice) and
--               spaced STEP yards. Worked out once for a set of places and
--               kept (QA.Shape), never per frame
--   the inside  per loop, the side the area lies on (the field tested a
--               little off it: a hole comes out right) and a point inside
--   the marks   one a loop: the middle of the places inside it, or the place
--               nearest that middle when it falls outside; each loop starts
--               at its point nearest its mark (a trace draws from there)
--   the look    the edge: ONE Line a stretch, in one picture across its
--               EDGE_PX (Media/Textures/QuestAreaEdge, Tools/
--               make_widget_art.py: a dark casing, the core, the casing; the
--               same both ways, so no Line's way matters and the joints
--               close); the glow inside: a soft dab a point (Media/Textures/
--               QuestAreaGlow), GLOW_IN px in along the inward normal, the
--               dabs overlapping into one band with no seams (Lines this
--               wide showed their joints on a curve); both tinted the
--               palette's selectedTrim (MelloUI.Painter), one size on the
--               screen at every zoom (painter:Scale)
--
--   QA.Places(entry) -> xs, ys, key   an objective's places (the core's
--       QuestObjectives entry) and its shape's key (reused tables)
--   QA.Shape(key, xs, ys) -> shape or nil
--       the shape of the places (xs, ys: world yards of one continent),
--       kept by key (a new set of places: a new key). shape = { loops =
--       { {x1, y1, x2, y2, ...}, ... }, probe = { {x, y}, ... } (a point
--       inside, by each loop's first stretch), marks = { {x, y, loop}, ... },
--       box = { {x0, y0, x1, y1}, ... } (each loop's) }
--   QA.Painter(parent[, drawLayer[, noGlow]]) -> painter (noGlow: the edge
--       alone -- the minimap, laid again every tick)
--       painter:Begin()                 a new lay
--       painter:Area(key, shape, project, stride, clip, box) -> area
--           the shape drawn (made or kept): each loop's every `stride`th
--           point through project(x, y) -> px, py (the parent's units from
--           its TOPLEFT, y negative downward), each stretch through clip(ax,
--           ay, bx, by) -> the part to draw or nil (the minimap's round or
--           square); a loop whose box misses `box` (the shape's units)
--           skipped. A place or a size written only when it changed
--       painter:End()                   the areas not drawn since Begin go
--                                       (one held for its out-motion stays)
--       painter:Scale(u)                the parent's units a screen pixel:
--                                       the edge and the glow one size on
--                                       the screen
--       painter:Hide()                  every area out of sight, kept (a
--                                       map's pins cleared before a new lay)
--       painter:Each(fn)                fn(area) for every area drawn now
--   area   .frame (its alpha the area's: dimmed, faded), .glow (its glow's
--          frame: GLOW_REST at rest, lit on a hover), .key, .shape, .new
--          (made by this lay)
--       QA.Trace(area, p)       part p (0..1) of each loop shown, from its
--                               mark's end; nil: all of it
--   the motion, the edges' and the marks' (below: "The motion")
-- Nothing at login: the first shape and the first painter are made when a
-- map or the minimap first draws an area.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI

local QA = {}
MelloUI.QuestAreas = QA

local exp, sqrt, floor, ceil, huge = math.exp, math.sqrt, math.floor, math.ceil, math.huge

local T = {
	RADIUS = 60,      -- yards: the edge round a lone place
	SIGMA = 52,       -- yards: a place's hill (places up to about 170 yards apart join in one area)
	CELL = 9,         -- yards: the grid
	STEP = 10,        -- yards between the edge's points
	JOIN = 276,       -- yards: places this far apart lie in parts of their own (no field reaches across)
	EDGE = "Interface\\AddOns\\MelloUI\\Media\\Textures\\QuestAreaEdge",
	GLOW = "Interface\\AddOns\\MelloUI\\Media\\Textures\\QuestAreaGlow",
	COLOUR = "selectedTrim",
	EDGE_PX = 7,      -- the edge on the screen: the casing, the gold line (2 px), the casing
	GLOW_IN = 6,      -- px inside the edge a glow dab's middle
	GLOW_PX = 20,     -- a dab's size (it reaches back under the edge)
	GLOW_A = 0.25,    -- a dab's alpha (a few overlap: the band about a third)
	GLOW_REST = 0.65, -- the glow frame's alpha at rest; a lit area's (hovered) 1, a swell's top 1
	MAX_LINES = 1200, -- one area's lines, and its dabs, at most
}
QA.T = T

local LEVEL = exp(-T.RADIUS * T.RADIUS / (2 * T.SIGMA * T.SIGMA))
local REACH = 2.6 * T.SIGMA   -- a place's hill counted to here (past it under a twentieth of the edge's level)

--------------------------------------------------------------------------------
-- The shape
--------------------------------------------------------------------------------

-- the field of the places at (x, y)
local function FieldAt(xs, ys, members, x, y)
	local s, k = 0, 1 / (2 * T.SIGMA * T.SIGMA)
	for _, i in ipairs(members) do
		local dx, dy = x - xs[i], y - ys[i]
		local d2 = dx * dx + dy * dy
		if d2 < REACH * REACH then
			s = s + exp(-d2 * k)
		end
	end
	return s
end

-- the places in parts: single linkage within JOIN
local function Parts(xs, ys)
	local n, seen, out = #xs, {}, {}
	local j2 = T.JOIN * T.JOIN
	for i = 1, n do
		if not seen[i] then
			seen[i] = true
			local part, top, stack = {}, 1, { i }
			while top > 0 do
				local a = stack[top]
				stack[top] = nil
				top = top - 1
				part[#part + 1] = a
				for b = 1, n do
					if not seen[b] then
						local dx, dy = xs[a] - xs[b], ys[a] - ys[b]
						if dx * dx + dy * dy <= j2 then
							seen[b] = true
							top = top + 1
							stack[top] = b
						end
					end
				end
			end
			out[#out + 1] = part
		end
	end
	return out
end

-- a closed loop smoothed (Chaikin's corner cutting) and spaced STEP apart: a flat list x1, y1, x2, y2, ...
local function Smooth(px, py)
	for _ = 1, 2 do
		local n = #px
		local qx, qy = {}, {}
		for i = 1, n do
			local j = i % n + 1
			local ax, ay, bx, by = px[i], py[i], px[j], py[j]
			qx[#qx + 1], qy[#qy + 1] = ax * 0.75 + bx * 0.25, ay * 0.75 + by * 0.25
			qx[#qx + 1], qy[#qy + 1] = ax * 0.25 + bx * 0.75, ay * 0.25 + by * 0.75
		end
		px, py = qx, qy
	end
	local out = { px[1], py[1] }
	local acc, n = 0, #px
	for i = 2, n + 1 do
		local a, b = i - 1, (i - 1) % n + 1
		local bx, by = px[b], py[b]
		acc = acc + sqrt((bx - px[a]) ^ 2 + (by - py[a]) ^ 2)
		if acc >= T.STEP and i <= n then
			out[#out + 1], out[#out + 2] = bx, by
			acc = 0
		end
	end
	return out
end

-- whether (x, y) lies inside a flat loop (even-odd)
local function Inside(x, y, loop)
	local c, n = false, #loop
	local jx, jy = loop[n - 1], loop[n]
	for i = 1, n - 1, 2 do
		local ix, iy = loop[i], loop[i + 1]
		if (iy > y) ~= (jy > y) and x < (jx - ix) * (y - iy) / (jy - iy) + ix then
			c = not c
		end
		jx, jy = ix, iy
	end
	return c
end
QA.Inside = Inside

-- The level line of one part's field: its loops (flat lists, smoothed). Marching squares on the grid's points
-- (f > LEVEL inside); a crossing is named by its grid edge (a horizontal edge odd, a vertical even), so the
-- stretches chain exactly
local function Trace(xs, ys, members, loops)
	local cell, m = T.CELL, T.RADIUS + 1.5 * T.SIGMA
	local x0, y0, x1, y1 = huge, huge, -huge, -huge
	for _, i in ipairs(members) do
		if xs[i] < x0 then x0 = xs[i] end
		if xs[i] > x1 then x1 = xs[i] end
		if ys[i] < y0 then y0 = ys[i] end
		if ys[i] > y1 then y1 = ys[i] end
	end
	x0, y0, x1, y1 = x0 - m, y0 - m, x1 + m, y1 + m
	local nx, ny = floor((x1 - x0) / cell) + 2, floor((y1 - y0) / cell) + 2
	local f = {}
	for k = 1, nx * ny do
		f[k] = 0
	end
	local k2 = 1 / (2 * T.SIGMA * T.SIGMA)
	local r = ceil(REACH / cell)
	for _, p in ipairs(members) do
		local px, py = xs[p], ys[p]
		local ci, cj = floor((px - x0) / cell + 0.5), floor((py - y0) / cell + 0.5)
		for j = math.max(0, cj - r), math.min(ny - 1, cj + r) do
			local dy = y0 + j * cell - py
			for i = math.max(0, ci - r), math.min(nx - 1, ci + r) do
				local dx = x0 + i * cell - px
				local d2 = dx * dx + dy * dy
				if d2 < REACH * REACH then
					local k = j * nx + i + 1
					f[k] = f[k] + exp(-d2 * k2)
				end
			end
		end
	end
	local t = LEVEL
	-- the crossing on an edge: its place (kept by the edge's id)
	local ex, ey = {}, {}
	local function H(i, j)   -- the edge (i, j)-(i+1, j)
		local id = (j * nx + i) * 2 + 1
		if not ex[id] then
			local a, b = f[j * nx + i + 1], f[j * nx + i + 2]
			ex[id], ey[id] = x0 + (i + (t - a) / (b - a)) * cell, y0 + j * cell
		end
		return id
	end
	local function V(i, j)   -- the edge (i, j)-(i, j+1)
		local id = (j * nx + i) * 2 + 2
		if not ex[id] then
			local a, b = f[j * nx + i + 1], f[(j + 1) * nx + i + 1]
			ex[id], ey[id] = x0 + i * cell, y0 + (j + (t - a) / (b - a)) * cell
		end
		return id
	end
	local n1, n2 = {}, {}
	local function Join(a, b)
		if n1[a] then n2[a] = b else n1[a] = b end
		if n1[b] then n2[b] = a else n1[b] = a end
	end
	for j = 0, ny - 2 do
		for i = 0, nx - 2 do
			local ftl, ftr = f[j * nx + i + 1], f[j * nx + i + 2]
			local fbl, fbr = f[(j + 1) * nx + i + 1], f[(j + 1) * nx + i + 2]
			local c = (ftl > t and 8 or 0) + (ftr > t and 4 or 0) + (fbr > t and 2 or 0) + (fbl > t and 1 or 0)
			if c ~= 0 and c ~= 15 then
				if c == 1 or c == 14 then
					Join(V(i, j), H(i, j + 1))
				elseif c == 2 or c == 13 then
					Join(H(i, j + 1), V(i + 1, j))
				elseif c == 3 or c == 12 then
					Join(V(i, j), V(i + 1, j))
				elseif c == 4 or c == 11 then
					Join(H(i, j), V(i + 1, j))
				elseif c == 6 or c == 9 then
					Join(H(i, j), H(i, j + 1))
				elseif c == 7 or c == 8 then
					Join(H(i, j), V(i, j))
				else
					-- a saddle: the middle's value decides which corners join
					local mid = (ftl + ftr + fbl + fbr) / 4 > t
					if (c == 5) == mid then
						Join(H(i, j), V(i, j))           -- the top-left corner cut off
						Join(H(i, j + 1), V(i + 1, j))   -- and the bottom-right
					else
						Join(H(i, j), V(i + 1, j))       -- the top-right corner cut off
						Join(V(i, j), H(i, j + 1))       -- and the bottom-left
					end
				end
			end
		end
	end
	-- the loops: each crossing walked once
	local seen = {}
	for id in pairs(n1) do
		if not seen[id] and n2[id] then
			local lx, ly = {}, {}
			local prev, cur = nil, id
			repeat
				seen[cur] = true
				lx[#lx + 1], ly[#ly + 1] = ex[cur], ey[cur]
				local nxt = n1[cur] ~= prev and n1[cur] or n2[cur]
				if n1[cur] == n2[cur] then
					nxt = n1[cur]
				end
				prev, cur = cur, nxt
			until cur == nil or cur == id or seen[cur]
			if #lx >= 6 then
				loops[#loops + 1] = Smooth(lx, ly)
			end
		end
	end
end

local shapes = {}

function QA.Shape(key, xs, ys)
	if key ~= nil and shapes[key] then
		return shapes[key]
	end
	local n = type(xs) == "table" and #xs or 0
	if n == 0 or type(ys) ~= "table" or #ys ~= n then
		return nil
	end
	local loops, all = {}, {}
	for i = 1, n do
		all[i] = i
	end
	for _, part in ipairs(Parts(xs, ys)) do
		Trace(xs, ys, part, loops)
	end
	if #loops == 0 then
		return nil
	end
	local shape = { loops = loops, probe = {}, marks = {}, box = {} }
	for li, loop in ipairs(loops) do
		local bx0, by0, bx1, by1 = huge, huge, -huge, -huge
		for i = 1, #loop - 1, 2 do
			local x, y = loop[i], loop[i + 1]
			if x < bx0 then bx0 = x end
			if x > bx1 then bx1 = x end
			if y < by0 then by0 = y end
			if y > by1 then by1 = y end
		end
		shape.box[li] = { bx0, by0, bx1, by1 }
		-- the mark: the places inside, their middle (or the place nearest it)
		local cx, cy, k = 0, 0, 0
		for i = 1, n do
			if Inside(xs[i], ys[i], loop) then
				cx, cy, k = cx + xs[i], cy + ys[i], k + 1
			end
		end
		if k > 0 then
			cx, cy = cx / k, cy / k
			if not Inside(cx, cy, loop) then
				local best, bx, by = huge, cx, cy
				for i = 1, n do
					local d = (xs[i] - cx) ^ 2 + (ys[i] - cy) ^ 2
					if d < best and Inside(xs[i], ys[i], loop) then
						best, bx, by = d, xs[i], ys[i]
					end
				end
				cx, cy = bx, by
			end
			shape.marks[#shape.marks + 1] = { cx, cy, li }
			-- the loop begins at its point nearest the mark (a trace draws from there)
			local best, at = huge, 1
			for i = 1, #loop - 1, 2 do
				local d = (loop[i] - cx) ^ 2 + (loop[i + 1] - cy) ^ 2
				if d < best then
					best, at = d, i
				end
			end
			if at > 1 then
				local turned = {}
				for i = at, #loop do
					turned[#turned + 1] = loop[i]
				end
				for i = 1, at - 1 do
					turned[#turned + 1] = loop[i]
				end
				loops[li] = turned
				loop = turned
			end
		end
		-- the inside: a little off the first stretch's middle, the side where the field is above the level
		local ax, ay, bx, by = loop[1], loop[2], loop[3], loop[4]
		local mx, my = (ax + bx) / 2, (ay + by) / 2
		local dx, dy = bx - ax, by - ay
		local len = sqrt(dx * dx + dy * dy)
		if len > 0 then
			local h = T.CELL / len
			local lx, ly = mx - dy * h, my + dx * h
			if FieldAt(xs, ys, all, lx, ly) > LEVEL then
				shape.probe[li] = { lx, ly }
			else
				shape.probe[li] = { mx + dy * h, my - dx * h }
			end
		else
			shape.probe[li] = { mx, my }
		end
	end
	if key ~= nil then
		shapes[key] = shape
	end
	return shape
end

-- An objective's places (MelloUI.QuestObjectives' entry: kind, name, alt, continent, x1, y1, x2, y2, ...) as world
-- yards, and the key of their shape: the continent and the places themselves, so objectives with the same places
-- (Gold Dust and Large Candle: the same kobolds) share one shape, one area; xs, ys reused until the next call
local pxs, pys, parts = {}, {}, {}
function QA.Places(entry)
	wipe(pxs)
	wipe(pys)
	wipe(parts)
	parts[1] = entry[4]
	local Finite = MelloUI.Safe.Finite
	for k = 5, #entry - 1, 2 do
		local x, y = Finite(entry[k]), Finite(entry[k + 1])
		if x and y then
			pxs[#pxs + 1], pys[#pys + 1] = x, y
			parts[#parts + 1] = floor(x) .. "," .. floor(y)
		end
	end
	return pxs, pys, table.concat(parts, ";")
end

-- (the tests, /mellomap dump) the shapes kept
function QA.Kept()
	local n = 0
	for _ in pairs(shapes) do
		n = n + 1
	end
	return n
end

--------------------------------------------------------------------------------
-- The painter
--------------------------------------------------------------------------------

local Painter = {}
Painter.__index = Painter

-- noGlow: the edge alone (the minimap: drawn again every tick)
function QA.Painter(parent, drawLayer, noGlow)
	return setmetatable({ parent = parent, layer = drawLayer or "ARTWORK", areas = {}, spare = {}, gen = 0,
		unit = 1, lines = 0, dabs = 0, noGlow = noGlow and true or false }, Painter)
end

function Painter:Begin()
	self.gen = self.gen + 1
end

-- a piece's colour (the palette's, by key) and its smoothness: never snapped to the pixel grid (the areas lie on
-- scaled canvases and move by fractions of a pixel: snapped, the edge stepped and shimmered -- the map's tiles do the
-- same, MapCanvas.lua)
local function Paint(region)
	if MelloUI.Painter and MelloUI.Painter.Paint then
		MelloUI.Painter.Paint(region, T.COLOUR, "vertex")
	end
	if region.SetSnapToPixelGrid then
		region:SetSnapToPixelGrid(false)
		region:SetTexelSnappingBias(0)
	end
end

local function NewLine(self, area)
	local l = area.edge:CreateLine(nil, self.layer)
	l:SetTexture(T.EDGE)
	l:SetThickness(T.EDGE_PX * self.unit)
	l.atW = self.unit
	Paint(l)
	self.lines = self.lines + 1
	return l
end

local function NewDab(self, area)
	local d = area.glow:CreateTexture(nil, self.layer)
	d:SetTexture(T.GLOW)
	d:SetAlpha(T.GLOW_A)
	Paint(d)
	self.dabs = self.dabs + 1
	return d
end

local function Place(l, frame, ax, ay, bx, by)
	if l.ax ~= ax or l.ay ~= ay or l.bx ~= bx or l.by ~= by then
		l.ax, l.ay, l.bx, l.by = ax, ay, bx, by
		l:SetStartPoint("TOPLEFT", frame, ax, ay)
		l:SetEndPoint("TOPLEFT", frame, bx, by)
	end
end

-- a dab of the glow at its edge point, GLOW_IN px inside along the inward normal (the painter's unit a px)
local function PlaceDab(d, frame, u)
	local x, y = d.px + d.nx * T.GLOW_IN * u, d.py + d.ny * T.GLOW_IN * u
	if d.ax ~= x or d.ay ~= y then
		d.ax, d.ay = x, y
		d:ClearAllPoints()
		d:SetPoint("CENTER", frame, "TOPLEFT", x, y)
	end
	if d.atU ~= u then
		d.atU = u
		d:SetSize(T.GLOW_PX * u, T.GLOW_PX * u)
	end
end

-- which pieces show: drawn this lay and within the trace
local function Showing(area)
	local p = area.trace
	for i = 1, area.used do
		local l = area.lines[i]
		local on = l.drawn and (p == nil or l.k <= ceil(p * l.count))
		if l.on ~= on then
			l.on = on
			l:SetShown(on)
		end
	end
	for i = area.used + 1, #area.lines do
		local l = area.lines[i]
		if l.on ~= false then
			l.on = false
			l:Hide()
		end
	end
	for i = 1, area.ndabs do
		local d = area.dabs[i]
		local on = p == nil or d.k <= ceil(p * d.count)
		if d.on ~= on then
			d.on = on
			d:SetShown(on)
		end
	end
	for i = area.ndabs + 1, #area.dabs do
		local d = area.dabs[i]
		if d.on ~= false then
			d.on = false
			d:Hide()
		end
	end
end

-- the projected points of a loop, kept between laps (no table a lay)
local qx, qy = {}, {}

function Painter:Area(key, shape, project, stride, clip, box)
	local area = self.areas[key]
	if not area then
		area = table.remove(self.spare)
		if not area then
			local f = CreateFrame("Frame", nil, self.parent)
			f:SetAllPoints(self.parent)
			-- (the glow under the edge: two frames of their own over the area's)
			local glow = CreateFrame("Frame", nil, f)
			glow:SetAllPoints(f)
			local edge = CreateFrame("Frame", nil, f)
			edge:SetAllPoints(f)
			edge:SetFrameLevel(glow:GetFrameLevel() + 1)
			area = { frame = f, glow = glow, edge = edge, lines = {}, dabs = {}, used = 0, ndabs = 0 }
		end
		area.frame:SetAlpha(1)
		area.glow:SetAlpha(T.GLOW_REST)
		area.frame:Show()
		area.key, area.new, area.trace, area.hold = key, true, nil, nil
		self.areas[key] = area
	else
		area.new = false
	end
	area.gen, area.shape, area.painter = self.gen, shape, self
	if not area.frame:IsShown() then
		area.frame:Show()
	end
	stride = math.max(1, floor(stride or 1))
	local used, ndabs, edge, u = 0, 0, area.edge, self.unit
	local glow = not self.noGlow
	for li, loop in ipairs(shape.loops) do
		local b = box and shape.box and shape.box[li]
		if not b or (b[3] >= box[1] and b[1] <= box[3] and b[4] >= box[2] and b[2] <= box[4]) then
			local pts = #loop / 2
			local count = ceil(pts / stride)
			-- the points taken, projected (nil off the projection)
			for s = 0, count - 1 do
				local j = s * stride
				qx[s + 1], qy[s + 1] = project(loop[2 * j + 1], loop[2 * j + 2])
			end
			-- the inside: the probe on the left of the first stretch, or on its right (y up)
			local inLeft = true
			local probe = shape.probe[li]
			local px, py = project(probe[1], probe[2])
			if px and qx[1] and qx[2] then
				inLeft = (qx[2] - qx[1]) * (py - qy[1]) - (qy[2] - qy[1]) * (px - qx[1]) > 0
			end
			for s = 1, count do
				local ax, ay = qx[s], qy[s]
				local n = s % count + 1
				local bx, by = qx[n], qy[n]
				if ax and bx and used < T.MAX_LINES then
					local cax, cay, cbx, cby = ax, ay, bx, by
					if clip then
						cax, cay, cbx, cby = clip(ax, ay, bx, by)
					end
					if cax then
						used = used + 1
						local l = area.lines[used]
						if not l then
							l = NewLine(self, area)
							area.lines[used] = l
						end
						l.k, l.count, l.drawn = s, count, true
						Place(l, edge, cax, cay, cbx, cby)
					end
				end
				-- the glow's dab at this point: inside along the normal (the stretches either side its tangent)
				if glow and ax and ndabs < T.MAX_LINES then
					local p = s == 1 and count or s - 1
					local tx, ty = (bx or ax) - (qx[p] or ax), (by or ay) - (qy[p] or ay)
					local len = sqrt(tx * tx + ty * ty)
					if len > 0 then
						ndabs = ndabs + 1
						local d = area.dabs[ndabs]
						if not d then
							d = NewDab(self, area)
							area.dabs[ndabs] = d
						end
						local nx, ny = -ty / len, tx / len   -- (the left normal, y up)
						if not inLeft then
							nx, ny = -nx, -ny
						end
						d.px, d.py, d.nx, d.ny, d.k, d.count = ax, ay, nx, ny, s, count
						PlaceDab(d, area.glow, u)
					end
				end
			end
		end
	end
	area.used, area.ndabs = used, ndabs
	Showing(area)
	return area
end

function Painter:End()
	for _, area in pairs(self.areas) do
		if area.gen ~= self.gen and not area.hold then
			QA.Release(self, area)
		end
	end
end

-- an area given back (its pieces hidden, its frames kept for the next one)
function QA.Release(painter, area)
	local Anim = MelloUI.Anim
	if Anim then
		Anim:Stop(area.frame, "alpha")
		Anim:Stop(area.glow, "alpha")
		Anim:Stop(area, "drive")
	end
	area.used, area.ndabs, area.trace, area.hold = 0, 0, nil, nil
	Showing(area)
	area.frame:Hide()
	if painter.areas[area.key] == area then
		painter.areas[area.key] = nil
	end
	painter.spare[#painter.spare + 1] = area
end

-- every area out of sight (kept: the next lay draws them again, or lets them go)
function Painter:Hide()
	for _, area in pairs(self.areas) do
		if not area.hold then
			area.frame:Hide()
		end
	end
end

-- the parent's units a screen pixel: the edge's thickness and the glow's dabs one size on the screen
function Painter:Scale(u)
	if u == self.unit or not (u and u > 0 and u < huge) then
		return
	end
	self.unit = u
	for _, area in pairs(self.areas) do
		for i = 1, #area.lines do
			local l = area.lines[i]
			if l.atW ~= u then
				l.atW = u
				l:SetThickness(T.EDGE_PX * u)
			end
		end
		for i = 1, area.ndabs do
			PlaceDab(area.dabs[i], area.glow, u)
		end
	end
end

function Painter:Each(fn)
	for _, area in pairs(self.areas) do
		fn(area)
	end
end

--------------------------------------------------------------------------------
-- The motion (MelloUI.Anim: one engine; Reduce Motion lands at once). One-shot moves, nothing that repeats:
--   the edge   QA.TraceIn(area, time, delay) drawn round from each loop's mark after `delay`; QA.TraceOut(area, time,
--              onDone) drawn back into it; QA.Swell(area, time) swelled once (thicker, settling)
--   a mark     (a frame of ours with its icon texture: the zone map's marks, the minimap's)
--              QA.MarkPop(frame, icon, size, delay)  popped in after `delay` (its icon grown from small, overshooting a
--                                                    little; the frame faded in)
--              QA.MarkBump(frame, icon, size[, noRing])  swelled once with a gold ring of light (its progress);
--                                                    noRing: the swell alone (you stepping into its area)
--              QA.MarkLift(frame, icon, size, on)    lifted a little bigger (hovered, you in its area) or set down
--              QA.MarkTick(frame, icon, size, onDone) a tick drawn on it, a ring, then it shrinks away (done)
--              QA.MarkStill(frame, icon, size)       every move of it stopped, at its rest
-- Times: T.POP, T.TRACE, T.GONE, T.SWELL, T.LIFT (seconds); T.RING_K the ring's growth
--------------------------------------------------------------------------------

T.POP, T.TRACE, T.GONE, T.SWELL, T.LIFT, T.RING, T.RING_K, T.TICK, T.HOLD = 0.3, 0.6, 0.5, 0.6, 0.15, 0.6, 1.9, 0.3, 0.3
T.RING_ART = "Interface\\AddOns\\MelloUI\\Media\\FrameFX\\Light\\halo_white"   -- look-ok: a moment's light, both looks

local function Clamp(v)
	return v < 0 and 0 or (v > 1 and 1 or v)
end

-- a little past the end and back (a pop's overshoot)
local function Back(p)
	local c1 = 1.9
	return 1 + (c1 + 1) * (p - 1) ^ 3 + c1 * (p - 1) ^ 2
end

function QA.Trace(area, p)
	area.trace = p
	Showing(area)
end

local function TraceStep(area, v)
	local t = v * area.tTotal - area.tDelay
	local p = Clamp(t / area.tTime)
	if area.traceOut then
		QA.Trace(area, 1 - p * p)
	else
		QA.Trace(area, 1 - (1 - p) ^ 3)
	end
end

local function TraceDone(area)
	if area.traceOut then
		local done = area.onOut
		area.onOut = nil
		if done then
			done(area)
		end
	else
		QA.Trace(area, nil)
	end
end

function QA.TraceIn(area, time, delay)
	local Anim = MelloUI.Anim
	area.traceOut = false
	if not Anim or Anim.reduceMotion then
		QA.Trace(area, nil)
		return
	end
	area.tTime, area.tDelay = time or T.TRACE, delay or 0
	area.tTotal = area.tTime + area.tDelay
	QA.Trace(area, 0)
	Anim:Drive(area, TraceStep, area.tTotal, "linear", TraceDone)
end

function QA.TraceOut(area, time, onDone)
	local Anim = MelloUI.Anim
	area.traceOut, area.onOut = true, onDone
	if not Anim or Anim.reduceMotion then
		TraceDone(area)
		return
	end
	area.tTime, area.tDelay = time or T.GONE, 0
	area.tTotal = area.tTime
	Anim:Drive(area, TraceStep, area.tTotal, "linear", TraceDone)
end

local function SwellStep(area, v)
	local painter = area.painter
	local up = math.sin(math.pi * v)
	if painter and not painter.noGlow then
		area.glow:SetAlpha(T.GLOW_REST + (1 - T.GLOW_REST) * up)
		return
	end
	local u = painter and painter.unit or 1
	local k = T.EDGE_PX * u * (1 + 0.6 * up)
	for i = 1, area.used do
		local l = area.lines[i]
		if l.on then
			l.atW = v < 1 and -1 or u
			l:SetThickness(k)
		end
	end
end

local function SwellDone(area)
	SwellStep(area, 0)
end

function QA.Swell(area, time)
	local Anim = MelloUI.Anim
	if not Anim or Anim.reduceMotion or not area.used then
		return
	end
	-- (a trace under way is a drive of its own: no swell over it)
	if Anim:IsRunning(area, "drive") then
		return
	end
	Anim:Drive(area, SwellStep, time or T.SWELL, "linear", SwellDone)
end

-- a mark's moving parts, by its frame (weak): its icon and size, the ring and the tick made on its first need
local fx = setmetatable({}, { __mode = "k" })

local function Fx(frame, icon, size)
	local f = fx[frame]
	if not f then
		f = {}
		fx[frame] = f
	end
	f.icon, f.size = icon, size
	return f
end

local function Ring(frame, f)
	local ring = f.ring
	if not ring then
		ring = frame:CreateTexture(nil, "OVERLAY", nil, 7)
		ring:SetTexture(T.RING_ART)
		ring:SetBlendMode("ADD")
		ring:SetPoint("CENTER", frame, "CENTER", 0, 0)
		if MelloUI.Painter and MelloUI.Painter.Paint then
			MelloUI.Painter.Paint(ring, T.COLOUR, "vertex")
		end
		ring:Hide()
		f.ring = ring
	end
	ring:SetSize(f.size * 1.3, f.size * 1.3)
	return ring
end

local function Size(f, k)
	local s = f.size * k
	f.icon:SetSize(s, s)
end

-- the pop: `delay` waited, then the icon from 0.4 of its size past 1 and back, the frame faded in
local function PopStep(frame, v)
	local f = fx[frame]
	local p = Clamp((v * f.total - f.delay) / T.POP)
	Size(f, 0.4 + 0.6 * Back(p))
	frame:SetAlpha(Clamp(p * 3))
end

local function Rest(frame)
	local f = fx[frame]
	if f then
		Size(f, f.lifted and 1.18 or 1)
	end
	frame:SetAlpha(1)
end

function QA.MarkPop(frame, icon, size, delay)
	local Anim = MelloUI.Anim
	local f = Fx(frame, icon, size)
	f.lifted = false
	if not Anim or Anim.reduceMotion then
		Rest(frame)
		return
	end
	f.delay = delay or 0
	f.total = f.delay + T.POP
	PopStep(frame, 0)
	Anim:Drive(frame, PopStep, f.total, "linear", Rest)
end

local function BumpStep(frame, v)
	Size(fx[frame], 1 + 0.3 * math.sin(math.pi * Clamp(v * 2)))
end

function QA.MarkBump(frame, icon, size, noRing)
	local Anim = MelloUI.Anim
	local f = Fx(frame, icon, size)
	if not Anim or Anim.reduceMotion then
		return
	end
	if not noRing then
		Anim:Burst(Ring(frame, f), T.RING_K, 0.9, T.RING)
	end
	Anim:Drive(frame, BumpStep, T.POP * 2, "linear", Rest)
end

local function LiftStep(frame, v)
	local f = fx[frame]
	local from, to = f.liftFrom, f.lifted and 1.18 or 1
	Size(f, from + (to - from) * (1 - (1 - v) ^ 3))
end

function QA.MarkLift(frame, icon, size, on)
	local Anim = MelloUI.Anim
	local f = Fx(frame, icon, size)
	local w = f.icon:GetWidth()
	f.liftFrom = (type(w) == "number" and size > 0) and w / size or 1
	f.lifted = on and true or false
	if not Anim or Anim.reduceMotion then
		Rest(frame)
		return
	end
	Anim:Drive(frame, LiftStep, T.LIFT, "linear", Rest)
end

-- the tick: drawn left to right over the icon (the widget glyph "check"), a ring, held, then the mark shrinks away
local function TickStep(frame, v)
	local f = fx[frame]
	local t = v * (T.TICK + T.HOLD + T.GONE)
	local draw = Clamp(t / T.TICK)
	local W = MelloUI.Widgets
	if f.tick and W and W.Glyph then
		local p = draw < 0.02 and 0.02 or draw
		W.Glyph(f.tick, "check", p)
		f.tick:SetSize(f.size * 0.7 * p, f.size * 0.7)
	end
	local gone = Clamp((t - T.TICK - T.HOLD) / T.GONE)
	if gone > 0 and not f.burst then
		f.burst = true
		local Anim = MelloUI.Anim
		Anim:Burst(Ring(frame, f), T.RING_K, 0.9, T.RING)
	end
	Size(f, 1 - 0.7 * gone * gone)
	frame:SetAlpha(1 - gone)
end

local function TickDone(frame)
	local f = fx[frame]
	if f.tick then
		f.tick:Hide()
	end
	frame:SetAlpha(0)
	local done = f.onDone
	f.onDone = nil
	if done then
		done(frame)
	end
end

function QA.MarkTick(frame, icon, size, onDone)
	local Anim = MelloUI.Anim
	local f = Fx(frame, icon, size)
	f.onDone, f.burst = onDone, false
	if not f.tick then
		f.tick = frame:CreateTexture(nil, "OVERLAY", nil, 6)
		f.tick:SetPoint("LEFT", frame, "CENTER", -size * 0.35, 0)
		if MelloUI.Painter and MelloUI.Painter.Paint then
			MelloUI.Painter.Paint(f.tick, "text", "vertex")
		end
	end
	if not Anim or Anim.reduceMotion then
		TickDone(frame)
		return
	end
	f.tick:Show()
	Size(f, 1)
	frame:SetAlpha(1)
	TickStep(frame, 0)
	Anim:Drive(frame, TickStep, T.TICK + T.HOLD + T.GONE, "linear", TickDone)
end

function QA.MarkStill(frame, icon, size)
	local Anim = MelloUI.Anim
	local f = Fx(frame, icon, size)
	f.lifted = false
	if Anim then
		Anim:Stop(frame, "drive")
	end
	if f.tick then
		f.tick:Hide()
	end
	Rest(frame)
end

--------------------------------------------------------------------------------
-- MelloUI Map - the trails (2.1.0, qu-01; the user, 2026-10-30: "the boats and
-- zepelins have their connections shown with high quality curved trails"; the
-- user's picks of BuildData/output/qu01_map_sketch: look A, a soft gold line,
-- and W1, the trails at full strength)
--
-- Every boat's and zeppelin's way from dock to dock, one trail a pair of
-- docks (the Quest List's transports: Forever's own paths, your side's and
-- the neutral ones):
--   a course   where the ship sails it on one map with no jump (the data's
--              course points, its path's nodes), smoothed (Chaikin's corner
--              cutting)
--   an arc     elsewhere (it changes map or is carried at sea): a smooth curve
--              from dock to dock, its middle BULGE of its length aside, to the
--              side the data names (the side with less land under it:
--              Tools/build_quest_list.py)
--   a stub     a way to a map the world does not show: the ship's way out of
--              the harbour, fading (qu-03: Zephras Isle's airships were the
--              stubs until the map laid the isle, MapData.isles; their ways
--              are arcs now, their side the data's)
-- The look (A): ONE Line a stretch in the quest areas' edge picture
-- (QuestAreaEdge: a dark casing, the gold core, the casing; the same both
-- ways, so the joints close), tinted the palette's selectedTrim
-- (MelloUI.Painter), never snapped to the pixel grid. On the canvas's root in
-- world units: it pans and zooms with the maps, nothing of ours runs for a
-- move; one width on the screen at every zoom (its thickness written again
-- when the zoom moved by a tenth). Only the stretches in the canvas's cull
-- box are drawn, the rest hidden and unanchored (the canvas's rule); a
-- stretch ends where the way has turned about 3 degrees (never shorter than
-- SEG_PX, never longer than MAX_PX on the screen: it never strays half a
-- pixel from the curve), taken again at each new cull box or zoom step: a few
-- hundred Lines at the world's zoom.
-- Nothing at login: the trails are worked out at the map's first open, their
-- Lines made as they first come into view.
--
--   Trails.Init(canvas)    (the window's build) the holder on the root
--   Trails.Open()          the window shown: the trails worked out once, laid
--   Trails.View()          the view moved (canvas.onView)
--   Trails.Show(on)        the transports' switch ("Boats, zeppelins and portals")
--   Trails.S               the state (the tests)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local ipairs, type, sqrt, floor, abs = ipairs, type, math.sqrt, math.floor, math.abs

local Trails = {}
ns.Trails = Trails

local T = {
	KINDS = { [1] = true, [2] = true, [5] = true },   -- the boats, the zeppelins and the airships (not the portal, the tram)
	BULGE = 0.12,        -- an arc's middle this share of its length aside (Tools/build_quest_list.py ARC_BULGE)
	ARC_POINTS = 64,     -- an arc's points
	SMOOTH = 4,          -- a course's rounds of corner cutting
	DOCK = 100,          -- yards: a course's end this near the next dock reaches it
	EDGE = "Interface\\AddOns\\MelloUI\\Media\\Textures\\QuestAreaEdge",
	COLOUR = "selectedTrim",
	EDGE_PX = 7,         -- the line on the screen: the casing, the gold core (2 px), the casing
	SEG_PX = 6,          -- a stretch at least this long on the screen (shorter ones joined) ...
	MAX_PX = 24,         -- ... at most this long ...
	TURN = 0.05,         -- ... ending where the way has turned this much (radians, about 3 degrees) since it began
	ZOOM_STEP = 1.1,     -- the width and the stretches again when the zoom moved by this factor
	FADE = 1.3,          -- a stub's fade along its way (alpha (1 - share) ^ FADE)
	MAX_LINES = 2400,    -- the Lines at most
	LEVEL = 2,           -- the holder this far under the pins' level (the quest areas' holder: 1)
	DATA_SIDE = { Alliance = 1, Horde = 2 },
}
Trails.T = T

local S = { canvas = nil, holder = nil, trails = nil, lines = {}, used = 0, k = nil, cuts = nil, on = true,
	shown = false }
Trails.S = S

--------------------------------------------------------------------------------
-- The shapes: worked out once (the first open), in world units
--------------------------------------------------------------------------------

local function Side()
	return UnitFactionGroup and MelloUI.Safe.Text((UnitFactionGroup("player"))) or nil
end

-- Chaikin's corner cutting of a flat list x1, y1, x2, y2 ..., the ends kept
local function Smooth(pts, rounds)
	for _ = 1, rounds do
		local n = #pts / 2
		if n < 3 then
			return pts
		end
		local out = { pts[1], pts[2] }
		for i = 1, n - 1 do
			local ax, ay, bx, by = pts[2 * i - 1], pts[2 * i], pts[2 * i + 1], pts[2 * i + 2]
			out[#out + 1], out[#out + 2] = 0.75 * ax + 0.25 * bx, 0.75 * ay + 0.25 * by
			out[#out + 1], out[#out + 2] = 0.25 * ax + 0.75 * bx, 0.25 * ay + 0.75 * by
		end
		out[#out + 1], out[#out + 2] = pts[2 * n - 1], pts[2 * n]
		pts = out
	end
	return pts
end

-- an arc from (ax, ay) to (bx, by), its middle BULGE of its length to `side` of the left normal (y down)
local function Arc(ax, ay, bx, by, side)
	local dx, dy = bx - ax, by - ay
	local d = sqrt(dx * dx + dy * dy)
	if d <= 0 or d ~= d then
		return nil
	end
	local s = (side == -1) and -1 or 1
	local cx, cy = (ax + bx) / 2 - s * dy / d * d * T.BULGE, (ay + by) / 2 + s * dx / d * d * T.BULGE
	local out, n = {}, T.ARC_POINTS
	for i = 0, n do
		local t = i / n
		local u = 1 - t
		out[#out + 1] = u * u * ax + 2 * u * t * cx + t * t * bx
		out[#out + 1] = u * u * ay + 2 * u * t * cy + t * t * by
	end
	return out
end

-- a row's course on the canvas (world units), from its dock; nil without one
local function Course(point, cont, list)
	if type(list) ~= "table" or #list < 4 then
		return nil
	end
	local out = {}
	for i = 1, #list - 1, 2 do
		local x, y = point(cont, list[i], list[i + 1])
		if x then
			out[#out + 1], out[#out + 2] = x, y
		end
	end
	return #out >= 4 and out or nil
end

local function Box(t)
	local p = t.pts
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for i = 1, #p - 1, 2 do
		local x, y = p[i], p[i + 1]
		if x < x0 then x0 = x end
		if x > x1 then x1 = x end
		if y < y0 then y0 = y end
		if y > y1 then y1 = y end
	end
	t.x0, t.y0, t.x1, t.y1 = x0, y0, x1, y1
end

-- the trails of the data: one a pair of docks (the first of its two rows), your side's and the neutral ones
local function Build()
	local trails = {}
	S.trails = trails
	local data = rawget(_G, "MelloUI_QuestListData")
	local point = ns.Layers and ns.Layers.WorldPoint
	if not (type(data) == "table" and type(data.transports) == "table" and point) then
		return
	end
	local mine = T.DATA_SIDE[Side()]
	local seen = {}
	for _, row in ipairs(data.transports) do
		local kind, f = row[1], row[2]
		if T.KINDS[kind] and (f == 0 or f == mine) then
			local cont, x, y, dcont, dx, dy = row[5], row[6], row[7], row[11], row[12], row[13]
			local key = cont .. ":" .. floor(x) .. ":" .. floor(y) .. ">" .. dcont .. ":" .. floor(dx) .. ":" .. floor(dy)
			local back = dcont .. ":" .. floor(dx) .. ":" .. floor(dy) .. ">" .. cont .. ":" .. floor(x) .. ":" .. floor(y)
			local ax, ay = point(cont, x, y)
			if ax and not seen[key] and not seen[back] then
				seen[key] = true
				local bx, by = point(dcont, dx, dy)
				local list = row[15]
				local n = type(list) == "table" and #list or 0
				local whole = n >= 4 and dcont == cont
					and sqrt((list[n - 1] - dx) ^ 2 + (list[n] - dy) ^ 2) < T.DOCK
				local pts, fade
				if whole and bx then
					-- (the ship's own course, dock to dock)
					pts = Course(point, cont, list)
					if pts then
						pts[1], pts[2], pts[#pts - 1], pts[#pts] = ax, ay, bx, by
						pts = Smooth(pts, T.SMOOTH)
					end
				elseif bx then
					pts = Arc(ax, ay, bx, by, row[16])
				else
					-- (a map the world does not show: the way out of the harbour, fading)
					pts = Course(point, cont, list)
					if pts then
						pts = Smooth(pts, T.SMOOTH)
						fade = true
					end
				end
				if pts then
					local t = { pts = pts, kind = kind, fade = fade, picked = {} }
					Box(t)
					trails[#trails + 1] = t
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The drawing: stretches in the cull box, one width on the screen
--------------------------------------------------------------------------------

local function Paint(l, alpha)
	local P = rawget(MelloUI, "Painter")
	if l.atAlpha ~= alpha and P and P.Paint then
		l.atAlpha = alpha
		P.Paint(l, T.COLOUR, "vertex", alpha)
	end
end

local function NewLine()
	local l = S.holder:CreateLine(nil, "ARTWORK")
	l:SetTexture(T.EDGE)
	if l.SetSnapToPixelGrid then
		l:SetSnapToPixelGrid(false)
		l:SetTexelSnappingBias(0)
	end
	l:SetThickness(T.EDGE_PX / S.k)
	l.atK = S.k
	return l
end

-- one stretch: a pooled Line placed (written only when it changed), its width at the zoom now
local function Stretch(ax, ay, bx, by, alpha)
	if S.used >= T.MAX_LINES then
		return
	end
	S.used = S.used + 1
	local l = S.lines[S.used]
	if not l then
		l = NewLine()
		S.lines[S.used] = l
	end
	if l.atK ~= S.k then
		l.atK = S.k
		l:SetThickness(T.EDGE_PX / S.k)
	end
	if l.ax ~= ax or l.ay ~= ay or l.bx ~= bx or l.by ~= by then
		l.ax, l.ay, l.bx, l.by = ax, ay, bx, by
		l:SetStartPoint("TOPLEFT", S.holder, ax, -ay)
		l:SetEndPoint("TOPLEFT", S.holder, bx, -by)
	end
	Paint(l, alpha)
	if not l.on then
		l.on = true
		l:Show()
	end
end

-- a trail's points taken for its stretches at zoom k (its ends kept): the next one where the way has turned TURN
-- since the last taken (at least SEG_PX on, on the screen) or MAX_PX on at the most -- a stretch never strays half a
-- pixel from the curve, and a gentle arc takes a dozen Lines, not its every point. The indices into its points
local function Pick(t, k)
	local p, picked = t.pts, t.picked
	local n = #p / 2
	local near, far = T.SEG_PX / k, T.MAX_PX / k
	local s2, f2 = near * near, far * far
	local m = 1
	picked[1] = 1
	local lx, ly = p[1], p[2]
	local turn = 0
	local px, py = p[3] - p[1], p[4] - p[2]
	for i = 2, n - 1 do
		local x, y = p[2 * i - 1], p[2 * i]
		local qx, qy = p[2 * i + 1] - x, p[2 * i + 2] - y
		local a = sqrt((px * px + py * py) * (qx * qx + qy * qy))
		if a > 0 then
			turn = turn + abs(px * qy - py * qx) / a
		end
		px, py = qx, qy
		local dx, dy = x - lx, y - ly
		local d2 = dx * dx + dy * dy
		if d2 >= f2 or (d2 >= s2 and turn >= T.TURN) then
			m = m + 1
			picked[m] = i
			lx, ly, turn = x, y, 0
		end
	end
	m = m + 1
	picked[m] = n
	for i = m + 1, #picked do
		picked[i] = nil
	end
	return m
end

local function Lay()
	local c = S.canvas
	local box = c.box
	S.used = 0
	if S.on and S.trails and box and box[1] then
		local k = S.k
		local bx0, by0, bx1, by1 = box[1], box[2], box[3], box[4]
		for _, t in ipairs(S.trails) do
			if t.x1 >= bx0 and t.x0 <= bx1 and t.y1 >= by0 and t.y0 <= by1 then
				local m = Pick(t, k)
				local p, picked = t.pts, t.picked
				for j = 1, m - 1 do
					local i, i2 = picked[j], picked[j + 1]
					local ax, ay, qx, qy = p[2 * i - 1], p[2 * i], p[2 * i2 - 1], p[2 * i2]
					if (ax > qx and ax or qx) >= bx0 and (ax < qx and ax or qx) <= bx1
						and (ay > qy and ay or qy) >= by0 and (ay < qy and ay or qy) <= by1 then
						local alpha = 1
						if t.fade then
							alpha = (1 - (j - 1) / (m - 1)) ^ T.FADE
						end
						Stretch(ax, ay, qx, qy, alpha)
					end
				end
			end
		end
	end
	-- (the rest hidden and unanchored)
	for i = S.used + 1, #S.lines do
		local l = S.lines[i]
		if l.on then
			l.on = false
			l:Hide()
			l:ClearAllPoints()
			l.ax = nil
		end
	end
	S.cuts = c.cuts
end

--------------------------------------------------------------------------------
-- The window's beat
--------------------------------------------------------------------------------

function Trails.Init(canvas)
	S.canvas = canvas
end

-- the holder: on the canvas's root, in world units (it pans and zooms with the maps), over the maps and under the
-- quest areas and the pins; made at the first open
local function Holder()
	local h = S.holder
	if not h then
		local root = S.canvas.root
		h = CreateFrame("Frame", nil, root)
		h:SetAllPoints(root)
		h:SetFrameLevel(root:GetFrameLevel() + ns.Pins.T.LEVEL - T.LEVEL)
		h:EnableMouse(false)
		h:SetShown(S.on)
		S.holder = h
	end
	return h
end

function Trails.View()
	local c = S.canvas
	if not (S.shown and S.holder and c and c.k1 and c.z) then
		return
	end
	local k = c.k1 * c.z
	if k <= 0 or k ~= k or k == math.huge then
		return
	end
	if S.k == nil or k > S.k * T.ZOOM_STEP or k < S.k / T.ZOOM_STEP then
		S.k = k
		Lay()
	elseif S.cuts ~= c.cuts then
		Lay()
	end
end

function Trails.Open()
	if not S.canvas then
		return
	end
	S.shown = true
	Holder()
	if not S.trails then
		Build()
	end
	S.k = nil
	Trails.View()
end

function Trails.Close()
	S.shown = false
end

function Trails.Show(on)
	on = on and true or false
	if S.on == on then
		return
	end
	S.on = on
	if S.holder then
		S.holder:SetShown(on)
		if S.shown then
			S.k = nil
			Trails.View()
		end
	end
end

-- (the tests, the dump) the trails worked out and the Lines laid now
function Trails.Count()
	return S.trails and #S.trails or 0, S.used
end

return Trails

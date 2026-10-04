--------------------------------------------------------------------------------
-- MelloUI - Outline: one outline round elements placed together
--
-- The dynamic backdrops (user, 2026-10-04: "give the users more freedom to
-- snap more random Elements together and form a unified backdrop";
-- docs/plans/dynamic-backdrops.md). Pure geometry, no frames: rects in
-- (screen px: left, bottom, right, top), shapes out.
--
--   MelloUI.Outline.Clusters(rects, reach)
--       the rects in groups: two belong together when the gap between them
--       is at most `reach` (0: touching or overlapping), and so on through
--       the group. A list of lists of indices into `rects`, in the order of
--       each group's first rect.
--   MelloUI.Outline.Shape(rects, tolerance)
--       the union of the rects as outline loops. Edges closer than
--       `tolerance` are lined up first (two bars a few px out of line make
--       one straight side, not a notch). Returns { loops = { loop, ... } };
--       a loop runs with the shape on its LEFT (the outside anticlockwise, a
--       hole clockwise) and is a list of corners { x, y, convex, din, dout }:
--       `convex` true where the shape's corner is 90 degrees (a gem's
--       corner), false where it is 270 (an inner corner, the L joint); `din`
--       and `dout` the directions in and out, "right", "up", "left" or
--       "down". Each straight side runs from one corner to the next; the side
--       a run is on is where the shape is NOT: the run going right is the
--       shape's bottom side (the shape above it), up its right side, left its
--       top, down its left side (Outline.SideOf). The shape also keeps its
--       grid (X, Y: the lined-up edges; inside[i][j]: cell i, j is in it)
--       for Fill.
--   MelloUI.Outline.Fill(shape, inset)
--       the inside of a shape as rects, moved in from the outline by inset's
--       sides ({ left, bottom, right, top }) and never nearer to it than
--       that at an inner corner either: a background that runs on through
--       the joins and stops under the rails.
--
-- Nothing here is per frame: a layout asks once after a change (a bar moved,
-- shown or hidden, Edit Mode closed), with a handful of rects.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local Outline = {}
MelloUI.Outline = Outline

local SIDE = { right = "bottom", up = "right", left = "top", down = "left" }
local STEP = { right = { 1, 0 }, up = { 0, 1 }, left = { -1, 0 }, down = { 0, -1 } }

function Outline.SideOf(dir)
	return SIDE[dir]
end

-- the gap between two rects (0 when they touch or overlap)
function Outline.Gap(a, b)
	local dx = math.max(0, math.max(a[1], b[1]) - math.min(a[3], b[3]))
	local dy = math.max(0, math.max(a[2], b[2]) - math.min(a[4], b[4]))
	return math.max(dx, dy)
end

function Outline.Clusters(rects, reach)
	reach = reach or 0
	local n = #rects
	local parent = {}
	for i = 1, n do
		parent[i] = i
	end
	local function Find(i)
		while parent[i] ~= i do
			parent[i] = parent[parent[i]]
			i = parent[i]
		end
		return i
	end
	for i = 1, n do
		for j = i + 1, n do
			if Outline.Gap(rects[i], rects[j]) <= reach then
				local a, b = Find(i), Find(j)
				if a ~= b then
					parent[math.max(a, b)] = math.min(a, b)
				end
			end
		end
	end
	local groups, order = {}, {}
	for i = 1, n do
		local root = Find(i)
		if not groups[root] then
			groups[root] = {}
			order[#order + 1] = root
		end
		table.insert(groups[root], i)
	end
	local out = {}
	for k, root in ipairs(order) do
		out[k] = groups[root]
	end
	return out
end

-- every value within `tol` of the one before it joins its group, the group
-- taking its middle value
local function Snapper(values, tol)
	table.sort(values)
	local map, group = {}, {}
	local function Close()
		if #group > 0 then
			local mid = (group[1] + group[#group]) / 2
			for _, v in ipairs(group) do
				map[v] = mid
			end
		end
	end
	for i, v in ipairs(values) do
		if i > 1 and v - values[i - 1] > tol then
			Close()
			group = {}
		end
		group[#group + 1] = v
	end
	Close()
	return map
end

local function Unique(map)
	local seen, list = {}, {}
	for _, v in pairs(map) do
		if not seen[v] then
			seen[v] = true
			list[#list + 1] = v
		end
	end
	table.sort(list)
	return list
end

local function Turn(a, b)
	local da, db = STEP[a], STEP[b]
	return da[1] * db[2] - da[2] * db[1]   -- > 0: a left turn
end

function Outline.Shape(rects, tolerance)
	local tol = tolerance or 0
	if #rects == 0 then
		return { loops = {} }
	end
	-- the edges lined up
	local xv, yv = {}, {}
	for _, r in ipairs(rects) do
		xv[#xv + 1], xv[#xv + 2] = r[1], r[3]
		yv[#yv + 1], yv[#yv + 2] = r[2], r[4]
	end
	local xmap, ymap = Snapper(xv, tol), Snapper(yv, tol)
	local snapped = {}
	for i, r in ipairs(rects) do
		snapped[i] = { xmap[r[1]], ymap[r[2]], xmap[r[3]], ymap[r[4]] }
	end
	local X, Y = Unique(xmap), Unique(ymap)
	-- the grid's cells inside the union
	local inside = {}
	for i = 1, #X - 1 do
		inside[i] = {}
		local cx = (X[i] + X[i + 1]) / 2
		for j = 1, #Y - 1 do
			local cy = (Y[j] + Y[j + 1]) / 2
			local on = false
			for _, r in ipairs(snapped) do
				if cx > r[1] and cx < r[3] and cy > r[2] and cy < r[4] then
					on = true
					break
				end
			end
			inside[i][j] = on
		end
	end
	local function In(i, j)
		return inside[i] ~= nil and inside[i][j] == true
	end
	-- the boundary as unit edges, the shape on their left, keyed by start
	local starts = {}
	local edges = {}
	local function Edge(i0, j0, i1, j1, dir)
		local e = { i0 = i0, j0 = j0, i1 = i1, j1 = j1, dir = dir }
		edges[#edges + 1] = e
		local key = i0 * 4096 + j0
		starts[key] = starts[key] or {}
		table.insert(starts[key], e)
	end
	for i = 1, #X - 1 do
		for j = 1, #Y - 1 do
			if In(i, j) then
				if not In(i, j - 1) then Edge(i, j, i + 1, j, "right") end
				if not In(i + 1, j) then Edge(i + 1, j, i + 1, j + 1, "up") end
				if not In(i, j + 1) then Edge(i + 1, j + 1, i, j + 1, "left") end
				if not In(i - 1, j) then Edge(i, j + 1, i, j, "down") end
			end
		end
	end
	-- the loops: from each unused edge round to it again; where two cells
	-- meet at one point only, the left turn keeps the loops apart
	local used, loops = {}, {}
	for _, first in ipairs(edges) do
		if not used[first] then
			local run = {}
			local e = first
			while e and not used[e] do
				used[e] = true
				run[#run + 1] = e
				local nexts = starts[e.i1 * 4096 + e.j1]
				local pick
				for _, cand in ipairs(nexts or {}) do
					if not used[cand] or cand == first then
						if not pick or Turn(e.dir, cand.dir) > Turn(e.dir, pick.dir) then
							pick = cand
						end
					end
				end
				if pick == first then
					break
				end
				e = pick
			end
			-- the corners: where the direction changes
			local corners = {}
			local m = #run
			for k = 1, m do
				local a, b = run[k], run[k % m + 1]
				if a.dir ~= b.dir then
					corners[#corners + 1] = { x = X[a.i1], y = Y[a.j1], convex = Turn(a.dir, b.dir) > 0, din = a.dir, dout = b.dir }
				end
			end
			-- (begun from the first corner, so a loop reads from a corner round)
			loops[#loops + 1] = corners
		end
	end
	return { loops = loops, X = X, Y = Y, inside = inside }
end

-- the sorted, unique values of a list (in place: the list itself)
local function Sorted(list)
	table.sort(list)
	local n = 0
	for i = 1, #list do
		if n == 0 or list[i] ~= list[n] then
			n = n + 1
			list[n] = list[i]
		end
	end
	for i = #list, n + 1, -1 do
		list[i] = nil
	end
	return list
end

-- The inside moved in from the outline by the insets: a point is in when a
-- box round it (il left, ir right, ib down, it up) lies inside the union.
-- At an outer corner that is the two sides' insets; at an inner one it also
-- keeps the background out of the square in the elbow (on the empty side of
-- the rails' lines, which a cell's own insets left in). Its edges lie on the
-- grid's lines moved by the insets: each cell of that finer grid is in or
-- out as a whole, read at its centre. A row's run of cells comes as one
-- rect, rows with the same runs as one.
function Outline.Fill(shape, inset)
	local X, Y, inside = shape.X, shape.Y, shape.inside
	local out = {}
	if not (X and Y and inside and #X >= 2 and #Y >= 2) then
		return out
	end
	local il, ib, ir, it = inset and inset[1] or 0, inset and inset[2] or 0, inset and inset[3] or 0, inset and inset[4] or 0
	-- the union holds the box x0..x1, y0..y1 (every grid cell it overlaps inside)
	local function Holds(x0, y0, x1, y1)
		if x0 < X[1] or x1 > X[#X] or y0 < Y[1] or y1 > Y[#Y] then
			return false
		end
		for i = 1, #X - 1 do
			if X[i] < x1 and X[i + 1] > x0 then
				for j = 1, #Y - 1 do
					if Y[j] < y1 and Y[j + 1] > y0 and not (inside[i] and inside[i][j]) then
						return false
					end
				end
			end
		end
		return true
	end
	local xs, ys = {}, {}
	for _, v in ipairs(X) do
		xs[#xs + 1], xs[#xs + 2], xs[#xs + 3] = v, v + il, v - ir
	end
	for _, v in ipairs(Y) do
		ys[#ys + 1], ys[#ys + 2], ys[#ys + 3] = v, v + ib, v - it
	end
	Sorted(xs)
	Sorted(ys)
	local open = {}   -- [x0 .. ":" .. x1] = the rect still growing up through the rows
	for j = 1, #ys - 1 do
		local cy = (ys[j] + ys[j + 1]) / 2
		local runs, i = {}, 1
		while i <= #xs - 1 do
			local cx = (xs[i] + xs[i + 1]) / 2
			if Holds(cx - il, cy - ib, cx + ir, cy + it) then
				local last = i
				while last + 1 <= #xs - 1 do
					local nx = (xs[last + 1] + xs[last + 2]) / 2
					if not Holds(nx - il, cy - ib, nx + ir, cy + it) then
						break
					end
					last = last + 1
				end
				runs[#runs + 1] = { xs[i], xs[last + 1] }
				i = last + 1
			else
				i = i + 1
			end
		end
		local still = {}
		for _, run in ipairs(runs) do
			local key = run[1] .. ":" .. run[2]
			local r = open[key]
			if r and r[4] == ys[j] then
				r[4] = ys[j + 1]
			else
				r = { run[1], ys[j], run[2], ys[j + 1] }
				out[#out + 1] = r
			end
			still[key] = r
		end
		open = still
	end
	return out
end

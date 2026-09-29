--------------------------------------------------------------------------------
-- MelloUI - Edit Layout: the snapping maths (0.15.0)
--
-- Pure maths for Edit Layout's drags (Core/EditLayoutMovers.lua): no frame,
-- no game call, no table made per call. Everything is in UIParent units
-- (the screen's size in them is W x H); a pixel constant is turned into units
-- with the screen's pixels per unit (Snap.PerUnit: the physical height over
-- UIParent's height). The user's decision of 2026-09-27 (U4): an element
-- snaps to the NEAREST element's edges and centre (and the screen's), and a
-- guide line shows where.
--
--   Snap.SNAP_PX, RELEASE_PX, AXIS_LOCK_PX   10, 16, 6 px: a line is taken
--       within SNAP_PX; once snapped it is held until the raw distance passes
--       RELEASE_PX (no jitter at the edge); Shift decides the axis after
--       AXIS_LOCK_PX of movement
--   Snap.GRID                  50 units from the screen's centre (grid mode)
--   Snap.NUDGE_PX, NUDGE_SHIFT_PX            1, 10 px (the arrow keys)
--   Snap.REPEAT_DELAY, REPEAT_EVERY          0.35 s, 0.04 s (a held arrow)
--   Snap.PerUnit(physicalH, uiH) -> pixels per unit (1 when either is not a
--       plain positive number)
--   Snap.Units(px, perUnit) -> units
--   Snap.Round(v, perUnit) -> v on the physical pixel grid
--   Snap.Features(l, b, w, h) -> x1, x2, x3, y1, y2, y3   left, centre,
--       right; bottom, centre, top
--   Snap.Gap(O, l, b, w, h) -> the edge-to-edge distance (0 when they
--       overlap), and the centre-to-centre one; O has l, b, w, h fields
--   Snap.Nearest(list, n, l, b, w, h) -> the index of the nearest of
--       list[1..n] (each with l, b, w, h), ties to the nearer centre; nil for
--       none
--   Snap.Axis(a1, a2, a3, o1, o2, o3, size, grid, held, thrIn, thrOut)
--       -> d, line, rank   one axis: the shift that puts one of the features
--       a1..a3 on a line. The lines: the element's o1..o3 (nil: none) and the
--       screen's 0, size / 2, size -- or, with `grid`, every size / 2 + k *
--       GRID on the screen and its two edges. A feature takes a line within
--       thrIn; the line it is held on (`held`, nil for none) within thrOut.
--       The smallest |d| wins; a tie goes to the lower rank: element lines
--       before screen lines before grid lines, edges before centres. d = 0
--       and line = nil when nothing is in reach
--   Snap.Lock(dx, dy, thr) -> "x" | "y" | nil   Shift's axis once the move
--       from where the drag began reaches thr on either axis: "x" moves
--       along x (y kept), "y" along y; nil while undecided
--   Snap.Clamp(l, b, w, h, eL, eB, eR, eT, W, H) -> l, b   the element kept
--       on the screen together with what moves with it: its union U reaches
--       eL / eB / eR / eT past its own left / bottom / right / top. Past the
--       right or the bottom it comes in; one wider than the screen keeps its
--       left edge on it, one taller its top (Core's FitOnScreen rule)
-- The rank of a line: 0 an element's edge, 1 its centre, 2 a screen edge,
-- 3 the screen's centre, 4 a grid line.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local Snap = {
	SNAP_PX = 10, RELEASE_PX = 16, AXIS_LOCK_PX = 6,
	GRID = 50,
	NUDGE_PX = 1, NUDGE_SHIFT_PX = 10,
	REPEAT_DELAY = 0.35, REPEAT_EVERY = 0.04,
}
MelloUI.EditLayoutSnap = Snap

local abs, floor, sqrt = math.abs, math.floor, math.sqrt

-- (a line is the held one within this: the lines are the same numbers from
-- frame to frame, the cached rects')
local SAME = 0.001

-- a plain positive number (not NaN), else nil; the maths never meets a
-- secret (the callers read through MelloUI.Safe), this only keeps a bad
-- number out of a sum
local function Positive(v)
	if type(v) ~= "number" or v ~= v or v <= 0 or v == math.huge then
		return nil
	end
	return v
end

function Snap.PerUnit(physicalH, uiH)
	physicalH, uiH = Positive(physicalH), Positive(uiH)
	if not (physicalH and uiH) then
		return 1
	end
	return physicalH / uiH
end

function Snap.Units(px, perUnit)
	return px / (Positive(perUnit) or 1)
end

function Snap.Round(v, perUnit)
	perUnit = Positive(perUnit) or 1
	return floor(v * perUnit + 0.5) / perUnit
end

function Snap.Features(l, b, w, h)
	return l, l + w / 2, l + w, b, b + h / 2, b + h
end

function Snap.Gap(O, l, b, w, h)
	local r, t = l + w, b + h
	local oR, oT = O.l + O.w, O.b + O.h
	local gapX = O.l - r
	if l - oR > gapX then
		gapX = l - oR
	end
	if gapX < 0 then
		gapX = 0
	end
	local gapY = O.b - t
	if b - oT > gapY then
		gapY = b - oT
	end
	if gapY < 0 then
		gapY = 0
	end
	local cx, cy = (O.l + O.w / 2) - (l + w / 2), (O.b + O.h / 2) - (b + h / 2)
	return sqrt(gapX * gapX + gapY * gapY), sqrt(cx * cx + cy * cy)
end

function Snap.Nearest(list, n, l, b, w, h)
	local best, bestDist, bestCentre = nil, nil, nil
	for i = 1, n do
		local dist, centre = Snap.Gap(list[i], l, b, w, h)
		if not best or dist < bestDist or (dist == bestDist and centre < bestCentre) then
			best, bestDist, bestCentre = i, dist, centre
		end
	end
	return best
end

-- One feature against one line: the running best (d, line, rank) or the
-- better of the two
local function Try(f, line, rank, held, thrIn, thrOut, bd, bl, br)
	local d = line - f
	local ad = abs(d)
	local thr = (held and abs(line - held) < SAME) and thrOut or thrIn
	if ad > thr then
		return bd, bl, br
	end
	if not bl or ad < abs(bd) or (ad == abs(bd) and rank < br) then
		return d, line, rank
	end
	return bd, bl, br
end

-- the three features against one line
local function TryAll(a1, a2, a3, line, rank, held, thrIn, thrOut, bd, bl, br)
	bd, bl, br = Try(a1, line, rank, held, thrIn, thrOut, bd, bl, br)
	bd, bl, br = Try(a2, line, rank, held, thrIn, thrOut, bd, bl, br)
	return Try(a3, line, rank, held, thrIn, thrOut, bd, bl, br)
end

-- the grid line nearest a feature, and the held one when it is a grid line
-- (on the screen only)
local function TryGrid(f, size, held, thrIn, thrOut, bd, bl, br)
	local half, grid = size / 2, Snap.GRID
	local line = half + floor((f - half) / grid + 0.5) * grid
	if line >= 0 and line <= size then
		bd, bl, br = Try(f, line, 4, held, thrIn, thrOut, bd, bl, br)
	end
	if held and held ~= line and held >= 0 and held <= size and abs((held - half) / grid - floor((held - half) / grid + 0.5)) < SAME then
		bd, bl, br = Try(f, held, 4, held, thrIn, thrOut, bd, bl, br)
	end
	return bd, bl, br
end

function Snap.Axis(a1, a2, a3, o1, o2, o3, size, grid, held, thrIn, thrOut)
	local bd, bl, br = 0, nil, nil
	if o1 then
		bd, bl, br = TryAll(a1, a2, a3, o1, 0, held, thrIn, thrOut, bd, bl, br)
		bd, bl, br = TryAll(a1, a2, a3, o2, 1, held, thrIn, thrOut, bd, bl, br)
		bd, bl, br = TryAll(a1, a2, a3, o3, 0, held, thrIn, thrOut, bd, bl, br)
	end
	bd, bl, br = TryAll(a1, a2, a3, 0, 2, held, thrIn, thrOut, bd, bl, br)
	bd, bl, br = TryAll(a1, a2, a3, size, 2, held, thrIn, thrOut, bd, bl, br)
	if grid then
		bd, bl, br = TryGrid(a1, size, held, thrIn, thrOut, bd, bl, br)
		bd, bl, br = TryGrid(a2, size, held, thrIn, thrOut, bd, bl, br)
		bd, bl, br = TryGrid(a3, size, held, thrIn, thrOut, bd, bl, br)
	else
		bd, bl, br = TryAll(a1, a2, a3, size / 2, 3, held, thrIn, thrOut, bd, bl, br)
	end
	if not bl then
		return 0, nil, nil
	end
	return bd, bl, br
end

function Snap.Lock(dx, dy, thr)
	local ax, ay = abs(dx), abs(dy)
	if ax < thr and ay < thr then
		return nil
	end
	return ax >= ay and "x" or "y"
end

function Snap.Clamp(l, b, w, h, eL, eB, eR, eT, W, H)
	local ul, ub, ur, ut = l - eL, b - eB, l + w + eR, b + h + eT
	local dx, dy = 0, 0
	if ur + dx > W then
		dx = W - ur
	end
	if ul + dx < 0 then
		dx = -ul
	end
	if ub + dy < 0 then
		dy = -ub
	end
	if ut + dy > H then
		dy = H - ut
	end
	return l + dx, b + dy
end

--------------------------------------------------------------------------------
-- MelloUI - Rims (1.2.0)
--
-- The gold rim round MelloUI's windows (the user, 2026-10-22: "using the border that you are using on the Personal
-- Resource Nameplate, how about we use it on the Map, minimap, QUest Tracker, Chat, Backpack and every other Future
-- custom window"; their pick C of BuildData/output/gilded_windows_sketch/gilded_windows.html: the Personal Display's
-- rim, W.RimArt, at a heavier rail, every inner line the gold hairline (W.Hairline); "keep the column as one if they
-- are snapped next to eachother", the whisper window out of the chat with them). One system for every window: the
-- own-window shell (Kit:OwnWindow, Modules/KitWindow.lua) adds its frame, and the panels that are windows of their own
-- (W.Panel's `rim` option: the Quest Tracker, the minimap column, the chat, the whisper window).
--
--   MelloUI.Rims:Add(frame[, opts]) -> entry   the window `frame` rimmed: a rim of its own on a child frame round it,
--       its rail outward from the frame's edge (its inner casing over the frame's own 1 px edge), drawn over the
--       window's parts. opts (read once): area (a look area, Kit.Areas: no rim while the painted look dresses it),
--       shown (fn(frame) -> false: no rim -- the painted shells). Windows snapped edge to edge -- a side shared, the
--       two others in line, at most the snap gap (Edit Layout's) apart -- wear one rim round them all: the first of
--       them (top, then left) carries it, the gap between them filled as the window (the Personal Display's joint)
--   MelloUI.Rims:Lay()    laid again on the next frame (a window moved, slid out, its look switched)
--   MelloUI.Rims.T        the rail and the room it takes
-- Laid again on a rimmed window's show, hide and size change, Edit Layout's open and close, the bus's 'mover' and its
-- look areas' switches; nothing at login but the windows' own; nothing each frame.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Rims")
local Num = MelloUI.Safe.Number

local Rims = { list = {}, byFrame = setmetatable({}, { __mode = "k" }) }
MelloUI.Rims = Rims

-- the rail (UI units: the Personal Display's 2.7, heavier for a window -- the pick's C), how far it is laid in over
-- the frame's edge (its inner casing on the frame's own line), the rim's place over the window's parts, how near two
-- windows' edges and sides count as snapped (screen px), the snap gap's most
Rims.T = { band = 4.5, tuck = 1, level = 60, align = 2.5, touch = 1.5, gapMost = 10 }
local T = Rims.T

local W   -- (MelloUI.Widgets: Widgets.lua loads before this file; read at the first rim)
local floor, abs, min = math.floor, math.abs, math.min

local function Shown(e)
	local f = e.frame
	if not f:IsShown() then
		return false
	end
	local Kit = MelloUI.Kit
	if e.area and Kit and Kit.IsOn and Kit:IsOn(e.area) then
		return false
	end
	if e.shown then
		local ok, on = pcall(e.shown, f)
		return ok and on ~= false
	end
	return true
end

-- a window's rect on the screen (px): left, bottom, right, top; nil while unreadable
local function Rect(f)
	local s = Num(f:GetEffectiveScale())
	local l, b, w, h = f:GetRect()
	l, b, w, h = Num(l), Num(b), Num(w), Num(h)
	if not (s and l and b and w and h) then
		return nil
	end
	return l * s, b * s, (l + w) * s, (b + h) * s
end

-- (the screen px of Edit Layout's snap gap, and a hair more)
local function GapPx()
	local E = MelloUI.EditLayout
	local gap = E and E.SnapGap and Num(E:SnapGap()) or 0
	local s = Num(UIParent:GetEffectiveScale()) or 1
	return min(gap, T.gapMost) * s + T.touch
end

-- a rim's pieces: a child frame over the window's parts, the rim's art on it, the joint (the gap between snapped
-- windows filled as the window)
local function Make(e)
	W = W or MelloUI.Widgets
	local f = e.frame
	local rim = CreateFrame("Frame", nil, f)
	rim:SetFrameLevel(f:GetFrameLevel() + T.level)
	rim:EnableMouse(false)
	rim.art = rim:CreateTexture(nil, "OVERLAY")
	W.RimArt(rim.art, T.band)
	rim.art:SetAllPoints(rim)
	rim.joint = W.Solid(rim, "BACKGROUND", "mainWindow", 1)
	rim.joint:Hide()
	e.rim = rim
end

-- the rim round `first`'s top left to `last`'s bottom right (the group's), its joint over the gap between `a` and `b`
local function Round(e, first, last)
	local rim, out = e.rim, T.band - T.tuck
	rim:ClearAllPoints()
	rim:SetPoint("TOPLEFT", first, "TOPLEFT", -out, out)
	rim:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", out, -out)
	rim:SetShown(true)
end

-- two windows snapped: `b` under `a` (or right of it), the sides in line, at most the gap apart -> "down" / "right"
local function Snapped(ra, rb, gap)
	local al, ab, ar, at = ra[1], ra[2], ra[3], ra[4]
	local bl, bb, br, bt = rb[1], rb[2], rb[3], rb[4]
	if abs(al - bl) <= T.align and abs(ar - br) <= T.align then
		local d = ab - bt   -- (b under a: a's foot over b's top)
		if d >= -T.touch and d <= gap then
			return "down"
		end
	end
	if abs(at - bt) <= T.align and abs(ab - bb) <= T.align then
		local d = bl - ar   -- (b right of a)
		if d >= -T.touch and d <= gap then
			return "right"
		end
	end
	return nil
end

-- everything laid: each shown window's rect; snapped ones in groups (a chain one way, every pair in line: the group's
-- outline a rectangle); each group's first window carries the rim round them all, the others none
function Rims.Relay()
	Rims.due = false
	local list, gap = Rims.list, GapPx()
	local live = {}
	for _, e in ipairs(list) do
		e.next, e.carried, e.how = nil, false, nil
		if e.rim then
			e.rim:Hide()
			e.rim.joint:Hide()
		end
		if Shown(e) then
			local l, b, r, t = Rect(e.frame)
			if l then
				e.r = e.r or {}
				e.r[1], e.r[2], e.r[3], e.r[4] = l, b, r, t
				live[#live + 1] = e
			end
		end
	end
	-- (the top-left one first: a chain is followed down or right from its head; whole px, a strict order)
	table.sort(live, function(x, y)
		local tx, ty = floor(x.r[4] + 0.5), floor(y.r[4] + 0.5)
		if tx ~= ty then
			return tx > ty
		end
		return floor(x.r[1] + 0.5) < floor(y.r[1] + 0.5)
	end)
	for _, a in ipairs(live) do
		if not a.carried then
			-- this window heads its group: follow the chain one way
			local tail, how = a, nil
			while true do
				local found
				for _, b in ipairs(live) do
					if b ~= tail and not b.carried and b ~= a then
						local way = Snapped(tail.r, b.r, gap)
						if way and (how == nil or way == how) then
							found = b
							how = way
							break
						end
					end
				end
				if not found then
					break
				end
				found.carried = true
				tail.next = found
				tail = found
			end
			if not a.rim then
				Make(a)
			end
			Round(a, a.frame, tail.frame)
			-- the joints: each gap in the chain filled as the window
			local j, cur = 0, a
			while cur.next do
				local nxt = cur.next
				local d = how == "down" and (cur.r[2] - nxt.r[4]) or (nxt.r[1] - cur.r[3])
				if d > 0.5 then
					j = j + 1
					local joint = Rims.Joint(a, j)
					joint:ClearAllPoints()
					if how == "down" then
						joint:SetPoint("TOPLEFT", cur.frame, "BOTTOMLEFT")
						joint:SetPoint("BOTTOMRIGHT", nxt.frame, "TOPRIGHT")
					else
						joint:SetPoint("TOPLEFT", cur.frame, "TOPRIGHT")
						joint:SetPoint("BOTTOMRIGHT", nxt.frame, "BOTTOMLEFT")
					end
					joint:Show()
				end
				cur = nxt
			end
			for k = j + 1, #(a.joints or {}) do
				a.joints[k]:Hide()
			end
		end
	end
end

-- the group's j-th joint (made the first time a gap needs it, kept), on its rim
function Rims.Joint(e, j)
	e.joints = e.joints or { e.rim.joint }
	local joint = e.joints[j]
	if not joint then
		joint = W.Solid(e.rim, "BACKGROUND", "mainWindow", 1)
		e.joints[j] = joint
	end
	return joint
end

-- laid again on the next frame (one pass however often asked)
function Rims:Lay()
	if Rims.due then
		return
	end
	Rims.due = true
	local S = MelloUI.Schedule
	if S and S.NextFrame then
		S:NextFrame(Rims, Rims.Relay)
	else
		Rims.Relay()
	end
end

local function Again()
	Rims:Lay()
end
local OnWindow   -- (Again wrapped once for the watchers' scripts, with the first rim)

local listening = false
local function Listen()
	if listening then
		return
	end
	listening = true
	MelloUI:On("editlayout", Again, "Rims")
	MelloUI:On("mover", Again, "Rims")
	MelloUI:On("scale", Again, "Rims")
	MelloUI:On("column", Again, "Rims")
	local Kit = MelloUI.Kit
	for name in pairs(Kit and Kit.Areas or {}) do
		MelloUI:On("look:" .. name, Again, "Rims")
	end
end

function Rims:Add(frame, opts)
	local e = Rims.byFrame[frame]
	if e then
		return e
	end
	opts = opts or {}
	e = { frame = frame, area = opts.area, shown = opts.shown }
	Rims.byFrame[frame] = e
	Rims.list[#Rims.list + 1] = e
	Listen()
	-- (a watcher of our own over the window, never its scripts: a window that sets its own OnHide after this -- the
	-- whisper window -- dropped the hooks in the game, and the chat lost its rim when the whisper window closed. A
	-- child shows and hides with its window and takes its size: nothing else ever sets its scripts)
	OnWindow = OnWindow or Perf.Shared("a rimmed window's show, hide or size (its rim laid again)", Again, "script")
	local watch = CreateFrame("Frame", nil, frame)
	watch:SetAllPoints(frame)
	watch:EnableMouse(false)
	Perf.SetScript(watch, "OnShow", OnWindow)
	Perf.SetScript(watch, "OnHide", OnWindow)
	Perf.SetScript(watch, "OnSizeChanged", OnWindow)
	e.watch = watch
	Rims:Lay()
	return e
end

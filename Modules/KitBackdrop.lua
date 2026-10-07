--------------------------------------------------------------------------------
-- MelloUI - Kit backdrops: one backdrop round elements placed together
--
-- The drawing of the action bars' backdrops (0.18.5, Modules/ActionBarPanel.lua,
-- user 2026-10-04: "snap more random Elements together and form a unified
-- backdrop"), the kit's since 0.19.8 so every backdrop is drawn by one system
-- (the border library's stage 3: the unit frames' backdrop, UnitFramePanel):
--   Kit:BackdropHolder(root) -> f   a holder on the root (the caller gives it
--       f.shade, a shade element, and keeps it)
--   Kit:DrawBackdrop(f, pads, piece, choice, ks, styleId) -> true | false
--       the outline round `pads` (screen px rects; MelloUI.Outline's shape),
--       the background `choice` (Kit.buttonLooks.backgrounds) through it, its
--       border the gems' frame `piece` (deco/barframe_red / _iron: a gem on
--       each outer corner, the L joint inside) or the border library's style
--       `styleId` (its nine at the heavy weight, its inner corners mitred,
--       Media/Textures/Masks/mitre), at ks screen px per piece px of the gems'
--       frame (an action button 97 piece px). False when the root cannot be
--       read on the screen.
-- Nothing at load: a holder and its pieces are made by the first drawing that
-- needs them, from pools (the same counts again make nothing new).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit
-- what the kit keeps beside the game's frames (Kit.lua: weak-keyed, never keys on them)
local pieceNameOf = MelloUI.Kept.pieceNameOf
local pieceOf = MelloUI.Kept.pieceOf
local Perf = MelloUI.Perf:Scope("KitBackdrop")
local Outline = MelloUI.Outline

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local SafeScreenRect = MelloUI.Safe.ScreenRect

-- A frame's rect in screen px (l, b, r, t), nil while it has no size
local function ScreenRect(f)
	local l, b, r, t = SafeScreenRect(f)
	if l and r > l and t > b then
		return l, b, r, t
	end
	return nil
end

local BACKGROUND_PIECES = Kit.buttonLooks.backgroundPiece
local FRAME_OPEN = { 29, 34, 106, 96 }   -- (the gems' frame's opening when the layout gives none: deco/barframe_red's)
local JOIN_PIECE = "deco/barjoin"        -- an inner corner, its own face turned up and left
local GEM_FRAME = "deco/barframe_red"    -- the gems' frame whose rails every pad is grown by (red and iron: one geometry)

-- A rect (screen px: l, b, r, t) grown into a pad: by the gems' frame's rails
-- at ks screen px per piece px and by `gap` (stone between the element and
-- the rails). Every look's outline is this pad (a look never splits or joins
-- a group); `into`: the table filled (else a new one)
function Kit:BackdropPad(r, ks, gap, into)
	local p = self:Piece(GEM_FRAME)
	local open = p and p.open or FRAME_OPEN
	local w, h = p and p.w or 135, p and p.h or 130
	local pad = into or {}
	pad[1], pad[2] = r[1] - open[1] * ks - gap, r[2] - (h - open[4]) * ks - gap
	pad[3], pad[4] = r[3] + (w - open[3]) * ks + gap, r[4] + open[2] * ks + gap
	return pad
end
-- The part of the backdrop's piece each part of its nine shows (Kit:CutNine,
-- piece px), as the options its partner is made with: that part of the
-- piece's shadow, reaching past the piece's outer sides only. Made once per
-- piece (red and iron gems: one geometry today, each its own all the same).
local FRAME_CORNER = 40      -- piece px: the corner square (the gem and the mitre) of the nine-slice
local partCut = {}   -- [piece name] = { [part key] = { cut = { x0, x1, y0, y1 } } }
local function PartCuts(name, p, c)
	local cuts = partCut[name]
	if not cuts then
		local w, h = p.w, p.h
		cuts = {
			tl = { cut = { 0, c, 0, c } }, tr = { cut = { w - c, w, 0, c } },
			bl = { cut = { 0, c, h - c, h } }, br = { cut = { w - c, w, h - c, h } },
			t = { cut = { c, w - c, 0, c } }, b = { cut = { c, w - c, h - c, h } },
			l = { cut = { 0, c, c, h - c } }, r = { cut = { w - c, w, c, h - c } },
			whole = { cut = { 0, w, 0, h } },
		}
		partCut[name] = cuts
	end
	return cuts
end

-- A piece of a backdrop (a rail or a gem, ShapeOn) shaded: its part of the
-- piece's shadow, at the holder's scale. Added to the holder's shade once,
-- with options read when its partner is made; a piece the pool hands out
-- again takes its new part on its partner (Kit:ShadowCut) or, still
-- waiting for one, in those options.
local SEG_PART = { top = "t", bottom = "b", left = "l", right = "r" }
local function ShadePiece(f, tex, name, part, k, corner)
	tex.kitScale = k or f.k   -- (drawn at k: its shadow reaches as far)
	local p = f.shade and Kit:Piece(name)
	if not p then
		return
	end
	local cut = PartCuts(name, p, corner or FRAME_CORNER)[part].cut
	if tex.kitShadow then
		Kit:ShadowCut(tex, cut[1], cut[2], cut[3], cut[4])
	else
		local o = tex.melloShadeOpts
		if o then
			local oc = o.cut
			oc[1], oc[2], oc[3], oc[4] = cut[1], cut[2], cut[3], cut[4]
		else
			tex.melloShadeOpts = { cut = { cut[1], cut[2], cut[3], cut[4] } }
			f.shade:Add(tex, tex.melloShadeOpts)
		end
	end
end


-- the pools' layers: the background under the rails, the gems and joints
-- over their ends
local POOLS = { stone = { "BACKGROUND", 0 }, rail = { "ARTWORK", 0 }, gem = { "ARTWORK", 1 }, joint = { "ARTWORK", 1 },
	mitre = { "ARTWORK", 0 }, stud = { "ARTWORK", 2 } }   -- (a library look's mitred joints and studs, DrawLibrary)

-- the background tiled at one on-screen size and from the screen's origin
-- (user, 2026-09-23: with the micro menu scaled up in Edit Mode its stone
-- came out stretched next to the bag bar's sharper one), so the pieces of a
-- shape show one surface
local function RetileStones(f)
	local pool = f.pools.stone
	for i = 1, pool.used do
		Kit:Retile(pool[i])
	end
end


-- A backdrop's holder on `root`: hidden, never part of the root's layout,
-- in the BACKGROUND strata and kept there, its pools empty. The caller gives
-- it its shade (f.shade: a shade element its rails' and gems' shadows join,
-- ShadePiece) and keeps it.
function Kit:BackdropHolder(root)
	local f = CreateFrame("Frame", nil, root)
	-- not part of the bar's size: an action bar is a layout frame that grows
	-- round its shown children, so a backdrop (a child reaching past the
	-- buttons) made it grow, which grew the backdrop ... until a relog (user,
	-- 2026-09-23, Edit Mode's Icon Size 100% -> 110%)
	f.ignoreInLayout = true
	f:EnableMouse(false)
	f:SetFrameStrata("BACKGROUND")
	-- and KEPT there: the game raises the action bars to TOOLTIP while a
	-- spell is dragged from the spell book (above the window), and a child
	-- follows its parent's strata -- the backdrop rose with its bar, one
	-- level over the buttons, and its background covered their icons, their
	-- own backgrounds and the stance bar (user, 2026-09-23, /abdump icons:
	-- the buttons TOOLTIP L3, the backdrops TOOLTIP L3 / L4)
	if f.SetFixedFrameStrata then
		f:SetFixedFrameStrata(true)
	end
	f.root = root
	f.pools = {}
	for kind in pairs(POOLS) do
		f.pools[kind] = { used = 0 }
	end
	Perf.SetScript(f, "OnSizeChanged", RetileStones)
	f:Hide()
	return f
end

-- the next texture of a pool (made the first time), showing `piece`
local function Take(f, kind, piece)
	local pool = f.pools[kind]
	local i = pool.used + 1
	pool.used = i
	local tex = pool[i]
	if not tex then
		local layer = POOLS[kind]
		tex = f:CreateTexture(nil, layer[1], nil, layer[2])
		pool[i] = tex
	end
	if piece and pieceNameOf[tex] ~= piece then
		Kit:Apply(tex, piece)
	end
	tex:ClearAllPoints()
	tex:Show()
	return tex
end

-- a texture over the screen rect x0, y0 - x1, y1 (in f's units from its corner)
local function Lay(f, tex, x0, y0, x1, y1)
	local s = f.s
	tex:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", (x0 - f.ox) / s, (y0 - f.oy) / s)
	tex:SetSize((x1 - x0) / s, (y1 - y0) / s)
end

-- Backdrop Background on a piece of the background: a tile, or the dark
-- fill (the palette's inner panel by its key, as the buttons' Dark
-- background, Kit:SetButtonBackground: a new palette paints it again)
local function PaintStone(tex, choice)
	local bg = BACKGROUND_PIECES[choice]
	if bg then
		if pieceNameOf[tex] ~= bg then
			Kit:Unpaint(tex)   -- (the dark fill's palette colour no longer on it)
			tex.kitScale = Kit.scale
			Kit:Apply(tex, bg)
		end
		tex:SetVertexColor(1, 1, 1)
		tex.darkFill = nil
	elseif pieceNameOf[tex] ~= nil or not tex.darkFill then
		Kit:Paint(tex, "innerPanel", "fill", 0.88)
		pieceOf[tex], pieceNameOf[tex], tex.darkFill = true, nil, true   -- still ours (a plain mark): never faded with the game's art
	end
	if not tex.melloRegistered then
		tex.melloRegistered = true
		if Kit.RegisterTexture then
			Kit:RegisterTexture(tex)
		end
	end
end

-- a convex corner's gem by the turn (the shape on the loop's left), and
-- where its square lies from the corner (in corner squares)
local GEM = { right = { up = "br" }, up = { left = "tr" }, left = { down = "tl" }, down = { right = "bl" } }
-- each rail's painted band in the nine (piece px from the piece's outer
-- edge): its outer line here (the margin outside it is clear), its inner line
-- the piece's opening (the top and bottom rails heavier)
local RAIL_OUTER = { top = 6, bottom = 5, left = 7, right = 7 }
local function RailInner(p, side)
	local open = p.open or FRAME_OPEN
	if side == "top" then
		return open[2]
	elseif side == "bottom" then
		return p.h - open[4]
	elseif side == "left" then
		return open[1]
	end
	return p.w - open[3]
end
local GEM_AT = { tl = { 0, -1 }, tr = { -1, -1 }, bl = { 0, 0 }, br = { -1, 0 } }
local STEP = { right = { 1, 0 }, up = { 0, 1 }, left = { -1, 0 }, down = { 0, -1 } }
local STONE_INSET = { 0, 0, 0, 0 }   -- (left, bottom, right, top: filled per shape)

-- The outline a holder drew last, kept with its pads and its tolerance (the
-- rail scale's): the same pads again (a setting, a show, a size that moved
-- nothing) reuse it and its background's cut, so such a relayout makes no
-- new shape (Outline.Shape builds its grid afresh: some KB a call)
local function KeptShape(f, pads, tol)
	local key = f.shapeKey
	if not (key and key[1] == tol and #key == 1 + 4 * #pads) then
		return nil
	end
	local k = 1
	for _, r in ipairs(pads) do
		for c = 1, 4 do
			k = k + 1
			if key[k] ~= r[c] then
				return nil
			end
		end
	end
	return f.shape
end

local function KeepShape(f, pads, tol, shape)
	local key = f.shapeKey or {}
	key[1] = tol
	local k = 1
	for _, r in ipairs(pads) do
		for c = 1, 4 do
			k = k + 1
			key[k] = r[c]
		end
	end
	for i = #key, k + 1, -1 do
		key[i] = nil
	end
	f.shapeKey, f.shape, f.fill = key, shape, nil
end

-- Today's look: the gems' frame (deco/barframe_*) along the loops, a gem on
-- each outer corner, the L joint in each inner one
local function DrawGems(f, shape, piece, p, tc, jp, C, ks)
	local ju0, ju1, jv0, jv1 = jp.uv[1], jp.uv[2], jp.uv[3], jp.uv[4]
	for _, loop in ipairs(shape.loops) do
		local m = #loop
		-- the rails: each side from corner to corner, short of a gem's square
		-- at an outer corner; at an inner one on past it by the other rail's
		-- clear margin, up to that rail's outer line (as the joins of before:
		-- the two rails' lines meet, the joint where their bands cross)
		for i = 1, m do
			local a, b = loop[i], loop[i % m + 1]
			local side = Outline.SideOf(a.dout)
			local ta = a.convex and C or -RAIL_OUTER[Outline.SideOf(a.din)] * ks
			local tb = b.convex and C or -RAIL_OUTER[Outline.SideOf(b.dout)] * ks
			local x0, y0, x1, y1
			if side == "top" or side == "bottom" then
				if a.x < b.x then
					x0, x1 = a.x + ta, b.x - tb
				else
					x0, x1 = b.x + tb, a.x - ta
				end
				if side == "top" then
					y0, y1 = a.y - C, a.y
				else
					y0, y1 = a.y, a.y + C
				end
			else
				if a.y < b.y then
					y0, y1 = a.y + ta, b.y - tb
				else
					y0, y1 = b.y + tb, a.y - ta
				end
				if side == "right" then
					x0, x1 = a.x - C, a.x
				else
					x0, x1 = a.x, a.x + C
				end
			end
			if x1 > x0 and y1 > y0 then
				local tex = Take(f, "rail", piece)
				local t = tc[side]
				tex:SetTexCoord(t[1], t[2], t[3], t[4])
				Lay(f, tex, x0, y0, x1, y1)
				ShadePiece(f, tex, piece, SEG_PART[side])
			end
		end
		-- the corners: a gem on each outer one, the L joint in each inner one,
		-- over the square where the two rails' bands cross (turned to face the
		-- empty side: mirrored when it lies right of the corner, flipped when
		-- below)
		for i = 1, m do
			local c = loop[i]
			if c.convex then
				local which = GEM[c.din] and GEM[c.din][c.dout]
				if which then
					local at, t = GEM_AT[which], tc[which]
					local tex = Take(f, "gem", piece)
					tex:SetTexCoord(t[1], t[2], t[3], t[4])
					local x, y = c.x + at[1] * C, c.y + at[2] * C
					Lay(f, tex, x, y, x + C, y + C)
					ShadePiece(f, tex, piece, which)
				end
			else
				local ex = STEP[c.dout][1] - STEP[c.din][1]
				local ey = STEP[c.dout][2] - STEP[c.din][2]
				-- the rail along the corner's row (top or bottom) and the one
				-- along its column (left or right), each band from the corner
				local across = (c.din == "left" or c.din == "right") and c.din or c.dout
				local hs = Outline.SideOf(across)
				local vs = Outline.SideOf(across == c.din and c.dout or c.din)
				local ho, hi = RAIL_OUTER[hs] * ks, RailInner(p, hs) * ks
				local vo, vi = RAIL_OUTER[vs] * ks, RailInner(p, vs) * ks
				local y0, y1, x0, x1
				if hs == "top" then
					y0, y1 = c.y - hi, c.y - ho
				else
					y0, y1 = c.y + ho, c.y + hi
				end
				if vs == "left" then
					x0, x1 = c.x + vo, c.x + vi
				else
					x0, x1 = c.x - vi, c.x - vo
				end
				local tex = Take(f, "joint", JOIN_PIECE)
				local u0, u1, v0, v1 = ju0, ju1, jv0, jv1
				if ex > 0 then
					u0, u1 = u1, u0
				end
				if ey < 0 then
					v0, v1 = v1, v0
				end
				tex:SetTexCoord(u0, u1, v0, v1)
				Lay(f, tex, x0, y0, x1, y1)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- (0.19.8, the border library's stage 3; the user, 2026-10-06: "go with
-- recommended" of MelloUI-BuildData/output/bar_group_border_sketch) A
-- backdrop in a border library style (Modules/KitBorders.lua): its nine at
-- the heavy weight (the style's own range kept: Hairline with corner nubs
-- at medium), its studs on every corner, outer and inner, and each inner
-- corner MITRED: the two rails' slices over the joint's square, each cut to
-- its half on the diagonal by one mask (Media/Textures/Masks/mitre,
-- Tools/make_mitre_mask.py) turned by its texture coordinates. A weight's UI
-- units are an action button's (45 at Edit Mode's 100%): the rails follow
-- the bars' size, as the gems' frame does. The outline and its pads are the
-- gems' frame's whatever the look, so a look never splits or joins a group.
--------------------------------------------------------------------------------

local BUTTON_UNITS = 45   -- an action button's side in UI units at Edit Mode's 100%
local MITRE_MASK = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Masks\\mitre"
-- the mask turned to each half of the square (the file's own: top left), and
-- the half its twin covers
local MITRE_UV = { TL = { 0, 1, 0, 1 }, TR = { 1, 0, 0, 1 }, BL = { 0, 1, 1, 0 }, BR = { 1, 0, 1, 0 } }
local MITRE_TWIN = { TL = "BR", TR = "BL", BL = "TR", BR = "TL" }
-- a rail family's pieces (the Single rail: window/single_t ...) by part
local FAMILY_PART = { top = "_t", bottom = "_b", left = "_l", right = "_r", tl = "_tl", tr = "_tr", bl = "_bl", br = "_br" }
-- from an outer corner into the shape (y up), the way its stud is turned
local STUD_SIGN = { tl = { 1, -1 }, tr = { -1, -1 }, bl = { 1, 1 }, br = { -1, 1 } }
local NO_OFF = { 0, 0 }
local libLooks = {}   -- [style id] = its look: pieces and coordinates once, its sizes at each layout

-- the middle of a rail's coordinates t, as long as the corner (c of the
-- rail's len piece px): the joint's square at the rails' own density
local function Slice(t, len, c, along)
	local a, b = 1, 2
	if along == "v" then
		a, b = 3, 4
	end
	local out = { t[1], t[2], t[3], t[4] }
	local mid, half = (t[a] + t[b]) / 2, (t[b] - t[a]) * c / (2 * len)
	out[a], out[b] = mid - half, mid + half
	return out
end

-- The look of library style `id` at the gems' frame's rail scale ks (screen
-- px per piece px), nil without the library or its pieces
local function LibraryLook(id, ks)
	local st = Kit.BorderStyles and Kit.BorderStyles[id]
	if not st or id == "backdrop" or not Kit.BorderWeightOf then
		return nil
	end
	local look = libLooks[id]
	if not look then
		look = { st = st, part = {}, uv = {}, slice = {}, inset = {} }
		if st.master then
			local p, tc = Kit:Piece(st.master), Kit:NineCoords(st.master, st.corner)
			if not (p and tc) then
				return nil
			end
			for part in pairs(FAMILY_PART) do
				look.part[part], look.uv[part] = st.master, tc[part]
			end
			local c, o = st.corner, p.open or { st.rail, st.rail, p.w - st.rail, p.h - st.rail }
			look.corner, look.master = c, true
			look.slice.top, look.slice.bottom = Slice(tc.top, p.w - 2 * c, c, "u"), Slice(tc.bottom, p.w - 2 * c, c, "u")
			look.slice.left, look.slice.right = Slice(tc.left, p.h - 2 * c, c, "v"), Slice(tc.right, p.h - 2 * c, c, "v")
			-- each rail's painted band (piece px from the outer edge): the opening
			look.band = { o[1], p.h - o[4], p.w - o[3], o[2] }
		else
			for part, suffix in pairs(FAMILY_PART) do
				local q = Kit:Piece(st.prefix .. suffix)
				if not q then
					return nil
				end
				look.part[part], look.uv[part] = st.prefix .. suffix, q.uv
			end
			local c = Kit:Piece(st.prefix .. "_tl").w
			look.corner = c
			for _, side in ipairs({ "top", "bottom" }) do
				look.slice[side] = Slice(look.uv[side], Kit:Piece(look.part[side]).w, c, "u")
			end
			for _, side in ipairs({ "left", "right" }) do
				look.slice[side] = Slice(look.uv[side], Kit:Piece(look.part[side]).h, c, "v")
			end
			look.band = { c, c, c, c }
		end
		look.stud = st.stud and Kit:Piece(st.stud) and st.stud or nil
		libLooks[id] = look
	end
	-- its sizes at this layout: the weight's band and gem in screen px
	local wt = Kit.BorderWeights[Kit:BorderWeightOf(id, "heavy")]
	if not wt then
		return nil
	end
	local unit = ks * 97 / BUTTON_UNITS
	local k = wt.band * unit / st.rail
	look.k, look.C, look.gem = k, look.corner * k, wt.gem * unit
	local band = look.band
	-- the background just under the rails' inner edges (left, bottom, right, top)
	for i = 1, 4 do
		look.inset[i] = math.max(0, band[i] - 3) * k
	end
	-- the rails' crossing from an outer corner (a stud's centre before its share)
	look.halfX, look.halfY = band[1] * k / 2, band[4] * k / 2
	return look
end

-- a rail's slice over a joint's square, cut to its half (MITRE_UV) by the mask
local function Mitre(f, look, side, half, x0, y0, x1, y1)
	local tex = Take(f, "mitre", look.part[side])
	local t = look.slice[side]
	tex:SetTexCoord(t[1], t[2], t[3], t[4])
	Lay(f, tex, x0, y0, x1, y1)
	local mask = tex.melloMitre
	if not mask then
		mask = f:CreateMaskTexture()
		mask:SetTexture(MITRE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(tex)
		tex:AddMaskTexture(mask)
		tex.melloMitre = mask
	end
	local m = MITRE_UV[half]
	mask:SetTexCoord(m[1], m[2], m[3], m[4])
end

-- a stud at the weight's size, centred off the rails' crossing at corner
-- (x, y) by its share (sx, sy: into the shape), turned to face out (each cut
-- at its top left: mirrored for the others, as the library's)
local function Stud(f, look, x, y, sx, sy)
	local p = Kit:Piece(look.stud)
	local tex = Take(f, "stud", look.stud)
	local u0, u1, v0, v1 = p.uv[1], p.uv[2], p.uv[3], p.uv[4]
	if sx < 0 then
		u0, u1 = u1, u0
	end
	if sy > 0 then
		v0, v1 = v1, v0
	end
	tex:SetTexCoord(u0, u1, v0, v1)
	local m = math.max(p.w, p.h)
	local w, h = look.gem * p.w / m, look.gem * p.h / m
	local off = look.st.studOff or NO_OFF
	local cx, cy = x + sx * (look.halfX + off[1] * look.gem), y + sy * (look.halfY + off[2] * look.gem)
	Lay(f, tex, cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
	ShadePiece(f, tex, look.stud, "whole", look.gem / m / f.s)
end

-- One backdrop's rails and corners in a library look
local function DrawLibrary(f, shape, look)
	local C, kh = look.C, look.k / f.s   -- (kh: holder units per piece px, the shadows' scale)
	for _, loop in ipairs(shape.loops) do
		local m = #loop
		-- the rails: each side from corner to corner, short of an outer
		-- corner's square; at an inner one up to the corner itself (the
		-- joint's square lies past it, on the shape's side)
		for i = 1, m do
			local a, b = loop[i], loop[i % m + 1]
			local side = Outline.SideOf(a.dout)
			local ta, tb = a.convex and C or 0, b.convex and C or 0
			local x0, y0, x1, y1
			if side == "top" or side == "bottom" then
				if a.x < b.x then
					x0, x1 = a.x + ta, b.x - tb
				else
					x0, x1 = b.x + tb, a.x - ta
				end
				if side == "top" then
					y0, y1 = a.y - C, a.y
				else
					y0, y1 = a.y, a.y + C
				end
			else
				if a.y < b.y then
					y0, y1 = a.y + ta, b.y - tb
				else
					y0, y1 = b.y + tb, a.y - ta
				end
				if side == "right" then
					x0, x1 = a.x - C, a.x
				else
					x0, x1 = a.x, a.x + C
				end
			end
			if x1 > x0 and y1 > y0 then
				local name, t = look.part[side], look.uv[side]
				local tex = Take(f, "rail", name)
				tex:SetTexCoord(t[1], t[2], t[3], t[4])
				Lay(f, tex, x0, y0, x1, y1)
				ShadePiece(f, tex, name, look.master and SEG_PART[side] or "whole", kh, look.corner)
			end
		end
		-- the corners: the nine's own on each outer one, the mitre in each
		-- inner one (the rail along its column on the half next to that
		-- rail, the one along its row on the other), a stud on both
		for i = 1, m do
			local c = loop[i]
			if c.convex then
				local which = GEM[c.din] and GEM[c.din][c.dout]
				if which then
					local at, name, t = GEM_AT[which], look.part[which], look.uv[which]
					local tex = Take(f, "gem", name)
					tex:SetTexCoord(t[1], t[2], t[3], t[4])
					local x, y = c.x + at[1] * C, c.y + at[2] * C
					Lay(f, tex, x, y, x + C, y + C)
					ShadePiece(f, tex, name, look.master and which or "whole", kh, look.corner)
					if look.stud then
						local sg = STUD_SIGN[which]
						Stud(f, look, c.x, c.y, sg[1], sg[2])
					end
				end
			else
				local across = (c.din == "left" or c.din == "right") and c.din or c.dout
				local hs = Outline.SideOf(across)
				local vs = Outline.SideOf(across == c.din and c.dout or c.din)
				local x0 = vs == "left" and c.x or c.x - C
				local y0 = hs == "top" and c.y - C or c.y
				local half = (hs == "top" and "T" or "B") .. (vs == "right" and "L" or "R")
				Mitre(f, look, vs, half, x0, y0, x0 + C, y0 + C)
				Mitre(f, look, hs, MITRE_TWIN[half], x0, y0, x0 + C, y0 + C)
				if look.stud then
					-- (turned to face the empty side: out of the shape)
					Stud(f, look, c.x, c.y, -(STEP[c.dout][1] - STEP[c.din][1]), -(STEP[c.dout][2] - STEP[c.din][2]))
				end
			end
		end
	end
end

-- One backdrop on holder f: the outline round `pads` (screen px), with the
-- rails and gems of `piece` or the library style `styleId`, the background
-- `choice`, at ks screen px per piece px. False when its leader cannot be
-- read on the screen.
function Kit:DrawBackdrop(f, pads, piece, choice, ks, styleId)
	local baseL, baseB = ScreenRect(f.root)
	local s = MelloUI.Safe.Finite(MelloUI.Safe.Call(f.root, "GetEffectiveScale"))
	local p, tc = Kit:Piece(piece), Kit:NineCoords(piece, FRAME_CORNER)
	local jp = Kit:Piece(JOIN_PIECE)
	local look = styleId and LibraryLook(styleId, ks) or nil
	if not (baseL and s and s > 0 and p and tc and jp) then
		return false
	end
	local C = FRAME_CORNER * ks
	-- (edges closer than half a rail lined up: no notch of a few px)
	local shape = KeptShape(f, pads, C / 2)
	if not shape then
		shape = Outline.Shape(pads, C / 2)
		KeepShape(f, pads, C / 2, shape)
	end
	local X, Y = shape.X, shape.Y
	if not (X and #X >= 2 and #Y >= 2) then
		return false
	end
	f.s, f.k, f.ox, f.oy = s, ks / s, X[1], Y[1]
	f:ClearAllPoints()
	f:SetPoint("BOTTOMLEFT", f.root, "BOTTOMLEFT", (X[1] - baseL) / s, (Y[1] - baseB) / s)
	f:SetSize((X[#X] - X[1]) / s, (Y[#Y] - Y[1]) / s)
	f:SetFrameLevel(3)
	f:Show()
	for _, pool in pairs(f.pools) do
		pool.used = 0
	end
	-- the background, just under the rails' inner edges
	if BACKGROUND_PIECES[choice] or choice == "dark" then
		if look then
			STONE_INSET[1], STONE_INSET[2], STONE_INSET[3], STONE_INSET[4] = look.inset[1], look.inset[2], look.inset[3], look.inset[4]
		else
			local open = p.open or FRAME_OPEN
			STONE_INSET[1], STONE_INSET[2] = (open[1] - 3) * ks, (p.h - open[4] - 3) * ks
			STONE_INSET[3], STONE_INSET[4] = (p.w - open[3] - 3) * ks, (open[2] - 3) * ks
		end
		-- (its cut kept with the shape and the insets: a look of other rails
		-- cuts it again)
		local fi = f.fillInset
		if not (f.fill and fi and fi[1] == STONE_INSET[1] and fi[2] == STONE_INSET[2] and fi[3] == STONE_INSET[3]
			and fi[4] == STONE_INSET[4]) then
			f.fill = Outline.Fill(shape, STONE_INSET)
			fi = fi or {}
			fi[1], fi[2], fi[3], fi[4] = STONE_INSET[1], STONE_INSET[2], STONE_INSET[3], STONE_INSET[4]
			f.fillInset = fi
		end
		for _, r in ipairs(f.fill) do
			local tex = Take(f, "stone")
			PaintStone(tex, choice)
			Lay(f, tex, r[1], r[2], r[3], r[4])
			tex.kitAlign = "screen"
			Kit:Retile(tex)
		end
	end
	if look then
		DrawLibrary(f, shape, look)
	else
		DrawGems(f, shape, piece, p, tc, jp, C, ks)
	end
	-- the pools' textures this shape did not need put away
	for _, pool in pairs(f.pools) do
		for i = pool.used + 1, #pool do
			pool[i]:Hide()
		end
	end
	return true
end

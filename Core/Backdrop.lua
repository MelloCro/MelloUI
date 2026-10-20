--------------------------------------------------------------------------------
-- MelloUI - Backdrop: one backdrop round elements placed together (the core)
--
-- (onelook stage D4, docs/plans/onelook-cd-plans/D4.md) Every backdrop is
-- drawn on one kind of holder through one registry of drawers: the action
-- bars' (Modules/ActionBars.lua, whatever the look) and the unit frames'
-- (UnitFramePanel, through the kit's Kit:BackdropHolder / Kit:DrawBackdrop).
-- This file is the core half -- the holder, its texture pools, the kept
-- shape, the placing, the registry -- and MelloUI's own drawer; the painted
-- kit registers its gems and border-library drawer, "gems"
-- (MelloUI_Oldschool/Modules/KitBackdrop.lua, Oldschool's).
--   MelloUI.Backdrop.ScreenRect(f) -> l, b, r, t | nil
--       a frame's rect in screen px (MelloUI.Safe.ScreenRect: secret-safe),
--       nil while it has no size: the backdrops' one reader
--   MelloUI.Backdrop.Holder(root) -> f
--       a holder on root: hidden, never part of the root's layout, in the
--       BACKGROUND strata and kept there, no pools yet (a drawer makes its
--       own: Pool). f.root, f.pools; f.drawnBy: the drawer that drew it last
--   Pool(f, kind, layer, sub) -> pool    a pool of textures on that layer
--       ({ used = n, [i] = texture }), made the first time
--   Next(f, kind) -> tex, made           the pool's next texture (made the
--       first time; its points and shown state the drawer's to set)
--   Lay(f, tex, x0, y0, x1, y1)          a texture over that screen rect
--   KeptShape(f, pads, tol) / KeepShape(f, pads, tol, shape)
--       the outline a holder drew last, kept with its pads and tolerance
--   Origin(f) -> s, baseL, baseB | nil   the root's scale and corner
--   Place(f, X, Y, s, baseL, baseB)      the holder over the shape's grid
--   Begin(f) / Finish(f)                 every pool's count to 0 / every
--       texture a drawing did not take hidden (any drawer's)
--   Claim(f, drawer)                     f drawn by `drawer` from now on:
--       the one before puts its own parts away (its Clear)
--   Register(id, drawer) / Drawer(id) -> drawer
--       drawer = { Pad(rect, unit, gap, into) -> pad, Draw(f, pads, unit,
--       look) -> true | false, Resized(f)?, Clear(f)?, reach? }; unit: an
--       action button's side in screen px (Action Bar 1's), the measure
--       every pad and line follows; gap: the space round a member; look:
--       the dressing's (Oldschool's picks), nil without one. Drawer() of an
--       unknown id: MelloUI's own
-- MelloUI's own drawer, "shade" (the user's pick B of the backdrops sketch,
-- docs/plans/onelook-b-sketches/backdrops.md): a soft dark shade on the
-- snapped outline, no edge line -- MelloUI.Shade:Outline (Core/Shade.lua),
-- innerPanel at 0.72, its edges 14 units soft. Its pads are the gems'
-- frame's (the rails' share of a button, fixed here: {29, 34, 29, 34} / 97,
-- plus the gap), so no group joins or splits when the look changes; it
-- draws that joined shape moved in by the rails' share (Outline.Fill), an
-- even 0.12 of a button round the buttons, the bars standing apart in one
-- group bridged.
-- Nothing at load but the registry's data: a holder and its textures are
-- made by the first drawing that needs them.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
-- this file's load time (/melloperf load); it sets no script, hook or timer
-- at load (a holder's one size handler comes with the first holder)
local Perf = MelloUI.Perf:Scope("Backdrop")

local B = {}
MelloUI.Backdrop = B

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua)
local SafeScreenRect = MelloUI.Safe.ScreenRect

-- A frame's rect in screen px (l, b, r, t), nil while it has no size: the
-- addon's one reader with the size the backdrops need. Four numbers, no
-- table.
function B.ScreenRect(f)
	local l, b, r, t = SafeScreenRect(f)
	if l and r > l and t > b then
		return l, b, r, t
	end
	return nil
end
local ScreenRect = B.ScreenRect

-- a holder's size changed: the drawer that drew it told (the gems retile
-- their stone from the screen's origin). One handler for every holder.
local function Resized(f)
	local d = f.drawnBy
	if d and d.Resized then
		d.Resized(f)
	end
end

function B.Holder(root)
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
	Perf.SetScript(f, "OnSizeChanged", Resized)
	f:Hide()
	return f
end

function B.Pool(f, kind, layer, sub)
	local pool = f.pools[kind]
	if not pool then
		pool = { used = 0, layer = layer or "ARTWORK", sub = sub or 0 }
		f.pools[kind] = pool
	end
	return pool
end

function B.Next(f, kind)
	local pool = f.pools[kind]
	local i = pool.used + 1
	pool.used = i
	local tex = pool[i]
	if tex then
		return tex, false
	end
	tex = f:CreateTexture(nil, pool.layer, nil, pool.sub)
	pool[i] = tex
	return tex, true
end

-- a texture over the screen rect x0, y0 - x1, y1 (in f's units from its corner)
function B.Lay(f, tex, x0, y0, x1, y1)
	local s = f.s
	tex:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", (x0 - f.ox) / s, (y0 - f.oy) / s)
	tex:SetSize((x1 - x0) / s, (y1 - y0) / s)
end

-- The outline a holder drew last, kept with its pads and its tolerance: the
-- same pads again (a setting, a show, a size that moved nothing) reuse it
-- and what a drawer cut from it, so such a relayout makes no new shape
-- (Outline.Shape builds its grid afresh: some KB a call)
function B.KeptShape(f, pads, tol)
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

function B.KeepShape(f, pads, tol, shape)
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

-- the root's effective scale and its bottom-left corner on the screen; nil
-- when it cannot be read there
function B.Origin(f)
	local baseL, baseB = ScreenRect(f.root)
	local s = MelloUI.Safe.Finite(MelloUI.Safe.Call(f.root, "GetEffectiveScale"))
	if not (baseL and s and s > 0) then
		return nil
	end
	return s, baseL, baseB
end

-- the holder over the shape's grid (X, Y: its lined-up edges), shown, at
-- level 3 of its fixed strata; f.s, f.ox, f.oy for Lay
function B.Place(f, X, Y, s, baseL, baseB)
	f.s, f.ox, f.oy = s, X[1], Y[1]
	f:ClearAllPoints()
	f:SetPoint("BOTTOMLEFT", f.root, "BOTTOMLEFT", (X[1] - baseL) / s, (Y[1] - baseB) / s)
	f:SetSize((X[#X] - X[1]) / s, (Y[#Y] - Y[1]) / s)
	f:SetFrameLevel(3)
	f:Show()
end

function B.Begin(f)
	for _, pool in pairs(f.pools) do
		pool.used = 0
	end
end

-- the pools' textures this drawing did not take put away (their shadow
-- partners follow them: the kit's)
function B.Finish(f)
	for _, pool in pairs(f.pools) do
		for i = pool.used + 1, #pool do
			pool[i]:Hide()
		end
	end
end

function B.Claim(f, drawer)
	local was = f.drawnBy
	if was ~= drawer then
		if was and was.Clear then
			was.Clear(f)
		end
		f.drawnBy = drawer
	end
end

--------------------------------------------------------------------------------
-- The registry
--------------------------------------------------------------------------------

local drawers = {}
B.MODERN = "shade"

function B.Register(id, drawer)
	if type(id) == "string" and type(drawer) == "table" then
		drawers[id] = drawer
	end
end

function B.Drawer(id)
	return (id ~= nil and drawers[id]) or drawers[B.MODERN]
end

--------------------------------------------------------------------------------
-- MelloUI's own drawer: the soft shade on the snapped outline
--------------------------------------------------------------------------------

do
	-- the gems' frame's rails as shares of an action button (deco/barframe_red's
	-- opening, Media/KitLayout.lua: 29 and 34 piece px of its 97 a button;
	-- left, bottom, right, top): every look's pad, so the groups never change
	-- with the look
	local JOIN = { 29 / 97, 34 / 97, 29 / 97, 34 / 97 }
	local INSET = { 0, 0, 0, 0 }   -- (the joined shape moved in by the rails: filled per drawing, no table made)
	-- edges closer than this share of a button lined up (about 3 UI units at
	-- Edit Mode's 100%): two bars a few px out of line make one side, no notch
	local TOLERANCE = 1 / 15
	-- the look (Shade:Outline's options): innerPanel at 0.72, 14 units soft
	local LOOK = { colour = "innerPanel", alpha = 0.72, feather = 14, layer = "BACKGROUND", sublevel = 0 }

	local SHADE = { reach = 0 }

	function SHADE.Pad(r, unit, gap, into)
		local pad = into or {}
		pad[1], pad[2] = r[1] - JOIN[1] * unit - gap, r[2] - JOIN[2] * unit - gap
		pad[3], pad[4] = r[3] + JOIN[3] * unit + gap, r[4] + JOIN[4] * unit + gap
		return pad
	end

	-- another drawer took the holder over: the shade put away
	function SHADE.Clear(f)
		if f.shadeOutline then
			f.shadeOutline:SetShown(false)
		end
	end

	function SHADE.Draw(f, pads, unit)
		local s, baseL, baseB = B.Origin(f)
		if not (s and type(unit) == "number" and unit > 0) then
			return false
		end
		local Outline = MelloUI.Outline
		local tol = unit * TOLERANCE
		local shape = B.KeptShape(f, pads, tol)
		if not shape then
			shape = Outline.Shape(pads, tol)
			B.KeepShape(f, pads, tol, shape)
		end
		local X, Y = shape.X, shape.Y
		if not (X and #X >= 2 and #Y >= 2) then
			return false
		end
		B.Claim(f, SHADE)
		B.Place(f, X, Y, s, baseL, baseB)
		-- (no pool of the holder's is this drawer's: a look's pieces left from
		-- before, put away)
		B.Begin(f)
		B.Finish(f)
		-- the drawn part: the joined shape moved in by the rails' share, and
		-- its outline (cut again only for a new shape)
		if not (f.shadeOf == shape and f.shadeUnit == unit) then
			INSET[1], INSET[2], INSET[3], INSET[4] = JOIN[1] * unit, JOIN[2] * unit, JOIN[3] * unit, JOIN[4] * unit
			local fill = Outline.Fill(shape, INSET)
			f.shadeFill, f.shadeShape, f.shadeOf, f.shadeUnit = fill, Outline.Shape(fill, 0), shape, unit
		end
		local o = f.shadeOutline
		if not o then
			o = MelloUI.Shade:Outline(f, LOOK)
			f.shadeOutline = o
		end
		o:SetShown(true)
		o:SetShape(f.shadeShape, f.shadeFill, s, f.ox, f.oy)
		return true
	end

	B.Register("shade", SHADE)
end

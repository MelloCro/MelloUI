--------------------------------------------------------------------------------
-- MelloUI - Kit sets: Oldschool's three frame sets (2.1.58)
--
-- The user, 2026-11-17: "im not satisfied with these elements currently: Unitframe, Personal Resource, Nameplates,
-- Chat Oldschool. We need to redesign those, and make sure that the new ones are all generated as 1 texture, which are
-- scalable horizontally and Vertically", then, to round 1's three directions: "Why not just Make all 3, so that we
-- have 3 Variations", "take into consideration the detalis and dont cut them off" (docs/plans/oldschool-redesign.md).
-- Their ChatGPT paintings (BuildData's masters/oldschool_redesign) are made into Media/Sets/<Set>/*.tga and
-- Media/FrameSets.lua by Tools/make_oldschool_sets.py; this file lays them (the machinery of 2.1.0's reverted ornate
-- sets, its bars now one texture each). One system for every piece of a set:
--   Frame Set           UI Modifications' border kind "frameset" (UIModifications.frameSet): Gilded Stone, Forged
--                       Iron or Carved Wood, live (Kit:ApplyBorder -> the bus's 'border' "frameset"). It stands for the
--                       unit frames' bars' border, their portrait ring, the cast bar's border, the Personal Display's,
--                       the nameplates' and the chat's frame: one painting each now.
--   Sets.Data(id)       a set's numbers (the one chosen when id is nil) and its id
--   Sets.File(set, n)   a set's file
--   Sets.Unit(e)        a unit frame's picture (one texture: the set's painting of its shape on the game picture's
--                       place), registered and laid while the skin dresses the frame (Sets.UnitShown):
--                         e = { frame, region (the game's picture, faded: ours is laid from its top left and follows
--                         its show and hide), shape ("player" | "target" | "small"), own (a frame of MelloUI's own:
--                         its bars, masks and texts are ours to lay), flip (fn: mirrored -- a flipped party member),
--                         bars = { { bar, mask, "health" | "power" }, ... }, texts = { fontstring, ... } }
--                       Over the bars and under the texts: the picture on a holder at the frame's lowest level that
--                       holds a text or a bar (the bars of MelloUI's own frames lowered to it and laid on the
--                       painting's holes, their texts lifted to OVERLAY), in OVERLAY -8 (over every fill and the heals
--                       coming in, under every text and icon); each fill cut to its hole by its own mask (a plain one:
--                       never a fourth); a dark ground under each hole (Sets.Ground: e.paintGround, the caller's Bar
--                       Background); the name's rect on the plaque (e.plaque); a crest over the ring's top (e.crest:
--                       the marks); the ring's outer edge (e.ring: the combo points); the soft shade under it all
--   Sets.Strip(parent)  ONE texture round a fill (the cast bars, the Personal Display's bars and shield column, the
--                       nameplates' health bar): strip:Lay(set, kind, fill, depth, length[, vertical]) -- the piece cut
--                       by the client, its ends whole at the fill's depth, its plain middle stretched; strip:Reach() ->
--                       above, below, left, right past the fill; strip:Icon() -> the cast bar's icon socket,
--                       strip:Badge() -> the nameplate's level socket, from the fill's top left; strip:Hide()
--   Sets.Window(parent) ONE texture round a window (the chat): window:Lay(set, rect, rail) -- its four ends whole, its
--                       sides stretched, its middle empty for the window's own background
-- Nothing at load but the option: a picture, a strip and their textures are made by the first dressing that wants
-- them.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Kit = MelloUI.Kit
local Perf = MelloUI.Perf:Scope("KitSets")
local hooksecurefunc = Perf.hooksecurefunc
local Secret = MelloUI.Safe.IsSecret
local Num = MelloUI.Safe.Number
local DATA = ns.FrameSetsData or { order = {} }

local Sets = {
	DIR = "Interface\\AddOns\\MelloUI_Oldschool\\Media\\Sets\\",
	WHITE = "Interface\\Buttons\\WHITE8X8",
	units = {},                                        -- every unit picture registered, in order
	byRegion = setmetatable({}, { __mode = "k" }),     -- [the game's picture] = its entry
	byFrame = setmetatable({}, { __mode = "k" }),      -- [the unit frame] = its entry (2.1.58: the glows, the effects)
	levels = setmetatable({}, { __mode = "k" }),       -- [a level circle's orb rep] = its badge (2.1.58)
	rects = setmetatable({}, { __mode = "k" }),        -- [a raid cell] = its glow (2.1.58)
	extra = setmetatable({}, { __mode = "k" }),        -- [the game's picture] = rows wanted under its power hole (2.1.61)
	PICTURE = { "OVERLAY", -8 },                       -- the picture's layer: over the fills, under the texts
	GROUND = { "BACKGROUND", -8 },                     -- a hole's ground: under the fills
	GROUND_PAD = 1,                                    -- (units) a ground past its hole, under the painted rim
	CUT_ROW = 0.25,                                    -- (units) the row of a painting drawn deeper for more bars (2.1.61)
	CUT_UNDER = 1,                                     -- (units) the holes' cut this far under the power hole's top
	CUT_RAIL = 1.5,                                    -- (units) the right rail starts this far right of the holes
	CREST = 0.95,                                      -- the crest's side, a share of the ring's opening radius
}
Kit.Sets = Sets

--------------------------------------------------------------------------------
-- The choice
--------------------------------------------------------------------------------
Sets.LOOKS = {}
for _, id in ipairs(DATA.order) do
	local d = DATA[id]
	Sets.LOOKS[#Sets.LOOKS + 1] = { value = id, label = d.label, set = id }
end
Kit:AddBorderKind({ kind = "frameset", key = "frameSet", default = DATA.order[1] or "stone", name = "Frame Set",
	values = Sets.LOOKS, preview = "set",
	desc = "The painted frames of the unit frames, cast bars, Personal Display, nameplates and chat." },
	"bar")

function Sets.Data(id)
	id = id or (Kit.BorderValue and Kit:BorderValue("frameset"))
	local set = DATA[id]
	if not set then
		id = DATA.order[1]
		set = id and DATA[id]
	end
	return set, id
end

function Sets.File(set, name)
	return Sets.DIR .. set.dir .. "\\" .. name
end

-- a size read back (ours: plain; a game region's: guarded), nil when secret or none
local function SizeOf(r)
	local ok, w, h = pcall(r.GetSize, r)
	w, h = ok and Num(w), ok and Num(h)
	if w and h and w > 0 and h > 0 then
		return w, h
	end
	return nil
end

local function LevelOf(f)
	local ok, l = pcall(f.GetFrameLevel, f)
	return ok and Num(l) or nil
end

local function Shown(r)
	local ok, on = pcall(r.IsShown, r)
	return ok and not Secret(on) and on == true
end

--------------------------------------------------------------------------------
-- A unit frame's picture
--------------------------------------------------------------------------------

-- its parts, made the first time it is laid (a holder at the frame's lowest text-or-bar level, the picture, a ground
-- per hole, the plaque's rect, the crest, the ring's outer edge; the shade under everything). On the game picture's
-- own frame (the container a game frame kept away is unseen by: MelloUI.Units), so ours goes and comes with it
local function Make(e)
	local okP, parent = pcall(e.region.GetParent, e.region)
	parent = okP and type(parent) == "table" and parent.CreateTexture and parent or e.frame
	local h = CreateFrame("Frame", nil, parent)
	h:EnableMouse(false)
	h.ignoreInLayout = true
	h:SetAllPoints(parent)
	e.holder = h
	e.art = h:CreateTexture(nil, Sets.PICTURE[1], nil, Sets.PICTURE[2])
	e.grounds = {}
	for i = 1, #e.bars do
		e.grounds[i] = h:CreateTexture(nil, Sets.GROUND[1], nil, Sets.GROUND[2])
	end
	e.plaque:SetParent(h)
	e.ring:SetParent(h)
	e.crest = h:CreateTexture(nil, "OVERLAY", nil, -7)
	e.crest:Hide()
	-- (2.1.58) the outer glow under it all (target, mouseover: Sets.GlowState), and the ring's own part of the picture
	-- once more on the ring's square -- what the frame effects read as the ring (its place, and a copy of it over their
	-- light: Unit Frames' RingOf)
	e.glow = h:CreateTexture(nil, "BACKGROUND", nil, -7)
	e.glow:Hide()
	e.ringArt = h:CreateTexture(nil, Sets.PICTURE[1], nil, Sets.PICTURE[2])
	e.ringArt.melloSetRing = true
	e.shade = parent:CreateTexture(nil, "BACKGROUND", nil, -8)
	e.shade:SetVertexColor(0, 0, 0)
	if Kit.RegisterTexture then
		Kit:RegisterTexture(e.art)   -- (Dark Mode's unit frames brightness, as the game's picture it stands for)
	end
	e.held = { levels = {}, layers = {}, masks = {}, points = {} }
	e.parts = {}   -- (2.1.61: a picture's three more textures while it is laid in parts, LayPicture)
	-- the game's picture shown or hidden (a vehicle's art in its place): ours with it
	if not e.watched then
		e.watched = true
		local function Follow()
			if e.holder then
				local on = e.on and Shown(e.region)
				e.holder:SetShown(on)
				e.shade:SetShown(on and e.shadeOn or false)
			end
		end
		for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
			hooksecurefunc(e.region, method, Follow)
		end
	end
end

-- a text lifted over the picture (MelloUI's own frames: OVERLAY, its sublevel kept at least 0), its layer kept
local function Lift(e, fs)
	if type(fs) ~= "table" or not fs.GetDrawLayer or e.held.layers[fs] then
		return
	end
	local ok, layer, sub = pcall(fs.GetDrawLayer, fs)
	if not ok or Secret(layer) or type(layer) ~= "string" then
		return
	end
	sub = Num(sub) or 0
	if layer ~= "OVERLAY" and layer ~= "HIGHLIGHT" then
		e.held.layers[fs] = { layer, sub }
		fs:SetDrawLayer("OVERLAY", math.max(0, sub))
	end
end

-- a bar's own texts added to `list` (its regions walked without a table)
local function BarTexts(list, ...)
	for i = 1, select("#", ...) do
		local r = select(i, ...)
		if r.GetObjectType and r:GetObjectType() == "FontString" then
			list[#list + 1] = r
		end
	end
end

-- every text of the frame's bars and the ones named, each with the frame it draws on
local function Texts(e)
	local list = {}
	local named = e.texts
	for i = 1, named and table.maxn(named) or 0 do   -- (a part the frame lacks: a hole in the list)
		local fs = named[i]
		if type(fs) == "table" and fs.GetDrawLayer then
			list[#list + 1] = fs
		end
	end
	for _, b in ipairs(e.bars) do
		local bar = b[1]
		if type(bar) == "table" and bar.GetRegions then
			BarTexts(list, bar:GetRegions())
		end
	end
	return list
end

-- the level the picture is drawn at: the lowest of its bars' and its texts' frames (a text drawn on a frame under the
-- bars -- the target of target's name -- stays over the picture only at its own level)
local function Level(e, texts)
	local v
	for _, b in ipairs(e.bars) do
		local l = type(b[1]) == "table" and LevelOf(b[1])
		if l and (not v or l < v) then
			v = l
		end
	end
	for _, fs in ipairs(texts) do
		local okP, owner = pcall(fs.GetParent, fs)
		local l = okP and type(owner) == "table" and LevelOf(owner)
		if l and (not v or l < v) then
			v = l
		end
	end
	return v or LevelOf(e.frame) or 0
end

-- a mask laid on a rect of the picture (plain white, clamped: soft by a pixel at its edges); its own atlas, size and
-- anchors kept the first time, to give back
local function Cut(e, mask, put, rect)
	if type(mask) ~= "table" or not mask.SetTexture then
		return
	end
	if not e.held.masks[mask] then
		local okA, atlas = pcall(mask.GetAtlas, mask)
		local points = {}
		local okN, n = pcall(mask.GetNumPoints, mask)
		for i = 1, (okN and Num(n)) or 0 do
			points[i] = { mask:GetPoint(i) }
		end
		local w, h = SizeOf(mask)
		e.held.masks[mask] = { atlas = okA and not Secret(atlas) and type(atlas) == "string" and atlas ~= "" and atlas or nil,
			w = w, h = h, points = points }
	end
	mask:SetTexture(Sets.WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	put(mask, rect[1], rect[2], rect[3] - rect[1], rect[4] - rect[2])
end

-- everything of the frame's own given back (its bars' levels, its texts' layers, its masks)
local function GiveBack(e)
	local held = e.held
	if not held then
		return
	end
	for bar, l in pairs(held.levels) do
		bar:SetFrameLevel(l)
	end
	for bar, at in pairs(held.points) do
		bar:ClearAllPoints()
		for _, p in ipairs(at.points) do
			bar:SetPoint(p[1], p[2], p[3], p[4], p[5])
		end
		if at.w and at.h then
			bar:SetSize(at.w, at.h)
		end
	end
	for fs, at in pairs(held.layers) do
		fs:SetDrawLayer(at[1], at[2])
	end
	for mask, at in pairs(held.masks) do
		if at.atlas then
			mask:SetAtlas(at.atlas, true)
		end
		if at.w and at.h then
			mask:SetSize(at.w, at.h)
		end
		mask:ClearAllPoints()
		for _, p in ipairs(at.points) do
			mask:SetPoint(p[1], p[2], p[3], p[4], p[5])
		end
	end
	held.levels, held.layers, held.masks, held.points = {}, {}, {}, {}
	if e.bracket then
		for _, b in ipairs(e.bars) do
			if b[1] then
				MelloUI.Kept.bracketOf[b[1]] = nil
				e.bracket(b[1])
			end
		end
	end
end

-- a hole's dark ground: the owner's look (`paint`: a unit frame's Bar Background), else the palette's inner panel
function Sets.Ground(tex, paint)
	if paint then
		paint(tex)
	elseif not tex.melloSetGround then
		tex.melloSetGround = true
		tex:SetTexture(Sets.WHITE)
		Kit:Paint(tex, "innerPanel", "vertex")
		tex:SetAlpha(0.92)
	end
end

-- the UI Shade's unit frames area, at its strength
local function ShadeAlpha()
	if Kit.ShadeOn and Kit:ShadeOn("unitframes") then
		return Kit:ShadeStrength()
	end
	return nil
end

-- (2.1.61; the user, 2026-11-20, with a picture of the player frame -- a druid's form row hung under the painting,
-- the painting's corner ornament left in the middle: "can you make a dynamic unitframe depending on how many bars are
-- being tracked, like you did with the Personal Nameplate") A frame's bars are as many as its unit shows: a row more
-- under the power hole (Sets.Rows; MelloUI's own player frame asks for a druid's form row) is ONE border round all of
-- them. The painting is one picture with two holes, so it is laid in parts. Only a PLAIN row of it is ever drawn
-- deeper, so no ornament loses its shape (the user, on Carved Wood, of a first cut through the power hole's middle
-- row, where that set's and Gilded Stone's corner leaf climbs the right rail: "the edge texture is being spread
-- instead and lost its artstyle ... it got stretched"). Three columns, two cuts:
--   left of the ring's edge: as it is, all the way down (the ring's foot, the level's socket);
--   the holes' columns: cut just under the power hole's top rim -- that row is the open hole between its two plain
--     side rims -- drawn a row deep, everything under it a row lower (the hole's foot, the plate's foot and whatever
--     of the corner ornament lies over them, whole);
--   the right rail: cut beside the health hole's middle, where every set's rail is plain -- that row drawn a row
--     deep, everything under it a row lower (the corner ornament whole, from its tip).
-- Both lower parts move by the same row, so an ornament that lies over both columns stays in one piece. In the longer
-- hole the painting's own rail between its two holes is drawn once more, between the power bar and the new row. The
-- picture's glow is laid the same way. A row is the power hole's pitch: its rail and its depth.
--------------------------------------------------------------------------------

-- the cuts for a frame's rows now, in the picture's units -- { xc, xr, yr, yh, pitch, row }: the ring's edge and the
-- right rail's start, the right rail's cut and the holes' -- or nil (none wanted, a mirrored frame, a painting
-- without the two holes)
local function CutOf(e, u, flip)
	local extra = Sets.extra[e.region]
	if not extra or flip or not (u.power and u.health and u.ring) then
		return nil
	end
	local yh = u.power[2] + Sets.CUT_UNDER
	local yr = (u.health[2] + u.health[4]) / 2
	local outer = u.ring[4] or u.ring[3] * 1.25
	local dy = yh - u.ring[2]
	local xc = u.ring[1] + math.sqrt(math.max(0, outer * outer - dy * dy))
	return { xc = math.min(xc, u.power[1] - 1), xr = math.max(u.health[3], u.power[3]) + Sets.CUT_RAIL, yr = yr, yh = yh,
		pitch = u.power[4] - u.health[4], row = Sets.CUT_ROW }
end

-- a picture of the painting's shape on e[key] (`r`: its rect in the picture's units, its share u, v of its file), whole
-- or in the cuts' seven parts (its six more textures made the first time, beside the first: its frame, its layer)
local function LayPicture(e, key, file, r, flip, Put, cut)
	local main = e[key]
	local parts = e.parts[key]
	main:SetTexture(file)
	if not cut then
		if flip then
			main:SetTexCoord(r.u, 0, 0, r.v)
		else
			main:SetTexCoord(0, r.u, 0, r.v)
		end
		Put(main, r.x, r.y, r.w, r.h)
		for i = 1, parts and #parts or 0 do
			parts[i].used = false
			parts[i]:Hide()
		end
		return
	end
	if not parts then
		parts = {}
		local okL, layer, sub = pcall(main.GetDrawLayer, main)
		for i = 1, 6 do
			parts[i] = main:GetParent():CreateTexture(nil, okL and layer or "ARTWORK", nil, okL and Num(sub) or 0)
			if key == "art" and Kit.RegisterTexture then
				Kit:RegisterTexture(parts[i])   -- (Dark Mode's unit frames brightness, as the first part)
			end
		end
		e.parts[key] = parts
	end
	local x1, y1 = r.x + r.w, r.y + r.h
	local function Part(t, xa, xb, ya, yb, toY, depth)
		t:SetTexture(file)
		t:SetTexCoord((xa - r.x) / r.w * r.u, (xb - r.x) / r.w * r.u, (ya - r.y) / r.h * r.v, (yb - r.y) / r.h * r.v)
		Put(t, xa, toY, xb - xa, depth)
	end
	local xc, xr, yr, yh, pitch = cut.xc, math.min(cut.xr, x1), cut.yr, cut.yh, cut.pitch
	-- over the higher cut: all of it
	Part(main, r.x, x1, r.y, yr, r.y, yr - r.y)
	-- left of the ring's edge: as it is
	Part(parts[1], r.x, xc, yr, y1, yr, y1 - yr)
	-- the holes' columns: as they are down to their cut, its row a row deep, the rest a row lower
	Part(parts[2], xc, xr, yr, yh, yr, yh - yr)
	Part(parts[3], xc, xr, yh, yh + cut.row, yh, pitch)
	Part(parts[4], xc, xr, yh, y1, yh + pitch, y1 - yh)
	-- the right rail: its cut's row a row deep, the rest a row lower
	Part(parts[5], xr, x1, yr, yr + cut.row, yr, pitch)
	Part(parts[6], xr, x1, yr, y1, yr + pitch, y1 - yr)
	for i = 1, 6 do
		parts[i].used = true
		parts[i]:SetShown(key ~= "glow" or main:IsShown())
	end
end

-- rows wanted under a frame's power hole (0 / nil: none; one is what the paintings' rails allow), by the game's
-- picture the frame's painting stands on -- asked before or after the painting is laid
function Sets.Rows(region, n)
	n = (type(n) == "number" and n >= 1) and 1 or nil
	if type(region) ~= "table" or Sets.extra[region] == n then
		return
	end
	Sets.extra[region] = n
	local e = Sets.byRegion[region]
	if e and e.on then
		Sets.LayUnit(e)
	end
end

function Sets.LayUnit(e)
	if InCombatLockdown() then
		Kit:WhenOutOfCombat(function()
			Sets.LayUnit(e)
		end, e)
		return
	end
	local set = e.on and Sets.Data()
	local u = set and set.unit[e.shape]
	if not u then
		if e.holder then
			e.holder:Hide()
			e.shade:Hide()
			e.crest:Hide()
		end
		if e.own then
			GiveBack(e)
		end
		e.laid = nil
		return
	end
	if not e.holder then
		Make(e)
	end
	-- (from the game picture's middle -- an art swap of another size keeps it: the minus mob's -- at its scale: the
	-- painting's numbers are for a picture u.rw x u.rh, a party member's pet's is half that)
	local rw = SizeOf(e.region)
	local k = rw and rw / u.rw or 1
	local flip = e.flip and e.flip() or false
	local W, cx0, cy0 = u.rw, u.rw / 2, u.rh / 2
	local function At(tex, point, x, y)
		tex:SetPoint(point, e.region, "CENTER", (x - cx0) * k, -(y - cy0) * k)
	end
	local function Put(tex, x, y, w, h)
		if flip then
			x = W - x - w
		end
		tex:ClearAllPoints()
		At(tex, "TOPLEFT", x, y)
		tex:SetSize(math.max(w * k, 0.01), math.max(h * k, 0.01))
	end
	e.put = Put   -- (2.1.58: the rank laid by the picture's own placer, Sets.Rank)
	-- (2.1.61: whole, or in parts with a row more under the power hole -- CutOf, LayPicture)
	local cut = CutOf(e, u, flip)
	e.cut = cut
	LayPicture(e, "art", Sets.File(set, e.shape), u, flip, Put, cut)
	local pad = Sets.GROUND_PAD
	for i, b in ipairs(e.bars) do
		local hole, ground = u[b[3]], e.grounds[i]
		if hole and ground then
			-- (the power hole's ground under the longer hole: the new row's too)
			local more = (cut and b[3] == "power") and cut.pitch or 0
			Put(ground, hole[1] - pad, hole[2] - pad, hole[3] - hole[1] + 2 * pad, hole[4] - hole[2] + 2 * pad + more)
			Sets.Ground(ground, e.paintGround)
		end
	end
	-- (the painting's own rail between its two holes once more, under the power hole: between it and the new row)
	if cut then
		local hp, pw = u.health, u.power
		local file = Sets.File(set, e.shape)
		if not e.sep then
			e.sep = e.holder:CreateTexture(nil, Sets.PICTURE[1], nil, Sets.PICTURE[2])
			if Kit.RegisterTexture then
				Kit:RegisterTexture(e.sep)
			end
		end
		e.sep:SetTexture(file)
		e.sep:SetTexCoord((pw[1] - u.x) / u.w * u.u, (pw[3] - u.x) / u.w * u.u, (hp[4] - u.y) / u.h * u.v,
			(pw[2] - u.y) / u.h * u.v)
		Put(e.sep, pw[1], pw[4], pw[3] - pw[1], pw[2] - hp[4])
		e.sep:Show()
	elseif e.sep then
		e.sep:Hide()
	end
	if u.plaque then
		local p = u.plaque
		Put(e.plaque, p[1], p[2], p[3] - p[1], p[4] - p[2])
	end
	local cx, cy, r = u.ring[1], u.ring[2], u.ring[3]
	local outer = u.ring[4] or r * 1.25
	Put(e.ring, cx - outer, cy - outer, 2 * outer, 2 * outer)
	local side = r * Sets.CREST * 2
	Put(e.crest, cx - side / 2, cy - outer - side * 0.25, side, side)
	-- (2.1.58) the glow, as the shade; the ring's copy on its square (its share of the picture)
	local g = u.glow
	if g then
		LayPicture(e, "glow", Sets.File(set, e.shape .. "_glow"), g, flip, Put, cut)
	end
	do
		local x0, y0 = (cx - outer - u.x) / u.w, (cy - outer - u.y) / u.h
		local x1, y1 = (cx + outer - u.x) / u.w, (cy + outer - u.y) / u.h
		x0, y0, x1, y1 = math.max(0, x0), math.max(0, y0), math.min(1, x1), math.min(1, y1)
		e.ringArt:SetTexture(Sets.File(set, e.shape))
		if flip then
			e.ringArt:SetTexCoord(u.u * (1 - x0), u.u * (1 - x1), u.v * y0, u.v * y1)
		else
			e.ringArt:SetTexCoord(u.u * x0, u.u * x1, u.v * y0, u.v * y1)
		end
		Put(e.ringArt, u.x + x0 * u.w, u.y + y0 * u.h, (x1 - x0) * u.w, (y1 - y0) * u.h)
	end
	local s = u.shade
	e.shade:SetTexture(Sets.File(set, e.shape .. "_shade"))
	e.shade:SetTexCoord(0, s.u, 0, s.v)
	Put(e.shade, s.x, s.y, s.w, s.h)
	local alpha = ShadeAlpha()
	e.shadeOn = alpha ~= nil
	e.shade:SetAlpha(alpha or 0)
	-- MelloUI's own frame: its bars at the picture's level, their fills cut to the holes, its texts over it
	local texts = Texts(e)
	local level = Level(e, texts)
	e.holder:SetFrameLevel(level)
	if e.own then
		for _, b in ipairs(e.bars) do
			local bar = b[1]
			local l = type(bar) == "table" and LevelOf(bar)
			if l and l ~= level then
				if e.held.levels[bar] == nil then
					e.held.levels[bar] = l
				end
				bar:SetFrameLevel(level)
			end
			local hole = u[b[3]]
			-- (2.1.58) the bar laid on its painted hole, so its fill reaches the hole's ends: a painting's holes miss
			-- the game's bars by a few units (ChatGPT keeps the guide only so closely); its own place kept to give back
			if hole and type(bar) == "table" and bar.GetObjectType and bar:GetObjectType() == "StatusBar" then
				if not e.held.points[bar] then
					local points = {}
					local okN, n = pcall(bar.GetNumPoints, bar)
					for i = 1, (okN and Num(n)) or 0 do
						points[i] = { bar:GetPoint(i) }
					end
					local bw, bh = SizeOf(bar)
					e.held.points[bar] = { points = points, w = bw, h = bh }
				end
				bar:ClearAllPoints()
				At(bar, "TOPLEFT", flip and (W - hole[3]) or hole[1], hole[2])
				bar:SetSize(math.max((hole[3] - hole[1]) * k, 0.01), math.max((hole[4] - hole[2]) * k, 0.01))
			end
			if hole and b[2] then
				local rect = { flip and (W - hole[3]) or hole[1], hole[2], flip and (W - hole[1]) or hole[3], hole[4] }
				Cut(e, b[2], function(tex, x, y, w, hh)
					tex:ClearAllPoints()
					At(tex, "TOPLEFT", x, y)
					tex:SetSize(math.max(w * k, 0.01), math.max(hh * k, 0.01))
				end, rect)
			end
			if bar and e.bracket then
				-- (Bar Textures' own shape mask off: the hole is the fill's edge)
				MelloUI.Kept.bracketOf[bar] = true
				e.bracket(bar)
			end
		end
		for _, fs in ipairs(texts) do
			Lift(e, fs)
		end
	end
	e.laid = set
	Sets.Rank(e, e.rankKind)
	Sets.Watch()
	e.isTarget = Sets.IsTarget(e)
	Sets.GlowState(e)
	local on = Shown(e.region)
	e.holder:SetShown(on)
	e.shade:SetShown(on and e.shadeOn)
end

--------------------------------------------------------------------------------
-- (2.1.58) The outer glow (the user, 2026-11-17: "the old targeting red borders highlight needs to be removed and a
-- new one added, i want outer glow on the nameplates of the targeted mob matching the shape of each nameplate type
-- ... same thing with the mouseover and target heighlight on the unitframes, group frames, pet, focus, target, target
-- of target"): each painting's own outline glowing (Tools/make_oldschool_sets.py: outside it only), in the palette's
-- selected trim while its unit is your target, its hover colour while the mouse is over it -- the target first. The
-- target frame itself shows your target always: it glows on the mouse only
--------------------------------------------------------------------------------
-- (the user in game: "the outer glow is barely noticable and the mouseover glow on the nameplates": drawn additively --
-- it lights the ground round the frame, on sand as in a cave -- the target in the selected trim's gold, the mouse in
-- the palette's light text colour, so the two read apart)
Sets.GLOW = { target = { "selectedTrim", 1 }, hover = { "text", 0.85 } }

local function PaintGlow(tex, state)
	local g = Sets.GLOW[state]
	tex:SetBlendMode("ADD")
	Kit:Paint(tex, g[1], "vertex")
	tex:SetAlpha(g[2])
end
Sets.PaintGlow = PaintGlow

-- a unit frame's unit (its own field, else its secure attribute), or nil
local function UnitOfFrame(f)
	local u = rawget(f, "unit")
	if type(u) ~= "string" and f.GetAttribute then
		local ok, a = pcall(f.GetAttribute, f, "unit")
		u = ok and a or nil
	end
	return (type(u) == "string" and not Secret(u)) and u or nil
end

-- is this frame's unit your target (a plain answer only: a secret one counts as no)
function Sets.IsTarget(e)
	local unit = e and e.frame and UnitOfFrame(e.frame)
	if not unit or unit == "target" then
		return false
	end
	local ok, same = pcall(UnitIsUnit, unit, "target")
	return ok and not Secret(same) and same == true
end

function Sets.GlowState(e)
	local glow = e and e.glow
	if not glow then
		return
	end
	local state = e.laid and ((e.isTarget and "target") or (e.isHover and "hover")) or nil
	if state then
		PaintGlow(glow, state)
		glow:Show()
	else
		glow:Hide()
	end
	-- (2.1.61: the glow of a painting laid in parts -- its other parts with it)
	local parts = e.parts and e.parts.glow
	for i = 1, parts and #parts or 0 do
		local p = parts[i]
		if state and p.used then
			PaintGlow(p, state)
			p:Show()
		else
			p:Hide()
		end
	end
end

Sets.OnEnter = Perf.Shared("the mouse over a frame in a frame set: its glow", function(f)
	local e = Sets.byFrame[f]
	if e then
		e.isHover = true
		Sets.GlowState(e)
	end
end, "script")

Sets.OnLeave = Perf.Shared("the mouse off a frame in a frame set: its glow away", function(f)
	local e = Sets.byFrame[f]
	if e and e.isHover then
		e.isHover = false
		Sets.GlowState(e)
	end
end, "script")

-- every laid frame's target glow again (your target changed, the group, your pet, your target's target)
function Sets.TargetAll()
	for _, e in ipairs(Sets.units) do
		if e.laid then
			e.isTarget = Sets.IsTarget(e)
			Sets.GlowState(e)
		end
	end
end

local TargetEvents = Perf.Shared("a target or group change: the frame sets' target glows", function(_, event, unit)
	if event ~= "UNIT_TARGET" or unit == "target" or unit == "focus" then
		Sets.TargetAll()
	end
end, "event")

-- the events, registered at the first frame laid (never at login)
function Sets.Watch()
	if Sets.watcher then
		return
	end
	local w = CreateFrame("Frame")
	w:SetScript("OnEvent", TargetEvents)
	for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_PET" }) do
		w:RegisterEvent(ev)
	end
	w:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
	Sets.watcher = w
end

-- (Mouseover Highlight, MelloUI.FrameHover: a party member in a set glows in its shape -- the outline stays away; a
-- raid cell under the painted look, a soft glow round its box) true when the frame is ours to light
function Sets.Hover(frame, on)
	local e = Sets.byFrame[frame]
	if e and e.laid then
		e.isHover = on and true or false
		Sets.GlowState(e)
		return true
	end
	-- (a box: a raid cell -- no portrait and bars the frame effects split; a portrait frame no set dresses keeps its
	-- own outline)
	local Skin = rawget(MelloUI, "Skin")
	local FX = MelloUI.FrameFX
	if Sets.Data() and Skin and Skin.Current and Skin.Current() == "oldschool" and FX and FX.Split
		and not FX.Split(frame) then
		Sets.RectGlow(frame, on)
		return true
	end
	return false
end

-- a raid cell's glow round its box: the rect glow cut by the client (DATA.rect: its pad past the cell), REACH units out
Sets.REACH = 5
function Sets.RectGlow(frame, on)
	local r = DATA.rect
	local g = Sets.rects[frame]
	if not on then
		if g then
			g:Hide()
		end
		return
	end
	if not (r and frame.CreateTexture) then
		return
	end
	if not g then
		g = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
		g:SetTexture(Sets.DIR .. "glow_rect")
		local m = r.pad + 4
		if g.SetTextureSliceMargins and g.SetTextureSliceMode and g.SetScale then
			g:SetTextureSliceMargins(m, m, m, m)
			g:SetTextureSliceMode(Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0)
			g:SetScale(Sets.REACH / r.pad)
		end
		local box = frame:CreateTexture(nil, "BACKGROUND", nil, -8)   -- (no file: the place, past the cell)
		box:SetPoint("TOPLEFT", frame, "TOPLEFT", -Sets.REACH, Sets.REACH)
		box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", Sets.REACH, -Sets.REACH)
		g:SetAllPoints(box)
		Sets.rects[frame] = g
	end
	PaintGlow(g, "hover")
	g:Show()
end

-- (2.1.58) the frame effects' parts of a frame in a set (Unit Frames' hooks, UnitFramePanel): the entry of a portrait's
-- frame, its ring (the ring's own copy: its square, the whole ring), its picture and plate
function Sets.EntryOf(region)
	local f = region
	for _ = 1, 5 do
		if type(f) ~= "table" then
			return nil
		end
		local e = Sets.byFrame[f]
		if e then
			return e.laid and e or nil
		end
		local ok, parent = pcall(f.GetParent, f)
		f = ok and parent or nil
	end
	return nil
end

function Sets.RingOf(portrait)
	local e = Sets.EntryOf(portrait)
	return e and e.ringArt or nil
end

-- the picture, its plate's rim and outer edge (shares of it, mirrored with the frame), or nil
function Sets.PlateOf(frame)
	local e = frame and Sets.byFrame[frame]
	local u = e and e.laid and e.laid.unit[e.shape]
	local plate = u and u.plate
	if not plate then
		return nil
	end
	if e.flip and e.flip() then
		plate = { 1 - plate[3], plate[2], 1 - plate[1], plate[4] }
	end
	return e.art, plate, plate
end

--------------------------------------------------------------------------------
-- (2.1.58) The level badge (the user: "the level ring on the new Unitframes dont match anymore, they need to match
-- their style"): the set's own badge over a unit frame's level circle in the kit orb's place (its orb put out), its
-- opening round the number -- laid again at a new set
--------------------------------------------------------------------------------
Sets.LEVEL_OPEN = 0.64   -- the opening's width, a share of the game's level circle (the badge about the old orb's size)

function Sets.LayLevel(b)
	local set = Sets.Data()
	local lv = set and set.level
	local orb = b.rep and b.rep.tex
	if not (lv and b.on) then
		b.tex:Hide()
		if orb then
			orb:SetAlpha(1)
		end
		return
	end
	local w = SizeOf(b.circle) or 26
	local hole = lv.hole
	local k = w * Sets.LEVEL_OPEN / (hole[3] - hole[1])
	b.tex:SetTexture(Sets.File(set, "level"))
	b.tex:SetTexCoord(0, lv.u, 0, lv.v)
	b.tex:ClearAllPoints()
	b.tex:SetPoint("CENTER", b.circle, "CENTER", (lv.w / 2 - (hole[1] + hole[3]) / 2) * k,
		-(lv.h / 2 - (hole[2] + hole[4]) / 2) * k)
	b.tex:SetSize(lv.w * k, lv.h * k)
	b.tex:SetShown(Shown(b.circle))
	if orb then
		orb:SetAlpha(0)
	end
end

-- the badge on a level circle's orb (the kit's rep), made once; on: shown with the skin
function Sets.Level(rep, circle, on)
	if not (rep and rep.tex and circle) then
		return nil
	end
	local b = Sets.levels[rep]
	if not b then
		local okP, host = pcall(circle.GetParent, circle)
		host = (okP and type(host) == "table" and host.CreateTexture) and host or rep.tex:GetParent()
		local okL, layer, sub = pcall(rep.tex.GetDrawLayer, rep.tex)
		b = { rep = rep, circle = circle,
			tex = host:CreateTexture(nil, okL and layer or "OVERLAY", nil, math.min(6, (okL and Num(sub)) or 5)) }
		Sets.levels[rep] = b
		-- (shown and hidden with the game's circle, as the orb follows it)
		local function Follow()
			if b.tex:IsShown() ~= Shown(circle) and b.on and Sets.Data() and Sets.Data().level then
				b.tex:SetShown(Shown(circle))
			end
		end
		for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
			hooksecurefunc(circle, method, Follow)
		end
	end
	b.on = on ~= false
	Sets.LayLevel(b)
	return b.tex
end

-- every badge with the skin (on) or put away, the orbs back (off)
function Sets.LevelsShown(on)
	for _, b in pairs(Sets.levels) do
		b.on = on and true or false
		Sets.LayLevel(b)
	end
end

-- a level circle's badge texture while shown (the frame effects' orb), or nil
function Sets.LevelOf(rep)
	local b = rep and Sets.levels[rep]
	return (b and b.on and b.tex:IsShown()) and b.tex or nil
end

function Sets.Unit(e)
	if type(e) ~= "table" or not (e.frame and e.region and e.shape and e.bars) then
		return nil
	end
	local had = Sets.byRegion[e.region]
	if had then
		return had
	end
	Sets.byRegion[e.region] = e
	Sets.units[#Sets.units + 1] = e
	e.on = false
	-- (made with the entry: the name is centred on the plaque, the combo points hung on the ring, before the first lay;
	-- empty and unseen until then)
	e.plaque = CreateFrame("Frame", nil, e.frame)
	e.plaque:EnableMouse(false)
	e.ring = CreateFrame("Frame", nil, e.frame)
	e.ring:EnableMouse(false)
	-- (2.1.58) the mouse over the frame: its glow (a post-hook of its own OnEnter / OnLeave / OnHide, once)
	Sets.byFrame[e.frame] = e
	if type(e.frame.HookScript) == "function" then
		Perf.HookScript(e.frame, "OnEnter", Sets.OnEnter)
		Perf.HookScript(e.frame, "OnLeave", Sets.OnLeave)
		Perf.HookScript(e.frame, "OnHide", Sets.OnLeave)
	end
	return e
end

-- the skin dressing its frame (on) or gone (off)
function Sets.UnitShown(e, on)
	if not e then
		return
	end
	e.on = on and true or false
	Sets.LayUnit(e)
end

-- every picture laid again (a new set, a party member flipped, the UI Shade)
function Sets.LayUnits()
	for _, e in ipairs(Sets.units) do
		if e.on then
			Sets.LayUnit(e)
		end
	end
end

-- (2.1.58; the user, 2026-11-17: "We also need Nameplates and Unitframes for Rare, Elite, Rare Elite and Boss enemies",
-- their "Yes, build them" to the sketch: oldschool_redesign_sketch/ranks) a target-style frame's rank -- the set's
-- portrait ring wearing the rank's ornament (rank_<kind>: elite a gold dragon, rare elite a silver one, rare a silver
-- star and laurel, boss a horned skull), its ring's outer edge on the painting's ring's, over it; the old kit crest no
-- more. The ring's own copy the frame effects read (e.ringArt) shows the ranked ring then. Only the target-shaped
-- frames (target, focus): a small frame stays plain
function Sets.Rank(e, kind)
	e.rankKind = kind
	local set = e.laid
	local r = kind and set and set.rank and set.rank[kind]
	local u = set and set.unit[e.shape]
	if not (r and u and e.shape == "target" and e.put) then
		if e.rank then
			e.rank:Hide()
		end
		if e.ringArt and e.ranked then
			e.ranked = nil
			Sets.LayUnit(e)   -- (the ring's copy back to the painting's)
		end
		return
	end
	if not e.rank then
		e.rank = e.holder:CreateTexture(nil, "OVERLAY", nil, -7)
		if Kit.RegisterTexture then
			Kit:RegisterTexture(e.rank)
		end
	end
	local cx, cy, ro = u.ring[1], u.ring[2], u.ring[4] or u.ring[3] * 1.25
	local k = ro / r.outer   -- (units a piece px)
	local file = Sets.File(set, "rank_" .. kind)
	e.rank:SetTexture(file)
	e.rank:SetTexCoord(0, r.u, 0, r.v)
	e.put(e.rank, cx - r.cx * k, cy - r.cy * k, r.w * k, r.h * k)
	e.rank:Show()
	-- the ring's copy: the ranked ring's square (its ornament past it is the rank's own)
	local x0, y0 = (r.cx - r.outer) / r.w, (r.cy - r.outer) / r.h
	local x1, y1 = (r.cx + r.outer) / r.w, (r.cy + r.outer) / r.h
	x0, y0, x1, y1 = math.max(0, x0), math.max(0, y0), math.min(1, x1), math.min(1, y1)
	e.ringArt:SetTexture(file)
	e.ringArt:SetTexCoord(r.u * x0, r.u * x1, r.v * y0, r.v * y1)
	e.put(e.ringArt, cx - ro, cy - ro, 2 * ro, 2 * ro)
	e.ranked = kind
end

-- (the marks' call, UnitFramePanel's MarkUnit) a frame's rank, the old crest put away
function Sets.Crest(e, piece, kind)
	if not (e and e.crest) then
		return
	end
	e.crest:Hide()
	Sets.Rank(e, kind)
end

--------------------------------------------------------------------------------
-- The portrait party's room (the user's brief, lk-15: "with Vertical Spacing at its default 2 the ornaments of one
-- member may reach the next"): the least room between two members so their paintings never overlap -- the painting's
-- height past a member's slot (the game's member, 53 units: Group Frames' GroupHeaders.lua adds it to Vertical
-- Spacing, PortraitSpacing) -- while the set dresses the party (Sets.PartyWorn, from the unit frames' skin). Each of
-- the three paintings stands inside its slot (39.75 - 47 of 53): no room added today
--------------------------------------------------------------------------------
Sets.MEMBER_H = 53
Sets.partyWorn = false

function Sets.PartyRoomOf(set)
	local u = set and set.unit and set.unit.small
	if not u then
		return 0
	end
	return math.max(0, math.ceil(u.h - Sets.MEMBER_H))
end

function Sets.PartyRoom()
	return Sets.partyWorn and Sets.PartyRoomOf(Sets.Data()) or 0
end

-- the unit frames' skin on the party (on) or gone (off): a set that needs room makes Group Frames lay the party again,
-- told on the bus's own 'partyroom' (2.1.58: no longer a second 'border' "frameset" -- the set did not change, and a
-- look switch told 'border' once more than its kinds, hard3/reviewfix)
function Sets.PartyWorn(on)
	on = on and true or false
	if Sets.partyWorn == on then
		return
	end
	Sets.partyWorn = on
	if Sets.PartyRoomOf(Sets.Data()) > 0 then
		MelloUI:Fire("partyroom")
	end
end

--------------------------------------------------------------------------------
-- One texture round a fill (2.1.58; the user, 2026-11-17: "make sure that the new ones are all generated as 1 texture,
-- which are scalable horizontally and Vertically", "take into consideration the detalis and dont cut them off"): the
-- set's piece cut by the client (SetTextureSliceMargins, Stretched) -- its ends (where its ornament is: Tools/
-- make_oldschool_sets.py finds them) drawn whole at the piece's scale, its plain middle stretched along the fill;
-- across, the piece at the scale its hole fits the fill's depth, so a taller bar is the whole piece bigger. A fill too
-- short for both ends: the whole piece scaled down until they fit, never an end cut. Laid on an empty box round the
-- fill (the texture's own scale sets the ends' size; a box keeps that scale out of its anchors)
--------------------------------------------------------------------------------
local StripMixin = {}
local STRETCHED = (Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched) or 0

-- the piece on `t`, cut by the client at scale `s` (units a piece px); a texture without the calls (a test world) shows
-- the piece whole. `tall` (2.1.61: several bars in one piece -- the Personal Display's): the piece's upper and lower
-- halves whole, its middle row stretched down the sides, so the ends' ornament keeps its shape at any depth
local function Cut9(t, file, p, s, tall)
	t:SetTexture(file)
	t:SetTexCoord(0, p.u, 0, p.v)
	if t.SetTextureSliceMargins and t.SetTextureSliceMode and t.SetScale then
		local m = p.margins
		local top, bottom = m[2], m[4]
		if tall and p.hole then
			top = math.floor((p.hole[2] + p.hole[4]) / 2)
			bottom = p.h - top - 1
		end
		t:SetTextureSliceMargins(m[1], top, m[3], bottom)
		t:SetTextureSliceMode(STRETCHED)
		t:SetScale(s)
	end
	t:Show()
end

function Sets.Strip(parent, layer, sub)
	local s = setmetatable({ parent = parent }, { __index = StripMixin })
	s.box = parent:CreateTexture(nil, "BACKGROUND", nil, -8)   -- (no file: draws nothing, only holds the place)
	s.t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 7)
	s.t:SetAllPoints(s.box)
	s.layer, s.sub = layer or "ARTWORK", sub or 7
	if Kit.RegisterTexture then
		Kit:RegisterTexture(s.t)
	end
	return s
end

-- a ground under the hole (and under its socket: the cast bar's icon, the nameplate's level): made on the first ask,
-- on the strip's parent
function StripMixin:Ground(on)
	if on and not self.ground then
		self.ground = self.parent:CreateTexture(nil, Sets.GROUND[1], nil, Sets.GROUND[2])
		self.iconGround = self.parent:CreateTexture(nil, Sets.GROUND[1], nil, Sets.GROUND[2])
	end
	self.wantGround = on and true or false
end

function StripMixin:Hide()
	self.t:Hide()
	if self.ground then
		self.ground:Hide()
		self.iconGround:Hide()
	end
	if self.rankTex then
		self.rankTex:Hide()
	end
	self.piece = nil
end

-- the set's `kind` ("plate" | "cast" | "shield" | "np") round `fill` (a region), the hole `depth` units across (the
-- fill's height; the upright shield's width), `length` units along (its width; the shield's height).
-- `tall` (2.1.61; the user, 2026-11-20: "1 main border with separators in the middle, depending on how many bars we
-- have active"): `fill` holds several bars -- the piece at the scale of ONE bar `depth` deep, round the whole of
-- `fill` however deep it is (Cut9's tall cut); a lying piece only
function StripMixin:Lay(set, kind, fill, depth, length, vertical, tall)
	local p = set and set[kind]
	if not (p and p.margins and fill and depth and depth > 0 and length and length > 0) then
		self:Hide()
		return false
	end
	local hole, m = p.hole, p.margins
	local s = depth / (vertical and (hole[3] - hole[1]) or (hole[4] - hole[2]))   -- units a piece px
	-- (px of the piece: along, its reach before and after the hole and its two ends; across, over and under it)
	local before, after, endA, endB, over, under
	if vertical then
		before, after, endA, endB = hole[2], p.h - hole[4], m[2], m[4]
		over, under = hole[1], p.w - hole[3]
	else
		before, after, endA, endB = hole[1], p.w - hole[3], m[1], m[3]
		over, under = hole[2], p.h - hole[4]
	end
	local short = endA + endB - before - after
	if short > 0 and short * s > length then
		s = length / short
	end
	self.piece, self.s, self.vertical, self.fill = p, s, vertical and true or false, fill
	-- (the fill's own depth at a scaled-down piece: the piece centred across it)
	local across = vertical and (hole[3] - hole[1]) or (hole[4] - hole[2])
	tall = tall and not vertical and true or false
	local slack = tall and 0 or (depth - across * s) / 2
	self.slack = slack
	local box = self.box
	box:ClearAllPoints()
	if vertical then
		self.reach = { before * s, after * s, over * s + slack, under * s + slack }
		box:SetPoint("TOPLEFT", fill, "TOPLEFT", -(over * s + slack), before * s)
		box:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", under * s + slack, -after * s)
	else
		self.reach = { over * s + slack, under * s + slack, before * s, after * s }
		box:SetPoint("TOPLEFT", fill, "TOPLEFT", -before * s, over * s + slack)
		box:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", after * s, -(under * s + slack))
	end
	Cut9(self.t, Sets.File(set, kind), p, s, tall)
	self.set, self.kind = set, kind
	if self.glows then
		for i = 1, #self.glows do
			self:LayGlow(self.glows[i])
		end
	end
	if self.rankKind or self.rankTex then
		self:LayRank()
	end
	if self.ground then
		local g = self.ground
		g:ClearAllPoints()
		g:SetPoint("TOPLEFT", fill, "TOPLEFT", -Sets.GROUND_PAD, Sets.GROUND_PAD)
		g:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", Sets.GROUND_PAD, -Sets.GROUND_PAD)
		g:SetShown(self.wantGround)
		local ig = self.iconGround
		local x0, y0, x1, y1, at = self:Icon()
		if not x0 then
			x0, y0, x1, y1, at = self:Badge()
		end
		if x0 then
			ig:ClearAllPoints()
			ig:SetPoint("TOPLEFT", fill, at, x0, -y0)
			ig:SetPoint("BOTTOMRIGHT", fill, at, x1, -y1)
		end
		ig:SetShown(self.wantGround and x0 ~= nil)
		Sets.Ground(g, self.paintGround)
		Sets.Ground(ig, self.paintGround)
	end
	return true
end

-- (2.1.58) an outer glow of the strip's piece on `parent` (the target's on the plate, the mouseover's in Mouseover
-- Highlight's frame): cut by the client as the piece is, its pad further out, at the piece's scale -- laid again with
-- the strip; shown by its state (GlowState: "target", "hover" or nil)
function StripMixin:Glow(parent, layer, sub)
	local g = { box = parent:CreateTexture(nil, "BACKGROUND", nil, -8), t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or -6) }
	g.t:SetAllPoints(g.box)
	g.t:Hide()
	self.glows = self.glows or {}
	self.glows[#self.glows + 1] = g
	if self.piece then
		self:LayGlow(g)
	end
	return g
end

function StripMixin:LayGlow(g)
	local p = self.piece
	local gd = p and p.glow
	if not gd then
		g.laid = false
		g.t:Hide()
		return
	end
	local s, pad = self.s, gd.pad
	g.box:ClearAllPoints()
	g.box:SetPoint("TOPLEFT", self.box, "TOPLEFT", -pad * s, pad * s)
	g.box:SetPoint("BOTTOMRIGHT", self.box, "BOTTOMRIGHT", pad * s, -pad * s)
	Cut9(g.t, Sets.File(self.set, self.kind .. "_glow"), gd, s)
	g.laid = true
	self:GlowState(g, g.state)
end

function StripMixin:GlowState(g, state)
	g.state = state
	if state and g.laid and self.piece then
		PaintGlow(g.t, state)
		g.t:Show()
	else
		g.t:Hide()
	end
end

-- past the fill: over, under, before, after (units; the shield: before = over it, after = under it, then its sides)
function StripMixin:Reach()
	local r = self.piece and self.reach
	if not r then
		return 0, 0, 0, 0
	end
	return r[1], r[2], r[3], r[4]
end

-- a socket of the piece (its px box): x0, y0 (down), x1, y1 from the fill's top left -- or, `fromEnd`, from its top
-- right (a socket in the piece's end stays with the end as the middle stretches) -- and that corner's name; nil when
-- the piece has none
local function Socket(self, box, fromEnd)
	local p, s = self.piece, self.s
	if not (box and s) then
		return nil
	end
	local hole = p.hole
	local slack = self.vertical and 0 or (self.slack or 0)
	local x = fromEnd and hole[3] or hole[1]
	return (box[1] - x) * s, (box[2] - hole[2]) * s + slack, (box[3] - x) * s, (box[4] - hole[2]) * s + slack,
		fromEnd and "TOPRIGHT" or "TOPLEFT"
end

-- (2.1.58) the rank on the piece's socket (the nameplate's level socket): the set's small socket wearing the rank's
-- ornament (np_rank_<kind>), its ring's outer edge on the socket ring's, over the piece; nil kind: none
function StripMixin:Rank(kind)
	self.rankKind = kind
	self:LayRank()
end

function StripMixin:LayRank()
	local set, p = self.set, self.piece
	local r = self.rankKind and set and set.np_rank and set.np_rank[self.rankKind]
	local x0, y0, x1, y1, at
	if r and p and p.socketOuter then
		x0, y0, x1, y1, at = self:Badge()
	end
	if not x0 then
		if self.rankTex then
			self.rankTex:Hide()
		end
		return
	end
	if not self.rankTex then
		self.rankTex = self.parent:CreateTexture(nil, self.layer, nil, math.min(7, self.sub + 1))
		if Kit.RegisterTexture then
			Kit:RegisterTexture(self.rankTex)
		end
	end
	local k = p.socketOuter * self.s / r.outer
	local bx, by = (x0 + x1) / 2, (y0 + y1) / 2
	local t = self.rankTex
	t:SetTexture(Sets.File(set, "np_rank_" .. self.rankKind))
	t:SetTexCoord(0, r.u, 0, r.v)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", self.fill, at, bx - r.cx * k, -(by - r.cy * k))
	t:SetSize(r.w * k, r.h * k)
	t:Show()
end

-- the cast bar's icon window (its socket at the start), from the fill's top left, or nil
function StripMixin:Icon()
	return Socket(self, self.piece and self.piece.icon, false)
end

-- the nameplate's level socket (at the end), from the fill's top right, or nil
function StripMixin:Badge()
	return Socket(self, self.piece and self.piece.badge, true)
end

--------------------------------------------------------------------------------
-- One texture round a window (the chat): the set's frame cut by the client, its four ends (the corner ornaments)
-- whole, its sides stretched, its middle empty -- the window's own background shows through. Its rail centred on the
-- rect's edge (the kit's window rail stood so), `rail` units deep: the piece at the scale its side reaches that
--------------------------------------------------------------------------------
local WindowMixin = {}

function Sets.Window(parent, layer, sub)
	local w = setmetatable({ parent = parent }, { __index = WindowMixin })
	w.box = parent:CreateTexture(nil, "BACKGROUND", nil, -8)   -- (no file: holds the place)
	w.t = parent:CreateTexture(nil, layer or "BORDER", nil, sub or 0)
	w.t:SetAllPoints(w.box)
	if Kit.RegisterTexture then
		Kit:RegisterTexture(w.t)
	end
	return w
end

function WindowMixin:Hide()
	self.t:Hide()
	self.piece = nil
end

-- the set's chat frame round `rect` (a region), its rail `rail` units deep
function WindowMixin:Lay(set, rect, rail)
	local p = set and set.chat
	if not (p and p.margins and rect and rail and rail > 0) then
		self:Hide()
		return false
	end
	local hole = p.hole
	local s = rail / hole[1]                    -- (units a piece px: its left side's depth is the rail)
	local half = rail / 2
	local box = self.box
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", rect, "TOPLEFT", half - hole[1] * s, hole[2] * s - half)
	box:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", (p.w - hole[3]) * s - half, half - (p.h - hole[4]) * s)
	Cut9(self.t, Sets.File(set, "chat"), p, s)
	self.piece = p
	return true
end

--------------------------------------------------------------------------------
-- The configurator's picture of a set (Kit:ChoicePicture's "set"): its small frame on the tile, at its aspect
--------------------------------------------------------------------------------
function Sets.Picture(tex, pic, choice, size)
	local set = choice and DATA[choice.set or choice.value]
	local u = set and set.unit.small
	if not u then
		tex:Hide()
		return false
	end
	tex:SetTexture(Sets.File(set, "small"))
	tex:SetTexCoord(0, u.u, 0, u.v)
	local w = size - 4
	local h = w * u.h / u.w
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", pic, "CENTER", 0, 0)
	tex:SetSize(w, h)
	tex:Show()
	return true
end

--------------------------------------------------------------------------------
-- A new set: every picture laid again, the Personal Display told (its own look's switch, Kit:PersonalLook); the UI
-- Shade changed: the pictures' shades
--------------------------------------------------------------------------------
Kit:OnBorderChanged("frameset", function()
	Sets.LayUnits()
	for _, b in pairs(Sets.levels) do
		Sets.LayLevel(b)
	end
	if Sets.OnSet then
		for _, fn in ipairs(Sets.OnSet) do
			pcall(fn)
		end
	end
	-- (the Personal Display hears this same 'border' "frameset" itself: no second 'border' "personal" here -- a set
	-- change told 'border' twice, hard3/reviewfix)
end)
Sets.OnSet = {}
if MelloUI.FrameHover then
	MelloUI.FrameHover.dressFrame = Sets.Hover
end

-- fn() after a new set (the cast bars, the action bars: laid again by their own panels)
function Sets.OnChange(fn)
	Sets.OnSet[#Sets.OnSet + 1] = fn
end

MelloUI:On("setting", function(name, key)
	local shade = Kit.shadeSettings
	if name == "UIModifications" and type(key) == "string" and shade
		and (key == shade.master or key == shade.strength or key == "shade_unitframes") and #Sets.units > 0 then
		Sets.LayUnits()
	end
end, "Kit sets: the pictures' shade")

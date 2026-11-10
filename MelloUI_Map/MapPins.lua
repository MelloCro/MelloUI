--------------------------------------------------------------------------------
-- MelloUI Map - the pins (docs/plans/seamless-map.md, stage M1)
--
-- One layer over the canvas, never scaled: a pin keeps its size at every zoom
-- and moves with the view (rescaling a layer of icons on every frame of a zoom
-- is the cost to avoid). Each pin is tied to a world point (the canvas's
-- world units) and kept in a grid cell; when the canvas cuts its cull box
-- again the pins of the cells in it are gathered, and each view lays only
-- those, one anchor each. A pin out of view is hidden and unanchored, its
-- texture back in its layer's pool when the pin goes.
--
-- Pins take no mouse (the setters that would pass a click through are
-- protected, blocked in a fight): the canvas, which watches the cursor while
-- it is over it, asks At(x, y) for the pin under it, for its tooltip and its
-- click.
--
--   Pins.New(canvas) -> pins
--   pins:Layer(name, order, opts)    a layer of pins (its own frame, `order` its
--                                    place in the stack; opts.minZ / maxZ: the
--                                    zooms it shows at)
--   pins:Show(name, on)              a whole layer on or off
--   pins:Set(name, key, wx, wy, spec) a pin at a world point (made or moved);
--                                    spec: icon (a file) or atlas, size (px),
--                                    rgb { r, g, b }, alpha, rotation, sub
--                                    (draw sublevel), tip (text or fn(pin) ->
--                                    lines), fillTip (fn(tooltip, pin): its
--                                    lines, the whole tooltip), click (fn(pin,
--                                    button)), look (fn(tex, pin): the pin's
--                                    picture its own, after the size), lift
--                                    (the set's icon name its glow or shade
--                                    is baked for: MelloUI.Shade:Lift), data;
--                                    (M4) frame: another addon's icon frame,
--                                    borrowed (MapAddonPins.lua: HereBeDragons'
--                                    pins) -- laid in place of a texture, its
--                                    own mouse and tooltip; release(frame)
--                                    hands it back when the pin goes
--   Pins.Lift(tex, name, size)       the icon set's glow (a disc) or shade
--                                    under a pin's picture (the UI Shade's
--                                    "icons"), where the core has it; name
--                                    false: none (a pooled texture showing
--                                    other art)
--   pins:SetAt(name, key, uiMapID, x, y, spec)  the same at a map's position
--   pins:Remove(name, key) / pins:Clear(name)
--   pins:Lay()                       the canvas's view laid (canvas.onView)
--   pins:At(x, y) -> pin             the topmost tip- or click-pin under a canvas point
--   pin.dx                           (1.2.0) px the pin stands right of its point (marks side by side)
-- (1.2.0; the user's "all eight" of BuildData/output/animation_previews/map_marks.html) a pin's moments, one-shot on
-- MelloUI.Anim's engine (Reduce Motion: the end at once); only a pin shown now moves (one out of view is simply
-- there when it comes in):
--   pins:Pop(pin, delay)             popped in after `delay`: its picture from small past its size and back, faded in
--   pins:Ring(pin)                   a gold ring of light from it, once (a count up, a quest ready to hand in)
--   pins:Raise(pin, on)              lifted a little bigger (the pin under the cursor) or set down
--   pin.moment = { pop = delay, ring = true, at = GetTime() }   played by the first lay that shows the pin, within
--                                    T.MOMENT s of `at` (a pin out of view meanwhile: dropped), then let go
-- (2.1.0, qu-01; the user's pick W1 of BuildData/output/qu01_map_sketch: "touching pins of one kind merge into one
-- with a count", the capitals named) the pins kept apart -- worked out when the zoom moved by a tenth, the cull box was
-- cut again or a pin of such a layer was set or went, never on every view:
--   opts.merge = px                  (a layer's) its pins within px of one another on the screen become one: the
--                                    first by its place shows, its count on a badge (the set's badge disc, a gold
--                                    edge, the number); pin.members every pin it holds, the others not shown
--   opts.nudge = true                (a layer's) a pin of it that would cover one laid before it (the layers by
--                                    their order, the highest first) steps aside to the nearest free place on a small
--                                    ring round its point (pin.nx, pin.ny px); none free: it stays
--   spec.disc = key                  a round disc of the palette's colour under the pin's picture, spec.edge px
--                                    past it all round (a seal's dark edge)
--   spec.core = key, spec.rim = px   a round disc of the palette's colour over the pin's picture, rim px in from
--                                    its edge (a seal: the gold rim round a slate core; the sketch's P2)
--   spec.tint = key                  the picture painted in the palette's colour (MelloUI.Painter: again with the
--                                    palette), not in its own
--   spec.own = name                  (qu-04) a picture a look may draw for the pin whole (MelloUI.Icons.Drawn: the
--                                    game's, a look's set's): shown alone in that look, without spec.tint, disc and
--                                    core; MelloUI's look keeps those. The count's badge the same (T.COUNT). Both
--                                    dressed again when the look switches (the bus's 'skin', 'icons')
--   spec.emblem = icon               (qu-04) a picture in the pin's seal: over its core 1 px in (MelloUI's look), in
--                                    a look's own seal picture at T.FRAME_EMBLEM of it (Oldschool's frame); none on
--                                    a game picture (the Default skin: the game's own look)
--   spec.many = icon                 the picture a pin shows that holds others with another picture than its own
--                                    (the quests': the "!" while one of them is still to do, though the first by
--                                    place is ready to hand in; all ready: the "?")
--   spec.number = text               (2.1.0, the dungeon map) a number in the pin's middle (a boss's place in its
--                                    dungeon's order), in the palette's spec.numberKey (default text)
--   spec.label = true                the pin's name (pin.name) beside it where it covers no pin and no other name,
--                                    else left out at that zoom (its hover still names it); pins.labelBoxes the boxes
--                                    of the names shown now (the zone names keep clear of them)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Finite = MelloUI.Safe.Finite
local ipairs, pairs, floor, tostring = ipairs, pairs, math.floor, tostring
local wipe = wipe

local Pins = {}
Pins.__index = Pins
ns.Pins = Pins

local T = {
	CELL = 16,        -- world units a grid cell (the world 1002 x 668: about 63 x 42 cells)
	MARGIN = 24,      -- px past the view a pin is still laid (its icon half out)
	LEVEL = 400,      -- the pin layer over the canvas's maps (their levels run to its root's + twice the maps' count)
	HIT = 3,          -- px round a pin's icon that still points at it
	POP = 0.3,        -- (1.2.0) a pop's time, a lift's, the ring's; the lift's size
	LIFT = 0.15,
	RING = 0.6,
	LIFTED = 1.18,
	MOMENT = 2,
	RING_ART = "Interface\\AddOns\\MelloUI\\Media\\FrameFX\\Light\\halo_white",   -- onelook-allow: a moment's light, both looks
	-- (2.1.0) the pins kept apart
	APART_ZOOM = 1.1,   -- worked out again when the zoom moved by this factor
	GAP = 1,            -- px kept free between two pins
	RING_STEP = 0.8,    -- a pin stepping aside: rings this share of its size apart, two of them, eight places a ring
	BADGE = 12,         -- the count's badge (px), its middle this share of the pin's size right and down of the pin's
	BADGE_AT = { 0.38, 0.32 },
	COUNT = "map_count",   -- (qu-04) the count's picture where a look draws its own (Skin.ICON, a look's set)
	FRAME_EMBLEM = 0.72,   -- (qu-04) an emblem inside a look's own seal picture (Oldschool's frame): this share of it
	LABEL_GAP = { 4, 14 },   -- px from a pin's edge a name may stand, the near ring first
	LABEL_PAD = 3,
	NAME_SHADE = 0.6,   -- the soft shade under a name (the zone names')
}
Pins.T = T

local function CellOf(wx, wy)
	return floor(wx / T.CELL) * 4096 + floor(wy / T.CELL)
end

local made = setmetatable({}, { __mode = "k" })   -- (qu-04) every pins object, for a look's switch

function Pins.New(canvas)
	local frame = CreateFrame("Frame", nil, canvas.frame)
	frame:SetAllPoints(canvas.frame)
	frame:SetFrameLevel(canvas.root:GetFrameLevel() + T.LEVEL)
	frame:EnableMouse(false)
	local self = setmetatable({
		canvas = canvas, frame = frame, layers = {}, cells = {}, near = {}, shownList = {}, gen = 0, cut = nil,
		dirty = true,
		-- (2.1.0) the pins kept apart: the layers that take part (the highest first), the zoom and the cull box they were
		-- worked out at, a pin of them set or gone since; the names' boxes shown now
		apartLayers = {}, apart = { k = nil, cuts = nil, dirty = true }, labelBoxes = {}, nLabels = 0,
	}, Pins)
	made[self] = true
	return self
end

function Pins:Layer(name, order, opts)
	local layer = self.layers[name]
	if layer then
		return layer
	end
	opts = opts or {}
	local f = CreateFrame("Frame", nil, self.frame)
	f:SetAllPoints(self.frame)
	f:SetFrameLevel(self.frame:GetFrameLevel() + (order or 1))
	f:EnableMouse(false)
	layer = { name = name, frame = f, pins = {}, pool = {}, on = true, minZ = opts.minZ or 0, maxZ = opts.maxZ or math.huge,
		order = order or 1, merge = opts.merge, nudge = opts.nudge and true or nil }
	self.layers[name] = layer
	if layer.merge or layer.nudge then
		local list = self.apartLayers
		list[#list + 1] = layer
		table.sort(list, function(a, b) return a.order > b.order end)
		self.apart.dirty = true
	end
	return layer
end

function Pins:Show(name, on)
	local layer = self.layers[name]
	if layer and layer.on ~= (on and true or false) then
		layer.on = on and true or false
		layer.frame:SetShown(layer.on)
		self.dirty = true
	end
end

local function Unhook(self, pin)
	local cell = self.cells[pin.cell]
	if cell then
		cell[pin] = nil
	end
	pin.cell = nil
end

local function Hook(self, pin)
	local key = CellOf(pin.wx, pin.wy)
	if pin.cell == key then
		return
	end
	if pin.cell then
		Unhook(self, pin)
	end
	local cell = self.cells[key]
	if not cell then
		cell = {}
		self.cells[key] = cell
	end
	cell[pin] = true
	pin.cell = key
	self.dirty = true
end

-- the core's icon lift (MelloUI.Shade:Lift), or nil where the core has none
local function LiftAPI()
	local Shade = rawget(MelloUI, "Shade")
	return type(Shade) == "table" and Shade.Lift and Shade or nil
end

local function HideTex(pin)
	local tex = pin.tex
	if tex and pin.spec.frame then
		-- (a borrowed frame: hidden only while it is ours -- its library may have taken it back for the game's map)
		if pin.shown and tex:GetParent() == pin.layer.frame then
			tex:Hide()
			tex:ClearAllPoints()
		end
		pin.shown = false
		return
	end
	if tex and pin.shown then
		tex:Hide()
		tex:ClearAllPoints()
		-- (its lift hidden with it, no stale alpha kept: laid again with the pin's look when it shows again)
		if LiftAPI() then
			Pins.Lift(tex, false)
			pin.dressed = false
		end
	end
	if pin.ring then
		pin.ring:Hide()
	end
	-- (2.1.0) its disc, its count and its name go with it
	if tex then
		if tex.disc then
			tex.disc:Hide()
		end
		if tex.core then
			tex.core:Hide()
		end
		if tex.emblem then
			tex.emblem:Hide()
		end
		if tex.number then
			tex.number:Hide()
		end
		if tex.badge then
			tex.badge:Hide()
		end
		if tex.label then
			tex.label.fs:Hide()
			if tex.label.band then
				tex.label.band:SetShown(false)
			end
			tex.label.on = false
		end
	end
	pin.shown = false
end

-- (qu-04) the picture a look draws for the pin whole (spec.own, MelloUI.Icons.Drawn), or nil; and the pin's size on
-- the screen in the look on show: its spec's, a game picture's `grow` applied (MelloUI.Skin: the Default skin's doors,
-- the user's yes to "a little bigger") -- read by the dressing, the pins kept apart, the pointer and the moments alike;
-- remembered per spec until the look switches (Restyle)
local function OwnOf(spec)
	local Icons = MelloUI.Icons
	return spec.own and Icons.Drawn and Icons.Drawn(spec.own) and spec.own or nil
end

-- (2.1.39; the user, 2026-11-10: "we need a scale slider on the map itself to scale its icons"; the pick: the title
-- row) every pin's size times this -- the map's own, Questie's restyled icons alike (Pins.SetScale, Map.lua's slider)
Pins.scale = 1
Pins.SCALE_MIN, Pins.SCALE_MAX = 0.5, 2

local sizes = setmetatable({}, { __mode = "k" })
local function PinPx(spec)
	local s = sizes[spec]
	if not s then
		s = (spec.size or 16) * Pins.scale
		local Skin = rawget(MelloUI, "Skin")
		local pic = Skin and spec.icon and Skin.Icon(OwnOf(spec) or spec.icon)
		if pic and pic.grow then
			s = s * pic.grow
		end
		s = floor(s + 0.5)
		sizes[spec] = s
	end
	return s
end

-- the pin's look on its texture (made from its layer's pool the first time it shows)
function Pins.Lift(tex, name, size)
	local Shade = LiftAPI()
	if Shade then
		pcall(Shade.Lift, Shade, tex, name, size)
	end
end

local function Dress(pin)
	local tex, spec = pin.tex, pin.spec
	if spec.frame then
		-- (another addon's icon on this layer, over its frame; shown as its library shows it on the game's map)
		local lf = pin.layer.frame
		tex:SetParent(lf)
		tex:ClearAllPoints()
		if tex:GetFrameLevel() <= lf:GetFrameLevel() then
			tex:SetFrameLevel(lf:GetFrameLevel() + 1)
		end
		tex:Show()
		pin.dressed = true
		return
	end
	local s = PinPx(spec)
	-- (2.1.0, qu-04) a look with a picture of its own for the pin (spec.own: the game's, a look's set's) shows that
	-- alone, without the palette's pieces (the seal's tint and discs: MelloUI's look)
	local Icons = MelloUI.Icons
	local own = OwnOf(spec)
	tex.own = own
	local Skin = rawget(MelloUI, "Skin")
	-- (2.1.0) its colour, first (a game picture with a colour of its own lays it over this: a member's class blip): the
	-- palette's (spec.tint, painted again with the palette) or its own; a pooled texture painted before lets go of the
	-- palette first
	local W = MelloUI.Widgets
	local tint = not own and spec.tint or nil
	if tex.tint and tex.tint ~= tint then
		local P = rawget(MelloUI, "Painter")
		if P and P.Unpaint then
			P.Unpaint(tex, "vertex")
		end
		tex.tint = nil
	end
	local c = spec.rgb
	if tint then
		W.Paint(tex, tint, "vertex")
		tex.tint = tint
	elseif c then
		tex:SetVertexColor(c[1], c[2], c[3])
	else
		tex:SetVertexColor(1, 1, 1)
	end
	if spec.atlas then
		tex:SetAtlas(spec.atlas, false, nil, true)   -- (2.1.4: a pooled texture's earlier crop not kept)
	elseif spec.icon then
		Icons.Set(tex, own or spec.icon, s)   -- (2026-10-21: the copy for its size; a game icon as it is)
		-- (qu-04) a game picture with a wide clear margin without it (Skin.InsetPicture: Default's doors); the icon system lets
		-- go of the texture then, and the next look switch dresses it again here (Restyle)
		local pic = Skin and Skin.InsetPicture and Skin.Icon(own or spec.icon)
		if pic and pic.inset then
			Skin.InsetPicture(tex, pic)
		end
	end
	tex:SetSize(s, s)
	tex.many = nil   -- (2.1.0: the picture for many set again by the lay's Extras)
	tex:SetAlpha(spec.alpha or 1)
	tex:SetRotation(pin.rotation or spec.rotation or 0)
	tex:SetDrawLayer("ARTWORK", spec.sub or 0)
	tex:SetDesaturated(false)
	-- (its glow or shade: the spec's; a look of its own may set another after)
	Pins.Lift(tex, spec.lift or false, s)
	if spec.look then
		spec.look(tex, pin)   -- (its own picture: the Quest List's giver icon)
	end
	-- (2.1.0) a seal: the set's badge disc in the palette's colours -- under the picture spec.edge px past it all round
	-- (spec.disc: the dark edge), over it spec.rim px in from its edge (spec.core: the slate core in the gold rim); both
	-- follow the picture's size (its moments)
	local disc = tex.disc
	if spec.disc and not own then
		if not disc then
			disc = pin.layer.frame:CreateTexture(nil, "ARTWORK")
			disc:Hide()
			tex.disc = disc
		end
		local e = spec.edge or 0
		disc:ClearAllPoints()
		disc:SetPoint("TOPLEFT", tex, "TOPLEFT", -e, e)
		disc:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", e, -e)
		MelloUI.Icons.Set(disc, "badge_disc", s + 2 * e)
		disc:SetDrawLayer("ARTWORK", (spec.sub or 0) - 1)
		W.Paint(disc, spec.disc, "vertex")
		if pin.shown then
			disc:Show()
		end
	elseif disc then
		disc:Hide()
	end
	local core = tex.core
	if spec.core and not own then
		if not core then
			core = pin.layer.frame:CreateTexture(nil, "ARTWORK")
			core:Hide()
			tex.core = core
		end
		local r = spec.rim or 0
		core:ClearAllPoints()
		core:SetPoint("TOPLEFT", tex, "TOPLEFT", r, -r)
		core:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", -r, r)
		MelloUI.Icons.Set(core, "badge_disc", s - 2 * r)
		core:SetDrawLayer("ARTWORK", (spec.sub or 0) + 1)
		W.Paint(core, spec.core, "vertex")
		if pin.shown then
			core:Show()
		end
	elseif core then
		core:Hide()
	end
	-- (qu-04) the emblem in the seal, following the picture's size (its moments)
	local emblem = tex.emblem
	local game = own and Skin and Skin.Icon(own)
	tex.emblemOn = spec.emblem and not game or nil
	if tex.emblemOn then
		if not emblem then
			emblem = pin.layer.frame:CreateTexture(nil, "ARTWORK")
			emblem:Hide()
			tex.emblem = emblem
		end
		local e = own and floor(s * T.FRAME_EMBLEM + 0.5) or (s - 2 * (spec.rim or 0) - 2)
		local i = (s - e) / 2
		emblem:ClearAllPoints()
		emblem:SetPoint("TOPLEFT", tex, "TOPLEFT", i, -i)
		emblem:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", -i, i)
		Icons.Set(emblem, spec.emblem, e)
		emblem:SetDrawLayer("ARTWORK", (spec.sub or 0) + 2)
		if pin.shown then
			emblem:Show()
		end
	elseif emblem then
		emblem:Hide()
	end
	-- (2.1.0, the dungeon map) the number in the seal
	local number = tex.number
	tex.numberOn = spec.number and true or nil
	if tex.numberOn then
		if not number then
			number = pin.layer.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			number:Hide()
			tex.number = number
		end
		number:ClearAllPoints()
		number:SetPoint("CENTER", tex, "CENTER", 0, 0)
		number:SetText(spec.number)
		W.Paint(number, spec.numberKey or "text", "text")
		if pin.shown then
			number:Show()
		end
	elseif number then
		number:Hide()
	end
	pin.dressed = true
	pin.apartAt = nil   -- (its count and its name shown again on the lay)
end

-- (2.1.0) the count's badge on a pin's texture: the set's badge disc in the palette's innerPanel, its edge in the gold,
-- the number in the palette's text -- or (qu-04) the look's own count picture (T.COUNT: the game's quest number disc,
-- a look's set's) under the number; laid again when the look switched (every badge, a pooled texture's too: the icon
-- system has set its disc again by a name the new look may not draw -- qu-04 sim: a magenta box). Made the first time a
-- pin that holds others is laid on this texture
local badges = setmetatable({}, { __mode = "k" })

local function LayBadge(b, force)
	local Icons = MelloUI.Icons
	local own = Icons.Drawn and Icons.Drawn(T.COUNT) or false
	if b.own == own and not force then
		return
	end
	b.own = own
	local P = rawget(MelloUI, "Painter")
	if own then
		if P and P.Unpaint then
			P.Unpaint(b.disc, "vertex")
		end
		b.disc:SetVertexColor(1, 1, 1)
		Icons.Set(b.disc, T.COUNT, T.BADGE)
		b.edge:Hide()
	else
		Icons.Set(b.disc, "badge_disc", T.BADGE)
		MelloUI.Widgets.Paint(b.disc, "innerPanel", "vertex")
		b.edge:Show()
	end
end

local function Badge(pin, tex)
	local b = tex.badge
	if not b then
		local W = MelloUI.Widgets
		local lf = pin.layer.frame
		b = CreateFrame("Frame", nil, lf)
		b:SetSize(T.BADGE, T.BADGE)
		b:SetFrameLevel(lf:GetFrameLevel() + 1)
		b:EnableMouse(false)
		b.disc = b:CreateTexture(nil, "ARTWORK", nil, 1)
		b.disc:SetAllPoints()
		local edge = b:CreateTexture(nil, "ARTWORK", nil, 2)
		edge:SetAllPoints()
		MelloUI.Icons.Set(edge, "badge_edge", T.BADGE)
		W.Paint(edge, "selectedTrim", "vertex")
		b.edge = edge
		local num = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		num:SetPoint("CENTER", 0, 0)
		W.Paint(num, "text", "text")
		b.num = num
		b:Hide()
		tex.badge = b
		badges[b] = true
	end
	LayBadge(b)
	return b
end

-- (2.1.0) a pin's name on its texture: the zone names' look (MelloUI's title font, the palette's text, the soft
-- shade), made the first time the pin is named
local function Label(pin, tex)
	local l = tex.label
	if not l then
		local lf = pin.layer.frame
		local fs = lf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		local Kit = MelloUI.Kit
		if Kit and Kit.TitleFont then
			Kit:TitleFont(fs, true)
		end
		MelloUI.Widgets.Paint(fs, "text", "text")
		local Shade = rawget(MelloUI, "Shade")
		local band = Shade and Shade.Band and Shade:Band(lf, { colour = "innerPanel", alpha = T.NAME_SHADE, feather = 8 })
		if band then
			band:Anchor(fs, 2, 1)
			band:SetShown(false)
		end
		fs:Hide()
		l = { fs = fs, band = band, on = false }
		tex.label = l
	end
	if l.text ~= pin.name then
		l.text = pin.name
		l.fs:SetText(pin.name or "")
	end
	return l
end

-- (2.1.0) a name's size on the screen, as Label draws it: one string of the same look measures every name once
local function Measure(self, text)
	local m = self.measured
	if not m then
		m = { sizes = {} }
		self.measured = m
	end
	local size = m.sizes[text]
	if not size then
		local fs = m.fs
		if not fs then
			fs = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			local Kit = MelloUI.Kit
			if Kit and Kit.TitleFont then
				Kit:TitleFont(fs, true)
			end
			fs:Hide()
			m.fs = fs
		end
		fs:SetText(text)
		local w, h = Finite(fs:GetStringWidth()), Finite(fs:GetStringHeight())
		if not (w and w > 0 and h and h > 0) then
			return 7 * #text, 12   -- (the face not read yet: a guess, measured again next time)
		end
		size = { w, h }
		m.sizes[text] = size
	end
	return size[1], size[2]
end

-- (2.1.0) a laid pin's count and name as the pins kept apart say (on the lay after they were worked out, or after its
-- texture changed)
local function Extras(self, pin, tex)
	pin.apartAt = self.apartGen
	if tex.disc and pin.spec.disc and not tex.own then
		tex.disc:Show()
	end
	if tex.core and pin.spec.core and not tex.own then
		tex.core:Show()
	end
	if tex.emblem and tex.emblemOn then
		tex.emblem:Show()
	end
	if tex.number and tex.numberOn then
		tex.number:Show()
	end
	local n = pin.members and #pin.members or 0
	-- (a pin that holds others with another picture than its own: spec.many's, where it has one; its own again when
	-- they are all like it or it stands alone)
	local many
	if n > 1 and pin.spec.many and pin.spec.many ~= pin.spec.icon then
		for _, m in ipairs(pin.members) do
			if m.spec.icon ~= pin.spec.icon then
				many = pin.spec.many
				break
			end
		end
	end
	if tex.many ~= many then
		tex.many = many
		MelloUI.Icons.Set(tex, many or tex.own or pin.spec.icon, PinPx(pin.spec))
	end
	if n > 1 then
		local b = Badge(pin, tex)
		if b.n ~= n then
			b.n = n
			b.num:SetText(n)
		end
		local s = PinPx(pin.spec)
		b:ClearAllPoints()
		b:SetPoint("CENTER", tex, "CENTER", s * T.BADGE_AT[1], -s * T.BADGE_AT[2])
		b:Show()
	elseif tex.badge then
		tex.badge:Hide()
	end
	local l = tex.label
	if pin.labelX and pin.spec.label then
		l = Label(pin, tex)
		l.fs:ClearAllPoints()
		l.fs:SetPoint("CENTER", tex, "CENTER", pin.labelX, -pin.labelY)
		if not l.on then
			l.on = true
			l.fs:Show()
			if l.band then
				l.band:SetShown(true)
			end
		end
	elseif l and l.on then
		l.on = false
		l.fs:Hide()
		if l.band then
			l.band:SetShown(false)
		end
	end
end

function Pins:Set(name, key, wx, wy, spec)
	wx, wy = Finite(wx), Finite(wy)
	local layer = self.layers[name] or self:Layer(name)
	local pin = layer.pins[key]
	if not (wx and wy) then
		if pin then
			self:Remove(name, key)
		end
		return nil
	end
	if not pin then
		pin = { layer = layer, key = key, shown = false }
		layer.pins[key] = pin
	end
	if pin.spec ~= spec then
		if pin.tex and pin.spec and (pin.spec.frame or spec.frame) then
			-- (a texture for a frame or the other way round: the old one let go first)
			self:Remove(name, key)
			return self:Set(name, key, wx, wy, spec)
		end
		pin.spec = spec
		pin.dressed = false
	end
	if (layer.merge or layer.nudge) and (pin.wx ~= wx or pin.wy ~= wy) then
		self.apart.dirty = true   -- (2.1.0: a pin kept apart came or moved: worked out again on the lay)
	end
	pin.wx, pin.wy = wx, wy
	Hook(self, pin)
	return pin
end

-- a pin at a map's position (0..1 on uiMapID), carried to world units by the canvas
function Pins:SetAt(name, key, uiMapID, x, y, spec)
	local wx, wy = self.canvas:ToWorld(uiMapID, x, y)
	return self:Set(name, key, wx, wy, spec)
end

function Pins:Remove(name, key)
	local layer = self.layers[name]
	local pin = layer and layer.pins[key]
	if not pin then
		return
	end
	HideTex(pin)
	if pin.tex then
		local spec = pin.spec
		if spec.frame then
			if spec.release then
				spec.release(pin.tex, layer.frame)   -- (a borrowed frame back where its library keeps it)
			end
		else
			layer.pool[#layer.pool + 1] = pin.tex
		end
		pin.tex = nil
	end
	if pin.ring then
		pin.ring:Hide()
		layer.rings = layer.rings or {}
		layer.rings[#layer.rings + 1] = pin.ring
		pin.ring = nil
	end
	local Anim = MelloUI.Anim
	if Anim then
		Anim:Stop(pin)
	end
	Unhook(self, pin)
	layer.pins[key] = nil
	self.dirty = true
	if layer.merge or layer.nudge then
		self.apart.dirty = true
	end
end

function Pins:Clear(name)
	local layer = self.layers[name]
	if not layer then
		return
	end
	for key in pairs(layer.pins) do
		self:Remove(name, key)
	end
end

-- the pins of the cells in the canvas's cull box (again when it is cut again, or a pin was set or went)
local function Gather(self)
	local c = self.canvas
	local box = c.box
	local near = self.near
	wipe(near)
	self.gen = self.gen + 1
	local gen = self.gen
	local cx0, cy0 = floor(box[1] / T.CELL), floor(box[2] / T.CELL)
	local cx1, cy1 = floor(box[3] / T.CELL), floor(box[4] / T.CELL)
	local cells = self.cells
	for gx = cx0, cx1 do
		for gy = cy0, cy1 do
			local cell = cells[gx * 4096 + gy]
			if cell then
				for pin in pairs(cell) do
					near[#near + 1] = pin
					pin.gen = gen
				end
			end
		end
	end
	-- (shown before, gathered no more: hidden)
	local list = self.shownList
	for i = #list, 1, -1 do
		local pin = list[i]
		if pin.gen ~= gen then
			HideTex(pin)
		end
		list[i] = nil
	end
	self.cut, self.dirty = c.cuts, false
end

-- (2.1.0) the pins kept apart (the layers with merge or nudge, the highest first): merged, stepped aside, named. On
-- screen px at the zoom now, relative only (a pin's world point times k): the view's corner moves them all alike
local function Overlaps(boxes, n, x0, y0, x1, y1, gap)
	for i = 1, n do
		local b = boxes[i]
		if not (x1 + gap <= b[1] or b[3] + gap <= x0 or y1 + gap <= b[2] or b[4] + gap <= y0) then
			return true
		end
	end
	return false
end

local function ByPlace(a, b)
	if a.wx ~= b.wx then
		return a.wx < b.wx
	end
	if a.wy ~= b.wy then
		return a.wy < b.wy
	end
	return tostring(a.key) < tostring(b.key)   -- (two on one spot: the same one first every time)
end

local RING = {}
for i = 0, 7 do
	RING[#RING + 1] = { math.cos(math.pi * i / 4), math.sin(math.pi * i / 4) }
end

local function PutBox(boxes, n, x0, y0, x1, y1)
	n = n + 1
	local b = boxes[n]
	if not b then
		b = {}
		boxes[n] = b
	end
	b[1], b[2], b[3], b[4] = x0, y0, x1, y1
	return n
end

local function Apart(self, k)
	local a, c = self.apart, self.canvas
	a.k, a.cuts, a.dirty = k, c.cuts, false
	self.apartGen = (self.apartGen or 0) + 1
	local z = c.z
	local boxes, n = a.boxes or {}, 0
	a.boxes = boxes
	-- every pin of these layers in the cull box: none merged, none aside, none named until laid below
	for _, layer in ipairs(self.apartLayers) do
		layer.cand = wipe(layer.cand or {})
	end
	for _, pin in ipairs(self.near) do
		local layer = pin.layer
		if layer.cand then
			pin.under, pin.members, pin.nx, pin.ny, pin.labelX, pin.labelY = nil, nil, nil, nil, nil, nil
			if layer.on and z >= layer.minZ and z <= layer.maxZ then
				layer.cand[#layer.cand + 1] = pin
			end
		end
	end
	local named = a.named or {}
	a.named = wipe(named)
	for _, layer in ipairs(self.apartLayers) do
		local list = layer.cand
		table.sort(list, ByPlace)
		-- merged: a pin within `merge` px of a first one (by place) is held by it
		if layer.merge then
			local r = layer.merge * Pins.scale / k   -- (2.1.39: bigger icons touch sooner)
			local r2, firsts = r * r, a.firsts or {}
			a.firsts = wipe(firsts)
			for _, pin in ipairs(list) do
				local by
				for _, f in ipairs(firsts) do
					local dx, dy = pin.wx - f.wx, pin.wy - f.wy
					if dx * dx + dy * dy <= r2 then
						by = f
						break
					end
				end
				if by then
					pin.under = by
					by.members = by.members or { by }
					by.members[#by.members + 1] = pin
				else
					firsts[#firsts + 1] = pin
				end
			end
			wipe(list)
			for i, f in ipairs(firsts) do
				list[i] = f
			end
		end
		-- laid: where it stands, or (nudge) the nearest free place on a ring round it
		for _, pin in ipairs(list) do
			local s = PinPx(pin.spec) / 2
			local x, y = pin.wx * k + (pin.dx or 0), pin.wy * k
			local ox, oy = 0, 0
			if layer.nudge and Overlaps(boxes, n, x - s, y - s, x + s, y + s, T.GAP) then
				local found = false
				for ring = 1, 2 do
					local d = 2 * s * T.RING_STEP * ring
					for _, u in ipairs(RING) do
						local tx, ty = x + u[1] * d, y + u[2] * d
						if not Overlaps(boxes, n, tx - s, ty - s, tx + s, ty + s, T.GAP) then
							ox, oy, found = u[1] * d, u[2] * d, true
							break
						end
					end
					if found then
						break
					end
				end
			end
			if ox ~= 0 or oy ~= 0 then
				pin.nx, pin.ny = ox, oy
			end
			n = PutBox(boxes, n, x + ox - s, y + oy - s, x + ox + s, y + oy + s)
			if pin.spec.label and pin.name then
				named[#named + 1] = pin
			end
		end
	end
	-- named: beside the pin, the near ring first (right, left, below, above, then the corners), where it covers no
	-- pin and no name laid before; else left out at this zoom
	local pad = T.LABEL_PAD
	for _, pin in ipairs(named) do
		local w, h = Measure(self, pin.name)
		local s = PinPx(pin.spec) / 2
		local x, y = pin.wx * k + (pin.dx or 0) + (pin.nx or 0), pin.wy * k + (pin.ny or 0)
		for _, g in ipairs(T.LABEL_GAP) do
			local e = s + g
			local spots = a.spots or {}
			a.spots = spots
			spots[1], spots[2] = e + w / 2, 0
			spots[3], spots[4] = -e - w / 2, 0
			spots[5], spots[6] = 0, e + h / 2 - 2
			spots[7], spots[8] = 0, -e - h / 2 + 2
			spots[9], spots[10] = e * 0.7 + w / 2, e * 0.6
			spots[11], spots[12] = -e * 0.7 - w / 2, e * 0.6
			spots[13], spots[14] = e * 0.7 + w / 2, -e * 0.6
			spots[15], spots[16] = -e * 0.7 - w / 2, -e * 0.6
			for i = 1, 15, 2 do
				local cx, cy = x + spots[i], y + spots[i + 1]
				local x0, y0, x1, y1 = cx - w / 2 - pad, cy - h / 2, cx + w / 2 + pad, cy + h / 2
				if not Overlaps(boxes, n, x0, y0, x1, y1, 0) then
					pin.labelX, pin.labelY = spots[i], spots[i + 1]
					n = PutBox(boxes, n, x0, y0, x1, y1)
					break
				end
			end
			if pin.labelX then
				break
			end
		end
	end
end

function Pins:Lay()
	local c = self.canvas
	if not (c.cx and c.box[1]) then
		return
	end
	if self.dirty or self.cut ~= c.cuts then
		Gather(self)
	end
	local k = c.k1 * c.z
	-- (2.1.0) the pins kept apart, worked out again when the zoom moved by a tenth, the cull box was cut again or one
	-- of them came, moved or went
	local a = self.apart
	if #self.apartLayers > 0 and (a.dirty or a.cuts ~= c.cuts or not a.k or k > a.k * T.APART_ZOOM
		or k < a.k / T.APART_ZOOM) then
		Apart(self, k)
	end
	local x0, y0 = c.cx - c.cw / (2 * k), c.cy - c.ch / (2 * k)
	local w, h, m = c.cw, c.ch, T.MARGIN
	local list = self.shownList
	local n, nl = 0, 0
	local gen = self.apartGen
	for _, pin in ipairs(self.near) do
		local layer = pin.layer
		local x, y = (pin.wx - x0) * k + (pin.dx or 0) + (pin.nx or 0), (pin.wy - y0) * k + (pin.ny or 0)
		if layer.on and c.z >= layer.minZ and c.z <= layer.maxZ and x > -m and x < w + m and y > -m and y < h + m
			and not pin.under then
			local tex = pin.tex
			local frame = pin.spec.frame
			if not tex then
				local pool = layer.pool
				tex = frame or pool[#pool]
				if frame then
					pin.shown = false
				elseif tex then
					pool[#pool] = nil
				else
					tex = layer.frame:CreateTexture(nil, "ARTWORK")
				end
				pin.tex = tex
				pin.dressed = false
			elseif frame and tex:GetParent() ~= layer.frame then
				pin.dressed = false   -- (its library took it back for the game's map meanwhile: ours again)
			end
			if not pin.dressed then
				Dress(pin)
			end
			tex:SetPoint("CENTER", layer.frame, "TOPLEFT", x, -y)
			local was = pin.shown
			if not was then
				tex:Show()
				pin.shown = true
			end
			if pin.ring then
				pin.ring:SetPoint("CENTER", layer.frame, "TOPLEFT", x, -y)
				pin.ring:Show()
			end
			-- (2.1.0) its disc, its count and its name as the pins kept apart say; a name's box for the zone names
			if not frame and (not was or (layer.cand and pin.apartAt ~= gen)) then
				Extras(self, pin, tex)
			end
			if pin.labelX and tex.label and tex.label.on then
				local lw, lh = Measure(self, pin.name)
				local lx, ly = x + pin.labelX, y + pin.labelY
				nl = PutBox(self.labelBoxes, nl, lx - lw / 2, ly - lh / 2, lx + lw / 2, ly + lh / 2)
			end
			pin.x, pin.y = x, y
			local mo = pin.moment
			if mo then
				pin.moment = nil
				if GetTime() - (mo.at or 0) <= T.MOMENT then
					if mo.pop then
						self:Pop(pin, mo.pop)
					end
					if mo.ring then
						self:Ring(pin)
					end
				end
			end
			n = n + 1
			list[n] = pin
		elseif pin.shown then
			HideTex(pin)
		end
	end
	for i = n + 1, #list do
		list[i] = nil
	end
	self.count = n
	self.nLabels = nl
end

-- the pin under a canvas point: the topmost (its layer's order, then the last laid) with a tip or a click
function Pins:At(x, y)
	local best, bestOrder
	for _, pin in ipairs(self.shownList) do
		local spec = pin.spec
		if pin.shown and (spec.tip or spec.fillTip or spec.click) then
			local r = PinPx(spec) / 2 + T.HIT
			local dx, dy = pin.x - x, pin.y - y
			if dx * dx + dy * dy <= r * r and (not bestOrder or pin.layer.order >= bestOrder) then
				best, bestOrder = pin, pin.layer.order
			end
		end
	end
	return best
end

-- (1.2.0) the moments
local function Clamp(v)
	return v < 0 and 0 or (v > 1 and 1 or v)
end

-- a pin's picture at k times its size (a pin not shown, or a borrowed frame: nothing)
local function Size(pin, k)
	local tex = pin.tex
	if tex and pin.shown and not pin.spec.frame then
		local s = PinPx(pin.spec) * k
		tex:SetSize(s, s)
	end
end

local function PopStep(pin, v)
	local p = Clamp((v * pin.popTotal - pin.popDelay) / T.POP)
	-- (from 0.4 of its size a little past it and back)
	local q = p - 1
	Size(pin, 0.4 + 0.6 * (1 + 2.9 * q * q * q + 1.9 * q * q))
	if pin.tex and pin.shown and not pin.spec.frame then
		pin.tex:SetAlpha((pin.spec.alpha or 1) * Clamp(p * 3))
	end
end

local function Rest(pin)
	Size(pin, pin.lifted and T.LIFTED or 1)
	if pin.tex and pin.shown and not pin.spec.frame then
		pin.tex:SetAlpha(pin.spec.alpha or 1)
	end
end

function Pins:Pop(pin, delay)
	local Anim = MelloUI.Anim
	if not (pin and pin.shown and pin.tex) or pin.spec.frame then
		return
	end
	if not Anim or Anim.reduceMotion then
		Rest(pin)
		return
	end
	pin.popDelay = delay or 0
	pin.popTotal = pin.popDelay + T.POP
	PopStep(pin, 0)
	Anim:Drive(pin, PopStep, pin.popTotal, "linear", Rest)
end

function Pins:Ring(pin)
	local Anim = MelloUI.Anim
	if not (Anim and pin and pin.shown and pin.tex) or Anim.reduceMotion then
		return
	end
	local layer = pin.layer
	local ring = pin.ring
	if not ring then
		local rings = layer.rings
		ring = rings and rings[#rings]
		if ring then
			rings[#rings] = nil
		else
			ring = layer.frame:CreateTexture(nil, "OVERLAY", nil, 7)
			ring:SetTexture(T.RING_ART)
			ring:SetBlendMode("ADD")
			if MelloUI.Painter and MelloUI.Painter.Paint then
				MelloUI.Painter.Paint(ring, "selectedTrim", "vertex")
			end
		end
		pin.ring = ring
	end
	local s = PinPx(pin.spec) * 1.3
	ring:SetSize(s, s)
	ring:ClearAllPoints()
	ring:SetPoint("CENTER", layer.frame, "TOPLEFT", pin.x or 0, -(pin.y or 0))
	Anim:Burst(ring, 1.9, 0.9, T.RING)
end

local function LiftStep(pin, v)
	local from, to = pin.liftFrom or 1, pin.lifted and T.LIFTED or 1
	Size(pin, from + (to - from) * (1 - (1 - v) ^ 3))
end

function Pins:Raise(pin, on)
	local Anim = MelloUI.Anim
	if not pin or pin.spec.frame then
		return
	end
	local w = pin.tex and pin.tex:GetWidth()
	pin.liftFrom = (type(w) == "number" and w > 0) and w / PinPx(pin.spec) or 1
	pin.lifted = on and true or false
	if not Anim or Anim.reduceMotion then
		Rest(pin)
		return
	end
	Anim:Drive(pin, LiftStep, T.LIFT, "linear", Rest)
end

-- (qu-04) the look switched (the skin, a look's own icon set: the bus's 'skin' and 'icons', after MelloUI.Icons has
-- set every held picture again): every count laid again now, every pin dressed again on the next lay (its own picture,
-- its size: PinPx forgets the old look's) and the pins kept apart worked out again -- now while the map shows
local function Restyle()
	wipe(sizes)
	for b in pairs(badges) do
		LayBadge(b, true)
	end
	for self in pairs(made) do
		for _, layer in pairs(self.layers) do
			for _, pin in pairs(layer.pins) do
				pin.dressed = false
				pin.apartAt = nil
			end
		end
		self.apart.dirty = true
		if self.frame:IsVisible() then
			self:Lay()
		end
	end
end
MelloUI:On("skin", Restyle, Pins)
MelloUI:On("icons", Restyle, Pins)

-- (2.1.39) the icons' scale (SCALE_MIN .. SCALE_MAX): every pin dressed again at its new size, as for a look switch
function Pins.SetScale(k)
	k = tonumber(k) or 1
	k = math.min(Pins.SCALE_MAX, math.max(Pins.SCALE_MIN, k))
	if k ~= Pins.scale then
		Pins.scale = k
		Restyle()
	end
end

-- every pin of a layer (the tests and the dump)
function Pins:Each(name, fn)
	local layer = self.layers[name]
	for _, pin in pairs(layer and layer.pins or {}) do
		fn(pin)
	end
end

return Pins

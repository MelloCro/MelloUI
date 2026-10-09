--------------------------------------------------------------------------------
-- MelloUI - Kit border library (0.19.8; docs/plans/border-library.md, stage 1:
-- the core and the square shape; the user, 2026-10-06: "library type borders
-- ... where it just pulls from those resources instead of building everything
-- 1 by 1 ... like Masque addon does it", every answer "as recommended")
--
-- A border STYLE is data: one master (a square nine-slice piece, Tools/
-- build_kit.py's borders/ group) or a rail family's eight pieces (`prefix`),
-- its reference rail, its corner gems. An element asks for a border at a
-- WEIGHT (its size class) and every style fits it:
--   light   rails ~5 / 4 screen px, gems 9 (auras, buttons, raid frames: the
--           Thin iron of a button today)
--   medium  rails ~8 / 6, gems 13 (unit frame plates, a raid group's outline)
--   heavy   rails ~12 / 10, gems 17 (the minimap, windows)
-- A weight is the band of a style's reference rail in UI units: the style is
-- drawn at band / rail (Kit:CutNine at that scale), so the five thin rims keep
-- their own proportions (a hairline stays a hairline) as they do on a button
-- today, and the Backdrop's heavy frame shrinks to the weight with its gems
-- laid on afterwards at the weight's gem size (shrinking the frame whole left
-- 6 px dots: the sketch). Where the frame lies is the element's: "on" its
-- rect (an icon, a frame: the content in the opening) or "round" it (a bar,
-- the map: the content keeps its size).
--   Kit.BorderStyles[id], Kit.BorderStyleOrder, Kit.BorderWeights[id]
--   Kit.squareLooks          the square rows' choices (the five thin rims, the
--                            Single rail, the Backdrop): `style` the id
--   Kit:NewBorder(opts)      a border on an element:
--     opts.rect    the element's frame (its rect)
--     opts.owner   the frame whose REGIONS the parts are (a compact raid
--                  frame's: in its layer stack); else a holder of its own
--     opts.layer / opts.sub   the rails' draw layer (gems one sublevel over)
--     opts.place   "on" (default) or "round"
--     opts.level   a holder's level over the rect's
--   border:Lay(style, weight, gem)   drawn in that style at that weight
--            (gem: "red" / "iron", the Backdrop's corner gems; nil: the
--            Action Bars Kit's Backdrop choice); false: an unknown style
--   border:SetShown(on), border:SetLit(hover, pressed, disabled) (a button's
--            states: the shared glow under the mouse -- the rails added
--            again as light in the palette's hover --, a darken pressed or
--            disabled; checked is the Active look, Kit:SetActive)
--   Kit:BorderGem()          the Backdrop's gem colour: Action Bars Kit's
--                            Backdrop (one gem setting, the plan's 2.1)
-- Nothing is made at login: a border's parts on its first Lay, its glow on
-- its first hover. A new Kit Colours look reaches the parts by themselves
-- (Kit:Apply registers them).
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit
-- what the kit keeps beside the game's frames (Kit.lua: weak-keyed, never keys on them)
local pieceNameOf = MelloUI.Kept.pieceNameOf
local repOf = MelloUI.Kept.repOf
local tintBaseOf = MelloUI.Kept.tintBaseOf
local W = MelloUI.Widgets

-- the styles: `master` a square piece cut at `corner` piece px, or `prefix` a
-- rail family's pieces; `rail` the reference rail (piece px) a weight's band
-- is measured on; `gems` the Backdrop's corner gems
Kit.BorderStyles = {
	thin = { label = "Thin iron", master = "borders/rim", corner = 13, rail = 13 },
	hairline = { label = "Hairline", master = "borders/rimhair", corner = 8, rail = 13 },
	rounded = { label = "Rounded corners", master = "borders/rimround", corner = 24, rail = 13 },
	gold = { label = "Iron with gold line", master = "borders/rimgold", corner = 13, rail = 13 },
	sunk = { label = "Sunk", master = "borders/rimsunk", corner = 13, rail = 13 },
	-- (the window rail family; its reference set so that light is the raid
	-- frames' single rail of today, F1, and heavy about the minimap's)
	single = { label = "Single rail", prefix = "window/single", rail = 16 },
	backdrop = { label = "Backdrop", master = "borders/backdrop", corner = 28, rail = 28, gems = true },
	-- (the NewUI2 rims the user picked, Tools/make_newui2_borders.py: `rail` the master's opening, `corner` its swept
	-- band; `stud` the corner's own piece, `studOff` its centre from the rails' crossing as a share of its size, cut
	-- at the top left and mirrored for the others; `minWeight` / `maxWeight` the weights it is drawn at: N5's nubs
	-- vanish past medium, N1's bevel crowds a light element -- the decision's per-style range)
	n4 = { label = "Medium iron, corner studs", master = "borders/n4", corner = 27, rail = 26, stud = "borders/n4_gem",
		studOff = { 0.129, 0.048 } },
	n4g = { label = "Thin gold, corner studs", master = "borders/n4g", corner = 30, rail = 29, stud = "borders/n4g_gem",
		studOff = { 0.195, 0.207 } },
	n5 = { label = "Hairline, corner nubs", master = "borders/n5", corner = 13, rail = 12, stud = "borders/n5_gem",
		studOff = { 0.074, 0.111 }, maxWeight = "medium" },
	n1 = { label = "Heavy bevel, corner studs", master = "borders/n1", corner = 42, rail = 40, stud = "borders/n1_gem",
		studOff = { 0.117, 0.064 }, minWeight = "medium" },
}
Kit.BorderStyleOrder = { "thin", "hairline", "rounded", "gold", "sunk", "single", "backdrop", "n4", "n4g", "n5", "n1" }
-- (UI units: band = the reference rail's on-screen depth, gem = a gem's side)
Kit.BorderWeights = {
	light = { band = 4.9, gem = 8.2 },
	medium = { band = 7.3, gem = 11.8 },
	heavy = { band = 10.9, gem = 15.5 },
}
-- a darken as the engine's vertex colour (a brightness, every channel alike)
local DARK = { pressed = 0.72, disabled = 0.55 }
local GLOW_ALPHA = 0.6   -- the shared glow under the mouse: the rails added again as light

-- The square rows' choices, the configurator's pictures included (`style`
-- the library's id; `piece` the picture's master where there is one)
Kit.squareLooks = {}
for _, id in ipairs(Kit.BorderStyleOrder) do
	local st = Kit.BorderStyles[id]
	Kit.squareLooks[#Kit.squareLooks + 1] = { value = id, label = st.label, style = id, piece = st.master }
end

-- The Backdrop's gem colour: Action Bars Kit's Backdrop choice (red / iron)
function Kit:BorderGem()
	local abp = MelloUI.GetModuleDB and MelloUI:GetModuleDB("ActionBarPanel")
	local v = type(abp) == "table" and abp.barBackdrop
	return v == "iron" and "iron" or "red"
end

--------------------------------------------------------------------------------
-- A border
--------------------------------------------------------------------------------
local Border = {}
Border.__index = Border
local GEM_CORNERS = { "tl", "tr", "bl", "br" }
local GEM_POINT = { tl = "TOPLEFT", tr = "TOPRIGHT", bl = "BOTTOMLEFT", br = "BOTTOMRIGHT" }
local GEM_SIGN = { tl = { 1, -1 }, tr = { -1, -1 }, bl = { 1, 1 }, br = { -1, 1 } }   -- inward from each corner (x, y)

--     opts.shade   { root = , area = } (0.19.8): the UI shade round it -- its
--                  parts' and gems' shadow partners in that area's element
--                  (Kit:ShadeElement), cut again by Kit:CutNine at every lay;
--                  for a border that stands in for no shaded piece of its own
--                  (a button's rim, F1's rails and a bar's bracket keep theirs)
function Kit:NewBorder(opts)
	return setmetatable({ rect = opts.rect, owner = opts.owner, layer = opts.layer or "OVERLAY", sub = opts.sub or 3,
		place = opts.place or "on", level = opts.level or 1, shown = false, shade = opts.shade }, Border)
end

-- the shade element its partners join (made with the first one)
local function ShadeOf(b)
	if not b.shade then
		return nil
	end
	if b.shadeEl == nil then
		b.shadeEl = Kit.ShadeElement and Kit:ShadeElement(b.shade.root, b.shade.area, b.shade.opts or {}) or false
	end
	return b.shadeEl or nil
end

-- the eight parts' partners, once (their cut as CutNine's for the master at
-- hand; a later lay cuts them again)
local function ShadeParts(b, st)
	local el = ShadeOf(b)
	if not el or b.partsShaded then
		return
	end
	local p = Kit:Piece(st.master)
	if not (p and p.w and p.h) then
		return
	end
	b.partsShaded = true
	local c, w, h = st.corner, p.w, p.h
	local cuts = { tl = { 0, c, 0, c }, tr = { w - c, w, 0, c }, bl = { 0, c, h - c, h }, br = { w - c, w, h - c, h },
		t = { c, w - c, 0, c }, b = { c, w - c, h - c, h }, l = { 0, c, c, h - c }, r = { w - c, w, c, h - c } }
	for _, key in ipairs(Kit.nineParts) do
		el:Add(b.parts[key], { cut = cuts[key] })
	end
end

-- a frame, not a texture (the game takes no texture as a frame's parent, and
-- a texture has no level of its own)
local function IsFrame(r)
	return r.IsObjectType and r:IsObjectType("Frame") or false
end

-- A border on a texture rect with an owner (a button's rim, a cooldown icon,
-- an aura's anchor) makes no frame at all: its anchor and every piece are the
-- owner's regions. On a game button whose aspects are secret (an aura button)
-- a frame of ours may neither stand inside it (the game takes no OnShow hook
-- there) nor anchor on it from outside (it would inherit the button's
-- forbidden aspects), and a texture is no frame's parent (0.19.8, the user's
-- aura errors)
local function Frameless(self)
	return self.owner ~= nil and not IsFrame(self.rect)
end

-- the border's own anchor on the rect: a frame, a child of the owner's (of
-- the rect without one); frameless, an empty texture of the owner's
local function Holder(self)
	local h = self.holder
	if not h then
		local rect = self.rect
		if Frameless(self) then
			h = self.owner:CreateTexture(nil, self.layer, nil, self.sub)   -- (no art: an anchor only)
		else
			local frameOf = IsFrame(rect) and rect or rect:GetParent()
			h = CreateFrame("Frame", nil, self.owner or frameOf)
			h:SetFrameLevel(math.max((frameOf:GetFrameLevel() or 0) + self.level, 0))
			h:EnableMouse(false)
		end
		h:SetAllPoints(rect)
		self.holder = h
	end
	return h
end

-- the region the nine is laid on: the rect itself ("on", parts on the owner),
-- or a holder of its own (round the rect; or the parts' frame when no owner)
function Border:At()
	if self.place == "on" and self.owner then
		return self.rect
	end
	return Holder(self)
end

-- A rail family's eight pieces with no frame (a frameless border's): the
-- owner's regions on the anchor region, as Kit:NineSlice lays them, in the
-- shape a skin answers with (art, all, kitScale, Show / Hide / SetShown).
-- The edges tiled to their length when it can be read; a size that reads
-- secret (an aura button's) leaves each edge's one tile stretched along it
-- (the rails are even along their length)
local RailSet = {}
RailSet.__index = RailSet
function RailSet:SetShown(on)
	for _, tex in ipairs(self.all) do
		tex:SetShown(on)
	end
	if on then
		for _, tex in ipairs(self.tiled) do
			Kit:Retile(tex)
		end
	end
end
function RailSet:Show()
	self:SetShown(true)
end
function RailSet:Hide()
	self:SetShown(false)
end

local RAIL_CORNER_AT = { tl = "TOPLEFT", tr = "TOPRIGHT", bl = "BOTTOMLEFT", br = "BOTTOMRIGHT" }
local function RailNine(at, host, prefix, k, layer, sub)
	local set = setmetatable({ kitScale = k, art = {}, all = {}, tiled = {} }, RailSet)
	local T = Kit:Size(prefix .. "_tl", k)
	for _, c in ipairs(GEM_CORNERS) do
		local tex = Kit:Texture(host, prefix .. "_" .. c, layer, math.min(sub + 1, 7), k)
		tex:SetPoint(RAIL_CORNER_AT[c], at, RAIL_CORNER_AT[c])
		set.art[#set.art + 1] = tex
		set.all[#set.all + 1] = tex
	end
	local edges = {
		t = { "TOPLEFT", T, 0, "TOPRIGHT", -T, 0 }, b = { "BOTTOMLEFT", T, 0, "BOTTOMRIGHT", -T, 0 },
		l = { "TOPLEFT", 0, -T, "BOTTOMLEFT", 0, T }, r = { "TOPRIGHT", 0, -T, "BOTTOMRIGHT", 0, T },
	}
	for _, e in ipairs({ "t", "b", "l", "r" }) do
		local a = edges[e]
		local tex = host:CreateTexture(nil, layer, nil, sub)
		tex.kitScale = k
		Kit:Apply(tex, prefix .. "_" .. e, true)
		tex:SetPoint(a[1], at, a[1], a[2], a[3])
		tex:SetPoint(a[4], at, a[4], a[5], a[6])
		if e == "t" or e == "b" then
			tex:SetHeight(T)
		else
			tex:SetWidth(T)
		end
		Kit:Retile(tex)
		set.art[#set.art + 1] = tex
		set.all[#set.all + 1] = tex
		set.tiled[#set.tiled + 1] = tex
	end
	return set
end

-- a rail family's nine for this border: a kit nine-slice on its frame, or
-- frameless its pieces on the anchor region; `sub` its draw sublevel
local function NineFor(b, prefix, k, sub)
	if Frameless(b) then
		return RailNine(b:At(), b:Host(), prefix, k, b.layer, sub)
	end
	return Kit:NineSlice(b:At(), { prefix = prefix, scale = k, gems = false, body = false,
		owner = b.owner, edgeLayer = b.layer, edgeSub = sub })
end

-- the frame the parts are regions of
function Border:Host()
	return self.owner or self:At()
end

local function NewParts(host, layer, sub)
	local parts = {}
	for _, key in ipairs(Kit.nineParts) do
		parts[key] = host:CreateTexture(nil, layer, nil, sub)
	end
	return parts
end

local function ShowParts(parts, on)
	if parts then
		for _, key in ipairs(Kit.nineParts) do
			parts[key]:SetShown(on)
		end
	end
end

-- round the rect: the holder grown by the master's rails at k, the opening on the rect
local function PlaceRound(b, st, k)
	local h = b:At()
	local p = Kit:Piece(st.master or "")
	local open = p and p.open
	h:ClearAllPoints()
	if open then
		h:SetPoint("TOPLEFT", b.rect, "TOPLEFT", -open[1] * k, open[2] * k)
		h:SetPoint("BOTTOMRIGHT", b.rect, "BOTTOMRIGHT", (p.w - open[3]) * k, -(p.h - open[4]) * k)
	else
		local o = (st.rail or 0) * k
		h:SetPoint("TOPLEFT", b.rect, "TOPLEFT", -o, o)
		h:SetPoint("BOTTOMRIGHT", b.rect, "BOTTOMRIGHT", o, -o)
	end
end

-- a weight within the style's range (its smallest and largest)
local WEIGHT_RANK = { light = 1, medium = 2, heavy = 3 }
local WEIGHT_OF = { "light", "medium", "heavy" }
local function WeightFor(st, id)
	local n = WEIGHT_RANK[id] or 1
	local lo, hi = WEIGHT_RANK[st.minWeight or "light"], WEIGHT_RANK[st.maxWeight or "heavy"]
	return WEIGHT_OF[math.max(lo, math.min(hi, n))]
end

-- (stage 3: the action bars' backdrops, ActionBarPanel's DrawLibrary) the
-- weight style `styleId` is drawn at when `id` is asked
function Kit:BorderWeightOf(styleId, id)
	local st = self.BorderStyles[styleId]
	return st and WeightFor(st, id) or id
end

function Border:Lay(styleId, weightId, gem)
	local st = Kit.BorderStyles[styleId]
	if st then
		weightId = WeightFor(st, weightId or "light")
	end
	local wt = Kit.BorderWeights[weightId or "light"]
	if not (st and wt) then
		self:SetShown(false)
		return false
	end
	-- the corner piece: the style's own stud, or the Backdrop's gem in its colour
	gem = st.stud or (st.gems and ("borders/gem_" .. (gem or Kit:BorderGem()))) or nil
	if self.styleId == styleId and self.weightId == weightId and self.gem == gem then
		self:SetShown(true)
		return true
	end
	self.styleId, self.weightId, self.gem = styleId, weightId, gem
	local k = wt.band / st.rail
	self.k = k
	if self.place == "round" then
		PlaceRound(self, st, k)
	end
	if st.master then
		if self.nine then
			self.nine:Hide()
		end
		if not self.parts then
			self.parts = NewParts(self:Host(), self.layer, self.sub)
		end
		Kit:CutNine(self:At(), self.parts, st.master, k, st.corner, false)
		if self.glow then
			Kit:CutNine(self:At(), self.glow, st.master, k, st.corner, false)
		end
		ShadeParts(self, st)
		self:LayGems(st, wt, gem, k)
		if self.glowNine then
			self.glowNine:Hide()
		end
	else
		ShowParts(self.parts, false)
		ShowParts(self.glow, false)
		self:LayGems(nil)
		-- a rail family: its nine-slice at k (made again only for another
		-- scale; its glow with it)
		if self.nine and self.nine.kitScale ~= k then
			self.nine:Hide()
			self.nine = nil
			if self.glowNine then
				self.glowNine:Hide()
				self.glowNine = nil
			end
		end
		if not self.nine then
			self.nine = NineFor(self, st.prefix, k, self.sub)
			-- (a frameless border's rails take no shade: none asks for one)
			local el = not Frameless(self) and ShadeOf(self)
			if el then
				el:Add(self.nine)
			end
		end
	end
	self.lit = nil   -- (the states laid again on the new parts)
	self:SetShown(true)
	self:SetLit(self.hover, self.pressed, self.disabled)
	return true
end

-- the Backdrop's gems: centred on the rails' crossing at each corner
function Border:LayGems(st, wt, gem, k)
	local gems = self.gems
	if not (st and gem) then
		if gems then
			for _, c in ipairs(GEM_CORNERS) do
				gems[c]:Hide()
			end
		end
		return
	end
	if not gems then
		gems = {}
		local host = self:Host()
		for _, c in ipairs(GEM_CORNERS) do
			gems[c] = host:CreateTexture(nil, self.layer, nil, math.min(self.sub + 1, 7))
		end
		self.gems = gems
		self.gemsUnshaded = true
	end
	local p = Kit:Piece(st.master)
	local open = p and p.open
	local side, top = (open and open[1] or st.rail) * k / 2, (open and open[2] or st.rail) * k / 2
	local at = self:At()
	-- a stud: its own proportions at the weight's size, its centre off the
	-- crossing by its share, mirrored for each corner (cut at the top left)
	local gp = Kit:Piece(gem)
	local w, h, ox, oy = wt.gem, wt.gem, 0, 0
	if st.stud and gp then
		local m = math.max(gp.w, gp.h)
		w, h = wt.gem * gp.w / m, wt.gem * gp.h / m
		ox, oy = st.studOff[1] * wt.gem, st.studOff[2] * wt.gem
	end
	for _, c in ipairs(GEM_CORNERS) do
		local t = gems[c]
		if pieceNameOf[t] ~= gem then
			Kit:Apply(t, gem)
		end
		if st.stud and gp then
			local u0, u1, v0, v1 = gp.uv[1], gp.uv[2], gp.uv[3], gp.uv[4]
			if c == "tr" then
				t:SetTexCoord(u1, u0, v0, v1)
			elseif c == "bl" then
				t:SetTexCoord(u0, u1, v1, v0)
			elseif c == "br" then
				t:SetTexCoord(u1, u0, v1, v0)
			else
				t:SetTexCoord(u0, u1, v0, v1)
			end
		end
		t:SetSize(w, h)
		t:ClearAllPoints()
		local s = GEM_SIGN[c]
		t:SetPoint("CENTER", at, GEM_POINT[c], s[1] * (side + ox), s[2] * (top + oy))
	end
	-- (their partners once they have their piece: the UI shade round a gem)
	local el = self.gemsUnshaded and ShadeOf(self)
	if el then
		self.gemsUnshaded = nil
		for _, c in ipairs(GEM_CORNERS) do
			el:Add(gems[c])
		end
	end
end

-- its drawn textures (the master's parts and gems; a rail family's skin's art),
-- one list kept: for a tint over all of them (Kit:TintSkin's libraryArt)
function Border:Art()
	local list = self.art or {}
	self.art = list
	for i = #list, 1, -1 do
		list[i] = nil
	end
	local st = Kit.BorderStyles[self.styleId or ""]
	if st and st.master and self.parts then
		for _, key in ipairs(Kit.nineParts) do
			list[#list + 1] = self.parts[key]
		end
		if self.gem and self.gems then
			for _, c in ipairs(GEM_CORNERS) do
				list[#list + 1] = self.gems[c]
			end
		end
	elseif self.nine and self.nine.art then
		for _, tex in ipairs(self.nine.art) do
			list[#list + 1] = tex
		end
	end
	return list
end

-- its parts to another draw layer (a bar's bracket follows its fill's layer:
-- Kit.lua's Relayer); only a change is written
function Border:SetLayer(layer, sub)
	if self.layer == layer and self.sub == sub then
		return
	end
	self.layer, self.sub = layer, sub
	for _, set in ipairs({ self.parts, self.glow }) do
		for _, key in ipairs(Kit.nineParts) do
			if set and set[key] then
				set[key]:SetDrawLayer(layer, set == self.glow and math.min(sub + 1, 7) or sub)
			end
		end
	end
	if self.gems then
		for _, c in ipairs(GEM_CORNERS) do
			self.gems[c]:SetDrawLayer(layer, math.min(sub + 1, 7))
		end
	end
end

-- how far the opening lies in from the border's outer edge (UI units, left
-- and top): the master's opening at k, or a rail family's top rail
function Border:Inset()
	local st, k = Kit.BorderStyles[self.styleId or ""], self.k or 0
	if not st then
		return 0, 0
	end
	local p = Kit:Piece(st.master or ((st.prefix or "") .. "_t"))
	if st.master then
		local open = p and p.open
		return (open and open[1] or st.rail) * k, (open and open[2] or st.rail) * k
	end
	local d = (p and p.h or st.rail) * k
	return d, d
end

function Border:SetShown(on)
	on = on and true or false
	self.shown = on
	local st = Kit.BorderStyles[self.styleId or ""]
	if self.holder then
		self.holder:SetShown(on)
	end
	if st and st.master then
		ShowParts(self.parts, on)
		ShowParts(self.glow, on and self.lit == "hover")
		if self.gems then
			for _, c in ipairs(GEM_CORNERS) do
				self.gems[c]:SetShown(on and self.gem ~= nil)
			end
		end
	elseif self.nine then
		self.nine:SetShown(on)
		if self.glowNine then
			self.glowNine:SetShown(on and self.lit == "hover")
		end
	end
end

-- a texture darkened from its own colour (a rail family's pieces may carry
-- one: MelloUI.Kept.tintBaseOf)
local function Darken(tex, d)
	local base = tintBaseOf[tex]
	tex:SetVertexColor((base and base[1] or 1) * d, (base and base[2] or 1) * d, (base and base[3] or 1) * d)
end

-- a rail family's states (Single rail): its pieces darkened, and its glow --
-- a second nine of the family added as light in the palette's hover -- made
-- on the first hover
local function LitNine(b, st, state)
	local d = DARK[state] or 1
	for _, tex in ipairs(b.nine.art or {}) do
		Darken(tex, d)
	end
	if state == "hover" and not b.glowNine then
		b.glowNine = NineFor(b, st.prefix, b.k, math.min(b.sub + 1, 7))
		for _, tex in ipairs(b.glowNine.art or {}) do
			tex:SetBlendMode("ADD")
			W.Paint(tex, "hover", "vertex", GLOW_ALPHA)
		end
	end
	if b.glowNine then
		b.glowNine:SetShown(b.shown and state == "hover")
	end
end

-- a button's states: the shared glow under the mouse, a darken pressed or
-- disabled (only a change is written)
function Border:SetLit(hover, pressed, disabled)
	self.hover, self.pressed, self.disabled = hover, pressed, disabled
	local state = disabled and "disabled" or pressed and "pressed" or hover and "hover" or "normal"
	if state == self.lit then
		return
	end
	self.lit = state
	local st = Kit.BorderStyles[self.styleId or ""]
	if st and st.prefix and self.nine then
		LitNine(self, st, state)
		return
	end
	if not (st and st.master and self.parts) then
		return
	end
	local d = DARK[state] or 1
	for _, key in ipairs(Kit.nineParts) do
		self.parts[key]:SetVertexColor(d, d, d)
	end
	if state == "hover" and not self.glow then
		self.glow = NewParts(self:Host(), self.layer, math.min(self.sub + 1, 7))
		for _, key in ipairs(Kit.nineParts) do
			self.glow[key]:SetBlendMode("ADD")
			W.Paint(self.glow[key], "hover", "vertex", GLOW_ALPHA)
		end
		Kit:CutNine(self:At(), self.glow, st.master, self.k, st.corner, false)
	end
	ShowParts(self.glow, self.shown and state == "hover")
end

--------------------------------------------------------------------------------
-- The configurator's picture of a library style (Kit:ChoicePicture's "rim":
-- KitWindow.lua asks here for a choice with a `style`): the style round the
-- sample icon on the stone, at the light weight, as on a button
--------------------------------------------------------------------------------
local pictures = setmetatable({}, { __mode = "k" })   -- [tile] = its border
function Kit:BorderPicture(tile, choice, icon)
	local b = pictures[tile]
	if not b then
		b = self:NewBorder({ rect = tile.pic, place = "on", layer = "ARTWORK", sub = 3, level = 2 })
		pictures[tile] = b
	end
	local x, y = 0, 0
	if b:Lay(choice.style, "light") then
		x, y = b:Inset()
	end
	if icon then
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", tile.pic, "TOPLEFT", x, -y)
		icon:SetPoint("BOTTOMRIGHT", tile.pic, "BOTTOMRIGHT", -x, y)
	end
end
-- a picture tile showing no library style (another kind's choice drawn on it)
function Kit:BorderPictureOff(tile)
	local b = pictures[tile]
	if b then
		b:SetShown(false)
	end
end

--------------------------------------------------------------------------------
-- Button Border's library styles (Single rail, Backdrop): on a skinned button
-- (its slot rim, rep.object), the library's border laid on the rim's own rect,
-- in its layer, shown and hidden with it, and the rim put out (alpha 0: its
-- states are still read by Kit.lua's Slot_Update, which hands them to the
-- border, rim.libraryBorder). The five thin rims keep their own art and
-- baked states (stage 5 of the plan moves them). Geometry on a protected
-- button waits for the fight's end.
--------------------------------------------------------------------------------
local Secret = MelloUI.Safe.IsSecret
local Perf = MelloUI.Perf:Scope("KitBorders")
local buttonBorders = setmetatable({}, { __mode = "k" })   -- [rim] = its border
local Rim_Follow = Perf.Shared("Show / Hide on a rim a library border stands in for", function(rim)
	local b = buttonBorders[rim]
	if b and rim.libraryBorder == b then
		b:SetShown(rim:IsShown())
	end
end)

local function LibraryOnly(self, style)
	return self.BorderStyles[style] ~= nil and self.buttonLooks.rimKind[style] == nil
end

function Kit:ButtonLibraryBorder(button, style)
	local rep = button and repOf[button]
	local rim = type(rep) == "table" and rep.object
	if type(rim) ~= "table" or not rim.base then
		return false   -- (no slot rim: nothing of the library's to lay)
	end
	local b = buttonBorders[rim]
	if not LibraryOnly(self, style) then
		if b and rim.libraryBorder then
			rim.libraryBorder = nil
			b:SetShown(false)
			rim:SetAlpha(1)
		end
		return false
	end
	if InCombatLockdown() then
		self:WhenOutOfCombat(function()
			self:SetButtonBorder(button, self:BorderValue("button"))
		end, "Button Border")
		return true
	end
	if not b then
		local layer, sub = "OVERLAY", 3
		local ok, l, s = pcall(rim.GetDrawLayer, rim)
		if ok and not Secret(l) and type(l) == "string" then
			layer, sub = l, (not Secret(s) and tonumber(s)) or 0
		end
		b = self:NewBorder({ rect = rim, owner = rim:GetParent(), place = "on", layer = layer, sub = sub })
		buttonBorders[rim] = b
		Perf.hooksecurefunc(rim, "Show", Rim_Follow)
		Perf.hooksecurefunc(rim, "Hide", Rim_Follow)
		Perf.hooksecurefunc(rim, "SetShown", Rim_Follow)
	end
	rim.libraryBorder = b
	rim:SetAlpha(0)
	b:Lay(style, "light")
	b:SetShown(rim:IsShown())
	return true
end

--------------------------------------------------------------------------------
-- Raid Frame Border (0.19.8, NEW: the library's first own row): the border on
-- each compact raid / party frame. The Single rail is today's F1 itself (Raid
-- Frames Kit's rail, kept as it is); another style lays the library's border
-- on the frame's rect as regions of the frame (the rails' layer as F1's: over
-- the fills, under the icons and the name) and puts F1's rails out (its stone
-- stays). Modules/RaidFramePanel.lua registers each frame it dresses.
--------------------------------------------------------------------------------
Kit:AddBorderKind({ kind = "raid", key = "raidFrameBorder", default = "single",
	name = "Raid Frame Border", values = Kit.squareLooks, preview = "rim",
	desc = "The border on each raid frame and raid-style party frame: the Single rail they wear today, one of the thin rims the buttons wear, or the Backdrop, its corner gems in the colour of the action bars' Backdrop." }, "aura")

Kit.raidBorders = setmetatable({}, { __mode = "k" })   -- [compact frame] = { border = , rails = F1's skin }

-- F1's rails (its skin's textures but its stone and dim fill) shown or put out
local function RailsAlpha(skin, a)
	if not (skin and skin.all) then
		return
	end
	for _, tex in ipairs(skin.all) do
		if tex ~= skin.body and tex ~= skin.dimFill then
			tex:SetAlpha(a)
		end
	end
end

-- Stage 3 (0.19.8, the plan's decision 7): where the border goes, UI
-- Modifications' Raid Border Placement -- "frame" on each frame, "group"
-- round each raid group (the game's group border, `borderFrame`, shown by
-- Edit Mode's Display Border: G1 the Single rail on it today), "both" (as
-- today, the default)
local function RaidPlace()
	local um = MelloUI:GetModule("UIModifications")
	local v = um and um.db and um.db.raidBorderPlace
	if v == "frame" or v == "group" then
		return v
	end
	return "both"
end

function Kit:RaidBorder(frame, skin)
	local e = self.raidBorders[frame]
	if not e then
		e = { skin = skin, on = true }
		self.raidBorders[frame] = e
	end
	local value = self:BorderValue("raid")
	local frameOn = e.on and RaidPlace() ~= "group"
	if not frameOn or value == "single" or not self.BorderStyles[value] then
		-- F1 as it is (its Single rail; the skin off: back as the game had
		-- it), or put out for "Round the group" (its stone kept)
		RailsAlpha(skin, (e.on and not frameOn) and 0 or 1)
		if skin then
			skin.libraryArt = nil
		end
		if e.border then
			e.border:SetShown(false)
		end
		return
	end
	if not e.border then
		e.border = self:NewBorder({ rect = frame, owner = frame, place = "on", layer = "ARTWORK", sub = -1 })
	end
	if e.border:Lay(value, "light") then
		RailsAlpha(skin, 0)
		-- (Healer Frames' debuff colour on the rails reaches these instead: Kit:TintSkin)
		if skin then
			skin.libraryArt = e.border:Art()
		end
	end
end

-- (0.20.0) How far a raid frame's border reaches into it, x and y in UI
-- units: the library style's opening, else the Single rail's inner edge at
-- the raid frames' weight (Kit.Replacements' "raidframe-hp-bg-white" scale);
-- 0, 0 while the kit draws none round it. MelloUI's own Group Frames lay
-- their bars inside it (the user, 2026-10-09: "the power bar however should
-- be inside of the borders, and fitting the width of the hp bar").
function Kit:RaidFrameInset(frame)
	local e = self.raidBorders[frame]
	if not (e and e.on) or RaidPlace() == "group" then
		return 0, 0
	end
	if e.border and e.border.shown then
		return e.border:Inset()
	end
	local rule = self.Replacements["raidframe-hp-bg-white"]
	local sc = (self.scale or 1) * (rule and rule.scale or 0.8)
	local l, t = self:Piece(self.framePrefix .. "_l"), self:Piece(self.framePrefix .. "_t")
	return (l and l.box) and l.box[3] * sc or 0, (t and t.box) and t.box[4] * sc or 0
end

-- A raid group's border (G1's frame: `holder`, the Single rail at 1.6 on
-- the game's borderFrame, Raid Frames Kit's SkinGroup): the style round the
-- group at the medium weight (a raid group's outline, the weights' table),
-- on a holder of the borderFrame's own, so it shows and hides with the game's
-- group border; G1 faded out under it. "On each frame": no group border
Kit.raidGroups = setmetatable({}, { __mode = "k" })   -- [borderFrame] = { holder = G1's frame, border = }

function Kit:RaidGroupBorder(border, holder)
	local e = self.raidGroups[border]
	if not e then
		e = { holder = holder, on = true }
		self.raidGroups[border] = e
	end
	local value = self:BorderValue("raid")
	local groupOn = e.on and RaidPlace() ~= "frame"
	if not groupOn or value == "single" or not self.BorderStyles[value] then
		if e.holder then
			e.holder:SetAlpha((e.on and not groupOn) and 0 or 1)
		end
		if e.border then
			e.border:SetShown(false)
		end
		return
	end
	if not e.border then
		e.border = self:NewBorder({ rect = border, place = "on", level = 1 })
	end
	if e.border:Lay(value, "medium") and e.holder then
		e.holder:SetAlpha(0)
	end
end

-- Raid Frames Kit on or off: every registered frame's and group's border
-- shown with it
function Kit:RaidBordersShown(on)
	for _, e in pairs(self.raidBorders) do
		e.on = on and true or false
		if not on then
			RailsAlpha(e.skin, 1)
			if e.border then
				e.border:SetShown(false)
			end
		end
	end
	for _, e in pairs(self.raidGroups) do
		e.on = on and true or false
		if not on then
			if e.holder then
				e.holder:SetAlpha(1)
			end
			if e.border then
				e.border:SetShown(false)
			end
		end
	end
	if on then
		self:ApplyRaidBorders()
	end
end

-- every frame and group of the kind again (Kit:ApplyBorder("raid"), Raid
-- Border Placement): a compact frame is protected, so its regions are laid
-- out of combat (at the fight's end)
local function ApplyRaid()
	for frame, e in pairs(Kit.raidBorders) do
		Kit:RaidBorder(frame, e.skin)
	end
	for border, e in pairs(Kit.raidGroups) do
		Kit:RaidGroupBorder(border, e.holder)
	end
	-- (0.20.0) the frames' insides changed with their border: Group Frames lays
	-- its bars again (Kit:RaidFrameInset)
	MelloUI:Fire("raidborder")
end
function Kit:ApplyRaidBorders()
	self:WhenOutOfCombat(ApplyRaid, "Raid Frame Border")
end

--------------------------------------------------------------------------------
-- Stage 2 (0.19.8, the bar shape): the bars' rows take the library's styles
-- too. A bar's bracket (Kit.lua's "bar" replacement: a strip of caps and a
-- middle, the thin looks baked as bars/<look>_*) stays for its own looks; a
-- library style (Single rail, Backdrop) puts the strip out (alpha 0, so it
-- keeps following the bar's show / hide) and lays the library's border ROUND
-- the bar at the light weight, as regions of the bar in the bracket's layer:
-- no arm takes the bar's width (rep:GetArms 0, the cast bar is not
-- narrowed), the fill has the whole rect (rep:GetOpening). The rows:
--   Progress Bar Border   every window's progress bar (no longer the unit
--                         frames': rule 9)
--   Unit Frame Border     (NEW) the unit frames' bars; a Progress Bar Border
--                         chosen before is its start (Core's MergeSettings)
--   Nameplate Border      the nameplates' health bar
--   Cast Bar Border       (NEW) the cast bar: every bar look but Ornate,
--                         today's Cast bar first
--   Personal Resource     (NEW) one frame round the personal resource
--   Border                display's bars: None (today), the thin rims or the
--                         Backdrop (the decision: the others crowd its gap)
--------------------------------------------------------------------------------
local function CastLooks()
	local out = {}
	for _, v in ipairs(Kit.buttonLooks.barBorders) do
		if v.value ~= "frame" then
			out[#out + 1] = v
		end
	end
	return out
end

Kit:AddBorderKind({ kind = "unitframe", key = "unitFrameBorder", default = "frame", name = "Unit Frame Border",
	values = Kit.buttonLooks.barBorders, preview = "bar",
	desc = "The frame round the unit frames' health and power bars (player, target, focus, pet, party): the Ornate bracket they wear by default, the cast bar's, a thin rim, the Single rail or the Backdrop." }, "bar")
Kit:AddBorderKind({ kind = "castbar", key = "castBarBorder", default = "castbar", name = "Cast Bar Border",
	values = CastLooks(), preview = "bar",
	desc = "The frame round your cast bar: the Cast bar bracket with its gem clusters (today's), a thin rim, the Single rail or the Backdrop. A frame laid round the bar leaves it its whole width." }, "nameplate")

local PERSONAL_LOOKS = { { value = "none", label = "None" } }
for _, v in ipairs(Kit.squareLooks) do
	if v.value ~= "single" and v.value ~= "n1" then
		PERSONAL_LOOKS[#PERSONAL_LOOKS + 1] = v
	end
end
Kit.personalLooks = PERSONAL_LOOKS
Kit:AddBorderKind({ kind = "personal", key = "personalBorder", default = "none", name = "Personal Resource Border",
	values = PERSONAL_LOOKS, preview = "rim",
	desc = "One frame round the health and power bars of your personal resource display (the bars under your character): none, a thin rim or the Backdrop." }, "castbar")

-- a bar's bracket in a library style, or put back (rep: Kit.lua's bar
-- replacement; true when the library took it)
function Kit:BarLibraryBorder(rep, style)
	local strip = rep and rep.strip
	if not (strip and strip.capL and strip.mid and strip.capR) then
		return false
	end
	if not LibraryOnly(self, style) then
		if rep.libraryStyle then
			rep.libraryStyle = nil
			rep.libraryBorder:SetShown(false)
			strip.capL:SetAlpha(1)
			strip.mid:SetAlpha(1)
			strip.capR:SetAlpha(1)
			rep:Refit()
		end
		return false
	end
	if InCombatLockdown() then
		self:WhenOutOfCombat(function()
			rep:SetBar(style)
		end, "a bar's border")
		return true
	end
	if not rep.libraryBorder then
		local layer, sub = "BORDER", 1
		local ok, l, s = pcall(strip.capL.GetDrawLayer, strip.capL)
		if ok and not Secret(l) and type(l) == "string" then
			layer, sub = l, (not Secret(s) and tonumber(s)) or 0
		end
		rep.libraryBorder = self:NewBorder({ rect = rep.rect, owner = rep.barParent, place = "round", layer = layer, sub = sub })
	end
	rep.libraryStyle = style
	strip.capL:SetAlpha(0)
	strip.mid:SetAlpha(0)
	strip.capR:SetAlpha(0)
	rep.libraryBorder:Lay(style, "light")
	rep.libraryBorder:SetShown(strip:IsShown())
	rep:Refit()
	return true
end

-- The personal resource display's frame: shown while Unit Frames Kit dresses
-- the unit frames (the display is the Unit Frames page's Personal pick; its
-- Activate / Deactivate: Kit:PersonalBordersShown) and a style is chosen;
-- made on the display's first show (never at login, and no listener of its
-- own: the skin's switch is the one), round its health bars and power bar
local personal = { hooked = false, seen = false, on = false }

local function PersonalLay()
	local prd = rawget(_G, "PersonalResourceDisplayFrame")
	if not (prd and personal.seen) then
		return
	end
	local value = Kit:BorderValue("personal")
	local on = personal.on and value ~= "none" and Kit.BorderStyles[value] ~= nil
	if not on then
		if personal.border then
			personal.border:SetShown(false)
		end
		return
	end
	local top = prd.HealthBarsContainer
	local bottom = prd.PowerBar or top
	if not (top and bottom) then
		return
	end
	if not personal.anchor then
		local a = CreateFrame("Frame", nil, prd)
		a:EnableMouse(false)
		personal.anchor = a
		-- (no piece of the game's under it to keep a shade: the UI shade's unit
		-- frames area round its own outline)
		personal.border = Kit:NewBorder({ rect = a, place = "round", layer = "OVERLAY", sub = 3, level = 2,
			shade = { root = prd, area = "unitframes" } })
	end
	personal.anchor:ClearAllPoints()
	personal.anchor:SetPoint("TOPLEFT", top, "TOPLEFT")
	personal.anchor:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT")
	personal.border:Lay(value, "light")
	personal.border:SetShown(true)
end

local Personal_OnShow = Perf.Shared("OnShow on the personal resource display", function()
	if not personal.seen then
		personal.seen = true
		PersonalLay()
	end
end, "script")

local function PersonalHook()
	local prd = rawget(_G, "PersonalResourceDisplayFrame")
	if personal.hooked or not (prd and prd.HookScript) then
		return
	end
	personal.hooked = true
	Perf.HookScript(prd, "OnShow", Personal_OnShow)
	if prd:IsShown() then
		Personal_OnShow()
	end
end

function Kit:ApplyPersonalBorder()
	if personal.on then
		PersonalHook()
	end
	if personal.seen then
		self:WhenOutOfCombat(PersonalLay, "Personal Resource Border")
	end
end

-- Unit Frames Kit on or off: the display hooked (nothing made: its frame on
-- the first show), the frame shown or put away with the skin
function Kit:PersonalBordersShown(on)
	personal.on = on and true or false
	if personal.on then
		PersonalHook()
	end
	if personal.seen then
		self:WhenOutOfCombat(PersonalLay, "Personal Resource Border")
	end
end

-- the configurator's picture of a library style on a bar row: a sample fill
-- (the palette's gold, as the bar pictures') with the style round it
local barPictures = setmetatable({}, { __mode = "k" })
function Kit:BorderBarPicture(tile, choice, fill, size)
	local b = barPictures[tile]
	if not b then
		b = { anchor = tile.pic:CreateTexture(nil, "BACKGROUND") }
		b.border = self:NewBorder({ rect = b.anchor, owner = tile.pic, place = "round", layer = "ARTWORK", sub = 3 })
		barPictures[tile] = b
	end
	b.anchor:ClearAllPoints()
	b.anchor:SetPoint("LEFT", tile.pic, "LEFT", 6, 0)
	b.anchor:SetPoint("RIGHT", tile.pic, "RIGHT", -6, 0)
	b.anchor:SetHeight(size * 0.22)
	if fill then
		fill:ClearAllPoints()
		fill:SetPoint("TOPLEFT", b.anchor, "TOPLEFT")
		fill:SetPoint("BOTTOMLEFT", b.anchor, "BOTTOMLEFT")
		fill:SetWidth((size - 12) * 0.66)
	end
	b.border:Lay(choice.style, "light")
end
function Kit:BorderBarPictureOff(tile)
	local b = barPictures[tile]
	if b then
		b.border:SetShown(false)
	end
end

--------------------------------------------------------------------------------
-- The rings (0.19.8, the border library's stage 4; the user, 2026-10-06: "Do
-- them now", the NewUI2 rings of decision 10): R1 four diamond studs and R3
-- the plain heavy ring (rings/r1, rings/r3, Tools/make_newui2_borders.py),
-- one normal piece each, their states the library's (the shared glow under
-- the mouse: the ring added again as light in the palette's hover; a darken
-- pressed or disabled; checked: the Active look, Kit:SetActive's round one).
--   Round Border: a round rim (Kit:Slot "roundslot") in a ring style is put
--     out (alpha 0: its states are still read by Kit.lua's Slot_Update, which
--     hands them to rim.libraryBorder) and the ring stands on the rim's own
--     rect, in its layer, shown and hidden with it (its opening a little wider
--     than the gem ring's, as the thin rings' are).
--   Portrait Ring (decision 8: a row of its own, the gem ring by default):
--     the unit frames' portrait ring in a ring style, its opening on the
--     portrait as the gem ring's; its elite / rare / boss twins are the ring
--     in the marks' metals (Tools/kit_marks.py marks/<ring>_<kind>,
--     Modules/KitMarks.lua). Modules/UnitFramePanel.lua registers each ring.
--   (0.19.9, the user's pick 4c 2026-10-08) R5, the NewUI2 winged border
--     (rings/r5, Tools/make_newui2_glyphs.py): a Portrait Ring choice only
--     (`portraitOnly`: its wings would reach past a round button), and the
--     windows' corner ring (Kit.lua's UI-Frame-PortraitMetal-CornerTopLeft).
--------------------------------------------------------------------------------
Kit.RingStyles = {
	r1 = { label = "Four diamond studs", piece = "rings/r1" },
	r3 = { label = "Plain heavy ring", piece = "rings/r3" },
	r5 = { label = "Winged border", piece = "rings/r5", portraitOnly = true },
}
Kit.RingStyleOrder = { "r1", "r3", "r5" }
for _, id in ipairs(Kit.RingStyleOrder) do
	local st = Kit.RingStyles[id]
	if not st.portraitOnly then
		Kit.roundLooks[#Kit.roundLooks + 1] = { value = id, label = st.label, piece = st.piece }
	end
end

local Ring = {}
Ring.__index = Ring

function Ring:SetShown(on)
	self.shown = on and true or false
	self.tex:SetShown(self.shown)
	if self.glow then
		self.glow:SetShown(self.shown and self.lit == "hover")
	end
end

function Ring:SetLit(hover, pressed, disabled)
	local state = disabled and "disabled" or pressed and "pressed" or hover and "hover" or "normal"
	if state == self.lit then
		return
	end
	self.lit = state
	local d = DARK[state] or 1
	self.tex:SetVertexColor(d, d, d)
	if state == "hover" and not self.glow then
		local layer, sub = self.tex:GetDrawLayer()
		self.glow = self.tex:GetParent():CreateTexture(nil, layer, nil, math.min((sub or 0) + 1, 7))
		self.glow:SetAllPoints(self.tex)
		Kit:Apply(self.glow, self.piece)
		self.glow:SetBlendMode("ADD")
		W.Paint(self.glow, "hover", "vertex", GLOW_ALPHA)
	end
	if self.glow then
		if pieceNameOf[self.glow] ~= self.piece then
			Kit:Apply(self.glow, self.piece)
		end
		self.glow:SetShown(self.shown and state == "hover")
	end
end

local ringRims = setmetatable({}, { __mode = "k" })   -- [rim] = its ring
local RingRim_Follow = Perf.Shared("Show / Hide on a round rim a ring stands in for", function(rim)
	local r = ringRims[rim]
	if r and rim.libraryBorder == r then
		r:SetShown(rim:IsShown())
	end
end)

-- Round Border's choice on one round rim: a ring style (true), or none (the
-- rim back as itself: false, Kit.lua's RoundLook lays the baked look)
function Kit:RoundLibraryRing(rim, value)
	local st = value and self.RingStyles[value]
	local r = ringRims[rim]
	if not st then
		if r and rim.libraryBorder == r then
			rim.libraryBorder = nil
			r:SetShown(false)
			rim:SetAlpha(1)
		end
		return false
	end
	if not r then
		local layer, sub = "OVERLAY", 3
		local ok, l, s = pcall(rim.GetDrawLayer, rim)
		if ok and not Secret(l) and type(l) == "string" then
			layer, sub = l, (not Secret(s) and tonumber(s)) or 0
		end
		local host = rim.owner or rim:GetParent()
		r = setmetatable({ rim = rim, tex = host:CreateTexture(nil, layer, nil, sub) }, Ring)
		r.tex:SetAllPoints(rim)
		ringRims[rim] = r
		Perf.hooksecurefunc(rim, "Show", RingRim_Follow)
		Perf.hooksecurefunc(rim, "Hide", RingRim_Follow)
		Perf.hooksecurefunc(rim, "SetShown", RingRim_Follow)
	end
	if r.piece ~= st.piece then
		r.piece = st.piece
		self:Apply(r.tex, st.piece)
		r.lit = nil
	end
	rim.libraryBorder = r
	rim:SetAlpha(0)
	-- (the rim's own glow, a lit card's, shows the ring as light too)
	if rim.glow and pieceNameOf[rim.glow] ~= st.piece then
		self:Apply(rim.glow, st.piece)
	end
	r:SetShown(rim:IsShown())
	r:SetLit(rim.hover, rim.pressed, rim.lastDisabled)
	return true
end

-- The Portrait Ring's row: the gem ring, or a ring style (after Round Border)
Kit.portraitLooks = { { value = "gem", label = "Gem ring", piece = "window/portrait_ring" } }
for _, id in ipairs(Kit.RingStyleOrder) do
	local st = Kit.RingStyles[id]
	Kit.portraitLooks[#Kit.portraitLooks + 1] = { value = id, label = st.label, piece = st.piece }
end
Kit:AddBorderKind({ kind = "portrait", key = "portraitRing", default = "gem", name = "Portrait Ring",
	values = Kit.portraitLooks, preview = "rim",
	desc = "The ring round the portraits of the unit frames: the player, target, focus, pet, target of target and "
		.. "party. The gem ring, a ring with four diamond studs, a plain heavy ring, or the winged border the windows "
		.. "wear. An elite, rare or boss shows the ring in its metal with its crest (Elite and Rare Marks)." }, "round")

-- the portrait ring's piece now (the gem ring's elsewhere: windows keep theirs)
function Kit:PortraitRingPiece()
	local st = self.RingStyles[self:BorderValue("portrait") or ""]
	return st and st.piece or "window/portrait_ring"
end

-- [rep] = its frame's change (a function: the portrait fitted again, the
-- marks, the bars' tuck, the cover), for every unit frame ring
Kit.portraitRings = setmetatable({}, { __mode = "k" })

-- One ring in the chosen piece: the texture re-pieced and re-sized by its
-- opening (rep.Resquare, Kit.lua's texture replacement) and its frame told;
-- a region of a protected frame, laid out of combat. True when it changed.
function Kit:LayPortraitRing(rep)
	local piece = self:PortraitRingPiece()
	local was = rep.ringPiece or (rep.rule and rep.rule.piece)
	if was == piece or not rep.tex then
		rep.ringPiece = piece
		return false
	end
	if InCombatLockdown() then
		self:WhenOutOfCombat(function() self:ApplyPortraitRings() end, "Portrait Ring")
		return false
	end
	rep.ringPiece = piece
	self:Apply(rep.tex, piece)
	if rep.Resquare then
		rep.Resquare(was)
	end
	local changed = self.portraitRings[rep]
	if type(changed) == "function" then
		pcall(changed, rep)
	end
	return true
end

function Kit:PortraitRing(rep, changed)
	if type(rep) ~= "table" then
		return
	end
	self.portraitRings[rep] = changed or true
	self:LayPortraitRing(rep)
end

function Kit:ApplyPortraitRings()
	for rep in pairs(self.portraitRings) do
		self:LayPortraitRing(rep)
	end
end

--------------------------------------------------------------------------------
-- Cooldown Manager Border (0.19.8; the addon study's item 7, "all as
-- recommended"): the icons of the game's Cooldown Manager -- the game's own
-- bevel (its IconOverlay), or a library style laid on the icon at the light
-- weight, the bevel put out (alpha 0). Modules/CooldownTweaks.lua registers
-- each icon as the game lays it out (Kit:CooldownIconBorder) and puts the
-- bevels back when it is switched off (Kit:CooldownBordersOff).
--------------------------------------------------------------------------------
Kit.cooldownLooks = { { value = "game", label = "The game's bevel" } }
for _, look in ipairs(Kit.squareLooks) do
	Kit.cooldownLooks[#Kit.cooldownLooks + 1] = look
end
Kit:AddBorderKind({ kind = "cooldown", key = "cooldownBorder", default = "game", name = "Cooldown Manager Border",
	values = Kit.cooldownLooks, preview = "rim",
	desc = "The rim round the icons of the game's Cooldown Manager: the game's own bevel, or one of the border styles "
		.. "the buttons wear." }, "raid")

Kit.cooldownIcons = setmetatable({}, { __mode = "k" })   -- [item] = { icon = texture, overlays = { bevel ... }, border }

function Kit:CooldownIconBorder(item, icon, overlays)
	local e = self.cooldownIcons[item]
	if not e then
		if not icon then
			return
		end
		e = { icon = icon, overlays = overlays or {} }
		self.cooldownIcons[item] = e
	end
	-- (a style of the painted kit's: with the reskin on, as every Look > Borders row; else the game's bevel)
	local um = MelloUI:GetModule("UIModifications")
	local value = (um and um.db and um.db.reskin ~= false) and self:BorderValue("cooldown") or "game"
	local st = value ~= "game" and self.BorderStyles[value] or nil
	for _, r in ipairs(e.overlays) do
		local want = st and 0 or 1
		if r:GetAlpha() ~= want then
			r:SetAlpha(want)
		end
	end
	if not st then
		if e.border then
			e.border:SetShown(false)
		end
		return
	end
	if not e.border then
		e.border = self:NewBorder({ rect = e.icon, owner = item, place = "on", layer = "OVERLAY", sub = 2 })
	end
	e.border:Lay(value, "light")
end

function Kit:ApplyCooldownBorders()
	for item in pairs(self.cooldownIcons) do
		self:CooldownIconBorder(item)
	end
end

-- the game's bevels back on every icon, the styles put away (the module off)
function Kit:CooldownBordersOff()
	for _, e in pairs(self.cooldownIcons) do
		for _, r in ipairs(e.overlays) do
			r:SetAlpha(1)
		end
		if e.border then
			e.border:SetShown(false)
		end
	end
end

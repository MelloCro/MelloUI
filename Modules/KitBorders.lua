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
--
-- (onelook D12) The core keeps the library itself -- the styles and weights,
-- Kit:NewBorder and its Border (W.Field, Auras, the Personal Display and the
-- minimap wear it), Kit.BorderBandRail and Kit:TuckTrough -- and the Cooldown
-- Manager Border (its kind `core = true`: UI Modifications' core settings
-- make its row). The painted reskin's borders are their own file (one look
-- stage I: MelloUI_Oldschool/Modules/KitBordersPainted.lua, the two OLDSCHOOL blocks that were
-- here; public tables only, two constants on Kit.__): (A) the configurator's pictures, the
-- Button Border library, Raid Frame Border and the bar library (Unit Frame,
-- Cast Bar, Personal Display, Swing Timer); (B) the bars' fit, the personal
-- resource display's frame, the bar pictures, the rings and the Portrait
-- Ring / Level Orb. Their kinds register where they stand, so
-- Kit.borderKinds keeps its order.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Kit = MelloUI.Kit
-- what the kit keeps beside the game's frames (Kit.lua: weak-keyed, never keys on them)
local pieceNameOf = MelloUI.Kept.pieceNameOf
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
	-- (0.20.1, the user: the RPG pack's frames "reusable as backdrop border, action bar border, progress bar border etc
	-- with its background" -- Tools/make_rpg_frames.py): the health bar's stone rail, two lit groove lines, rounded
	-- outer corners; `bg` its trough, a master cut at `bgCorner` and drawn whole under the element's content
	-- (Border:LayBackground)
	rpg = { label = "Stone rail", master = "borders/rpg", corner = 40, rail = 30, bg = "borders/rpg_bg", bgCorner = 22 },
}
Kit.BorderStyleOrder = { "thin", "hairline", "rounded", "gold", "sunk", "single", "backdrop", "n4", "n4g", "n5", "n1", "rpg" }
-- (UI units: band = the reference rail's on-screen depth, gem = a gem's side)
Kit.BorderWeights = {
	light = { band = 4.9, gem = 8.2 },
	medium = { band = 7.3, gem = 11.8 },
	heavy = { band = 10.9, gem = 15.5 },
}
-- a darken as the engine's vertex colour (a brightness, every channel alike)
local DARK = { pressed = 0.72, disabled = 0.55 }
local GLOW_ALPHA = 0.6   -- the shared glow under the mouse: the rails added again as light
-- (the two for the painted reskin's borders, MelloUI_Oldschool/Modules/KitBordersPainted.lua)
Kit.__.BorderDark, Kit.__.BorderGlowAlpha = DARK, GLOW_ALPHA
-- ONELOOK HEADER END (the painted reskin's borders, MelloUI_Oldschool/Modules/KitBordersPainted.lua, use only public tables)

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
--     opts.bgLayer / opts.bgSub (0.20.1) a style's background's draw layer (BACKGROUND -7: under the content -- an
--                  action button's icon is BACKGROUND 0, a bar's fill ARTWORK)
--     opts.bgHost / opts.bgAt   the frame its background is regions of and the region it lies on (a bar: its own
--                  trough's, which sits under the fill wherever that fill is drawn -- on a lower strata too)
--     opts.noBg    no background (the minimap: its map is drawn by the frame itself, under every region of it)
--     opts.open    "l" / "r": that side left open, the top and bottom rails running to the rect's edge (a unit
--                  frame's bar butting into the portrait ring, the kit bracket's dropped cap)
function Kit:NewBorder(opts)
	return setmetatable({ rect = opts.rect, owner = opts.owner, layer = opts.layer or "OVERLAY", sub = opts.sub or 3,
		place = opts.place or "on", level = opts.level or 1, shown = false, shade = opts.shade,
		bgLayer = opts.bgLayer or "BACKGROUND", bgSub = opts.bgSub or -7, bgHost = opts.bgHost,
		bgAtRegion = opts.bgAt, noBg = opts.noBg, open = opts.open }, Border)
end

-- (0.20.1, the user: the Stone rail "a bit too big" on the Reputation and Skills bars and the nameplates) a border's
-- own fit: its band no deeper than `maxBand` UI units (a bar's: a share of its height), its art at `kScale` (a
-- panel's smaller bars: the bracket's artScale) -- laid again when either changes
function Border:SetFit(maxBand, kScale)
	if self.maxBand == maxBand and self.kScale == kScale then
		return
	end
	self.maxBand, self.kScale = maxBand, kScale
	if self.styleId then
		local s, w = self.styleId, self.weightId
		self.styleId = nil
		self:Lay(s, w)
	end
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
local RAIL_EDGES = { "t", "b", "l", "r" }

-- the set's eight laid for a rail family at k: their art, sizes and the edges' insets (the textures kept -- a
-- region can never be freed: 2026-10-12, the user's client stopped on an assert, "L->top < L->ci->top", a nameplate's
-- health bar carrying hundreds of rails, a new eight made for every height the plate was given, GetRegions past the
-- engine's stack)
function RailSet:Relay(prefix, k)
	self.kitScale, self.prefix = k, prefix
	local T = Kit:Size(prefix .. "_tl", k)
	for i, c in ipairs(GEM_CORNERS) do
		local tex = self.art[i]
		tex.kitScale = k
		Kit:Apply(tex, prefix .. "_" .. c)
		tex:SetSize(Kit:Size(prefix .. "_" .. c, k))
	end
	local at = self.at
	for i, e in ipairs(RAIL_EDGES) do
		local tex = self.tiled[i]
		tex.kitScale = k
		Kit:Apply(tex, prefix .. "_" .. e, true)
		tex:ClearAllPoints()
		if e == "t" or e == "b" then
			local side = e == "t" and "TOP" or "BOTTOM"
			tex:SetPoint(side .. "LEFT", at, side .. "LEFT", T, 0)
			tex:SetPoint(side .. "RIGHT", at, side .. "RIGHT", -T, 0)
			tex:SetHeight(T)
		else
			local side = e == "l" and "LEFT" or "RIGHT"
			tex:SetPoint("TOP" .. side, at, "TOP" .. side, 0, -T)
			tex:SetPoint("BOTTOM" .. side, at, "BOTTOM" .. side, 0, T)
			tex:SetWidth(T)
		end
		Kit:Retile(tex)
	end
end

local function RailNine(at, host, prefix, k, layer, sub)
	local set = setmetatable({ at = at, art = {}, all = {}, tiled = {} }, RailSet)
	for _, c in ipairs(GEM_CORNERS) do
		local tex = host:CreateTexture(nil, layer, nil, math.min(sub + 1, 7))
		tex:SetPoint(RAIL_CORNER_AT[c], at, RAIL_CORNER_AT[c])
		set.art[#set.art + 1] = tex
		set.all[#set.all + 1] = tex
	end
	for _ = 1, #RAIL_EDGES do
		local tex = host:CreateTexture(nil, layer, nil, sub)
		set.art[#set.art + 1] = tex
		set.all[#set.all + 1] = tex
		set.tiled[#set.tiled + 1] = tex
	end
	set:Relay(prefix, k)
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
	-- (0.20.1: an open side grows no rail past the rect)
	local gl, gr = b.open == "l" and 0 or 1, b.open == "r" and 0 or 1
	if open then
		h:SetPoint("TOPLEFT", b.rect, "TOPLEFT", -open[1] * k * gl, open[2] * k)
		h:SetPoint("BOTTOMRIGHT", b.rect, "BOTTOMRIGHT", (p.w - open[3]) * k * gr, -(p.h - open[4]) * k)
	else
		-- a rail family: grown by its own rails' depth at k (Border:Inset: its top piece), not the style's `rail` --
		-- the depth a weight's band maps to (0.20.5, the user: the Single rail "not properly attached to the
		-- progress bars": 16 against its 11 px rail stood it 5 px of art off every side)
		local o = b:Inset()
		h:SetPoint("TOPLEFT", b.rect, "TOPLEFT", -o * gl, o)
		h:SetPoint("BOTTOMRIGHT", b.rect, "BOTTOMRIGHT", o * gr, -o)
	end
end

-- (0.20.1) an open side: its corners and side rail put away, the top and bottom rails to that edge (after CutNine and
-- after every show of the parts)
local OPEN_PARTS = { l = { "tl", "bl", "l" }, r = { "tr", "br", "r" } }
local function OpenSide(b, relay)
	local s, parts = b.open, b.parts
	if not (s and parts and OPEN_PARTS[s]) then
		return
	end
	for _, key in ipairs(OPEN_PARTS[s]) do
		parts[key]:Hide()
	end
	if relay then
		local f, k = b:At(), b.k or 0
		local st = Kit.BorderStyles[b.styleId or ""]
		local cs = (st and st.corner or 0) * k
		if s == "l" then
			parts.t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
			parts.b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
		else
			parts.t:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, -cs)
			parts.b:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, cs)
		end
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
	local band = wt.band
	if self.maxBand and self.maxBand < band then
		band = self.maxBand
	end
	local k = band / st.rail * (self.kScale or 1)
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
		OpenSide(self, true)
		self:LayGems(st, wt, gem, k)
		self:LayBackground(st, k)
		if self.glowNine then
			self.glowNine:Hide()
		end
	else
		ShowParts(self.parts, false)
		ShowParts(self.glow, false)
		self:LayGems(nil)
		self:LayBackground(nil)
		-- a rail family: its nine-slice at k (made again only for another
		-- scale; its glow with it) -- a frameless one's eight laid again in place (RailSet:Relay: a bar's border is
		-- fitted to every height its bar is given, a nameplate's to each plate's)
		if self.nine and self.nine.Relay and (self.nine.kitScale ~= k or self.nine.prefix ~= st.prefix) then
			self.nine:Relay(st.prefix, k)
			if self.glowNine then
				self.glowNine:Relay(st.prefix, k)
			end
		elseif self.nine and self.nine.kitScale ~= k then
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

-- (0.20.1) A style's own background (`bg`, the stone rail's trough): its master cut at `bgCorner` and drawn whole --
-- the middle too -- in the opening, a little under the rails, as regions of the frame the element's content is drawn
-- on (on the rect: the owner, a button; round it: the rect's frame, a bar) at bgLayer / bgSub, under that content
function Border:LayBackground(st, k)
	local piece = not self.noBg and st and st.bg
	if not piece then
		if self.bgParts then
			ShowParts(self.bgParts, false)
			self.bgParts.m:Hide()
		end
		return
	end
	if not self.bgParts then
		local rect = self.rect
		local host = self.bgHost or (self.place == "on" and self.owner) or (IsFrame(rect) and rect) or rect:GetParent()
		local parts = NewParts(host, self.bgLayer, self.bgSub)
		parts.m = host:CreateTexture(nil, self.bgLayer, nil, self.bgSub)
		self.bgParts = parts
		-- the region given; round the rect its opening is the rect; on it, an empty region of the host's inset by
		-- the rails
		self.bgAt = self.bgAtRegion or (self.place == "round" and rect) or host:CreateTexture(nil, self.bgLayer, nil, self.bgSub)
		if self.bgAt ~= rect and self.bgAt ~= self.bgAtRegion then
			self.bgAt:Hide()   -- (0.20.1: an empty anchor -- hidden it lays out alike and is never counted as drawn)
		end
	end
	if self.bgAt ~= self.rect and self.bgAt ~= self.bgAtRegion then
		local x, y = self:Inset()
		local tuck = 2 * k   -- (under the rails' inner bevel: no gap at the trough's edge)
		local at = self:At()
		self.bgAt:ClearAllPoints()
		self.bgAt:SetPoint("TOPLEFT", at, "TOPLEFT", x - tuck, -(y - tuck))
		self.bgAt:SetPoint("BOTTOMRIGHT", at, "BOTTOMRIGHT", -(x - tuck), y - tuck)
	end
	Kit:CutNine(self.bgAt, self.bgParts, piece, k, st.bgCorner or 16, false)
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
	if self.bgParts then
		ShowParts(self.bgParts, on and st ~= nil and st.bg ~= nil)
		self.bgParts.m:SetShown(on and st ~= nil and st.bg ~= nil)
	end
	if st and st.master then
		ShowParts(self.parts, on)
		OpenSide(self)
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

-- (the painted reskin's borders, part A: MelloUI_Oldschool/Modules/KitBordersPainted.lua, one look stage I)

-- (0.20.1) A bar's library border fitted to the bar as the bracket is (Kit.lua's bar Refit asks again on every
-- refit): its band the bracket's share of the bar's height, centred; its rails a quarter of that band at most, never
-- deeper than the weight's (a thin bar -- a nameplate's, an XP bar -- a thin rail); its art at the panel's artScale
-- (Kit:BarLibraryFit, block B; 0.21.0: the Personal Display's bars, the same rule)
Kit.BorderBandRail = 0.25

-- (0.20.5, the user: the Stone rail apart from the bar, "there is the background, but not attached") a bar's trough
-- run half a rail under a library border on each railed side: the rail's inner edge, its art drawn far smaller than
-- painted, is soft, and with no style background on a bar (noBg) the world showed through it. Every style's rail is
-- solid to its opening, so the tucked trough stays hidden under it. On `rect` set in by l, r, t, b (a bar's opening;
-- 0 for a fill); no border: on that rect itself. Shared: Kit:BarLibraryFit, the Personal Display (0.21.0)
function Kit:TuckTrough(trough, rect, border, l, r, t, b)
	local x, y = 0, 0
	if border then
		x, y = border:Inset()
		x, y = x / 2, y / 2
	end
	l, r, t, b = l or 0, r or 0, t or 0, b or 0
	local open = border and border.open
	trough:ClearAllPoints()
	trough:SetPoint("TOPLEFT", rect, "TOPLEFT", l - (open == "l" and 0 or x), -(t - y))
	trough:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", -(r - (open == "r" and 0 or x)), b - y)
	Kit:Retile(trough)
end

-- (the painted reskin's borders, part B: MelloUI_Oldschool/Modules/KitBordersPainted.lua)

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
-- (onelook D12: `core`, the one kind UI Modifications' core settings make a row for; the others are the painted
-- reskin's, their rows its part's)
Kit:AddBorderKind({ kind = "cooldown", key = "cooldownBorder", default = "game", name = "Cooldown Manager Border",
	values = Kit.cooldownLooks, preview = "rim", core = true,
	desc = "The rim round the icons of the game's Cooldown Manager: the game's own bevel, or one of the border styles "
		.. "the buttons wear." }, nil, "colours")

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
	-- (a style of the painted kit's: with the reskin on, as every Oldschool > Borders row; else the game's bevel)
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

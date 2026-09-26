--------------------------------------------------------------------------------
-- MelloUI - Shade
--
-- The soft shade: one shared way to darken what is behind a piece of text so
-- it reads without an outline (user, 2026-09-25: the on-screen notice first,
-- then the nameplates' names, and in 0.14.0 a shade that follows every kit
-- shape). The game cannot blur what lies behind a frame, so the blur is faked
-- with a band of one white texture whose alpha falls off smoothly
-- (Media\Textures\SoftShade, made by Tools\make_soft_shade.py), tinted with a
-- dark palette colour. It is laid as three slices -- the left end, the
-- middle, the right end -- so the soft ends keep their width however long
-- the band is; top and bottom fade inside the texture.
--
--   local band = MelloUI.Shade:Band(parent, opts)
--       Three textures made on `parent` (they draw in its layers and follow
--       its show, hide and alpha). opts, all optional, read once, not kept:
--         colour    a MelloUI.Palette key (default "innerPanel"); an unknown
--                   key paints innerPanel
--         alpha     its strength, 0..1 (default 0.7)
--         feather   the width of each soft end, in parent units (default 16)
--         layer     the draw layer (default "BACKGROUND"; an unknown one too)
--         sublevel  -8..7 (default 0; kept inside that range)
--         region, padX, padY   laid behind `region` at once (band:Anchor)
--   band:Anchor(region[, padX, padY])
--       Its full-strength middle covers the region grown by padX on each
--       side and padY above and below; the soft ends reach `feather` further
--       out left and right (a negative padX pulls them inside the region).
--   band:Anchor(left, right[, padX, padY])
--       Between two regions: from left's left edge (and top) to right's
--       right edge (and bottom).
--       Anchors only: no size or position is ever read, so it can sit behind
--       a region whose size is secret (a nameplate's), and it follows the
--       region's size with no code at all (a text that grows).
--   band:SetStrength(alpha)   its alpha, 0..1
--   band:SetShown(on)         shown or hidden (its parent's own show still rules)
--   band:IsShown()
--   band:SetColour(key)       another palette key
--   band:SetFeather(width)    the soft ends' width
--   band.left, band.mid, band.right: its textures (read only)
-- Nothing is made until the first band: then its three textures and one
-- 'palette' listener for all bands, which repaints each from the palette's
-- colour of its key. A band makes no garbage once made (Anchor, SetStrength,
-- SetShown and a repaint allocate nothing).
--
-- 0.14.0 adds three more pieces here, each made on first use only:
--   MelloUI.Shade.TEXT            the look of every soft-shaded line of text
--                                 (the notice's): read by the notice, the zone
--                                 text and the centre texts ("The text look")
--   MelloUI.Shade:Measure(...)    an unseen copy of a line that the engine
--                                 sizes to its text, for a band to hug it
--                                 without reading a size ("The measure")
--   MelloUI.Shade:Glow(...)       the round soft glow in a palette colour
--                                 (the Reminder widget's; "The round glow")
-- The one 'palette' listener (owner "Shade") repaints the bands and the glows.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
-- this file's load time (/melloperf load); at load it sets no script, hook
-- or timer (a glow's hooks on its frame come with the first glow)
local Perf = MelloUI.Perf:Scope("Shade")

local Shade = {}
MelloUI.Shade = Shade

Shade.FILE = "Interface\\AddOns\\MelloUI\\Media\\Textures\\SoftShade"
local DEFAULT_COLOUR = "innerPanel"
local DEFAULT_ALPHA = 0.7
local DEFAULT_FEATHER = 16
-- the file's slices (Tools\make_soft_shade.py: the ends are its outer
-- quarters, the middle half is flat across)
local CAP = 0.25
-- the draw layers a texture can take
local LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true, HIGHLIGHT = true }

local Num = MelloUI.Safe.Number
local Secret = MelloUI.Safe.IsSecret

local bands = setmetatable({}, { __mode = "k" })   -- every band made, for the repaint
local glows = setmetatable({}, { __mode = "k" })   -- every glow made, for the repaint
local listening = false
local NO_OPTIONS = {}

-- a draw layer and sublevel the game takes: CreateTexture raises on others
-- (an unknown layer is BACKGROUND, the sublevel kept in -8..7)
local function Layer(opts, sublevel)
	local layer = type(opts.layer) == "string" and LAYERS[opts.layer] and opts.layer or "BACKGROUND"
	sublevel = math.floor(Num(opts.sublevel) or sublevel)
	if sublevel < -8 then
		sublevel = -8
	elseif sublevel > 7 then
		sublevel = 7
	end
	return layer, sublevel
end

local Band = {}
local BandMeta = { __index = Band }

-- its colour from the palette as it is now (a new palette is a new table)
function Band:Paint()
	local palette = MelloUI.Palette
	local c = palette[self.colour] or palette[DEFAULT_COLOUR]
	local a = self.alpha
	self.left:SetVertexColor(c[1], c[2], c[3], a)
	self.mid:SetVertexColor(c[1], c[2], c[3], a)
	self.right:SetVertexColor(c[1], c[2], c[3], a)
end

function Band:SetStrength(alpha)
	alpha = Num(alpha)
	if not alpha then
		return
	end
	if alpha < 0 then
		alpha = 0
	elseif alpha > 1 then
		alpha = 1
	end
	self.alpha = alpha
	self:Paint()
end

function Band:SetColour(key)
	self.colour = type(key) == "string" and key or DEFAULT_COLOUR
	self:Paint()
end

function Band:SetFeather(width)
	width = Num(width)
	if not width or width < 0 then
		return
	end
	self.feather = width
	self.left:SetWidth(width)
	self.right:SetWidth(width)
end

function Band:SetShown(on)
	on = on and true or false
	self.shown = on
	self.left:SetShown(on)
	self.mid:SetShown(on)
	self.right:SetShown(on)
end

function Band:IsShown()
	return self.shown
end

-- Anchor(region[, padX, padY]) or Anchor(left, right[, padX, padY]): only
-- the middle is anchored here; the ends hang on the middle's edges
function Band:Anchor(a, b, c, d)
	local left, right, padX, padY
	if type(b) == "table" then
		left, right, padX, padY = a, b, c, d
	else
		left, right, padX, padY = a, a, b, c
	end
	padX, padY = Num(padX) or 0, Num(padY) or 0
	local mid = self.mid
	mid:ClearAllPoints()
	if type(left) ~= "table" then
		return
	end
	mid:SetPoint("TOPLEFT", left, "TOPLEFT", -padX, padY)
	mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", padX, -padY)
end

local function Repaint()
	for band in pairs(bands) do
		band:Paint()
	end
	for glow in pairs(glows) do
		glow:Paint()
	end
end

-- the one 'palette' listener, taken with the first band or glow
local function Listen()
	if not listening then
		listening = true
		MelloUI:On("palette", Repaint, "Shade")
	end
end

local function Slice(parent, layer, sublevel, l, r)
	local t = parent:CreateTexture(nil, layer, nil, sublevel)
	t:SetTexture(Shade.FILE)
	t:SetTexCoord(l, r, 0, 1)
	return t
end

function Shade:Band(parent, opts)
	if type(parent) ~= "table" or not parent.CreateTexture then
		return nil
	end
	if type(opts) ~= "table" then
		opts = NO_OPTIONS
	end
	local layer, sublevel = Layer(opts, 0)
	local band = setmetatable({
		colour = type(opts.colour) == "string" and opts.colour or DEFAULT_COLOUR,
		alpha = Num(opts.alpha) or DEFAULT_ALPHA,
		feather = Num(opts.feather) or DEFAULT_FEATHER,
		shown = true,
	}, BandMeta)
	band.left = Slice(parent, layer, sublevel, 0, CAP)
	band.mid = Slice(parent, layer, sublevel, CAP, 1 - CAP)
	band.right = Slice(parent, layer, sublevel, 1 - CAP, 1)
	-- the ends on the middle's edges, once: an Anchor moves only the middle
	band.left:SetPoint("TOPRIGHT", band.mid, "TOPLEFT")
	band.left:SetPoint("BOTTOMRIGHT", band.mid, "BOTTOMLEFT")
	band.right:SetPoint("TOPLEFT", band.mid, "TOPRIGHT")
	band.right:SetPoint("BOTTOMLEFT", band.mid, "BOTTOMRIGHT")
	band.left:SetWidth(band.feather)
	band.right:SetWidth(band.feather)
	band:Paint()
	if opts.region then
		band:Anchor(opts.region, opts.padX, opts.padY)
	end
	bands[band] = true
	Listen()
	return band
end

--------------------------------------------------------------------------------
-- The text look (0.14.0, the centre texts: one look for every soft-shaded
-- line of text, where the notice, the zone text and the centre texts each
-- kept a copy)
--   MelloUI.Shade.TEXT   read only (fields by name; writing one raises)
--     colour "innerPanel", alpha 0.7, feather 36, padX 10, padY 12,
--     layer "BACKGROUND"    the band: these are Shade:Band's own options,
--                           so Shade:Band(parent, Shade.TEXT) lays the look
--                           (a region and pads are anchored separately)
--     shadow 0.85, shadowX 1, shadowY -1
--                           the text's shadow: innerPanel at 0.85, one unit
--                           right and down
--     lineY 0.4             stacked lines (the zone text's three): padY is
--                           0.4 of each line's text size (Shade:LinePadY)
--   MelloUI.Shade:LinePadY(size) -> padY for one of stacked lines of that
--       text size (lineY * size); a size that is not a plain number above 0
--       gives TEXT.padY
--------------------------------------------------------------------------------

do
	local LOOK = { colour = DEFAULT_COLOUR, alpha = DEFAULT_ALPHA, feather = 36, padX = 10, padY = 12,
		layer = "BACKGROUND", shadow = 0.85, shadowX = 1, shadowY = -1, lineY = 0.4 }
	Shade.TEXT = setmetatable({}, {
		__index = LOOK,
		__newindex = function(_, key)
			error("MelloUI.Shade.TEXT is read only (" .. tostring(key) .. ")", 2)
		end,
		__metatable = false,
	})

	function Shade:LinePadY(size)
		size = Num(size)
		if not size or size <= 0 then
			return LOOK.padY
		end
		return LOOK.lineY * size
	end
end

--------------------------------------------------------------------------------
-- The measure (lifted from the nameplates' name shade, 0.13.7, for any line
-- a band must hug without reading its size: the centre texts, 0.14.0)
--   local m = MelloUI.Shade:Measure(parent, source[, point])
--       An unseen font string made on `parent` (BACKGROUND, alpha 0, no
--       width of its own, no wrap), its `point` ("TOP" when left out;
--       "CENTER", "LEFT", ...) on the same point of `source` (the line it
--       measures), its font copied from source: font object, then face,
--       size and flags, then text scale (a secret or refused one leaves that
--       part as it was). The engine sizes it to its text, so a band hung on
--       it (band:Anchor(m, padX, padY)) hugs the text however long, reading
--       no size. nil when parent cannot make font strings.
--   MelloUI.Shade:MeasureText(m, text) -> taken
--       the text handed on untouched, a secret one too (pcall(SetText)):
--       true when the measure took it; false (a client that refuses the
--       text there) means: hang the band on the line's span instead
--   MelloUI.Shade:MeasureFormatted(m, format, ...) -> taken
--       the same for a line set with SetFormattedText (its arguments handed
--       on untouched: pcall(SetFormattedText))
--   MelloUI.Shade:MeasureFont(m[, source])
--       its font copied again, from `source` (which it then follows, font
--       only: its anchor stays) or from its own: after the line's restyle
--   MelloUI.Shade:ClearMeasure(m)
--       empty, and its secret text aspect dropped (ClearText; SetText("")
--       where there is none)
-- Every measure copies its source's font again when the fonts change (one
-- 'fonts' listener for all, owner "Shade measures", taken with the first
-- measure; run on the next frame, so the lines' own restyle comes first).
-- Nothing is written onto the source, and no size is read anywhere. (The
-- nameplates' name shade uses these calls too, since 0.14.0: one measure,
-- one 'fonts' listener.)
--------------------------------------------------------------------------------

do
	local measures = setmetatable({}, { __mode = "k" })   -- [measure] = the line it measures
	local POINTS = { TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, CENTER = true, TOPLEFT = true,
		TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
	local fontsHeard = false

	-- the line's font on the measure: each part handed on as it comes
	local function CopyFont(source, m)
		local okO, object = pcall(source.GetFontObject, source)
		if okO and not Secret(object) and type(object) == "table" then
			pcall(m.SetFontObject, m, object)
		end
		local okF, face, size, flags = pcall(source.GetFont, source)
		if okF and not Secret(face) and type(face) == "string" then
			pcall(m.SetFont, m, face, size, flags)
		end
		local okS, scale = pcall(source.GetTextScale, source)
		if okS and not Secret(scale) and type(scale) == "number" then
			pcall(m.SetTextScale, m, scale)
		end
	end

	local function RefontAll()
		for m, source in pairs(measures) do
			CopyFont(source, m)
		end
	end

	local function OnFonts()
		local Kit = MelloUI.Kit
		if Kit and Kit.NextFrame then
			Kit:NextFrame("Shade measures", RefontAll)
		else
			RefontAll()
		end
	end

	function Shade:Measure(parent, source, point)
		if type(parent) ~= "table" or type(parent.CreateFontString) ~= "function" or type(source) ~= "table" then
			return nil
		end
		point = type(point) == "string" and POINTS[point] and point or "TOP"
		local m = parent:CreateFontString(nil, "BACKGROUND")
		m:SetAlpha(0)
		m:SetWordWrap(false)
		m:SetPoint(point, source, point, 0, 0)
		CopyFont(source, m)
		measures[m] = source
		if not fontsHeard then
			fontsHeard = true
			MelloUI:On("fonts", OnFonts, "Shade measures")
		end
		return m
	end

	function Shade:MeasureText(m, text)
		if type(m) ~= "table" or not measures[m] then
			return false
		end
		return (pcall(m.SetText, m, text))
	end

	function Shade:MeasureFormatted(m, ...)
		if type(m) ~= "table" or not measures[m] then
			return false
		end
		return (pcall(m.SetFormattedText, m, ...))
	end

	function Shade:MeasureFont(m, source)
		if type(m) ~= "table" or not measures[m] then
			return
		end
		if type(source) == "table" then
			measures[m] = source
		end
		CopyFont(measures[m], m)
	end

	function Shade:ClearMeasure(m)
		if type(m) ~= "table" or not measures[m] then
			return
		end
		if type(m.ClearText) == "function" then
			pcall(m.ClearText, m)
		else
			pcall(m.SetText, m, "")
		end
	end
end

--------------------------------------------------------------------------------
-- The round glow (0.14.0, the Reminder widget; the user, 2026-09-26: "make
-- sure that widget has a nice glow around it": a gentle gold pulse for about
-- 10 s, then a steady glow that brightens in reach of the NPC; round and
-- baked, never a square). One white texture, Media\Textures\SoftGlowRound
-- (Tools\make_soft_glow.py): clear in the middle, brightest just outside the
-- ring's edge, fading out to nothing; tinted with a palette colour and added
-- as light.
--   local glow = MelloUI.Shade:Glow(parent, opts)
--       One texture made on `parent` (a frame), hidden until shown. opts, all
--       optional, read once, not kept:
--         key       a MelloUI.Palette key (default "selectedTrim"; an
--                   unknown one paints selectedTrim)
--         region    the ring it lies around (default parent)
--         size      the ring's size, in region units (default 36): the
--                   glow reaches a third of it past each side. It hangs on
--                   the region by anchors only and reads no size, so it can
--                   sit under a nameplate; the caller knows the size (it
--                   set it)
--         strength  "near" (default), "reach" (brighter: in reach of the
--                   NPC) or a number 0..1
--         layer, sublevel   default BACKGROUND -7 (over the shade partners
--                   at -8, under the ring's own art)
--         blend     "ADD" (default: light) or "BLEND"
--         shown     true: shown, and playing, at once
--   glow:SetShown(on)     shown and playing its motion, or hidden and still
--                         (shown again while shown: nothing)
--   glow:IsShown()
--   glow:SetStrength("near" | "reach" | n)   its brightness; no garbage
--   glow:Settle()         from now on: pulse about 10 s, then a steady glow
--                         (the user's choice); started again now if shown
--   glow:Pulse()          from now on: pulse for as long as it shows (the
--                         motion a new glow has)
--   glow:Still()          from now on: a steady glow
--   glow:SetColour(key)   another palette key
--   glow:Anchor(region[, size])   hung on another ring; region left out: the
--                         ring it hangs on now, at a new size
--   glow.tex              its texture (read only)
-- The pulse is Anim:Pulse's, run by the engine: no Lua per frame. Reduce
-- Motion: a steady glow at once, whatever the motion. Hidden -- by SetShown
-- or because its frame hides -- its pulse is stopped (no idle work); when
-- its frame shows again the motion starts again (a Settle pulses its 10 s
-- again). The one 'palette' listener repaints it. Made on first use: the
-- first glow on a frame hooks that frame's OnShow and OnHide (one shared
-- handler each, for every glow's frame).
--------------------------------------------------------------------------------

Shade.GLOW_FILE = "Interface\\AddOns\\MelloUI\\Media\\Textures\\SoftGlowRound"
-- the ring's edge in the art, as a share of its half-width (make_soft_glow.py
-- RING): the art reaches (1 / RING - 1) / 2 of the ring's size past each side
Shade.GLOW_RING = 0.6

do
	local GLOW_KEY = "selectedTrim"
	local GLOW_SIZE = 36
	local PAD = (1 / Shade.GLOW_RING - 1) / 2
	local STRENGTH = { near = 0.7, reach = 1 }
	-- the motion: from, to (the texture's own alpha), one way's time, the
	-- steady glow's alpha, and a Settle's time pulsing
	local FROM, TO, PERIOD, STILL, SETTLE = 0.35, 0.85, 1.6, 0.7, 10
	local MOTIONS = { pulse = true, settle = true, still = true }

	local Glow = {}
	local GlowMeta = { __index = Glow }
	local glowsOn = setmetatable({}, { __mode = "k" })   -- [frame] = { [glow] = true }, its glows
	local OnFrameShow, OnFrameHide   -- the hooks' one handler each, made with the first glow

	local function StrengthOf(s)
		if Secret(s) then
			return STRENGTH.near
		end
		local v = STRENGTH[s]
		if v then
			return v
		end
		v = Num(s)
		if not v then
			return STRENGTH.near
		end
		return v < 0 and 0 or (v > 1 and 1 or v)
	end

	-- its frame shown on the screen (a secret answer counts as shown)
	local function Visible(frame)
		local v = frame:IsVisible()
		return Secret(v) or (v and true or false)
	end

	local function Stop(glow)
		local Anim = MelloUI.Anim
		if Anim and glow.group then
			Anim:StopGroup(glow.group)
		end
		glow.group = false
	end

	-- its motion, from the start (only while it and its frame show)
	local function Play(glow)
		local Anim = MelloUI.Anim
		local tex = glow.tex
		if not Anim or glow.motion == "still" then
			Stop(glow)
			tex:SetAlpha(STILL)
		elseif glow.motion == "settle" then
			glow.group = Anim:Pulse(tex, FROM, TO, PERIOD, STILL, SETTLE)
		else
			glow.group = Anim:Pulse(tex, FROM, TO, PERIOD, STILL)
		end
	end

	local function Motion(glow, motion)
		glow.motion = MOTIONS[motion] and motion or "pulse"
		if glow.shown and Visible(glow.parent) then
			Play(glow)
		end
	end

	local function FrameShown(frame)
		local list = glowsOn[frame]
		if list then
			for glow in pairs(list) do
				if glow.shown then
					Play(glow)
				end
			end
		end
	end

	local function FrameHidden(frame)
		local list = glowsOn[frame]
		if list then
			for glow in pairs(list) do
				Stop(glow)
			end
		end
	end

	function Glow:Paint()
		local palette = MelloUI.Palette
		local c = palette[self.key] or palette[GLOW_KEY]
		self.tex:SetVertexColor(c[1], c[2], c[3], self.strength)
	end

	function Glow:SetStrength(s)
		local v = StrengthOf(s)
		if v ~= self.strength then
			self.strength = v
			self:Paint()
		end
	end

	function Glow:SetColour(key)
		self.key = type(key) == "string" and key or GLOW_KEY
		self:Paint()
	end

	function Glow:Anchor(region, size)
		if type(region) ~= "table" then
			region = self.region or self.parent   -- the ring it hangs on now
		end
		size = Num(size) or self.size
		self.region, self.size = region, size
		local pad = size * PAD
		local tex = self.tex
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", region, "TOPLEFT", -pad, pad)
		tex:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", pad, -pad)
	end

	function Glow:SetShown(on)
		on = on and true or false
		if on == self.shown then
			return
		end
		self.shown = on
		self.tex:SetShown(on)
		if on and Visible(self.parent) then
			Play(self)
		else
			Stop(self)
		end
	end

	function Glow:IsShown()
		return self.shown
	end

	function Glow:Settle()
		Motion(self, "settle")
	end

	function Glow:Pulse()
		Motion(self, "pulse")
	end

	function Glow:Still()
		Motion(self, "still")
	end

	-- the frame's show and hide, hooked once per frame (a hook: the frame
	-- may be the game's)
	local function Hook(frame, glow)
		local list = glowsOn[frame]
		if not list then
			list = setmetatable({}, { __mode = "k" })
			glowsOn[frame] = list
			if not OnFrameShow then
				OnFrameShow = Perf.Shared("OnShow on a glow's frame (its pulse played)", FrameShown, "script")
				OnFrameHide = Perf.Shared("OnHide on a glow's frame (its pulse stopped)", FrameHidden, "script")
			end
			Perf.HookScript(frame, "OnShow", OnFrameShow)
			Perf.HookScript(frame, "OnHide", OnFrameHide)
		end
		list[glow] = true
	end

	function Shade:Glow(parent, opts)
		if type(parent) ~= "table" or not parent.CreateTexture or not parent.HookScript then
			return nil
		end
		if type(opts) ~= "table" then
			opts = NO_OPTIONS
		end
		local layer, sublevel = Layer(opts, -7)
		local tex = parent:CreateTexture(nil, layer, nil, sublevel)
		tex:SetTexture(Shade.GLOW_FILE)
		tex:SetBlendMode(opts.blend == "BLEND" and "BLEND" or "ADD")
		tex:SetAlpha(STILL)
		tex:Hide()
		local glow = setmetatable({
			tex = tex,
			parent = parent,
			key = type(opts.key) == "string" and opts.key or GLOW_KEY,
			strength = StrengthOf(opts.strength),
			size = GLOW_SIZE,
			motion = "pulse",
			shown = false,
		}, GlowMeta)
		glow:Anchor(opts.region, Num(opts.size) or GLOW_SIZE)
		glow:Paint()
		glows[glow] = true
		Hook(parent, glow)
		Listen()
		if opts.shown then
			glow:SetShown(true)
		end
		return glow
	end
end

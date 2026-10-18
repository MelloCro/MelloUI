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
--         colour    a MelloUI.Palette key (default "innerPanel"), or (0.25.0)
--                   a MelloUI.Meaning one (the Personal Display's red rim:
--                   combatTaken); an unknown key paints innerPanel
--         alpha     its strength, 0..1 (default 0.7)
--         feather   the width of each soft end, in parent units (default 16)
--         layer     the draw layer (default "BACKGROUND"; an unknown one too)
--         sublevel  -8..7 (default 0; kept inside that range)
--         region, padX, padY   laid behind `region` at once (band:Anchor)
--         featherY  (0.17.0) a fixed height for the top and bottom fade, in
--                   parent units: for a tall band behind a block of lines
--                   (the widget column's subtitles). Left out, the texture's
--                   own fade stretches with the band -- right for one line,
--                   but a block four lines tall faded over 30% of its height
--                   at each end, its first and last lines on the fade (user,
--                   2026-10-01). With it, the texture's top and bottom rows
--                   are laid at featherY above and below the middle, and the
--                   middle is the texture's flat part: full strength over the
--                   whole region, as band:Anchor says
--         pixel     (one-look D6) true: every slice on the pixel grid when
--                   made (Shade:RoundToPixel): for parts added to a nameplate
--                   after the game rounded the plate at its OnLoad
--                   (Blizzard_NamePlateUnitFrame.lua:104)
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
--   band:SetFeather(width)    the soft ends' width (the tests'; the bands
--                             keep the one they were made with)
--   band.left, band.mid, band.right: its middle row's textures (read only);
--   band.slices: every texture of it (three, or nine with featherY)
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
-- onelook stage D4 adds one more:
--   MelloUI.Shade:Outline(...)    the band's soft look round any snapped
--                                 shape (the action bars' backdrops; "The
--                                 soft outline")
-- onelook D6 adds, each made on first use only, nothing at load:
--   MelloUI.Shade:RoundToPixel(region)   a region of ours on the pixel grid
--                                 (Band's `pixel`, the measure's and the
--                                 cover's)
--   MelloUI.Shade:Measure(parent, source, point, opts)   opts { pixel,
--                                 smooth }, read once ("The measure")
--   MelloUI.Shade:Cover(parent, source[, opts]) -> fs, with :CoverText,
--                                 :CoverColour and :CoverFont: a string of
--                                 ours on a game line's rect in its look,
--                                 showing another text over it ("The
--                                 cover"; the nameplates' Show Names As and
--                                 Unit Frames' name covers). opts: layer,
--                                 sublevel, pixel, hidden, textColour (true:
--                                 its colour set with SetTextColor; else
--                                 SetVertexColor, the plates' game's), refont
--                                 (fn(fs, source), run after a Font Style
--                                 copy). The covers share the measures' one
--                                 'fonts' listener (owner "Shade measures"),
--                                 and after every font copy a cover gets its
--                                 last colour back (a font object puts its
--                                 own colour on a string: Notice.lua,
--                                 QuestInk.lua)
-- The one 'palette' listener (owner "Shade") repaints the bands, the glows
-- and the outlines.
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
-- ... and its height's: the alpha rises over the top 20 of its 64 rows and
-- falls over the bottom 20, flat between (featherY lays them apart)
local VCAP = 0.3125
-- the draw layers a texture can take
local LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true, HIGHLIGHT = true }

local Num = MelloUI.Safe.Number
local Secret = MelloUI.Safe.IsSecret

local bands = setmetatable({}, { __mode = "k" })   -- every band made, for the repaint
local glows = setmetatable({}, { __mode = "k" })   -- every glow made, for the repaint
local outlines = setmetatable({}, { __mode = "k" })   -- every soft outline made, for the repaint
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
	local c = palette[self.colour] or MelloUI.Meaning[self.colour] or palette[DEFAULT_COLOUR]
	local a = self.alpha
	local slices = self.slices
	for i = 1, #slices do
		slices[i]:SetVertexColor(c[1], c[2], c[3], a)
	end
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
	local slices = self.slices
	for i = 1, #slices do
		slices[i]:SetShown(on)
	end
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

-- (one-look D6) a region of ours on the game's pixel grid: the game rounds a
-- nameplate's every part to the nearest pixel once, at its making
-- (Blizzard_NamePlateUnitFrame.lua OnLoad), and a part added later keeps its
-- own sub-pixel layout and slides against the rounded ones as the plate
-- moves. A frame that is forbidden or protected (or answers so secret, or
-- raises) is left alone; only a plain false is set (NameplatePanel's Round)
function Shade:RoundToPixel(region)
	if type(region) ~= "table" or type(region.GetRoundLayoutToNearestPixel) ~= "function" then
		return
	end
	if region.IsForbidden then
		local okF, forbidden = pcall(region.IsForbidden, region)
		if not okF or Secret(forbidden) or forbidden then
			return
		end
	end
	if region.IsProtected then
		local okP, protected = pcall(region.IsProtected, region)
		if not okP or Secret(protected) or protected then
			return
		end
	end
	local ok, on = pcall(region.GetRoundLayoutToNearestPixel, region)
	if ok and not Secret(on) and on == false then
		pcall(region.SetRoundLayoutToNearestPixel, region, true)
	end
end

local function Repaint()
	for band in pairs(bands) do
		band:Paint()
	end
	for glow in pairs(glows) do
		glow:Paint()
	end
	for outline in pairs(outlines) do
		outline:Paint()
	end
end

-- the one 'palette' listener, taken with the first band, glow or outline
local function Listen()
	if not listening then
		listening = true
		MelloUI:On("palette", Repaint, "Shade")
	end
end

local function Slice(parent, layer, sublevel, l, r, top, bottom)
	local t = parent:CreateTexture(nil, layer, nil, sublevel)
	t:SetTexture(Shade.FILE)
	t:SetTexCoord(l, r, top or 0, bottom or 1)
	return t
end

-- (0.17.0) featherY: the middle row on the texture's flat part, the top and
-- bottom rows of it laid above and below at a fixed height
local EDGE_ROWS = { { 0, VCAP, "BOTTOM", "TOP" }, { 1 - VCAP, 1, "TOP", "BOTTOM" } }

local function Edges(band, parent, layer, sublevel, featherY)
	band.left:SetTexCoord(0, CAP, VCAP, 1 - VCAP)
	band.mid:SetTexCoord(CAP, 1 - CAP, VCAP, 1 - VCAP)
	band.right:SetTexCoord(1 - CAP, 1, VCAP, 1 - VCAP)
	local cols = { { 0, CAP, band.left }, { CAP, 1 - CAP, band.mid }, { 1 - CAP, 1, band.right } }
	for _, row in ipairs(EDGE_ROWS) do
		for _, col in ipairs(cols) do
			local s = Slice(parent, layer, sublevel, col[1], col[2], row[1], row[2])
			s:SetPoint(row[3] .. "LEFT", col[3], row[4] .. "LEFT")
			s:SetPoint(row[3] .. "RIGHT", col[3], row[4] .. "RIGHT")
			s:SetHeight(featherY)
			band.slices[#band.slices + 1] = s
		end
	end
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
	band.slices = { band.left, band.mid, band.right }
	local featherY = Num(opts.featherY)
	if featherY and featherY > 0 then
		Edges(band, parent, layer, sublevel, featherY)
	end
	if opts.pixel then
		for i = 1, #band.slices do
			Shade:RoundToPixel(band.slices[i])
		end
	end
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
--   local m = MelloUI.Shade:Measure(parent, source[, point[, opts]])
--       (one-look D6: opts, read once, not kept: pixel -- the holder and the
--       measure on the pixel grid, Shade:RoundToPixel; smooth -- the
--       source's smooth scaling copied with its font, as a nameplate name's)
--       An unseen font string made on `parent` (BACKGROUND, no width of its
--       own, no wrap) -- on parent's unseen child frame (alpha 0, one per
--       parent, on parent's rect, out of layouts, no mouse): its own alpha
--       does not keep it unseen, a font object handed to a font string sets
--       that back to 1 (2026-10-03: every party frame drew its measure's copy
--       of the name over the name, a hair wider) -- its `point` ("TOP" when left out;
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
--   MelloUI.Shade:SourceFont(source)
--       every measure of `source` copies its font again: a line whose own
--       font changed outside a 'fonts' Fire (one look C11: a unit frame
--       name's face, Modules/UnitFrames.lua NameFace)
--   MelloUI.Shade:ClearMeasure(m)
--       empty, and its secret text aspect dropped (ClearText; SetText("")
--       where there is none)
-- Every measure copies its source's font again when the fonts change (one
-- 'fonts' listener for all, owner "Shade measures", taken with the first
-- measure; run on the next frame, so the lines' own restyle comes first).
-- Nothing is written onto the source, and no size is read anywhere. (The
-- nameplates' name shade uses these calls too, since 0.14.0: one measure,
-- one 'fonts' listener.)
--
-- The cover (one-look D6: the nameplates' Show Names As, written on the
-- game's name on every health update before -- hard rule 1 -- and Unit
-- Frames' name covers, one maker for both)
--   local fs = MelloUI.Shade:Cover(parent, source[, opts])
--       A font string of ours made on `parent` at the source's draw layer
--       and sublevel (opts.layer / opts.sublevel win), on the source's rect
--       (SetAllPoints), no wrap, in the source's look: its font (as a
--       measure's, with smooth scaling), justify (H and V) and shadow. opts,
--       read once: pixel (on the pixel grid), hidden (made hidden),
--       textColour (true: its colour set with SetTextColor; else
--       SetVertexColor), refont (fn(fs, source), run after each Font Style
--       copy of it). nil when parent cannot make font strings.
--   MelloUI.Shade:CoverText(fs, text) -> taken
--       a secret text handed on each time, never compared; a plain one set
--       only when it differs from the last
--   MelloUI.Shade:CoverColour(fs, r, g, b, a)
--       kept as it comes and set with the cover's setter: a secret part
--       handed on every call, never compared; a plain colour skipped when
--       it is the one on already
--   MelloUI.Shade:CoverFont(fs[, source])
--       its look copied again (from `source`, which it then follows)
-- After every copy of the look the cover's last colour is handed back, raw
-- (a font object puts its own colour on a string): only a plain flag is
-- tested, never the values. Every cover is copied again with the measures
-- when the fonts change (the same one 'fonts' listener), then its refont.
--------------------------------------------------------------------------------

do
	local measures = setmetatable({}, { __mode = "k" })   -- [measure] = the line it measures
	local POINTS = { TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, CENTER = true, TOPLEFT = true,
		TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
	local fontsHeard = false
	local holders = setmetatable({}, { __mode = "k" })   -- [parent] = its unseen frame for measures
	-- (one-look D6) the strings whose font copy takes the source's smooth
	-- scaling too (a nameplate name's: Blizzard_NamePlates.xml, smoothScaling)
	local smooth = setmetatable({}, { __mode = "k" })   -- [font string] = true
	-- the covers: [cover] = the line it covers; [cover] = its record (made
	-- once at Cover: text, textSet, r, g, b, a, colourSet, colourSecret,
	-- setter, refont)
	local covers = setmetatable({}, { __mode = "k" })
	local rec = setmetatable({}, { __mode = "k" })

	-- the frame a parent's measures are drawn on: alpha 0 (a frame's alpha no
	-- font object changes), on the parent's rect so it is laid out, out of
	-- the parent's layout, no mouse; made with the parent's first measure
	local function Holder(parent)
		local holder = holders[parent]
		if not holder then
			holder = CreateFrame("Frame", nil, parent)
			holder:SetAllPoints(parent)
			holder:SetAlpha(0)
			holder:EnableMouse(false)
			holder.ignoreInLayout = true
			holders[parent] = holder
		end
		return holder
	end

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
		if smooth[m] then
			local okM, on = pcall(source.GetSmoothScaling, source)
			if okM and not Secret(on) and type(on) == "boolean" then
				pcall(m.SetSmoothScaling, m, on)
			end
		end
		-- (one-look D6: a measure's alpha 0 is set by each caller right after
		-- this -- the font object set it back; a cover keeps its own)
	end

	-- a cover's look (one-look D6): the font, the justify and the shadow, each
	-- handed on as it comes (a secret or refused one leaves that part); then
	-- its last colour back, the values raw and never compared -- a font
	-- object puts its own colour on a string (only the plain flag is tested)
	local function CopyLook(source, fs)
		CopyFont(source, fs)
		local okH, h = pcall(source.GetJustifyH, source)
		if okH and not Secret(h) and type(h) == "string" then
			pcall(fs.SetJustifyH, fs, h)
		end
		local okV, v = pcall(source.GetJustifyV, source)
		if okV and not Secret(v) and type(v) == "string" then
			pcall(fs.SetJustifyV, fs, v)
		end
		local okO, x, y = pcall(source.GetShadowOffset, source)
		if okO and Num(x) and Num(y) then
			pcall(fs.SetShadowOffset, fs, x, y)
		end
		local okC, r, g, b, a = pcall(source.GetShadowColor, source)
		if okC and Num(r) and Num(g) and Num(b) and not Secret(a) then
			pcall(fs.SetShadowColor, fs, r, g, b, a)
		end
		local c = rec[fs]
		if c and c.colourSet then
			pcall(fs[c.setter], fs, c.r, c.g, c.b, c.a)
		end
	end

	local function RefontAll()
		for m, source in pairs(measures) do
			CopyFont(source, m)
			m:SetAlpha(0)   -- (the font object set it back; its holder keeps it unseen anyway)
		end
		for fs, source in pairs(covers) do
			CopyLook(source, fs)
			local c = rec[fs]
			if c and c.refont then
				local ok, err = pcall(c.refont, fs, source)
				if not ok then
					geterrorhandler()(err)
				end
			end
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

	-- the one 'fonts' listener, taken with the first measure or cover
	local function HearFonts()
		if not fontsHeard then
			fontsHeard = true
			MelloUI:On("fonts", OnFonts, "Shade measures")
		end
	end

	function Shade:Measure(parent, source, point, opts)
		if type(parent) ~= "table" or type(parent.CreateFontString) ~= "function" or type(source) ~= "table" then
			return nil
		end
		point = type(point) == "string" and POINTS[point] and point or "TOP"
		local pixel = type(opts) == "table" and opts.pixel
		local holder = Holder(parent)
		if pixel then
			Shade:RoundToPixel(holder)
		end
		local m = holder:CreateFontString(nil, "BACKGROUND")
		m:SetAlpha(0)   -- (and its own alpha 0 too, for what it is worth)
		m:SetWordWrap(false)
		m:SetPoint(point, source, point, 0, 0)
		if type(opts) == "table" and opts.smooth then
			smooth[m] = true
		end
		CopyFont(source, m)
		m:SetAlpha(0)   -- (the font object set it back; its holder keeps it unseen anyway)
		if pixel then
			Shade:RoundToPixel(m)
		end
		measures[m] = source
		HearFonts()
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
		m:SetAlpha(0)   -- (the font object set it back; its holder keeps it unseen anyway)
	end

	function Shade:SourceFont(source)
		for m, src in pairs(measures) do
			if src == source then
				CopyFont(source, m)
				m:SetAlpha(0)   -- (the font object set it back; its holder keeps it unseen anyway)
			end
		end
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

	-- The cover (one-look D6; the section's head above)
	function Shade:Cover(parent, source, opts)
		if type(parent) ~= "table" or type(parent.CreateFontString) ~= "function" or type(source) ~= "table" then
			return nil
		end
		if type(opts) ~= "table" then
			opts = NO_OPTIONS
		end
		-- the source's draw layer and sublevel (asked for secret first), the
		-- options' where given
		local okL, layer, sublevel = pcall(source.GetDrawLayer, source)
		if not okL or Secret(layer) or type(layer) ~= "string" or not LAYERS[layer] then
			layer = "OVERLAY"
		end
		if not okL or Secret(sublevel) or type(sublevel) ~= "number" then
			sublevel = 0
		end
		if type(opts.layer) == "string" and LAYERS[opts.layer] then
			layer = opts.layer
		end
		sublevel = math.floor(Num(opts.sublevel) or sublevel)
		if sublevel < -8 then
			sublevel = -8
		elseif sublevel > 7 then
			sublevel = 7
		end
		local fs = parent:CreateFontString(nil, layer)
		pcall(fs.SetDrawLayer, fs, layer, sublevel)
		fs:SetAllPoints(source)
		fs:SetWordWrap(false)
		smooth[fs] = true
		rec[fs] = { setter = opts.textColour and "SetTextColor" or "SetVertexColor",
			refont = type(opts.refont) == "function" and opts.refont or nil, textSet = false, colourSet = false }
		CopyLook(source, fs)
		if opts.pixel then
			Shade:RoundToPixel(fs)
		end
		if opts.hidden then
			fs:Hide()
		end
		covers[fs] = source
		HearFonts()
		return fs
	end

	function Shade:CoverText(fs, text)
		local c = type(fs) == "table" and rec[fs]
		if not c then
			return false
		end
		-- (asked for secret first: a secret is handed on each time, never compared)
		if Secret(text) then
			c.text, c.textSet = nil, false
			return (pcall(fs.SetText, fs, text))
		end
		if c.textSet and c.text == text then
			return true
		end
		local ok = pcall(fs.SetText, fs, text)
		c.text, c.textSet = text, ok
		return ok
	end

	function Shade:CoverColour(fs, r, g, b, a)
		local c = type(fs) == "table" and rec[fs]
		if not c then
			return
		end
		if Secret(r) or Secret(g) or Secret(b) or Secret(a) then
			c.r, c.g, c.b, c.a = r, g, b, a
			c.colourSet, c.colourSecret = true, true
			pcall(fs[c.setter], fs, r, g, b, a)
			return
		end
		if c.colourSet and not c.colourSecret and c.r == r and c.g == g and c.b == b and c.a == a then
			return
		end
		c.r, c.g, c.b, c.a = r, g, b, a
		c.colourSet, c.colourSecret = true, false
		pcall(fs[c.setter], fs, r, g, b, a)
	end

	function Shade:CoverFont(fs, source)
		if type(fs) ~= "table" or not covers[fs] then
			return
		end
		if type(source) == "table" then
			covers[fs] = source
		end
		CopyLook(covers[fs], fs)
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
--   glow:SetTint(r, g, b) a colour of meaning instead (a debuff's dispel
--                         colour, perhaps secret: handed to the texture as it
--                         is, kept through a new palette); nil: its key again
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
Shade.GLOW_RING = 0.72   -- (0.6 until 2026-10-04: the user, the widgets' glow "kind of too big")

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
		if self.tinted then
			-- (a colour that is not the palette's: kept as given, perhaps
			-- secret -- only handed on, never read)
			self.tex:SetVertexColor(self.tintR, self.tintG, self.tintB, self.strength)
			return
		end
		local palette = MelloUI.Palette
		local c = palette[self.key] or palette[GLOW_KEY]
		self.tex:SetVertexColor(c[1], c[2], c[3], self.strength)
	end

	-- a colour of meaning rather than the palette's (a debuff's dispel
	-- colour: the client's, and secret in a fight): kept through a new
	-- palette; nil goes back to its key
	function Glow:SetTint(r, g, b)
		if not Secret(r) and r == nil then   -- (a secret is a colour: tested first, never compared)
			self.tinted, self.tintR, self.tintG, self.tintB = false, nil, nil, nil
		else
			self.tinted, self.tintR, self.tintG, self.tintB = true, r, g, b
		end
		self:Paint()
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

--------------------------------------------------------------------------------
-- The soft outline (onelook stage D4; the user's pick B of the action bars'
-- backdrops, docs/plans/onelook-b-sketches/backdrops.md: "a soft dark shade
-- on the snapped outline, no edge line"): a band's own look round any shape
-- MelloUI.Outline makes, so nothing else draws a soft outline. The band's
-- file and slices: the flat middle over the shape's inside, each side's soft
-- edge laid outward (a left or right side the file's end columns, a top or
-- bottom side its edge rows), the file's own corner on each outer corner
-- (its fall-off the two edges' product, as a band's corner), and in each
-- inner corner the two sides' edges crossed over the corner's square, each
-- cut to its half on the diagonal by Media\Textures\Masks\mitre
-- (Tools\make_mitre_mask.py: a half and its twin add up to one): there the
-- shade falls off from the nearer side, never doubled. Beside a run shorter
-- than the feather (a step of a few units) that square reaches only along
-- the run, its fall-off pressed into it, so it never lies over the next
-- corner's. (A bay narrower than two feathers can still double at its
-- walls; in an action bar backdrop the rails' insets alone make any bay
-- about that wide at the bars' usual size.)
--   local o = MelloUI.Shade:Outline(parent, opts)
--       Nothing made until a shape needs it. opts as a band's, all optional,
--       read once, not kept: colour (a palette key, default "innerPanel"),
--       alpha (0.7), feather (the soft edges' width in parent units, 16),
--       layer ("BACKGROUND"), sublevel (0). nil when parent cannot make
--       textures.
--   o:SetShape(shape, fill, s, ox, oy)
--       shape: MelloUI.Outline.Shape's (screen px); fill: its inside as
--       rects (left out: Outline.Fill(shape), made here); s: screen px per
--       parent unit; ox, oy: the parent's bottom-left corner on the screen.
--       Its textures come from its pools (the same counts again make
--       nothing new), the ones this shape does not need hidden; nil shape:
--       nothing drawn
--   o:SetColour(key), o:SetStrength(alpha), o:SetShown(on), o:IsShown()
--       as a band's
--   o:SetFeather(width)    the soft edges' width, the shape laid again
--   o.pools                its textures by kind, each { used = n, ... }:
--                          fill, side, corner, mitre (read only)
-- The one 'palette' listener repaints it. Laying a shape again allocates
-- nothing once its pools hold enough.
--------------------------------------------------------------------------------

Shade.MITRE = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Masks\\mitre"

do
	local abs = math.abs
	-- each side's soft edge, its slice of the file (u0, u1, v0, v1): full at
	-- the shape, clear outward
	local EDGE_UV = {
		left = { 0, CAP, VCAP, 1 - VCAP }, right = { 1 - CAP, 1, VCAP, 1 - VCAP },
		top = { CAP, 1 - CAP, 0, VCAP }, bottom = { CAP, 1 - CAP, 1 - VCAP, 1 },
	}
	local FLAT_UV = { CAP, 1 - CAP, VCAP, 1 - VCAP }
	-- an outer corner by its turn (the shape on the loop's left), the file's
	-- corner for it, and where its square lies from the corner (feathers)
	local OUTER = { right = { up = "br" }, up = { left = "tr" }, left = { down = "tl" }, down = { right = "bl" } }
	local CORNER_UV = { tl = { 0, CAP, 0, VCAP }, tr = { 1 - CAP, 1, 0, VCAP }, bl = { 0, CAP, 1 - VCAP, 1 },
		br = { 1 - CAP, 1, 1 - VCAP, 1 } }
	local CORNER_AT = { tl = { -1, 0 }, tr = { 0, 0 }, bl = { -1, -1 }, br = { 0, -1 } }
	-- the mask turned to each half of a square (the file's own: the top
	-- left one, cut from its top right corner to its bottom left), and the
	-- half its twin covers
	local MITRE_UV = { TL = { 0, 1, 0, 1 }, TR = { 1, 0, 0, 1 }, BL = { 0, 1, 1, 0 }, BR = { 1, 0, 1, 0 } }
	local MITRE_TWIN = { TL = "BR", TR = "BL", BL = "TR", BR = "TL" }
	local KINDS = { "fill", "side", "corner", "mitre" }

	local Out = {}
	local OutMeta = { __index = Out }

	function Out:Paint()
		local palette = MelloUI.Palette
		local c = palette[self.colour] or palette[DEFAULT_COLOUR]
		local a = self.alpha
		for _, kind in ipairs(KINDS) do
			local pool = self.pools[kind]
			for i = 1, #pool do
				pool[i]:SetVertexColor(c[1], c[2], c[3], a)
			end
		end
	end

	-- the next texture of a pool (made, and painted, the first time)
	local function Take(o, kind)
		local pool = o.pools[kind]
		local i = pool.used + 1
		pool.used = i
		local tex = pool[i]
		if not tex then
			tex = o.parent:CreateTexture(nil, o.layer, nil, o.sublevel)
			tex:SetTexture(Shade.FILE)
			pool[i] = tex
			local palette = MelloUI.Palette
			local c = palette[o.colour] or palette[DEFAULT_COLOUR]
			tex:SetVertexColor(c[1], c[2], c[3], o.alpha)
		end
		return tex, i
	end

	-- a texture over the screen rect x0, y0 - x1, y1, showing slice uv
	local function Lay(o, tex, uv, x0, y0, x1, y1)
		local s = o.s
		tex:SetTexCoord(uv[1], uv[2], uv[3], uv[4])
		tex:ClearAllPoints()
		tex:SetPoint("BOTTOMLEFT", o.parent, "BOTTOMLEFT", (x0 - o.ox) / s, (y0 - o.oy) / s)
		tex:SetSize((x1 - x0) / s, (y1 - y0) / s)
	end

	-- one side's edge over an inner corner's square (x0, y0, w wide, h
	-- high), cut to its half by the mask
	local function Mitre(o, side, half, x0, y0, w, h)
		local tex, i = Take(o, "mitre")
		Lay(o, tex, EDGE_UV[side], x0, y0, x0 + w, y0 + h)
		local mask = o.masks[i]
		if not mask then
			mask = o.parent:CreateMaskTexture()
			mask:SetTexture(Shade.MITRE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(tex)
			tex:AddMaskTexture(mask)
			o.masks[i] = mask
		end
		local m = MITRE_UV[half]
		mask:SetTexCoord(m[1], m[2], m[3], m[4])
	end

	-- how far an inner corner's square reaches along a run `len` long whose
	-- other end is `other`: the feather, or less where the run is shorter
	-- (a step between two bars a little out of line): up to that end when
	-- it is an outer corner (whose square lies past it), to the run's middle
	-- when it is an inner one too (whose square takes the other half). So no
	-- two squares lie over each other and the shade is never laid twice.
	local function Reach(F, len, other)
		local r = other.convex and len or len / 2
		return r < F and r or F
	end

	-- the shape's textures (F: the feather in screen px)
	local function Draw(o, shape, fill, F)
		for _, r in ipairs(fill) do
			Lay(o, Take(o, "fill"), FLAT_UV, r[1], r[2], r[3], r[4])
		end
		if F <= 0 then
			return
		end
		-- (the side a run is on, where the shape is NOT: Outline's one rule,
		-- read here -- Core/Outline.lua loads after this file)
		local SideOf = MelloUI.Outline.SideOf
		for _, loop in ipairs(shape.loops) do
			local m = #loop
			-- each side's edge from corner to corner, outward; short of an
			-- inner corner by its square (the mitres' there)
			for i = 1, m do
				local a, b = loop[i], loop[i % m + 1]
				local side = SideOf(a.dout)
				local len = abs(b.x - a.x) + abs(b.y - a.y)
				local ta = a.convex and 0 or Reach(F, len, b)
				local tb = b.convex and 0 or Reach(F, len, a)
				local x0, y0, x1, y1
				if side == "top" or side == "bottom" then
					if a.x < b.x then
						x0, x1 = a.x + ta, b.x - tb
					else
						x0, x1 = b.x + tb, a.x - ta
					end
					if side == "top" then
						y0, y1 = a.y, a.y + F
					else
						y0, y1 = a.y - F, a.y
					end
				else
					if a.y < b.y then
						y0, y1 = a.y + ta, b.y - tb
					else
						y0, y1 = b.y + tb, a.y - ta
					end
					if side == "right" then
						x0, x1 = a.x, a.x + F
					else
						x0, x1 = a.x - F, a.x
					end
				end
				if side and x1 > x0 and y1 > y0 then
					Lay(o, Take(o, "side"), EDGE_UV[side], x0, y0, x1, y1)
				end
			end
			-- the corners: the file's own on each outer one; on each inner
			-- one the row's edge and the column's crossed, each on its half
			for i = 1, m do
				local c = loop[i]
				if c.convex then
					local which = OUTER[c.din] and OUTER[c.din][c.dout]
					if which then
						local at = CORNER_AT[which]
						local x, y = c.x + at[1] * F, c.y + at[2] * F
						Lay(o, Take(o, "corner"), CORNER_UV[which], x, y, x + F, y + F)
					end
				else
					local across = (c.din == "left" or c.din == "right") and c.din or c.dout
					local hs = SideOf(across)
					local vs = SideOf(across == c.din and c.dout or c.din)
					if hs and vs then
						-- (its square along the run in, back towards the corner
						-- before, and along the run out: the feather, or less
						-- on a short run -- Reach)
						local p, n = loop[(i - 2) % m + 1], loop[i % m + 1]
						local rin = Reach(F, abs(c.x - p.x) + abs(c.y - p.y), p)
						local rout = Reach(F, abs(n.x - c.x) + abs(n.y - c.y), n)
						local w, h = rout, rin
						if across == c.din then
							w, h = rin, rout
						end
						local x0 = vs == "left" and c.x - w or c.x
						local y0 = hs == "bottom" and c.y - h or c.y
						-- (the row's edge keeps the half on the corner's row, the
						-- column's the other)
						local half = (hs == "bottom" and "T" or "B") .. (vs == "left" and "L" or "R")
						Mitre(o, hs, half, x0, y0, w, h)
						Mitre(o, vs, MITRE_TWIN[half], x0, y0, w, h)
					end
				end
			end
		end
	end

	-- the textures this shape uses shown (while the outline is), the rest hidden
	local function Finish(o)
		local shown = o.shown
		for _, kind in ipairs(KINDS) do
			local pool = o.pools[kind]
			for i = 1, #pool do
				pool[i]:SetShown(shown and i <= pool.used)
			end
		end
	end

	function Out:SetShape(shape, fill, s, ox, oy)
		s, ox, oy = Num(s), Num(ox), Num(oy)
		local pools = self.pools
		for _, kind in ipairs(KINDS) do
			pools[kind].used = 0
		end
		if type(shape) == "table" and type(shape.loops) == "table" and s and s > 0 and ox and oy then
			if type(fill) ~= "table" then
				fill = MelloUI.Outline.Fill(shape)
			end
			self.shape, self.fill, self.s, self.ox, self.oy = shape, fill, s, ox, oy
			Draw(self, shape, fill, self.feather * s)
		else
			self.shape, self.fill = nil, nil
		end
		Finish(self)
	end

	function Out:SetShown(on)
		self.shown = on and true or false
		Finish(self)
	end

	function Out:IsShown()
		return self.shown
	end

	function Out:SetColour(key)
		self.colour = type(key) == "string" and key or DEFAULT_COLOUR
		self:Paint()
	end

	function Out:SetStrength(alpha)
		alpha = Num(alpha)
		if not alpha then
			return
		end
		self.alpha = alpha < 0 and 0 or (alpha > 1 and 1 or alpha)
		self:Paint()
	end

	function Out:SetFeather(width)
		width = Num(width)
		if not width or width < 0 then
			return
		end
		self.feather = width
		if self.shape then
			self:SetShape(self.shape, self.fill, self.s, self.ox, self.oy)
		end
	end

	function Shade:Outline(parent, opts)
		if type(parent) ~= "table" or not parent.CreateTexture then
			return nil
		end
		if type(opts) ~= "table" then
			opts = NO_OPTIONS
		end
		local layer, sublevel = Layer(opts, 0)
		local o = setmetatable({
			parent = parent, layer = layer, sublevel = sublevel,
			colour = type(opts.colour) == "string" and opts.colour or DEFAULT_COLOUR,
			alpha = Num(opts.alpha) or DEFAULT_ALPHA,
			feather = Num(opts.feather) or DEFAULT_FEATHER,
			shown = true,
			pools = { fill = { used = 0 }, side = { used = 0 }, corner = { used = 0 }, mitre = { used = 0 } },
			masks = {},   -- [i] = the mitre pool's i-th texture's mask
		}, OutMeta)
		outlines[o] = true
		Listen()
		return o
	end
end

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
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
MelloUI.Perf:Scope("Shade")   -- this file's load time (/melloperf load); it sets no script or timer

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

local bands = setmetatable({}, { __mode = "k" })   -- every band made, for the repaint
local listening = false
local NO_OPTIONS = {}

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
	-- a layer or sublevel the game does not take would make CreateTexture
	-- raise: an unknown layer is BACKGROUND, the sublevel kept in -8..7
	local layer = type(opts.layer) == "string" and LAYERS[opts.layer] and opts.layer or "BACKGROUND"
	local sublevel = math.floor(Num(opts.sublevel) or 0)
	if sublevel < -8 then
		sublevel = -8
	elseif sublevel > 7 then
		sublevel = 7
	end
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
	if not listening then
		listening = true
		MelloUI:On("palette", Repaint, "Shade")
	end
	return band
end

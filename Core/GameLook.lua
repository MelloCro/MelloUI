--------------------------------------------------------------------------------
-- MelloUI - the look of MelloUI's own parts (0.17.1; docs/plans/game-look.md,
-- the sketch the user approved: docs/plans/next-update-refs/gamelook.jpg)
--
-- The user, 2026-10-01: "when people choose to play with the reskin off, the
-- widget looks is not fit for it, neither is the DPS Meter, that needs to
-- addapt and be fitting with the default UI aswell, chaning to reskin only
-- when the reskin is enabled, that should follow all the features".
--
-- ONE dispatcher for every part MelloUI draws of its own (the widget column
-- and its widgets, Voice Over's, the reminder widget, the damage meter's
-- parts, Combat Text, Gains, the notices, threat, Services, Route's marks,
-- Restock, the swing timers, the own windows). A feature asks MelloUI.Look
-- for a piece and gets MelloUI's painted one while its look area is on (the
-- reskin), the GAME's own while it is off: the game's art (atlases and files
-- by name, the client's own), its font OBJECTS (so whatever the player or
-- another addon sets for the game's fonts carries over) and its colours. A
-- piece swaps by itself, in place, when the area changes (its 'look:<area>'
-- topic): the feature never branches on the look, and makes nothing for the
-- look it does not show (the game's pieces at their first need).
--
-- The area: "own" (Modules/Kit.lua's Kit.Areas, on with the reskin) unless a
-- piece names another (the windows: "config"; the swing timers: the cast
-- bars' "castbar").
--
--   Look:On([area]) -> true while the painted look shows
--   Look.Text(fs, role[, size[, opts]])
--       the string's font and colour in the role:
--         "text"    the palette's text / the game's white (GameFontHighlight,
--                   GameFontHighlightSmall at 11 or less)
--         "title"   the palette's text / the game's gold (GameFontNormal(Small))
--         "gold"    the palette's selected trim / the game's gold
--         "muted"   the palette's muted text / the game's grey
--         "number"  the palette's selected trim in the chat face / the game's
--                   NumberFontNormal, white
--         "note"    the palette's text / the game's grey small (a time, a hint)
--         "value"   the palette's selected trim / the game's white (a number)
--       size: the painted size (the game's objects keep theirs); opts (read
--       once, kept): key (another palette key for the painted look), font
--       (another font role than fontText), alpha, area
--   Look.Colour(fs, colour)   a meaning colour ({ r, g, b } or a ColorMixin)
--       on a string Look.Text styles: kept over a look switch (nil: the
--       role's own again)
--   Look.Plate(parent, opts) -> plate
--       the plate behind a block of text: the soft shade band (Shade:Band,
--       with opts) painted; the game's tooltip frame (TooltipDefaultLayout's
--       pieces in its navy, as regions of `parent` round the region) in the
--       game's look. plate:Anchor(region[, padX, padY]), plate:SetShown(on),
--       plate:IsShown(), plate:SetStrength(alpha) -- the band's own API
--   Look.Hide(region[, area])   a purely painted region (a glow, a disc): it
--       shows only in the painted look; region:SetShown asks go through
--       Look.Show(region, on)
--   Look.Show(region, on)      shown when asked AND the painted look shows
--       (a region Look.Hide took), else as asked
--   Look.Art(key) -> kind, name   the game's art table (the checks' list)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("GameLook")
local Secret = MelloUI.Safe.IsSecret

local Look = { AREA = "own" }
MelloUI.Look = Look

-- the game's art, by its name in the client's own tables (the tests check
-- each against the cached UiTextureAtlasMember table and the listfile)
Look.ART = {
	tooltipCornerTL = { "atlas", "Tooltip-NineSlice-CornerTopLeft" },
	tooltipCornerTR = { "atlas", "Tooltip-NineSlice-CornerTopRight" },
	tooltipCornerBL = { "atlas", "Tooltip-NineSlice-CornerBottomLeft" },
	tooltipCornerBR = { "atlas", "Tooltip-NineSlice-CornerBottomRight" },
	tooltipEdgeTop = { "atlas", "_Tooltip-NineSlice-EdgeTop" },
	tooltipEdgeBottom = { "atlas", "_Tooltip-NineSlice-EdgeBottom" },
	tooltipEdgeLeft = { "atlas", "!Tooltip-NineSlice-EdgeLeft" },
	tooltipEdgeRight = { "atlas", "!Tooltip-NineSlice-EdgeRight" },
	tooltipCenter = { "atlas", "Tooltip-NineSlice-Center" },
	ring = { "file", "Interface\\Minimap\\MiniMap-TrackingBorder" },
	roundMask = { "file", "Interface\\CharacterFrame\\TempPortraitAlphaMask" },
	barFill = { "atlas", "UI-HUD-CoolDownManager-Bar" },
	barBack = { "atlas", "ui-damagemeters-bar-shadowbg" },
	barEdge = { "atlas", "ui-damagemeters-bar-shadowedge" },
}

function Look.Art(key)
	local a = Look.ART[key]
	if a then
		return a[1], a[2]
	end
	return nil
end

-- the text roles: the painted look's palette key and font role, the game's
-- font objects (normal, small) and colour (a global ColorMixin)
local ROLE = {
	text = { key = "text", font = "fontText", normal = "GameFontHighlight", small = "GameFontHighlightSmall",
		colour = "HIGHLIGHT_FONT_COLOR" },
	title = { key = "text", font = "fontText", normal = "GameFontNormal", small = "GameFontNormalSmall",
		colour = "NORMAL_FONT_COLOR" },
	gold = { key = "selectedTrim", font = "fontText", normal = "GameFontNormal", small = "GameFontNormalSmall",
		colour = "NORMAL_FONT_COLOR" },
	muted = { key = "mutedText", font = "fontText", normal = "GameFontDisable", small = "GameFontDisableSmall",
		colour = "GRAY_FONT_COLOR" },
	number = { key = "selectedTrim", font = "fontChat", object = "NumberFontNormalSmall", normal = "NumberFontNormal",
		small = "NumberFontNormal", colour = "HIGHLIGHT_FONT_COLOR" },
	note = { key = "text", font = "fontText", normal = "GameFontDisableSmall", small = "GameFontDisableSmall",
		colour = "GRAY_FONT_COLOR" },
	value = { key = "selectedTrim", font = "fontText", normal = "GameFontHighlight", small = "GameFontHighlightSmall",
		colour = "HIGHLIGHT_FONT_COLOR" },
}
local PAINTED_OBJECT = "GameFontHighlight"
local SMALL = 11   -- a painted size at or under it: the game's small object

--------------------------------------------------------------------------------
-- The areas and the pieces that follow them
--------------------------------------------------------------------------------

local weak = { __mode = "k" }
-- [area] = { [piece] = its apply function, or a list of them (a region that
-- is both painted and of one look only: a count's disc) } (weak keys)
local pieces = {}
local told = {}       -- [area] = the look its pieces show (true painted)

function Look:On(area)
	local Kit = MelloUI.Kit
	return (Kit and Kit.IsOn and Kit:IsOn(area or self.AREA)) and true or false
end

local function Refresh(area)
	local painted = Look:On(area)
	told[area] = painted
	local list = pieces[area]
	if not list then
		return
	end
	for piece, apply in pairs(list) do
		if type(apply) == "table" then
			for i = 1, #apply do
				apply[i](piece, painted)
			end
		else
			apply(piece, painted)
		end
	end
end

-- a piece kept and laid in the area's look now (its topic listened to from
-- the first piece of that area on)
local function Track(area, piece, apply)
	local list = pieces[area]
	if not list then
		list = setmetatable({}, weak)
		pieces[area] = list
		MelloUI:On("look:" .. area, Perf.Shared("'look:" .. area .. "' on the bus: MelloUI's own parts", function()
			Refresh(area)
		end), "Look " .. area)
	end
	local had = list[piece]
	if had == nil or had == apply then
		list[piece] = apply
	elseif type(had) == "table" then
		local found = false
		for i = 1, #had do
			found = found or had[i] == apply
		end
		if not found then
			had[#had + 1] = apply
		end
	else
		list[piece] = { had, apply }
	end
	apply(piece, Look:On(area))
end

local function GameColour(name)
	local c = _G[name]
	if type(c) == "table" then
		if c.GetRGB then
			return c:GetRGB()
		end
		return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1
	end
	return 1, 1, 1
end

local function RGB(c)
	if type(c) ~= "table" then
		return nil
	end
	if c.GetRGB then
		return c:GetRGB()
	end
	return c.r or c[1], c.g or c[2], c.b or c[3]
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

local texts = setmetatable({}, weak)   -- [fs] = { role, size, key, font, alpha, colour }

local function ApplyText(fs, painted)
	local e = texts[fs]
	if not e then
		return
	end
	local role = ROLE[e.role] or ROLE.text
	local W, Kit = MelloUI.Widgets, MelloUI.Kit
	if painted then
		local object = _G[role.object or PAINTED_OBJECT] or _G.GameFontHighlight
		if object then
			fs:SetFontObject(object)
			if MelloUI.StyleFont then
				MelloUI:StyleFont(fs, e.font or role.font, object, e.size)
			end
		end
		if e.colour then
			if Kit and Kit.Unpaint then
				Kit:Unpaint(fs, "text")
			end
			local r, g, b = RGB(e.colour)
			fs:SetTextColor(r or 1, g or 1, b or 1, e.alpha or 1)
		elseif W then
			W.Paint(fs, e.key or role.key, "text", e.alpha)
		end
		return
	end
	if Kit and Kit.Unpaint then
		Kit:Unpaint(fs, "text")
	end
	if MelloUI.StyleFont then
		MelloUI:StyleFont(fs, nil, nil)   -- (out of the font list: the game's object rules)
	end
	local size = e.size
	local name = (type(size) == "number" and not Secret(size) and size <= SMALL) and role.small or role.normal
	local object = _G[name] or _G[role.normal] or _G.GameFontHighlight
	if object then
		fs:SetFontObject(object)
	end
	local r, g, b
	if e.colour then
		r, g, b = RGB(e.colour)
	else
		r, g, b = GameColour(role.colour)
	end
	fs:SetTextColor(r or 1, g or 1, b or 1, e.alpha or 1)
end

function Look.Text(fs, role, size, opts)
	if type(fs) ~= "table" or not fs.SetTextColor then
		return
	end
	local e = texts[fs]
	if not e then
		e = {}
		texts[fs] = e
	end
	e.role, e.size = role or "text", size
	if opts then
		e.key, e.font, e.alpha = opts.key, opts.font, opts.alpha
	end
	e.area = opts and opts.area or Look.AREA
	Track(e.area, fs, ApplyText)
end

function Look.Colour(fs, colour)
	local e = texts[fs]
	if not e then
		return
	end
	e.colour = colour
	ApplyText(fs, told[e.area] ~= nil and told[e.area] or Look:On(e.area))
end

--------------------------------------------------------------------------------
-- Painted-only regions (a glow, the count's disc): shown only while painted
--------------------------------------------------------------------------------

local only = setmetatable({}, weak)   -- [region] = { asked = shown as asked, game = shown in the game's look, area }

local function ApplyOnly(region, painted)
	local e = only[region]
	if e then
		region:SetShown(e.asked and (painted ~= e.game))
	end
end

-- a region of one look only: "painted" (default) or "game"
function Look.Only(region, look, area)
	if type(region) ~= "table" or not region.SetShown then
		return
	end
	local e = only[region]
	if not e then
		local shown = region.IsShown and region:IsShown()
		e = { asked = (not Secret(shown)) and shown and true or false }
		only[region] = e
	end
	e.game = look == "game"
	e.area = area or Look.AREA
	Track(e.area, region, ApplyOnly)
end

function Look.Hide(region, area)
	Look.Only(region, "painted", area)
end

function Look.Show(region, on)
	local e = only[region]
	if not e then
		region:SetShown(on)
		return
	end
	e.asked = on and true or false
	ApplyOnly(region, told[e.area] ~= nil and told[e.area] or Look:On(e.area))
end

--------------------------------------------------------------------------------
-- The plate behind a block of text: the soft shade band painted, the game's
-- tooltip frame (TooltipDefaultLayout's nine pieces, the corners unique, the
-- edges tiled, the centre in TOOLTIP_DEFAULT_BACKGROUND_COLOR, laid as the
-- game's NineSlice lays them) as regions of the parent round the region:
-- under the parent's text (BACKGROUND and BORDER), over nothing of its own
--------------------------------------------------------------------------------

local Plate = {}
Plate.__index = Plate

-- the tooltip frame's pieces: [name] = { art key, layer, sublevel }
local PIECES = {
	{ "TopLeftCorner", "tooltipCornerTL" }, { "TopRightCorner", "tooltipCornerTR" },
	{ "BottomLeftCorner", "tooltipCornerBL" }, { "BottomRightCorner", "tooltipCornerBR" },
	{ "TopEdge", "tooltipEdgeTop" }, { "BottomEdge", "tooltipEdgeBottom" },
	{ "LeftEdge", "tooltipEdgeLeft" }, { "RightEdge", "tooltipEdgeRight" },
	{ "Center", "tooltipCenter" },
}

local function AtlasOn(tex, name)
	local api = _G.C_Texture
	local info = api and api.GetAtlasInfo and select(2, pcall(api.GetAtlasInfo, name))
	if type(info) == "table" then
		pcall(tex.SetHorizTile, tex, info.tilesHorizontally and true or false)
		pcall(tex.SetVertTile, tex, info.tilesVertically and true or false)
	end
	pcall(tex.SetAtlas, tex, name, true)
end

-- the game's frame, made at its first need: its pieces on the parent
local function GameFrame(p)
	local g = p.game
	if g then
		return g
	end
	g = {}
	local parent = p.parent
	for _, piece in ipairs(PIECES) do
		local layer = piece[1] == "Center" and "BACKGROUND" or "BORDER"
		local tex = parent:CreateTexture(nil, layer, nil, piece[1] == "Center" and -7 or -7)
		AtlasOn(tex, select(2, Look.Art(piece[2])))
		g[piece[1]] = tex
	end
	g.Center:SetVertexColor(GameColour("TOOLTIP_DEFAULT_BACKGROUND_COLOR"))
	p.game = g
	return g
end

-- the game frame round the region (the tooltip's own insets: its corners
-- at the region's corners grown by the pads)
local function LayGame(p)
	local g, region = p.game, p.region
	if not (g and region) then
		return
	end
	local x, y = p.padX or 0, p.padY or 0
	local right = p.right or region
	g.TopLeftCorner:ClearAllPoints()
	g.TopLeftCorner:SetPoint("TOPLEFT", region, "TOPLEFT", -x, y)
	g.TopRightCorner:ClearAllPoints()
	g.TopRightCorner:SetPoint("TOPRIGHT", right, "TOPRIGHT", x, y)
	g.BottomLeftCorner:ClearAllPoints()
	g.BottomLeftCorner:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", -x, -y)
	g.BottomRightCorner:ClearAllPoints()
	g.BottomRightCorner:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", x, -y)
	g.TopEdge:ClearAllPoints()
	g.TopEdge:SetPoint("TOPLEFT", g.TopLeftCorner, "TOPRIGHT")
	g.TopEdge:SetPoint("TOPRIGHT", g.TopRightCorner, "TOPLEFT")
	g.BottomEdge:ClearAllPoints()
	g.BottomEdge:SetPoint("BOTTOMLEFT", g.BottomLeftCorner, "BOTTOMRIGHT")
	g.BottomEdge:SetPoint("BOTTOMRIGHT", g.BottomRightCorner, "BOTTOMLEFT")
	g.LeftEdge:ClearAllPoints()
	g.LeftEdge:SetPoint("TOPLEFT", g.TopLeftCorner, "BOTTOMLEFT")
	g.LeftEdge:SetPoint("BOTTOMLEFT", g.BottomLeftCorner, "TOPLEFT")
	g.RightEdge:ClearAllPoints()
	g.RightEdge:SetPoint("TOPRIGHT", g.TopRightCorner, "BOTTOMRIGHT")
	g.RightEdge:SetPoint("BOTTOMRIGHT", g.BottomRightCorner, "TOPRIGHT")
	g.Center:ClearAllPoints()
	g.Center:SetPoint("TOPLEFT", g.TopLeftCorner, "BOTTOMRIGHT", -4, 4)
	g.Center:SetPoint("BOTTOMRIGHT", g.BottomRightCorner, "TOPLEFT", 4, -4)
end

local function GameShown(p, on)
	local g = p.game
	if g then
		for _, piece in ipairs(PIECES) do
			g[piece[1]]:SetShown(on)
		end
	end
end

local function ApplyPlate(p, painted)
	p.painted = painted
	if painted then
		if not p.band then
			p.band = MelloUI.Shade:Band(p.parent, p.bandOpts)
			if p.region then
				if p.right then
					p.band:Anchor(p.region, p.right, p.padX, p.padY)
				else
					p.band:Anchor(p.region, p.padX, p.padY)
				end
			end
		end
		p.band:SetShown(p.shown)
		if p.strength then
			p.band:SetStrength(p.strength)
		end
		GameShown(p, false)
	else
		GameFrame(p)
		LayGame(p)
		GameShown(p, p.shown)
		if p.band then
			p.band:SetShown(false)
		end
	end
end

function Plate:Anchor(region, a, b, c)
	-- (region, padX, padY) or (left, right, padX, padY), as the band's
	if type(a) == "table" then
		self.region, self.right, self.padX, self.padY = region, a, b, c
	else
		self.region, self.right, self.padX, self.padY = region, nil, a, b
	end
	if self.band then
		if self.right then
			self.band:Anchor(self.region, self.right, self.padX, self.padY)
		else
			self.band:Anchor(self.region, self.padX, self.padY)
		end
	end
	LayGame(self)
end

function Plate:SetShown(on)
	self.shown = on and true or false
	if self.painted then
		if self.band then
			self.band:SetShown(self.shown)
		end
	else
		GameShown(self, self.shown)
	end
end

function Plate:IsShown()
	return self.shown
end

function Plate:SetStrength(alpha)
	self.strength = alpha
	if self.painted and self.band then
		self.band:SetStrength(alpha)
	end
end

function Look.Plate(parent, opts)
	opts = opts or {}
	local p = setmetatable({ parent = parent, shown = true, area = opts.area or Look.AREA }, Plate)
	-- the band's options, as Shade:Band reads them (its region laid by Anchor)
	p.bandOpts = { colour = opts.colour, alpha = opts.alpha, feather = opts.feather, featherY = opts.featherY,
		layer = opts.layer, sublevel = opts.sublevel }
	if opts.region then
		p.region, p.padX, p.padY = opts.region, opts.padX, opts.padY
	end
	Track(p.area, p, ApplyPlate)
	return p
end

--------------------------------------------------------------------------------
-- A palette fill or tint, the game's neutral in its look: the dark grounds
-- black, the text white, the trims the game's gold, the muted grey
--------------------------------------------------------------------------------

local NEUTRAL = {
	mainWindow = "BLACK_FONT_COLOR", innerPanel = "BLACK_FONT_COLOR", raisedPanel = "BLACK_FONT_COLOR",
	border = "GRAY_FONT_COLOR", trim = "NORMAL_FONT_COLOR", selectedTrim = "NORMAL_FONT_COLOR",
	text = "HIGHLIGHT_FONT_COLOR", mutedText = "GRAY_FONT_COLOR", selectedTab = "RED_FONT_COLOR",
	hover = "HIGHLIGHT_FONT_COLOR",
}
local paints = setmetatable({}, weak)   -- [region] = { key, how, alpha, area }

local function ApplyPaint(region, painted)
	local e = paints[region]
	if not e then
		return
	end
	local W, Kit = MelloUI.Widgets, MelloUI.Kit
	if painted then
		if W then
			W.Paint(region, e.key, e.how, e.alpha)
		end
		return
	end
	if Kit and Kit.Unpaint then
		Kit:Unpaint(region, e.how)
	end
	local name = NEUTRAL[e.key] or "HIGHLIGHT_FONT_COLOR"
	local r, g, b = 0, 0, 0
	if name ~= "BLACK_FONT_COLOR" or _G.BLACK_FONT_COLOR then
		r, g, b = GameColour(name)
	end
	local a = e.alpha or 1
	if e.how == "vertex" then
		region:SetVertexColor(r, g, b, a)
	elseif e.how == "text" then
		region:SetTextColor(r, g, b, a)
	elseif e.how == "swipe" then
		region:SetSwipeColor(r, g, b, a)
	else
		region:SetColorTexture(r, g, b, a)
	end
end

-- a region Look.Paint took, let go (it shows a picture of its own again:
-- an icon in place of a glyph); its colour as it is
function Look.Unpaint(region)
	local e = paints[region]
	if not e then
		return
	end
	paints[region] = nil
	local list = pieces[e.area]
	local had = list and list[region]
	if had == ApplyPaint then
		list[region] = nil
	elseif type(had) == "table" then
		for i = #had, 1, -1 do
			if had[i] == ApplyPaint then
				table.remove(had, i)
			end
		end
	end
	local Kit = MelloUI.Kit
	if Kit and Kit.Unpaint then
		Kit:Unpaint(region, e.how)
	end
end

function Look.Paint(region, key, how, alpha, area)
	if type(region) ~= "table" then
		return
	end
	local e = paints[region]
	if not e then
		e = {}
		paints[region] = e
	end
	e.key, e.how, e.alpha, e.area = key, how or "fill", alpha, area or Look.AREA
	Track(e.area, region, ApplyPaint)
end

--------------------------------------------------------------------------------
-- A ring of time round a round icon (a Cooldown): the gold ring painted
-- (its own texture, a palette swipe, a track under it, round the face), the
-- game's own dark sweep over the icon itself in the game's look (the round
-- mask its swipe texture, no track)
--   Look.Ring(cd, opts) -> cd   opts (read once, kept): texture (the
--       painted ring's), face (the round icon: W.RoundIcon), size (the
--       painted ring's size), track (its track region, painted only)
--   Look.RingState(cd, state)    "run" (gold), "paused" (muted), "share"
--------------------------------------------------------------------------------

local rings = setmetatable({}, weak)   -- [cd] = { texture, face, size, track, state, area }
local SWEEP = { run = 0.6, paused = 0.35, share = 0.6 }   -- the game's sweep's darkness by state

local function ApplyRing(cd, painted)
	local e = rings[cd]
	if not e then
		return
	end
	cd:ClearAllPoints()
	if painted then
		cd:SetSwipeTexture(e.texture)
		cd:SetSize(e.size, e.size)
		cd:SetPoint("CENTER", e.face, "CENTER", 0, 0)
		local W = MelloUI.Widgets
		if W then
			W.Paint(cd, e.state == "paused" and "mutedText" or "selectedTrim", "swipe")
		end
		if e.track then
			Look.Show(e.track, e.trackShown)
		end
		return
	end
	local Kit = MelloUI.Kit
	if Kit and Kit.Unpaint then
		Kit:Unpaint(cd, "swipe")
	end
	local _, mask = Look.Art("roundMask")
	cd:SetSwipeTexture(mask)
	cd:SetAllPoints(e.face.icon or e.face)
	cd:SetSwipeColor(0, 0, 0, SWEEP[e.state] or 0.6)
	if e.track then
		Look.Show(e.track, e.trackShown)
	end
end

function Look.Ring(cd, opts)
	local e = rings[cd] or {}
	rings[cd] = e
	e.texture, e.face, e.size, e.track, e.area = opts.texture, opts.face, opts.size, opts.track, opts.area or Look.AREA
	e.state = e.state or "run"
	if e.track then
		Look.Hide(e.track, e.area)
	end
	Track(e.area, cd, ApplyRing)
	return cd
end

function Look.RingState(cd, state, trackShown)
	local e = rings[cd]
	if not e then
		return
	end
	e.state, e.trackShown = state or "run", trackShown and true or false
	ApplyRing(cd, told[e.area] ~= nil and told[e.area] or Look:On(e.area))
end

--------------------------------------------------------------------------------
-- A count on a round icon: on its dark disc painted, the game's corner
-- number in its look (NumberFontNormal white at the icon's lower right, as
-- an action button's count)
--   Look.Count(fs, disc, face[, size])   Look.CountShown(fs, on)
--------------------------------------------------------------------------------

local counts = setmetatable({}, weak)   -- [fs] = { disc, face, shown, area }

local function ApplyCount(fs, painted)
	local e = counts[fs]
	if not e then
		return
	end
	fs:ClearAllPoints()
	if painted then
		fs:SetPoint("CENTER", e.disc, "CENTER", 0, 0)
	else
		fs:SetPoint("BOTTOMRIGHT", e.face.icon or e.face, "BOTTOMRIGHT", 2, -2)
	end
	Look.Show(e.disc, e.shown)
	fs:SetShown(e.shown)
end

function Look.Count(fs, disc, face, size)
	local e = counts[fs] or {}
	counts[fs] = e
	e.disc, e.face, e.area = disc, face, Look.AREA
	e.shown = e.shown or false
	Look.Text(fs, "number", size)
	Look.Hide(disc)
	Track(e.area, fs, ApplyCount)
end

function Look.CountShown(fs, on)
	local e = counts[fs]
	if not e then
		fs:SetShown(on)
		return
	end
	e.shown = on and true or false
	ApplyCount(fs, told[e.area] ~= nil and told[e.area] or Look:On(e.area))
end

--------------------------------------------------------------------------------
-- A whole frame's panel (a hover list, a tray): the flat fill and its edge
-- painted (the palette's inner panel, the trim), the game's tooltip frame
-- round the frame in its look
--   Look.Panel(frame[, opts]) -> panel   opts: alpha (the fill's, 0.92),
--       edge (the edge's palette key, "trim"), area
--------------------------------------------------------------------------------

local function ApplyPanel(p, painted)
	local W = MelloUI.Widgets
	if painted then
		if not p.fill and W then
			p.fill = W.Solid(p.frame, "BACKGROUND", "innerPanel", p.alpha or 0.92)
			p.fill:SetAllPoints(p.frame)
			p.edges = W.Edges and W.Edges(p.frame, p.edge or "trim") or nil
		end
		if p.fill then
			p.fill:Show()
		end
		for _, e in pairs(p.edges or {}) do
			if type(e) == "table" and e.Show then
				e:Show()
			end
		end
		GameShown(p, false)
		return
	end
	if p.fill then
		p.fill:Hide()
	end
	for _, e in pairs(p.edges or {}) do
		if type(e) == "table" and e.Hide then
			e:Hide()
		end
	end
	GameFrame(p)
	LayGame(p)
	GameShown(p, true)
end

function Look.Panel(frame, opts)
	opts = opts or {}
	local p = { frame = frame, parent = frame, region = frame, padX = 0, padY = 0, alpha = opts.alpha, edge = opts.edge,
		area = opts.area or Look.AREA }
	Track(p.area, p, ApplyPanel)
	return p
end

--------------------------------------------------------------------------------
-- A class's round picture: MelloUI's class medallion painted, the game's own
-- round class icon (UI-Classes-Circles at the class's coordinates) in its
-- look
--   Look.ClassIcon(tex, class, medallion[, area])   medallion: the painted
--       picture's path (the caller's: Meter.ClassIcon)
--------------------------------------------------------------------------------

local classIcons = setmetatable({}, weak)   -- [tex] = { class, medallion, area }
Look.ART.classCircles = { "file", "Interface\\TargetingFrame\\UI-Classes-Circles" }

local function ApplyClassIcon(tex, painted)
	local e = classIcons[tex]
	if not e then
		return
	end
	local coords = _G.CLASS_ICON_TCOORDS and e.class and _G.CLASS_ICON_TCOORDS[e.class]
	if painted or not coords then
		tex:SetTexture(e.medallion or "Interface\\Icons\\INV_Misc_QuestionMark")
		tex:SetTexCoord(0, 1, 0, 1)
		return
	end
	local _, file = Look.Art("classCircles")
	tex:SetTexture(file)
	tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
end

function Look.ClassIcon(tex, class, medallion, area)
	local e = classIcons[tex] or {}
	classIcons[tex] = e
	e.class = (not Secret(class) and type(class) == "string") and class or nil
	e.medallion, e.area = medallion, area or Look.AREA
	Track(e.area, tex, ApplyClassIcon)
end

--------------------------------------------------------------------------------
-- A feature's own part of a look switch (what no block covers: a texture
-- swapped for another, a kit piece enabled): fn(owner, painted) now and at
-- every switch of the area. The one place a feature names both looks.
--   Look.Watch(owner, fn[, area])
--------------------------------------------------------------------------------

function Look.Watch(owner, fn, area)
	Track(area or Look.AREA, owner, fn)
end

-- for /mello look dump and the tests: every piece by area and the look it shows
function Look.Pieces()
	return pieces, told
end


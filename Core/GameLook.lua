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
--         "heal"    the healing meaning's green / the game's green
--         "numberSmall"  the palette's text / the game's small outlined number
--         "picture"  (a colour only) the palette's gold / a game picture's own
--         "badge"    (a colour only) the palette's selected tab / black
--       opts: tint (another role's colour, in both looks: Look.Tint changes
--       it), outline (true: MelloUI's font styling outlined)
--       size: the painted size (the game's objects keep theirs); opts (read
--       once, kept): key (another palette key for the painted look), font
--       (another font role than fontText), alpha, area, object (the painted
--       look's base font object by name: GameFontHighlight)
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
--   (wave 2, each laid out at its own section below)
--   Look.Solid(parent, layer, key[, alpha])   W.Solid's twin
--   Look.Mark(tex, kind, key, alpha)   a list row's selection / hover mark
--   Look.Bar(fill, opts), Look.GameBar(fill, ground, on)   a bar or a share
--       line: the game's damage meter bar in its look
--   Look.ColumnButton(button, glyph, paintedOnly)   a button in the chat's
--       column: the game's column button in its look
--   (wave 3)
--   Look.Palette() -> the palette's keys as the look shows them (tooltips)
--   Look.Paint(region, key, "backdrop" | "border", alpha)   a backdrop: the
--       tooltip's own colours in the game's look
--   Look.GameSwing(track, fill, hand, on, height)   the game's swing bar
--   Look.Outline(asked), Look.Shadow(fs, alpha)   a text on the world: the
--       game's outline and black shadow in its look
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("GameLook")
-- (a handler wrapped once for the profiler: every Perf:Scope has it)
local Shared = Perf.Shared
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
	-- (wave 3) the game's navigation (its super-tracked frame) and map pin: Route's marks
	navIcon = { "atlas", "Navigation-Tracked-Icon" },
	navArrow = { "atlas", "Navigation-Tracked-Arrow" },
	mapPin = { "atlas", "Waypoint-MapPin-Tracked" },
	mapPinChat = { "atlas", "Waypoint-MapPin-ChatIcon" },   -- (wave 5: the Quest Tracker's followed quest)
	-- (0.18.5) the game's own rank icons for a rare and a rare elite (its plates' and
	-- target frame's, Blizzard_NamePlateClassificationFrame): the Rare Alert's crest
	rareMark = { "atlas", "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star" },
	rareEliteMark = { "atlas", "nameplates-icon-elite-silver" },
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
	-- (wave 2) healing: Combat Text's meaning green painted, the game's green
	heal = { meaning = "combatHeal", font = "fontText", normal = "GameFontHighlight", small = "GameFontHighlightSmall",
		colour = "GREEN_FONT_COLOR" },
	-- a small number on a game frame (the raid frames' meter number): the
	-- game's small outlined number font
	numberSmall = { key = "text", font = "fontText", normal = "NumberFontNormalSmall", small = "NumberFontNormalSmall",
		colour = "HIGHLIGHT_FONT_COLOR" },
	-- (wave 3) a picture of the game's tinted in the palette's gold painted, in
	-- its own colours in the game's look (Route's arrows)
	picture = { key = "selectedTrim", font = "fontText", normal = "GameFontHighlight", small = "GameFontHighlightSmall",
		colour = "HIGHLIGHT_FONT_COLOR" },
	-- (wave 4) a small word's plate (W.Tag: "New", "Recommended") -- the
	-- palette's selected tab painted, a dark plate under the game's gold
	badge = { key = "selectedTab", font = "fontText", normal = "GameFontHighlight", small = "GameFontHighlightSmall",
		colour = "BLACK_FONT_COLOR" },
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
	if not (Kit and Kit.IsOn) then
		return true   -- (no Kit to ask, before it loads: MelloUI's own look, the default)
	end
	return Kit:IsOn(area or self.AREA) and true or false
end

local gameFilled   -- (Look.Palette's: filled again after a switch)

local function Refresh(area)
	gameFilled = false
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
		MelloUI:On("look:" .. area, Shared("'look:" .. area .. "' on the bus: MelloUI's own parts", function()
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

-- a piece's apply taken out of an area it no longer follows (its area
-- changed: laid by the new area's switches only)
local function Untrack(area, piece, apply)
	local list = pieces[area]
	local had = list and list[piece]
	if had == apply then
		list[piece] = nil
	elseif type(had) == "table" then
		for i = #had, 1, -1 do
			if had[i] == apply then
				table.remove(had, i)
			end
		end
	end
end

-- a colour's three numbers, plain ones only (anything else: white)
local function Plain3(r, g, b)
	if type(r) == "number" and type(g) == "number" and type(b) == "number"
		and not (Secret(r) or Secret(g) or Secret(b)) then
		return r, g, b
	end
	return 1, 1, 1
end

local function GameColour(name)
	local c = rawget(_G, name)
	if type(c) == "table" then
		if type(c.GetRGB) == "function" then
			return Plain3(c:GetRGB())
		end
		return Plain3(c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1)
	end
	if name == "BLACK_FONT_COLOR" then
		return 0, 0, 0   -- (a client without it: black all the same)
	end
	return 1, 1, 1
end

-- a role's colour in a look: painted, its meaning colour or its palette
-- key's; the game's, its global colour
local function RoleRGB(role, painted)
	if painted then
		local c = role.meaning and MelloUI.Meaning and MelloUI.Meaning[role.meaning]
			or MelloUI.Palette[role.key or "text"]
		if c then
			return c[1], c[2], c[3]
		end
		return 1, 1, 1
	end
	return GameColour(role.colour)
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
	local tint = e.tint and ROLE[e.tint] or role
	local W, Kit = MelloUI.Widgets, MelloUI.Kit
	if painted then
		local object = _G[e.object or role.object or PAINTED_OBJECT] or _G.GameFontHighlight
		if object then
			fs:SetFontObject(object)
			if MelloUI.StyleFont then
				if e.outline then
					MelloUI:StyleFont(fs, e.font or role.font, object, e.size, "", true)
				else
					MelloUI:StyleFont(fs, e.font or role.font, object, e.size)
				end
			end
		end
		if e.colour or tint.meaning then
			if Kit and Kit.Unpaint then
				Kit:Unpaint(fs, "text")
			end
			local r, g, b
			if e.colour then
				r, g, b = RGB(e.colour)
			else
				r, g, b = RoleRGB(tint, true)
			end
			fs:SetTextColor(r or 1, g or 1, b or 1, e.alpha or 1)
		elseif W then
			W.Paint(fs, e.key or tint.key, "text", e.alpha)
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
		r, g, b = GameColour(tint.colour)
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
		e.key, e.font, e.alpha, e.outline, e.object = opts.key, opts.font, opts.alpha, opts.outline, opts.object
		if opts.tint then
			e.tint = opts.tint
		end
	end
	-- (its area as given, else as before, else MelloUI's own: a call without
	-- opts -- a font size laid again -- keeps the area an earlier one gave;
	-- review 2026-10-02)
	local area = opts and opts.area or e.area or Look.AREA
	if e.area and e.area ~= area then
		Untrack(e.area, fs, ApplyText)
	end
	e.area = area
	Track(area, fs, ApplyText)
end

-- a text's colour role, apart from its font's (Look.Text's opts.tint)
function Look.Tint(fs, tint)
	local e = texts[fs]
	if not e then
		Look.Text(fs, "text", nil, { tint = tint })   -- (tinted before its font was set: the text role's)
		return
	end
	if e.tint == tint then
		return   -- (a list laid again: nothing to change)
	end
	e.tint = tint
	ApplyText(fs, Look:On(e.area))
end

-- a role's colour as the look shows it now: r, g, b
function Look.RoleColour(role, area)
	return RoleRGB(ROLE[role] or ROLE.text, Look:On(area))
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

-- (wave 4) the game's inset (InsetFrameTemplate's NineSlice layout: the
-- thin inner border, its bottom corners 1 lower; its marble ground tiled
-- under it): the panels of MelloUI's own windows in the game's look
Look.ART.insetTL = { "atlas", "UI-Frame-InnerTopLeft" }
Look.ART.insetTR = { "atlas", "UI-Frame-InnerTopRight" }
Look.ART.insetBL = { "atlas", "UI-Frame-InnerBotLeftCorner" }
Look.ART.insetBR = { "atlas", "UI-Frame-InnerBotRight" }
Look.ART.insetTop = { "atlas", "_UI-Frame-InnerTopTile" }
Look.ART.insetBottom = { "atlas", "_UI-Frame-InnerBotTile" }
Look.ART.insetLeft = { "atlas", "!UI-Frame-InnerLeftTile" }
Look.ART.insetRight = { "atlas", "!UI-Frame-InnerRightTile" }
Look.ART.marble = { "file", "Interface\\FrameGeneral\\UI-Background-Marble" }
local INSET_PIECES = {
	{ "TopLeftCorner", "insetTL" }, { "TopRightCorner", "insetTR" },
	{ "BottomLeftCorner", "insetBL" }, { "BottomRightCorner", "insetBR" },
	{ "TopEdge", "insetTop" }, { "BottomEdge", "insetBottom" },
	{ "LeftEdge", "insetLeft" }, { "RightEdge", "insetRight" },
	{ "Center", "marble" },
}
-- [kind] = its pieces; the inset's ground is a file under the whole frame
local FRAME_PIECES = { tooltip = PIECES, inset = INSET_PIECES }

local function AtlasOn(tex, name)
	local api = _G.C_Texture
	local info = api and api.GetAtlasInfo and select(2, pcall(api.GetAtlasInfo, name))
	if type(info) == "table" then
		pcall(tex.SetHorizTile, tex, info.tilesHorizontally and true or false)
		pcall(tex.SetVertTile, tex, info.tilesVertically and true or false)
	end
	pcall(tex.SetAtlas, tex, name, true)
end

-- the game's frame, made at its first need: its pieces on the parent (the
-- tooltip's, or the inset's: p.kind)
local function GameFrame(p)
	local g = p.game
	if g then
		return g
	end
	g = {}
	local parent = p.parent
	local inset = p.kind == "inset"
	for _, piece in ipairs(FRAME_PIECES[p.kind] or PIECES) do
		local centre = piece[1] == "Center"
		local tex = parent:CreateTexture(nil, centre and "BACKGROUND" or "BORDER", nil, inset and -5 or -7)
		local kind, name = Look.Art(piece[2])
		if kind == "file" then
			tex:SetTexture(name, "REPEAT", "REPEAT")
			tex:SetHorizTile(true)
			tex:SetVertTile(true)
		else
			AtlasOn(tex, name)
		end
		g[piece[1]] = tex
	end
	if not inset then
		g.Center:SetVertexColor(GameColour("TOOLTIP_DEFAULT_BACKGROUND_COLOR"))
	end
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
	local low = p.kind == "inset" and 1 or 0   -- (the inset's bottom corners: 1 lower, as its layout)
	g.TopLeftCorner:ClearAllPoints()
	g.TopLeftCorner:SetPoint("TOPLEFT", region, "TOPLEFT", -x, y)
	g.TopRightCorner:ClearAllPoints()
	g.TopRightCorner:SetPoint("TOPRIGHT", right, "TOPRIGHT", x, y)
	g.BottomLeftCorner:ClearAllPoints()
	g.BottomLeftCorner:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", -x, -y - low)
	g.BottomRightCorner:ClearAllPoints()
	g.BottomRightCorner:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", x, -y - low)
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
	if p.kind == "inset" then
		g.Center:SetAllPoints(region)   -- (its ground under the whole inset, as the template's Bg)
	else
		g.Center:SetPoint("TOPLEFT", g.TopLeftCorner, "BOTTOMRIGHT", -4, 4)
		g.Center:SetPoint("BOTTOMRIGHT", g.BottomRightCorner, "TOPLEFT", 4, -4)
	end
end

local function GameShown(p, on)
	local g = p.game
	if g then
		for _, piece in ipairs(FRAME_PIECES[p.kind] or PIECES) do
			g[piece[1]]:SetShown(on)
		end
	end
end

-- (wave 4) the game's tooltip frame or inset round a whole frame, as
-- regions of it, made at the first call; not a tracked piece -- its owner
-- shows it in its look (the widget set's panels and trays)
--   Look.GameFrame(frame, kind) -> frame's set   kind "tooltip" | "inset"
--   Look.GameFrameShown(frame, kind, on)
local gameFrames = setmetatable({}, weak)   -- [frame] = { [kind] = p }

function Look.GameFrameShown(frame, kind, on)
	local byKind = gameFrames[frame]
	local p = byKind and byKind[kind]
	if not p then
		if not on then
			return
		end
		p = { parent = frame, region = frame, padX = 0, padY = 0, kind = kind }
		byKind = byKind or {}
		byKind[kind] = p
		gameFrames[frame] = byKind
		GameFrame(p)
		LayGame(p)
	end
	GameShown(p, on and true or false)
end

function Look.GameFrame(frame, kind)
	local byKind = gameFrames[frame]
	local p = byKind and byKind[kind]
	return p and p.game
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
	-- (wave 4: a selection in the game's gold, as its lists' highlights, not its red)
	text = "HIGHLIGHT_FONT_COLOR", mutedText = "GRAY_FONT_COLOR", selectedTab = "NORMAL_FONT_COLOR",
	-- (a hover a quiet grey lift, never the text's white: Edit Layout's lit
	-- plates; review 2026-10-02 -- the lists' hover is the game's own mark)
	hover = "GRAY_FONT_COLOR",
}
-- a backdrop's fill and edge in the game's look: the tooltip's own colours
local BACKDROP = { fill = "TOOLTIP_DEFAULT_BACKGROUND_COLOR", border = "TOOLTIP_DEFAULT_COLOR" }
local paints = setmetatable({}, weak)   -- [region] = { key, how, alpha, area }

local function ApplyPaint(region, painted)
	local e = paints[region]
	if not e then
		return
	end
	local Kit = MelloUI.Kit
	local role = ROLE[e.key]
	local r, g, b
	if painted then
		if role and role.meaning then
			if Kit and Kit.Unpaint then
				Kit:Unpaint(region, e.how)
			end
			r, g, b = RoleRGB(role, true)
		else
			-- (the palette's one registry: W.Paint's own call)
			if Kit and Kit.Paint then
				Kit:Paint(region, role and role.key or e.key, e.how, e.alpha)
			end
			return
		end
	else
		if Kit and Kit.Unpaint then
			Kit:Unpaint(region, e.how)
		end
		local name = role and role.colour or NEUTRAL[e.key] or "HIGHLIGHT_FONT_COLOR"
		if e.how == "backdrop" then
			name = BACKDROP.fill
		elseif e.how == "border" then
			name = BACKDROP.border
		end
		r, g, b = GameColour(name)
	end
	local a = e.alpha or 1
	if e.how == "vertex" then
		region:SetVertexColor(r, g, b, a)
	elseif e.how == "text" then
		region:SetTextColor(r, g, b, a)
	elseif e.how == "swipe" then
		region:SetSwipeColor(r, g, b, a)
	elseif e.how == "backdrop" then
		region:SetBackdropColor(r, g, b, a)
	elseif e.how == "border" then
		region:SetBackdropBorderColor(r, g, b, a)
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

-- (wave 3) the palette as the look shows it now, by its keys: MelloUI.Palette
-- painted, the game's neutral colours in its look (a tooltip's lines: read
-- when shown, never kept; wave 4: the one registry of palette colours,
-- Kit:Paint, reads its colours here, so every own window's flat part takes
-- the game's colours with the reskin off). The game's table filled once per
-- switch (its colours are the game's globals).
local gamePalette = {}   -- (gameFilled: declared with Refresh, which clears it)

function Look.Palette(area)
	if Look:On(area) then
		return MelloUI.Palette
	end
	if gameFilled then
		return gamePalette
	end
	gameFilled = true
	for key, name in pairs(NEUTRAL) do
		local t = gamePalette[key]
		if not t then
			t = {}
			gamePalette[key] = t
		end
		local r, g, b = GameColour(name)
		t[1], t[2], t[3] = r, g, b
		t.hex = string.format("%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
	end
	return gamePalette
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
-- (wave 2) A flat block (W.Solid's twin): the palette's key painted, the
-- game's neutral colour for it in its look (Look.Paint's)
--   Look.Solid(parent, layer, key[, alpha[, area]]) -> texture
--------------------------------------------------------------------------------

local WHITE = "Interface\\Buttons\\WHITE8x8"

function Look.Solid(parent, layer, key, alpha, area)
	local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
	tex:SetTexture(WHITE)
	Look.Paint(tex, key, "vertex", alpha or 1, area)
	return tex
end

--------------------------------------------------------------------------------
-- (wave 2) A list row's selection or hover mark: the palette's flat fill
-- painted (its key and alpha), the game's own list marks in its look (the
-- settings list's Options_List_Active and Options_List_Hover)
--   Look.Mark(tex, kind, key, alpha[, area])   kind "selected" or "hover"
--------------------------------------------------------------------------------

Look.ART.listActive = { "atlas", "Options_List_Active" }
Look.ART.listHover = { "atlas", "Options_List_Hover" }
local marks = setmetatable({}, weak)   -- [tex] = { kind, key, alpha, area }

local function ApplyMark(tex, painted)
	local e = marks[tex]
	if not e then
		return
	end
	local W, Kit = MelloUI.Widgets, MelloUI.Kit
	if painted then
		tex:SetTexture(WHITE)
		tex:SetTexCoord(0, 1, 0, 1)
		if W then
			W.Paint(tex, e.key, "vertex", e.alpha)
		end
		return
	end
	if Kit and Kit.Unpaint then
		Kit:Unpaint(tex, "vertex")
	end
	local _, atlas = Look.Art(e.kind == "hover" and "listHover" or "listActive")
	tex:SetAtlas(atlas, false, nil, true)   -- (resetTexCoords: no earlier crop kept on the mark)
	tex:SetVertexColor(1, 1, 1, 1)
end

function Look.Mark(tex, kind, key, alpha, area)
	if type(tex) ~= "table" then
		return
	end
	marks[tex] = { kind = kind, key = key, alpha = alpha, area = area or Look.AREA }
	Track(marks[tex].area, tex, ApplyMark)
end

--------------------------------------------------------------------------------
-- (wave 2) A bar or a share line, the fill a StatusBar or a plain texture:
-- painted as the feature made it (its flat fill, its track and outline); in
-- the game's look the game's damage meter bar: the fill the cooldown bar's
-- atlas (in the colour the feature gives it), the meter's dark ground under
-- it and its shadowed edge round it (made at the first game look), the
-- painted track and outline hidden
--   Look.Bar(fill, opts) -> fill   opts (read once, kept): track, outline
--       (painted regions), height (the fill's and the track's in the game's
--       look; the painted heights put back), texture (the painted fill's: a
--       path or a function giving one; WHITE8x8), area
--   Look.GameBar(fill, ground, on)   the game's bar art on `fill` (its
--       ground and edge on `ground`, else the fill), or off: the one place
--       it is made (the race bar's own switch uses it too)
--------------------------------------------------------------------------------

local gameBars = setmetatable({}, weak)   -- [fill] = { back, edge }

local function IsStatusBar(fill)
	local ok, kind = pcall(fill.GetObjectType, fill)
	return ok and kind == "StatusBar"
end

function Look.GameBar(fill, ground, on)
	local g = gameBars[fill]
	if not on then
		if g then
			g.back:Hide()
			g.edge:Hide()
		end
		return
	end
	local _, fillAtlas = Look.Art("barFill")
	local status = IsStatusBar(fill)
	if status then
		if not pcall(fill.SetStatusBarTexture, fill, fillAtlas) then
			fill:SetStatusBarTexture(WHITE)
		end
	else
		fill:SetAtlas(fillAtlas)
	end
	if not g then
		ground = ground or fill
		local host = status and fill or fill:GetParent()
		local back = host:CreateTexture(nil, "BACKGROUND")
		back:SetAtlas((select(2, Look.Art("barBack"))))
		back:SetAllPoints(ground)
		local edge = host:CreateTexture(nil, "OVERLAY")
		edge:SetAtlas((select(2, Look.Art("barEdge"))))
		edge:SetPoint("TOPLEFT", ground, "TOPLEFT", -2, 2)
		edge:SetPoint("BOTTOMRIGHT", ground, "BOTTOMRIGHT", 2, -2)
		g = { back = back, edge = edge }
		gameBars[fill] = g
	end
	g.back:Show()
	g.edge:Show()
end

-- the game's ground and edge of a bar (the tests, a dump)
function Look.GameBarParts(fill)
	local g = gameBars[fill]
	if g then
		return g.back, g.edge
	end
end

local bars = setmetatable({}, weak)   -- [fill] = { track, outline, height, texture, heights, area }

local function SetHeights(b, game)
	local fill, track = b.fill, b.track
	if not b.height then
		return
	end
	fill:SetHeight(game and b.height or b.fillH)
	if track then
		track:SetHeight(game and b.height or b.trackH)
	end
end

local function ApplyBar(fill, painted)
	local b = bars[fill]
	if not b then
		return
	end
	if painted then
		Look.GameBar(fill, nil, false)
		local t = b.texture
		if type(t) == "function" then
			t = t()
		end
		if IsStatusBar(fill) then
			fill:SetStatusBarTexture(t or WHITE)
		else
			fill:SetTexture(t or WHITE)
			fill:SetTexCoord(0, 1, 0, 1)
		end
		SetHeights(b, false)
		return
	end
	Look.GameBar(fill, b.track, true)
	SetHeights(b, true)
end

function Look.Bar(fill, opts)
	if type(fill) ~= "table" then
		return fill
	end
	opts = opts or {}
	local b = { fill = fill, track = opts.track, height = opts.height, texture = opts.texture,
		area = opts.area or Look.AREA }
	if b.height then
		b.fillH = fill:GetHeight()
		b.trackH = b.track and b.track:GetHeight()
	end
	bars[fill] = b
	if b.track then
		Look.Hide(b.track, b.area)
	end
	if opts.outline then
		Look.Hide(opts.outline, b.area)
	end
	Track(b.area, fill, ApplyBar)
	return fill
end

--------------------------------------------------------------------------------
-- (wave 2) A small round button of MelloUI's in the chat's button column
-- (Fight History's): its glyph on the palette's dark disc painted; the
-- game's own column button in its look (the channel button's plate,
-- chatframe-button-up, and its highlight; the glyph white on it). The look
-- of its neighbours: the area "chat" unless named
--   Look.ColumnButton(button, glyph, paintedOnly[, area])   paintedOnly: the
--       painted look's own regions (the disc, its hover), hidden in the game's
--------------------------------------------------------------------------------

Look.ART.chatButton = { "atlas", "chatframe-button-up" }
Look.ART.chatButtonHighlight = { "atlas", "chatframe-button-highlight" }
local CHAT_BUTTON = { 27, 26 }   -- (the plate atlas's own size)
local columnButtons = setmetatable({}, weak)   -- [button] = { plate, lit }

local function ApplyColumnButton(button, painted)
	local e = columnButtons[button]
	if not e then
		return
	end
	if not painted and not e.plate then
		local plate = button:CreateTexture(nil, "ARTWORK", nil, 0)
		plate:SetAtlas((select(2, Look.Art("chatButton"))))
		plate:SetSize(CHAT_BUTTON[1], CHAT_BUTTON[2])
		plate:SetPoint("CENTER")
		local lit = button:CreateTexture(nil, "HIGHLIGHT")
		lit:SetAtlas((select(2, Look.Art("chatButtonHighlight"))))
		lit:SetAllPoints(plate)
		e.plate, e.lit = plate, lit
	end
	if e.plate then
		e.plate:SetShown(not painted)
		e.lit:SetShown(not painted)
	end
end

function Look.ColumnButton(button, glyph, paintedOnly, area)
	area = area or "chat"
	columnButtons[button] = columnButtons[button] or {}
	for _, r in ipairs(paintedOnly or {}) do
		Look.Hide(r, area)
	end
	if glyph then
		Look.Paint(glyph, "text", "vertex", nil, area)
	end
	Track(area, button, ApplyColumnButton)
end

-- the game's plate of a column button (the tests)
function Look.ColumnButtonPlate(button)
	local e = columnButtons[button]
	return e and e.plate, e and e.lit
end

--------------------------------------------------------------------------------
-- (wave 3) A swing timer's track in the game's look: the game's own swing
-- timer bar (Blizzard_SwingTimer's template, its atlases by the names it
-- uses -- the atlas ELEMENT names; the client picks the classic "-2x-c60"
-- member itself, and SetAtlas finds no member name: the user, 2026-10-02,
-- "no border nor background" -- its dark ground and frame over
-- the whole track, the fill for the hand inset as the template's -- 5 and 4
-- on its 30 high frame, so of the track's height), the fill white (the
-- atlas has its colour). The fill's behaviour stays the feature's.
--   Look.GameSwing(track, fill, hand, on, height)   hand "main", "off" or
--       "ranged"; off: the game's parts hidden, the fill over the track
--   Look.GameSwingParts(track) -> ground, frame   (the tests)
--------------------------------------------------------------------------------

Look.ART.swingBack = { "atlas", "ui-swingtimerbar-background" }
Look.ART.swingFrame = { "atlas", "ui-swingtimerbar-frame" }
Look.ART.swingMain = { "atlas", "ui-swingtimerbar-filling-mainhand" }
Look.ART.swingOff = { "atlas", "ui-swingtimerbar-filling-offhand" }
Look.ART.swingRanged = { "atlas", "ui-swingtimerbar-filling-ranged" }
local SWING_FILL = { main = "swingMain", off = "swingOff", ranged = "swingRanged" }
local SWING_INSET_X, SWING_INSET_Y = 5 / 30, 4 / 30
local swings = setmetatable({}, weak)   -- [track] = { back, frame }

function Look.GameSwing(track, fill, hand, on, height)
	local g = swings[track]
	if not on then
		if g then
			g.back:Hide()
			g.frame:Hide()
		end
		fill:ClearAllPoints()
		fill:SetAllPoints(track)
		return
	end
	if not g then
		local back = track:CreateTexture(nil, "BACKGROUND")
		back:SetAtlas((select(2, Look.Art("swingBack"))))
		back:SetAllPoints(track)
		local frame = track:CreateTexture(nil, "BACKGROUND", nil, 1)
		frame:SetAtlas((select(2, Look.Art("swingFrame"))))
		frame:SetAllPoints(track)
		g = { back = back, frame = frame }
		swings[track] = g
	end
	g.back:Show()
	g.frame:Show()
	local h = (type(height) == "number" and not Secret(height)) and height or 10
	local ix, iy = h * SWING_INSET_X, h * SWING_INSET_Y
	fill:ClearAllPoints()
	fill:SetPoint("TOPLEFT", track, "TOPLEFT", ix, -iy)
	fill:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", -ix, iy)
	pcall(fill.SetStatusBarTexture, fill, (select(2, Look.Art(SWING_FILL[hand] or "swingMain"))))
	fill:SetStatusBarColor(1, 1, 1)
end

function Look.GameSwingParts(track)
	local g = swings[track]
	if g then
		return g.back, g.frame
	end
end

--------------------------------------------------------------------------------
-- (wave 3) A text of MelloUI's on the world, on no panel (the notice, Combat
-- Text's lines, Gains'): MelloUI's text look painted (the soft band behind
-- it, the palette's soft shadow, outlined only with Outlined Text); the
-- game's floating text in its look (no band, the game's black shadow and an
-- outline: the game's way to read a text on the world, as its zone text and
-- its combat numbers). Its band: Look.Hide(band), its show asks Look.Show.
-- The feature's restyle runs again at the switch (Look.Watch).
--   Look.Outline(asked[, area]) -> the outline a text on the world takes
--       now: `asked` (Outlined Text) painted, true in the game's look
--   Look.Shadow(fs, alpha[, area])   its shadow's colour now: the palette's
--       inner panel at `alpha` painted, black in the game's look
--------------------------------------------------------------------------------

function Look.Outline(asked, area)
	if Look:On(area) then
		return asked and true or false
	end
	return true
end

function Look.Shadow(fs, alpha, area)
	if Look:On(area) then
		local s = MelloUI.Palette.innerPanel
		fs:SetShadowColor(s[1], s[2], s[3], alpha or 1)
	else
		fs:SetShadowColor(0, 0, 0, 1)
	end
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


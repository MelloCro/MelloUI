--------------------------------------------------------------------------------
-- MelloUI - Minimap Panel
--
-- The minimap cluster dressed in the painted kit (Modules/Kit.lua) on the
-- game's own layout. This client (Blizzard_Minimap/Camelot/Skin.lua) draws a
-- round frame (UI-HUD-Minimap-Frame, 215 x 226) around the 198 px map, the
-- zone band (BorderTop, 175 x 16) above it with the tracking button on its
-- left. User's picks (kit_raw/minimap_catalog.png, 2026-09-21): R1 Z2.
--   R1  the frame → the portrait ring sized from the map's opening x 0.75
--       (user: a quarter smaller, the map untouched), its rim over the map's
--       edge, on a holder one level above the map; the band, its text, the
--       tracking button and the indicators raised above the ring
--   Z2  the zone band → the title plate, as the band's own regions (under
--       its text), standing on the ring's top rim as a title on a rail
--   the tracking button's round plate → the round rim; zoom in / out → the
--   kit's plus / minus. The calendar, mail, crafting-order, landing-page and
--   day / night dial pictures, the compass letters and MelloUI's Services bar
--   stay the game's.
-- Shape (user, 2026-09-23: "Square Minimap with a Square Border of my
-- choosing"): Round (the ring above) or Square: the map's mask a plain
-- square, the ring hidden and a square border of the kit round the map, its
-- inner edge on the map's edge (Square Border: the window frame with its gem
-- corners, the single rail, the heavy backdrop frame with red or iron gems,
-- or none). GetMinimapShape answers "SQUARE" meanwhile, for other addons'
-- minimap buttons.
-- Merge With Services (user, 2026-09-23: "merge the Header, Minimap and the
-- Services window into 1 thing, but there needs to be a border separating the
-- Minimap from the Services Window", example D): with the square shape and a
-- rail border (the window frame or the single rail), one frame runs round the
-- map and MelloUI's Services bar under it; a header plate named "Services"
-- lies between the two, on the frame's stone (with Services' one row of
-- groups the same rail, gem caps and name); the zone band rides
-- the frame's top rail as every window's title plate does (the red plate,
-- its caps' gems on the frame's top corners, which give way), the tracking
-- button and the calendar on its two caps. The game's anchors come back when
-- it is off.
-- The column under the minimap (the map, the Services bar, Route's distance
-- line; the Quest Tracker glued under it where nobody placed it) is one
-- contract kept here, on or off: M:ColumnSlot, M:ColumnRect, M:ColumnPart,
-- M:LayColumn and the bus's 'column' (below M:Relayout).
-- The map's size (0.15.0; user, 2026-09-28: the 150 % of the first load was
-- "far too big", and free Width and Height sliders instead of the scale):
-- this module's Width and Height, 198 x 198 by default (the game's map at
-- 100 %). The game's map stays SQUARE underneath, max(W, H) on a side (its
-- projection and the player's arrow want a square canvas), cropped to W x H
-- by a mask (Media/Textures/Masks/Minimap, the short side in 256ths of the
-- long one) with its hit rect inset to match; a plain frame of that size on
-- the map's middle, M:MapFrame(), is what the border, the zone band, the
-- clock, the Services row, Route's line and the Quest Tracker hang from.
-- Edit Mode's Size (the map's container's scale) is held at 100 % while
-- this module is on, so the border art and the buttons keep their size; a
-- Size a player had set became their Width and Height once. The container
-- takes the game's margins round the shown map and the cluster is laid
-- round it as the game lays it (Size, below), so Edit Mode's selection box
-- stays on the map. The Quest Tracker (Match The Minimap's Width) and
-- Services' row follow the map's width (M:ColumnWidth). Covers the Dark Mode
-- group "minimap". /mmdump [frames|reps].
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("MinimapPanel")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer
local Kit = MelloUI.Kit

-- Square Border: `prefix` a kit rail family laid as a nine-slice at `scale`
-- (x Kit.scale), `piece` one frame picture cut into nine (the action bars'
-- backdrop frame: its corner CORNER piece px); `preview` for the picker
local BORDERS = {
	{ value = "window", label = "Window frame", prefix = "window/frame", scale = 1, gem = true, piece = "window/frame_gem_tl" },
	{ value = "single", label = "Single rail", prefix = "window/single", scale = 1.6, piece = "window/single_tl" },
	{ value = "red", label = "Heavy, red gems", piece = "deco/barframe_red" },
	{ value = "iron", label = "Heavy, iron gems", piece = "deco/barframe_iron" },
	{ value = "none", label = "None" },
}
local BORDER = {}
for _, b in ipairs(BORDERS) do
	BORDER[b.value] = b
end
local SHAPES = {
	{ value = "round", label = "Round", piece = "window/portrait_ring" },
	{ value = "square", label = "Square", piece = "deco/barframe_iron" },
}
local CORNER = 40            -- piece px: a backdrop frame's corner square (as ActionBarPanel's)
local ROUND_MASK = "ui-hud-minimap-frame-generic-mask"   -- the game's (Blizzard_Minimap/Camelot/Skin.lua)
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
local HYBRID_ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local Num = MelloUI.Safe.Number

-- the map's Width and Height (0.15.0): the sliders' range and step, in UI
-- units; the game's map is 198 at 100 % (the range Edit Mode's Size had,
-- 50 - 200 %: every old Size is kept when taken over, Size.Migrate)
local MAP_BASE, MAP_MIN, MAP_MAX, MAP_STEP = 198, 98, 400, 2
local function MapSizeText(v)
	return tostring(math.floor(v + 0.5))
end

local M = MelloUI:RegisterModule("MinimapPanel", {
	title = "Minimap Kit",
	desc = "The minimap cluster dressed in the painted kit on the game's own layout.",
	window = { label = "Minimap", desc = "The minimap ring (or a square map in a border of your choosing), zone band and buttons in the kit.", tab = "HUD" },
	enabledByDefault = true,
	defaults = { shape = "round", squareBorder = "window", servicesMerge = true, width = MAP_BASE, height = MAP_BASE },
	-- the old Size taken over once (Size.Migrate): this machine's step, never
	-- in a profile
	keep = { "sizeMigrated" },
	options = {
		{ type = "dropdown", key = "shape", name = "Shape", values = SHAPES,
		  desc = "Round: the map in the painted ring. Square: the whole square map, in the border chosen below." },
		{ type = "dropdown", key = "squareBorder", name = "Square Border", values = BORDERS,
		  desc = "The border round the square map: the windows' frame with its gem corners, a single iron rail, the action bars' heavy frame with red or iron gems, or none. Both are chosen with pictures on Minimap > Minimap." },
		{ type = "toggle", key = "servicesMerge", name = "Merge With Services",
		  desc = "The square map, its zone header and the Services bar in one frame: the zone name on the frame's top rail, and under the map a divider rail named Services over the Services bar (with the row of group buttons, the clock beside the zone name). For the square shape with the window frame or the single rail." },
		{ type = "slider", key = "width", name = "Width", min = MAP_MIN, max = MAP_MAX, step = MAP_STEP, new = "0.15.0",
		  format = MapSizeText,
		  desc = "How wide the map is. The round map is as tall as it is wide, and its painted ring grows and shrinks with it. The square map's border and the zone name keep their size, the Services buttons too (smaller only on a map too narrow for them), and the Quest Tracker under the map follows its width. Edit Mode's minimap Size no longer sizes the map while the Minimap Kit is on." },
		{ type = "slider", key = "height", name = "Height", min = MAP_MIN, max = MAP_MAX, step = MAP_STEP, new = "0.15.0",
		  format = MapSizeText,
		  desc = "How tall the square map is (the round map takes its Width). The shorter side is at least half the longer one." },
	},
})

local skin = nil
local active = false

-- The column's shade (0.14.0, the UI shade's minimap area: Kit:ShadeElement,
-- Modules/KitShade.lua; user, 2026-09-26: outline pieces only). ONE element
-- for the whole column, rooted on the map: its shade frame, a child of the
-- map one level under it, draws every partner under the map, the ring, the
-- square frame, the band, the tracking button and the Services bar, and over
-- the world -- so a piece's inward shadow lies under the map or its rails
-- and only the outline's shade shows. The pieces: the ring (drawn at its own
-- size, not its kitScale), or the square border of each look (its rails'
-- nine with the gem corners; the heavy frames' eight cut parts, each the
-- same cut of the frame's shadow; None: the map's own square edge), the zone
-- band's plate and the tracking button's rim; never the divider rail or the
-- stones inside the frame.
-- Services adds its bar's box to the same element (Kit:ShadeElement(Minimap,
-- "minimap")). Made as the pieces are dressed; the switches, the strength
-- and the palette are KitShade's and Kit's. Partners drawn by another frame
-- are fitted again where the scales part (the merged band's SetScale, Edit
-- Mode's Size on the map's container): Kit:ShadowRefit, once a frame.
local Shade = { DRAWN = { drawn = true } }

function Shade.Element()
	if Shade.el == nil then
		local ok, el = false, nil
		if Kit.ShadeElement and Minimap then
			ok, el = pcall(Kit.ShadeElement, Kit, Minimap, "minimap")
		end
		Shade.el = (ok and type(el) == "table" and type(el.Add) == "function") and el or false
	end
	return Shade.el or nil
end

function Shade.Add(obj, opts)
	local el = obj and Shade.Element()
	if el then
		el:Add(obj, opts)
	end
end

-- a heavy frame's eight parts (Kit:CutNine's), each with the same cut of the
-- frame's shadow (piece px; its reach past the picture's outer sides only),
-- once: CutNine cuts them again at every lay
function Shade.Cut(parts, piece)
	local p = Kit:Piece(piece)
	if Shade.cut or not (p and p.w and p.h) then
		return
	end
	Shade.cut = true
	local c, w, h = CORNER, p.w, p.h
	local cuts = { tl = { 0, c, 0, c }, tr = { w - c, w, 0, c }, bl = { 0, c, h - c, h }, br = { w - c, w, h - c, h },
		t = { c, w - c, 0, c }, b = { c, w - c, h - c, h }, l = { 0, c, c, h - c }, r = { w - c, w, c, h - c } }
	for key, cut in pairs(cuts) do
		Shade.Add(parts[key], { cut = cut })
	end
end

-- the square map with no border ("None"): the map's own edge shaded, KitShade's
-- synthetic square on a plain frame over the map (in the map's container, as
-- the border frame; on the map's shown part, M:MapFrame), its partners shown
-- and hidden with it; made the first time that look shows
function Shade.Bare(show)
	local bare = skin and skin.bare
	if not show then
		if bare then
			bare:Hide()
		end
		return
	end
	if not bare then
		if not (skin and Shade.Element()) then
			return
		end
		bare = CreateFrame("Frame", nil, Minimap:GetParent() or MinimapCluster)
		bare:EnableMouse(false)
		skin.bare = bare
		Shade.Add(bare, { shape = "shade/square" })
	end
	local shown = M:MapFrame()
	if bare.on ~= shown then
		bare.on = shown
		bare:ClearAllPoints()
		bare:SetAllPoints(shown)
	end
	bare:Show()
end

-- the partners drawn by the shade frame fitted again next frame, where their
-- frames' scales parted
function Shade.Refit()
	if Shade.el and Kit.ShadowRefit then
		Kit:ShadowRefit(true)
	end
end

local function Replace(region, opts)
	if not region then
		return nil
	end
	local rep, key = Kit:Replace(region, opts)
	if not rep then
		if key then
			MelloUI:Notice("Minimap: no kit piece mapped for %s", tostring(key))
		end
		return nil
	end
	skin.reps[#skin.reps + 1] = rep
	if active then
		rep:Enable()
	end
	return rep
end

local function Build()
	if skin then
		return
	end
	skin = { reps = {} }
	local cluster = MinimapCluster
	local map = Minimap
	if not (cluster and map) then
		return
	end
	-- the ring (R1): the frame and its rotated-mode pointer / underlay faded,
	-- the ring on a holder at the cluster's level with its opening on the map
	-- the ring one level above the map (its rim lies over the map's edge at
	-- 0.75); the band, its text, the tracking button and the indicators are
	-- raised one level above the ring (they overlap its top), their game
	-- levels put back on disable. Every level here is kept as an OFFSET from
	-- the map's (user, 2026-09-26: the column and the Quest Tracker took
	-- turns on top): the cluster is toplevel, a click in it lifts the whole
	-- tree, and a level saved as a number put the band and its buttons back
	-- under the lifted map on the next re-skin.
	local ringLevel = map:GetFrameLevel() + 1
	if MinimapCompassTexture then
		local rep = Replace(MinimapCompassTexture, { as = "UI-HUD-Minimap-Frame", parent = cluster, rect = map, level = ringLevel - cluster:GetFrameLevel(),
			alsoFade = { MinimapCompassTextureUnderlay } })
		skin.ring = rep
		Shade.Add(rep, Shade.DRAWN)   -- (hidden with its holder: the square shape)
		if rep then
			local raised = {}
			for _, key in ipairs({ "BorderTop", "ZoneTextButton", "Tracking", "IndicatorFrame" }) do
				local f = cluster[key]
				if f then
					raised[#raised + 1] = { frame = f, offset = f:GetFrameLevel() - map:GetFrameLevel() }
				end
			end
			if GameTimeFrame then
				raised[#raised + 1] = { frame = GameTimeFrame, offset = GameTimeFrame:GetFrameLevel() - map:GetFrameLevel() }
			end
			rep.onEnable = function()
				local base = map:GetFrameLevel()
				for _, entry in ipairs(raised) do
					entry.frame:SetFrameLevel(base + math.max(2, entry.offset))
				end
			end
			rep.onDisable = function()
				local base = map:GetFrameLevel()
				for _, entry in ipairs(raised) do
					entry.frame:SetFrameLevel(math.max(0, base + entry.offset))
				end
			end
			if active then
				rep.onEnable()
			end
		end
	end
	-- the zone band (Z2): the nine-slice's textures faded, the plate as regions
	local band = cluster.BorderTop
	if band then
		local first, extra = nil, {}
		for _, region in ipairs({ band:GetRegions() }) do
			if region:GetObjectType() == "Texture" and not region.kitPiece then
				if first then
					extra[#extra + 1] = region
				else
					first = region
				end
			end
		end
		if first then
			local rep = Replace(first, { as = "MinimapZoneBand", rect = band, alsoFade = extra })
			skin.band = rep
			Shade.Add(rep)
			-- (no drag handle of its own: the minimap cluster is moved on its
			-- plate in Edit Layout, which covers the whole cluster)
			-- the zone text centred on the plate (user, 2026-09-21); the game's
			-- anchor (LEFT-justified in its button) put back on disable
			local text = MinimapZoneText
			if rep and text then
				local saved = { justify = text:GetJustifyH() }
				for i = 1, text:GetNumPoints() do
					saved[i] = { text:GetPoint(i) }
				end
				local enable = rep.onEnable
				rep.onEnable = function(...)
					if enable then
						enable(...)
					end
					text:ClearAllPoints()
					text:SetPoint("CENTER", band, "CENTER", 0, 0)
					text:SetJustifyH("CENTER")
					Kit:TitleFont(text, true)
				end
				rep.onDisable = function()
					Kit:TitleFont(text, false)
					text:ClearAllPoints()
					for _, pt in ipairs(saved) do
						if type(pt) == "table" then
							text:SetPoint(unpack(pt))
						end
					end
					text:SetJustifyH(saved.justify or "LEFT")
				end
				if active then
					rep.onEnable()
				end
			end
		end
	end
	-- the tracking button's plate, the zoom buttons
	local tracking = cluster.Tracking
	if tracking and tracking.Background then
		-- (its rim drawn square to the button's plate, not at its kitScale)
		Shade.Add(Replace(tracking.Background, { as = "ui-hud-minimap-button" }), Shade.DRAWN)
	end
	for _, entry in ipairs({ { map.ZoomIn, "ui-hud-minimap-zoom-in" }, { map.ZoomOut, "ui-hud-minimap-zoom-out" } }) do
		local button, key = entry[1], entry[2]
		if button and button.GetNormalTexture and button:GetNormalTexture() then
			Replace(button:GetNormalTexture(), { as = key, button = button,
				alsoFade = { button:GetPushedTexture(), button:GetHighlightTexture(), button:GetDisabledTexture() } })
		end
	end
end

--------------------------------------------------------------------------------
-- The map's size (0.15.0): Width x Height, a square map cropped
--------------------------------------------------------------------------------
-- The game draws the map on a square canvas (sized to anything else, its
-- terrain slides away from the player's arrow as it zooms). So the map stays
-- square, max(W, H) on a side (the round map: W), and a mask shows W x H of
-- it: a band across its middle, the short side in whole 256ths of the long
-- one (a file per step, Tools/make_minimap_masks.py; never under half: a
-- step under the sliders' 2 even at 400, so every step of Height shows), the
-- map's hit rect inset to the band, so a click on the hidden part goes
-- through to the world. The proxy (M:MapFrame) is the shown part: what
-- stands round the map hangs from it. The canvas sized, the picture is drawn
-- again by a zoom there and back (the game keeps drawing it at the old size
-- until the zoom changes: the map small in a corner).
-- Held while this module is on:
--   the container's scale at 1 (Edit Mode's Size; its SetScale hook, Hook
--   below), Size.editScale keeping Edit Mode's own, given back when off;
--   the container the game's margins round the shown map (its size less the
--   map's as the game laid them: 215 x 253 round 198), and the cluster laid
--   round its children as the game's layout frame lays it (LayCluster), so
--   Edit Mode's selection box is round the map and the game's own layout,
--   whenever it runs, finds the cluster as it is;
--   the zoom buttons and the day / night dial where they stood on the game's
--   map, in proportion to the shown part, the ring sized from it, and the
--   player's coordinates under its bottom.
-- The group finder's eye stays where Edit Mode puts it (an Edit Mode system:
-- Edit Mode owns its place; on the map's edge at 198, a player drags it in
-- Edit Mode for another size).
-- A size is set only when it differs from the frame's own (by more than
-- SLACK: the client keeps sizes as 32-bit floats); nothing runs a frame by
-- itself. Out of combat (Kit:WhenOutOfCombat): a frame anchored to the map
-- may be a protected one of another addon's.
local Size = {
	STEPS = 256,
	SLACK = 0.01,
	MASK = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Masks\\Minimap\\",
	-- the dial's centre from the map's at 100 % (Blizzard_Minimap/Camelot/
	-- Diel.lua: 63, 72 from the cluster's centre; the container hangs 10
	-- right of the cluster's top middle, 30 down, and the cluster laid round
	-- its children is 27 taller than it -- its bottom 3 under the cluster's,
	-- measured in game (Core/LayoutFit.lua's model): 53, 88.5 whatever the
	-- container's height); its place on the cluster, the game's (Diel.lua's
	-- AnchorX, AnchorY)
	DIAL_X = 53, DIAL_Y = 88.5, DIAL_HOME_X = 63, DIAL_HOME_Y = 72,
	masks = {},          -- [key] = a mask's path, made once
	bounds = {},         -- LayCluster's extents, reused
	file = nil,          -- the crop's mask, nil: the whole square
	home = nil,          -- the game's own, read before anything is changed (Size.Home)
	editScale = nil,     -- Edit Mode's Size (the container's scale) as the game last set it
	holding = false,     -- the container's scale is being set from here: its hook stands aside
	held = false,        -- this module's size is laid (Release puts the game's back)
	dialDirty = true,    -- the game placed the dial again (Edit Mode's Size): placed once more
	dialHeld = false,    -- the dial is placed from here (Size.Place)
	zoomHeld = false,    -- the zoom buttons too
	coordsHeld = false,  -- the player's coordinates too
}

-- two sizes the same to the client (it keeps them as 32-bit floats: 217.8
-- set reads back 217.8000030517578)
local function Same(a, b)
	return a ~= nil and b ~= nil and math.abs(a - b) <= Size.SLACK
end

-- the Width and Height asked for, each in the sliders' range (the round
-- map: W x W)
function Size.Wanted()
	local db = M.db
	local w = Num(db and db.width) or MAP_BASE
	local h = Num(db and db.height) or MAP_BASE
	w = math.min(MAP_MAX, math.max(MAP_MIN, w))
	h = math.min(MAP_MAX, math.max(MAP_MIN, h))
	if not (db and db.shape == "square") then
		h = w
	end
	return w, h
end

-- the canvas's side, the shown part's width and height, and the mask that
-- crops the canvas to it (nil: the whole square)
function Size.Crop(w, h)
	local s = math.max(w, h)
	local steps = Size.STEPS
	local n = math.floor(math.min(w, h) / s * steps + 0.5)
	n = math.max(steps / 2, math.min(steps, n))
	if n >= steps then
		return s, s, s, nil
	end
	local cut = s * n / steps
	local key = (w > h and "h" or "v") .. n
	local file = Size.masks[key]
	if not file then
		file = Size.MASK .. key
		Size.masks[key] = file
	end
	if w > h then
		return s, s, cut, file
	end
	return s, cut, s, file
end

-- a frame's size when it reads plainly
local function PlainSize(f)
	local ok, w, h = pcall(f.GetSize, f)
	return ok and Num(w) or nil, ok and Num(h) or nil
end

-- a frame's one point, `point` on the same point of the map, as the game
-- lays it: its offsets, else nil
local function OnPoint(b, map, point)
	local okN, n = false, nil
	if b and b.GetNumPoints then
		okN, n = pcall(b.GetNumPoints, b)
	end
	if not (okN and n == 1) then
		return nil
	end
	local p, rel, rp, x, y = b:GetPoint(1)
	x, y = Num(x), Num(y)
	if p == point and rp == point and rel == map and x and y then
		return x, y
	end
	return nil
end

-- The game's own, read once before anything here changes them: the map's
-- and the container's sizes (the container's margins round the map), the
-- zoom buttons' places on the map's middle, the player's coordinates under
-- its bottom (Minimap.xml: the container's PlayerCoords), the dial
function Size.Home(map, c)
	if Size.home then
		return Size.home
	end
	local home = { zoom = {} }
	local mw, mh = PlainSize(map)
	local cw, ch = PlainSize(c)
	home.mapW, home.mapH = (mw and mw > 0) and mw or MAP_BASE, (mh and mh > 0) and mh or MAP_BASE
	home.cw, home.ch = (cw and cw > 0) and cw or 215, (ch and ch > 0) and ch or 253
	home.padW, home.padH = math.max(0, home.cw - home.mapW), math.max(0, home.ch - home.mapH)
	for _, key in ipairs({ "ZoomIn", "ZoomOut", "ZoomHitArea" }) do
		local b = map[key]
		local x, y = OnPoint(b, map, "CENTER")
		if x then
			home.zoom[#home.zoom + 1] = { frame = b, x = x, y = y }
		end
	end
	local coords = c.PlayerCoords or map.PlayerCoords
	local x, y = OnPoint(coords, map, "BOTTOM")
	if x then
		home.coords = { frame = coords, x = x, y = y }
	end
	local dial = MinimapCluster and MinimapCluster.DielFrame
	if dial and dial.SetScale then
		home.dial = { frame = dial }
	end
	Size.home = home
	return home
end

-- The shown part: a plain frame on the map's middle, in the map's container
function Size.Proxy()
	local p = Size.proxy
	if not p then
		p = CreateFrame("Frame", nil, Minimap:GetParent() or MinimapCluster)
		p:EnableMouse(false)
		p.ignoreInLayout = true   -- (never part of a layout frame's size, as the kit's holders)
		p:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
		p:SetSize(MAP_BASE, MAP_BASE)
		Size.proxy = p
	end
	return p
end

-- What stands round the map hangs from this: the map's shown part while this
-- module holds its size, else the game's map itself
function M:MapFrame()
	local p = Size.proxy
	if active and Size.held and p then
		return p
	end
	return Minimap
end

-- The container's scale set to `to` from here; `keep`: its place on the
-- screen kept (the game anchors it by offsets over its scale: its
-- SetHeaderUnderneath)
function Size.Rescale(c, to, keep)
	local okS, from = pcall(c.GetScale, c)
	from = okS and Num(from) or nil
	if not (from and from > 0) or math.abs(from - to) < 1e-6 then
		return false
	end
	local p, rel, rp, x, y
	if keep then
		local okN, n = pcall(c.GetNumPoints, c)
		if okN and n == 1 then
			p, rel, rp, x, y = c:GetPoint(1)
			x, y = Num(x), Num(y)
		end
	end
	Size.holding = true
	c:SetScale(to)
	Size.holding = false
	if p and x and y then
		c:ClearAllPoints()
		c:SetPoint(p, rel, rp, x * from / to, y * from / to)
	end
	return true
end

-- a map's picture drawn again at its new size: a zoom there and back, now
-- and once more on the next frame (should the game take the new size only
-- when it draws)
function Size.Blink(map)
	local okZ, z = pcall(map.GetZoom, map)
	z = okZ and Num(z) or nil
	if not z then
		return
	end
	pcall(map.SetZoom, map, z > 0 and 0 or 1)
	pcall(map.SetZoom, map, z)
end

function Size.BlinkLater()
	if Minimap then
		Size.Blink(Minimap)
	end
end

function Size.Redraw(map)
	Size.Blink(map)
	if Kit.NextFrame then
		Kit:NextFrame("Minimap redraw", Size.BlinkLater)
	end
end

-- the extents of the cluster's layout children among `...` (LayCluster), in
-- the cluster's units at `es` (its effective scale)
function Size.Extents(c, es, ...)
	local b = Size.bounds
	local Secret = MelloUI.Safe.IsSecret
	for i = 1, select("#", ...) do
		local r = select(i, ...)
		local okV, shown = pcall(r.IsShown, r)
		shown = okV and not Secret(shown) and shown
		if (shown or r.includeAsLayoutChildWhenHidden) and not r.ignoreInLayout
			and (not c.ignoreAllChildren or r.includeInLayout) then
			-- (on the screen over the cluster's scale; the game's
			-- GetUnscaledFrameRect: an unreadable rect is 1, 1, 1, 1)
			local l, bo, r2, t = MelloUI.Safe.ScreenRect(r)
			if l then
				l, bo, r2, t = l / es, bo / es, r2 / es, t / es
			else
				l, bo, r2, t = 1, 1, 2, 2
			end
			b.L, b.R = b.L and math.min(b.L, l) or l, b.R and math.max(b.R, r2) or r2
			b.B, b.T = b.B and math.min(b.B, bo) or bo, b.T and math.max(b.T, t) or t
		end
	end
end

-- one side as the game's layout frame sizes it (LayoutFrame.lua GetSize)
local function LaidSide(desired, fixed, lo, hi)
	lo = Num(lo) or desired
	hi = math.max(Num(hi) or desired, lo)
	return Num(fixed) or math.min(math.max(desired, lo), hi)
end

-- The cluster laid round its shown children as the game's layout frame lays
-- it (Blizzard_SharedXML/LayoutFrame.lua ResizeLayoutMixin:Layout: from a 1
-- x 1 start, the extents of its children and regions not ignored in the
-- layout, plus its widthPadding / heightPadding), once the container took
-- its size here. Only its size is set: no field of the game's frames is
-- written and none of its layout code runs from here (run from an addon, it
-- would run tainted).
function Size.LayCluster()
	local c = MinimapCluster
	if not (c and c.SetSize and c.GetChildren) then
		return
	end
	local okE, es = pcall(c.GetEffectiveScale, c)
	es = okE and Num(es) or nil
	if not (es and es > 0) then
		return
	end
	local fw, fh = c.fixedWidth, c.fixedHeight
	if Num(fw) and Num(fh) then
		c:SetSize(fw, fh)
		return
	end
	c:SetSize(1, 1)
	local b = Size.bounds
	b.L, b.R, b.B, b.T = nil, nil, nil, nil
	Size.Extents(c, es, c:GetChildren())
	Size.Extents(c, es, c:GetRegions())
	local w, h = 1, 1
	if b.L then
		w = (b.R - b.L) + (Num(c.widthPadding) or 0)
		h = (b.T - b.B) + (Num(c.heightPadding) or 0)
	end
	c:SetSize(LaidSide(w, fw, c.minimumWidth, c.maximumWidth), LaidSide(h, fh, c.minimumHeight, c.maximumHeight))
end

-- the zoom buttons, the dial and the ring where they stood on the game's map,
-- in proportion to the shown part (cw x ch), the player's coordinates under
-- its bottom (the canvas's is lower on a wide map, s tall)
function Size.Place(home, cw, ch, s, force)
	local map = Minimap
	local kx, ky = cw / home.mapW, ch / home.mapH
	if force then
		-- (the game's own places untouched at the game's size)
		local moved = not (Same(cw, home.mapW) and Same(ch, home.mapH))
		if moved or Size.zoomHeld then
			Size.zoomHeld = moved
			for _, z in ipairs(home.zoom) do
				z.frame:ClearAllPoints()
				z.frame:SetPoint("CENTER", map, "CENTER", z.x * kx, z.y * ky)
			end
		end
		local coords = home.coords
		local cut = not Same(ch, s)
		if coords and (cut or Size.coordsHeld) then
			Size.coordsHeld = cut
			coords.frame:ClearAllPoints()
			coords.frame:SetPoint("BOTTOM", cut and Size.Proxy() or map, "BOTTOM", coords.x, coords.y)
		end
		local ring = skin and skin.ring
		local p = ring and ring.tex and ring.rule and Kit:Piece(ring.rule.piece)
		if p and p.w and p.open and p.open[3] > p.open[1] then
			local size = math.min(cw, ch) * p.w / (p.open[3] - p.open[1]) * (ring.rule.openingScale or 1)
			ring.tex:SetSize(size, size)
		end
	end
	-- the dial: the game's own while the map is at its own size and Edit
	-- Mode's Size at 100 % (nothing to follow), else taken over: at 100 %,
	-- on the shown part's corner
	local dial = home.dial
	local ek = Size.editScale
	if dial and (not (Same(cw, home.mapW) and Same(ch, home.mapH)) or (ek and math.abs(ek - 1) > 1e-6))
		and (force or Size.dialDirty or not Size.dialHeld) then
		Size.dialDirty, Size.dialHeld = false, true
		dial.frame:SetScale(1)
		dial.frame:ClearAllPoints()
		dial.frame:SetPoint("CENTER", map, "CENTER", Size.DIAL_X * kx, Size.DIAL_Y * ky)
	end
end

-- This module's size laid (Width x Height)
function Size.Apply()
	local map = Minimap
	local c = map and map:GetParent()
	if not (c and c ~= MinimapCluster and c.SetScale) then
		return
	end
	local home = Size.Home(map, c)
	-- Edit Mode's Size held at 100 % (a scale found here is the game's)
	local okS, k = pcall(c.GetScale, c)
	k = okS and Num(k) or nil
	if k and (Size.editScale == nil or math.abs(k - 1) > 1e-6) then
		Size.editScale = k
	end
	local moved = Size.Rescale(c, 1, true)
	local w, h = Size.Wanted()
	local s, cw, ch, file = Size.Crop(w, h)
	local mw, mh = PlainSize(map)
	if not (Same(mw, s) and Same(mh, s)) then
		map:SetSize(s, s)
		Size.Redraw(map)
	end
	Size.file = file
	local p = Size.Proxy()
	local force = not Size.held or cw ~= Size.cw or ch ~= Size.ch
	if force then
		Size.cw, Size.ch = cw, ch
		local ix, iy = (s - cw) / 2, (s - ch) / 2
		pcall(map.SetHitRectInsets, map, ix, ix, iy, iy)
		p:SetSize(cw, ch)
	end
	Size.held = true
	local pw, ph = PlainSize(c)
	if not (Same(pw, cw + home.padW) and Same(ph, ch + home.padH)) then
		c:SetSize(cw + home.padW, ch + home.padH)
		moved = true
	end
	Size.Place(home, cw, ch, s, force)
	if moved then
		Size.LayCluster()
	end
end

-- The game's own back (this module switched off)
function Size.Release()
	local map = Minimap
	local c = map and map:GetParent()
	local home = Size.home
	if not (Size.held and home and c) then
		return
	end
	Size.held, Size.cw, Size.ch, Size.file = false, nil, nil, nil
	local mw, mh = PlainSize(map)
	if not (Same(mw, home.mapW) and Same(mh, home.mapH)) then
		map:SetSize(home.mapW, home.mapH)
		Size.Redraw(map)
	end
	pcall(map.SetHitRectInsets, map, 0, 0, 0, 0)
	if Size.zoomHeld then
		Size.zoomHeld = false
		for _, z in ipairs(home.zoom) do
			z.frame:ClearAllPoints()
			z.frame:SetPoint("CENTER", map, "CENTER", z.x, z.y)
		end
	end
	local coords = home.coords
	if coords and Size.coordsHeld then
		Size.coordsHeld = false
		coords.frame:ClearAllPoints()
		coords.frame:SetPoint("BOTTOM", map, "BOTTOM", coords.x, coords.y)
	end
	-- the dial as the game places it for Edit Mode's Size (Camelot/Diel.lua's
	-- SetEditModeScale: its scale never under 1, its offsets from the
	-- cluster's centre shrunk below 100 %), that Size perhaps set while the
	-- dial was held here
	local dial = home.dial
	if dial and Size.dialHeld then
		local k = Size.editScale or 1
		local kk = math.min(1, k)
		dial.frame:SetScale(math.max(1, k))
		dial.frame:ClearAllPoints()
		dial.frame:SetPoint("CENTER", MinimapCluster, "CENTER", Size.DIAL_HOME_X * kk, Size.DIAL_HOME_Y * kk)
	end
	Size.dialDirty, Size.dialHeld = true, false
	c:SetSize(home.cw, home.ch)
	Size.Rescale(c, Size.editScale or 1, true)
	Size.LayCluster()
end

-- The size laid or put back, out of combat (a fight's: Size.Later, below,
-- when it is over)
function Size.Lay()
	if not (active or Size.held) then
		return
	end
	if InCombatLockdown() then
		Kit:WhenOutOfCombat(Size.Later, "Minimap size")
		return
	end
	if active then
		Size.Apply()
	else
		Size.Release()
	end
end

-- The Size MelloUI's own layout wrote, not the player: until 0.14.0 the
-- layout fit (Core/LayoutFit.lua F5m) set 150 %, or a 10 % step down to the
-- approved layout's 90 % on a smaller screen -- the map "far too big" (user,
-- 2026-09-28). So a whole 10 % step from 90 to 150 % while the Edit Mode
-- layout in use is MelloUI's own ("MelloUI", or "MelloUI 1920x1080" on
-- another screen; unreadable: while the installer or the reskin put it in,
-- UIModifications' layoutApplied). A player's own Size in MelloUI's layout
-- reads the same and is not kept: the map at its normal size then.
function Size.Fitted(k)
	local step = k * 10
	if k < 0.895 or k > 1.505 or math.abs(step - math.floor(step + 0.5)) > 0.01 then
		return false
	end
	local ok, state = pcall(MelloUI.EditModeState, MelloUI)
	local name = ok and type(state) == "table" and state.activeName or nil
	if type(name) == "string" then
		return name == "MelloUI" or name:find("^MelloUI %d+x%d+$") ~= nil
	end
	local umdb = MelloUI:GetModuleDB("UIModifications")
	return type(umdb) == "table" and umdb.layoutApplied == true
end

-- The old Size taken over once (0.15.0): until 0.14.0 the map's size was
-- Edit Mode's Size (the container's scale). A player who set a Size that is
-- not 100 % keeps the map's size on the screen: Width and Height 198 x Size,
-- on the sliders' steps (within a unit; whole units the client keeps exactly
-- in its 32-bit sizes, and the slider shows as they are). The Size
-- MelloUI's own layout wrote is not taken over (Size.Fitted). Once
-- (`sizeMigrated`, this machine's, never in a profile), and never after a
-- size of the player's own.
function Size.Migrate(k)
	local db = M.db
	if type(db) ~= "table" or db.sizeMigrated then
		return false
	end
	db.sizeMigrated = true
	k = Num(k)
	if not (k and k > 0) or math.abs(k - 1) < 0.005 or Size.Fitted(k) then
		return false
	end
	local v = MAP_MIN + math.floor((MAP_BASE * k - MAP_MIN) / MAP_STEP + 0.5) * MAP_STEP
	v = math.min(MAP_MAX, math.max(MAP_MIN, v))
	db.width, db.height = v, v
	return true
end

-- the container's scale as it reads now (the game's while this module has
-- not held it)
function Size.ContainerScale()
	local c = Minimap and Minimap:GetParent()
	if not (c and c ~= MinimapCluster and c.GetScale) then
		return nil
	end
	local ok, k = pcall(c.GetScale, c)
	return ok and Num(k) or nil
end

-- the login settled with nothing taken over yet: Edit Mode's layout is in,
-- its Size is the one the game last set (or found before it was held)
function Size.MigrateLate()
	if active and Size.Migrate(Size.editScale or Size.ContainerScale()) then
		-- a new size: laid as one set on the sliders -- the Services row as
		-- wide as the map, the frame round both (Size.Changed)
		Size.Changed()
	end
end

-- at the switch-on, before the size is held: a scale that is not 1 is Edit
-- Mode's (the game's own is 1 until Edit Mode's layout is in); after the
-- login, whatever it is; during it, 1 waits for Edit Mode (its SetScale
-- hook) or for the login to settle
function Size.Start()
	local db = M.db
	if type(db) ~= "table" or db.sizeMigrated then
		return
	end
	local k = Size.ContainerScale()
	if k and (math.abs(k - 1) > 1e-6 or not MelloUI:LoggingIn()) then
		Size.Migrate(k)
	else
		MelloUI:AfterLogin(Size.MigrateLate)
	end
end

--------------------------------------------------------------------------------
-- The square minimap
--------------------------------------------------------------------------------

local savedShapeFn = nil   -- another addon's GetMinimapShape, put back when round

local function SetMask(square)
	local map = Minimap
	if not map then
		return
	end
	-- (square: cropped to the Width x Height, Size.Crop)
	local file = square and (Size.file or SQUARE_MASK) or ROUND_MASK
	pcall(map.SetMaskTexture, map, file)
	-- a dungeon's own map (Blizzard_HybridMinimap) masks with a circle of its own
	local hybrid = _G.HybridMinimap
	if hybrid and hybrid.CircleMask then
		pcall(hybrid.CircleMask.SetTexture, hybrid.CircleMask, square and (Size.file or SQUARE_MASK) or HYBRID_ROUND_MASK)
	end
	if square then
		if not M.shapeFn then
			M.shapeFn = function() return "SQUARE" end
		end
		if _G.GetMinimapShape ~= M.shapeFn then
			savedShapeFn = _G.GetMinimapShape
			_G.GetMinimapShape = M.shapeFn
		end
	elseif M.shapeFn and _G.GetMinimapShape == M.shapeFn then
		_G.GetMinimapShape = savedShapeFn
		savedShapeFn = nil
	end
end

-- The square border's frame on the map, one level above it (the ring's place)
local function BorderFrame()
	if skin.square then
		return skin.square
	end
	-- in the map's own container (Edit Mode's Size scaled that, not the
	-- cluster: a frame on the cluster kept its size while the map grew --
	-- user, 2026-09-23: "using the Editmode scaling break the map size";
	-- held at 100 % since 0.15.0, the map sized by Width and Height)
	local f = CreateFrame("Frame", nil, Minimap:GetParent() or MinimapCluster)
	f:SetFrameLevel(Minimap:GetFrameLevel() + 1)
	f:EnableMouse(false)
	f.parts = {}
	for _, key in ipairs({ "tl", "t", "tr", "l", "r", "bl", "b", "br" }) do
		f.parts[key] = f:CreateTexture(nil, "ARTWORK")
	end
	f.nine = {}   -- [prefix] = a Kit:NineSlice skin, made on first use
	f:Hide()
	skin.square = f
	return f
end

-- How far a rail family's rails reach inward from their outer edge (the
-- opaque part's inner edge), per side (l, r, t, b), at `sc`
local function RailDepths(prefix, sc)
	local function Depth(name, inner)
		local p = Kit:Piece(name)
		if not (p and p.box) then
			return 0
		end
		local d = inner == "r" and p.box[3] or inner == "l" and (p.w - p.box[1]) or inner == "b" and p.box[4] or (p.h - p.box[2])
		return d * sc
	end
	return Depth(prefix .. "_l", "r"), Depth(prefix .. "_r", "l"), Depth(prefix .. "_t", "b"), Depth(prefix .. "_b", "t")
end

-- How far a rail family's bottom gem corners paint below the frame, in the
-- frame's units at `sc` (Kit:NineSlice sets each gem's canvas its overhang
-- past the frame's corner; the clear rows under its box give some of it
-- back): 0 without gem corners
local function GemReach(prefix, sc)
	local reach = 0
	for i = 1, 2 do
		local p = Kit:Piece(prefix .. (i == 1 and "_gem_bl" or "_gem_br"))
		if p and p.overhang and p.box and p.h then
			reach = math.max(reach, p.overhang - (p.h - p.box[4]))
		end
	end
	return reach * sc
end

-- (a frame picture cut into nine on the square frame: the kit's one cutter,
-- Kit:CutNine, since 0.14.0 -- this file and the action bars had a copy each;
-- it also cuts the parts' shade partners)

-- the merge's measures: the divider band's height (UI px: the header rail
-- stands in it, its opaque part 4 less, its gem caps a hair over the map's
-- edge; the bar under it, with either Button Layout); the cap gem, as
-- Kit:TitleOnRail's (tabs/top caps: the gem's centre from the outer end)
local DIVIDER_H = 26
local CAP_GEM_X = 48
-- the rail's ends kept clear of its gem caps: where the clock stood on the
-- Services plate, and where the name and Route's line stand on the rail
local RAIL_PAD = DIVIDER_H * 1.6

-- Whether the Services bar joins the square map's frame (Services asks too)
function M:WantsServices()
	if not (active and M.db and M.db.shape == "square" and M.db.servicesMerge ~= false) then
		return false
	end
	local b = BORDER[M.db.squareBorder or "window"]
	return b and b.prefix ~= nil or false
end

-- What Services says of its row under the map (the contract Services fills,
-- read at call time): `groups`, true while its buttons stand as ONE row of
-- groups (the merged frame's divider rail then shares its rail with Route's
-- distance line, its "Services" name kept, and the clock goes to the zone
-- band's right end), and the row's `height` in the
-- bar's own units (nil: the bar's own height). Services:ColumnRow() -> groups,
-- height; until Services has it: not groups, the bar's height.
local function ServicesRow()
	local services = MelloUI:GetModule("Services")
	if services and services.isEnabled and services.ColumnRow then
		local ok, groups, height = pcall(services.ColumnRow, services)
		if ok then
			height = MelloUI.Safe.Number(height)
			return groups == true, (height and height > 0) and height or nil
		end
	end
	return false, nil
end

-- the stone between the map and the merged bar: the band the divider's rail
-- stands in, the bar right under it (the "Services" name on the rail with
-- either Button Layout; over the row of groups it shares the rail with
-- Route's distance line: the same height)
function M:DividerHeight()
	return DIVIDER_H
end

-- the stone of the frame's family, under the divider and the bar
function M:BodyPiece()
	local b = BORDER[M.db and M.db.squareBorder or "window"]
	return (b and b.prefix or "window/frame") .. "_body"
end

local function ServicesBar()
	local bar = _G.MelloUIServicesBar
	if bar and bar:IsShown() then
		return bar
	end
	return nil
end

-- The divider: the frame's stone across the map's width under it, the header
-- rail on it (its gem caps at the ends) with "Services" in the title face
-- (with either Button Layout: LayoutDivider)
local function Divider(f)
	if skin.divider then
		return skin.divider
	end
	local d = CreateFrame("Frame", nil, f)
	d:SetFrameLevel(f:GetFrameLevel() + 1)
	d:EnableMouse(false)
	d.stone = d:CreateTexture(nil, "BACKGROUND")
	d.stone:SetAllPoints(d)
	local ok, plate = pcall(Kit.Strip, Kit, d, "lists/header", { scale = Kit.scale })
	d.plate = ok and plate or nil
	-- the name on a layer above the plate (the plate is a child frame of the
	-- divider and drew over the divider's own text)
	d.textLayer = CreateFrame("Frame", nil, d)
	d.textLayer:SetAllPoints(d)
	d.textLayer:SetFrameLevel(d:GetFrameLevel() + 4)
	d.text = d.textLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	d.text:SetText("Services")
	d:Hide()
	skin.divider = d
	return d
end

-- a region's width when it reads plainly, else `fallback`
local function PlainWidth(region, fallback)
	if not region then
		return fallback
	end
	local ok, w = pcall(region.GetWidth, region)
	w = ok and MelloUI.Safe.Number(w) or nil
	return (w and w > 0) and w or fallback
end

-- `groups`: Services' one row of groups (layout E; user, 2026-09-25: "it
-- does not have the separation line between the minimap and the services
-- tab"): the same rail with its two gem caps and its "Services" name
-- between the map and the row, the name sharing the rail with Route's
-- distance line (M.RailName; the clock is on the zone band then)
local function LayoutDivider(f, b, groups)
	local d = Divider(f)
	local map = M:MapFrame()
	d:ClearAllPoints()
	d:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, 0)
	d:SetPoint("TOPRIGHT", map, "BOTTOMRIGHT", 0, 0)
	d:SetHeight(DIVIDER_H)
	local piece = b.prefix .. "_body"
	if d.stone.kitName ~= piece then
		Kit:Apply(d.stone, piece)
	end
	Kit:Retile(d.stone)
	local plate = d.plate
	if plate then
		local h = DIVIDER_H - 4
		local yoff = plate.FitBox and plate:FitBox(h) or 0
		plate:ClearAllPoints()
		plate:SetPoint("LEFT", d, "LEFT", 0, yoff)
		plate:SetPoint("RIGHT", d, "RIGHT", 0, yoff)
		plate:SetHeight(plate.height)
		-- its caps where it is wider than the two (a width that reads
		-- secret leaves them as they are)
		local w = plate.FitCaps and PlainWidth(d, nil)
		if w then
			plate:FitCaps(w)
		end
	end
	-- the name always stands on the rail (user, 2026-09-26: "there should be
	-- text on top of it called Services"); over Services' row of groups it
	-- shares the rail with Route's distance line (M.RailName)
	d.shares = groups and true or false
	d.nameLeft = nil
	d.text:Show()
	Kit:TitleFont(d.text, true)
	M.RailName()
	d:Show()
end

-- The rail's name: centred while nothing is tracked (user, 2026-09-26: "if
-- nothing is tracked, it should only say Services, text anchored to the
-- middle"); at the rail's left end while Route's distance line stands at its
-- right end. Route calls this when its line shows or hides.
function M.RailName()
	local d = skin and skin.divider
	if not (d and d.text) then
		return
	end
	local route = MelloUI:GetModule("Route")
	local left = (d.shares and route and route.DistanceLineShown and route:DistanceLineShown()) and true or false
	if d.nameLeft == left then
		return
	end
	d.nameLeft = left
	d.text:ClearAllPoints()
	if left then
		d.text:SetPoint("LEFT", d, "LEFT", RAIL_PAD, 0)
	else
		d.text:SetPoint("CENTER", d, "CENTER", 0, 0)
	end
end

-- The zone band on the frame's top rail (merged) or back where the game put
-- it, with the tracking button, the calendar and the zone text's width;
-- `groups`: Services' one row of groups (ServicesRow), the clock on the
-- band
local function PlaceBand(merged, f, b, groups)
	local cluster = MinimapCluster
	local band = cluster and cluster.BorderTop
	local rep = skin.band
	if not band then
		return
	end
	local movers = { band, cluster.Tracking, _G.GameTimeFrame, _G.TimeManagerClockButton }
	if merged then
		if not skin.bandSaved then
			-- (a level as an offset from the map's: put back over a map a click
			-- in the toplevel cluster lifted meanwhile)
			local saved = {}
			local base = Minimap:GetFrameLevel()
			for i, frame in ipairs(movers) do
				if frame then
					local pts = {}
					for j = 1, frame:GetNumPoints() do
						pts[j] = { frame:GetPoint(j) }
					end
					saved[i] = { points = pts, w = frame:GetWidth(), scale = frame:GetScale(), offset = frame:GetFrameLevel() - base }
				end
			end
			saved.textWidth = MinimapZoneText and MinimapZoneText:GetWidth()
			skin.bandSaved = saved
		end
		-- each at the frame's (the map's) scale, one after the other (a
		-- button inside the band follows it; its own ratio is then 1)
		for i, frame in ipairs(movers) do
			if frame and skin.bandSaved[i] then
				local okE, fe = pcall(f.GetEffectiveScale, f)
				local okM, me = pcall(frame.GetEffectiveScale, frame)
				if okE and okM and fe and me and me > 0 then
					frame:SetScale(frame:GetScale() * fe / me)
				end
			end
		end
		local sc = Kit.scale * (b.scale or 1)
		local rail = Kit:Piece(b.prefix .. "_t")
		local middle = rail and rail.box and (rail.box[2] + rail.box[4]) / 2 * sc or 9
		-- the plate is 1.4 x the band (MinimapZoneBand): the band sized so the
		-- plate spans the frame, its caps' gems on the frame's top corners
		local strip = rep and rep.strip
		local ss = strip and strip.scale or Kit.scale
		local okW, fw = pcall(f.GetWidth, f)
		if not (okW and fw and not (issecretvalue and issecretvalue(fw)) and fw > 0) then
			return
		end
		local reach = CAP_GEM_X * ss - 20 * sc
		local plateW = fw + 2 * reach
		local bandW = plateW / 1.4
		band:ClearAllPoints()
		band:SetPoint("CENTER", f, "TOP", 0, -middle)
		band:SetWidth(bandW)
		if strip and strip.SetState then
			strip:SetState("open")
		end
		if rep and rep.Refit then
			rep:Refit()
		end
		-- the tracking button and the calendar on the caps' gems
		local over = bandW * 0.2
		local tracking, clock = cluster.Tracking, _G.GameTimeFrame
		if tracking then
			tracking:ClearAllPoints()
			tracking:SetPoint("CENTER", band, "LEFT", -over + CAP_GEM_X * ss, 0)
		end
		if clock then
			clock:ClearAllPoints()
			clock:SetPoint("CENTER", band, "RIGHT", over - CAP_GEM_X * ss, 0)
		end
		-- the clock on the Services plate's right end, clear of the header;
		-- with Services' one row of groups (layout E) on the zone band's
		-- right end, just inside the calendar, the zone name kept
		-- as far clear of it at both ends
		local timeButton = _G.TimeManagerClockButton
		local d = skin.divider
		if MinimapZoneText then
			if groups and timeButton then
				local margin = CAP_GEM_X * ss + PlainWidth(clock, 19) / 2 + 2 + PlainWidth(timeButton, 40) + 4
				MinimapZoneText:SetWidth(math.max(40, plateW - 2 * math.max(70 * ss, margin)))
			else
				MinimapZoneText:SetWidth(math.max(40, plateW - 2 * 70 * ss))
			end
		end
		if timeButton and groups then
			timeButton:ClearAllPoints()
			if clock then
				timeButton:SetPoint("RIGHT", clock, "LEFT", -2, 0)
			else
				timeButton:SetPoint("RIGHT", band, "RIGHT", over - CAP_GEM_X * ss, 0)
			end
			timeButton:SetFrameLevel(band:GetFrameLevel() + 2)
		elseif timeButton and d then
			timeButton:ClearAllPoints()
			timeButton:SetPoint("RIGHT", d, "RIGHT", -DIVIDER_H * 1.6, 0)
			timeButton:SetFrameLevel(d:GetFrameLevel() + 6)
		end
		skin.bandMerged = true
	elseif skin.bandMerged then
		local saved = skin.bandSaved or {}
		local base = Minimap:GetFrameLevel()
		for i, frame in ipairs(movers) do
			local entry = saved[i]
			if frame and entry then
				frame:ClearAllPoints()
				for _, pt in ipairs(entry.points) do
					frame:SetPoint(unpack(pt))
				end
				if i == 1 and entry.w then
					frame:SetWidth(entry.w)
				end
				if entry.scale then
					frame:SetScale(entry.scale)
				end
				if entry.offset then
					frame:SetFrameLevel(math.max(0, base + entry.offset))
				end
			end
		end
		if MinimapZoneText and saved.textWidth then
			MinimapZoneText:SetWidth(saved.textWidth)
		end
		local strip = rep and rep.strip
		if strip and strip.SetState then
			strip:SetState("title")
		end
		if rep and rep.Refit then
			rep:Refit()
		end
		skin.bandMerged = nil
		skin.bandSaved = nil
	end
end

local function LaySquare()
	local square = active and M.db and M.db.shape == "square"
	-- the map's Width and Height first (its crop is the square mask), or the
	-- game's size back
	Size.Lay()
	SetMask(square)
	if not skin then
		return
	end
	local ring = skin.ring
	if ring and ring.object then
		ring.object:SetShown(active and not square)
	end
	local f = BorderFrame()
	local b = BORDER[M.db and M.db.squareBorder or "window"] or BORDER.window
	local merged = square and M:WantsServices() and ServicesBar() ~= nil
	if not merged then
		PlaceBand(false)
		if skin.divider then
			skin.divider:Hide()
		end
	end
	-- (no border: the map's own edge takes the shade, Shade.Bare)
	Shade.Bare(square and b.value == "none")
	if not square or b.value == "none" then
		f:Hide()
		return
	end
	local map = M:MapFrame()
	for _, tex in pairs(f.parts) do
		tex:Hide()
	end
	for _, nine in pairs(f.nine) do
		nine:Hide()
	end
	local over = 1   -- UI px: the rail's inner edge just over the map's, no line of world between
	f:ClearAllPoints()
	if b.prefix then
		local sc = Kit.scale * b.scale
		local l, r, t, bo = RailDepths(b.prefix, sc)
		f:SetPoint("TOPLEFT", map, "TOPLEFT", -(l - over), t - over)
		if merged then
			-- down round the Services bar (as wide as the map, under it)
			f:SetPoint("BOTTOMRIGHT", ServicesBar(), "BOTTOMRIGHT", r - over, -(bo - over))
		else
			f:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", r - over, -(bo - over))
		end
		local nine = f.nine[b.prefix]
		if not nine then
			nine = Kit:NineSlice(f, { prefix = b.prefix, scale = sc, gems = false, body = false, corners = b.gem and "gem" or nil })
			f.nine[b.prefix] = nine
			Shade.Add(nine)   -- (its rails' nine and gem corners; hidden with it)
		end
		nine:Show()
		f.gemReach = b.gem and GemReach(b.prefix, sc) or 0
		-- merged: the zone band's caps take the top corners
		if nine.SetTopGems then
			nine:SetTopGems(not merged)
		end
		if merged then
			-- Services' one row of groups: the rail with its name, which
			-- shares it with Route's line, the clock on the band
			local groups = ServicesRow()
			LayoutDivider(f, b, groups)
			f:Show()
			PlaceBand(true, f, b, groups)
			return
		end
	else
		local p = Kit:Piece(b.piece)
		local k = Kit.scale
		local open = (p and p.open) or { 29, 34, 106, 97 }
		local w, h = p and p.w or 135, p and p.h or 130
		f:SetPoint("TOPLEFT", map, "TOPLEFT", -(open[1] * k - over), open[2] * k - over)
		f:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", (w - open[3]) * k - over, -((h - open[4]) * k - over))
		f.gemReach = 0   -- (the picture fills the frame)
		if not p or Kit:CutNine(f, f.parts, b.piece, k, CORNER, true) == false then
			f:Hide()
			return
		end
		Shade.Cut(f.parts, b.piece)
	end
	f:Show()
end

-- the Services bar laid out again, without calling back
local function ServicesLayout()
	local services = MelloUI:GetModule("Services")
	if services and services.isEnabled and services.LayoutForMinimap then
		services:LayoutForMinimap()
	end
end

-- the map's frame laid, then the column under it (below): what hangs from
-- it follows on the next frame
local function LayoutSquare()
	LaySquare()
	Shade.Refit()
	M:LayColumn()
end

local function Activate()
	if active then
		return
	end
	active = true
	Build()
	for _, rep in ipairs(skin.reps) do
		rep:Enable()
	end
	-- (the old Size taken over, once, before the size is held)
	Size.Start()
	LayoutSquare()
	Kit:Cover("minimap")
	-- the map's size and shape set: Services' row as wide as the map, its
	-- minimap button onto the map's edge (Services loads first and laid them
	-- on the game's round map at login)
	ServicesLayout()
end


local function Deactivate()
	if not active then
		return
	end
	active = false
	for _, rep in ipairs(skin.reps) do
		rep:Disable()
	end
	LayoutSquare()   -- the round mask, the game's size and shape answer back
	Kit:Uncover("minimap")
	ServicesLayout()   -- (the row and the minimap button back on the game's map)
end

-- the map's container scaled: laid out again on the next frame, once however
-- often it was scaled in this one (Edit Mode's Size slider dragged), with no
-- closure made per call
local function RelayoutNow()
	if active then
		M:Relayout()
	end
end
local function RelayoutSoon()
	if Kit.NextFrame then
		Kit:NextFrame("Minimap relayout", RelayoutNow)
	else
		C_Timer.After(0, RelayoutNow)
	end
end

-- Edit Mode set the container's scale (its Size: a layout put in, or its
-- slider): kept as Edit Mode's own, taken over once as the map's size
-- (Size.Migrate), and held at 1 while this module is on -- at once, before
-- the game anchors the container for the scale it finds (its
-- SetHeaderUnderneath, right after) and lays the cluster round it; the map
-- laid out again on the next frame (the dial, which the game placed for its
-- Size, placed again)
function Size.OnEditScale(c, scale)
	if Size.holding then
		return
	end
	scale = Num(scale)
	if scale and scale > 0 then
		Size.editScale = scale
	end
	if not active then
		return
	end
	Size.dialDirty = true
	local taken = Size.Migrate(scale)
	if scale and math.abs(scale - 1) > 1e-6 then
		Size.holding = true
		c:SetScale(1)
		Size.holding = false
	end
	if taken then
		-- the old Size taken over: a new size, laid as one set on the sliders
		-- (the Services row as wide as the map, the frame round both)
		if Kit.NextFrame then
			Kit:NextFrame("Minimap size", Size.Changed)
		else
			Size.Changed()
		end
	end
	RelayoutSoon()
end

local hooked = false
local function Hook()
	if hooked then
		return
	end
	hooked = true
	-- Edit Mode's Size scales the map's container: held at 1 while this
	-- module is on (the map's size is its Width and Height), the map laid
	-- out again (Size.OnEditScale)
	local container = Minimap and Minimap:GetParent()
	if container and container ~= MinimapCluster and container.SetScale then
		hooksecurefunc(container, "SetScale", Size.OnEditScale)
	end
	-- the UI Scale changed (user, 2026-09-24: "UI Scaling Break the UI"): the
	-- merged band and its buttons were scaled to the frame's EFFECTIVE scale
	-- (PlaceBand), measured at the old UI scale; laid out again with the rest
	if Kit.OnUIScaleChanged then
		Kit:OnUIScaleChanged(function(reason)
			if reason == "uiscale" and active then
				Kit:WhenOutOfCombat(function()
					if active then
						M:Relayout()
					end
				end)
			end
		end)
	end
	-- the game sets the round mask again when the minimap's rotation is
	-- switched (UpdateMinimapConfig); the square one after it
	if CVarCallbackRegistry and CVarCallbackRegistry.RegisterCallback then
		CVarCallbackRegistry:RegisterCallback("rotateMinimap", function()
			C_Timer.After(0, function()
				if active then
					LayoutSquare()
				end
			end)
		end, M)
	end
	-- a dungeon's own map, loaded on demand
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("ADDON_LOADED")
	Perf.SetScript(ev, "OnEvent", function(_, _, name)
		if name == "Blizzard_HybridMinimap" and active then
			LayoutSquare()
		end
	end)
end

function M:OnEnable(db)
	self.db = db
	Hook()
	if MinimapCluster then
		Activate()
	end
end

-- the Services bar joins or leaves the frame: it lays itself out first
local function LayoutWithServices()
	ServicesLayout()
	LayoutSquare()
end

-- the size laid once a fight is over (Size.Lay), then what follows it: the
-- Services row as wide as the map, the map's frame round both; and the same
-- for a new Width or Height, once a frame however often a slider moved in it
function Size.Later()
	Size.Lay()
	LayoutWithServices()
end
Size.Changed = Size.Later

-- Services calls this after laying its bar out (Edit Mode, its settings)
function M:Relayout()
	LayoutSquare()
end

--------------------------------------------------------------------------------
-- The column under the minimap (audit, 2026-09-24, rank 18; user, 2026-09-25:
-- "everything should be lined up and working flawlessly with one another").
-- One contract for what stands under the map, top to bottom: the map's block
-- (the map with its zone band; the square border round it, or the merged
-- frame that runs round the Services bar too), the Services bar while it
-- shows and is not merged into that frame, and Route's distance line. Kept
-- here whether this module is on or not (the minimap's column either way):
--   M:ColumnSlot(part)  where a part hangs its TOP from: region, its point,
--                       x, y ("services": the bar, "route": the distance line)
--   M:ColumnRect()      the stack on the screen, the distance line's slot
--                       included while Route keeps the line, and what is
--                       painted past the frames (the square frame's bottom
--                       gems, the ring, the game's own frame art while the
--                       kit is off, a band under the map): left, bottom,
--                       right, top in screen pixels; nil when a rect cannot
--                       be read plainly
--   M:LayColumn()       something in it changed: the bus's 'column' goes out
--                       on the next frame, once for everything of that frame
--   M:ColumnPart(part)  one part of the column of layout E (M.COLUMN_PARTS:
--                       "band", "map", "services", "route", "tracker": the
--                       parts, NOT their order) or "frame" (the painted
--                       frame round the map: the kit ring's opaque part, the
--                       square border): left, bottom, right, top on the
--                       screen; nil while it is not in the column or cannot
--                       be read plainly
--   M:ColumnOrder()     the parts shown, top to bottom as they stand now
--                       (sorted by their tops): the band over the map, or
--                       under it with Edit Mode's Header Underneath; Route's
--                       line 2 under the map, so over the Services row while
--                       the bar's distance leaves it room, else under the
--                       bar; the tracker last where nobody placed it
--   M:ColumnWidth()     map, line: the column's width on the screen (pixels)
--                       while this module is on; `map` the map's own (round:
--                       its diameter, square: its width; its Width and
--                       Height are this module's), `line` the width the
--                       frames line up to: the square border's frame
--                       (merged: the frame round the map and the Services
--                       bar) where it stands wider than the map, else the
--                       map's. The Quest Tracker takes `line` (Match The
--                       Minimap's Width). nil, nil while this module is off
--                       or the map cannot be read plainly
--   M:ColumnAnchor()    the Quest Tracker's glue (0.15.0): region, point,
--                       dy -- the frame it lines up with (`line` above), its
--                       BOTTOMRIGHT, and how far the column's bottom
--                       (M:ColumnRect) lies under that point, in screen
--                       pixels (0 or less). The tracker hangs its top right
--                       corner that far under it, so it moves with the map
--                       and takes its width. nil while this module is off or
--                       the column cannot be read plainly
--   M:MapFrame()        the map's shown part (its Width x Height) while this
--                       module holds its size, else the game's map: what
--                       hangs from the map hangs from this
--   M:ColumnSide([l, r]) "left" while the column (its painted frame, or the
--                       edges l, r already read from it) stands in the
--                       screen's left half, else "right"; nil when it cannot
--                       be read. What opens beside the column opens toward
--                       the screen's centre: Services' tray, the Auras rows
-- (A region's edges on the screen: MelloUI.Safe.ScreenRect, Core.lua, the
-- addon's one reader; the old M:ScreenRect alias went in 0.15.0.)
-- Services hangs its bar and Route its line from it; the Quest Tracker is
-- glued under its bottom where nobody placed it, and takes its width
-- (QuestTracker.lua). The map is never sized for it. The places
-- are the ones they had -- the bar under the map by its offset (by the
-- divider's height merged), the line 2 px under the map (inside the square
-- border and the merged frame too, as before) -- except that the line goes
-- under the bar where a bar offset leaves it no room, and merged over
-- Services' row of groups it stands at the divider rail's right end (the
-- rail's "Services" name at its left end meanwhile). The pairwise calls
-- above (WantsServices, DividerHeight, BodyPiece, Relayout) stay as they were.
--------------------------------------------------------------------------------

local LINE_GAP = 2        -- the distance line under what it hangs from
local LINE_H = 12         -- its height when Route cannot say

-- a region's edges on the screen (pixels); nil when one cannot be read
-- plainly: the addon's one reader (MelloUI.Safe.ScreenRect, Core.lua)
local ScreenRect = MelloUI.Safe.ScreenRect

-- a region's effective scale when it reads plainly and is above 0
local function EffScale(region)
	local ok, s = pcall(region.GetEffectiveScale, region)
	s = ok and Num(s) or nil
	return (s and s > 0) and s or nil
end

local Column = {}

-- the Services bar merged into the square map's frame (Services asks the
-- very same: the minimap's cover, this module on, and its WantsServices)
function Column.Merged()
	return Kit:IsCovered("minimap") and M.isEnabled and M:WantsServices() and true or false
end

-- the map's block: the square border's frame while it shows round the map
-- (merged, it runs round the Services bar too), else the map (its shown
-- part: M:MapFrame)
function Column.Block()
	local f = skin and skin.square
	if active and f and f:IsShown() then
		return f
	end
	return M:MapFrame()
end

-- the Services bar while it shows beside the block, not merged into it
function Column.LooseBar()
	local bar = ServicesBar()
	if bar and not Column.Merged() then
		return bar
	end
	return nil
end

-- the distance line's height while Route keeps it, else nil
function Column.LineHeight()
	local route = MelloUI:GetModule("Route")
	return route and route.ColumnLine and route:ColumnLine() or nil
end

-- the Services bar's edges on the screen, its height the row's as Services
-- gives it (ServicesRow; the bar's own until Services says)
function Column.BarRect(bar)
	local l, b, r, t = ScreenRect(bar)
	if not l then
		return nil
	end
	local _, height = ServicesRow()
	local s = height and EffScale(bar)
	if s then
		b = t - height * s
	end
	return l, b, r, t
end

function M:ColumnSlot(part)
	local map = M:MapFrame()
	if part == "services" then
		if Column.Merged() then
			return map, "BOTTOM", 0, -M:DividerHeight()
		end
		local services = MelloUI:GetModule("Services")
		local db = services and services.db
		return map, "BOTTOM", 0, tonumber(db and db.barOffset) or -26
	end
	-- merged over Services' row of groups (layout E): the distance line at
	-- the divider rail's right end, the "Services" name at its left end
	-- (M.RailName). Fifth and sixth values: the line's justify and the width
	-- it may take (the rail less its two ends and the name), or nil
	if Column.Merged() and ServicesBar() and ServicesRow() then
		local h = Column.LineHeight() or LINE_H
		local d = skin and skin.divider
		local w = PlainWidth(d, nil)
		local nameW = 0
		if d and d.text then
			local ok, sw = pcall(d.text.GetStringWidth, d.text)
			nameW = ok and MelloUI.Safe.Number(sw) or 0
		end
		local maxW = w and math.max(40, w - 2 * RAIL_PAD - nameW - 8) or nil
		return map, "BOTTOMRIGHT", -RAIL_PAD, -math.max(LINE_GAP, (DIVIDER_H - h) / 2), "RIGHT", maxW
	end
	-- the distance line: 2 px under the map as it always lay (square and
	-- merged too: nothing moves for a user who changes nothing, user,
	-- 2026-09-25), or under the bar where a bar offset leaves it no room there
	-- (measured on the screen; under the map when that cannot be read)
	local bar = Column.LooseBar()
	if bar then
		local _, bottom = ScreenRect(map)
		local _, barBottom, _, barTop = Column.BarRect(bar)
		local okS, s = pcall(map.GetEffectiveScale, map)
		s = okS and Num(s) or nil
		if bottom and barBottom and s then
			local top = bottom - LINE_GAP * s
			local h = Column.LineHeight() or LINE_H
			if top - h * s < barTop and top > barBottom then
				return bar, "BOTTOM", 0, -LINE_GAP
			end
		end
	end
	return map, "BOTTOM", 0, -LINE_GAP
end

-- What is painted past the block's rect (user, 2026-09-26: the Quest Tracker
-- must never sit on the Services row): the square frame's bottom gem corners
-- (f.gemReach, LaySquare), the kit ring's opaque part round the map
-- (Column.Frame), the game's own frame art while the kit is off (215 x 226
-- round the 198 map: LayoutFit's Column.GAME), the zone band under the map
-- (Edit Mode's Header Underneath). -> the rect grown by them
function Column.Painted(block, l, b, r, t)
	if block ~= M:MapFrame() then
		local reach = block.gemReach
		local s = reach and reach > 0 and EffScale(block)
		if s then
			b = b - reach * s
		end
	else
		local fl, fb, fr, ft = Column.Frame()
		if not active and MinimapCompassTexture then
			local ok, shown = pcall(MinimapCompassTexture.IsVisible, MinimapCompassTexture)
			if ok and not MelloUI.Safe.IsSecret(shown) and shown then
				fl, fb, fr, ft = ScreenRect(MinimapCompassTexture)
			end
		end
		if fl then
			l, b, r, t = math.min(l, fl), math.min(b, fb), math.max(r, fr), math.max(t, ft)
		end
	end
	local band = MinimapCluster and MinimapCluster.BorderTop
	if band and band:IsShown() then
		local _, bb = ScreenRect(band)
		if bb and bb < b then
			b = bb
		end
	end
	return l, b, r, t
end

function M:ColumnRect()
	local block = Column.Block()
	local l, b, r, t = ScreenRect(block)
	if not l then
		return nil
	end
	l, b, r, t = Column.Painted(block, l, b, r, t)
	local bar = Column.LooseBar()
	if bar then
		local bl, bb, br, bt = Column.BarRect(bar)
		if not bl then
			return nil
		end
		l, b, r, t = math.min(l, bl), math.min(b, bb), math.max(r, br), math.max(t, bt)
	end
	local h = Column.LineHeight()
	if h then
		local rel, _, _, y = self:ColumnSlot("route")
		local _, relBottom = ScreenRect(rel)
		local okS, s = pcall(Minimap.GetEffectiveScale, Minimap)
		s = okS and Num(s) or nil
		if not (relBottom and s) then
			return nil
		end
		b = math.min(b, relBottom + (y - h) * s)
	end
	return l, b, r, t
end

-- The parts of the column (layout E): the zone band, the map, the Services
-- row, Route's distance line, the Quest Tracker (MelloUI's while it is on,
-- else the game's). A list of the parts, NOT their order on the screen: the
-- distance line stands between the map and the Services row while the bar's
-- distance leaves it room, and Header Underneath puts the band under the
-- map. The order as it stands: M:ColumnOrder().
M.COLUMN_PARTS = { "band", "map", "services", "route", "tracker" }

-- the painted frame round the map: the kit ring's opaque part (its piece's
-- box on its canvas) while it shows, else the map's block
function Column.Frame()
	local ring = active and skin and skin.ring
	local tex = ring and ring.tex
	if tex and ring.object and ring.object:IsShown() then
		local l, b, r, t = ScreenRect(tex)
		local p = l and ring.rule and Kit:Piece(ring.rule.piece)
		if p and p.box and p.w and p.h and p.w > 0 and p.h > 0 then
			local w, h = r - l, t - b
			return l + p.box[1] / p.w * w, t - p.box[4] / p.h * h, l + p.box[3] / p.w * w, t - p.box[2] / p.h * h
		end
		if l then
			return l, b, r, t
		end
	end
	return ScreenRect(Column.Block())
end

function M:ColumnSide(l, r)
	if not (l and r) then
		local _
		l, _, r = Column.Frame()
	end
	local okW, sw = pcall(UIParent.GetWidth, UIParent)
	local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
	sw, us = okW and Num(sw) or nil, okU and Num(us) or nil
	if not (l and r and sw and us) then
		return nil
	end
	return (l + r < sw * us) and "left" or "right"
end

function M:ColumnPart(part)
	if part == "frame" then
		return Column.Frame()
	elseif part == "band" then
		local band = MinimapCluster and MinimapCluster.BorderTop
		if band and band:IsShown() then
			return ScreenRect(band)
		end
	elseif part == "map" then
		if Minimap and Minimap:IsShown() then
			return ScreenRect(M:MapFrame())
		end
	elseif part == "services" then
		local bar = ServicesBar()
		if bar then
			return Column.BarRect(bar)
		end
	elseif part == "route" then
		-- the line's slot: from where it hangs, its height, the map's width
		local h = Minimap and Column.LineHeight()
		if h then
			local rel, _, _, y = self:ColumnSlot("route")
			local _, relBottom = ScreenRect(rel)
			local l, _, r = ScreenRect(M:MapFrame())
			local s = EffScale(Minimap)
			if relBottom and l and s then
				local top = relBottom + y * s
				return l, top - h * s, r, top
			end
		end
	elseif part == "tracker" then
		local qt = MelloUI:GetModule("QuestTracker")
		local f = (qt and qt.isEnabled and _G.MelloUIQuestTracker) or _G.ObjectiveTrackerFrame
		if f and f:IsShown() then
			return ScreenRect(f)
		end
	end
	return nil
end

-- M:ColumnOrder's list and the tops it is sorted by, reused (no garbage);
-- parts at one height keep M.COLUMN_PARTS's order
Column.order, Column.tops, Column.rank = {}, {}, {}
for i, part in ipairs(M.COLUMN_PARTS) do
	Column.rank[part] = i
end
function Column.ByTop(a, b)
	local ta, tb = Column.tops[a], Column.tops[b]
	if ta ~= tb then
		return ta > tb
	end
	return Column.rank[a] < Column.rank[b]
end

-- The parts shown, top to bottom as they stand on the screen now (a part
-- that cannot be read plainly is left out). One table, reused on every call:
-- read it, don't keep or change it.
function M:ColumnOrder()
	local order, tops = Column.order, Column.tops
	for i = #order, 1, -1 do
		order[i] = nil
	end
	for _, part in ipairs(M.COLUMN_PARTS) do
		local _, _, _, t = self:ColumnPart(part)
		if t then
			tops[part] = t
			order[#order + 1] = part
		end
	end
	table.sort(order, Column.ByTop)
	return order
end

-- the frame the column lines up to (M:ColumnWidth's `line`) and its width
-- and the map's on the screen; nil while it cannot be read plainly
function Column.Line()
	local shown = M:MapFrame()
	local l, _, r = ScreenRect(shown)
	if not (l and r > l) then
		return nil
	end
	local map = r - l
	local f = skin and skin.square
	if f and f:IsShown() then
		local fl, _, fr = ScreenRect(f)
		if fl and fr - fl > map then
			return f, fr - fl, map
		end
	end
	return shown, map, map
end

function M:ColumnWidth()
	if not (active and Minimap) then
		return nil, nil
	end
	local _, line, map = Column.Line()
	if not line then
		return nil, nil
	end
	return map, line
end

function M:ColumnAnchor()
	if not (active and Minimap) then
		return nil
	end
	local region = Column.Line()
	local _, lb = ScreenRect(region)
	local _, cb = self:ColumnRect()
	if not (lb and cb) then
		return nil
	end
	return region, "BOTTOMRIGHT", math.min(0, cb - lb)
end

function Column.Fire()
	MelloUI:Fire("column")
end

function M:LayColumn()
	if Kit.NextFrame then
		Kit:NextFrame("Minimap column", Column.Fire)
	else
		C_Timer.After(0, Column.Fire)
	end
end

-- What moves the column without the map's frame being laid again: Route's
-- line (or Route) switched, the minimap cluster dragged by the window mover
-- (its place is a setting) or UI Modifications switched, Edit Mode closed
-- (the map moved or sized there), the UI Scale, a Font Style (the line's
-- height), a profile; and the world entered and Edit Mode's layout applied
-- (at login the map and the game's tracker take their places then). Heard
-- whether this module is on or not; each only asks for the next frame's
-- 'column'. (Edit Mode's Size: the container's SetScale hook, M:Relayout.)
function Column.Lay()
	M:LayColumn()
end

MelloUI:On("setting", function(module, key)
	if (module == "Route" and key == "distanceText") or (module == "UIModifications" and key == "positions") then
		M:LayColumn()
	end
end, "Minimap column")
MelloUI:On("module", function(name)
	if name == "Route" or name == "UIModifications" then
		M:LayColumn()
	end
end, "Minimap column")
MelloUI:On("editmode", function(entering)
	if not entering then
		M:LayColumn()
	end
end, "Minimap column")
-- Match The Quest Tracker's Width (`matchTracker`) came and went during the
-- 0.13.7 build, never shipped: the map's size is Edit Mode's now. A saved one
-- is dead data that would travel in profiles, share strings and the backup:
-- dropped at login (OnInit) and after a profile load (the bus's 'restart').
local function DropStale(db)
	if type(db) == "table" then
		db.matchTracker = nil
	end
end

function M:OnInit(db)
	DropStale(db)
end

function Column.Restart()
	DropStale(MelloUI:GetModuleDB("MinimapPanel"))
	M:LayColumn()
end

MelloUI:On("scale", Column.Lay, "Minimap column")
MelloUI:On("fonts", Column.Lay, "Minimap column")
MelloUI:On("restart", Column.Restart, "Minimap column")
do
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	pcall(ev.RegisterEvent, ev, "EDIT_MODE_LAYOUTS_UPDATED")
	Perf.SetScript(ev, "OnEvent", Column.Lay)
end

function M:OnSettingChanged(key, _, db)
	self.db = db
	if key == "width" or key == "height" then
		-- a size of the player's own: the old Size is never taken over after it
		db.sizeMigrated = true
		-- the map's size first: the Services row takes its width (Size.Changed)
		if Kit.NextFrame then
			Kit:NextFrame("Minimap size", Size.Changed)
		else
			Size.Changed()
		end
		return
	end
	if key == "shape" or key == "squareBorder" or key == "servicesMerge" then
		if key == "shape" then
			Size.Lay()   -- (the round map is as tall as it is wide)
		end
		LayoutWithServices()
		-- the shape switched: Services' minimap button onto the new shape's
		-- edge (it read the game's shape answer before the new mask set it;
		-- review, 2026-09-25)
		if key == "shape" then
			ServicesLayout()
		end
	end
end

-- The minimap's picture choices, for the Configurator's picture rows and the
-- installer's minimap step (PickerGroups: each section's key, title, kind
-- and choices)
function M:PickerGroups()
	return { { id = "minimap", title = "Minimap", hint = "Click to choose the minimap's shape and its square border.", sections = {
		{ key = "shape", title = "Shape", kind = "frame", choices = SHAPES },
		{ key = "squareBorder", title = "Square Border", kind = "frame", choices = BORDERS },
	} } }
end

function M:OnDisable()
	Deactivate()
end

--------------------------------------------------------------------------------
-- /mmdump [frames|reps]: the cluster's art. Opens the copy window.
--------------------------------------------------------------------------------
SLASH_MELLOMMDUMP1 = "/mmdump"
SlashCmdList.MELLOMMDUMP = function(msg)
	msg = (msg or ""):lower()
	MelloUI:ClearLog()
	if not MinimapCluster then
		MelloUI:Print("No minimap cluster.")
	else
		MelloUI:Print("== MinimapCluster  %s L%d; Minimap L%d; backdrop L%d", MinimapCluster:GetFrameStrata(), MinimapCluster:GetFrameLevel(),
			Minimap and Minimap:GetFrameLevel() or -1, MinimapBackdrop and MinimapBackdrop:GetFrameLevel() or -1)
		-- the size (0.15.0): the square map, the part it shows and its mask,
		-- Edit Mode's Size held
		local w, h = Size.Wanted()
		local sw, sh = PlainSize(M:MapFrame())
		local mw = PlainSize(Minimap)
		MelloUI:Print("== size  asked %s x %s; map %s square, shows %s x %s (%s); Edit Mode's Size %s, container %s",
			tostring(w), tostring(h), tostring(mw), tostring(sw), tostring(sh), tostring(Size.file or "no crop"),
			tostring(Size.editScale), tostring(Size.ContainerScale()))
		Kit:DumpWindow(MinimapCluster, skin, msg ~= "" and msg or nil)
	end
	MelloUI:ShowLog("mmdump " .. msg)
end

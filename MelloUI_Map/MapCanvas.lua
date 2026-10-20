--------------------------------------------------------------------------------
-- MelloUI Map - the canvas (docs/plans/seamless-map.md, stage M0)
--
-- One world-space canvas for the whole world map. Every map the client places
-- on Azeroth (947) -- the world, the continents, the zones and the cities -- is
-- laid once in world units (the pixels of 947's art layer) by the client's own
-- C_Map.GetMapRectOnMap, read at runtime: a new client build needs no table of
-- ours. Its art is the client's own tiles by file ID
-- (C_Map.GetMapArtLayerTextures) with the explored pieces over them
-- (C_MapExplorationInfo), laid as Blizzard's map canvas lays them, cut at the
-- art's edge.
--
-- A zoom or a pan is one transform: the root's scale and its anchor. What is
-- out of view is hidden AND unanchored (the engine lays out every anchored
-- region on every frame of a move, seen or not); what comes into view is made
-- then -- nothing at login, at the first open only one frame per map -- and
-- its file loaded a few a frame, faded in. The detail follows the zoom: the
-- world's art, then the continents', then the zones' and the cities'; the
-- alphas quantized, so SetAlpha and SetShown fire on a change only.
--
--   Canvas.New(parent) -> canvas   the clipping frame (canvas.frame) and its root
--   canvas:Layout()                the places read (the first open; idempotent)
--   canvas:SetView(cx, cy, z)      the centre (world units) and the zoom (1: the
--                                  world fits the canvas); clamped
--   canvas:Glide(cx, cy, z, s, e)  there in s seconds: a zoom about the one point
--                                  both views share (MelloUI.Anim:Drive; Reduce
--                                  Motion: at once)
--   canvas:ZoomAt(x, y, notches)   the wheel: the world point under the canvas
--                                  point (x, y) stays under it
--   canvas:Fit(mapID, s)           glide to show a whole map
--   canvas:FitBox(x0, y0, x1, y1)  the centre and zoom that show a box of world
--                                  units (canvas.cover: the px of its right the
--                                  quest log covers; the box in what shows)
--   canvas:Path(x, y) -> list      the maps under a canvas point, the world first,
--                                  by the client's own shapes (GetMapInfoAtPosition)
--   canvas:Deeper(x, y) / :Out()   the next map in, under the point / the one out
--   canvas:Point(x, y) -> wx, wy   a canvas point in world units
--   canvas:Explored()              the explored pieces read again (the event)
--   canvas:Stats() -> table        the numbers /melloperf map shows
--
-- The look (stage M2, the user's picks of 2026-10-20: C, H; then B of the
-- zoom sketch, "parchment all the way"): the world's painting is the ground at
-- every zoom; each continent's painting over it cut to its land (our mask: its
-- zones' outlines joined), its frame, painted sea and ships gone; each zone's
-- picture inside its own soft outline (our mask, made by Tools/build_map_data.py
-- from the client's tables: its pieces' hit rectangles, widened and blurred),
-- its land pieces over it; the places not explored yet drawn faint (every piece
-- from MapData, the explored ones full). The continents' art goes as the zones
-- come in; the world's stays under them. A view stays on the world's painting.
--
-- The close zoom (stage M3, the user's pick A, 2026-10-20: "does the map on
-- zoom in at a certain point change into the minimap style map?"): from zoom
-- 5 to 8 the game's own minimap ground (its files, 512 px a 533-yard terrain
-- tile, listed in MapData from each continent's WDT) comes in over the zones'
-- art, which goes; past its tiles the sea in the minimap's own open water, a
-- texture the canvas's size (the user: "i dont want to have such low
-- resolution water texture"). A minimap tile out of view lets its file go.
--
-- Secret values: every number the client hands over is read through
-- MelloUI.Safe (Finite); a map whose place does not read plainly is not laid.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Map (MapCanvas)")
local Anim = MelloUI.Anim
local W = MelloUI.Widgets
local Finite = MelloUI.Safe.Finite
local Text = MelloUI.Safe.Text
local ScreenRect = MelloUI.Safe.ScreenRect
local ipairs, type, pcall, tostring = ipairs, type, pcall, tostring
local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
local log, exp = math.log, math.exp
local wipe = wipe

local Canvas = {}
Canvas.__index = Canvas
ns.Canvas = Canvas
local EMPTY = {}

local T = {
	WORLD = 947,
	STEP = 1.25,            -- one wheel notch
	ZOOM_SECONDS = 0.25,    -- a notch's ease
	GLIDE_SECONDS = 0.4,    -- a click's glide
	MAX_PX = 64,            -- the deepest zoom: canvas units per world unit (a city's art about 2.5 x its pixels)
	FIT_ROOM = 1.08,        -- a fitted map's margin
	CULL_MARGIN = 0.35,     -- the cull box: the view and this share of it round it
	CULL_EDGE = 0.1,        -- cut again when the view comes this near its edge
	CULL_ZOOM = 1.6,        -- or the zoom has changed this many times since
	LOAD_PER_FRAME = 24,    -- files set a frame
	FADE = 0.25,            -- a tile's fade in once its file is set
	QUANT = 20,             -- the alphas' steps
	-- the detail by zoom (1: the world fits): from, to. The world's painting at every zoom, the ground (the user's
	-- pick B); the continents' cut to their land in over it before their own zoom (a click into one fits its land:
	-- Kalimdor at about 1.27, the Eastern Kingdoms 1.47)
	CONT_IN = { 1.02, 1.2 },
	-- (M2) the zones in as the continents' art goes
	ZONE_IN = { 1.8, 2.8 },
	-- (M3) the minimap's ground in over the zones' art (and the cities'), which goes as it comes
	MINI_IN = { 5.0, 8.0 },
	MINI_SEAM = 0.004,        -- a minimap tile this share bigger each way: no hairline between neighbours
	-- (after M4; the user, 2026-10-20: "Caves at close zoom") the caves' rooms in over the minimap's ground
	CAVE_IN = { 7.5, 9.5 },
	CAVE_YARDS = 1600 / 3,    -- yards a terrain tile (the caves' origins are in tiles, their rooms in yards)
	CAVE_WRAP = "CLAMPTOBLACKADDITIVE",   -- a turned picture's corners past its file: clear, not its edge drawn out
	CONT_OUT = { 2.2, 3.0 },
	OUTLINES = "Interface\\AddOns\\MelloUI_Map\\Media\\Outlines\\",   -- <uiMapID>, city, <continent>
	UNEXPLORED = 0.3,         -- a place not explored yet: its piece this faint (the user's pick H)
	CITY_IN = { 0.2, 0.4 },        -- a city as it fills this share of the view's width
	MAP_TYPE = { continent = 2, zone = 3 },
}
Canvas.T = T

-- the canvases by their frame (the glide's shared step finds its canvas here)
local byFrame = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
-- The places: each map's rectangle on the world, its art
--------------------------------------------------------------------------------

local C_Map = C_Map

-- a map's rectangle on `top` (0..1 there), or nil: not placed, secret, or empty
local function Rect(id, top)
	local ok, x0, x1, y0, y1 = pcall(C_Map.GetMapRectOnMap, id, top)
	if not ok then
		return nil
	end
	x0, x1, y0, y1 = Finite(x0), Finite(x1), Finite(y0), Finite(y1)
	if not (x0 and x1 and y0 and y1) or x1 - x0 <= 0 or y1 - y0 <= 0 then
		return nil
	end
	return x0, x1, y0, y1
end

local function Children(id, mapType, all)
	local ok, list = pcall(C_Map.GetMapChildrenInfo, id, mapType, all)
	return ok and type(list) == "table" and list or nil
end

-- a continent's rectangle when the client gives none for it on the world: carried
-- through one of its zones, placed both on it and on the world (the two are one
-- linear map)
local function ViaChild(id)
	for _, kid in ipairs(Children(id, T.MAP_TYPE.zone) or {}) do
		local k = Finite(kid.mapID)
		local a0, a1, b0, b1 = Rect(k, id)
		local c0, c1, d0, d1 = Rect(k, T.WORLD)
		if a0 and c0 then
			local sx, sy = (c1 - c0) / (a1 - a0), (d1 - d0) / (b1 - b0)
			local x0, y0 = c0 - a0 * sx, d0 - b0 * sy
			return x0, x0 + sx, y0, y0 + sy
		end
	end
	return nil
end

-- a city: the client's own flag, or a zone map the client gives no exploration pieces (UiMap's ShowOverlays flag, 2:
-- every zone of this client has it, the six capitals alone have not)
local function IsCity(id, flags)
	local fn = C_Map.IsCityMap
	if fn then
		local ok, city = pcall(fn, id)
		if ok and city == true then
			return true
		end
	end
	return flags ~= nil and floor(flags / 2) % 2 == 0
end

-- a place: the map's world rectangle (world units), its kind and its art, made the first time it is near the view
local function NewPlace(self, id, kind, x0, x1, y0, y1)
	local info = select(2, pcall(C_Map.GetMapInfo, id))
	local p = {
		id = id, kind = kind, name = type(info) == "table" and Text(info.name) or tostring(id),
		parent = type(info) == "table" and Finite(info.parentMapID) or nil,
		flags = type(info) == "table" and Finite(info.flags) or nil,
		left = x0 * self.W, top = y0 * self.H, w = (x1 - x0) * self.W, h = (y1 - y0) * self.H,
		tiles = nil, alpha = 0, live = false,
	}
	local data = ns.MapData
	p.label = data and data.outline and data.outline[id] or nil   -- (a zone with an outline: where its name goes)
	local okA, art = pcall(C_Map.GetMapArtID, id)
	p.artID = okA and Finite(art) or nil
	p.right, p.bottom = p.left + p.w, p.top + p.h
	p.area = p.w * p.h
	return p
end

function Canvas:Layout()
	if self.places then
		return
	end
	local t0 = debugprofilestop()
	local layers = select(2, pcall(C_Map.GetMapArtLayers, T.WORLD))
	local L = type(layers) == "table" and layers[1]
	self.W = L and Finite(L.layerWidth) or 1002
	self.H = L and Finite(L.layerHeight) or 668
	self.root:SetSize(self.W, self.H)
	local places, byID = {}, {}
	local world = NewPlace(self, T.WORLD, "world", 0, 1, 0, 1)
	places[1], byID[T.WORLD] = world, world
	for _, m in ipairs(Children(T.WORLD, nil, true) or {}) do
		local id, mt = Finite(m.mapID), Finite(m.mapType)
		if id and not byID[id] and (mt == T.MAP_TYPE.continent or mt == T.MAP_TYPE.zone) then
			local x0, x1, y0, y1 = Rect(id, T.WORLD)
			if not x0 and mt == T.MAP_TYPE.continent then
				x0, x1, y0, y1 = ViaChild(id)
			end
			if x0 then
				local p = NewPlace(self, id, mt == T.MAP_TYPE.continent and "continent" or "zone", x0, x1, y0, y1)
				if p.kind == "zone" and IsCity(id, p.flags) then
					p.kind = "city"
				end
				places[#places + 1], byID[id] = p, p
			end
		end
	end
	-- the order: the biggest first (a city over its zone, a zone over its continent)
	table.sort(places, function(a, b)
		if a.area ~= b.area then
			return a.area > b.area
		end
		return a.id < b.id
	end)
	-- (the levels: the maps biggest first; the zone under the view's centre over them all, Focus; the cities over
	-- that, each over its zone)
	local base = self.root:GetFrameLevel() + 1
	local n = #places
	self.focusLevel = base + n + 2
	for i, p in ipairs(places) do
		local f = CreateFrame("Frame", nil, self.root)
		local under = p.kind == "world" or p.kind == "continent"
		p.level = p.kind == "city" and base + n + 3 + i or (under and base + i or base + i + 1)
		f:SetFrameLevel(p.level)
		f:SetSize(p.w, p.h)
		f:Hide()
		p.frame = f
	end
	-- (M3) the minimap's ground over every map's art, the open water just under it
	self:MiniLayout(places, base + 2 * n + 6)
	-- (after M4) the caves over the minimap's ground
	self:CaveLayout(places, base + 2 * n + 7)
	-- a continent's land: the box round its zones (its art reaches far out to sea: the Eastern Kingdoms' spans 0.37
	-- to 1.16 of the world's width), what a glide into it frames
	for _, p in ipairs(places) do
		local c = p.parent and byID[p.parent]
		if c and c.kind == "continent" and p.kind ~= "continent" then
			local land = c.land
			if not land then
				land = { p.left, p.top, p.right, p.bottom }
				c.land = land
			else
				land[1], land[2] = min(land[1], p.left), min(land[2], p.top)
				land[3], land[4] = max(land[3], p.right), max(land[4], p.bottom)
			end
		end
	end
	-- how far a view may go: the world's painting, the ground (the continents' art reaches past it, but only its land
	-- is drawn, and that lies on the world)
	self.bounds = { 0, 0, self.W, self.H }
	self.places, self.byID = places, byID
	self.stats.layoutMs = debugprofilestop() - t0
end

-- (M3) the minimap's ground: a place for each continent's world map (MapData.minimap: its tile grid on Azeroth),
-- at `level`, appended to the places (after their sort: not a map of the client's, never in byID); and the open
-- water past its tiles (MapData.minimapWater) on a frame of the canvas's size, just under it
function Canvas:MiniLayout(places, level)
	local data = ns.MapData
	local grids = data and data.minimap
	if type(grids) ~= "table" then
		return
	end
	local ids = {}
	for mapID in pairs(grids) do
		ids[#ids + 1] = mapID
	end
	table.sort(ids)
	for _, mapID in ipairs(ids) do
		local g = grids[mapID]
		local list = type(g) == "table" and g.tiles
		if type(list) == "table" and #list >= 3 then
			local minX, minY, maxX, maxY = 64, 64, -1, -1
			for i = 1, #list - 2, 3 do
				minX, minY = min(minX, list[i]), min(minY, list[i + 1])
				maxX, maxY = max(maxX, list[i]), max(maxY, list[i + 1])
			end
			local tw, th = g.w * self.W, g.h * self.H
			local p = {
				id = -1 - mapID, kind = "minimap", name = "minimap " .. mapID, grid = g, minX = minX, minY = minY,
				tw = tw, th = th, left = (g.x + minX * g.w) * self.W, top = (g.y + minY * g.h) * self.H,
				w = (maxX - minX + 1) * tw, h = (maxY - minY + 1) * th, tiles = nil, alpha = 0, live = false,
				level = level,
			}
			p.right, p.bottom = p.left + p.w, p.top + p.h
			p.area = p.w * p.h
			local f = CreateFrame("Frame", nil, self.root)
			f:SetFrameLevel(level)
			f:SetSize(p.w, p.h)
			f:Hide()
			p.frame = f
			places[#places + 1] = p
			self.hasMini = true
		end
	end
	local file = data.minimapWater
	if file then
		local water = CreateFrame("Frame", nil, self.root)
		water:SetAllPoints(self.frame)
		water:SetFrameLevel(level - 1)
		local tex = water:CreateTexture(nil, "BACKGROUND")
		tex:SetAllPoints(water)
		tex:SetTexCoord(0.25, 0.75, 0.25, 0.75)   -- (its middle: one colour, no edge to stretch)
		water:SetAlpha(0)
		water:Hide()
		self.water = { frame = water, tex = tex, file = file, set = false }
	end
end

-- (after M4) the caves of the data (MapData.caves: the client's own pictures of each underground model's rooms,
-- placed and turned as its terrain places it; Tools/build_map_data.py) over the minimap's ground from CAVE_IN: one
-- place a cave, a picture a tile -- the box round the turned picture, its corners' coordinates in the file
-- (SetTexCoord's eight), past the file clear (CAVE_WRAP); each lets its file go out of view, as the minimap's tiles
local function CavePlace(self, g, cave, n, level)
	local ox, oy = (g.x + cave[1] * g.w) * self.W, (g.y + cave[2] * g.h) * self.H
	local kx, ky = g.w * self.W / T.CAVE_YARDS, g.h * self.H / T.CAVE_YARDS
	local th = math.rad(90 - cave[3])
	local c, s, size = math.cos(th), math.sin(th), cave[4] or 1
	local pics = cave[5]
	if type(pics) ~= "table" or #pics < 5 then
		return nil
	end
	-- the model's units -> the canvas, and back
	local function Out(lx, ly)
		local u, v = (lx * c + ly * s) * size, (lx * s - ly * c) * size
		return ox + u * kx, oy + v * ky
	end
	local function In(x, y)
		local u, v = (x - ox) / kx, (y - oy) / ky
		return (c * u + s * v) / size, (s * u - c * v) / size
	end
	local tiles = {}
	local l, t0, r, b = math.huge, math.huge, -math.huge, -math.huge
	for i = 1, #pics - 4, 5 do
		local file, ax, ay, fw, fh = pics[i], pics[i + 1], pics[i + 2], pics[i + 3], pics[i + 4]
		-- (the picture in the model's units: 2 px a unit from its anchor, its rows from the bottom)
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for _, corner in ipairs({ { ax, ay }, { ax + fw / 2, ay }, { ax, ay + fh / 2 }, { ax + fw / 2, ay + fh / 2 } }) do
			local x, y = Out(corner[1], corner[2])
			x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
		end
		local function Coord(x, y)
			local lx, ly = In(x, y)
			return (lx - ax) * 2 / fw, 1 - (ly - ay) * 2 / fh
		end
		local ulx, uly = Coord(x0, y0)
		local llx, lly = Coord(x0, y1)
		local urx, ury = Coord(x1, y0)
		local lrx, lry = Coord(x1, y1)
		tiles[#tiles + 1] = {
			file = file, wx0 = x0, wy0 = y0, wx1 = x1, wy1 = y1, w = x1 - x0, h = y1 - y0,
			tc = { ulx, uly, llx, lly, urx, ury, lrx, lry }, wrap = T.CAVE_WRAP,
			layer = "ARTWORK", sub = 0, tex = nil, set = false, shown = false, unload = true,
		}
		l, t0, r, b = min(l, x0), min(t0, y0), max(r, x1), max(b, y1)
	end
	local p = {
		id = -100000 - n, kind = "cave", name = "cave", left = l, top = t0, right = r, bottom = b, w = r - l, h = b - t0,
		tiles = tiles, alpha = 0, live = false, level = level,
	}
	p.area = p.w * p.h
	for _, t in ipairs(tiles) do
		t.x, t.y = t.wx0 - l, t.wy0 - t0
	end
	return p   -- (its frame made the first time it comes into view: CaveFrame)
end

-- a cave's frame, the first time it comes into view (358 caves: none made until one is near)
local function CaveFrame(self, p)
	local f = CreateFrame("Frame", nil, self.root)
	f:SetFrameLevel(p.level)
	f:SetSize(p.w, p.h)
	f:SetAlpha(p.alpha)
	f:Hide()
	p.frame = f
	return f
end

function Canvas:CaveLayout(places, level)
	local data = ns.MapData
	local all, grids = data and data.caves, data and data.minimap
	if type(all) ~= "table" or type(grids) ~= "table" then
		return
	end
	local ids = {}
	for mapID in pairs(all) do
		ids[#ids + 1] = mapID
	end
	table.sort(ids)
	local n = 0
	for _, mapID in ipairs(ids) do
		local g = grids[mapID]
		if type(g) == "table" then
			for _, cave in ipairs(all[mapID]) do
				local p = CavePlace(self, g, cave, n + 1, level)
				if p then
					n = n + 1
					places[#places + 1] = p
				end
			end
		end
	end
	self.hasCaves = n > 0
end

-- the caves shown or not (the layers' switch "Caves"): the view laid again at once
function Canvas:SetCaves(on)
	on = on and true or false
	if self.cavesOn ~= on then
		self.cavesOn = on
		if self.cx then
			self.box[5] = nil   -- (a cut: their places in or out)
			self:SetView(self.cx, self.cy, self.z)
		end
	end
end

-- one tile's record: its art pixels cut at the art's edge, its place in its map and on the world
local function Tile(p, file, x, y, pw, ph, fw, fh, layer, sub, sx, sy)
	local t = {
		file = file, x = x * sx, y = y * sy, w = pw * sx, h = ph * sy, u = pw / fw, v = ph / fh,
		layer = layer, sub = sub, tex = nil, set = false, shown = false,
	}
	t.wx0, t.wy0 = p.left + t.x, p.top + t.y
	t.wx1, t.wy1 = t.wx0 + t.w, t.wy0 + t.h
	return t
end

-- the next power of two from 16 (an explored piece's last file, as the client's map canvas reads it)
local function FileSize(px)
	local s = 16
	while s < px do
		s = s * 2
	end
	return s
end

-- (M3) the minimap's tiles of a continent: one a terrain tile, its whole file, a hair bigger than its square; each
-- lets its file go when it leaves the view (512 px each: a long pan at a close zoom would keep hundreds)
local function MakeMiniTiles(p)
	local tiles, list = {}, p.grid.tiles
	p.tiles = tiles
	local gw, gh = p.tw * T.MINI_SEAM, p.th * T.MINI_SEAM
	for i = 1, #list - 2, 3 do
		local file = Finite(list[i + 2])
		if file then
			local t = Tile(p, file, list[i] - p.minX, list[i + 1] - p.minY, 1, 1, 1, 1, "BACKGROUND", 0, p.tw, p.th)
			t.x, t.y, t.w, t.h = t.x - gw, t.y - gh, t.w + 2 * gw, t.h + 2 * gh
			t.unload = true
			tiles[#tiles + 1] = t
		end
	end
end

-- a map's tiles: its base art, then its explored pieces (C_MapExplorationInfo), in art pixels of its own layer
local function MakeTiles(p)
	if p.kind == "minimap" then
		MakeMiniTiles(p)
		return
	end
	local tiles = {}
	p.tiles = tiles
	local layers = select(2, pcall(C_Map.GetMapArtLayers, p.id))
	local L = type(layers) == "table" and layers[1]
	local lw, lh = L and Finite(L.layerWidth), L and Finite(L.layerHeight)
	local tw, th = L and Finite(L.tileWidth), L and Finite(L.tileHeight)
	if not (lw and lh and tw and th) or lw <= 0 or lh <= 0 or tw <= 0 or th <= 0 then
		return
	end
	local sx, sy = p.w / lw, p.h / lh
	p.tileW, p.tileH, p.sx, p.sy = tw, th, sx, sy
	local ok, files = pcall(C_Map.GetMapArtLayerTextures, p.id, 1)
	if ok and type(files) == "table" then
		local cols, rows = ceil(lw / tw), ceil(lh / th)
		for r = 0, rows - 1 do
			for c = 0, cols - 1 do
				local file = Finite(files[r * cols + c + 1])
				if file then
					local pw, ph = min(tw, lw - c * tw), min(th, lh - r * th)
					tiles[#tiles + 1] = Tile(p, file, c * tw, r * th, pw, ph, tw, th, "BACKGROUND", 0, sx, sy)
				end
			end
		end
	end
	p.baseCount = #tiles
	for i = 1, #tiles do
		tiles[i].base = true
	end
	-- (M2) the zone's picture inside its soft outline; a city's, or a zone's the client gives no pieces (Forever's own
	-- Riverglades), inside a soft-edged rectangle; (B) a continent's inside its land
	local data = ns.MapData
	local outline = p.label and T.OUTLINES .. p.id or ((p.kind == "city" or p.kind == "zone") and T.OUTLINES .. "city")
		or (p.kind == "continent" and data and data.land and data.land[p.id] and T.OUTLINES .. p.id) or nil
	if outline then
		local mask = p.frame:CreateMaskTexture()
		mask:SetTexture(outline, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(p.frame)
		p.mask = mask
	end
	Canvas.AddExplored(p)
end

-- one piece of a map: its tiles (the last column / row in a file the next power of two, as the client's map canvas
-- reads it); `files` the client's list from `first` + 1 on; `alpha` its strength (a place not explored yet: faint)
local function AddPiece(p, ew, eh, ox, oy, files, first, sub, alpha)
	local tiles, tw, th = p.tiles, p.tileW, p.tileH
	local wide, tall = ceil(ew / tw), ceil(eh / th)
	for j = 1, tall do
		local ph, fh = th, th
		if j == tall then
			ph = eh % th
			if ph == 0 then
				ph = th
			end
			fh = FileSize(ph)
		end
		for k = 1, wide do
			local pw, fw = tw, tw
			if k == wide then
				pw = ew % tw
				if pw == 0 then
					pw = tw
				end
				fw = FileSize(pw)
			end
			local file = Finite(files[first + (j - 1) * wide + k])
			if file then
				local t = Tile(p, file, ox + tw * (k - 1), oy + th * (j - 1), pw, ph, fw, fh, "ARTWORK", sub, p.sx, p.sy)
				t.alpha = alpha
				tiles[#tiles + 1] = t
			end
		end
	end
end

-- a map's pieces (its tiles past the base's: made again when the client tells of new ones): the ones the client
-- calls explored (C_MapExplorationInfo) full; then (M2, the user's pick H) every other piece the map has (MapData,
-- the client's tables) faint: a place not explored yet, still readable
function Canvas.AddExplored(p)
	local tiles, tw = p.tiles, p.tileW
	if not (tiles and tw) then
		return
	end
	local seen = p.seenPieces
	if not seen then
		seen = {}
		p.seenPieces = seen
	end
	wipe(seen)
	local api = rawget(_G, "C_MapExplorationInfo")
	local ok, pieces = false, nil
	if api and api.GetExploredMapTextures then
		ok, pieces = pcall(api.GetExploredMapTextures, p.id)
	end
	for _, e in ipairs(ok and type(pieces) == "table" and pieces or EMPTY) do
		local ew, eh = Finite(e.textureWidth), Finite(e.textureHeight)
		local ox, oy = Finite(e.offsetX), Finite(e.offsetY)
		local files = type(e.fileDataIDs) == "table" and e.fileDataIDs
		-- (the pieces shown only under the mouse on the game's map: not drawn)
		if ew and eh and ox and oy and files and e.isShownByMouseOver ~= true then
			seen[ew .. ":" .. eh .. ":" .. ox .. ":" .. oy] = true
			AddPiece(p, ew, eh, ox, oy, files, 0, e.isDrawOnTopLayer == true and 1 or 0, 1)
		end
	end
	local data = ns.MapData
	local all = p.artID and data and data.pieces and data.pieces[p.artID]
	for _, q in ipairs(all or EMPTY) do
		if not seen[q[1] .. ":" .. q[2] .. ":" .. q[3] .. ":" .. q[4]] then
			AddPiece(p, q[1], q[2], q[3], q[4], q, 4, 0, T.UNEXPLORED)
		end
	end
end

--------------------------------------------------------------------------------
-- Showing and hiding: anchored only while in view
--------------------------------------------------------------------------------

local function Load(self, t)
	if not t.queued then
		t.queued = true
		local q = self.queue
		q[#q + 1] = t
		self.loader:Show()
	end
end

local function ShowTile(self, p, t)
	local tex = t.tex
	if not tex then
		tex = p.frame:CreateTexture(nil, t.layer, nil, t.sub)
		if tex.SetSnapToPixelGrid then
			tex:SetSnapToPixelGrid(false)
			tex:SetTexelSnappingBias(0)
		end
		local tc = t.tc
		if tc then
			tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4], tc[5], tc[6], tc[7], tc[8])   -- (a cave's turned picture)
		else
			tex:SetTexCoord(0, t.u, 0, t.v)
		end
		tex:SetSize(t.w, t.h)
		tex:SetAlpha(0)
		if t.base and p.mask then
			tex:AddMaskTexture(p.mask)   -- (M2: inside the zone's soft outline; B: a continent's inside its land)
		end
		t.tex = tex
		self.stats.made = self.stats.made + 1
	end
	tex:SetPoint("TOPLEFT", p.frame, "TOPLEFT", t.x, -t.y)
	tex:Show()
	t.shown = true
	if not t.set then
		Load(self, t)
	end
end

local function HideTile(t)
	local tex = t.tex
	if tex then
		tex:Hide()
		tex:ClearAllPoints()
		if t.unload and t.set then
			-- (M3: its file let go; set again, and faded in, when it comes back into view)
			Anim:Stop(tex, "alpha")
			tex:SetTexture(nil)
			tex:SetAlpha(0)
			t.set = false
		end
	end
	t.shown = false
end

local function Overlaps(ax0, ay0, ax1, ay1, b)
	return ax1 > b[1] and ax0 < b[3] and ay1 > b[2] and ay0 < b[4]
end

local function HidePlace(p)
	if not p.live then
		return
	end
	p.live = false
	for _, t in ipairs(p.tiles or {}) do
		if t.shown then
			HideTile(t)
		end
	end
	p.frame:Hide()
	p.frame:ClearAllPoints()
end

-- the maps and their tiles against the cull box: in, made and anchored; out, hidden and unanchored
local function Cull(self)
	local box = self.box
	local live, shown = 0, 0
	for _, p in ipairs(self.places) do
		if p.alpha > 0 and Overlaps(p.left, p.top, p.right, p.bottom, box) then
			if not p.tiles then
				MakeTiles(p)
			end
			if not p.live then
				p.live = true
				if not p.frame then
					CaveFrame(self, p)
				end
				p.frame:SetPoint("TOPLEFT", self.root, "TOPLEFT", p.left, -p.top)
				p.frame:Show()
			end
			live = live + 1
			for _, t in ipairs(p.tiles) do
				if Overlaps(t.wx0, t.wy0, t.wx1, t.wy1, box) then
					if not t.shown then
						ShowTile(self, p, t)
					end
					shown = shown + 1
				elseif t.shown then
					HideTile(t)
				end
			end
		else
			HidePlace(p)
		end
	end
	self.stats.live, self.stats.shown = live, shown
	self.stats.culls = self.stats.culls + 1
end

-- the cull box: the view and a margin round it, cut again near its edge or after a big zoom step
local function NeedCut(self, x0, y0, x1, y1)
	local box = self.box
	if not box[5] then
		return true
	end
	local vw, vh = x1 - x0, y1 - y0
	local ex, ey = vw * T.CULL_EDGE, vh * T.CULL_EDGE
	if x0 - ex < box[1] or y0 - ey < box[2] or x1 + ex > box[3] or y1 + ey > box[4] then
		return true
	end
	local ratio = self.z / box[5]
	return ratio > T.CULL_ZOOM or ratio < 1 / T.CULL_ZOOM
end

-- the zone under the view's centre drawn over its neighbours: every zone's art spills past its borders, and a
-- smaller neighbour (drawn later) covered the zone you look at; until M2's edges, the one in view wins
local function Focus(self)
	local path = self:Path(self.cw / 2, self.ch / 2, self.focusPath)
	local f
	for i = #path, 1, -1 do
		if path[i].kind == "zone" then
			f = path[i]
			break
		end
	end
	if f ~= self.focus then
		local old = self.focus
		if old then
			old.frame:SetFrameLevel(old.level)
		end
		if f then
			f.frame:SetFrameLevel(self.focusLevel)
		end
		self.focus = f
	end
end

local function Ramp(v, a, b)
	if v <= a then
		return 0
	elseif v >= b then
		return 1
	end
	return (v - a) / (b - a)
end

local function Quant(a)
	return floor(a * T.QUANT + 0.5) / T.QUANT
end

-- the detail by zoom: each map's alpha, set on a change; true when one came in or went out
local function Detail(self, viewW)
	local z = self.z
	local world = 1   -- (B: the ground at every zoom)
	local cont = Quant(Ramp(z, T.CONT_IN[1], T.CONT_IN[2]) * (1 - Ramp(z, T.CONT_OUT[1], T.CONT_OUT[2])))
	-- (M3: only where the data has the minimap's ground; without it the zones stay)
	local mini = self.hasMini and Quant(Ramp(z, T.MINI_IN[1], T.MINI_IN[2])) or 0
	local zone = Quant(min(Ramp(z, T.ZONE_IN[1], T.ZONE_IN[2]), 1 - mini))
	local cave = (self.hasCaves and self.cavesOn ~= false) and Quant(min(mini, Ramp(z, T.CAVE_IN[1], T.CAVE_IN[2]))) or 0
	local flipped = false
	for _, p in ipairs(self.places) do
		local a
		if p.kind == "world" then
			a = world
		elseif p.kind == "continent" then
			a = cont
		elseif p.kind == "minimap" then
			a = mini
		elseif p.kind == "cave" then
			a = cave
		elseif p.kind == "city" then
			a = Quant(min(zone, Ramp(p.w / viewW, T.CITY_IN[1], T.CITY_IN[2])))
		else
			a = zone
		end
		if a ~= p.alpha then
			if (a > 0) ~= (p.alpha > 0) then
				flipped = true
			end
			p.alpha = a
			if p.frame then   -- (a cave's frame waits until it comes into view)
				p.frame:SetAlpha(a)
			end
		end
	end
	local water = self.water
	if water and water.alpha ~= mini then
		water.alpha = mini
		if mini > 0 and not water.set then
			water.tex:SetTexture(water.file)
			water.set = true
		end
		water.frame:SetAlpha(mini)
		water.frame:SetShown(mini > 0)
	end
	return flipped
end

--------------------------------------------------------------------------------
-- The view: one transform
--------------------------------------------------------------------------------

function Canvas:Size()
	local w, h = Finite(self.frame:GetWidth()), Finite(self.frame:GetHeight())
	if not (w and h) or w <= 1 or h <= 1 then
		return nil
	end
	self.cw, self.ch = w, h
	self.k1 = min(w / self.W, h / self.H)
	self.zMax = max(1, T.MAX_PX / self.k1)
	return w, h
end

function Canvas:Clamp(cx, cy, z)
	z = min(max(z or 1, 1), self.zMax or 1)
	local k = self.k1 * z
	local vw, vh = self.cw / k, self.ch / k
	-- (the whole world in view: it stays centred; closer, the view stays within what is drawn)
	local b = self.bounds
	if vw >= self.W or not b then
		cx = self.W / 2
	else
		cx = min(max(cx, b[1] + vw / 2), b[3] - vw / 2)
	end
	if vh >= self.H or not b then
		cy = self.H / 2
	else
		cy = min(max(cy, b[2] + vh / 2), b[4] - vh / 2)
	end
	return cx, cy, z
end

function Canvas:SetView(cx, cy, z)
	if not (self.places and self.cw) then
		return
	end
	local t0 = debugprofilestop()
	cx, cy, z = self:Clamp(cx, cy, z)
	self.cx, self.cy, self.z = cx, cy, z
	local k = self.k1 * z
	local root = self.root
	root:SetScale(k)
	root:ClearAllPoints()
	root:SetPoint("TOPLEFT", self.frame, "TOPLEFT", self.cw / (2 * k) - cx, cy - self.ch / (2 * k))
	local vw, vh = self.cw / k, self.ch / k
	local x0, y0 = cx - vw / 2, cy - vh / 2
	local x1, y1 = x0 + vw, y0 + vh
	local flipped = Detail(self, vw)
	if flipped or NeedCut(self, x0, y0, x1, y1) then
		local box, mx, my = self.box, vw * T.CULL_MARGIN, vh * T.CULL_MARGIN
		box[1], box[2], box[3], box[4], box[5] = x0 - mx, y0 - my, x1 + mx, y1 + my, z
		Cull(self)
		Focus(self)
		self.cuts = self.cuts + 1   -- (the pins gather again)
	end
	local s = self.stats
	local ms = debugprofilestop() - t0
	s.views = s.views + 1
	s.lastMs = ms
	if ms > s.maxMs then
		s.maxMs = ms
	end
	-- (a frame's time while the view moves: from the last view set to this one, within a move)
	if self.moving then
		if s.lastAt then
			local frame = t0 - s.lastAt
			if frame < 250 then
				s.moveFrames = s.moveFrames + 1
				s.moveSum = s.moveSum + frame
				if frame > s.moveMax then
					s.moveMax = frame
				end
			end
		end
		s.lastAt = t0
	end
	if self.onView then
		self.onView(self)
	end
end

-- a map's position (0..1 on uiMapID) in world units: a laid map's place, else the map's rect on the world (a city's
-- or a cave's map the client places there), read once; nil where the client places it nowhere (an instance's own)
function Canvas:ToWorld(id, x, y)
	id, x, y = Finite(id), Finite(x), Finite(y)
	if not (id and x and y and self.places) then
		return nil
	end
	local r = self.byID[id] or self.rects[id]
	if r == nil then
		local x0, x1, y0, y1 = Rect(id, T.WORLD)
		r = x0 and { left = x0 * self.W, top = y0 * self.H, w = (x1 - x0) * self.W, h = (y1 - y0) * self.H } or false
		self.rects[id] = r
	end
	if not r then
		return nil
	end
	return r.left + x * r.w, r.top + y * r.h
end

-- a canvas point (from its top left) in world units
function Canvas:Point(x, y)
	local k = self.k1 * self.z
	return self.cx + (x - self.cw / 2) / k, self.cy + (y - self.ch / 2) / k
end

-- where the cursor is on the canvas (from its top left, canvas units), or nil off it or unread (the one screen-rect
-- reader, MelloUI.Safe.ScreenRect: screen pixels, as the cursor's)
function Canvas:Cursor()
	local l, b, r, t = ScreenRect(self.frame)
	if not (l and self.cw) or r <= l or t <= b then
		return nil
	end
	local cx, cy = GetCursorPosition()
	cx, cy = Finite(cx), Finite(cy)
	if not (cx and cy) or cx < l or cx > r or cy < b or cy > t then
		return nil
	end
	return (cx - l) * self.cw / (r - l), (t - cy) * self.ch / (t - b)
end

--------------------------------------------------------------------------------
-- The glide: a zoom about the one point both views share, eased in log zoom
--------------------------------------------------------------------------------

local function GlideStep(frame, share)
	local self = byFrame[frame]
	local g = self and self.g
	if not g then
		return
	end
	local z = exp(g.lz0 + (g.lz1 - g.lz0) * share)
	local cx, cy
	if g.pan then
		cx, cy = g.cx0 + (g.cx1 - g.cx0) * share, g.cy0 + (g.cy1 - g.cy0) * share
	else
		local q = g.z0 / z
		cx, cy = g.px + (g.cx0 - g.px) * q, g.py + (g.cy0 - g.py) * q
	end
	self:SetView(cx, cy, z)
end

local function GlideDone(frame)
	local self = byFrame[frame]
	if self then
		self.gliding = false
		self.moving = false
		self.stats.lastAt = nil
		self:Refocus()
		if self.onRest then
			self.onRest(self)
		end
	end
end

function Canvas:Glide(cx, cy, z, seconds, easing)
	if not self.cx then
		return
	end
	cx, cy, z = self:Clamp(cx, cy, z)
	local g = self.g
	g.cx0, g.cy0, g.z0 = self.cx, self.cy, self.z
	g.cx1, g.cy1, g.z1 = cx, cy, z
	g.lz0, g.lz1 = log(g.z0), log(z)
	-- (the fixed point: P = (c1 k1 - c0 k0) / (k1 - k0); a pure pan when the zoom stays)
	g.pan = abs(z / g.z0 - 1) < 1e-3
	if not g.pan then
		g.px = (cx * z - g.cx0 * g.z0) / (z - g.z0)
		g.py = (cy * z - g.cy0 * g.z0) / (z - g.z0)
	end
	self.gliding, self.moving = true, true
	self.stats.lastAt = nil
	Anim:Drive(self.frame, GlideStep, seconds or T.GLIDE_SECONDS, easing or "inOutQuad", GlideDone)
end

-- the zone in view drawn on top again (a glide or a drag came to rest)
function Canvas:Refocus()
	if self.places and self.cx then
		Focus(self)
	end
end

function Canvas:Stop()
	if self.gliding then
		Anim:Stop(self.frame, "drive")
		self.gliding = false
		self.moving = false
		self.stats.lastAt = nil
	end
end

-- where a running glide is going (the next notch adds to it), else the view
function Canvas:Goal()
	if self.gliding then
		local g = self.g
		return g.cx1, g.cy1, g.z1
	end
	return self.cx, self.cy, self.z
end

function Canvas:ZoomAt(x, y, notches)
	if not self.cx then
		return
	end
	local _, _, gz = self:Goal()
	local z = min(max(gz * T.STEP ^ notches, 1), self.zMax)
	local wx, wy = self:Point(x, y)
	local k = self.k1 * z
	self:Glide(wx - (x - self.cw / 2) / k, wy - (y - self.ch / 2) / k, z, T.ZOOM_SECONDS, "outCubic")
end

-- the zoom that shows a box of world units, and its centre. (the quest log) canvas.cover: the px of the canvas's
-- right the quest log's column covers while it is out -- the box fitted into what shows, in its middle
function Canvas:FitBox(x0, y0, x1, y1)
	local cover = self.cover or 0
	local z = min(max(1, self.cw - cover) / ((x1 - x0) * T.FIT_ROOM), self.ch / ((y1 - y0) * T.FIT_ROOM)) / self.k1
	local k = self.k1 * min(max(z, 1), self.zMax or 1)
	return (x0 + x1) / 2 + cover / (2 * k), (y0 + y1) / 2, z
end

-- the zoom that shows a whole map (a continent: its land), and its centre
function Canvas:FitOf(p)
	local x0, y0, x1, y1 = p.left, p.top, p.right, p.bottom
	local land = p.land
	if land then
		x0, y0, x1, y1 = land[1], land[2], land[3], land[4]
	end
	return self:FitBox(x0, y0, x1, y1)
end

function Canvas:Fit(id, seconds)
	local p = self.byID and self.byID[id]
	if p then
		local cx, cy, z = self:FitOf(p)
		self:Glide(cx, cy, z, seconds)
	end
end

-- (M4) the map under the view's middle: the zone there once the zones' art shows (ZONE_IN), else the continent there;
-- nil over the sea. Read from the path kept for the focus (made again at each cut: no lookups per frame). The Quest
-- List's Current zone in the map's column, and other addons' OnViewChanged (MapAddonPins.lua)
function Canvas:ViewMap()
	local focus = self.focus
	if focus and focus.id and self.z >= T.ZONE_IN[1] then
		return focus.id
	end
	local path = self.focusPath
	for i = #path, 1, -1 do
		if path[i].kind == "continent" then
			return path[i].id
		end
	end
	return nil
end

-- the maps under a canvas point, the world first, each one in by the client's own shapes
function Canvas:Path(x, y, out)
	local wx, wy = self:Point(x, y)
	return self:PathWorld(wx, wy, out)
end

-- the same at a world point (world units)
function Canvas:PathWorld(wx, wy, out)
	out = out or {}
	wipe(out)
	local p = self.byID[T.WORLD]
	while p do
		out[#out + 1] = p
		local u, v = (wx - p.left) / p.w, (wy - p.top) / p.h
		local ok, info = pcall(C_Map.GetMapInfoAtPosition, p.id, u, v)
		local id = ok and type(info) == "table" and Finite(info.mapID)
		local nextP = id and id ~= p.id and self.byID[id]
		-- (only a map that lies within the one before it: a step in, never sideways)
		if nextP and nextP.area < p.area then
			p = nextP
		else
			p = nil
		end
	end
	return out
end

-- (after M4) the deepest map at a world point other than the world (a zone, a city, a continent), or nil: an
-- objective mark's map for its waypoint
local placePath = {}
function Canvas:PlaceAt(wx, wy)
	local path = self:PathWorld(wx, wy, placePath)
	local p = path[#path]
	return (p and p.kind ~= "world") and p or nil
end

-- the next map in under the point: the first on its path that the view does not show whole yet
function Canvas:Deeper(x, y)
	local path = self:Path(x, y, self.path)
	for _, p in ipairs(path) do
		local cx, cy, z = self:FitOf(p)
		if z > self.z * 1.05 then
			self:Glide(cx, cy, z)
			return p
		end
	end
	return nil
end

-- one map out: the deepest on the path under the view's centre that shows more than the view does now
function Canvas:Out()
	local path = self:Path(self.cw / 2, self.ch / 2, self.path)
	for i = #path, 1, -1 do
		local p = path[i]
		local cx, cy, z = self:FitOf(p)
		if z < self.z * 0.95 then
			self:Glide(cx, cy, z)
			return p
		end
	end
	local cx, cy = self:Clamp(self.W / 2, self.H / 2, 1)
	self:Glide(cx, cy, 1)
	return nil
end

-- the explored pieces read again (MAP_EXPLORATION_UPDATED): the maps whose tiles are made drop their pieces
function Canvas:Explored()
	for _, p in ipairs(self.places or {}) do
		local tiles = p.tiles
		if tiles and p.baseCount then
			for i = #tiles, p.baseCount + 1, -1 do
				local t = tiles[i]
				if t.tex then
					HideTile(t)
					t.tex:SetTexture(nil)
				end
				tiles[i] = nil
			end
			Canvas.AddExplored(p)
		end
	end
	if self.cx then
		self.box[5] = nil
		self:SetView(self.cx, self.cy, self.z)
	end
end

--------------------------------------------------------------------------------
-- The file queue: a few files a frame, each faded in; runs only while files wait
--------------------------------------------------------------------------------

local function Loader_OnUpdate(loader)
	local self = loader.canvas
	local q = self.queue
	local n, done = #q, 0
	local i = 1
	while i <= n and done < T.LOAD_PER_FRAME do
		local t = q[i]
		t.queued = false
		if t.shown and not t.set then
			t.tex:SetTexture(t.file, t.wrap, t.wrap, "TRILINEAR")
			t.set = true
			Anim:To(t.tex, "alpha", t.alpha or 1, T.FADE)
			done = done + 1
			self.stats.files = self.stats.files + 1
		end
		i = i + 1
	end
	-- (the rest moved down: no new table)
	local k = 0
	for j = i, n do
		k = k + 1
		q[k] = q[j]
	end
	for j = k + 1, n do
		q[j] = nil
	end
	if k == 0 then
		loader:Hide()
	end
end

--------------------------------------------------------------------------------
-- The canvas
--------------------------------------------------------------------------------

function Canvas.New(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetClipsChildren(true)
	local sea = W.Solid(frame, "BACKGROUND", "innerPanel", 1)
	sea:SetAllPoints(frame)
	local root = CreateFrame("Frame", nil, frame)
	root:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	local loader = CreateFrame("Frame", nil, frame)
	loader:Hide()
	local self = setmetatable({
		frame = frame, root = root, sea = sea, loader = loader, queue = {}, box = {}, g = {}, path = {}, rects = {}, cuts = 0, focusPath = {},
		cx = nil, cy = nil, z = 1, W = 1002, H = 668,
		stats = { made = 0, files = 0, views = 0, culls = 0, live = 0, shown = 0, lastMs = 0, maxMs = 0,
			moveFrames = 0, moveSum = 0, moveMax = 0, layoutMs = 0 },
	}, Canvas)
	loader.canvas = self
	Perf.SetScript(loader, "OnUpdate", Loader_OnUpdate)
	byFrame[frame] = self
	return self
end

-- the move's frame numbers start again (/melloperf map shows them since the last reset)
function Canvas:ResetStats()
	local s = self.stats
	s.views, s.culls, s.maxMs, s.moveFrames, s.moveSum, s.moveMax, s.lastAt = 0, 0, 0, 0, 0, 0, nil
end

function Canvas:Stats()
	local s = self.stats
	local placed, tiles = 0, 0
	for _, p in ipairs(self.places or {}) do
		placed = placed + 1
		tiles = tiles + (p.tiles and #p.tiles or 0)
	end
	s.placed, s.tiles, s.queued = placed, tiles, #self.queue
	return s
end

-- every place with its rectangle (the tests and the dump)
function Canvas:EachPlace(fn)
	for _, p in ipairs(self.places or {}) do
		fn(p)
	end
end

return Canvas

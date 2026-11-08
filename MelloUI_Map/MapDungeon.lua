--------------------------------------------------------------------------------
-- MelloUI Map - the dungeon map (2.1.0; the user, 2026-11-02: "once inside of
-- the dungeon, to open the dungeon map, with boss positions and loot seen on
-- the right side of the map"; the look B "slate" of Workspace/BuildData/output/
-- dungeonmap_sketch; docs/plans/dungeon-map.md)
--
-- Inside a dungeon or a raid the map opens on that instance's own plan -- the
-- client has no map of one: a canvas of its own (MapCanvas: the same view,
-- wheel, drag and tiles; LayoutDungeon) laid in yards from MapDungeons
-- (Tools/build_dungeon_maps.py), over the world's canvas, which stays as it
-- was. Its one pin: you (the game's arrow, where the game gives your place
-- inside). Dungeon Info's page of the instance stands beside it, its bosses and
-- their loot. (The user, 2026-11-03: "remove all of the Boss icons from the
-- map, dungeon entrances and arrows, those maps already draw the dungeon
-- entrance and boss locations": no boss seal, door or doorway arrow of ours.)
-- The "World map" button at the top left, or a right-click at the plan's
-- widest view, goes back to the world.
--
-- Blizzard's drawings (the user, 2026-11-03: "use the Blizzard own dungeon
-- maps for the existing ones"): an old dungeon's wings are Blizzard's own drawn
-- floors -- the client holds their art, no map of them -- laid by their place
-- (MapDungeons' drawn, rect, art; MapCanvas' DrawnPlace). Forever's own are
-- Santiago Reyes' maps (the user, 2026-11-03, with his blessing; MapDungeons'
-- credit): his sheets (their credit band cut, his watermark kept) laid the
-- same way, his name on the footer, no place of the world on them (no arrow).
--
-- From outside (the user, 2026-11-03: "Can i open the dungeon map by clicking
-- on it on the map, or clicking on the dungeon in the dungeon info?"): Dungeon
-- Info's page of an instance shows its plan too (M:ShowDungeon) -- a click on
-- its door on the world map, or on its row in Dungeon Info's list. Your arrow
-- and the wing that follows you are the instance's you stand in only.
--
-- Battlegrounds (2.1.17; the user, 2026-11-07: "Battleground maps are missing
-- from our map"): an instance MelloUI has no plan of, whose map the client has
-- itself and the world does not lay -- an orphan map (Enum.UIMapType), on its
-- own instance map: Alterac Valley, Warsong Gulch, Arathi Basin and Forever's
-- own battleground -- opens on that map, as the game's own map does
-- (MapUtil.GetDisplayableMapForPlayer): its plan made from the client's map
-- (ClientPlan: its art one drawn floor by file ID, its units the art's
-- pixels). Not behind Dungeon Maps: it is the game's own map. From outside
-- the game's map has no way to one (no map links in this client), nor has
-- this one.
-- The people on it (2.1.19; a player, 2026-11-08: the map shows, "but the
-- units are not shown on it"): the client gives no addon a place inside an
-- instance (UnitPosition answers none in a dungeon, proven in game) nor a
-- raid member's anywhere (C_Map.GetPlayerMapPosition: the player and the
-- party only), so you and your group come from the game's own unit frame
-- (Units: a UnitPositionFrame, its map's group pin), which the client draws
-- itself -- as the game's map does, inside its scaled canvas, the units
-- added again at each zoom. A client without one: our pins from the places
-- that read (C_Map.GetPlayerMapPosition, MapLayers' Layers.Group). The
-- battleground's own marks as its map draws them: its flags, on the ground
-- or with the one who carries it, and its vehicles (Battlefield).
--
-- Wings (the user, 2026-11-02: "Several floors, we need to spread them into
-- Wings"): a dungeon whose floors lie over each other comes in wings (the
-- data's, each named by the game's own area name), one shown at a time, picked
-- with the chips beside the World map button. The map opens on the wing you
-- stand in -- the minimap's area name (GetMinimapZoneText) is one of its own --
-- and follows you into another as the name changes; your arrow shows on yours.
--
--   Dungeon.Init(win, hook)      at the window's build (hook(frame): the canvas's
--                                mouse, as the world's)
--   Dungeon.Current() -> map     the instance you are in, when it has a plan and
--                                the option is on, or (2.1.17) a map of the
--                                client's own the world does not lay; else nil
--   Dungeon.Has(map) -> bool     a plan of it, and the option on
--   Dungeon.Show(map)          the plan shown (its canvas made the first time)
--   Dungeon.Hide(keep)           the world again (keep: the plan's files kept, it
--                                shows again at once)
--   Dungeon.Shown() -> map       the plan shown now, or nil
--   Dungeon.Out()                a right-click: out, then the world
--   Dungeon.FindMe()             a middle-click: the view on you
--   Dungeon.Tick(elapsed)        your arrow (the window's beat; 2.1.19: a
--                                battleground's people and marks)
--   Dungeon.Listen(on)           the wing you walk into (the module on / off)
--   Dungeon.Hint()               the footer's text while the plan shows
--   Dungeon.SetWing(w, glide)    the wing shown (the view on the whole of it)
--   Dungeon.Where(map) -> w      the wing the minimap names you in, or nil
--
-- Secret values: every number the client hands over is read through
-- MelloUI.Safe (Finite); a place that does not read plainly is not drawn.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Map (MapDungeon)")
local Finite = MelloUI.Safe.Finite
local Text = MelloUI.Safe.Text
local W = MelloUI.Widgets
local Canvas, Pins, Layers = ns.Canvas, ns.Pins, ns.Layers
local ipairs, pcall, type, max, ceil = ipairs, pcall, type, math.max, math.ceil

local Dungeon = {}
ns.Dungeon = Dungeon

local T = {
	GRID = 32 * 1600 / 3,    -- yards from the world's middle to the terrain grid's 0, 0
	ARROW_SIZE = 26,
	ARROW_ATLAS = "UI-WorldMapArrow",                 -- the game's own map arrow
	ARROW_FILE = "Interface\\Minimap\\MinimapArrow",  -- (if the atlas is missing)
	EVERY = 0.1,             -- your place read at most this often
	-- (the group: a battleground's own map only, 2.1.17; 2.1.19: its flags and vehicles under the people, as the game's)
	ORDER = { pvp = 30, group = 40, player = 50 },
	-- (2.1.19) the people on a battleground's map, the game's unit frame: px on the screen (MapLayers' member and dot
	-- sizes; your arrow ARROW_SIZE), the game's own blips (its UnitPositionFrame's: your party, in a raid the dotted
	-- one), the draw sublevel (you on top)
	MEMBER_SIZE = 16,
	RAID_SIZE = 12,
	BLIP = "WhiteCircle-RaidBlips",
	BLIP_PARTY = "WhiteDotCircle-RaidBlips",
	UNIT_SUB = 6,
	PLAIN = 1,               -- a unit's picture in its own colours (no tint: the game passes white)
	UNITS_ZOOM = 1.02,       -- their units added again when the zoom moved by this factor (their size within a hair)
	FLAG_SIZE = 30,          -- a battleground's flag (the game's: 36 at its pins' smallest scale 0.825)
	BACK_AT = 8,             -- the World map button: px in from the canvas's top left
	FIND_ZOOM = 2,           -- Find me: at least this close
	OUT_AT = 1.02,           -- a right-click at this share of the wing's whole view or wider: the world
	CHIPS_GAP = 8,           -- the wings' chips: px right of the World map button ...
	CHIPS_RIGHT = 8,         -- ... and in from the canvas's right (2.1.0: the map's buttons on the rail beside it)
	CHIPS_MIN = 160,
}

local TEXT = {
	back = "World map",
	hint = "Wheel: zoom   Drag: look around   Right-click: out, then the world map",
	wing = "Wing %d",        -- (a wing the game names nothing)
	credit = "Map by %s",   -- (an artist's sheets: MapDungeons' credit)
}

-- (own: [instance map] = the plan made from the client's own map, 2.1.17; 2.1.19: roster, the group's changes counted --
-- a battleground's unit frame adds its units again when its count is behind)
local S = { canvases = {}, areas = {}, wingOf = {}, own = {}, roster = 0 }

--------------------------------------------------------------------------------
-- The instance you are in
--------------------------------------------------------------------------------

-- MelloUI's plan of an instance (MapDungeons)
local function Data(mapID)
	local all = ns.MapDungeons
	return mapID and type(all) == "table" and all[mapID] or nil
end

-- the plan shown: MelloUI's, else (2.1.17) the one made from the client's own map
local function Plan(mapID)
	return mapID and (Data(mapID) or S.own[mapID]) or nil
end

local function On()
	local m = ns.Map
	return m and m.db and m.db.dungeonMaps ~= false
end

-- the instance map you are in (GetInstanceInfo's eighth), or nil outside one
local function InstanceMap()
	local ok, inside, kind = pcall(IsInInstance)
	if not (ok and inside == true) or kind == "none" then
		return nil
	end
	local okI, _, _, _, _, _, _, _, mapID = pcall(GetInstanceInfo)
	return okI and Finite(mapID) or nil
end

-- (2.1.17) a plan made from a map of the client's own (a battleground's): its art one drawn floor -- the client's files
-- by ID, the whole map in its first art layer -- its units the art's pixels; nil when its art does not read plainly
local function ClientPlan(uiMap)
	local okL, layers = pcall(C_Map.GetMapArtLayers, uiMap)
	local L = okL and type(layers) == "table" and layers[1]
	local lw, lh = L and Finite(L.layerWidth), L and Finite(L.layerHeight)
	local tw, th = L and Finite(L.tileWidth), L and Finite(L.tileHeight)
	if not (lw and lh and tw and th) or lw <= 0 or lh <= 0 or tw <= 0 or th <= 0 then
		return nil
	end
	local okF, files = pcall(C_Map.GetMapArtLayerTextures, uiMap, 1)
	if not (okF and type(files) == "table") then
		return nil
	end
	local cols, rows = ceil(lw / tw), ceil(lh / th)
	local drawn, any = {}, false
	for i = 1, cols * rows do
		drawn[i] = Finite(files[i]) or false   -- (a tile that does not read: none drawn, its place kept)
		any = any or drawn[i] ~= false
	end
	if not any then
		return nil
	end
	local okI, info = pcall(C_Map.GetMapInfo, uiMap)
	local name = okI and type(info) == "table" and Text(info.name) or nil
	local whole = { 0, 0, lw, lh }
	return {
		name = name, uiMap = uiMap, w = lw, h = lh, cw = lw, ch = lh, e0 = 0, s0 = 0, cols = cols, rows = rows,
		ground = {},
		wings = { { name = name, box = whole, areas = {}, drawn = drawn, rect = whole, art = { lw, lh, tw, th },
			cove = {}, edge = {}, rooms = {} } },
	}
end

-- (2.1.17) inside an instance MelloUI has no plan of: the client's map for you (the game's own map shows it), when it
-- is an orphan or the world does not lay it -- its plan (kept for the instance while the client's map for you is the
-- same), or nil
local function Own(mapID)
	if not mapID or Data(mapID) then
		return nil
	end
	local ok, uiMap = pcall(C_Map.GetBestMapForUnit, "player")
	uiMap = ok and Finite(uiMap) or nil
	if not uiMap then
		return nil
	end
	local d = S.own[mapID]
	if d and d.uiMap == uiMap then
		return d
	end
	local okI, info = pcall(C_Map.GetMapInfo, uiMap)
	local kind = okI and type(info) == "table" and Finite(info.mapType) or nil
	if kind ~= Canvas.T.MAP_TYPE.orphan and Canvas.OnWorld(uiMap) then
		return nil
	end
	d = ClientPlan(uiMap)
	if d and S.own[mapID] and S.canvases[mapID] then
		-- (another map of the client's in this instance: the old plan's canvas let go, the new one made at its show)
		if S.shown == mapID then
			Dungeon.Hide()
		end
		local old = S.canvases[mapID]
		old:Release()
		old.frame:Hide()
		S.canvases[mapID] = nil
	end
	if d then
		S.own[mapID] = d
	end
	return d
end

function Dungeon.Current()
	local mapID = InstanceMap()
	if On() and Data(mapID) then
		return mapID
	end
	return Own(mapID) and mapID or nil
end

function Dungeon.Has(mapID)
	return On() and Data(mapID) ~= nil
end

function Dungeon.Shown()
	return S.shown
end

function Dungeon.Hint()
	local d = Plan(S.shown)
	if d and type(d.credit) == "string" then
		return TEXT.hint .. "   " .. TEXT.credit:format(d.credit)   -- (the artist named on his map)
	end
	return TEXT.hint
end

-- the wing the minimap names you in: its area name now (the game's own for the room you stand in) one of a wing's own;
-- nil outside that instance (a plan shown from outside: the world's area names are not its rooms')
function Dungeon.Where(mapID)
	local areas = S.areas[mapID]
	local fn = rawget(_G, "GetMinimapZoneText")
	if not (areas and fn) or InstanceMap() ~= mapID then
		return nil
	end
	local ok, name = pcall(fn)
	name = ok and Text(name) or nil
	return name and areas[name] or nil
end

local function WingName(d, w)
	local wing = d.wings and d.wings[w]
	return wing and wing.name or TEXT.wing:format(w)
end

--------------------------------------------------------------------------------
-- You
--------------------------------------------------------------------------------

local PLAYER = { size = T.ARROW_SIZE, sub = 2 }

local function ArrowLook()
	local info = C_Texture and C_Texture.GetAtlasInfo and select(2, pcall(C_Texture.GetAtlasInfo, T.ARROW_ATLAS))
	if type(info) == "table" then
		PLAYER.atlas = T.ARROW_ATLAS
	else
		PLAYER.icon = T.ARROW_FILE
	end
end

-- (2.1.17) your place on a map of the client's own (0..1 on it, the game's own), in its plan's units; nil: none, a
-- secret, off the map
local function OnClientMap(d)
	local ok, pos = pcall(C_Map.GetPlayerMapPosition, d.uiMap, "player")
	if not (ok and type(pos) == "table") then
		return nil
	end
	local okXY, x, y = pcall(pos.GetXY, pos)
	x, y = okXY and Finite(x), okXY and Finite(y)
	if not (x and y) or x < 0 or y < 0 or x > 1 or y > 1 then
		return nil
	end
	return x * d.w, y * d.h
end

-- your place on the plan shown (yards from its top left), or nil: the game gives none inside, or a secret, or you are
-- not in that instance (its plan shown from outside)
local function You()
	local d = Plan(S.shown)
	if not d or InstanceMap() ~= S.shown then
		return nil
	end
	if d.uiMap then
		return OnClientMap(d)   -- (2.1.17: a battleground's own map)
	end
	-- (an artist's sheets, d.credit: no place of the world on them)
	if not UnitPosition or d.credit then
		return nil
	end
	-- (the game's world position: its first the north, its second the west)
	local ok, north, west, _, instance = pcall(UnitPosition, "player")
	north, west, instance = ok and Finite(north), ok and Finite(west), ok and Finite(instance)
	if not (north and west) or (instance and instance ~= S.shown) then
		return nil
	end
	local x, y = T.GRID - west - d.e0, T.GRID - north - d.s0
	if x < 0 or y < 0 or x > d.w or y > d.h then
		return nil
	end
	return x, y
end

-- a pin turned to the way it faces (a plain angle; else as it was)
local function Turn(pin, facing)
	facing = Finite(facing)
	if facing and pin.rotation ~= facing then
		pin.rotation = facing
		if pin.tex then
			pin.tex:SetRotation(facing)
		end
	end
end

local function Player()
	local pins = S.pins
	local x, y = You()
	local here, c = Dungeon.Where(S.shown), S.canvases[S.shown]
	if (here and c and here ~= c.wing) or (c and c.units) then
		x = nil   -- (you stand in another wing: no arrow on this one; 2.1.19: the game's unit frame draws you)
	end
	local pin = x and pins:Set("player", "player", x, y, PLAYER)
	if not pin then
		pins:Remove("player", "player")
		return
	end
	Turn(pin, GetPlayerFacing and GetPlayerFacing())
end

-- (2.1.17) a map of the client's own (a battleground's), on a client without the game's unit frame: your group at
-- their places on it, by MapLayers' one rule (a member elsewhere: not on it)
local function Group()
	local d, c = Plan(S.shown), S.canvases[S.shown]
	if d and d.uiMap and c and c.seen then
		Layers.Group(S.pins, d.uiMap, c.seen)
	end
end

-- (2.1.19) the people on a map of the client's own (a battleground's): the game's own unit frame -- its map's group
-- pin, a UnitPositionFrame -- over that map's place in the scaled canvas, the client's map set on it: the client draws
-- you and your group at their places itself (none of which it hands an addon inside an instance); nil on a client
-- without one (our pins then)
local function Units(c, d)
	local p = c.byID[d.uiMap]
	local ok, f = pcall(CreateFrame, "UnitPositionFrame", nil, c.root)
	if not (p and ok and type(f) == "table" and type(f.AddUnit) == "function" and type(f.SetUiMapID) == "function"
		and type(f.ClearUnits) == "function" and type(f.FinalizeUnits) == "function") then
		if ok and type(f) == "table" and f.Hide then
			f:Hide()
		end
		return nil
	end
	f:SetPoint("TOPLEFT", c.root, "TOPLEFT", p.left, -p.top)
	f:SetSize(p.w, p.h)
	f:SetFrameLevel(c.pins.frame:GetFrameLevel() + T.ORDER.group)   -- (over the flags' pins, under nothing of ours)
	f:EnableMouse(false)   -- (the canvas keeps its wheel and drag)
	if not pcall(f.SetUiMapID, f, d.uiMap) then
		f:Hide()
		return nil
	end
	return f
end

local UNIT = { raid = {}, party = {} }   -- [kind][i] = its unit token (made once)
for i = 1, 40 do
	UNIT.raid[i] = "raid" .. i
end
for i = 1, 4 do
	UNIT.party[i] = "party" .. i
end

-- an answer of the client's, true when it reads plainly true (a secret: no)
local function Yes(v)
	v = MelloUI.Safe.Value(v)
	return v ~= nil and v ~= false
end

-- the unit frame's units added again (the group changed, or the zoom: their sizes are in the canvas's scaled units, as
-- the game's map adds them again at each scale): each member in their class's colour (MelloUI.Colours), your party's
-- bigger, you last with your facing
local function Roster(c)
	local f = c.units
	local k = c.k1 * c.z
	c.unitsK, c.roster = k, S.roster
	pcall(f.ClearUnits, f)
	local raid = Yes(IsInRaid and IsInRaid())
	local list = raid and UNIT.raid or UNIT.party
	local Colours, sub = MelloUI.Colours, rawget(_G, "UnitInSubgroup")
	for i = 1, #list do
		local unit = list[i]
		if Yes(UnitExists(unit)) and not Yes(UnitIsUnit(unit, "player")) then
			local mine = not raid or Yes(sub and sub(unit))
			local _, class = UnitClass(unit)
			local r, g, b
			if Colours and Colours.Class then
				r, g, b = Colours.Class(Text(class))
			end
			r, g, b = Finite(r), Finite(g), Finite(b)
			if not (r and g and b) then
				r, g, b = T.PLAIN, T.PLAIN, T.PLAIN   -- (no class read: the blip as it is)
			end
			local s = (mine and T.MEMBER_SIZE or T.RAID_SIZE) / k
			pcall(f.AddUnit, f, unit, (mine and raid) and T.BLIP_PARTY or T.BLIP, s, s, r, g, b, T.PLAIN, T.UNIT_SUB, false)
		end
	end
	if not (PLAYER.atlas or PLAYER.icon) then
		ArrowLook()   -- (its first view comes before the show's own)
	end
	local s = T.ARROW_SIZE / k
	local w = T.PLAIN
	pcall(f.AddUnit, f, "player", PLAYER.atlas or PLAYER.icon, s, s, w, w, w, w, T.UNIT_SUB + 1, true)
	pcall(f.FinalizeUnits, f)
end

-- (2.1.19) a battleground's own marks on its map, as the game's map draws them (its BattlefieldFlag and Vehicle
-- providers): each flag at the game's place for it -- on the ground, or with the one who carries it -- in its own
-- picture; each vehicle in its atlas, turned its way (none you ride); a place that does not read plainly: not drawn
local flagSpecs, carSpecs, EMPTY = {}, {}, {}

local function Flags(c, pins, map)
	local count = 0
	local pvp = rawget(_G, "C_PvP")
	local get = pvp and pvp.GetBattlefieldFlagPosition
	local fn = rawget(_G, "GetNumBattlefieldFlagPositions")
	if get and fn then
		local ok, n = pcall(fn)
		count = ok and Finite(n) or 0
	end
	for i = 1, count do
		local ok, x, y, file = pcall(get, i, map)
		x, y, file = ok and Finite(x), ok and Finite(y), ok and Finite(file)
		local spec = file and flagSpecs[file]
		if file and not spec then
			spec = { icon = file, size = T.FLAG_SIZE, sub = 1 }
			flagSpecs[file] = spec
		end
		if not (x and y and spec and pins:SetAt("pvp", i, map, x, y, spec)) then
			pins:Remove("pvp", i)
		end
	end
	for i = count + 1, c.flags or 0 do
		pins:Remove("pvp", i)
	end
	c.flags = count
end

local function Vehicles(c, pins, map)
	local cars = 0
	local pvp = rawget(_G, "C_PvP")
	local get = pvp and pvp.GetBattlefieldVehicles
	local ok, all = false, nil
	if get then
		ok, all = pcall(get, map)
	end
	if ok and type(all) == "table" then
		for i, v in ipairs(all) do
			v = type(v) == "table" and v or EMPTY
			local x, y = Finite(v.x), Finite(v.y)
			local atlas = Text(v.atlas)
			local spec = atlas and carSpecs[atlas]
			if atlas and not spec then
				spec = { atlas = atlas, size = Finite(v.textureWidth) or T.FLAG_SIZE, sub = 2 }
				carSpecs[atlas] = spec
			end
			local pin = x and y and spec and Yes(v.isAlive) and not Yes(v.isPlayer)
				and pins:SetAt("pvp", -i, map, x, y, spec)
			if pin then
				Turn(pin, v.facing)
			else
				pins:Remove("pvp", -i)
			end
			cars = i
		end
	end
	for i = cars + 1, c.cars or 0 do
		pins:Remove("pvp", -i)
	end
	c.cars = cars
end

-- the unit frame's units again when the group changed or the zoom moved (a view of its canvas, or the beat)
local function Resize(c)
	local k, was = c.units and c.k1 and c.z and c.k1 * c.z, c.unitsK
	if k and (c.roster ~= S.roster or not was or k > was * T.UNITS_ZOOM or k < was / T.UNITS_ZOOM) then
		Roster(c)
	end
end

local function Battlefield()
	local d, c = Plan(S.shown), S.canvases[S.shown]
	if not (d and d.uiMap and c) then
		return
	end
	Resize(c)
	Flags(c, S.pins, d.uiMap)
	Vehicles(c, S.pins, d.uiMap)
end

function Dungeon.Tick(elapsed)
	if not S.shown then
		return
	end
	S.wait = (S.wait or 0) - elapsed
	if S.wait <= 0 then
		S.wait = T.EVERY
		Player()
		Group()
		Battlefield()
		S.pins:Lay()
	end
end

function Dungeon.FindMe()
	local c = S.shown and S.canvases[S.shown]
	local here = Dungeon.Where(S.shown)
	if c and here and here ~= c.wing then
		Dungeon.SetWing(here)
	end
	local x, y = You()
	if c and x then
		c:Glide(x, y, math.max(c.z, T.FIND_ZOOM))
	end
end

--------------------------------------------------------------------------------
-- The plan's canvas, shown in place of the world's
--------------------------------------------------------------------------------

local function Make(mapID)
	local c = S.canvases[mapID]
	if c then
		return c
	end
	local win = S.win
	c = Canvas.New(win.body)
	c.frame:SetAllPoints(S.world.frame)
	c.frame:SetFrameLevel(S.world.frame:GetFrameLevel() + 1)
	c.frame:EnableMouse(true)
	c.frame:EnableMouseWheel(true)
	c.frame:Hide()
	local d = Plan(mapID)
	c:LayoutDungeon(d, mapID)
	local areas = {}
	for w, wing in ipairs(type(d.wings) == "table" and d.wings or {}) do
		for _, name in ipairs(type(wing.areas) == "table" and wing.areas or {}) do
			areas[name] = w
		end
	end
	S.areas[mapID] = areas
	local pins = Pins.New(c)
	c.pins = pins
	if d.uiMap then
		-- (a battleground's own map: its flags and vehicles; you and your group the game's unit frame draws -- 2.1.19 --
		-- else, as 2.1.17, our pins: the group as the world's)
		pins:Layer("pvp", T.ORDER.pvp)
		c.units = Units(c, d)
		if not c.units then
			pins:Layer("group", T.ORDER.group)
			c.seen = {}
		end
	end
	pins:Layer("player", T.ORDER.player)
	c.onView = function()
		pins:Lay()
		if c.units then
			Resize(c)   -- (2.1.19: the units' size kept on the screen through a zoom)
		end
	end
	S.hook(c.frame)
	S.canvases[mapID] = c
	return c
end

-- the view of the whole wing shown (its box; without one the dungeon's own box in the plan, which is its art's whole
-- tiles)
local function Whole(c)
	local d = c.dungeon
	local wing = type(d.wings) == "table" and d.wings[c.wing]
	local b = wing and wing.box
	if type(b) == "table" and #b == 4 then
		return c:FitBox(b[1], b[2], b[3], b[4])
	end
	return c:FitBox(0, 0, Finite(d.cw) or c.W, Finite(d.ch) or c.H)
end

local function Back()
	local b = S.back
	if not b then
		b = W.Button(S.win.body, TEXT.back, nil, nil, { onClick = function() Dungeon.Hide() end })
		b:SetFrameLevel(S.world.frame:GetFrameLevel() + 500)   -- (over the plan's pins)
		b:SetPoint("TOPLEFT", S.world.frame, "TOPLEFT", T.BACK_AT, -T.BACK_AT)
		S.back = b
	end
	return b
end

-- the wings' chips beside the World map button (the configurator's own, W.Chips), for a dungeon of more than one wing
local function Chips(mapID)
	local d = Plan(mapID)
	local wings = d and type(d.wings) == "table" and d.wings or {}
	local chips = S.chips
	if #wings < 2 then
		if chips then
			chips:Hide()
		end
		return
	end
	local back = S.back
	if not chips then
		local width = (Finite(S.world.frame:GetWidth()) or 0) - (Finite(back:GetWidth()) or 0) - 2 * T.BACK_AT
			- T.CHIPS_GAP - T.CHIPS_RIGHT
		chips = W.Chips(S.win.body, { row = true, width = max(T.CHIPS_MIN, width),
			onPick = function(_, key) Dungeon.SetWing(key, true) end })
		chips:SetFrameLevel(S.world.frame:GetFrameLevel() + 500)
		chips:SetPoint("LEFT", back, "RIGHT", T.CHIPS_GAP, 0)
		S.chips = chips
	end
	local items = {}
	for w in ipairs(wings) do
		items[w] = { key = w, label = WingName(d, w) }
	end
	chips:SetItems(items)
	chips:Select(S.canvases[mapID].wing)
	chips:Show()
end

-- the wing shown: its rooms, the view on the whole of it (glide: there in a glide)
function Dungeon.SetWing(w, glide)
	local mapID = S.shown
	local c, d = mapID and S.canvases[mapID], Plan(mapID)
	if not (c and d and type(d.wings) == "table" and d.wings[w]) then
		return
	end
	c:SetWing(w)
	S.wingOf[mapID] = w
	if S.chips and S.chips:IsShown() then
		S.chips:Select(w)
	end
	S.wait = 0
	if c.cw then
		if glide then
			c:Glide(Whole(c))
		else
			c:SetView(Whole(c))
		end
	end
end

function Dungeon.Show(mapID)
	local win = S.win
	if not (win and Plan(mapID)) then
		return false
	end
	if S.shown and S.shown ~= mapID then
		Dungeon.Hide()
	end
	if not S.shown then
		S.world, S.worldPins = win.canvas, win.pins
	end
	local c = Make(mapID)
	S.shown, S.pins = mapID, c.pins
	win.canvas, win.pins = c, c.pins
	S.world.frame:Hide()
	c.frame:Show()
	-- (the wing you stand in, else the one shown last)
	local wing = Dungeon.Where(mapID) or S.wingOf[mapID] or 1
	local moved = wing ~= c.wing
	c:SetWing(wing)
	S.wingOf[mapID] = wing
	if c:Size() then
		c.box[5] = nil
		if c.cx and not moved then
			c:SetView(c.cx, c.cy, c.z)
		else
			c:SetView(Whole(c))
		end
	end
	if not (PLAYER.atlas or PLAYER.icon) then
		ArrowLook()
	end
	S.wait = 0
	Back():Show()
	Chips(mapID)
	return true
end

function Dungeon.Hide(keep)
	local win, mapID = S.win, S.shown
	if not mapID then
		return
	end
	local c = S.canvases[mapID]
	S.shown, S.pins = nil, nil
	if c then
		c:Stop()
		c.frame:Hide()
		if not keep then
			c:Release()   -- (its files let go; laid again when it shows. keep: it shows again at once)
		end
	end
	win.canvas, win.pins = S.world, S.worldPins
	S.world.frame:Show()
	if S.back then
		S.back:Hide()
	end
	if S.chips then
		S.chips:Hide()
	end
	if win.frame:IsShown() and S.world.places and S.world:Size() then
		S.world.box[5] = nil
		S.world:SetView(S.world.cx or S.world.W / 2, S.world.cy or S.world.H / 2, S.world.z)
	end
end

-- a right-click: out to the whole wing, and from there the world
function Dungeon.Out()
	local c = S.shown and S.canvases[S.shown]
	if not c then
		return
	end
	local cx, cy, z = c:Clamp(Whole(c))   -- (the zoom as the view takes it: never under 1)
	if c.z <= z * T.OUT_AT then
		Dungeon.Hide()
	else
		c:Glide(cx, cy, z)
	end
end

--------------------------------------------------------------------------------
-- The wing you walk into (the minimap's area name)
--------------------------------------------------------------------------------

local function Listen_OnEvent(_, event)
	if event == "GROUP_ROSTER_UPDATE" then
		S.roster = S.roster + 1   -- (2.1.19: a battleground's unit frame adds its units again on its next beat)
		return
	end
	if S.shown then
		-- (ZONE_CHANGED_INDOORS, ZONE_CHANGED: the minimap's area name changed -- into another wing, its rooms shown)
		local here = Dungeon.Where(S.shown)
		local c = S.canvases[S.shown]
		if here and c and here ~= c.wing then
			Dungeon.SetWing(here, true)
		end
	end
end

function Dungeon.Listen(on)
	local f = S.listen
	if on and not f then
		f = CreateFrame("Frame")
		Perf.SetScript(f, "OnEvent", Listen_OnEvent)
		S.listen = f
	end
	if not f then
		return
	end
	if on then
		f:RegisterEvent("ZONE_CHANGED_INDOORS")
		f:RegisterEvent("ZONE_CHANGED")
		f:RegisterEvent("GROUP_ROSTER_UPDATE")
	else
		f:UnregisterAllEvents()
	end
end

function Dungeon.Init(win, hook)
	S.win, S.hook = win, hook
end

-- the plans' canvases (the tests' and the dump's way in)
function Dungeon.Canvas(mapID)
	return S.canvases[mapID or S.shown]
end

Dungeon.S = S   -- (the tests' way in: the event frame, the chips)

return Dungeon

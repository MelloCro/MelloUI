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
-- pixels), your arrow and your group at the game's places on it
-- (C_Map.GetPlayerMapPosition; the group by MapLayers' Layers.Group). Not
-- behind Dungeon Maps: it is the game's own map. From outside the game's map
-- has no way to one (no map links in this client), nor has this one.
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
--   Dungeon.Tick(elapsed)        your arrow (the window's beat)
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
	ORDER = { group = 40, player = 50 },   -- (the group: a battleground's own map only, 2.1.17)
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

-- (own: [instance map] = the plan made from the client's own map, 2.1.17)
local S = { canvases = {}, areas = {}, wingOf = {}, own = {} }

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

local function Player()
	local pins = S.pins
	local x, y = You()
	local here, c = Dungeon.Where(S.shown), S.canvases[S.shown]
	if here and c and here ~= c.wing then
		x = nil   -- (you stand in another wing: no arrow on this one)
	end
	local pin = x and pins:Set("player", "player", x, y, PLAYER)
	if not pin then
		pins:Remove("player", "player")
		return
	end
	local facing = Finite(GetPlayerFacing and GetPlayerFacing())
	if facing and pin.rotation ~= facing then
		pin.rotation = facing
		if pin.tex then
			pin.tex:SetRotation(facing)
		end
	end
end

-- (2.1.17) a map of the client's own (a battleground's): your group at their places on it, by MapLayers' one rule (a
-- member elsewhere: not on it)
local function Group()
	local d, c = Plan(S.shown), S.canvases[S.shown]
	if d and d.uiMap and c and c.seen then
		Layers.Group(S.pins, d.uiMap, c.seen)
	end
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
	if d.uiMap then
		pins:Layer("group", T.ORDER.group)   -- (2.1.17: a battleground's own map, its group as the world's)
		c.seen = {}
	end
	pins:Layer("player", T.ORDER.player)
	c.pins = pins
	c.onView = function()
		pins:Lay()
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

local function Listen_OnEvent()
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

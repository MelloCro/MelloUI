--------------------------------------------------------------------------------
-- MelloUI - Route
--
-- Draws the way to the map waypoint on the world map and on the minimap.
-- The client has no road or terrain data for addons, so the module learns
-- the roads from you: every half second it drops a breadcrumb where you
-- stand, links it to the previous one, and keeps the result as a graph of
-- paths you have walked, plus flights you have taken and the boats and
-- zeppelins the Quest List knows. A route is the cheapest way through that
-- graph from you to the waypoint (A*), with straight legs to reach the graph;
-- where nothing has been learned yet, it is a straight line.
--
-- Persistence: what is learned is saved as MelloUIRoutes, which the game
-- writes at logout and on /reload and brings back at login (it can arrive a
-- few seconds late: AdoptSaved polls for it). Tools\bake_routes.py also bakes
-- it into Media\RouteData.lua, which the addon loads like any other file, so
-- the roads can ship to every player.
--
-- The traced roads and the quest objective places are the MelloUI_Companion
-- addon's (loaded on demand, Core\Companions.lua), and the graph is built the
-- first time a route is wanted, a couple of milliseconds a frame, not at
-- login (user, 2026-09-24): see "Building the graph" below.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
-- frames made in a game window: Core's maker, so the game's gamepad
-- navigation never walks an open window for each one (MelloUI.Safe.CreateFrame)
local CreateFrame = MelloUI.Safe.CreateFrame
local Perf = MelloUI.Perf:Scope("Route")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer

local M = MelloUI:RegisterModule("Route", {
	title = "Route",
	desc = "Draws the way to your map waypoint on the world map and the minimap, along roads you have walked before.",
	icon = "Interface\\Icons\\Ability_Tracking",
	flavour = "A trail of gems from here to there, along the roads you have walked before.",
	group = "Quests and travel", navOrder = 2,
	role = "feature",
	keep = { "^flights_" },   -- each character's own flight points (CharFlightsKey): never in a profile, never wiped by one
	enabledByDefault = true,
	defaults = {
		worldMap = true,
		minimap = true,
		distanceText = true,
		travelTime = true,
		learn = true,
		trackQuests = true,
		trackFirstWatched = false,
		arrow = true,
		worldMarker = true,
		routeBeam = true,
		markerSound = true,
		lineWidth = 3,
		trailLook = "beads",
		arrive = 25,
		flightHint = true,
		flightCountdown = true,
	},
	options = {
		{ type = "header", name = "Drawing" },
		{ type = "toggle", key = "worldMap", name = "Route On The World Map",
		  desc = "Draw the route to the waypoint on the world map, and its destination as a flag in a gold ring. A stretch where no road is known is a paler, straight guess." },
		{ type = "toggle", key = "minimap", name = "Route On The Minimap",
		  desc = "Draw the nearby part of the route on the minimap." },
		{ type = "dropdown", key = "trailLook", name = "Trail Look", new = "0.19.5", values = {
			{ value = "beads", label = "Red Beads" },
			{ value = "line", label = "Gilded Line" },
			{ value = "dashes", label = "Waymarks" },
		  }, desc = "How the route is drawn on the world map and the minimap: red beads in gold rings, one pale gold line, or short pale gold dashes. The destination is a flag in a gold ring either way." },
		{ type = "slider", key = "lineWidth", name = "Trail Size", min = 1, max = 8, step = 1,
		  desc = "How big the route's beads, line or dashes are on the world map and the minimap." },
		{ type = "toggle", key = "trackQuests", name = "Route To The Tracked Quest",
		  desc = "When no map pin is set, route to the quest you are tracking (the one with the arrow): to the nearest place for an objective you have not finished yet (a creature to kill, an object to use, where the item drops or is sold, a place to explore), and to its turn-in once it is complete. An objective that needs an item in your bags first (remains to bury, a key for a cage) is routed to where that item comes from until you have it." },
		{ type = "toggle", key = "trackFirstWatched", parent = "trackQuests", name = "Fall Back To The First Tracked Quest",
		  desc = "When nothing is super-tracked, follow the first quest on the game's watch list instead of showing nothing. That is the game's own order of the quests you watch, not the Quest Tracker's Nearest Quest First order." },
		{ type = "toggle", key = "distanceText", name = "Distance Under The Minimap",
		  desc = "Show the remaining route length and the destination under the minimap, with or without Route On The Minimap (hidden while the Direction Arrow shows them)." },
		{ type = "toggle", key = "travelTime", name = "Travel Time",
		  desc = "About how long the rest of the way takes, beside the distance under the arrow and on the World Marker, from how fast you are moving (on foot or mounted). The tracking notice says it too, and arriving says how long the way took." },
		{ type = "toggle", key = "arrow", name = "Direction Arrow",
		  desc = "A row in the widget column while a route is followed: an arrow that points along the route's next leg, the destination, the distance and the travel time, and a ring that fills as the way is done. Hover it to show the route on the map or to stop it." },
		{ type = "toggle", key = "worldMarker", name = "World Marker",
		  desc = "A gem over the destination itself, with the distance and the travel time, that stays on it as you move the camera. Far away it is a beacon, smaller the farther the place, faint while it stands in the middle of the screen; within 100 yards it rises above the place, the distance and the name over it and gold chevrons rippling down to it, so it never covers what you are looking for. Inside a quest's objective area it hides, and comes back when you leave. When the place is off screen, an arrow beside your character points the way to turn. Takes the place of the game's own destination marker while it is on." },
		{ type = "toggle", key = "routeBeam", parent = "worldMarker", name = "Light Beam",
		  desc = "A red beam of light rising from the destination into the sky, so the place can be seen from far away, with a ring of light on the ground at its foot and the gem lit red. It fades as you come near and is gone once the marker rises above the place, and hides while the place is off screen. Part of the World Marker." },
		{ type = "toggle", key = "markerSound", parent = "worldMarker", name = "Marker Sounds",
		  desc = "A soft breath of air as the World Marker changes: when it comes up for a new destination, as it rises above the place you are near, and as it turns back into the beacon when you walk away. For a new destination it is the one sound: the tracking notice leaves its chime out then. Plays on the Sound Effects channel. Part of the World Marker." },
		{ type = "header", name = "Arrival" },
		{ type = "slider", key = "arrive", name = "Arrived Within (yards)", min = 10, max = 100, step = 5,
		  desc = "The route ends and the waypoint is cleared when you get this close. Not for the route to a tracked quest: that one moves on with the quest." },
		{ type = "header", name = "Flights" },
		{ type = "toggle", key = "flightHint", name = "Flight Map Help",
		  desc = "At a flight master: where your route flies to, on the flight map's title band, with a small gem on that flight point. Pointing at a flight point also shows about how long the flight takes." },
		{ type = "toggle", key = "flightCountdown", name = "Landing Countdown",
		  desc = "While you fly, the Direction Arrow's row points at where you will land and its ring counts down the time left (with the Direction Arrow on), also when no route is set. The on-screen notice says the take-off and the landing." },
		{ type = "header", name = "Learning" },
		{ type = "toggle", key = "learn", name = "Learn Paths While Playing",
		  desc = "Remember where you walk and fly so routes can follow real roads. What it learns is saved and kept from one session to the next. /route shows how much has been learned." },
	},
})

MelloUI.Route = M

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- secret-safe reads, one set for the addon (MelloUI.Safe, Core.lua); Plain(v)
-- is v, or nil when v is secret -- asked first: comparing a secret, even with
-- nil, is refused on this client
local Plain = MelloUI.Safe.Value

local function VectorXY(pos)
	if type(pos) ~= "table" then
		return nil, nil
	end
	local x, y = Plain(pos.x), Plain(pos.y)
	if (x == nil or y == nil) and type(pos.GetXY) == "function" then
		local ok, gx, gy = pcall(pos.GetXY, pos)
		if ok then
			x, y = Plain(gx), Plain(gy)
		end
	end
	return x, y
end

local WALK = 7           -- yards per second on foot; costs are seconds
local FLIGHT = 30        -- yards per second on a flight path
local BOAT_COST = 90     -- seconds for a boat or zeppelin, wait included
local CELL = 10          -- yards; one graph node per cell
local LINK = 50          -- link consecutive breadcrumbs closer than this
local NEAR = 15          -- link a new node to existing nodes this close
local OFFROAD = 250      -- how far a route may leave the graph at either end
local JUMP = 300         -- yards; from the end of a path the route may cross open ground to another path
local JUMP_COST = 1.5    -- relative to walking a road
local FAR_HUB_COST = 4   -- relative to walking: a straight leg to a dock or flight point past OFFROAD
                         -- (user, 2026-09-23: a beeline to the boat across the hills beat the road
                         -- at the old 1.3; the docks and flight points are on the roads themselves)
local STRAIGHT_COST = 2.2 -- the direct line from start to goal, so roads win unless they are a real detour
local MAP_CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2

-- Continent map sizes in yards, when C_Map.GetMapWorldSize is missing. A
-- newMap's size is taken from the map's corners first (WorldSize), this one
-- only when they cannot be read: 2521, Zephras Isle, which is its own
-- continent (ContinentOf), from the client's map tables.
local WORLD_SIZE = { [1414] = { 36799.8, 24533.2 }, [1415] = { 40741.2, 27149.7 }, [12] = { 36799.8, 24533.2 }, [13] = { 40741.2, 27149.7 },
	[2521] = { 5562.5, 3708.3, newMap = true } }

local contCache, rectCache, sizeCache = {}, {}, {}

-- The map a map's places are measured on, walking up the parents: the
-- Continent map above it. (0.14.0, the Zephras Isle fix: the isle's zone
-- map sits straight under the World map, with no Continent above it, so the
-- player had no position there and every route and service failed.) With
-- no Continent on the way, the highest map below a World or Cosmic map, or
-- below the top (parent 0), counts as its own continent; a World or Cosmic
-- map itself has none. Both answers are kept: "none" as false, until the
-- next loading screen (M.ForgetNoContinent). Also M.ContinentOf, for the
-- Services bar (one way to find a continent).
local function ContinentOf(mapID)
	if not mapID then
		return nil
	end
	local cached = contCache[mapID]
	if cached ~= nil then
		return cached or nil
	end
	local id, below, found = mapID, nil, false
	for _ = 1, 8 do
		local ok, info = pcall(C_Map.GetMapInfo, id)
		if not ok or type(info) ~= "table" then
			-- a parent the game does not describe: the map below it is the top
			found = below or false
			break
		end
		-- a secret kind or parent tells nothing: no continent now, nothing
		-- kept (asked again next time), never a zone taken for its own
		if MelloUI.Safe.IsSecret(info.mapType) or MelloUI.Safe.IsSecret(info.parentMapID) then
			return nil
		end
		local kind = Plain(info.mapType)
		if kind == MAP_CONTINENT then
			found = id
			break
		elseif type(kind) == "number" and kind < MAP_CONTINENT then
			found = below or false   -- the World (1) or Cosmic (0) map: the one below it
			break
		end
		local parent = Plain(info.parentMapID)
		if not parent or parent == 0 then
			found = id
			break
		end
		below, id = id, parent
	end
	contCache[mapID] = found
	return found or nil
end

-- one way to find a map's continent, for the other modules (Services);
-- asked as M.ContinentOf(mapID) or M:ContinentOf(mapID)
function M.ContinentOf(a, b)
	if a == M then
		a = b
	end
	return ContinentOf(Plain(a))
end

-- A loading screen: the maps without a continent are asked again (the
-- game may not have known them yet)
function M.ForgetNoContinent()
	for id, v in pairs(contCache) do
		if v == false then
			contCache[id] = nil
		end
	end
end

local function RectOn(mapID, cont)
	local key = mapID .. ":" .. cont
	local r = rectCache[key]
	if r == nil then
		local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, mapID, cont)
		minX, maxX, minY, maxY = Plain(minX), Plain(maxX), Plain(minY), Plain(maxY)
		if ok and minX and maxX and minY and maxY and maxX > minX and maxY > minY then
			r = { minX, maxX, minY, maxY }
			rectCache[key] = r
		else
			r = nil   -- not cached: the client may answer later
		end
	end
	return r
end

-- a continent's size in yards that can be used: finite and at least 100
-- (NaN fails every test; a tiny one made every map place huge)
local function Sized(w, h)
	return type(w) == "number" and type(h) == "number" and w >= 100 and h >= 100 and w < math.huge and h < math.huge
end

local function WorldSize(cont)
	local s = sizeCache[cont]
	if not s then
		local w, h
		if C_Map.GetMapWorldSize then
			local ok, a, b = pcall(C_Map.GetMapWorldSize, cont)
			if ok then
				w, h = Plain(a), Plain(b)
			end
		end
		local f = WORLD_SIZE[cont]
		if not Sized(w, h) and f and not f.newMap then
			w, h = f[1], f[2]   -- the two continents, as always
		end
		if not Sized(w, h) and C_Map.GetWorldPosFromMapPos and CreateVector2D then
			-- (0.14.0, new maps such as Zephras Isle) the map's corners in the
			-- world: across the map is the world's y, down it the world's x
			local ok1, _, p1 = pcall(C_Map.GetWorldPosFromMapPos, cont, CreateVector2D(0, 0))
			local ok2, _, p2 = pcall(C_Map.GetWorldPosFromMapPos, cont, CreateVector2D(1, 1))
			local x1, y1 = VectorXY(ok1 and p1)
			local x2, y2 = VectorXY(ok2 and p2)
			if x1 and y1 and x2 and y2 then
				w, h = math.abs(y1 - y2), math.abs(x1 - x2)
			end
		end
		if not Sized(w, h) then
			w, h = f and f[1] or 40000, f and f[2] or 27000
		end
		s = { w, h }
		sizeCache[cont] = s
	end
	return s[1], s[2]
end

-- Map position (0..1) -> continent, yards east, yards south.
local function ToYards(mapID, x, y)
	local cont = ContinentOf(mapID)
	if not cont then
		return nil
	end
	local cx, cy = x, y
	if mapID ~= cont then
		local r = RectOn(mapID, cont)
		if not r then
			return nil
		end
		cx, cy = r[1] + x * (r[2] - r[1]), r[3] + y * (r[4] - r[3])
	end
	local w, h = WorldSize(cont)
	return cont, cx * w, cy * h
end

-- Continent yards -> position on a map (0..1); may lie outside 0..1.
local function OnMap(mapID, cont, yx, yy)
	if ContinentOf(mapID) ~= cont then
		return nil
	end
	local w, h = WorldSize(cont)
	local cx, cy = yx / w, yy / h
	if mapID == cont then
		return cx, cy
	end
	local r = RectOn(mapID, cont)
	if not r then
		return nil
	end
	return (cx - r[1]) / (r[2] - r[1]), (cy - r[3]) / (r[4] - r[3])
end

-- The player's place: continent, yards east, yards south (nil when unknown).
-- The game makes a new position table at every ask, and the arrow and the
-- minimap each asked every frame they drew (user, 2026-09-24: no per-frame
-- garbage). With `sameFrame`, the answer already asked this frame is given
-- again (GetTime is the frame's own time, and the player does not move
-- within a frame); the timers and the planner always ask afresh.
local PlayerYards
do
	local askedAt, askedCont, askedX, askedY
	PlayerYards = function(sameFrame)
		local now = GetTime()
		if sameFrame and now == askedAt then
			return askedCont, askedX, askedY
		end
		local cont, x, y
		local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
		mapID = ok and Plain(mapID) or nil
		if mapID then
			local okP, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
			if okP then
				local mx, my = VectorXY(pos)
				if mx and my then
					cont, x, y = ToYards(mapID, mx, my)
				end
			end
		end
		askedAt, askedCont, askedX, askedY = now, cont, x, y
		return cont, x, y
	end
end

local function Dist(ax, ay, bx, by)
	local dx, dy = ax - bx, ay - by
	return math.sqrt(dx * dx + dy * dy)
end

local function Yards(d)
	if d >= 1000 then
		return string.format("%.1f km", d / 1000)
	end
	return string.format("%d yd", d)
end

--------------------------------------------------------------------------------
-- Fonts (user, 2026-09-24: "The Tracking Notice and the Arrow Text should
-- respect the Changes in Font Changing")
--
-- The notice set its font once, by hand, from whatever face its font object
-- had at that moment, so it never followed the Fonts module; the arrow's, the
-- marker's and the minimap's texts rode on the game's font objects and so
-- all took the interface face, the distances included. Each text now names
-- its role and the game font object it starts from, and MelloUI:StyleFont
-- (Fonts.lua, the one font path for MelloUI's own strings) gives it the
-- role's face, its size slider and the Outline, on top of the text's own
-- base size and flags, and again whenever any of them changes. Off, or a
-- role on "Keep the game's", a text keeps its own face exactly as before.
-- Asked at call time (the texts are made on first use); without the Fonts
-- file a text keeps the font object it was made with.
-- A table, not more locals: this file's main chunk is near Lua's limit.
--------------------------------------------------------------------------------

local RouteFont = {}
function RouteFont.Style(fs, role, object, size, flags, outline)
	if MelloUI.StyleFont then
		MelloUI:StyleFont(fs, role, object, size, flags, outline)
	end
end

--------------------------------------------------------------------------------
-- Tracking notice
--
-- Route's lines (the place now tracked, the arrival) go to MelloUI's one
-- on-screen notice (Core/Notice.lua, MelloUI:Announce), which holds, fades,
-- colours and sounds them, keeps its place and follows the notice options
-- (On-screen Notices and the rest, beside Chat Notices). (0.16.0: Route's
-- own Route Announces and Announce Sound are gone: its lines follow
-- On-screen Notices, Send To Chat Instead and Notice Sounds.)
--------------------------------------------------------------------------------

-- kind: "track" (new destination, the default), "arrive", "learn", "fail",
-- "info", "silent" (no chime). mute: the line without its chime (0.19.4:
-- the World Marker's sound stands for a new destination's, M.TrackMute)
function M:Notify(text, kind, mute)
	MelloUI:Announce(text, kind or "track", mute)
end

-- Whether a destination set now is announced with a sound (Route on and
-- the notice's own switches, Notice Sounds among them, or, 0.19.4, the
-- World Marker's sound standing for it: M.MarkerSounds): a caller
-- that routes for the player (the Quest List's pins) plays its own click
-- sound only when not, so one sound plays, not two
function M:AnnounceSounds()
	return (M.isEnabled and ((MelloUI.AnnounceSounds and MelloUI:AnnounceSounds("track")) or (M.MarkerSounds and M.MarkerSounds()))) and true or false
end

-- Said once per map per session, instead of failing quietly (0.14.0, the
-- Zephras Isle fix: on the isle nothing was drawn and nothing was said):
-- a destination is wanted but Route cannot place `what` on `mapID` --
-- "you" (the player's own map: no position there) or "point" (the
-- destination's map). Not inside an instance, where Route has never drawn,
-- nor on a flight; a dungeon's map is not the open world either. With
-- On-screen Notices off nothing is shown (M:Notify). "you" on a map Route can
-- place in principle (it has a continent) is said only when the next plan
-- misses there too: the game may give no position, or not yet say where a
-- zone lies, for a moment. (M.placeMissed: the map the last plan missed on;
-- a plan that places the player clears it.)
M.placeMissed = nil
do
	local told = {}   -- [mapID] = true once said
	local DUNGEON = (Enum and Enum.UIMapType and Enum.UIMapType.Dungeon) or 4

	function M.CannotPlace(mapID, what)
		if what == "you" then
			local okM, mine = pcall(C_Map.GetBestMapForUnit, "player")
			mapID = okM and mine or nil
		end
		mapID = Plain(mapID)
		if type(mapID) ~= "number" or told[mapID] or not M.isEnabled then
			return
		end
		local okI, inside = pcall(IsInInstance)
		if not okI or Plain(inside) then
			return
		end
		local okT, onTaxi = pcall(UnitOnTaxi, "player")
		if okT and Plain(onTaxi) then
			return
		end
		local ok, info = pcall(C_Map.GetMapInfo, mapID)
		info = ok and type(info) == "table" and info or nil
		if what ~= "you" and info and Plain(info.mapType) == DUNGEON then
			return
		end
		if what == "you" and ContinentOf(mapID) and M.placeMissed ~= mapID then
			M.placeMissed = mapID   -- the first miss here: said if the next plan misses too
			return
		end
		told[mapID] = true
		local name = info and MelloUI.Safe.Text(info.name) or ("map " .. mapID)
		if what == "you" then
			M:Notify("Route can't place you on this map (" .. name .. "), so there is no route from here.", "info")
		else
			M:Notify("Route can't place that point on its map (" .. name .. "), so there is no route to it.", "info")
		end
	end
end

-- Distance to the current destination for the notices: the route's length
-- when there is one, else the straight line.
local DestinationDistance -- defined with the route state below

--------------------------------------------------------------------------------
-- The graph
--
-- live.graphs[continent][key] = { x, y, { [otherKey] = cost } }, key = cell.
--------------------------------------------------------------------------------

-- (flights: the flight times learned by timing, ["<from node>><to node>"] =
-- seconds, kept with the learned paths: see "Flight-master help")
local live = { graphs = {}, pins = { entrances = {}, transports = {} }, flights = {} }
local mergedSaved = false
-- What a search can use, counted as it changes, so a search that found no
-- way is not run again until something has changed (memory audit,
-- 2026-09-24): nodes and links per continent, and the hubs (docks, flight
-- points, the flight points this character may use).
local edits = { all = 0, hubs = 0, conts = {} }
local NodeAdded   -- (cont, key, node): keeps the search's indexes up to date; set under "Search"

local function Edited(cont)
	edits.all = edits.all + 1
	edits.conts[cont] = (edits.conts[cont] or 0) + 1
end

-- The graph is built the first time a route is wanted (see "Building the
-- graph" below). Until it is, what changes it -- a breadcrumb, a flight, the
-- saved variable arriving, /route reset -- waits in `pending`, in order, and
-- is made once the roads and the baked paths are in, as it always came after
-- them: a breadcrumb on a road's cell still lands on the road.
local Build = { ready = false, pending = {}, deadline = 0, count = 0, MAX_PENDING = 5000 }

-- A breadcrumb or a flight: may land on a road's cell, so the roads must be
-- in first
function Build.Learn(fn, ...)
	if Build.ready then
		return fn(...)
	end
	local pending = Build.pending
	pending[#pending + 1] = { fn = fn, n = select("#", ...), ... }
	if #pending > Build.MAX_PENDING then
		-- a long walk with nothing to route to: the waiting changes would
		-- soon cost more than the graph itself
		Build.Want()
	end
end

-- Any other change to the graph (the saved variable, /route reset)
function Build.Queue(fn, ...)
	if Build.ready then
		return fn(...)
	end
	local pending = Build.pending
	pending[#pending + 1] = { fn = fn, n = select("#", ...), ... }
end

-- Inside the build's loops: every few nodes, the frame's share used up
-- hands over to the next frame (only the build's own coroutine yields)
function Build.Slice()
	local n = Build.count + 1
	if n < 16 then
		Build.count = n
		return
	end
	Build.count = 0
	if debugprofilestop() >= Build.deadline and Build.job and coroutine.running() == Build.job then
		coroutine.yield()
	end
end

-- Pins the Quest List records by hand travel with the learned paths: the
-- baker keeps both across sessions.
local function PinStore()
	live.pins = live.pins or {}
	live.pins.entrances = live.pins.entrances or {}
	live.pins.transports = live.pins.transports or {}
	live.pins.services = live.pins.services or {}
	return live.pins
end

function M:Pins()
	return PinStore()
end

local function Graph(cont)
	local g = live.graphs[cont]
	if not g then
		g = {}
		live.graphs[cont] = g
	end
	return g
end

local function KeyOf(x, y)
	return math.floor(x / CELL) .. ":" .. math.floor(y / CELL)
end

-- A learned change to the link between two traced road nodes, with the
-- road's own cost (false: none), so /route reset can put the roads back as
-- traced without the road data, which is let go once merged (memory audit,
-- 2026-09-24). A few entries: most learned links end on a learned node,
-- and those go with it.
local roadEdits = {}   -- [road node] = { [other key] = cost before }

local function RoadEdit(node, key)
	local e = roadEdits[node]
	if not e then
		e = {}
		roadEdits[node] = e
	end
	if e[key] == nil then
		e[key] = node[3][key] or false
	end
end

local function Link(cont, a, akey, b, bkey, cost)
	local roads = a[4] and b[4]
	if a[3][bkey] == nil or a[3][bkey] > cost then
		if roads then
			RoadEdit(a, bkey)
		end
		a[3][bkey] = cost
	end
	if b[3][akey] == nil or b[3][akey] > cost then
		if roads then
			RoadEdit(b, akey)
		end
		b[3][akey] = cost
	end
	Edited(cont)
end

local function AddNode(cont, x, y)
	local g = Graph(cont)
	local key = KeyOf(x, y)
	local node = g[key]
	if not node then
		node = { x, y, {} }
		g[key] = node
		Edited(cont)
		NodeAdded(cont, key, node)
		local cx, cy = math.floor(x / CELL), math.floor(y / CELL)
		for i = -2, 2 do
			for j = -2, 2 do
				local k = (cx + i) .. ":" .. (cy + j)
				local o = g[k]
				if o and k ~= key then
					local d = Dist(x, y, o[1], o[2])
					if d <= NEAR then
						Link(cont, node, key, o, k, d / WALK)
					end
				end
			end
		end
	end
	return key, node
end

local function CountNodes()
	local nodes, edges = 0, 0
	for _, g in pairs(live.graphs) do
		for _, node in pairs(g) do
			nodes = nodes + 1
			for _ in pairs(node[3]) do
				edges = edges + 1
			end
		end
	end
	return nodes, edges / 2
end

-- The pins another table recorded (baked data or the saved variable), folded
-- into live at once: the Quest List and the services read them whether the
-- graph is built or not.
local function MergePins(other)
	if type(other) ~= "table" or type(other.pins) ~= "table" then
		return
	end
	local mine = PinStore()
	for kind, list in pairs(other.pins) do
		if (kind == "entrances" or kind == "transports" or kind == "services") and type(list) == "table" then
			for name, v in pairs(list) do
				if mine[kind][name] == nil and type(v) == "table" then
					mine[kind][name] = v
				end
			end
		end
	end
end

-- Fold another graph table (baked data or the saved variable) into live; its
-- pins go in through MergePins.
local function Merge(other)
	if type(other) ~= "table" or type(other.graphs) ~= "table" then
		return 0
	end
	local added = 0
	local Slice = Build.Slice
	for contKey, g in pairs(other.graphs) do
		local cont = tonumber(contKey)
		if cont and type(g) == "table" then
			local mine = Graph(cont)
			-- the baker rounds coordinates, which can move a node into the
			-- next cell: it goes under the key its coordinates give now, and
			-- the links follow (audit, 2026-09-22)
			local keyMap = {}
			for key, node in pairs(g) do
				if type(node) == "table" and type(node[1]) == "number" and type(node[2]) == "number" then
					local k = KeyOf(node[1], node[2])
					keyMap[key] = k
					if not mine[k] then
						AddNode(cont, node[1], node[2])   -- links to the nodes near it
						added = added + 1
					end
				end
				Slice()
			end
			for key, node in pairs(g) do
				Slice()
				local k = keyMap[key]
				local target = k and mine[k]
				if target then
					for linked, cost in pairs(node[3] or {}) do
						local ko = keyMap[linked] or linked
						if ko ~= k and type(cost) == "number" and (target[3][ko] == nil or target[3][ko] > cost) then
							local back = mine[ko]
							local roads = target[4] and back and back[4]
							if roads then
								RoadEdit(target, ko)
							end
							target[3][ko] = cost
							if back and (back[3][k] == nil or back[3][k] > cost) then
								if roads then
									RoadEdit(back, k)
								end
								back[3][k] = cost
							end
						end
					end
				end
			end
			Edited(cont)
		end
	end
	return added
end

-- Roads traced from the map art (MelloUI_Companion/RoadData.lua,
-- Tools/trace_roads.py): folded in like baked data but scaled to the
-- continent sizes this client reports, marked as traced so they are never
-- written back into the saved variable, and linked to whatever was learned
-- near them.
local tracedNodes = 0

local function MergeRoads(data)
	if type(data) ~= "table" or type(data.graphs) ~= "table" then
		return 0
	end
	local added = 0
	local Slice = Build.Slice
	for contKey, g in pairs(data.graphs) do
		local cont = tonumber(contKey)
		if cont and type(g) == "table" then
			local w, h = WorldSize(cont)
			local size = type(data.sizes) == "table" and data.sizes[cont]
			local sx = (size and size[1] and size[1] > 0) and w / size[1] or 1
			local sy = (size and size[2] and size[2] > 0) and h / size[2] or 1
			local mine = Graph(cont)
			local keyMap = {}
			for key, node in pairs(g) do
				if type(node) == "table" and type(node[1]) == "number" and type(node[2]) == "number" then
					local x, y = node[1] * sx, node[2] * sy
					local k = KeyOf(x, y)
					keyMap[key] = k
					if not mine[k] then
						local _, created = AddNode(cont, x, y)
						created[4] = true
						added = added + 1
					end
				end
				Slice()
			end
			for key, node in pairs(g) do
				Slice()
				local k = keyMap[key]
				local target = k and mine[k]
				if target then
					for other, cost in pairs(node[3] or {}) do
						local ko = keyMap[other]
						if ko and mine[ko] and type(cost) == "number" and ko ~= k then
							if target[3][ko] == nil or target[3][ko] > cost then
								target[3][ko] = cost
								mine[ko][3][k] = cost
							end
						end
					end
				end
			end
			Edited(cont)
		end
	end
	tracedNodes = tracedNodes + added
	return added
end

-- The ground (0.17.0; the user, 2026-10-01, in Northshire: the dots led
-- over a ridge no one can climb; docs/plans/route-terrain.md, option A). The
-- companion's walk grid -- the walkable ground measured offline from the
-- client's own terrain (Tools/trace_terrain.py, Tools/ground_graph.py; its
-- ground links are in the graph beside the roads, priced over them) -- says
-- whether a straight leg stays on walkable ground: the start's and the
-- goal's legs to the graph, the direct line and the jumps between paths
-- take only those. A continent with no grid (an instance, a map not
-- measured) answers nil: as before, and a straight line there is a guess.
--   M.Ground.Set(data)     the companion's walk grids (data.walk, scaled
--                          by data.sizes as the roads), at the build
--   M.Ground.Has(cont)     a grid for that continent
--   M.Ground.Clear(cont, x0, y0, x1, y1) -> true (no wall on the segment),
--                          false (a wall), nil (no grid there)
-- A row is decoded the first time a leg crosses it (its runs kept).
-- (0.17.1, the walking freezes: docs/plans/hotfix-0.17.1-route-freeze.md)
-- The line is sampled once a cell, not twice, and the decoded rows are kept
-- ROWS at most per grid, the oldest let go first: they grew as you walked
-- (60 MB against 48). Clear itself makes nothing.
M.Ground = { grids = {}, ROWS = 256 }

function M.Ground.Set(data)
	local walk = type(data) == "table" and data.walk
	if type(walk) ~= "table" then
		return
	end
	for contKey, g in pairs(walk) do
		local cont = tonumber(contKey)
		if cont and type(g) == "table" and type(g.rows) == "table" and type(g.cell) == "number" then
			local w, h = WorldSize(cont)
			local size = type(data.sizes) == "table" and data.sizes[cont]
			g.sx = (w and size and size[1] and size[1] > 0) and w / size[1] or 1
			g.sy = (h and size and size[2] and size[2] > 0) and h / size[2] or 1
			g.decoded, g.kept, g.keptAt = {}, {}, 0   -- the rows decoded, and which, in the order they came
			M.Ground.grids[cont] = g
		end
	end
end

function M.Ground.Has(cont)
	return M.Ground.grids[cont] ~= nil
end

-- a row's runs: { last column of run 1, its letter, last column of run 2, ... }
function M.Ground.Row(g, r)
	local runs = g.decoded[r]
	if runs then
		return runs
	end
	runs = {}
	local text = g.rows[r + 1]
	if type(text) == "string" then
		local col = 0
		for letter, count in text:gmatch("(%a)(%d*)") do
			col = col + (tonumber(count) or 1)
			runs[#runs + 1] = col - 1
			runs[#runs + 1] = letter
		end
	end
	-- (the oldest row let go once ROWS are kept: a ring of their numbers)
	local slot = g.keptAt % M.Ground.ROWS + 1
	local old = g.kept[slot]
	if old then
		g.decoded[old] = nil
	end
	g.kept[slot], g.keptAt = r, slot
	g.decoded[r] = runs
	return runs
end

-- the letter of a cell (w walk, s swim, x wall, n none), nil off the grid
function M.Ground.At(g, r, q)
	if r < 0 or q < 0 or r >= g.h or q >= g.w then
		return nil
	end
	local runs = M.Ground.Row(g, r)
	local lo, hi = 1, #runs / 2
	if hi < 1 then
		return nil
	end
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		if runs[mid * 2 - 1] < q then
			lo = mid + 1
		else
			hi = mid
		end
	end
	return runs[lo * 2]
end

function M.Ground.Clear(cont, x0, y0, x1, y1)
	local g = M.Ground.grids[cont]
	if not g then
		return nil
	end
	x0, y0, x1, y1 = x0 / g.sx, y0 / g.sy, x1 / g.sx, y1 / g.sy
	local cell, e0, s0 = g.cell, g.e0, g.s0
	local steps = math.max(1, math.ceil(Dist(x0, y0, x1, y1) / cell))
	-- (0.17.1) the cells of the two ends are not asked: someone stands there
	-- (the player, a quest's place, a node), and a wall cell under one -- the
	-- edge of a slope, a house -- cut every leg from it, so the search went
	-- the long way round the continent and over the sea (a fifth of the ends
	-- the hotfix's timing pairs picked)
	local qa, ra = math.floor((x0 - e0) / cell), math.floor((y0 - s0) / cell)
	local qb, rb = math.floor((x1 - e0) / cell), math.floor((y1 - s0) / cell)
	for i = 0, steps do
		local t = i / steps
		local q = math.floor((x0 + (x1 - x0) * t - e0) / cell)
		local r = math.floor((y0 + (y1 - y0) * t - s0) / cell)
		if not ((q == qa and r == ra) or (q == qb and r == rb)) and M.Ground.At(g, r, q) == "x" then
			return false
		end
	end
	return true
end

-- The learned part of the graph: what the saved variable and the baker keep
-- (the flight times learned by timing with it).
local function LearnedOnly()
	local out = { graphs = {}, pins = live.pins, flights = live.flights }
	for cont, g in pairs(live.graphs) do
		local og = {}
		for key, node in pairs(g) do
			if not node[4] then
				local links = {}
				for other, cost in pairs(node[3]) do
					local o = g[other]
					if o and not o[4] then
						links[other] = cost
					end
				end
				og[key] = { node[1], node[2], links }
			end
		end
		out.graphs[cont] = og
	end
	return out
end

--------------------------------------------------------------------------------
-- Docks and zeppelin towers, from the Quest List data
--------------------------------------------------------------------------------

local docks = nil   -- { { cont, x, y, label, pair = index, faction } }

-- World coordinates (continent id, x, y) -> continent map, yards east, yards south.
local worldYards = {}

-- Through the same ContinentOf as the player's own place (0.14.0, the
-- Zephras Isle fix), so the docks, quest places and services on a map share
-- the player's map number: an answer on a map that is not its own continent
-- (a zone, the isle's flight map) is asked again on the one that is, and
-- the isle's world map (2991) is always measured on its zone map (2521).
-- `fresh`: worked out and not kept (the objective places, which
-- Route:ObjectivePlaces keeps per quest itself), the kept ones not looked up.
local YardsOfWorld
do
	local ROOTS = { [2991] = 2521 }
	local vec   -- one vector for every ask (the game reads it and keeps nothing)

	local function Ask(wcont, wx, wy, root)
		if not vec then
			vec = CreateVector2D(0, 0)
		end
		vec.x, vec.y = wx, wy
		local ok, mapID, pos
		if root then
			ok, mapID, pos = pcall(C_Map.GetMapPosFromWorldPos, wcont, vec, root)
		else
			ok, mapID, pos = pcall(C_Map.GetMapPosFromWorldPos, wcont, vec)
		end
		if not ok then
			return nil
		end
		local x, y = VectorXY(pos)
		return Plain(mapID), x, y
	end

	-- (kept by number, [wcont][wx][wy] = { cont, x, y }: a key made of text
	-- made a string per candidate, found or not -- the reach checks' walks)
	YardsOfWorld = function(wcont, wx, wy, fresh)
		local keep = not fresh and wcont ~= nil and wx == wx and wy == wy   -- (nil and NaN are no key)
		if keep then
			local byX = worldYards[wcont]
			local byY = byX and byX[wx]
			local c = byY and byY[wy]
			if c then
				return c[1], c[2], c[3]
			end
		end
		if not (C_Map.GetMapPosFromWorldPos and CreateVector2D) then
			return nil
		end
		local mapID, cx, cy = Ask(wcont, wx, wy)
		local root = ROOTS[wcont] or (mapID and ContinentOf(mapID))
		if root and (root ~= mapID or not (cx and cy)) then
			-- (taken when the game answers on that map; for the isle also when it
			-- answers on its other map, which has the same bounds)
			local m2, rx, ry = Ask(wcont, wx, wy, root)
			if rx and ry and (m2 == root or ROOTS[wcont]) then
				mapID, cx, cy = root, rx, ry
			end
		end
		if not (mapID and cx and cy) then
			return nil   -- not cached: the client may answer later (as RectOn does)
		end
		local cont, x, y = ToYards(mapID, cx, cy)
		if not cont then
			return nil
		end
		if keep then
			local byX = worldYards[wcont]
			if not byX then
				byX = {}
				worldYards[wcont] = byX
			end
			local byY = byX[wx]
			if not byY then
				byY = {}
				byX[wx] = byY
			end
			byY[wy] = { cont, x, y }
		end
		return cont, x, y
	end
end

-- The side a character's rows are for (0.14.0, one side helper for the
-- addon's data rows, whose side is 0 both, 1 Alliance, 2 Horde): 1 or 2,
-- and 0 for a character of neither faction yet (a Neutral one: the rows
-- open to both factions only). M.SideOpen(side[, mine]): whether a row of
-- that side is this character's (`mine`: PlayerSide asked once per scan).
function M.PlayerSide()
	local ok, faction = pcall(UnitFactionGroup, "player")
	faction = ok and MelloUI.Safe.Text(faction) or nil
	if faction == "Alliance" then
		return 1
	elseif faction == "Horde" then
		return 2
	end
	return 0
end

function M.SideOpen(side, mine)
	side = tonumber(side) or 0
	return side == 0 or side == (mine or M.PlayerSide())
end

-- (the docks and the flight points are built for the side they were built
-- with, M.builtSide: a faction chosen later builds them again, M.SideChanged)
local function BuildDocks()
	docks = {}
	edits.hubs = edits.hubs + 1
	local mine = M.PlayerSide()
	M.builtSide = mine
	local data = MelloUI_QuestListData
	if type(data) ~= "table" or type(data.transports) ~= "table" then
		return
	end
	for _, t in ipairs(data.transports) do
		local faction = t[2]
		if faction == 0 or faction == mine then
			local cont, x, y = YardsOfWorld(t[5], t[6], t[7])
			local dcont, dx, dy = YardsOfWorld(t[11], t[12], t[13])
			if cont and dcont then
				docks[#docks + 1] = { cont = cont, x = x, y = y, label = t[3], dest = { dcont, dx, dy }, kind = t[1] }
			end
		end
	end
	-- Pair each dock with the one at its destination.
	for i, d in ipairs(docks) do
		for j, o in ipairs(docks) do
			if i ~= j and o.cont == d.dest[1] and Dist(o.x, o.y, d.dest[2], d.dest[3]) < 60 then
				d.pair = j
			end
		end
	end
end

-- a dock leg's seconds, the wait included: a boat or a zeppelin BOAT_COST;
-- the portal between Darnassus and Rut'theran Village a few seconds, the
-- Deeprun Tram about three minutes (the user, 2026-10-03: "2-4 minutes
-- depending on the wait time for the train"); `d` a dock, or a route point's
-- id ("D3": its dock)
M.DOCK_SECONDS = { [3] = 10, [4] = 180 }

function M.DockSeconds(d)
	if type(d) == "string" then
		local index = tonumber(d:match("^D(%d+)$"))
		d = index and docks and docks[index]
	end
	return d and M.DOCK_SECONDS[d.kind] or BOAT_COST
end

--------------------------------------------------------------------------------
-- Flight points
--
-- The vanilla network comes from the Quest List data (flight time from the
-- path geometry); only flight points the character has discovered count. On
-- top of that, every flight master's map you open teaches the links from
-- there to everything reachable, which also covers Forever's new points.
--------------------------------------------------------------------------------

local taxis = nil            -- [id] = { cont, x, y, name, links = { [id] = seconds } }
local discovered = nil       -- { names = { [lower name] = true }, ids = { [nodeID] = true } } or nil when the client cannot tell
local discoveredAt = 0
local FLIGHT_UNREACHABLE = (Enum and Enum.FlightPathState and Enum.FlightPathState.Unreachable) or 2
local FLIGHT_CURRENT = (Enum and Enum.FlightPathState and Enum.FlightPathState.Current) or 0
local FLIGHT_REACHABLE = (Enum and Enum.FlightPathState and Enum.FlightPathState.Reachable) or 1
local MAP_ZONE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

local function BuildTaxis()
	taxis = {}
	edits.hubs = edits.hubs + 1
	local data = MelloUI_QuestListData
	if type(data) ~= "table" or type(data.taxiNodes) ~= "table" then
		return
	end
	local mine = M.PlayerSide()
	for id, n in pairs(data.taxiNodes) do
		if n[5] == 0 or n[5] == mine then
			local cont, x, y = YardsOfWorld(n[2], n[3], n[4])
			if cont then
				taxis[id] = { cont = cont, x = x, y = y, name = n[1], links = {} }
			end
		end
	end
	for _, p in ipairs(data.taxiPaths or {}) do
		if taxis[p[1]] and taxis[p[2]] then
			taxis[p[1]].links[p[2]] = p[3]
		end
	end
end

-- The same keys in both sets
local function SameKeys(a, b)
	for k in pairs(a) do
		if not b[k] then
			return false
		end
	end
	for k in pairs(b) do
		if not a[k] then
			return false
		end
	end
	return true
end

-- Flight points the character can use, from the world map's own flight point
-- list of every zone. Cached for two minutes, an empty list too (memory
-- audit, 2026-09-24: this client's world map lists none, so every search --
-- every three seconds while there is no route -- asked every zone again);
-- a flight master's map resets it (RememberFlights, LearnFlights).
-- Read only while it decides: once this character knows its own flight
-- points (CharFlights), TaxiUsable goes by those alone, so the search and
-- IsTaxiUsable leave the walk out (user, 2026-09-24, the /melloperf
-- recording: see IsTaxiUsable).
local function RefreshDiscovered()
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap and C_Map.GetMapChildrenInfo) then
		discovered = nil
		return
	end
	if discoveredAt > 0 and GetTime() - discoveredAt < 120 then
		return
	end
	local names, ids, conts = {}, {}, {}
	for _, t in pairs(taxis or {}) do
		conts[t.cont] = true
	end
	-- no flight points loaded yet: nothing asked, so nothing kept
	discoveredAt = next(conts) and GetTime() or 0
	for cont in pairs(conts) do
		local ok, children = pcall(C_Map.GetMapChildrenInfo, cont, MAP_ZONE, true)
		if ok and type(children) == "table" then
			for _, child in ipairs(children) do
				local okN, list = pcall(C_TaxiMap.GetTaxiNodesForMap, child.mapID)
				if okN and type(list) == "table" then
					for _, info in ipairs(list) do
						local name, state = Plain(info.name), Plain(info.state)
						if state ~= FLIGHT_UNREACHABLE then
							if name then names[name:lower()] = true end
							if Plain(info.nodeID) then ids[info.nodeID] = true end
						end
					end
				end
			end
		end
	end
	local before = discovered
	if next(names) or next(ids) then
		discovered = { names = names, ids = ids }
	else
		discovered = nil
	end
	-- other flight points than before: a search that found no way may find one now
	if (before == nil) ~= (discovered == nil)
		or (before and not (SameKeys(before.names, names) and SameKeys(before.ids, ids))) then
		edits.hubs = edits.hubs + 1
	end
end

-- The flight points THIS character knows (user, 2026-09-23: the route sent
-- a character to Booty Bay by air, a flight point it had never found --
-- this client's world map lists no flight points, and "nothing known" was
-- read as "everything usable"). A flight master's own map is the one place
-- the client says which points are known: each time one opens, the known
-- points (the current one and the reachable ones) are kept, per character,
-- as a Route setting: saved with the settings, and in the macro backup too,
-- which brings them back should the saved variables ever be missing.
local charFlights = nil   -- { [nodeID] = true }, read once from the setting

local function CharFlightsKey()
	local ok, guid = pcall(UnitGUID, "player")
	guid = ok and Plain(guid) or nil
	if type(guid) ~= "string" then
		return nil
	end
	return "flights_" .. guid:gsub("[^%w]", "")
end

local function CharFlights()
	if charFlights then
		return charFlights
	end
	local key = CharFlightsKey()
	if not key then
		return {}   -- not yet: asked again later
	end
	charFlights = {}
	edits.hubs = edits.hubs + 1
	local stored = M.db and M.db[key]
	if type(stored) == "string" then
		for id in stored:gmatch("%d+") do
			charFlights[tonumber(id)] = true
		end
	end
	return charFlights
end

local function RememberFlights(ids)
	local key = CharFlightsKey()
	if not (key and M.db) then
		return
	end
	local set, changed = CharFlights(), false
	for id in pairs(ids) do
		if not set[id] then
			set[id], changed = true, true
		end
	end
	if changed then
		edits.hubs = edits.hubs + 1
		local list = {}
		for id in pairs(set) do
			list[#list + 1] = id
		end
		table.sort(list)
		M.db[key] = table.concat(list, ",")
		if MelloUI.ScheduleBackup then
			MelloUI:ScheduleBackup("flight points")
		end
		discoveredAt = 0
	end
end

-- Usable: known to this character from a flight master's map; before any
-- flight master was opened, what the world map lists; with neither, none
-- (walking and boats until the first flight master is opened).
local function TaxiUsable(id, t)
	local mine = CharFlights()
	if next(mine) then
		return mine[id] or false
	end
	if discovered then
		return discovered.ids[id] or discovered.names[t.name:lower()] or false
	end
	return false
end

-- A flight point this character may use within `reach` yards of a place
-- (a learned flight link's ends lie on the flight master)
local function UsableTaxiNear(cont, x, y, reach)
	for id, t in pairs(taxis or {}) do
		if t.cont == cont and Dist(t.x, t.y, x, y) <= reach and TaxiUsable(id, t) then
			return true
		end
	end
	return false
end

-- At a flight master: one graph link from here to every reachable point,
-- costed by the real flight route.
-- At a flight master: which flight points this character knows
local function KnownFlightsHere()
	if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID) then
		return
	end
	local okM, mapID = pcall(GetTaxiMapID)
	mapID = okM and Plain(mapID) or nil
	local okN, list = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
	if not (mapID and okN and type(list) == "table") then
		return
	end
	local ids = {}
	for _, info in ipairs(list) do
		local state, id = Plain(info.state), Plain(info.nodeID)
		if id and (state == FLIGHT_CURRENT or state == FLIGHT_REACHABLE) then
			ids[id] = true
		end
	end
	RememberFlights(ids)
end

local LearnFlights
do
	-- What one flight master's map taught, made in the graph: its node, and a
	-- link to every reachable point of the continent at its flight time
	local function FlightLinks(cont, x, y, legs)
		local akey, a = AddNode(cont, x, y)
		for _, leg in ipairs(legs) do
			local bkey, b = AddNode(cont, leg[1], leg[2])
			if bkey ~= akey then
				Link(cont, a, akey, b, bkey, leg[3])
			end
		end
	end

	LearnFlights = function()
		if not (M.isEnabled and M.db.learn and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID) then
			return
		end
		local okM, mapID = pcall(GetTaxiMapID)
		mapID = okM and Plain(mapID) or nil
		if not mapID then
			return
		end
		local okN, list = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
		if not okN or type(list) ~= "table" then
			return
		end
		local current
		for _, info in ipairs(list) do
			if Plain(info.state) == FLIGHT_CURRENT then
				current = info
			end
		end
		if not current then
			return
		end
		local cx, cy = VectorXY(current.position)
		if not cx then
			return
		end
		local ccont, cyx, cyy = ToYards(mapID, cx, cy)
		if not ccont then
			return
		end
		-- read now, while the map is open; made in the graph now, or once it
		-- is built
		local akey, legs, learned = KeyOf(cyx, cyy), {}, 0
		for _, info in ipairs(list) do
			if Plain(info.state) == FLIGHT_REACHABLE then
				local slot = Plain(info.slotIndex)
				local px, py = VectorXY(info.position)
				local dcont, dx, dy
				if px then
					dcont, dx, dy = ToYards(mapID, px, py)
				end
				if dcont == ccont then
					local length, lx, ly = 0, cyx, cyy
					if slot and GetNumRoutes and TaxiGetDestX and TaxiGetDestY then
						local okR, hops = pcall(GetNumRoutes, slot)
						hops = okR and Plain(hops) or 0
						for h = 1, hops do
							local okX, hx = pcall(TaxiGetDestX, slot, h)
							local okY, hy = pcall(TaxiGetDestY, slot, h)
							hx, hy = okX and Plain(hx) or nil, okY and Plain(hy) or nil
							if hx and hy then
								local hc, hyx, hyy = ToYards(mapID, hx, hy)
								if hc == ccont then
									length = length + Dist(lx, ly, hyx, hyy)
									lx, ly = hyx, hyy
								end
							end
						end
					end
					if length <= 0 then
						length = Dist(cyx, cyy, dx, dy)
					end
					legs[#legs + 1] = { dx, dy, length / FLIGHT + 5 }
					if KeyOf(dx, dy) ~= akey then
						learned = learned + 1
					end
				end
			end
		end
		Build.Learn(FlightLinks, ccont, cyx, cyy, legs)
		if learned > 0 then
			discoveredAt = 0
		end
	end
end

--------------------------------------------------------------------------------
-- Search
--
-- (memory audit, 2026-09-24) A search made about 650 bytes of garbage for
-- every node it looked at -- a "continent|cell" string per step, a new Relax
-- function per node, a table per heap entry, new score tables every time --
-- 8 to 11 MB for one that found no way, run again every three seconds while
-- there was no route. Graph nodes now go by their own table, the working
-- tables are kept from one search to the next, and the heap is three
-- parallel arrays. Links are tried in the order they always were, so the
-- routes come out the same (a node learned since is tried after the older
-- ones near it, which can only choose between two routes of equal cost).
--------------------------------------------------------------------------------

local NodesNear, FindRoute, ForgetLearned   -- in a block: its helpers stay out of the main chunk's 200 locals
local IsFlight   -- the block's rule for a learned flight link, which the travel time prices too

-- (0.17.1, the walking freezes: the user, 2026-10-01, "im having random
-- freezes while walking" / "it happens only when im tracking a quest";
-- docs/plans/hotfix-0.17.1-route-freeze.md) The walk grid's checks ran
-- INSIDE the search: from the start and the goal to every node within
-- OFFROAD (the ground lattice puts hundreds there), from every dock and
-- flight point in every search, and across open ground from every path's
-- end it reached -- up to 300 ms a search, and the tracked quest's pick ran
-- four. Now:
--   legs     with a grid, the LEG_MAX nearest nodes within LEG_NEAR are
--            checked, the ones within OFFROAD (LEG_WIDE checks at most,
--            spread over it) only when none of those is clear; a dock's or
--            a flight point's legs are worked out once and kept (as its
--            nodes near were), the start's once for a pick and the route
--            after it; the cells under a leg's two ends are not asked
--            (M.Ground.Clear)
--   jumps    across open ground only where the ground is not known: the
--            ground's own links are that
--   pricing  one search for every candidate (Search.Price)
--   frames   a search runs in a job of its own that hands over to the next
--            frame when it has used BUDGET ms of this one (Search.Run); its
--            answer is used when it comes -- at once, inside the frame,
--            nearly always
-- The job's state and tunables, one table (the main chunk is near its 200
-- locals): the queue, the job running, when its slice began, what waits
-- for the queue to empty (M:WhenReady), the plan and the pricing pending,
-- the pricings kept (M:Cheapest); counted, for /route and the tests: the
-- searches run, the path ends crossed from (jumps); the seeker frame.
-- BUDGET 3 ms: a slice ends past it after at most EVERY more nodes, inside
-- the 5 ms a slow call starts at (/melloperf).
local Search = { LEG_NEAR = 80, LEG_MAX = 8, LEG_WIDE = 64, BUDGET = 3, EVERY = 16, PRICE_KEEP = 5, PRICE_NEAR = 30,
	PRICE_CAP = 2, PRICE_EXTRA = 120, REPICK_MOVED = 40, queue = {}, running = nil, slice = 0, after = {}, plan = nil,
	pricing = {}, priced = {}, runs = 0, jumps = 0, frame = nil }

do
	-- Nodes grouped in 250-yard buckets per continent, built on first use and
	-- then kept up to date as nodes are added (memory audit, 2026-09-24: it
	-- was built anew after every new node, 617 KB each time on new ground).
	local BUCKET = 250
	local buckets = nil   -- [cont][bucket number] = { key, ... }

	local function BucketOf(x, y)
		return math.floor(x / BUCKET) * 100000 + math.floor(y / BUCKET)
	end

	local function Buckets(cont)
		if not buckets then
			buckets = {}
			for c, g in pairs(live.graphs) do
				local index = {}
				for key, node in pairs(g) do
					local bk = BucketOf(node[1], node[2])
					local list = index[bk]
					if not list then
						list = {}
						index[bk] = list
					end
					list[#list + 1] = key
				end
				buckets[c] = index
			end
		end
		return buckets[cont]
	end

	-- Graph nodes within `radius` yards of a point, as { key = distance }.
	NodesNear = function(cont, x, y, radius)
		local g = live.graphs[cont]
		local found = {}
		if not g then
			return found, 0
		end
		local index = Buckets(cont)
		if not index then
			return found, 0
		end
		local count = 0
		local span = math.ceil(radius / BUCKET)
		local bx, by = math.floor(x / BUCKET), math.floor(y / BUCKET)
		for i = -span, span do
			for j = -span, span do
				local list = index[(bx + i) * 100000 + by + j]
				if list then
					for _, key in ipairs(list) do
						local node = g[key]
						if node then
							local d = Dist(x, y, node[1], node[2])
							if d <= radius then
								found[key] = d
								count = count + 1
							end
						end
					end
				end
			end
		end
		return found, count
	end

	-- (0.17.1) NodesNear into two lists kept from one call to the next (the
	-- keys in nearKey, their yards in nearD, `n` of them), for the legs below
	local nearKey, nearD = {}, {}
	local function NearList(cont, x, y, radius)
		local g = live.graphs[cont]
		local index = g and Buckets(cont)
		local n = 0
		if index then
			local span = math.ceil(radius / BUCKET)
			local bx, by = math.floor(x / BUCKET), math.floor(y / BUCKET)
			for i = -span, span do
				for j = -span, span do
					local list = index[(bx + i) * 100000 + by + j]
					if list then
						for _, key in ipairs(list) do
							local node = g[key]
							if node then
								local d = Dist(x, y, node[1], node[2])
								if d <= radius then
									n = n + 1
									nearKey[n], nearD[n] = key, d
								end
							end
						end
					end
				end
			end
		end
		return n
	end

	-- the `k` nearest of NearList's `n` moved to its front, nearest first (a
	-- selection: k is small)
	local function NearestFirst(n, k)
		for i = 1, math.min(k, n) do
			local m = i
			for j = i + 1, n do
				if nearD[j] < nearD[m] then
					m = j
				end
			end
			nearKey[i], nearKey[m] = nearKey[m], nearKey[i]
			nearD[i], nearD[m] = nearD[m], nearD[i]
		end
	end

	-- (0.17.1) The legs from a point to the graph on a continent whose ground
	-- is known: the nearest LEG_MAX nodes within LEG_NEAR whose straight line
	-- the walk grid allows (the ground lattice is about 40 yd apart). When
	-- none is: the nodes within OFFROAD past those, nearest first, LEG_WIDE of
	-- them checked at most, spread over the whole reach (a wall round the
	-- player hides the nearest ones, however many a town has), until LEG_MAX
	-- are. Into legKey / legD (kept), their count returned.
	local legKey, legD = {}, {}
	local order = {}   -- the second pass's nodes (their places in nearKey / nearD), nearest first
	local function ByNear(i, j)
		return nearD[i] < nearD[j]
	end

	local function Legs(cont, x, y)
		local g = live.graphs[cont]
		if not g then
			return 0
		end
		local count = 0
		local n = NearList(cont, x, y, Search.LEG_NEAR)
		local k = math.min(Search.LEG_MAX, n)
		NearestFirst(n, k)
		for i = 1, k do
			local node = g[nearKey[i]]
			if node and M.Ground.Clear(cont, x, y, node[1], node[2]) ~= false then
				count = count + 1
				legKey[count], legD[count] = nearKey[i], nearD[i]
			end
		end
		if count > 0 then
			return count
		end
		local checked = k > 0 and nearD[k] or -1
		n = NearList(cont, x, y, OFFROAD)
		local m = 0
		for i = 1, n do
			if nearD[i] > checked then
				m = m + 1
				order[m] = i
			end
		end
		for i = #order, m + 1, -1 do
			order[i] = nil
		end
		table.sort(order, ByNear)
		for s = 1, m, math.max(1, math.ceil(m / Search.LEG_WIDE)) do
			local i = order[s]
			local node = g[nearKey[i]]
			if node and M.Ground.Clear(cont, x, y, node[1], node[2]) ~= false then
				count = count + 1
				legKey[count], legD[count] = nearKey[i], nearD[i]
				if count >= Search.LEG_MAX then
					break
				end
			end
			Search.Yield()
		end
		return count
	end

	-- Neighbourhood links of a fixed hub (dock, flight point), kept until a
	-- node is added near it (memory audit, 2026-09-24: every new node threw
	-- all of them away). Where the ground is known its legs themselves are
	-- kept (0.17.1, hubLegs: { node key, yards, node key, yards, ... }): the
	-- walk grid's checks of every hub ran in every search.
	local hubNear, hubAt, hubLegs = {}, {}, {}   -- [id] = its NodesNear, [id] = { cont, x, y } it was taken at, [id] = its legs
	-- A dead end's NodesNear at JUMP, kept only while big searches follow one
	-- another (a player off a long route is routed again every two seconds)
	-- and let go with the working tables below: [cont][node] = near
	local jumpNear = {}

	local function HubNear(id, cont, x, y)
		local near, at = hubNear[id], hubAt[id]
		if not (near and at[1] == cont and at[2] == x and at[3] == y) then
			near = NodesNear(cont, x, y, OFFROAD)
			hubNear[id], hubAt[id] = near, { cont, x, y }
		end
		return near
	end

	NodeAdded = function(cont, key, node)
		if buckets then
			local index = buckets[cont]
			if not index then
				index = {}
				buckets[cont] = index
			end
			local bk = BucketOf(node[1], node[2])
			local list = index[bk]
			if not list then
				list = {}
				index[bk] = list
			end
			list[#list + 1] = key
		end
		-- the hubs and dead ends that may see it (a yard to spare) look again
		for id, at in pairs(hubAt) do
			if at[1] == cont and Dist(at[2], at[3], node[1], node[2]) <= OFFROAD + 1 then
				hubNear[id], hubAt[id], hubLegs[id] = nil, nil, nil
			end
		end
		local ends = jumpNear[cont]
		if ends then
			for n in pairs(ends) do
				if Dist(n[1], n[2], node[1], node[2]) <= JUMP + 1 then
					ends[n] = nil
				end
			end
		end
	end

	-- A start link that points back the way the player is walking is priced
	-- BEHIND_COST times its length (user, 2026-09-22: the arrow sent the player
	-- back to the road behind them, "the checkpoint", after a shortcut): the
	-- planner then joins the road ahead unless going back is a real saving.
	local BEHIND_COST = 2.5

	local FLIGHT_LINK_MIN = 200   -- yards: a shorter link is never taken for a flight
	local FLIGHT_END_REACH = 90   -- yards: a flight link's end lies this near its flight master

	-- A link of d yards far quicker than walking (cost seconds) is a flight
	-- (learned at a flight master, maybe by another character). The one rule
	-- for it: the travel time prices such a link by it too (Travel.LinkFlight).
	IsFlight = function(d, cost)
		return d > FLIGHT_LINK_MIN and cost < d / WALK * 0.5
	end

	-- The working tables, kept from one search to the next and wiped. They
	-- keep the size of the biggest search since, so they are let go once no
	-- search has run for SCRATCH_IDLE seconds, or SCRATCH_IDLE_BIG after one
	-- that expanded more than SCRATCH_KEEP nodes (2-4 MB for a road across a
	-- continent): the memory is only held while it is saving garbage. Graph
	-- nodes go by their own table; the start ("S"), the goal ("G"; a
	-- pricing's goals "G1", "G2" ...), docks ("D<i>"), flight points
	-- ("T<id>") and a link to a cell with no node ("c|key") by string.
	local SCRATCH_KEEP, SCRATCH_IDLE, SCRATCH_IDLE_BIG = 500, 20, 4
	local gScore, from, closed = {}, {}, {}   -- per node: cost so far, the node before, expanded
	local heapId, heapF, heapCont, heapN = {}, {}, {}, 0   -- binary heap keyed by f
	local extra, nodeExtra, pos = {}, {}, {}   -- id -> { otherId = cost }, graph node -> its extra, id -> { cont, x, y }
	local flightEnds = {}   -- [node] = a flight point this character may use is at it
	local sBase, sFrom          -- the node being expanded: its cost so far, itself
	local sSpeed, sHx, sHy      -- the estimate's speed, the heading
	-- the goals: `n` of them, each its id, continent and place; of[id] = its
	-- number (0.17.1: a pricing has several, a route one, "G")
	local goals = { n = 0, id = {}, cont = {}, x = {}, y = {}, of = {}, ids = {} }
	-- the start's legs as last worked out (0.17.1: a pick's search and the
	-- route's after it start from the same place): where, at which graph
	-- edit, the legs' node keys and yards
	local startLegs = { cont = nil, x = 0, y = 0, edits = -1, n = 0, keys = {}, ds = {} }
	local hubIds = {}   -- the flight points' ids, gathered before their legs are made (a search may yield there)
	local lastSearch, releaseQueued, scratchBig = 0, false, false
	-- [scont][gcont] = { hub edits, other continents' edits } of a search that found no way
	local failed = {}

	local function ReleaseIfIdle()
		if Search.running or #Search.queue > 0 then
			C_Timer.After(SCRATCH_IDLE_BIG, ReleaseIfIdle)   -- (never under a search that waits for its next frame)
			return
		end
		if GetTime() - lastSearch < (scratchBig and SCRATCH_IDLE_BIG or SCRATCH_IDLE) then
			C_Timer.After(SCRATCH_IDLE_BIG, ReleaseIfIdle)
			return
		end
		releaseQueued, scratchBig = false, false
		gScore, from, closed, extra, nodeExtra, pos, flightEnds = {}, {}, {}, {}, {}, {}, {}
		heapId, heapF, heapCont, heapN = {}, {}, {}, 0
		jumpNear = {}
	end

	-- Small binary heap keyed by f.
	local function Push(id, f, cont)
		local n = heapN + 1
		heapN = n
		heapId[n], heapF[n], heapCont[n] = id, f, cont
		while n > 1 do
			local p = math.floor(n / 2)
			if heapF[p] <= heapF[n] then
				break
			end
			heapId[p], heapId[n] = heapId[n], heapId[p]
			heapF[p], heapF[n] = heapF[n], heapF[p]
			heapCont[p], heapCont[n] = heapCont[n], heapCont[p]
			n = p
		end
	end

	local function Pop()
		local n = heapN
		if n == 0 then
			return nil
		end
		local id, cont, f = heapId[1], heapCont[1], heapF[1]
		heapId[1], heapF[1], heapCont[1] = heapId[n], heapF[n], heapCont[n]
		heapId[n], heapF[n], heapCont[n] = nil, nil, nil
		n = n - 1
		heapN = n
		local i = 1
		while true do
			local l, r, s = i * 2, i * 2 + 1, i
			if l <= n and heapF[l] < heapF[s] then s = l end
			if r <= n and heapF[r] < heapF[s] then s = r end
			if s == i then
				break
			end
			heapId[s], heapId[i] = heapId[i], heapId[s]
			heapF[s], heapF[i] = heapF[i], heapF[s]
			heapCont[s], heapCont[i] = heapCont[i], heapCont[s]
			i = s
		end
		return id, cont, f
	end

	local function SetPos(id, cont, x, y)
		local p = pos[id]
		if not p then
			p = {}
			pos[id] = p
		end
		p[1], p[2], p[3] = cont, x, y
	end

	local function Position(id)
		local p = pos[id]
		if p then
			return p[1], p[2], p[3]
		end
		local cont, key = id:match("^(%d+)|(.+)$")
		cont = tonumber(cont)
		local node = cont and live.graphs[cont] and live.graphs[cont][key]
		if node then
			return cont, node[1], node[2]
		end
		return nil
	end

	-- the estimate to the goal at the fastest way this character can travel
	-- (several goals: to the nearest, and none while one is on another
	-- continent -- the least of the goals' own estimates, never more than
	-- any of them)
	local function Heuristic(id, cont)
		local x, y
		if type(id) == "table" then
			x, y = id[1], id[2]
		else
			local p = pos[id]
			if not p then
				return 0   -- a link to a cell with no node
			end
			cont, x, y = p[1], p[2], p[3]
		end
		local gc, gx, gy = goals.cont, goals.x, goals.y
		if goals.n == 1 then
			if cont ~= gc[1] then
				return 0
			end
			return Dist(x, y, gx[1], gy[1]) / sSpeed
		end
		local best
		for i = 1, goals.n do
			if cont ~= gc[i] then
				return 0
			end
			local d = Dist(x, y, gx[i], gy[i])
			if not best or d < best then
				best = d
			end
		end
		return (best or 0) / sSpeed
	end

	-- One link out of the node being expanded
	local function Relax(other, cont, cost)
		local tentative = sBase + cost
		local old = gScore[other]
		if old == nil or tentative < old then
			gScore[other] = tentative
			from[other] = sFrom
			Push(other, tentative + Heuristic(other, cont), cont)
		end
	end

	-- One link of the extra table, where graph nodes are "c|key"
	local function RelaxId(other, cost)
		local c, key = other:match("^(%d+)|(.+)$")
		c = tonumber(c)
		local g = c and live.graphs[c]
		local node = g and g[key]
		if node then
			Relax(node, c, cost)
		else
			Relax(other, nil, cost)
		end
	end

	-- Both ends of a flight link at a flight point this character may use
	local function FlightEnd(cont, node)
		local v = flightEnds[node]
		if v == nil then
			v = UsableTaxiNear(cont, node[1], node[2], FLIGHT_END_REACH)
			flightEnds[node] = v
		end
		return v
	end

	local function AddExtra(a, b, cost)
		extra[a] = extra[a] or {}
		extra[b] = extra[b] or {}
		if extra[a][b] == nil or extra[a][b] > cost then extra[a][b] = cost end
		if extra[b][a] == nil or extra[b][a] > cost then extra[b][a] = cost end
	end

	-- One leg from a point to the graph node `key`, `d` yards away
	local function Leg(id, cont, x, y, key, d, node)
		local cost = d / WALK * 1.3
		if id == "S" and sHx and d > 5 and node then
			-- the node's direction from the player against the heading
			local dot = ((node[1] - x) * sHx + (node[2] - y) * sHy) / d
			if dot < -0.3 then
				cost = cost * BEHIND_COST
			elseif dot < 0.3 then
				cost = cost * (1 + (0.3 - dot) * (BEHIND_COST - 1) / 0.6)   -- sideways: in between
			end
		end
		local nid = cont .. "|" .. key
		AddExtra(id, nid, cost)
		if node then
			nodeExtra[node] = extra[nid]
		end
	end

	-- A point's legs to the graph. Where the ground is not known: every node
	-- within OFFROAD, as ever. Where it is (0.17.0: a leg over a wall is no
	-- leg): the nearest clear ones (Legs, 0.17.1), a hub's kept, the start's
	-- kept while the player and the graph stay as they were.
	local function LinkPoint(id, cont, x, y, cached)
		local g = live.graphs[cont]
		if not M.Ground.Has(cont) then
			local near = cached and HubNear(id, cont, x, y) or NodesNear(cont, x, y, OFFROAD)
			for key, d in pairs(near) do
				Leg(id, cont, x, y, key, d, g and g[key])
			end
			return
		end
		local n, keys, ds
		if cached then
			local list, at = hubLegs[id], hubAt[id]
			if not (list and at and at[1] == cont and at[2] == x and at[3] == y) then
				local count = Legs(cont, x, y)
				list = {}
				for i = 1, count do
					list[i * 2 - 1], list[i * 2] = legKey[i], legD[i]
				end
				hubLegs[id], hubAt[id], hubNear[id] = list, { cont, x, y }, nil
			end
			for i = 1, #list, 2 do
				local key = list[i]
				Leg(id, cont, x, y, key, list[i + 1], g and g[key])
			end
			return
		elseif id == "S" then
			local s = startLegs
			if not (s.cont == cont and s.edits == edits.all and Dist(s.x, s.y, x, y) < 1) then
				local at = edits.all   -- (as it was when the legs were begun: an edit while they are made counts)
				local count = Legs(cont, x, y)
				for i = 1, count do
					s.keys[i], s.ds[i] = legKey[i], legD[i]
				end
				s.cont, s.x, s.y, s.edits, s.n = cont, x, y, at, count
			end
			n, keys, ds = s.n, s.keys, s.ds
		else
			n, keys, ds = Legs(cont, x, y), legKey, legD
		end
		for i = 1, n do
			local key = keys[i]
			Leg(id, cont, x, y, key, ds[i], g and g[key])
		end
	end

	-- a straight leg from the start or to the goal to a dock / flight point:
	-- a short hop as walking, a long one only as a last resort
	local function HubLeg(d)
		if d <= OFFROAD then
			return d / WALK * 1.3
		end
		return d / WALK * FAR_HUB_COST
	end

	-- The goals of the next search: `n` of them; GoalId(i) the i-th of a
	-- pricing's ids ("G1" ...), made once
	local function GoalId(i)
		local id = goals.ids[i]
		if not id then
			id = "G" .. i
			goals.ids[i] = id
		end
		return id
	end

	local function SetGoal(i, id, cont, x, y)
		goals.id[i], goals.cont[i], goals.x[i], goals.y[i] = id, cont, x, y
		goals.of[id] = i
	end

	local function ClearGoals()
		for i = 1, goals.n do
			goals.of[goals.id[i]] = nil
		end
		goals.n = 0
	end

	-- a hub's straight leg from the start and to each goal on its continent
	local function HubEnds(id, cont, x, y, scont, sx, sy)
		if cont == scont then
			AddExtra("S", id, HubLeg(Dist(x, y, sx, sy)))
		end
		for i = 1, goals.n do
			if cont == goals.cont[i] then
				AddExtra(goals.id[i], id, HubLeg(Dist(x, y, goals.x[i], goals.y[i])))
			end
		end
	end

	-- The start, the goals (set before: SetGoal), the docks and the flight
	-- points, linked to the graph and to each other. The hubs are walked by
	-- number (0.17.1: a search may hand over to the next frame inside, and a
	-- table walked by pairs must not grow meanwhile)
	local function Begin(scont, sx, sy, hx, hy)
		wipe(gScore)
		wipe(from)
		wipe(closed)
		wipe(extra)
		wipe(nodeExtra)
		wipe(flightEnds)
		for i = heapN, 1, -1 do
			heapId[i], heapF[i], heapCont[i] = nil, nil, nil
		end
		heapN = 0
		sHx, sHy = hx, hy
		SetPos("S", scont, sx, sy)
		for i = 1, goals.n do
			SetPos(goals.id[i], goals.cont[i], goals.x[i], goals.y[i])
		end
		LinkPoint("S", scont, sx, sy)
		for i = 1, goals.n do
			LinkPoint(goals.id[i], goals.cont[i], goals.x[i], goals.y[i])
		end
		local list = docks or {}
		for i = 1, #list do
			local d = list[i]
			local id = "D" .. i
			SetPos(id, d.cont, d.x, d.y)
			LinkPoint(id, d.cont, d.x, d.y, true)
			if d.pair then
				AddExtra(id, "D" .. d.pair, M.DockSeconds(d))
			end
			HubEnds(id, d.cont, d.x, d.y, scont, sx, sy)
			Search.Yield()
		end
		local all = taxis or {}
		local n = 0
		for tid in pairs(all) do
			n = n + 1
			hubIds[n] = tid
		end
		for i = #hubIds, n + 1, -1 do
			hubIds[i] = nil
		end
		for i = 1, n do
			local tid = hubIds[i]
			local t = all[tid]
			if t and TaxiUsable(tid, t) then
				local nid = "T" .. tid
				SetPos(nid, t.cont, t.x, t.y)
				LinkPoint(nid, t.cont, t.x, t.y, true)
				for other, secs in pairs(t.links) do
					if all[other] and TaxiUsable(other, all[other]) then
						AddExtra(nid, "T" .. other, secs)
					end
				end
				HubEnds(nid, t.cont, t.x, t.y, scont, sx, sy)
			end
			Search.Yield()
		end
		-- (0.17.0: the direct line only where the ground allows it, or is not known)
		for i = 1, goals.n do
			local gx, gy = goals.x[i], goals.y[i]
			if scont == goals.cont[i] and M.Ground.Clear(scont, sx, sy, gx, gy) ~= false then
				AddExtra("S", goals.id[i], Dist(sx, sy, gx, gy) / WALK * STRAIGHT_COST)
			end
		end
		-- the estimate at the fastest way this character can travel: flying
		-- only with a usable flight point on a goal's continent, else walking
		-- (a far tighter estimate: the long road searches finish)
		local speed = WALK
		for i = 1, n do
			local tid = hubIds[i]
			local t = all[tid]
			if t and TaxiUsable(tid, t) then
				for k = 1, goals.n do
					if t.cont == goals.cont[k] then
						speed = FLIGHT
					end
				end
			end
		end
		sSpeed = speed
	end

	-- The links out of one node
	local function Expand(id, cont)
		sBase, sFrom = gScore[id], id
		local ex
		if type(id) == "table" then
			local g, links = live.graphs[cont], id[3]
			local degree = 0
			for k, cost in pairs(links) do
				-- a flight only between two flight points this character may use
				local o = g[k]
				if not (o and IsFlight(Dist(id[1], id[2], o[1], o[2]), cost)) or (FlightEnd(cont, id) and FlightEnd(cont, o)) then
					Relax(o or (cont .. "|" .. k), cont, cost)
				end
				degree = degree + 1
			end
			-- the end of a path: cross open ground to any path nearby -- only
			-- where the ground is not known (0.17.1: the ground's own links are
			-- that, and the walk grid's check of every jump cost the most)
			if degree <= 1 and not M.Ground.Has(cont) then
				Search.jumps = Search.jumps + 1
				local ends = scratchBig and jumpNear[cont]
				local near = ends and ends[id]
				if not near then
					near = NodesNear(cont, id[1], id[2], JUMP)
					if scratchBig then
						ends = ends or {}
						jumpNear[cont] = ends
						ends[id] = near
					end
				end
				for k, d in pairs(near) do
					local o = g[k]
					if o ~= id and links[k] == nil then
						Relax(o, cont, d / WALK * JUMP_COST)
					end
				end
			end
			ex = nodeExtra[id]
		else
			ex = extra[id]
		end
		if ex then
			for other, cost in pairs(ex) do
				RelaxId(other, cost)
			end
		end
	end

	-- Walk back from the goal; graph nodes are "c|key" in the points, as ever.
	local function Path()
		local ids = {}
		local id = "G"
		while id do
			if type(id) == "table" then
				local key = KeyOf(id[1], id[2])
				local name
				for c, g in pairs(live.graphs) do
					if g[key] == id then
						name = c .. "|" .. key
						break
					end
				end
				ids[#ids + 1] = name or "?"
			else
				ids[#ids + 1] = id
			end
			id = from[id]
		end
		for i = 1, math.floor(#ids / 2) do
			ids[i], ids[#ids + 1 - i] = ids[#ids + 1 - i], ids[i]
		end
		local points = {}
		for i, nid in ipairs(ids) do
			local cont, x, y = Position(nid)
			if cont then
				local prev = ids[i - 1]
				local kind = "road"
				local hubNow, hubPrev = nid:sub(1, 1), prev and prev:sub(1, 1)
				local isHubNow, isHubPrev = hubNow == "D" or hubNow == "T", hubPrev == "D" or hubPrev == "T"
				if not prev or nid == "G" or prev == "S" or isHubNow or isHubPrev then
					kind = "guess"
				elseif prev then
					local pc, pk = prev:match("^(%d+)|(.+)$")
					local _, nk = nid:match("^(%d+)|(.+)$")
					local pnode = pc and live.graphs[tonumber(pc)] and live.graphs[tonumber(pc)][pk]
					if pnode and nk and pnode[3][nk] == nil then
						kind = "guess"
					end
				end
				if isHubPrev and isHubNow then
					kind = hubPrev == "T" and "flight" or "boat"
				end
				points[#points + 1] = { cont, x, y, kind, nid }
			end
		end
		return points, gScore.G
	end

	-- The search from the start to Begin's goals: until the one goal ("G")
	-- is reached, or every goal of a pricing is (`single` false: each one's
	-- cost then in gScore, the goals never expanded -- a way through one to
	-- another is not the way the player walks to that one), or none can be
	-- any more. Every EVERY nodes it may hand over to the next frame
	-- (Search.Yield: only inside a job). How it ended: "found", "none" (no
	-- way), "big" (past 60,000 nodes), "cap" (a pricing's other goals cost
	-- more than PRICE_CAP times the cheapest's and PRICE_EXTRA seconds: no
	-- choice, whatever they cost)
	local function Walk(scont, single)
		gScore.S = 0
		Push("S", Heuristic("S"), scont)
		local expanded, settled, cap = 0, 0, nil
		local ended
		while true do
			local id, cont, f = Pop()
			if not id then
				ended = "none"
				break
			end
			if single then
				if id == "G" then
					ended = "found"
					break
				end
			elseif cap and f > cap then
				ended = "cap"
				break
			end
			if not closed[id] then
				closed[id] = true
				if not single and goals.of[id] then
					settled = settled + 1
					cap = cap or gScore[id] * Search.PRICE_CAP + Search.PRICE_EXTRA
					if settled >= goals.n then
						ended = "found"
						break
					end
				else
					expanded = expanded + 1
					if expanded > 60000 then
						scratchBig = true
						return "big"
					end
					Expand(id, cont)
					if expanded % Search.EVERY == 0 then
						Search.Yield()
					end
				end
			end
		end
		scratchBig = scratchBig or expanded > SCRATCH_KEEP
		return ended
	end

	local function Searched()
		Search.runs = Search.runs + 1
		lastSearch = GetTime()
		if not releaseQueued then
			releaseQueued = true
			C_Timer.After(SCRATCH_IDLE_BIG, ReleaseIfIdle)
		end
	end

	-- Route from (scont, sx, sy) to (gcont, gx, gy): a list of { cont, x, y, kind }
	-- points and the total cost in seconds, or nil.
	FindRoute = function(scont, sx, sy, gcont, gx, gy, hx, hy)
		-- the character's own flight points, read before the memo below (the
		-- first read counts as a hub change); the world map's list only while
		-- there are none, as in IsTaxiUsable
		if not next(CharFlights()) then
			RefreshDiscovered()
		end
		-- (memory audit, 2026-09-24) The start is linked to every dock and
		-- flight point of its continent and the goal to every one of its own,
		-- so whether another continent can be reached at all does not hang on
		-- where the two ends are on them: a search that found no way is not
		-- run again until the hubs or a third continent's paths change.
		local others
		if scont ~= gcont then
			others = edits.all - (edits.conts[scont] or 0) - (edits.conts[gcont] or 0)
			local memo = failed[scont] and failed[scont][gcont]
			if memo and memo[1] == edits.hubs and memo[2] == others then
				return nil
			end
		end
		Searched()
		ClearGoals()
		SetGoal(1, "G", gcont, gx, gy)
		goals.n = 1
		Begin(scont, sx, sy, hx, hy)
		local ended = Walk(scont, true)
		if ended ~= "found" then
			if ended == "none" and others then
				failed[scont] = failed[scont] or {}
				failed[scont][gcont] = { edits.hubs, others }
			end
			return nil
		end
		return Path()
	end

	-- (0.17.1) What each of `places` ({ cont, x, y } each) costs from
	-- (scont, sx, sy), in seconds, in ONE search (it was one search a place:
	-- the tracked quest's pick ran three, Services' nearest six): out[i] its
	-- cost, nil where the search did not reach it. True when the ones not
	-- reached have no way it could find (it ran out of graph, or past 60,000
	-- nodes, where FindRoute gave none either), false when it stopped at the
	-- cap (Walk's "cap").
	function Search.Price(scont, sx, sy, places, out)
		if not next(CharFlights()) then
			RefreshDiscovered()
		end
		local n = #places
		for i = 1, n do
			out[i] = nil
		end
		if n == 0 then
			return true
		end
		Searched()
		ClearGoals()
		for i = 1, n do
			local p = places[i]
			SetGoal(i, GoalId(i), p[1], p[2], p[3])
		end
		goals.n = n
		Begin(scont, sx, sy)
		local ended = Walk(scont, false)
		for i = 1, n do
			local id = goals.id[i]
			out[i] = closed[id] and gScore[id] or nil
		end
		return ended ~= "cap"
	end

	-- (0.17.1) The jobs. A search runs in a coroutine of its own, one at a
	-- time (they share the working tables above), in a queue: the first is
	-- begun as it is asked for, in the asker's frame, and nearly always ends
	-- there; one that has used BUDGET ms of the frame hands over to the next
	-- (Search.Yield, between nodes and between hubs) and goes on there, from
	-- the seeker frame's OnUpdate, shown only while a job waits. A job is a
	-- table: kind "route" (scont, sx, sy, gcont, gx, gy, hx, hy -> points,
	-- cost) or "price" (scont, sx, sy, places, costs -> costs filled,
	-- exhausted), and done(job), called when it ends in a later frame. A
	-- stale job (asked for again since) is dropped unanswered; one whose graph
	-- was reset under it begins again (ForgetLearned).
	local OnSeek   -- the seeker frame's OnUpdate (Search.frame: made with the first job that waits for a frame)

	local function Clock()
		local f = debugprofilestop
		return f and f() or 0
	end

	function Search.Yield()
		local job = Search.running
		if job and coroutine.running() == job.co and Clock() - Search.slice > Search.BUDGET then
			coroutine.yield()
		end
	end

	local function Work(job)
		if job.kind == "price" then
			job.exhausted = Search.Price(job.scont, job.sx, job.sy, job.places, job.costs)
		else
			job.points, job.cost = FindRoute(job.scont, job.sx, job.sy, job.gcont, job.gx, job.gy, job.hx, job.hy)
		end
	end

	-- one slice of a job: true when it has ended
	local function Slice(job)
		if not job.co then
			job.co = coroutine.create(Work)
		end
		Search.running, Search.slice = job, Clock()
		local ok, err = coroutine.resume(job.co, job)
		Search.running = nil
		if not ok then
			job.failed, job.ended = true, true   -- (never waited for again)
			MelloUI:Print("|cffff4040Error|r in module 'Route' (finding a way): %s", tostring(err))
			return true
		end
		return coroutine.status(job.co) == "dead"
	end

	-- Search.Run(job) -> true when it has ended already (its answers in it);
	-- else its done(job) is called in the frame it ends
	function Search.Run(job)
		local q = Search.queue
		while q[1] and q[1].stale do
			table.remove(q, 1)   -- (asked for again since: the new one may begin now)
		end
		q[#q + 1] = job
		if #q == 1 and Slice(job) then
			table.remove(q, 1)
			return true
		end
		local seeker = Search.frame
		if not seeker then
			seeker = CreateFrame("Frame")
			Perf.SetScript(seeker, "OnUpdate", OnSeek)
			Search.frame = seeker
		end
		seeker:Show()
		return false
	end

	-- whether a search is under way (asked for, not ended)
	function Search.Busy()
		return #Search.queue > 0
	end

	-- fn run once no search is under way (M:WhenReady)
	function Search.After(fn)
		local list = Search.after
		list[#list + 1] = fn
	end

	local function Told(ok, err)
		if not ok then
			MelloUI:Print("|cffff4040Error|r in module 'Route' (after finding a way): %s", tostring(err))
		end
	end

	OnSeek = function()
		local q = Search.queue
		if not M.isEnabled then
			-- switched off meanwhile: nothing more found, nothing waits
			for i = 1, #q do
				q[i].stale, q[i].ended = true, true
			end
			wipe(q)
			wipe(Search.after)
			Search.repickDue = false
			Search.frame:Hide()
			Build.Loaded()   -- (the loading line, if it waited for this search: never held)
			return
		end
		local job = q[1]
		if job then
			if job.stale then
				table.remove(q, 1)   -- (begun or not: its working tables are wiped by the next one's Begin)
			elseif Slice(job) then
				table.remove(q, 1)
				if not job.failed and not job.stale and job.done then
					Told(pcall(job.done, job))
				end
			end
		end
		if #q == 0 then
			Search.frame:Hide()
			local after = Search.after
			if #after > 0 then
				Search.after = {}
				for i = 1, #after do
					Told(pcall(after[i]))
				end
			end
		end
	end

	-- /route reset: the learned nodes go, with every link to them, and the
	-- links learned between two roads get the road's own cost back; the
	-- traced roads stay as they were merged (memory audit, 2026-09-24: the
	-- road data is let go once merged, so it is no longer merged in afresh)
	ForgetLearned = function()
		for node, e in pairs(roadEdits) do
			for key, cost in pairs(e) do
				node[3][key] = cost or nil
			end
		end
		roadEdits = {}
		local roads = 0
		for _, g in pairs(live.graphs) do
			for key, node in pairs(g) do
				if not node[4] then
					g[key] = nil
				end
			end
			for _, node in pairs(g) do
				roads = roads + 1
				local links = node[3]
				for other in pairs(links) do
					if not g[other] then
						links[other] = nil
					end
				end
			end
		end
		tracedNodes = roads
		buckets = nil
		wipe(hubNear)
		wipe(hubAt)
		wipe(hubLegs)
		wipe(failed)
		jumpNear = {}
		startLegs.edits = -1
		-- (0.17.1) a search waiting for its next frame begins again on the graph as it is now
		for _, job in ipairs(Search.queue) do
			job.co = nil
		end
	end
end

--------------------------------------------------------------------------------
-- Current route
--------------------------------------------------------------------------------

local route = nil        -- { points = {...}, cost = seconds, length = yards, dest = { cont, x, y } }
local destination = nil  -- { cont, x, y, mapID, mx, my, label }
-- The stand-in (see "Another continent"): the map pin on the dock where the
-- route leaves the player's continent while the destination is on another,
-- or on a needed item's source (Needed).
-- { cont, x, y, label, pin = { mapID, mx, my } given back, questID given back }
local standIn = nil
local crossContinent = false   -- the destination on another continent than the player
local StandIn = {}             -- its functions (Update, IsPin, GiveBackSaved, Drop), below
local lastPlan = 0
local offRoute = false   -- the player is farther than OFF_ROUTE from the path (see the arrow)
local offRouteSince = nil   -- when the player left the path (GetTime), nil while on it
local OFF_ROUTE_SECONDS = 2    -- off the path this long before a new route is planned (the arrow's OFF_ROUTE yards)
local REPLAN_SECONDS = 30      -- a followed route is refreshed this often at most

-- The player's heading: the direction of the last few yards walked, nil
-- while standing. Read by the planner (a start link that points back the
-- way the player came costs more) and by the arrow.
local headTrail = {}   -- the last positions { t, cont, x, y }
local HEAD_YARDS = 4

local function NoteHeading(cont, x, y)
	local now = GetTime()
	local n = #headTrail
	if n == 0 or headTrail[n][2] ~= cont or Dist(headTrail[n][3], headTrail[n][4], x, y) >= 1 then
		headTrail[n + 1] = { now, cont, x, y }
	end
	-- the last 3 seconds only
	while #headTrail > 1 and now - headTrail[1][1] > 3 do
		table.remove(headTrail, 1)
	end
end

local function Heading(cont)
	local n = #headTrail
	if n < 2 then
		return nil
	end
	local a, b = headTrail[1], headTrail[n]
	if a[2] ~= cont or b[2] ~= cont or GetTime() - b[1] > 2 then
		return nil   -- another continent, or standing for two seconds
	end
	local dx, dy = b[3] - a[3], b[4] - a[4]
	local len = math.sqrt(dx * dx + dy * dy)
	if len < HEAD_YARDS then
		return nil
	end
	return dx / len, dy / len
end

local function RouteLength(points)
	local total = 0
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if a[1] == b[1] and b[4] ~= "boat" and b[4] ~= "flight" then
			total = total + Dist(a[2], a[3], b[2], b[3])
		end
	end
	return total
end

local Redraw -- forward
local OBJECTIVE_ARRIVE = 60   -- yards; objective areas are wide, stop drawing this close

DestinationDistance = function()
	if not destination then
		return nil
	end
	if route and route.length then
		return route.length
	end
	local cont, x, y = PlayerYards()
	if cont and cont == destination.cont then
		return Dist(x, y, destination.x, destination.y)
	end
	return nil
end

--------------------------------------------------------------------------------
-- Travel time (user, 2026-09-25, for 0.13.7): about how long the rest of the
-- way takes, beside the distance under the arrow and on the World Marker's
-- gem ("1.2 km · about 2 min"), in the tracking notice, and how long the way
-- took on arriving ("Arrived: Stormwind (2:48)"). Travel Time off: every
-- text exactly as before.
--
-- The search prices a route in seconds: a walked or traced road at WALK
-- yards a second (the run speed on foot), a flight at its flight time, a boat
-- or zeppelin at BOAT_COST with the wait. The legs that join the graph carry
-- factors on top (1.3 to 4) so that the roads win, which a time must not, so
-- route.cost is a price, not a time. The estimate prices the route ahead the
-- search's way without them: its flights and boats at their seconds, its
-- ground yards at the player's own speed instead of WALK. That speed is
-- measured once a second from the yards moved, over seconds of moving all
-- through (a stop or a start within one spoils it), and smoothed (an
-- exponential moving average); a new pace that holds for two measures in a
-- row (mounting, dismounting, a faster mount) is taken at once. Before a
-- measure, and after standing still a while, it is the game's run speed for
-- the player (mounted or not), else WALK. Not shown while it cannot be trusted: no route, off the
-- path, on a flight, or over three hours.
-- Estimated at most once a second, from the arrow's tick (which runs only
-- while something is routed); a text is made again only when what it shows
-- changes. (One table: this file's main chunk is near Lua's 200 locals.)
--------------------------------------------------------------------------------

local Travel = {
	EVERY = 1,              -- seconds between estimates
	ALPHA = 0.35,           -- the smoothing: a new measure's share
	STEP = 0.4,             -- a measure this far (a share) from the smoothed speed is a new pace
	MOVING = 1,             -- yards a second: slower is standing
	FASTEST = 60,           -- yards a second: faster is a jump (a portal, a loading screen)
	FRESH = 10,             -- seconds: an older measure gives way to the run speed
	LONGEST = 3 * 3600,     -- seconds: a longer estimate is not shown
	HOUR = 3600,            -- a way that took this long gets no time on arrival
	LOGIN_GRACE = 20,       -- seconds after the login's loading screen: a destination first seen then was there before
	SEP = " \194\183 ",     -- " · " between the distance and the time
	speed = nil, measuredAt = 0, steps = 0,   -- the smoothed speed, when it was last set, new-pace measures in a row
	at = nil, cont = nil, x = 0, y = 0,       -- the last measure's time and place
	still = false,          -- a tick since the last measure found the player where the one before did
	tickX = nil, tickY = nil,                 -- the place at the last tick (the arrow's, 20 a second)
	nextAt = 0,             -- when the next estimate is due
	dest = nil,             -- the destination the minutes shown are for
	minutes = nil,          -- shown: nil none, 0 under a minute, else whole minutes
	pending = nil,          -- a change by one minute, taken when the next estimate agrees
	suffix = "",            -- what follows the distance: "" or " · about 2 min"
	loginAt = nil,          -- when Route came on in the login's pass (EnsureMarker), then when that loading screen ended
	entered = false,        -- the login's loading screen has ended (its PLAYER_ENTERING_WORLD)
}

-- The flight-master help's state (see "Flight-master help" below, where its
-- functions are): a field of M, not a local (this file's main chunk is near
-- Lua's 200 locals). slots: the open flight map's points by slot; openGen /
-- readGen: flight maps opened / read; pending: a flight asked for (the
-- game's TakeTaxiNode), not yet taken off; active: the flight under way;
-- arrowOn: its countdown has the arrow; wanted: the slot the route flies to.
M.flight = { slots = {}, openGen = 0, readGen = -1, arrowOn = false,
	SPEED = 32,        -- yards a second in the air: the Quest List data's flight times (plus 5 s a flight)
	TIMEOUT = 5,       -- seconds: no take-off by then (no money for it), nothing happens
	SHORTEST = 10, LONGEST = 3600,   -- seconds: a flight timed outside these is not learned
	GEM = 10,          -- the gem on the wanted flight point (its button is 16)
	BAND = 20,         -- the flight map's title band, its height (TaxiFrame's title bar)
	INSET = 12,        -- the line's gap from the window's left edge, beside the game's title
	NEAR = 150,        -- yards: a route's flight end this near a flight point is that point
}

function Travel.Words(m)
	if m < 1 then
		return "under a minute"
	elseif m < 60 then
		return string.format("about %d min", m)
	end
	local h, rest = math.floor(m / 60), m % 60
	if rest == 0 then
		return string.format("about %d h", h)
	end
	return string.format("about %d h %d min", h, rest)
end

function Travel.OnTaxi()
	local ok, on = pcall(UnitOnTaxi, "player")
	return ok and Plain(on) and true or false
end

-- yards a second over the ground: the smoothed measure while fresh, else the
-- game's run speed for the player (a mount's included), else WALK
function Travel.Speed()
	if Travel.speed and GetTime() - Travel.measuredAt < Travel.FRESH then
		return Travel.speed
	end
	local unitSpeed = _G.GetUnitSpeed
	if unitSpeed then
		local ok, _, run = pcall(unitSpeed, "player")
		run = ok and MelloUI.Safe.Number(run) or nil
		if run and run > 0 then
			return run
		end
	end
	return WALK
end

-- One measure: the yards moved since the last one over the time between,
-- taken only when the player moved all the while: a tick that found them
-- where they were (standing, or starting or stopping within the second)
-- spoils it, since its part-second pace is no pace (Travel.still). A measure
-- not taken breaks a run of new-pace measures, and only a speed set counts
-- as fresh. `measure` false (on a flight) starts the measures over.
function Travel.Sample(now, cont, px, py, measure)
	local at, v = Travel.at, nil
	if measure and at and not Travel.still and Travel.cont == cont then
		local dt = now - at
		if dt >= 0.5 and dt <= 3 then
			v = Dist(px, py, Travel.x, Travel.y) / dt
			if v < Travel.MOVING or v > Travel.FASTEST then
				v = nil   -- standing, or a jump (a portal, a loading screen)
			end
		end
	end
	Travel.still = false
	if measure then
		Travel.at, Travel.cont, Travel.x, Travel.y = now, cont, px, py
	else
		Travel.at = nil
	end
	if not v then
		Travel.steps = 0
		return
	end
	local s = Travel.speed
	if not s or now - Travel.measuredAt >= Travel.FRESH then
		s = v   -- the first measure, or the first for a long while: as it is
	elseif math.abs(v - s) > s * Travel.STEP then
		-- once is a stumble (a corner, a slope); twice running, a new pace
		-- (mounting, dismounting)
		local steps = Travel.steps + 1
		if steps < 2 then
			Travel.steps = steps
			return
		end
		s = v
	else
		s = s + Travel.ALPHA * (v - s)
	end
	Travel.speed, Travel.measuredAt, Travel.steps = s, now, 0
end

-- A flight leg between two flight points ("T<id>"): its time as timed on an
-- earlier flight (the flight-master help's, M.flight), else from the flight
-- network, else as a flight master's map prices one
function Travel.FlightSeconds(a, b, d)
	local ia, ib = a[5], b[5]
	if type(ia) == "string" and type(ib) == "string" and taxis then
		local ka, kb = ia:sub(2), ib:sub(2)
		local timed = live.flights[ka .. ">" .. kb]
		if type(timed) == "number" then
			return timed
		end
		local t = taxis[tonumber(ka)] or taxis[ka]
		local secs = t and (t.links[tonumber(kb)] or t.links[kb])
		if type(secs) == "number" then
			return secs
		end
	end
	return d / FLIGHT + 5
end

-- A link of d yards between two graph nodes ("<cont>|<cell>") that is a
-- flight learned at a flight master, by the search's own rule (IsFlight): its
-- seconds; nil for a walked one. (A link too short to be a flight at any
-- price is not looked up.)
function Travel.LinkFlight(a, b, d)
	local ia, ib = a[5], b[5]
	if not IsFlight(d, 0) or type(ia) ~= "string" or type(ib) ~= "string" then
		return nil
	end
	local c, ka = ia:match("^(%d+)|(.+)$")
	local kb = ib:match("^%d+|(.+)$")
	local g = c and kb and live.graphs[tonumber(c)]
	local node = g and g[ka]
	local cost = node and node[3][kb]
	if type(cost) == "number" and IsFlight(d, cost) then
		return cost
	end
	return nil
end

-- The route ahead of each of its points, summed from its end: G[j] the yards
-- to cover on the ground from point j, F[j] the seconds of its flights and
-- boats. Made once per route, at its first estimate (a new plan is a new
-- route table).
function Travel.Ahead(r)
	local G, F = r.etaGround, r.etaFixed
	if G then
		return G, F
	end
	G, F = {}, {}
	local points = r.points
	local n = #points
	G[n], F[n] = 0, 0
	for j = n - 1, 1, -1 do
		local a, b = points[j], points[j + 1]
		local ground, fixed = 0, 0
		if a[1] == b[1] then
			local d = Dist(a[2], a[3], b[2], b[3])
			if b[4] == "boat" then
				fixed = M.DockSeconds(b[5])
			elseif b[4] == "flight" then
				fixed = Travel.FlightSeconds(a, b, d)
			else
				fixed = Travel.LinkFlight(a, b, d) or 0
				if fixed == 0 then
					ground = d
				end
			end
		elseif b[4] == "boat" or b[4] == "flight" then
			fixed = BOAT_COST   -- the crossing to another continent
		end
		G[j], F[j] = G[j + 1] + ground, F[j + 1] + fixed
	end
	r.etaGround, r.etaFixed = G, F
	return G, F
end

-- Seconds from the player's place on the route (between points i and i + 1,
-- at qx, qy) to its end, or nil
function Travel.Seconds(i, qx, qy)
	local r = route
	if not (r and i and qx) then
		return nil
	end
	local G, F = Travel.Ahead(r)
	local points = r.points
	local secs = 0
	if i < #points then
		local ground = G[i + 1]
		if G[i] > ground then
			local b = points[i + 1]
			ground = ground + Dist(qx, qy, b[2], b[3])
		end
		secs = ground / Travel.Speed() + F[i]
	end
	if secs ~= secs or secs > Travel.LONGEST then
		return nil
	end
	return secs
end

function Travel.MinutesOf(secs)
	return secs < 60 and 0 or math.floor(secs / 60 + 0.5)
end

-- The minutes shown (nil: none), and the words after the distance made only
-- when they change. A change by one minute waits for the next estimate to
-- agree, so a time on the edge between two does not flicker (`now`: at once).
function Travel.Show(secs, now)
	-- (0.17.0, docs/plans/route-terrain.md section 4: the straight line no
	-- known way proves, "444 yd straight · no known way", not a time)
	local guess = route and route.guess or false
	if guess ~= (Travel.guess or false) then
		Travel.guess = guess
		Travel.minutes, Travel.pending = nil, nil
		Travel.suffix = guess and (" straight" .. Travel.SEP .. "no known way") or ""
	end
	if guess then
		return
	end
	local target = secs and Travel.MinutesOf(secs)
	local shown = Travel.minutes
	if target == shown then
		Travel.pending = nil
		return
	end
	if not now and target and shown and math.abs(target - shown) == 1 and Travel.pending ~= target then
		Travel.pending = target
		return
	end
	Travel.pending = nil
	Travel.minutes = target
	Travel.suffix = target and (Travel.SEP .. Travel.Words(target)) or ""
end

-- The whole way from here, for the tracking notice ("about 2 min", nil for
-- none); the arrow and the marker start from the same
function Travel.Planned()
	local r = route
	local p = r and r.points[1]
	if not (M.db.travelTime and p) or Travel.OnTaxi() then
		return nil
	end
	local secs = Travel.Seconds(1, p[2], p[3])
	if not secs then
		return nil
	end
	Travel.dest = destination
	Travel.Show(secs, true)
	Travel.nextAt = GetTime() + Travel.EVERY
	if not Travel.minutes then
		return nil   -- (0.17.0: a straight guess has no time to tell)
	end
	return Travel.Words(Travel.minutes)
end

-- A destination's start: the first time the route's drawing sees it (Plan's
-- Redraw, at once when it is set). One seen after Route came on at login and
-- before that loading screen ended, or within LOGIN_GRACE after (the game
-- tells a pin a moment late, and a cold login's loading screen can be long),
-- was there before the /reload (or the logout): its start is not known, so
-- its arrival says no time.
function Travel.See(d)
	if d.seenAt then
		return
	end
	local now = GetTime()
	d.seenAt = now
	local login = Travel.loginAt
	if login and (not Travel.entered or now - login < Travel.LOGIN_GRACE) then
		d.untimed = true
	end
end

-- The login's loading screen has ended (the first PLAYER_ENTERING_WORLD after
-- Route came on in the login's pass): the grace runs from here
function Travel.Entered()
	if Travel.loginAt and not Travel.entered then
		Travel.loginAt, Travel.entered = GetTime(), true
	end
end

-- "1:16": seconds as minutes and seconds, to the nearest second (Route's
-- one m:ss formatter: the time taken, the flight times, the countdown)
function Travel.Clock(secs)
	secs = math.max(0, math.floor(secs + 0.5))
	return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

-- "2:48", the time since the destination was set; nil with Travel Time off,
-- from an hour on, or when tracking was paused (Route switched off
-- meanwhile) or began before a /reload
function Travel.Took(d)
	local at = d.seenAt
	if not (M.db.travelTime and at) or d.untimed then
		return nil
	end
	local secs = GetTime() - at
	if secs < 0 or secs >= Travel.HOUR then
		return nil
	end
	return Travel.Clock(math.floor(secs))   -- (the whole seconds gone, as always)
end

-- The distance line of the arrow or the marker (f.distance): d yards as
-- Yards(d) writes them, then the time. Made again only when what it shows
-- can have changed (the ticks run 20 and 60 times a second): the whole yards
-- under 1000; from 1000, once d leaves the band whose tenth of a km is sure
-- (its edges, where the rounding decides, are written each time d moves).
function Travel.Line(f, d)
	local suffix = Travel.suffix
	if suffix == f.lineSuffix then
		if d == f.lineD then
			return
		elseif d < 1000 then
			if f.lineYards == math.floor(d) then
				return
			end
		elseif f.lineLo and d > f.lineLo and d < f.lineHi then
			return
		end
	end
	f.lineSuffix, f.lineD = suffix, d
	if d < 1000 then
		f.lineYards, f.lineLo, f.lineHi = math.floor(d), nil, nil
		f.distance:SetText(string.format("%d yd%s", d, suffix))
	else
		local t = d / 100 + 0.5
		local tenths = math.floor(t)
		f.lineYards, f.lineLo, f.lineHi = nil, math.max(tenths * 100 - 50, 1000), tenths * 100 + 50
		if t - tenths < 1e-6 or t - tenths > 1 - 1e-6 then
			f.lineLo = nil   -- on an edge: which tenth it shows is the format's
		end
		f.distance:SetText(string.format("%.1f km%s", d / 1000, suffix))
	end
end

-- Say what is tracked now; `text` overrides the standard sentence. With
-- Travel Time, the time the whole way takes follows the distance ("Tracking
-- Stormwind: 1.2 km, about 2 min"; a caller's "{dist} away" is followed by
-- ", about 2 min"); without, the sentences are as they were.
local function Announce(text)
	if not destination then
		return
	end
	local d = DestinationDistance()
	local time = d and Travel.Planned()
	if text then
		if time then
			text = text:gsub("{dist} away", "{dist} away, " .. time)
		end
		text = text:gsub("{dist}", d and Yards(d) or "?")
	elseif time then
		text = "Tracking " .. (destination.label or "map pin") .. ": " .. Yards(d) .. ", " .. time
	end
	-- (0.19.4) one sound for a new destination: no chime while the World
	-- Marker's own sound stands for it (M.TrackMute, by the marker below)
	local mute = M.TrackMute ~= nil and M.TrackMute(destination) or nil
	M:Notify(text or ("Tracking " .. (destination.label or "map pin") .. (d and (", " .. Yards(d) .. " away") or "")), "track",
		mute)
end

local function Plan(force, announce, announceText)
	if not destination then
		route = nil
		Redraw()
		return
	end
	local now = GetTime()
	if not force then
		-- (0.17.1) a plan for it under way: its answer comes (a long search
		-- asked again every few seconds would never end)
		local pending = Search.plan
		if pending and not pending.ended and not pending.stale and pending.d == destination then
			return
		end
		-- (user, 2026-09-22: the arrow was too strict) a route being
		-- followed is kept and only re-projected by the arrow; a new one is
		-- planned when the player has been off it for OFF_ROUTE_SECONDS, or
		-- every REPLAN_SECONDS as a refresh (a road learned meanwhile)
		if route and not offRoute and now - lastPlan < REPLAN_SECONDS then
			return
		end
		if route and offRoute and (not offRouteSince or now - offRouteSince < OFF_ROUTE_SECONDS) then
			return
		end
		if not route and now - lastPlan < 3 then
			return
		end
	end
	lastPlan = now
	offRoute = false
	offRouteSince = nil
	local cont, x, y = PlayerYards()
	if not cont then
		route = nil
		Redraw()
		M.CannotPlace(nil, "you")
		return
	end
	M.placeMissed = nil   -- placed: a miss before was a moment's
	local d = destination
	if d.fromQuest and cont == d.cont and Dist(x, y, d.x, d.y) <= OBJECTIVE_ARRIVE then
		route = nil
		Redraw()
		return
	end
	if not Build.Ready() then
		-- the roads are still going in (the first route of the session, a
		-- few frames): planned, and announced, the moment they are all in;
		-- the arrow and the marker point straight at the place meanwhile
		Build.Wait(announce, announceText)
		Redraw()
		return
	end
	local waited = Build.waiting
	if waited then
		-- a route asked for while the graph was being built: its notice now
		Build.waiting = nil
		if waited.announce and not announce then
			announce, announceText = true, waited.text
		end
	end
	-- (0.17.1) the search as a job (Search.Run): its answer put in place
	-- below at once, or in the frame it ends. A plan asked for again while
	-- one waits for its frame takes its place (its notice with it, for the
	-- same destination)
	local before = Search.plan
	if before and not before.stale and not before.ended then
		before.stale = true
		if before.d == d and before.announce and not announce then
			announce, announceText = true, before.text
		end
	end
	local hx, hy = Heading(cont)
	local job = { kind = "route", scont = cont, sx = x, sy = y, gcont = d.cont, gx = d.x, gy = d.y, hx = hx, hy = hy,
		d = d, announce = announce, text = announceText, done = Search.Planned }
	Search.plan = job
	if Search.Run(job) then
		Search.Planned(job)
	end
end

-- The route a plan's search found, put in place (Plan; Search.Run's done)
function Search.Planned(job)
	job.ended = true
	if Search.plan == job then
		Search.plan = nil
	end
	local d = job.d
	if destination ~= d then
		return   -- (another destination since: its own plan follows)
	end
	local cont, x, y = job.scont, job.sx, job.sy
	local points, cost = job.points, job.cost
	local announce, announceText = job.announce, job.text
	if points and #points == 2 and cont == d.cont then
		-- the direct line won: its real walking time, not the price that made roads compete
		cost = Dist(x, y, d.x, d.y) / WALK
	end
	if points and cont == d.cont and not M.Ground.Has(cont) then
		-- A silly detour is worse than a straight guess -- only where the
		-- ground is not known (0.17.0): with it, the long way round is the way
		local beeline = Dist(x, y, d.x, d.y)
		if cost > beeline / WALK * 3 + 60 then
			points, cost = nil, nil
		end
	end
	local guess = false
	if not points and cont == d.cont then
		points = { { cont, x, y, "guess" }, { d.cont, d.x, d.y, "guess" } }
		cost = Dist(x, y, d.x, d.y) / WALK
		guess = true
	elseif points and #points == 2 and cont == d.cont then
		-- (the direct line: a guess unless the ground shows it walkable)
		guess = M.Ground.Clear(cont, x, y, d.x, d.y) ~= true
	end
	if points then
		route = { points = points, cost = cost, length = RouteLength(points), dest = { d.cont, d.x, d.y }, guess = guess }
	else
		route = nil
	end
	StandIn.Update()
	Redraw()
	if announce then
		Announce(announceText)
	end
end

--------------------------------------------------------------------------------
-- Tracked quest objectives
--
-- The client places a marker for every quest in the log on the map its
-- objectives are on (the turn-in once the quest is complete). Those markers
-- are read for the super-tracked quest, first on the player's map, then on
-- every zone of both continents.
--------------------------------------------------------------------------------

local poiCache = {}   -- [questID] = { mapID, x, y, at }

local function ScanQuestOnMap(mapID, questID)
	if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then
		return nil
	end
	local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
	if ok and type(list) == "table" then
		for _, info in ipairs(list) do
			if Plain(info.questID) == questID then
				local x, y = Plain(info.x), Plain(info.y)
				if x and y then
					return x, y
				end
			end
		end
	end
	return nil
end

local function QuestObjectivePoint(questID)
	local c = poiCache[questID]
	if c and GetTime() - c.at < 20 then
		return c.mapID, c.x, c.y
	end
	local candidates = {}
	local okM, playerMap = pcall(C_Map.GetBestMapForUnit, "player")
	playerMap = okM and Plain(playerMap) or nil
	if playerMap then
		candidates[#candidates + 1] = playerMap
	end
	local playerCont = playerMap and ContinentOf(playerMap)
	local conts = {}
	if playerCont then
		conts[#conts + 1] = playerCont
	end
	local seen = { [playerCont or 0] = true }
	for _, t in pairs(taxis or {}) do
		if not seen[t.cont] then
			seen[t.cont] = true
			conts[#conts + 1] = t.cont
		end
	end
	for _, cont in ipairs(conts) do
		local okC, children = pcall(C_Map.GetMapChildrenInfo, cont, MAP_ZONE, true)
		if okC and type(children) == "table" then
			for _, child in ipairs(children) do
				if Plain(child.mapID) and child.mapID ~= playerMap then
					candidates[#candidates + 1] = child.mapID
				end
			end
		end
	end
	for _, mapID in ipairs(candidates) do
		local x, y = ScanQuestOnMap(mapID, questID)
		if x then
			poiCache[questID] = { mapID = mapID, x = x, y = y, at = GetTime() }
			return mapID, x, y
		end
	end
	-- The client's own "next stop" for the quest, if it has one.
	if C_QuestLog and C_QuestLog.GetNextWaypoint then
		local ok, mapID, x, y = pcall(C_QuestLog.GetNextWaypoint, questID)
		mapID, x, y = ok and Plain(mapID) or nil, ok and Plain(x) or nil, ok and Plain(y) or nil
		if mapID and x and y then
			poiCache[questID] = { mapID = mapID, x = x, y = y, at = GetTime() }
			return mapID, x, y
		end
	end
	poiCache[questID] = { at = GetTime() }
	return nil
end

-- What the game super-tracks: the quest ID (nil for none) and whether it is
-- the map pin (nil when this client cannot say). The game tracks one at a
-- time; its navigation frame (the world marker) follows only that one.
local function SuperTrackState()
	local quest, pin
	if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
		local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
		quest = ok and Plain(id) or nil
		if quest == 0 then
			quest = nil
		end
	end
	if C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint then
		local ok, on = pcall(C_SuperTrack.IsSuperTrackingUserWaypoint)
		pin = ok and Plain(on)
		if pin ~= nil then
			pin = pin and true or false
		end
	end
	return quest, pin
end

-- Choosing a quest to track while a map pin is set replaces the pin (user,
-- 2026-09-23: the pin stayed, the route kept going to it, and once the quest
-- was untracked again the arrow round the character froze on it).
local function DropPinForTrackedQuest()
	if not (C_Map.HasUserWaypoint and C_Map.ClearUserWaypoint) then
		return
	end
	local okH, has = pcall(C_Map.HasUserWaypoint)
	if not (okH and Plain(has)) then
		return
	end
	local quest, pin = SuperTrackState()
	if quest and pin == false then
		pcall(C_Map.ClearUserWaypoint)
	end
end

local function TrackedQuestID()
	local questID
	if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
		local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
		questID = ok and Plain(id) or nil
	elseif GetSuperTrackedQuestID then
		local ok, id = pcall(GetSuperTrackedQuestID)
		questID = ok and Plain(id) or nil
	end
	-- the stand-in pin on the dock took the game's tracking from the quest
	if (not questID or questID == 0) and standIn and standIn.questID then
		local okL, index = true, true
		if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
			okL, index = pcall(C_QuestLog.GetLogIndexForQuestID, standIn.questID)
		end
		if okL and index then
			questID = standIn.questID
		end
	end
	-- The first quest in the tracker only when asked for (or when this client
	-- has no super-tracking at all); otherwise nothing tracked means no route.
	local canSuperTrack = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) or GetSuperTrackedQuestID
	if (not questID or questID == 0) and (M.db.trackFirstWatched or not canSuperTrack)
		and C_QuestLog and C_QuestLog.GetQuestIDForQuestWatchIndex then
		local ok, id = pcall(C_QuestLog.GetQuestIDForQuestWatchIndex, 1)
		questID = ok and Plain(id) or nil
	end
	if questID == 0 then
		questID = nil
	end
	return questID
end

--------------------------------------------------------------------------------
-- The objectives themselves (user, 2026-09-23: "now start on the route to
-- quest objectives"): MelloUI_Companion/QuestObjectiveData.lua (Tools/build_
-- quest_objectives.py, cmangos classic-db) knows where each objective of a
-- Classic quest is done -- the creature to kill, the object to use, what
-- drops the item or sells it, the place to explore. The tracked quest's
-- unfinished objectives are matched to it by name; of their places the
-- nearest few are priced by route and the cheapest is the destination.
-- Re-chosen as the objectives change and every few seconds, so the route
-- moves on to the next spawn as the player works through them. A complete
-- quest, or one without data, keeps the game's own marker (the turn-in, the
-- quest area). The data is the companion's: loaded with the roads when a
-- quest is first tracked, and read from its global when asked for (nil until
-- then, or when the companion is missing: the game's marker then).
--
-- Needed items (0.15.0; a player's report, Marla's Last Wish: kill Samuel
-- Fipps, loot Samuel's Remains, then bury them at Marla's Grave -- the route
-- went straight to the grave). The data names, for some objectives, an item
-- the bags must hold before the objective can be done (Tools/build_quest_
-- objectives.py: the quest's ReqSourceId, in MelloUI_QuestNeededItems beside
-- the objectives) and where it comes from. While
-- the bags hold fewer than needed, the item's sources stand in for the
-- objective: the route, the arrow, the World Marker (Route's own pin on the
-- source, StandIn) and the tracker's "First: ..." line (Route:ItemFirst) all
-- point there; the moment the bags hold them (BAG_UPDATE_DELAYED, heard
-- while such a quest is followed) they all go to the objective at once
-- (user, 2026-09-28). A count the client does not give (a secret, no such
-- call) counts as held: the objective itself, as before.
--------------------------------------------------------------------------------

local OBJECTIVE_RECHECK = 8     -- seconds between choosing again
local OBJECTIVE_PRICED = 3      -- the nearest this many places are priced by route
local OBJECTIVE_SPOT = 40       -- yards: an objective whose places all lie this close together is one spot
local objectiveChoice = {}      -- [questID] = { sig, at, cont, x, y, name, source }

-- Needed items: their functions (Count, Want, Held, Gates here; Listen,
-- BagsChanged with the events), the words of the tracker's line by how the
-- source gives the item (1 a creature drops it, 2 an object holds it, 3 a
-- vendor sells it), and the items still counted as held after they left the
-- bags (Held): [questID] = { [item] = { lines, at } }
local Needed = { VERB = { "loot", "get", "buy" }, LATCH = 300, latched = {} }

-- How many of a needed item the bags hold, or nil when the client cannot say
function Needed.Count(gate)
	local Count = (C_Item and C_Item.GetItemCount) or GetItemCount
	if type(Count) ~= "function" then
		return nil
	end
	local ok, n = pcall(Count, gate.item)
	n = ok and Plain(n) or nil
	return type(n) == "number" and n or nil
end

-- How many the bags must hold. The data's count is the most of the item that
-- drops for the quest (review, 2026-09-28: cmangos' loot cap, not a number to
-- hold): all of it at once where the objective's line wants one thing (1016:
-- five bracers for one scroll), else as many as the line still lacks, at
-- most that (746: a pick for each tool still missing). `left`: what the
-- game's line still lacks when it counts more than one, else nil.
function Needed.Want(gate, left)
	return left and math.max(1, math.min(gate.count, left)) or gate.count
end

-- Held, or not known (then the objective itself, as before this existed);
-- second, how many are wanted (Want). An item the objective's own step used
-- up (a carcass that calls the beast whose fang is the objective, remains
-- buried a moment before the log counts them, a key turned in its chest's
-- lock) still counts while the quest's objective lines (`lines`, one string)
-- are as they were when it came into the bags, Needed.LATCH seconds at
-- most: sent back for another the moment the step is taken is wrong
-- (review, 2026-09-28). A step that moves a line (905: a feather used at one
-- nest) lets go at once: the next nest wants a new feather.
function Needed.Held(gate, left, questID, lines)
	local want = Needed.Want(gate, left)
	local n = Needed.Count(gate)
	if n == nil then
		return true, want
	end
	local latched = questID and lines and Needed.latched[questID]
	local l = latched and latched[gate.item]
	if n >= want then
		if questID and lines then
			if not l then
				latched = latched or {}
				Needed.latched[questID] = latched
				l = { lines = lines }
				latched[gate.item] = l
			end
			l.at = GetTime()
		end
		return true, want
	end
	if l and l.lines == lines and GetTime() - l.at < Needed.LATCH then
		return true, want
	end
	if l then
		latched[gate.item] = nil
	end
	return false, want
end

-- A quest's entries, { { kind, name, alt, map, x1, y1, x2, y2, ... }, ... },
-- an entry's needed items on it (.gates, .made), or nil: the one reader of
-- the companion's objective places, shared with the Quest List's objective
-- marks since 0.19.5 (MelloUI.QuestObjectives, Core/QuestObjectives.lua:
-- the decoding and its few kept quests moved there unchanged).
-- (looked up when asked, not bound at load: the file loads before the
-- modules in the game; a world that leaves it out has no objective places)
local function ObjectivesOf(questID)
	local QO = MelloUI.QuestObjectives
	return QO and QO.Of(questID) or nil
end

-- The needed items of a quest's data, every objective's, in one new list, or
-- nil when it names none (most quests)
function Needed.Gates(questID)
	local list, out = ObjectivesOf(questID), nil
	for i = 1, list and #list or 0 do
		local gates = list[i].gates
		for g = 1, gates and #gates or 0 do
			out = out or {}
			out[#out + 1] = gates[g]
		end
	end
	return out
end

-- The data's entries still to do: each { kind, name, alt, map, points }, and
-- a signature of the open objectives (a new choice when it changes). An open
-- objective whose needed item the bags do not hold yet gives the places that
-- item comes from instead (Needed), and `hints`, when given, gets that item
-- by the game's objective line: hints[line] = its gate, wants[line] = how
-- many the bags must hold (Route:ItemFirst). Third and fourth: how many
-- needed items are missing, and whether every open place is one's source
-- (the stand-in pin goes there only then: StandIn). Of several items one
-- line still lacks, the hint names `prefer` when it is one (the item the
-- route goes for), else the first; a made objective (entry.made) whose items
-- the bags all hold gets hints[line] = the objective itself (use them).
local function OpenObjectives(questID, hints, wants, prefer)
	local data = ObjectivesOf(questID)
	if not data then
		return nil
	end
	if C_QuestLog and C_QuestLog.IsComplete then
		local ok, done = pcall(C_QuestLog.IsComplete, questID)
		if ok and Plain(done) then
			return nil   -- the turn-in: the game's marker has it
		end
	end
	-- (each line: its text, finished, its index, and what it still lacks when
	-- it counts more than one; `lines` all of them as one string, Needed.Held;
	-- an entry's line found by name, an item by the quest's one item line:
	-- MelloUI.QuestObjectives' Lines / ItemLine / Match, shared since 0.19.5)
	local QO = MelloUI.QuestObjectives
	local open = {}
	local texts, lines = QO.Lines(questID)
	local itemLine = QO.ItemLine(data, texts)
	local anyMatched, sig, missing, sourceOnly = false, {}, 0, true
	-- (an item needed for several objectives, 905's feather for each of three
	-- nests: its places once, not once each)
	local added = {}
	-- an open objective (`t` its game line, when matched); or, while an item
	-- it needs is not in the bags, the places that item comes from
	-- ("<i>s<gate>" in the signature: chosen again the moment the bags hold it)
	local function Open(i, entry, t)
		local gates, lacking = entry.gates, false
		for g = 1, gates and #gates or 0 do
			local gate = gates[g]
			local held, want = Needed.Held(gate, t and t[4], questID, lines)
			if not held then
				lacking = true
				missing = missing + 1
				if not added[gate.item] then
					added[gate.item] = true
					for k = 1, #gate do
						open[#open + 1] = gate[k]
					end
				end
				sig[#sig + 1] = i .. "s" .. g
				local line = t and t[3]
				if hints and line and (not hints[line] or (prefer and gate.item == prefer)) then
					hints[line] = gate
					if wants then
						wants[line] = want
					end
				end
			end
		end
		if not lacking then
			open[#open + 1] = entry
			sig[#sig + 1] = i
			local line = t and t[3]
			if entry.made and hints and line and not hints[line] then
				hints[line] = entry
			end
			-- (one kept for a needed item alone has no place to go to)
			if #entry > 4 then
				sourceOnly = false
			end
		end
	end
	for i, entry in ipairs(data) do
		local kind = entry[1]
		local t = QO.Match(entry, texts, itemLine)
		if t then
			anyMatched = true
			if not t[2] then
				Open(i, entry, t)
			end
		elseif kind == 4 then
			-- an exploration objective has no line of its own: open until
			-- the quest is complete
			Open(i, entry)
		end
	end
	-- no line matched a name at all (another language, a renamed creature):
	-- every place of the quest rather than none
	if not anyMatched and #open == 0 and #texts > 0 then
		for i, entry in ipairs(data) do
			Open(i, entry)
		end
	end
	if #open == 0 then
		return nil
	end
	return open, table.concat(sig, ","), missing, sourceOnly and missing > 0
end

-- The place to go for the quest's open objectives: continent yards and the
-- objective's name, or nil; nil and then true while the places cannot be
-- priced yet (the graph not built). Sixth: the needed item's source when the
-- place is one ({ from, "Samuel Fipps", "", map, ..., gate = its gate });
-- seventh and eighth: OpenObjectives' missing items and "every open place a
-- source"; ninth: the objective is an area, not one spot (0.15.0, the World
-- Marker hides inside a quest's area: Beacon.InArea) -- a place to explore,
-- or places spread wider than OBJECTIVE_SPOT (creatures to kill about a
-- camp); one NPC, one object, one source is a spot.
local function ObjectiveSpot(questID)
	local open, sig, missing, sourceOnly = OpenObjectives(questID)
	if not open then
		objectiveChoice[questID] = nil
		return nil
	end
	local c = objectiveChoice[questID]
	if c and c.sig == sig and GetTime() - c.at < OBJECTIVE_RECHECK then
		return c.cont, c.x, c.y, c.name, nil, c.source, missing, sourceOnly, c.area
	end
	local pcont, px, py = PlayerYards()
	if not pcont then
		return c and c.cont, c and c.x, c and c.y, c and c.name, nil, c and c.source, missing, sourceOnly, c and c.area
	end
	-- (0.17.1) the same objectives, and the player still within REPICK_MOVED
	-- yards of where they were chosen: kept (a walk chose again, and searched,
	-- every OBJECTIVE_RECHECK seconds)
	if c and c.sig == sig and c.pcont == pcont and Dist(px, py, c.px, c.py) < Search.REPICK_MOVED then
		return c.cont, c.x, c.y, c.name, nil, c.source, missing, sourceOnly, c.area
	end
	-- every place on the player's continent, nearest first
	local near = {}
	for _, entry in ipairs(open) do
		local wmap = entry[4]
		-- (a needed item's source: "Samuel Fipps (Samuel's Remains)")
		local name = entry.label or (entry[2] ~= "" and entry[2]) or (entry[3] ~= "" and entry[3]) or nil
		local first, x0, y0, x1, y1 = #near + 1, nil, nil, nil, nil
		for i = 5, #entry - 1, 2 do
			local cont, x, y = YardsOfWorld(wmap, entry[i], entry[i + 1])
			if cont == pcont then
				near[#near + 1] = { d = Dist(px, py, x, y), cont = cont, x = x, y = y, wmap = wmap, wx = entry[i], wy = entry[i + 1],
					name = name, source = entry.gate and entry or nil }
				x0, y0 = math.min(x0 or x, x), math.min(y0 or y, y)
				x1, y1 = math.max(x1 or x, x), math.max(y1 or y, y)
			end
		end
		local area = entry[1] == 4 or (x0 ~= nil and (x1 - x0 > OBJECTIVE_SPOT or y1 - y0 > OBJECTIVE_SPOT))
		for k = first, #near do
			near[k].area = area
		end
	end
	if #near == 0 then
		objectiveChoice[questID] = nil
		return nil   -- all of it elsewhere: the game's marker leads the way
	end
	table.sort(near, function(a, b) return a.d < b.d end)
	local pick = near[1]
	-- the nearest few priced by route: the one past a river or a cliff loses
	if #near > 1 then
		local candidates = {}
		for i = 1, math.min(OBJECTIVE_PRICED, #near) do
			candidates[i] = { cont = near[i].wmap, wx = near[i].wx, wy = near[i].wy }
		end
		local ok, best, _, later = pcall(M.Cheapest, M, candidates)
		if ok and later then
			-- not priced yet (the roads are still going in): nothing chosen,
			-- so the first choice is the cheapest one, as ever
			return nil, nil, nil, nil, true
		end
		if ok and best and near[best] then
			pick = near[best]
		end
	end
	objectiveChoice[questID] = { sig = sig, at = GetTime(), cont = pick.cont, x = pick.x, y = pick.y, name = pick.name,
		source = pick.source, area = pick.area, pcont = pcont, px = px, py = py }
	return pick.cont, pick.x, pick.y, pick.name, nil, pick.source, missing, sourceOnly, pick.area
end

local function ReadTrackedQuest()
	if destination and not destination.fromQuest and not destination.fromWaypoint then
		return
	end
	local questID
	if M.db.trackQuests then
		questID = TrackedQuestID()
	end
	-- stopped (M.nav.Stop): no quest followed, nor the first tracked one,
	-- until the player focuses a quest again
	local stop = M.stopped
	if stop then
		local quest = SuperTrackState()
		if quest and (stop.cleared or quest ~= stop.quest) then
			M.stopped = nil
		else
			questID = nil
		end
	end
	if not questID then
		if destination and destination.fromQuest then
			destination = nil
			route = nil
			Redraw()
		end
		return
	end
	-- the objective itself, when the data knows where it is done (the
	-- companion's data, loaded now if it is not yet, the roads with it)
	Build.Want()
	local ocont, ox, oy, oname, later, source, missing, sourceOnly, area = ObjectiveSpot(questID)
	if later then
		-- chosen by route once the roads are in (Build.Replan), or once its
		-- search has ended (0.17.1: one that went on in the next frames);
		-- nothing changes until then
		if Build.ready then
			Search.RepickSoon()
		end
		return
	end
	if ocont then
		local same = destination and destination.fromQuest and destination.questID == questID
		missing = missing or 0
		-- a needed item come into the bags while the way led to where it
		-- comes from: the next step, said as a new quest is. Not the way back
		-- to a source (an item used at one of several nests, the latch run
		-- out: Needed.Held), nor the pick moving between a plain objective's
		-- places and a source's as the player walks (review, 2026-09-28: said
		-- at every turn, the pin put up and taken down with it)
		local step = same and destination.source ~= nil and missing < (destination.missing or 0)
		if same and not step and destination.cont == ocont and Dist(destination.x, destination.y, ox, oy) < 1
			and (destination.source ~= nil) == (source ~= nil) and destination.sourceOnly == sourceOnly then
			destination.missing = missing
			return
		end
		local title
		if C_QuestLog and C_QuestLog.GetTitleForQuestID then
			local ok, t = pcall(C_QuestLog.GetTitleForQuestID, questID)
			title = ok and Plain(t) or nil
		end
		-- (`source`: a needed item's; `sourceOnly`: every open place is one's,
		-- so Route's own pin goes on it, StandIn; `missing`: the items not
		-- held; `gated`: the quest needs an item, so the bags are heard, Needed;
		-- `area`: an objective area, not one spot: the World Marker hides
		-- inside it, Beacon.InArea)
		destination = { cont = ocont, x = ox, y = oy, fromQuest = true, questID = questID, objective = oname,
			source = source, sourceOnly = sourceOnly, missing = missing, gated = Needed.Gates(questID) ~= nil,
			area = area and true or false, label = "|A:QuestNormal:16:16|a " .. (oname or title or "quest") }
		-- announced once per quest (and step), not at every next spawn
		Plan(true, not same or step, "|A:QuestNormal:22:22|a  Tracking quest " .. (title or "") .. (oname and (": " .. oname) or "") .. ", {dist} away")
		return
	end
	local mapID, px, py = QuestObjectivePoint(questID)
	if not mapID then
		if destination and destination.fromQuest and destination.questID == questID then
			destination = nil
			route = nil
			Redraw()
		end
		return
	end
	if destination and destination.fromQuest and destination.questID == questID and destination.mapID == mapID
		and math.abs(destination.mx - px) < 0.0005 and math.abs(destination.my - py) < 0.0005 then
		return
	end
	local cont, x, y = ToYards(mapID, px, py)
	if not cont then
		M.CannotPlace(mapID, "point")
		return
	end
	local title
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local ok, t = pcall(C_QuestLog.GetTitleForQuestID, questID)
		title = ok and Plain(t) or nil
	end
	-- (`area` false: the game's own point says nothing of an area or one
	-- spot, and its quest blob is drawn round one NPC or object too, so the
	-- World Marker stays on it as on any spot -- never hidden at the target;
	-- review, 2026-09-28. Hidden only where the data says area: ObjectiveSpot)
	destination = { cont = cont, x = x, y = y, mapID = mapID, mx = px, my = py, fromQuest = true, questID = questID,
		gated = Needed.Gates(questID) ~= nil, area = false, label = "|A:QuestNormal:16:16|a " .. (title or "quest") }
	Plan(true, true, "|A:QuestNormal:22:22|a  Tracking quest " .. (title or "") .. ", {dist} away")
end

-- The waypoint the client shows is the destination; Blizzard's own map clicks
-- count too, not only the Quest List's. Without one, the tracked quest is.
local function ReadWaypoint()
	if not (C_Map.HasUserWaypoint and C_Map.GetUserWaypoint) then
		ReadTrackedQuest()
		return
	end
	if StandIn.GiveBackSaved() then
		return   -- the pin given back is read on its USER_WAYPOINT_UPDATED
	end
	local okH, has = pcall(C_Map.HasUserWaypoint)
	if not okH or not has then
		if destination and destination.fromWaypoint then
			destination = nil
			route = nil
			Redraw()
		end
		ReadTrackedQuest()
		return
	end
	local ok, point = pcall(C_Map.GetUserWaypoint)
	if not ok or type(point) ~= "table" then
		return
	end
	local mapID = Plain(point.uiMapID)
	local px, py = VectorXY(point.position)
	if not (mapID and px and py) then
		return
	end
	-- the stand-in on the dock: the destination stays the one beyond it
	if StandIn.IsPin(mapID, px, py) then
		if not (destination and destination.fromQuest) then
			return
		end
		ReadTrackedQuest()
		return
	end
	if destination and destination.mapID == mapID and destination.mx and destination.my
		and math.abs(destination.mx - px) < 0.003 and math.abs(destination.my - py) < 0.003 then
		return
	end
	local cont, x, y = ToYards(mapID, px, py)
	if not cont then
		M.CannotPlace(mapID, "point")
		return
	end
	M.stopped = nil   -- (a new pin: the player's pick, M.nav.Stop)
	destination = { cont = cont, x = x, y = y, mapID = mapID, mx = px, my = py, fromWaypoint = true,
		label = "|A:Waypoint-MapPin-ChatIcon:16:16|a map pin" }
	Plan(true, true)
end

-- (0.17.1) The tracked quest's pick waited for its search (one that went on
-- in the next frames): read again once it has ended, once however often it
-- was asked (the search's answer is kept a moment: M:Cheapest)
function Search.Repick()
	Search.repickDue = false
	if M.isEnabled then
		ReadWaypoint()
	end
end

function Search.RepickSoon()
	if not Search.repickDue then
		Search.repickDue = true
		M:WhenReady(Search.Repick)
	end
end

-- A candidate is { mapID, x, y } (map fraction) or { cont, wx, wy } (world
-- coordinates as the client tables give them). Returns continent-map yards.
local function CandidateYards(c)
	if c.mapID then
		return ToYards(c.mapID, c.x, c.y)
	end
	if c.cont then
		return YardsOfWorld(c.cont, c.wx, c.wy)
	end
	return nil
end

-- Continent yards -> the zone (or city) map holding the point and the
-- position on it, for placing a pin.
local function MapPointOfYards(cont, yx, yy)
	local w, h = WorldSize(cont)
	local cx, cy = yx / w, yy / h
	if C_Map.GetMapInfoAtPosition then
		local ok, info = pcall(C_Map.GetMapInfoAtPosition, cont, cx, cy)
		local zone = ok and type(info) == "table" and Plain(info.mapID) or nil
		if zone and zone ~= cont then
			local r = RectOn(zone, cont)
			if r then
				local x, y = (cx - r[1]) / (r[2] - r[1]), (cy - r[3]) / (r[4] - r[3])
				if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
					-- One level deeper for a city inside the zone.
					local okC, cinfo = pcall(C_Map.GetMapInfoAtPosition, zone, x, y)
					local child = okC and type(cinfo) == "table" and Plain(cinfo.mapID) or nil
					if child and child ~= zone then
						local r2 = RectOn(child, cont)
						if r2 then
							local x2, y2 = (cx - r2[1]) / (r2[2] - r2[1]), (cy - r2[3]) / (r2[4] - r2[3])
							if x2 >= 0 and x2 <= 1 and y2 >= 0 and y2 <= 1 then
								return child, x2, y2
							end
						end
					end
					return zone, x, y
				end
			end
		end
	end
	return cont, cx, cy
end

--------------------------------------------------------------------------------
-- Another continent (user, 2026-09-23: the beam and the World Marker "get
-- stuck in the middle of the screen" while the tracked place is on another
-- continent; "it should mark me the location to the boat in Booty Bay"). The
-- game's navigation frame, which the marker hangs on, has no place on screen
-- for a point on another continent. While the destination lies there, the
-- map pin goes on the dock where the route leaves the player's continent (a
-- stand-in, super-tracked, so the game's frame and the marker show the boat);
-- what was there before -- the player's own pin, or the tracked quest -- is
-- given back on reaching the destination's continent, or when the World
-- Marker is switched off. Removing the stand-in pin ends it like any pin;
-- a quest it held is the game's to track again (the player chose the quest,
-- not Route's pin), and no stand-in goes up again for the same thing until
-- that changes (0.15.0: it came straight back). Only a quest the game
-- tracked is held and given back: one followed as the first tracked quest
-- (Fall Back To The First Tracked Quest) was never the game's.
-- Kept in the saved settings, so a reload on the way still gives it back.
-- The same pin stands on a needed item's source (0.15.0, Needed: the game's
-- own point for the quest is the objective the item is for) while every
-- open place of the quest is one, and is given back the moment the bags hold
-- the item.
-- And on a followed quest's own place once the game's point for quests is
-- seen off the ground (2026-10-04, the user's video and /route pin: this
-- client puts a quest's point at height 0 -- 166 yd under Thunder Bluff's
-- mesa, 40-60 under Mulgore's plain -- so the marker, hung on the game's
-- frame, sank into the ground; the game sets a map pin on the ground, the
-- vendors' stand-ins stood on them). Seen once -- the game's distance to its
-- point more than OFF_GROUND above the flat one on the map allows -- it holds
-- for the session (StandIn.offGround): the pin on Route's own spot, so the
-- marker stands on the ground and on the place the route goes to. Inside a
-- quest's area the marker still hides (Beacon.InArea: s.spot).
--------------------------------------------------------------------------------

-- in a block: its helpers stay out of the main chunk's 200 locals
do
	local STAND_IN_MOVE = 30   -- yards: a new exit dock this far from the pin moves it
	local SPOT_MOVE = 8        -- yards: a quest's place this far from its stand-in moves it
	local OFF_GROUND = 15      -- yards: the game's point this far above or below the ground is off it
	-- the stand-in the player took away ("<questID>:<item>" for a needed
	-- item's source, "<questID>:dock"): none put up for it again meanwhile
	local dismissed = nil

	-- Beside the settings, not in them: a journey's state has no place in the
	-- settings backup
	local function SaveStandIn(value)
		if type(MelloUI.db) == "table" then
			MelloUI.db.routeStandIn = value
		end
	end

	-- The map pin, as continent yards and as the map point it was set on
	local function WaypointYards()
		if not (C_Map.HasUserWaypoint and C_Map.GetUserWaypoint) then
			return nil
		end
		local okH, has = pcall(C_Map.HasUserWaypoint)
		if not (okH and Plain(has)) then
			return nil
		end
		local ok, point = pcall(C_Map.GetUserWaypoint)
		if not ok or type(point) ~= "table" then
			return nil
		end
		local mapID = Plain(point.uiMapID)
		local px, py = VectorXY(point.position)
		if not (mapID and px and py) then
			return nil
		end
		local cont, x, y = ToYards(mapID, px, py)
		return cont, x, y, mapID, px, py
	end

	local function IsPlace(s, cont, x, y)
		return s ~= nil and cont ~= nil and s.cont == cont and Dist(s.x, s.y, x, y) < 5
	end

	StandIn.IsPin = function(mapID, px, py)
		if not standIn then
			return false
		end
		local cont, x, y = ToYards(mapID, px, py)
		return IsPlace(standIn, cont, x, y)
	end

	-- The map pin on a map point, super-tracked
	local function SetPin(mapID, mx, my)
		if not (mapID and mx and my and C_Map.SetUserWaypoint and UiMapPoint) then
			return false
		end
		local okCan, can = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
		if okCan and can == false then
			return false
		end
		local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, mx, my))
		if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
		end
		return ok
	end

	-- The dock where the route leaves the player's continent, and its label
	local function ExitDock(cont)
		local points = route and route.points
		if not points then
			return nil
		end
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			if a[1] == cont and b[1] ~= cont then
				local index = type(a[5]) == "string" and tonumber(a[5]:match("^D(%d+)$"))
				local dock = index and docks and docks[index]
				return a, dock and dock.label
			end
		end
		return nil
	end

	-- The game's tracking back on the quest a stand-in held: only while the
	-- quest is still in the log (review, 2026-09-28: one abandoned meanwhile
	-- was tracked again, and nothing was followed)
	local function TrackQuest(questID)
		if not (questID and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then
			return
		end
		if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
			local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
			if not (ok and index) then
				return
			end
		end
		if securecallfunction then
			securecallfunction(C_SuperTrack.SetSuperTrackedQuestID, questID)
		else
			pcall(C_SuperTrack.SetSuperTrackedQuestID, questID)
		end
	end

	-- The stand-in off; with `giveBack`, the pin or the quest that was tracked
	-- before is tracked again (only while the pin is still the stand-in)
	local function EndStandIn(giveBack)
		local s = standIn
		standIn = nil
		SaveStandIn(nil)
		if not (s and giveBack) then
			return
		end
		if not IsPlace(s, WaypointYards()) then
			return
		end
		if s.pin then
			SetPin(s.pin[1], s.pin[2], s.pin[3])
			return
		end
		-- the quest first: with the pin cleared before, nothing would be tracked for a moment
		TrackQuest(s.questID)
		if C_Map.ClearUserWaypoint then
			pcall(C_Map.ClearUserWaypoint)
		end
	end

	-- Whether the game's point for the followed quest is off the ground (see
	-- the top): measured while the game tracks the quest, kept once seen
	local function QuestPointOffGround(d)
		if StandIn.offGround then
			return true
		end
		local quest = SuperTrackState()
		if not (quest and quest == d.questID and C_Navigation and C_Navigation.GetDistance) then
			return false
		end
		local okD, dist = pcall(C_Navigation.GetDistance)
		dist = okD and Plain(dist) or nil
		local mapID, mx, my = QuestObjectivePoint(quest)
		if not (dist and mapID) then
			return false
		end
		local cont, x, y = ToYards(mapID, mx, my)
		local pcont, px, py = PlayerYards(true)
		if not (cont and cont == pcont) then
			return false
		end
		local flat = Dist(px, py, x, y)
		if dist * dist - flat * flat > OFF_GROUND * OFF_GROUND then
			StandIn.offGround = true
		end
		return StandIn.offGround == true
	end

	-- (`whole`: the marker's whole label, a needed item's source's; `spot`:
	-- the quest's own place)
	local function PlaceStandIn(dock, label, whole, spot)
		local mapID, mx, my = MapPointOfYards(dock[1], dock[2], dock[3])
		local before = standIn
		local s = { cont = dock[1], x = dock[2], y = dock[3], spot = spot,
			label = whole or ("|A:Waypoint-MapPin-ChatIcon:16:16|a " .. (label or "the boat")) }
		if before then
			s.pin, s.questID = before.pin, before.questID
			-- (2026-10-04) another quest meanwhile: the one to give back is that one,
			-- if the game tracks it -- the pin before stays the player's own
			if destination.fromQuest and before.questID ~= destination.questID then
				local quest = SuperTrackState()
				s.questID = quest == destination.questID and quest or nil
			end
		else
			-- what to give back: the pin there was (the player's own), the quest
			-- the game tracks (not one Route follows as the first tracked quest:
			-- the game never tracked it, and holding it kept Route on it when the
			-- tracker's order changed)
			local cont, _, _, pm, px, py = WaypointYards()
			if cont then
				s.pin = { pm, px, py }
			end
			local quest = SuperTrackState()
			s.questID = destination.fromQuest and quest == destination.questID and quest or nil
		end
		-- known before the pin is set: its USER_WAYPOINT_UPDATED reads it
		standIn = s
		if not SetPin(mapID, mx, my) then
			standIn = before
			return
		end
		SaveStandIn({ cont = s.cont, x = s.x, y = s.y, pin = s.pin, questID = s.questID })
		-- (0.18.4) the marker, standing for the same destination, glides there
		if StandIn.Moved then
			StandIn.Moved()
		end
	end

	-- Whether Route's own pin should stand for the destination but is not up
	-- there yet (2026-10-04, the user's video: on a quest picked in the tracker
	-- the marker showed on the game's point, sunk, then hopped to Route's pin):
	-- the marker waits for it (NavIsOurs). Not for a quest whose pin the player
	-- took away
	StandIn.Pending = function(d)
		if not (StandIn.offGround and d and d.fromQuest and not crossContinent and M.isEnabled and M.db.worldMarker) then
			return false
		end
		if dismissed and dismissed:find("^" .. tostring(d.questID) .. ":") then
			return false
		end
		return not (standIn and standIn.cont == d.cont and Dist(standIn.x, standIn.y, d.x, d.y) < STAND_IN_MOVE)
	end

	-- A stand-in left from before a reload: given back once the pins are known
	StandIn.GiveBackSaved = function()
		local saved = MelloUI.db and MelloUI.db.routeStandIn
		if standIn or type(saved) ~= "table" then
			return false
		end
		local cont, x, y = WaypointYards()
		if not cont then
			return false
		end
		if not IsPlace(saved, cont, x, y) then
			SaveStandIn(nil)
			return false
		end
		standIn = saved
		EndStandIn(true)
		return true
	end

	StandIn.Update = function()
		local cont = PlayerYards()
		if not cont then
			return
		end
		local d = destination
		crossContinent = d ~= nil and d.cont ~= cont
		-- a needed item's source on this continent (0.15.0, Needed): the pin
		-- on the source itself, so the game's frame and the marker show it
		-- (the game's own point is the objective the item is for); given back
		-- like the dock's the moment the destination is the objective again.
		-- Only while every open place is a source: beside a plain objective the
		-- pick moves between the two as the player walks (review, 2026-09-28)
		local atSource = not crossContinent and d ~= nil and d.source ~= nil and d.sourceOnly
		-- (2026-10-04) a followed quest's own place, the game's point for it off the ground
		local atSpot = not crossContinent and not atSource and d ~= nil and d.fromQuest and M.isEnabled
			and M.db.worldMarker and QuestPointOffGround(d)
		local want = (crossContinent or atSource or atSpot) and M.isEnabled and M.db.worldMarker
		-- what a stand-in would stand for, for a quest (`dismissed`)
		local key = want and d.fromQuest and (d.questID .. ":" .. (atSource and d.source.gate.item or atSpot and "spot" or "dock")) or nil
		-- the stand-in pin removed or replaced (by the player): no longer ours;
		-- removed, with nothing else tracked, the quest it held is tracked again
		if standIn and not IsPlace(standIn, WaypointYards()) then
			local s = standIn
			EndStandIn(false)
			dismissed = key
			if not WaypointYards() and not SuperTrackState() then
				TrackQuest(s.questID)
			end
		elseif dismissed ~= key then
			dismissed = nil
		end
		if key and key == dismissed then
			return
		end
		if want and (atSource or atSpot) then
			if standIn and standIn.cont == d.cont and Dist(standIn.x, standIn.y, d.x, d.y) < (atSpot and SPOT_MOVE or STAND_IN_MOVE)
				and (standIn.spot or false) == (atSpot or false) then
				standIn.label = d.label   -- (another source this near: its name)
				return
			end
			PlaceStandIn({ d.cont, d.x, d.y }, nil, d.label, atSpot or nil)
			return
		end
		local dock, label
		if want and route and route.dest and route.dest[1] == d.cont and Dist(route.dest[2], route.dest[3], d.x, d.y) < 1 then
			dock, label = ExitDock(cont)
		end
		if not dock then
			-- on the destination's continent, or the marker off: the old pin back
			-- (with no route yet the stand-in waits for one)
			if standIn and not want then
				EndStandIn(true)
			end
			return
		end
		if standIn and standIn.cont == dock[1] and Dist(standIn.x, standIn.y, dock[2], dock[3]) < STAND_IN_MOVE then
			return
		end
		PlaceStandIn(dock, label)
	end

	-- The route cleared: the stand-in on the dock goes with it. A quest it
	-- held is tracked by the game again first, as it was before the pin went
	-- up (review, 2026-09-28: the Services bar's Stop Route left nothing
	-- tracked, only while the pin was up); the tracker's click, letting go of
	-- the quest, takes the game's tracking off it right after.
	StandIn.Drop = function()
		local s = standIn
		if s then
			EndStandIn(false)
			if IsPlace(s, WaypointYards()) then
				if not s.pin then
					TrackQuest(s.questID)
				end
				if C_Map.ClearUserWaypoint then
					pcall(C_Map.ClearUserWaypoint)
				end
			end
		end
	end
end

-- Route to a candidate; with `pin`, also place the map waypoint there so the
-- map and the waypoint arrow show it (removing the pin ends the route).
function M:SetDestinationTo(candidate, label, pin, noticeText)
	local cont, x, y = CandidateYards(candidate)
	if not cont then
		-- (a point on a map with no place: said once; its caller falls back)
		if candidate.mapID then
			M.CannotPlace(candidate.mapID, "point")
		end
		return false
	end
	local mapID, mx, my = candidate.mapID, candidate.x, candidate.y
	if not mapID then
		mapID, mx, my = MapPointOfYards(cont, x, y)
	end
	M.stopped = nil   -- (a destination chosen: the player's pick, M.nav.Stop)
	destination = { cont = cont, x = x, y = y, mapID = mapID, mx = mx, my = my, label = label }
	if pin and mapID and C_Map.SetUserWaypoint and UiMapPoint then
		local okCan, can = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
		if not (okCan and can == false) then
			local okSet = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, mx, my))
			-- only a waypoint that is really there makes the destination its
			-- own: otherwise the next tick saw no waypoint and dropped it
			local okHas, has = pcall(C_Map.HasUserWaypoint)
			destination.fromWaypoint = (okSet and (not C_Map.HasUserWaypoint or (okHas and has))) and true or nil
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
				pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
			end
		end
	end
	Plan(true, true, noticeText)
	return true
end

-- Straight-line yards from the player, or nil when on another continent.
-- `sameFrame`: the player's place already asked this frame is used again
-- (a scan over many candidates asks the game once, not once each).
function M:DistanceTo(candidate, sameFrame)
	local pcont, px, py = PlayerYards(sameFrame)
	local cont, x, y = CandidateYards(candidate)
	if not (pcont and cont) then
		return nil
	end
	if cont ~= pcont then
		return nil, true
	end
	return Dist(px, py, x, y)
end

-- Index and cost (seconds) of the candidate cheapest to reach by route. While
-- the graph is still being built (the first route of the session): nil, nil,
-- true -- not priced yet; M:WhenReady makes the choice once it can be.
-- costs (optional, 0.17.0): a table filled with every candidate's cost
-- ([i] = seconds, nil where none), for a caller's own rule (Services' zone)
-- (0.17.1) Every candidate is priced in ONE search (Search.Price), as a job:
-- one that goes on in the next frames answers nil, nil, true as well, and
-- M:WhenReady runs once it has ended. Its answer is kept PRICE_KEEP seconds
-- for the same places while the player is within PRICE_NEAR yards of where
-- it was asked, so that next ask has it at once. A candidate with no way at
-- all costs its straight line on foot, as before; one the search stopped
-- short of (far dearer than the cheapest) none.
function M:Cheapest(candidates, costs)
	local pcont, px, py = PlayerYards()
	if not pcont then
		return nil
	end
	if not Build.Ready() then
		Build.Loading()   -- (the notice and the arrow's working look while it lasts)
		return nil, nil, true
	end
	local places, index, parts = {}, {}, {}
	for i, c in ipairs(candidates) do
		local cont, x, y = CandidateYards(c)
		if cont then
			local n = #places + 1
			places[n], index[n] = { cont, x, y }, i
			parts[n] = string.format("%d:%.0f:%.0f", cont, x, y)
		end
	end
	local sig = table.concat(parts, " ")
	local kept = Search.priced[sig]
	if not (kept and kept.scont == pcont and GetTime() - kept.at < Search.PRICE_KEEP
		and Dist(px, py, kept.sx, kept.sy) <= Search.PRICE_NEAR) then
		local pending = Search.pricing[sig]
		if pending and not pending.ended then
			return nil, nil, true   -- (asked for already: its answer comes)
		end
		local job = { kind = "price", scont = pcont, sx = px, sy = py, places = places, costs = {}, sig = sig,
			done = Search.Priced }
		Search.pricing[sig] = job
		if not Search.Run(job) then
			return nil, nil, true
		end
		Search.Priced(job)
		kept = job
	end
	if costs then
		for i = 1, #candidates do
			costs[i] = nil
		end
	end
	local best, bestCost
	for n = 1, #places do
		local i, p = index[n], places[n]
		local cost = kept.costs[n]
		if cost == nil and kept.exhausted and p[1] == pcont then
			cost = Dist(px, py, p[2], p[3]) / WALK * 1.3
		end
		if costs then
			costs[i] = cost
		end
		if cost and (not bestCost or cost < bestCost) then
			best, bestCost = i, cost
		end
	end
	return best, bestCost
end

-- A pricing's answer kept (M:Cheapest; Search.Run's done), by its places;
-- the ones kept past PRICE_KEEP let go
function Search.Priced(job)
	local now = GetTime()
	job.ended, job.at = true, now
	local kept = Search.priced
	for sig, old in pairs(kept) do
		if now - old.at >= Search.PRICE_KEEP then
			kept[sig] = nil
		end
	end
	kept[job.sig] = job
	if Search.pricing[job.sig] == job then
		Search.pricing[job.sig] = nil
	end
end

-- (0.17.0, Services' nearest: your own zone wins a near tie) The zone map a
-- point lies in -- the zone, never a city inside it -- from continent yards
-- (as Where gives them) or a candidate (as DistanceTo takes it); nil where
-- the client places it in no zone. Asks the client once per call: a caller
-- keeps the answer.
function M:ZoneAt(cont, yx, yy)
	if not (cont and yx and yy and C_Map.GetMapInfoAtPosition) then
		return nil
	end
	local w, h = WorldSize(cont)
	if not (w and h) or w <= 0 or h <= 0 then
		return nil
	end
	local ok, info = pcall(C_Map.GetMapInfoAtPosition, cont, yx / w, yy / h)
	local zone = ok and type(info) == "table" and Plain(info.mapID) or nil
	return zone ~= cont and zone or nil
end

function M:ZoneOf(c)
	return M:ZoneAt(CandidateYards(c))
end

-- the walking speed the costs are in (yards a second)
M.WALK = WALK

-- fn run once routes can be priced: at once when the graph is built, else in
-- the frame after it is (the build started now if it is not yet). For a
-- choice Cheapest could not make yet (its third answer): made then, by route
-- as ever, not by straight line. Dropped when Route is switched off meanwhile.
-- (0.17.1) A search going on in the next frames (Search.Run): fn run once no
-- search is under way any more, so the choice it waited for is there.
function M:WhenReady(fn)
	if Build.ready then
		if Search.Busy() then
			Search.After(fn)
		else
			fn()
		end
		return
	end
	local list = Build.later or {}
	Build.later = list
	list[#list + 1] = fn
	Build.Want()
	Build.Loading()
end

-- The world map's list is walked only while it decides the answer (user,
-- 2026-09-24, the /melloperf recording). A flight master's map starts that
-- list over, and the next answer asked (the Services bar's flight icon, a
-- few seconds after every visit) walked every zone of both continents for
-- it: 18 ms and 3.6 MB in one call, for a list TaxiUsable does not read once
-- the character knows its own points. Those are kept as the map opens
-- (KnownFlightsHere), so a point learned there is usable at once; they are
-- only ever added to, so once there is one the walk is not needed again.
function M:IsTaxiUsable(id)
	local t = taxis and taxis[id]
	if not t then
		return false
	end
	if not next(CharFlights()) then
		RefreshDiscovered()
	end
	return TaxiUsable(id, t)
end

function M:HasDestination()
	return destination ~= nil, destination and destination.label
end

function M:Clear()
	StandIn.Drop()
	destination = nil
	route = nil
	Redraw()
end

local function CheckArrival()
	if not (destination and route) or destination.fromQuest then
		return
	end
	local cont, x, y = PlayerYards()
	if cont and cont == destination.cont and Dist(x, y, destination.x, destination.y) <= (tonumber(M.db.arrive) or 25) then
		-- with Travel Time, how long the way took: "Arrived: Stormwind (2:48)"
		local took = Travel.Took(destination)
		M:Notify("Arrived: " .. (destination.label or "destination") .. (took and (" (" .. took .. ")") or ""), "arrive")
		if destination.fromWaypoint and C_Map.ClearUserWaypoint then
			pcall(C_Map.ClearUserWaypoint)
		end
		M:Clear()
	end
end

--------------------------------------------------------------------------------
-- Recording
--------------------------------------------------------------------------------

local last = nil         -- last breadcrumb { cont, key, x, y }
local taxiStart = nil    -- where the current flight began
local recorded = 0       -- breadcrumbs this session, for /route
local recordSkip = ""    -- why the last Record call recorded nothing, for /route

local Record
do
	-- A flight landed: one edge from take-off to landing
	local function Landing(cont, ax, ay, bx, by)
		local akey, a = AddNode(cont, ax, ay)
		local bkey, b = AddNode(cont, bx, by)
		if akey ~= bkey then
			Link(cont, a, akey, b, bkey, Dist(ax, ay, bx, by) / FLIGHT + 20)
		end
	end

	-- A breadcrumb: its node, linked to the last one (`lastKey`, `d` yards
	-- back) when that is near
	local function Crumb(cont, x, y, lastKey, d)
		local key, node = AddNode(cont, x, y)
		if lastKey and key ~= lastKey and d <= LINK then
			local prev = live.graphs[cont][lastKey]
			if prev then
				Link(cont, node, key, prev, lastKey, d / WALK)
			end
		end
	end

	-- The graph changes go through Build.Learn: made now, or once the graph
	-- is built; the recorder's own state (the last breadcrumb, the flight)
	-- is kept here as ever, and a cell's key needs no graph
	Record = function()
		if not (M.isEnabled and M.db.learn) then
			recordSkip = "learning is off"
			return
		end
		local okI, inInstance = pcall(IsInInstance)
		if not okI or inInstance then
			recordSkip = okI and "in an instance" or "the game did not say whether you are in an instance"
			last = nil
			return
		end
		local okT, onTaxi = pcall(UnitOnTaxi, "player")
		if okT and onTaxi then
			recordSkip = "on a taxi"
			if not taxiStart then
				local cont, x, y = PlayerYards()
				if cont then
					taxiStart = { cont, x, y }
				end
			end
			last = nil
			return
		end
		if taxiStart then
			local cont, x, y = PlayerYards()
			if cont and cont == taxiStart[1] then
				Build.Learn(Landing, cont, taxiStart[2], taxiStart[3], x, y)
			end
			taxiStart = nil
		end
		local cont, x, y = PlayerYards()
		if not cont then
			recordSkip = "no player position"
			last = nil
			return
		end
		recordSkip = ""
		if last and last.cont == cont then
			local d = Dist(x, y, last.x, last.y)
			if d < CELL * 0.7 then
				return
			end
			recorded = recorded + 1
			Build.Learn(Crumb, cont, x, y, last.key, d)
			last = { cont = cont, key = KeyOf(x, y), x = x, y = y }
		else
			Build.Learn(Crumb, cont, x, y)
			last = { cont = cont, key = KeyOf(x, y), x = x, y = y }
		end
	end
end

--------------------------------------------------------------------------------
-- World map drawing
--------------------------------------------------------------------------------

-- The trail: how the way is drawn, on the map and the minimap alike, in the
-- look the player picks (Trail Look, 0.19.5: the user's A, C and E of
-- BuildData/output/route_look_sketch, "to fit our style more"; before it,
-- pick A of route_marks_sketch, the red dots, 2026-09-30):
--   beads   (E, the default) Media/Textures/Route/trail_dot (Tools/
--           make_route_beam.py), a white disc with a darker rim, tinted with
--           Route's red (MelloUI.Meaning.routeTrail, the World Marker beam's
--           red, a meaning colour read when drawing), each in a ring of the
--           palette's gold (selectedTrim)
--   line    (A) one pale gold line (the palette's text) in a dark casing
--           (innerPanel), round at its bends; a guessed stretch, a flight's
--           and a boat's dashed
--   dashes  (C) short pale gold dashes in the same casing
-- A guessed stretch (a straight line where no road is known) is paler and
-- sparser; a flight's and a boat's marks are smaller and sparser.
local STYLE = {
	road = { size = 1.0, gap = 1.6, alpha = 1 },
	guess = { size = 1.0, gap = 2.2, alpha = 0.55 },
	flight = { size = 0.9, gap = 3.0, alpha = 0.8 },
	boat = { size = 0.7, gap = 3.0, alpha = 0.6 },
}
local MAX_DOTS = 700

-- the trail's looks and their measures (fields of M: this file's main chunk
-- is near Lua's limit of locals)
M.TRAIL = { beads = true, line = true, dashes = true,
	RING = 0.74,               -- a bead's red disc, of its gold ring's size (the sketch's 1.4 px ring at 10.5)
	CORE = 0.27, CASE = 0.57,  -- the line's gold core and dark casing, of the dot size (2.8 and 6 px at 10.5)
	DASH = 0.86, GAP = 0.57,   -- a dash and the space after it, of the dot size (9 and 6 px at 10.5)
	ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
}
-- the trail's look now: the setting's, beads for anything else
function M.TrailLook()
	local look = M.db and M.db.trailLook
	return (look ~= nil and M.TRAIL[look] == true) and look or "beads"
end

-- A pool of small textures and lines on one frame, laid out along route
-- segments with an even spacing that carries over from one segment to the
-- next. A pooled region is painted by its palette key only when the key or
-- the alpha changes (the minimap redraws twenty times a second); a new
-- palette repaints them through the kit's list (W.Paint). A piece is placed,
-- sized and shown again only when its place, size or alpha changed (0.19.5:
-- standing still, a tick of the minimap writes nothing; the beads' gold
-- rings had doubled the writes a tick).
local function NewPainter(frame)
	-- (the dot's path here: the file's main chunk is at Lua 5.1's 200 locals)
	local TRAIL_DOT = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Route\\trail_dot"   -- look-ok: the trail's dots in Route's red, a meaning colour (the user's pick 2026-10-06 keeps them, ringed in the palette's gold)
	local T = M.TRAIL
	local painter = { frame = frame, dots = {}, rims = {}, used = 0, cases = {}, cores = {}, lused = 0,
		jcases = {}, jcores = {}, jused = 0, carry = 0, dashOn = true, look = "beads" }
	local function Paint(region, key, alpha, how)
		local W = MelloUI.Widgets
		if (region.mpKey ~= key or region.mpAlpha ~= alpha) and W and W.Paint then
			region.mpKey, region.mpAlpha = key, alpha
			W.Paint(region, key, how, alpha)
		end
	end
	local function Finite(a, b, c)
		return a > -math.huge and a < math.huge and b > -math.huge and b < math.huge
			and (c == nil or (c > -math.huge and c < math.huge))
	end
	function painter:Begin()
		self.used, self.lused, self.jused = 0, 0, 0
		self.carry, self.dashOn, self.lastX = 0, true, nil
		self.look = M.TrailLook()
	end
	-- a bead: Route's red dot in its gold ring
	function painter:Dot(x, y, size, style, anchor)
		if self.used >= MAX_DOTS then
			return
		end
		if not (x > -math.huge and x < math.huge and y > -math.huge and y < math.huge and size > 0 and size < math.huge) then
			return   -- (a NaN or endless place or size: nothing to draw)
		end
		self.used = self.used + 1
		local dot, rim = self.dots[self.used], self.rims[self.used]
		if not dot then
			rim = self.frame:CreateTexture(nil, "OVERLAY", nil, 1)
			rim:SetTexture(T.ROUND)
			dot = self.frame:CreateTexture(nil, "OVERLAY", nil, 2)
			dot:SetTexture(TRAIL_DOT)
			rim:SetPoint("CENTER", dot, "CENTER")   -- (the ring round its dot: placed with it, once)
			self.dots[self.used], self.rims[self.used] = dot, rim
		end
		local c = MelloUI.Meaning.routeTrail
		if dot.colour ~= c then
			dot.colour = c
			dot:SetVertexColor(c[1], c[2], c[3])
		end
		if rim.mpAlpha ~= style.alpha or rim.mpKey ~= "selectedTrim" then
			Paint(rim, "selectedTrim", style.alpha, "vertex")
		end
		if dot.atAlpha ~= style.alpha then
			dot.atAlpha = style.alpha
			dot:SetAlpha(style.alpha)
		end
		if dot.atSize ~= size then
			dot.atSize = size
			dot:SetSize(size * T.RING, size * T.RING)
			rim:SetSize(size, size)
		end
		if dot.atX ~= x or dot.atY ~= y or dot.atAnchor ~= anchor then
			dot.atX, dot.atY, dot.atAnchor = x, y, anchor
			dot:ClearAllPoints()
			dot:SetPoint("CENTER", self.frame, anchor, x, y)
		end
		if not dot.on then
			dot.on = true
			dot:Show()
			rim:Show()
		end
	end
	-- a stroke of the line: its dark casing under, its gold core over (every
	-- casing under every core: the sublevels, so the bends join)
	function painter:Stroke(ax, ay, bx, by, size, alpha, anchor)
		if self.lused >= MAX_DOTS then
			return
		end
		self.lused = self.lused + 1
		local case, core = self.cases[self.lused], self.cores[self.lused]
		if not case then
			case = self.frame:CreateLine(nil, "OVERLAY", nil, 1)
			core = self.frame:CreateLine(nil, "OVERLAY", nil, 3)
			self.cases[self.lused], self.cores[self.lused] = case, core
		end
		Paint(case, "innerPanel", 0.92 * alpha, "fill")
		Paint(core, "text", alpha, "fill")
		if case.atSize ~= size then
			case.atSize = size
			case:SetThickness(size * T.CASE)
			core:SetThickness(size * T.CORE)
		end
		if case.atAX ~= ax or case.atAY ~= ay or case.atBX ~= bx or case.atBY ~= by or case.atAnchor ~= anchor then
			case.atAX, case.atAY, case.atBX, case.atBY, case.atAnchor = ax, ay, bx, by, anchor
			case:SetStartPoint(anchor, self.frame, ax, ay)
			case:SetEndPoint(anchor, self.frame, bx, by)
			core:SetStartPoint(anchor, self.frame, ax, ay)
			core:SetEndPoint(anchor, self.frame, bx, by)
		end
		if not case.on then
			case.on = true
			case:Show()
			core:Show()
		end
	end
	-- the line's round bend: a disc of the casing and one of the core
	function painter:Joint(x, y, size, alpha, anchor)
		if self.jused >= MAX_DOTS then
			return
		end
		self.jused = self.jused + 1
		local case, core = self.jcases[self.jused], self.jcores[self.jused]
		if not case then
			case = self.frame:CreateTexture(nil, "OVERLAY", nil, 1)
			case:SetTexture(T.ROUND)
			core = self.frame:CreateTexture(nil, "OVERLAY", nil, 3)
			core:SetTexture(T.ROUND)
			self.jcases[self.jused], self.jcores[self.jused] = case, core
		end
		Paint(case, "innerPanel", 0.92 * alpha, "vertex")
		Paint(core, "text", alpha, "vertex")
		if case.atX ~= x or case.atY ~= y or case.atSize ~= size or case.atAnchor ~= anchor then
			case.atX, case.atY, case.atSize, case.atAnchor = x, y, size, anchor
			case:SetSize(size * T.CASE, size * T.CASE)
			core:SetSize(size * T.CORE, size * T.CORE)
			case:ClearAllPoints()
			case:SetPoint("CENTER", self.frame, anchor, x, y)
			core:ClearAllPoints()
			core:SetPoint("CENTER", self.frame, anchor, x, y)
		end
		if not case.on then
			case.on = true
			case:Show()
			core:Show()
		end
	end
	-- a segment in dashes: the dash and the space carry over to the next
	function painter:Dashes(ax, ay, bx, by, style, size, len, anchor)
		local on, off = size * T.DASH, size * T.GAP * style.gap / STYLE.road.gap
		if not (Finite(on, off) and on > 0 and off > 0) then
			return
		end
		local ux, uy = (bx - ax) / len, (by - ay) / len
		local drawing, left = self.dashOn, self.carry
		if not (left > 0 and left < math.huge) then
			drawing, left = true, on
		end
		local t = 0
		while t < len do
			if self.lused >= MAX_DOTS then
				self.carry = 0
				return
			end
			local d = math.min(left, len - t)
			if drawing then
				self:Stroke(ax + ux * t, ay + uy * t, ax + ux * (t + d), ay + uy * (t + d), size, style.alpha, anchor)
			end
			t, left = t + d, left - d
			if left <= 1e-6 then
				drawing = not drawing
				left = drawing and on or off
			end
		end
		self.dashOn, self.carry = drawing, left
	end
	-- One route segment; `unit` is the dot size for width 3 in frame units.
	function painter:Segment(ax, ay, bx, by, style, unit, anchor)
		local dx, dy = bx - ax, by - ay
		local len = math.sqrt(dx * dx + dy * dy)
		-- finite, positive numbers only (NaN fails every test below): a step of
		-- 0 or a map zoomed very far in never ended this loop -- the game froze
		-- opening the map (a player in gamepad mode, 2026-09-26)
		if not (len > 0 and len < math.huge and ax > -math.huge and ax < math.huge and ay > -math.huge and ay < math.huge) then
			return
		end
		local size = unit * style.size
		local step = size * style.gap
		if not (size > 0 and size < math.huge and step > 0 and step < math.huge) then
			return
		end
		local look = self.look
		if look == "line" and style == STYLE.road then
			self:Joint(ax, ay, size, style.alpha, anchor)
			self:Stroke(ax, ay, bx, by, size, style.alpha, anchor)
			self.lastX, self.lastY, self.lastSize, self.lastAnchor = bx, by, size, anchor
			self.dashOn, self.carry = true, 0
			return
		elseif look ~= "beads" then
			if self.lastX then
				-- (a solid run ends: its last bend rounded)
				self:Joint(self.lastX, self.lastY, self.lastSize, STYLE.road.alpha, self.lastAnchor)
				self.lastX = nil
			end
			self:Dashes(ax, ay, bx, by, style, size, len, anchor)
			return
		end
		local ux, uy = dx / len, dy / len
		local at = self.carry
		if not (at >= 0 and at < math.huge) then
			at = 0
		end
		while at <= len do
			if self.used >= MAX_DOTS then
				-- (every dot drawn: nothing more to walk this pass)
				self.carry = 0
				return
			end
			self:Dot(ax + ux * at, ay + uy * at, size, style, anchor)
			at = at + step
		end
		self.carry = at - len
	end
	function painter:End()
		if self.lastX then
			self:Joint(self.lastX, self.lastY, self.lastSize, STYLE.road.alpha, self.lastAnchor)
			self.lastX = nil
		end
		for i = self.used + 1, #self.dots do
			local dot = self.dots[i]
			if dot.on then
				dot.on = false
				dot:Hide()
				self.rims[i]:Hide()
			end
		end
		for i = self.lused + 1, #self.cases do
			local case = self.cases[i]
			if case.on then
				case.on = false
				case:Hide()
				self.cores[i]:Hide()
			end
		end
		for i = self.jused + 1, #self.jcases do
			local case = self.jcases[i]
			if case.on then
				case.on = false
				case:Hide()
				self.jcores[i]:Hide()
			end
		end
	end
	function painter:Clear()
		self.used, self.lused, self.jused, self.lastX = 0, 0, 0, nil
		self:End()
	end
	return painter
end

-- The goal's mark (0.19.5, with the trail's looks; the user's pick of
-- route_look_sketch): the flag (the widget glyph) on the palette's dark disc
-- in its gold ring, the objective marks' family; the flag in Route's red
-- with the beads, in the palette's text colour with the line and the dashes.
-- On the world map it lies over the game's own red waypoint pin, a little
-- larger (a cover: the game's pin under it still takes its clicks, this mark
-- takes no mouse); on the minimap at its place, or on the edge toward it
-- with a gold chevron when it lies beyond. Made the first time a goal is
-- drawn on that map, never at login.
--   M.GoalMark(parent) -> the mark (a frame, hidden)
--   M.MarkPlace(mark, size, anchorFrame, anchor, x, y)   sized, placed (both
--                                         written only on a change), shown:
--                                         the objective marks' on the
--                                         minimap too, with their own glyph
--   M.GoalLay(mark, ...)                  M.MarkPlace, the flag coloured for
--                                         the trail's look now (M.GoalFlag)
M.TRAIL.CHEVRON = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Route\\chevron"   -- look-ok: the minimap goal's edge chevron, the palette's gold
M.TRAIL.GOAL_MAP = 26     -- the mark on the world map, screen px (the game's pin is 30, its diamond about 22)
M.TRAIL.GOAL_MINI = 16    -- on the minimap
M.GOAL_LEVEL = 2900       -- the world map mark's level when the map cannot say its waypoint pin's (its pins: 2000 up)
function M.GoalMark(parent)
	local T, W = M.TRAIL, MelloUI.Widgets
	local f = CreateFrame("Frame", nil, parent)
	f:EnableMouse(false)
	f.ring = f:CreateTexture(nil, "ARTWORK", nil, 1)
	f.ring:SetTexture(T.ROUND)
	f.ring:SetAllPoints()
	f.disc = f:CreateTexture(nil, "ARTWORK", nil, 2)
	f.disc:SetTexture(T.ROUND)
	f.flag = f:CreateTexture(nil, "ARTWORK", nil, 3)
	f.flag:SetPoint("CENTER")
	if W then
		W.Glyph(f.flag, "flag")
		W.Paint(f.ring, "selectedTrim", "vertex", 1)
		W.Paint(f.disc, "innerPanel", "vertex", 0.95)
	end
	f:Hide()
	return f
end
-- the flag's colour for the trail's look now: Route's red with the beads (a
-- meaning colour, out of the palette's list), the palette's text with the
-- line and the dashes; written only on a change (the maps' marks and the
-- World Marker alike)
function M.GoalFlag(flag)
	local look = M.TrailLook()
	local c = MelloUI.Meaning.routeTrail
	if flag.look == look and (look ~= "beads" or flag.red == c) then
		return
	end
	flag.look = look
	if look == "beads" then
		flag.red = c
		if MelloUI.Kit and MelloUI.Kit.Unpaint then
			MelloUI.Kit:Unpaint(flag, "vertex")
		end
		flag:SetVertexColor(c[1], c[2], c[3], 1)
	elseif MelloUI.Widgets then
		flag.red = nil
		MelloUI.Widgets.Paint(flag, "text", "vertex", 1)
	end
end
function M.MarkPlace(f, size, anchorFrame, anchor, x, y)
	if f.size ~= size then
		f.size = size
		f:SetSize(size, size)
		local ring = math.max(1, size * 0.08)
		f.disc:ClearAllPoints()
		f.disc:SetPoint("TOPLEFT", f, "TOPLEFT", ring, -ring)
		f.disc:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ring, ring)
		f.flag:SetSize(size * 0.58, size * 0.58)
	end
	-- (moved half a pixel or more, or onto another frame: the minimap's
	-- marks follow the player a tick at a time, mostly by less)
	local ax, ay = f.atX, f.atY
	if f.atFrame ~= anchorFrame or not ax or (x - ax) * (x - ax) + (y - ay) * (y - ay) >= 0.25 then
		f.atX, f.atY, f.atFrame = x, y, anchorFrame
		f:ClearAllPoints()
		f:SetPoint("CENTER", anchorFrame, anchor, x, y)
	end
	if not f:IsShown() then
		f:Show()
	end
end
function M.GoalLay(f, size, anchorFrame, anchor, x, y)
	M.MarkPlace(f, size, anchorFrame, anchor, x, y)
	if f.flag.look ~= M.TrailLook() or f.flag.look == "beads" and f.flag.red ~= MelloUI.Meaning.routeTrail then
		M.GoalFlag(f.flag)
	end
end
local Provider = nil
local mapPainter = nil
local mapFrame = nil

-- The route layer sits just above the map's own art layers (the tiles come
-- from a pool and land on frame levels that differ from zone to zone) and
-- below the lowest pin, so the dots show through and the pins stay clickable.
-- Pins that are part of the map art rather than markers on it: the explored
-- areas (drawn as a pin above the greyed base tiles), zone highlights, debug.
-- The fog of war is art too (user, 2026-09-23: the route showed only where
-- the map was explored): taken for a pin, it set the route's ceiling and the
-- route was drawn under the fog. Any layer named for fog or exploration
-- counts, whatever this client calls it.
local ART_PINS = {
	PIN_FRAME_LEVEL_MAP_EXPLORATION = true, PIN_FRAME_LEVEL_MAP_HIGHLIGHT = true,
	PIN_FRAME_LEVEL_DEBUG = true, PIN_FRAME_LEVEL_MAP_LINK = true,
	PIN_FRAME_LEVEL_FOG_OF_WAR = true,
}
local function IsArtLayer(kind)
	if ART_PINS[kind] then
		return true
	end
	return type(kind) == "string" and (kind:find("FOG", 1, true) or kind:find("EXPLOR", 1, true)) and true or false
end

-- What sits on the world map's canvas, by frame level (for /route layers)
local function CanvasLayers(canvas)
	local out = {}
	for _, child in ipairs({ canvas:GetChildren() }) do
		local kind = "tiles"
		if child.GetFrameLevelType then
			local ok, k = pcall(child.GetFrameLevelType, child)
			kind = ok and tostring(k) or "pin"
		elseif child.pinTemplate then
			kind = "pin"
		end
		out[#out + 1] = { child:GetFrameLevel(), kind, child == mapFrame }
	end
	table.sort(out, function(a, b) return a[1] < b[1] end)
	return out
end

-- (0.19.5: the one rule for MelloUI's drawings on the map's canvas -- Route's
-- trail and the Quest List's objective areas: M.LayerAboveArt(frame,
-- canvas); the layers it has placed are passed by, so two never climb over
-- each other)
M.artLayers = setmetatable({}, { __mode = "k" })
function M.LayerAboveArt(frame, canvas)
	M.artLayers[frame] = true
	local tiles, pins = canvas:GetFrameLevel(), nil
	for _, child in ipairs({ canvas:GetChildren() }) do
		if not M.artLayers[child] then
			local lv = child:GetFrameLevel()
			local kind = nil
			if child.GetFrameLevelType then
				local ok, k = pcall(child.GetFrameLevelType, child)
				kind = ok and k or "pin"
			elseif child.pinTemplate then
				kind = "pin"
			end
			if kind and not IsArtLayer(kind) then
				if not pins or lv < pins then
					pins = lv
				end
			elseif lv > tiles then
				tiles = lv
			end
		end
	end
	local level = tiles + 1
	if pins and pins > level then
		level = math.min(level + 5, pins - 1)
	end
	if frame:GetFrameLevel() ~= level then
		frame:SetFrameLevel(level)
	end
end

-- The part of the route still ahead: the segments from the player's place
-- on the path (route.progress / atX / atY, set by the arrow) onward, the
-- first one starting at that place. A route is kept while it is followed
-- (user, 2026-09-22), so the part behind the player is not drawn.
local function RouteAhead()
	local points = route.points
	local from = route.progress or 1
	if from < 1 or from >= #points then
		return points, 2
	end
	local list = {}
	if route.atX then
		list[1] = { points[from][1], route.atX, route.atY, points[from][4] }
	else
		list[1] = points[from]
	end
	for i = from + 1, #points do
		list[#list + 1] = points[i]
	end
	return list, 2
end

local function DrawWorldMap()
	if not (Provider and WorldMapFrame and WorldMapFrame:IsShown()) then
		return
	end
	local map = WorldMapFrame
	if not mapFrame then
		local canvas = map:GetCanvas()
		mapFrame = CreateFrame("Frame", nil, canvas)
		mapFrame:SetAllPoints(canvas)
		mapFrame:SetFrameLevel(canvas:GetFrameLevel() + 5)
		mapPainter = NewPainter(mapFrame)
		Perf.SetScript(mapFrame, "OnSizeChanged", function() C_Timer.After(0, DrawWorldMap) end)
	end
	M.LayerAboveArt(mapFrame, map:GetCanvas())
	mapPainter:Begin()
	if M.goalMap then
		M.goalMap:Hide()
	end
	if not (route and M.isEnabled and M.db.worldMap) then
		mapPainter:End()
		return
	end
	local mapID = Plain(map:GetMapID())
	if not mapID then
		mapPainter:End()
		return
	end
	-- finite sizes and scale only (NaN fails every test): an endless canvas
	-- scale made the dots' spacing 0 (the map froze in gamepad mode, 2026-09-26)
	local W, H = Plain(mapFrame:GetWidth()), Plain(mapFrame:GetHeight())
	if not (W and H and W >= 10 and H >= 10 and W < math.huge and H < math.huge) then
		mapPainter:End()
		return
	end
	local scale = map.GetCanvasScale and Plain(map:GetCanvasScale())
	if not (scale and scale > 0 and scale < math.huge) then
		scale = 1
	end
	local unit = 3.5 * (tonumber(M.db.lineWidth) or 3) / scale
	local points = RouteAhead()
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if a[1] == b[1] and b[4] ~= "boat" then
			local ax, ay = OnMap(mapID, a[1], a[2], a[3])
			local bx, by = OnMap(mapID, b[1], b[2], b[3])
			if ax and bx and not (ax < -0.2 and bx < -0.2) and not (ax > 1.2 and bx > 1.2)
				and not (ay < -0.2 and by < -0.2) and not (ay > 1.2 and by > 1.2) then
				mapPainter:Segment(ax * W, -ay * H, bx * W, -by * H, STYLE[b[4]] or STYLE.road, unit, "TOPLEFT")
			end
		end
	end
	mapPainter:End()
	-- the goal's mark, over the game's waypoint pin, the same size on screen
	-- at every zoom. The map's pins stand at fixed levels of their own (its
	-- pin levels manager, from 2000 up: not the canvas's plus some), so the
	-- mark goes one above the waypoint pin's, asked of the map (read only);
	-- the canvas's plus 1000 lay under it (the user, 2026-10-06: the red
	-- diamond still showed)
	local d = destination
	local gx, gy
	if d then
		gx, gy = OnMap(mapID, d.cont, d.x, d.y)
	end
	if gx and gx >= 0 and gx <= 1 and gy >= 0 and gy <= 1 then
		local canvas = map:GetCanvas()
		if not M.goalMap then
			M.goalMap = M.GoalMark(canvas)
		end
		local want = M.GOAL_LEVEL
		local okM, mgr = pcall(map.GetPinFrameLevelsManager, map)
		if okM and mgr and mgr.GetValidFrameLevel then
			local okL, lv = pcall(mgr.GetValidFrameLevel, mgr, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
			lv = okL and Plain(lv)
			if type(lv) == "number" and lv >= 0 and lv < 9000 then
				want = lv + 1
			end
		end
		if M.goalMap:GetFrameLevel() ~= want then
			M.goalMap:SetFrameLevel(want)
		end
		M.GoalLay(M.goalMap, M.TRAIL.GOAL_MAP / scale, mapFrame, "TOPLEFT", gx * W, -gy * H)
	end
end

local function CreateProvider()
	if Provider or not (MapCanvasDataProviderMixin and WorldMapFrame and WorldMapFrame.AddDataProvider) then
		return
	end
	Provider = CreateFromMixins(MapCanvasDataProviderMixin)
	function Provider:RemoveAllData()
		if mapPainter then
			mapPainter:Clear()
		end
		if M.goalMap then
			M.goalMap:Hide()
		end
	end
	function Provider:RefreshAllData()
		DrawWorldMap()
	end
	function Provider:OnCanvasScaleChanged()
		DrawWorldMap()
	end
	WorldMapFrame:AddDataProvider(Provider)
	Perf.HookScript(WorldMapFrame, "OnShow", function() C_Timer.After(0, DrawWorldMap) end)
end

--------------------------------------------------------------------------------
-- Minimap drawing
--------------------------------------------------------------------------------

local mm = nil
local mmPainter = nil
local OUTDOOR = { 466.67, 400, 333.33, 266.67, 200, 133.33 }
local INDOOR = { 300, 240, 180, 120, 80, 50 }
local indoors = false

local function MinimapDiameter()
	local zoom = Minimap:GetZoom()
	local a = tonumber(GetCVar("minimapZoom")) or 0
	local b = tonumber(GetCVar("minimapInsideZoom")) or 0
	if zoom ~= a or zoom ~= b then
		indoors = (zoom ~= a)
	end
	local table_ = indoors and INDOOR or OUTDOOR
	return table_[zoom + 1] or OUTDOOR[1]
end

local function IsRoundMinimap()
	if GetMinimapShape then
		local ok, shape = pcall(GetMinimapShape)
		if ok and shape and shape ~= "ROUND" then
			return false
		end
	end
	return true
end

-- The distance line's place in the column under the minimap (MinimapPanel:
-- one contract for the map, the Services bar and this line; audit,
-- 2026-09-24, rank 18): 2 px under the map as before (square and merged
-- too), and under the Services bar only where a bar offset leaves it no
-- room. Placed again whenever the column is re-laid (the bus's 'column'),
-- only when its place moved.
-- (Fields of M, not locals: this file's main chunk is near Lua's limit.)
function M.PlaceDistanceLine()
	local text = mm and mm.text
	if not text then
		return
	end
	local mp = MelloUI:GetModule("MinimapPanel")
	local rel, relPoint, x, y, justify, maxW
	if mp and mp.ColumnSlot then
		rel, relPoint, x, y, justify, maxW = mp:ColumnSlot("route")
	end
	rel, relPoint, x, y = rel or Minimap, relPoint or "BOTTOM", x or 0, y or -2
	local at = mm.lineAt
	if at and at[1] == rel and at[2] == relPoint and at[3] == x and at[4] == y and at[5] == justify and at[6] == maxW then
		return
	end
	if not at then
		at = {}
		mm.lineAt = at
	end
	at[1], at[2], at[3], at[4], at[5], at[6] = rel, relPoint, x, y, justify, maxW
	text:ClearAllPoints()
	if justify == "RIGHT" then
		-- on the minimap's divider rail, at its right end beside the
		-- "Services" name: kept to the room the rail leaves, cut with "..."
		text:SetPoint("TOPRIGHT", rel, relPoint, x, y)
		text:SetJustifyH("RIGHT")
		text:SetWordWrap(false)
		text:SetWidth(maxW or 0)
	else
		text:SetPoint("TOP", rel, relPoint, x, y)
		text:SetJustifyH("CENTER")
		text:SetWidth(0)
	end
end

-- whether the distance line stands under the minimap now (a route or a
-- destination, Distance Under The Minimap on, the arrow hidden)
function M:DistanceLineShown()
	return (mm and mm:IsShown() and mm.text:IsShown()) and true or false
end

-- The line shown or hidden: the minimap's divider rail moves its "Services"
-- name aside for it or back to the middle (only when the state changes)
function M.LineMaybeChanged()
	local shown = M:DistanceLineShown()
	if shown == M.lineShown then
		return
	end
	M.lineShown = shown
	local mp = MelloUI:GetModule("MinimapPanel")
	if mp and mp.RailName then
		mp.RailName()
	end
	M.PlaceDistanceLine()
end

-- its height in the column while Route keeps the line (Route on, Distance
-- Under The Minimap on, the route's dots on the minimap or not: the line's
-- own switch, M.MinimapLine): its face's size and a hair; nil otherwise
function M:ColumnLine()
	local text = mm and mm.text
	if not (M.isEnabled and M.db and M.db.distanceText and text) then
		return nil
	end
	local ok, _, size = pcall(text.GetFont, text)
	size = ok and Plain(size) or nil
	return (type(size) == "number" and size > 0) and math.ceil(size) + 2 or 12
end

local function EnsureMinimapFrame()
	if mm or not Minimap then
		return
	end
	mm = CreateFrame("Frame", nil, Minimap)
	mm:SetAllPoints(Minimap)
	mm:SetFrameLevel(Minimap:GetFrameLevel() + 6)
	mmPainter = NewPainter(mm)
	mm.text = mm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	-- the route's length (and the destination): the arrow's distance line
	-- while the arrow is hidden, so the numbers' face like it
	RouteFont.Style(mm.text, "fontChat", _G.GameFontNormalSmall)
	M.PlaceDistanceLine()
	MelloUI:On("column", M.PlaceDistanceLine, "Route distance line")
	Travel.Paint()   -- in the arrow's gold, a palette colour
	mm.text:Hide()
	mm:Hide()
end

-- Clip a segment (pixels from the minimap centre) to a circle of radius R.
local function ClipToCircle(ax, ay, bx, by, R)
	local dx, dy = bx - ax, by - ay
	local a = dx * dx + dy * dy
	if a == 0 then
		return nil
	end
	local b = 2 * (ax * dx + ay * dy)
	local c = ax * ax + ay * ay - R * R
	local disc = b * b - 4 * a * c
	if disc < 0 then
		return nil
	end
	local sq = math.sqrt(disc)
	local t0, t1 = (-b - sq) / (2 * a), (-b + sq) / (2 * a)
	if t1 < 0 or t0 > 1 then
		return nil
	end
	t0, t1 = math.max(t0, 0), math.min(t1, 1)
	return ax + dx * t0, ay + dy * t0, ax + dx * t1, ay + dy * t1
end

-- Clip a segment to the square of half-size R (Liang-Barsky).
local function ClipToSquare(ax, ay, bx, by, R, RY)
	RY = RY or R   -- (a map cropped to its Width x Height: half its height)
	local dx, dy = bx - ax, by - ay
	local t0, t1 = 0, 1
	local function Edge(p, q)
		if p == 0 then
			return q >= 0
		end
		local t = q / p
		if p < 0 then
			if t > t1 then return false end
			if t > t0 then t0 = t end
		else
			if t < t0 then return false end
			if t < t1 then t1 = t end
		end
		return true
	end
	if Edge(-dx, ax + R) and Edge(dx, R - ax) and Edge(-dy, ay + RY) and Edge(dy, RY - ay) then
		return ax + dx * t0, ay + dy * t0, ax + dx * t1, ay + dy * t1
	end
	return nil
end

--------------------------------------------------------------------------------
-- Direction arrow: a row of the widget column (user, 2026-10-03: "merge me
-- the Navigation Arrow into the Widget"; pick A of MelloUI-BuildData/output/
-- nav_widget_sketch: the arrow turning in the rim, the ring filling as the
-- way is done, the destination and the distance line on the band; the arrow
-- on the screen went: docs/plans/nav-widget.md). `arrow` is its state, no
-- frame of its own: UpdateArrow, the loading look and the landing countdown
-- set it, the row (MelloUI.Reminders, key "route") reads it --
--   Show / Hide / IsShown   whether the row is wanted (its check)
--   targetCont/X/Y          where it points (aimless: nowhere yet)
--   title, distance.text    the destination; the distance and travel time
--                           (Travel.Line writes it through `distance`)
--   quiet, spinning         the line hidden and the arrow going round while
--                           the roads load with nothing to point at
--   icon                    the row's arrow texture, once it has one (its
--                           colour: Travel.Paint)
-- The row's place and size are the column's (Edit Layout's "Widgets"). The
-- column lays the arrow's texture in the row's face and hands it here
-- (turnArt): Route turns it every frame from a small frame of its own
-- (M.nav.turner, made at that first hand-over, shown only while the row is
-- wanted, as the arrow's own OnUpdate was) and tells the column its lines
-- when they change (M.nav.Push: Rem:SetLines, no re-lay). Made at the
-- module's enable: a table and the row's spec.
--------------------------------------------------------------------------------

local arrow = nil

-- Rotation for a target dx yards east, dy yards south of the player facing f.
local function ArrowRotation(dx, dy, facing)
	local sin, cos = math.sin(facing), math.cos(facing)
	local rx, ry = dx * cos - dy * sin, dx * sin + dy * cos
	return math.atan2(-rx, -ry)
end

-- the row's parts (fields of M: this file's main chunk is near Lua's limit)
M.nav = { KEY = "route", SPIN = 2.4, registered = false,
	MAP_TIP = "Show on the map", STOP_TIP = "Stop the route" }

function M.nav.Rem()
	local r = MelloUI.Reminders
	return type(r) == "table" and type(r.Register) == "function" and r or nil
end

-- the row looked at again on the next frame (shown, hidden, laid afresh)
function M.nav.Refresh()
	local r = M.nav.Rem()
	if r and M.nav.registered then
		r:Refresh(M.nav.KEY)
	end
end

-- where the arrow points, from the way the player faces (Route's turner,
-- every frame while the row is wanted)
function M.nav.Angle()
	local a = arrow
	if not a then
		return nil
	end
	if not a.targetX then
		return a.angle
	end
	local cont, px, py = PlayerYards(true)   -- (the minimap's ask this frame, when it drew first)
	if cont and cont == a.targetCont then
		local facing = 0
		if GetPlayerFacing then
			local ok, f = pcall(GetPlayerFacing)
			facing = ok and Plain(f) or 0
		end
		a.angle = ArrowRotation(a.targetX - px, a.targetY - py, facing)
	end
	return a.angle
end

-- the ring: the share of the way done (none while flying: the flight's
-- time has it)
function M.nav.Share()
	local r = route
	if M.flight.arrowOn or not (r and r.left and r.length and r.length > 0) then
		return nil
	end
	local share = 1 - r.left / r.length
	return share < 0 and 0 or share
end

-- the ring while flying: the flight's time, from take-off
function M.nav.Flight()
	local f = M.flight.arrowOn and M.flight.active
	if f and f.secs and f.at then
		return f.at, f.secs
	end
	return nil
end

-- the map opened on the destination's map (the game's own open, the next
-- frame, out of this click's run); never in the Gamepad UI: a map opened
-- from MelloUI's code there runs its frame manager in MelloUI's run (the
-- 0.15.0 freeze), the player opens it
function M.nav.ShowMap()
	if MelloUI.Safe.GamepadUI() then
		MelloUI:Print("Route: in the Gamepad UI, open your map to see the route.")
		return
	end
	C_Timer.After(0, M.nav.OpenMap)
end

function M.nav.OpenMap()
	if MelloUI.Safe.GamepadUI() or type(_G.OpenWorldMap) ~= "function" then
		return
	end
	local d = destination
	local ok, err = pcall(_G.OpenWorldMap, d and (d.mapID or d.cont) or nil)
	if not ok then
		geterrorhandler()(err)
	end
end

-- the route stopped (the row's Stop, /route clear; user, 2026-10-03: "clicking
-- on stop the route does not actually stop it" -- a tracked quest's route
-- came straight back): the map pin cleared, the game's focus on a quest let
-- go (the quest stays in the tracker), and no quest followed until the player
-- picks one again (M.stopped: ReadTrackedQuest) -- super-tracks a quest, sets
-- a map pin or a destination (SetDestinationTo)
function M.nav.Stop()
	local quest = SuperTrackState()
	local d = destination
	M.stopped = { quest = (d and d.fromQuest and d.questID) or quest or TrackedQuestID(), cleared = quest == nil }
	if quest and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
		-- (once the game's focus is let go, any quest focused again is the
		-- player's pick; when it could not be, another quest)
		M.stopped.cleared = pcall(C_SuperTrack.SetSuperTrackedQuestID, 0) and SuperTrackState() == nil
	end
	if C_Map.ClearUserWaypoint then
		pcall(C_Map.ClearUserWaypoint)
	end
	M:Clear()
end

-- the row's lines told to the column when they changed (from UpdateArrow,
-- the landing countdown and the loading look); the way's share in steps of
-- half a percent
function M.nav.Push()
	local r = M.nav.Rem()
	local a = arrow
	if not (r and M.nav.registered and a and a.shown and r.SetLines) then
		return
	end
	local share = M.nav.Share()
	r:SetLines(M.nav.KEY, a.title or "", (not a.quiet and a.distance.text) or "",
		share and math.floor(share * 200 + 0.5) / 200 or nil)
end

-- the row's arrow turned, every frame while it is wanted (while it goes
-- round, the motion engine turns it: M.nav.Work)
function M.nav.Turn()
	local a = arrow
	local tex = a and a.icon
	if not (tex and a.shown) then
		M.nav.turner:Hide()
		return
	end
	if a.spinning then
		return
	end
	local angle = M.nav.Angle()
	if angle then
		tex:SetRotation(angle)
	end
end

-- the loading look on the row's arrow as Build.ArrowWork has it: it breathes
-- in its gold while the roads load (Anim:Pulse) and goes round, 2.4 s a
-- turn, with nothing to point at (Anim:Spin); set again when the column
-- hands the arrow over (a row made, or another row's face)
function M.nav.Work()
	local a = arrow
	local tex = a and a.icon
	local anim = MelloUI.Anim
	if not (tex and anim and anim.Pulse and anim.Spin and anim.StopGroup) then
		return
	end
	if a.working and not a.breath then
		a.breath = anim:Pulse(tex, 0.35, 1, 0.8)
	elseif not a.working and a.breath then
		anim:StopGroup(a.breath)
		a.breath = nil
		tex:SetAlpha(1)
	end
	if a.spinning and not a.spin then
		a.spin = anim:Spin(tex, M.nav.SPIN)
	elseif not a.spinning and a.spin then
		anim:StopGroup(a.spin)
		a.spin = nil
	end
end

function M.nav.Turning()
	local t = M.nav.turner
	if not t then
		if not (arrow and arrow.icon) then
			return
		end
		t = CreateFrame("Frame")
		t:Hide()
		Perf.SetScript(t, "OnUpdate", M.nav.Turn)
		M.nav.turner = t
	end
	t:SetShown(arrow.shown and arrow.icon ~= nil)
end

function M.nav.Register()
	local r = M.nav.Rem()
	if not r or M.nav.registered then
		return
	end
	M.nav.registered = true
	r:Register({
		key = M.nav.KEY, column = true, label = "Navigation", enabled = true,
		check = function()
			return arrow ~= nil and arrow.shown and M.isEnabled and M.db ~= nil and M.db.arrow and true or false
		end,
		title = function()
			return arrow and arrow.title or ""
		end,
		text = function()
			return (arrow and not arrow.quiet) and arrow.distance.text or ""
		end,
		turn = true,
		turnArt = function(tex)
			if arrow.icon ~= tex then
				-- (another row's face: the look's groups on the one it had go)
				local anim = MelloUI.Anim
				if anim and anim.StopGroup then
					if arrow.breath then
						anim:StopGroup(arrow.breath)
					end
					if arrow.spin then
						anim:StopGroup(arrow.spin)
					end
				end
				if arrow.icon then
					arrow.icon:SetAlpha(1)
				end
				arrow.breath, arrow.spin = nil, nil
			end
			arrow.icon = tex
			Travel.PlayerArrow(tex)
			Travel.Paint()
			M.nav.Work()
			M.nav.Turning()
			M.nav.Turn()
		end,
		fraction = M.nav.Share,
		progress = M.nav.Flight,
		onClick = function()
			M.nav.ShowMap()
		end,
		hint = M.nav.MAP_TIP,
		actions = {
			{ glyph = "way", tip = M.nav.MAP_TIP, desc = "Opens the map on the destination, the route drawn on it.",
			  fn = function() M.nav.ShowMap() end },
			{ glyph = "cross", tip = M.nav.STOP_TIP, desc = "Clears the destination and its route.",
			  fn = function() M.nav.Stop() end },
		},
	})
end

local function EnsureArrow()
	if arrow then
		return
	end
	local a = { shown = false, quiet = false }   -- (its title: none until it is first shown)
	-- the distance line: Travel.Line writes it here as on the marker's text
	-- (its `text`, as a font string keeps it)
	a.distance = { SetText = function(self, text) self.text = text end }
	function a:IsShown()
		return self.shown
	end
	function a:Show()
		if not self.shown then
			self.shown = true
			M.nav.Refresh()
			M.nav.Turning()
		end
	end
	function a:Hide()
		if self.shown then
			self.shown = false
			M.nav.Refresh()
			M.nav.Turning()
		end
	end
	arrow = a
	M.nav.Register()
end

--------------------------------------------------------------------------------
-- World marker (user, 2026-09-23: "go ahead with the route arrow"). The game
-- keeps a navigation frame over the super-tracked destination's real place on
-- the screen (C_Navigation.GetFrame; it slides to the screen's edge while the
-- place is beside or behind the camera). The marker hangs on it: the kit's
-- gem with the distance over the destination itself, and at the screen's edge
-- an arrow pointing the way to turn. The direction arrow above still follows
-- the road; this one shows where the road ends. The game's own destination
-- marker is only faded while ours shows -- never hidden, moved or written to.
--
-- Its states (user, 2026-09-28; the borders in Beacon, each with a buffer
-- between the way in and the way out, so it never flips on one):
--   beacon    far off: the gem with the red beam rising from it, the
--             distance and the travel time under it (Travel.Line). Faint
--             while it stands in the middle of the screen, where the
--             character is and the player looks.
--   pin       under 100 yards: the beam gone (faded out on the way in), the
--             gem lands on the place with its pop, never faint. It stays on
--             top of an NPC, an object or an item's source until it is done.
--   edge      off screen: the arrow on the ring round the character,
--             easing round it, pointing the way to turn.
--   hidden    inside a quest's objective AREA (the game's quest blob, where
--             the client can say so: Beacon.InArea) -- killing about a camp
--             needs no gem over one of its spots; back when the player
--             leaves. Never for one spot, nor on Route's own pin.
-- Per frame (only while it shows): the navigation frame's place and the
-- distance read, and nothing more while neither moved (the player and the
-- camera still) except the beam's rising streaks and the ring's easing.
--------------------------------------------------------------------------------

local marker = nil
-- Its states' borders (0.15.0; see the top), each with a buffer so the
-- marker never flips back and forth on one, and what it last saw of the
-- quest's area (Beacon.InArea); its functions below
local Beacon = {
	PIN_IN = 100,         -- yards: nearer than this the beacon turns into the pin
	PIN_OUT = 115,        -- ... and a beacon again only past this
	BEAM_FADE = 40,       -- yards past PIN_OUT over which the beam fades in (gone before the pin)
	EDGE_BACK = 0.10,     -- off screen: back over the place only this far inside every edge (EDGE_MARGIN out)
	FAINT_IN = 0.10,      -- the beacon this near the screen's middle (in screen heights) goes faint
	FAINT_OUT = 0.15,     -- ... and full again only past this
	FAINT_ALPHA = 0.35,
	FAINT_TIME = 0.25,    -- seconds its fade takes
	AREA_EVERY = 0.25,    -- seconds between asks whether the player is in the quest's area
	AREA_BUFFER = 10,     -- yards from where the player was last inside it before the marker comes back
	AREA_LEAVE = 3,       -- ... or seconds out of it
	-- the light at the beam's foot (pick D; the marker's build): the ring on
	-- the ground (its middle this far below the gem's), the glow behind the
	-- gem, and each one's strength (the beam's fade scales them)
	RING_W = 72, RING_H = 27, RING_DROP = -10,
	HALO_SIZE = 72,
	RING_ALPHA = 0.9, HALO_ALPHA = 0.6,
	FLAG = 15, FLAG_RING = 2,   -- the flag mark (0.19.5): the flag glyph, the gold ring's width round the dark disc
	-- the gem and the beam smaller the farther the place (user, 2026-10-04:
	-- "the waypoint marker and the Light beam change their size dynamically
	-- depending on the distance"): full size within SIZE_NEAR yards (the pin
	-- always), then (SIZE_NEAR / d) ^ SIZE_POWER, never under SIZE_MIN; the
	-- texts keep theirs. Set when it changes by more than SIZE_STEP
	SIZE_NEAR = 150, SIZE_POWER = 0.8, SIZE_MIN = 0.35, SIZE_STEP = 0.005,
	-- the ring round the character follows the camera's zoom (the same day:
	-- the arrow "behaves much more smoothly and dynamically when you are
	-- spinning around" in another marker): RING_X / RING_Y at RING_ZOOM yards,
	-- larger nearer, smaller farther, within RING_MIN to RING_MAX of that
	RING_ZOOM = 15, RING_MIN = 0.6, RING_MAX = 2,
	-- the near look (user, 2026-10-04: "Hover above, point down", pick A of
	-- MelloUI-BuildData/output/near_marker_sketch): within PIN_IN the gem rises
	-- HOVER above the place (gliding GLIDE seconds), the distance and the name
	-- over it, three gold chevrons under it (CHEV_Y below the gem's middle,
	-- CHEV_W x CHEV_H each) rippling down toward the place, the lowest one's tip
	-- about 40 above it -- clear of the NPC; back down to the beacon's foot the
	-- same way. The texts change sides fading (WORDS_FADE)
	HOVER = 79, GLIDE = 0.8, WORDS_FADE = 0.45,
	CHEV_Y = { 17, 25, 33 }, CHEV_W = 32, CHEV_H = 16,   -- (the V itself 16 x 7: Tools/make_route_beam.py)
	RIPPLE = 1.75, RIPPLE_TRAVEL = 7.5, RIPPLE_STAGGER = 0.25,
	-- Route's own pin set again for the same destination (a nearer spawn, the
	-- game's sunken point given up for Route's spot): the marker glides there
	-- on screen in MOVE_TIME seconds, never jumps (user, 2026-10-04: "Our
	-- navigation sometimes jumps around and skips the appearing animation")
	MOVE_TIME = 0.4,
	area = { quest = nil, inside = false, next = 0 },
}
local BEAM_ROOT = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Route\\"   -- look-ok: the beam, the painted look's only (Beacon.painted)
local BEAM_W, BEAM_H = 48, 420
local BEAM_SPAN = BEAM_H / (256 * BEAM_W / 64)   -- how many times the streak strip repeats up the beam
local EDGE_MARGIN = 0.07        -- the navigation frame this near a screen edge (share of the screen) = off screen
-- off screen, the arrow goes round the character on this ring (UI units from
-- the screen's centre, the character stands about there) instead of sitting
-- at the screen's edge (user, 2026-09-23: "its too far off the character")
local RING_X, RING_Y, RING_DY = 230, 170, -20
local gameMarkerFaded = false
local gameMarkerHooked = false

--------------------------------------------------------------------------------
-- Text Shade (user, 2026-09-25, for 0.13.7: the marker's texts and gem were
-- hard to read over bright ground, "and also the arrow"): the nameplates'
-- readability shade on the World Marker and the Direction Arrow.
--   Each text line (the distance with the travel time, the destination's
--   name): the shared soft band (MelloUI.Shade) anchored to the line, so it
--   hugs the text. While the shade is on, the name line is as wide as its
--   text (off: 180 wide as always, a longer name cut).
--   The marker's gem: its shadow partner (Kit:Shadow), a blurred dark copy
--   of the gem's own art made offline (Tools/make_kit_shadows.py, piece
--   deco/gem_large), anchored to the gem and grown by the blur; it follows
--   the gem's show, hide and alpha, and pops in with it.
--   The direction arrow and the marker's edge arrow: a round soft band. They
--   are the game's own atlas, which the builder cannot read (it reads the
--   kit's masters only), and they turn every frame: a copy of their shape
--   would have to turn with them, a round shade needs nothing.
-- Anchors only: the marker hangs on the game's navigation frame and moves
-- every frame, and nothing here is measured. Made at the arrow's and the
-- marker's first show with the option on, never at login; the option shows
-- or hides each piece (one SetShown each). The colour is the palette's
-- innerPanel, repainted on 'palette' by the band and the partner themselves.
-- One fixed strength, the notice's and the nameplates' default: the
-- nameplates' Shade Strength is their own setting, not a shared one.
-- (One table: this file's main chunk is near Lua's limit of 200 locals.)
--------------------------------------------------------------------------------

local TextShade = {
	ALPHA = 0.7,          -- its strength
	FEATHER = 20,         -- a text line's band: its soft ends (the nameplates' length)
	PAD_X = 4,            -- ... its full part past the text's ends
	PAD_Y = 4,            -- ... and above and below it
	LABEL_W = 180,        -- the name line's width with the shade off (as EnsureArrow and EnsureMarker make it)
	GEM = 26,             -- the marker's gem, drawn this wide (EnsureMarker)
	OPTS = {},            -- the options handed to Shade:Band and Kit:Shadow (read once, not kept)
}

-- the option: Tweaks' Text Shade (0.16.0: one with the zone text's and the
-- centre texts'), as saved; on unless switched off
function TextShade.On()
	if not MelloUI.Look:On() then
		return false   -- (the reskin off: the game's look, no band; its text shade comes back with the reskin)
	end
	local mods = MelloUI.db and MelloUI.db.modules
	local tweaks = type(mods) == "table" and mods.Tweaks
	return not (type(tweaks) == "table" and tweaks.textShade == false)
end

-- a soft band on `parent` behind `region`: `feather` long soft ends, its
-- full part `padX` past the region's ends (a negative one: inside them) and
-- `padY` above and below, at BACKGROUND `sublevel` (0; -8: under all else
-- its frame draws)
function TextShade.Band(parent, region, feather, padX, padY, sublevel)
	local o = TextShade.OPTS
	o.colour, o.alpha, o.feather, o.layer, o.sublevel = "innerPanel", TextShade.ALPHA, feather, "BACKGROUND", sublevel or 0
	o.region, o.padX, o.padY, o.scale = region, padX, padY, nil
	local band = MelloUI.Shade:Band(parent, o)   -- look-ok: TextShade.On: the painted look's only
	o.region = nil
	return band
end

-- a round soft shade behind a square icon `size` wide: the band's full
-- middle pulled in to 2 units at the icon's centre, its soft ends reaching
-- about as far out as its top and bottom fade
function TextShade.Round(parent, icon, size)
	return TextShade.Band(parent, icon, math.floor(size * 0.63 + 0.5), 1 - size / 2, 2, -8)
end

-- the pop the marker's gem comes up with (grown in from 1.6 times its size
-- as it fades in), and its partner with it
function TextShade.Pop(region)
	local pop = region:CreateAnimationGroup()
	local grow = pop:CreateAnimation("Scale")
	grow:SetScaleFrom(1.6, 1.6)
	grow:SetScaleTo(1, 1)
	grow:SetDuration(0.35)
	grow:SetSmoothing("OUT")
	local fade = pop:CreateAnimation("Alpha")
	fade:SetFromAlpha(0)
	fade:SetToAlpha(1)
	fade:SetDuration(0.2)
	pop:SetToFinalAlpha(true)
	return pop
end

-- The marker's (at its first show: UpdateMarker): a band behind its
-- distance line and its name line, the gem's shadow partner at the gem's
-- drawn scale (UI units per painted px), a round band behind the edge arrow.
-- With the option off nothing is made (made when it is switched on)
function TextShade.Marker()
	if marker.shade or not TextShade.On() then
		return
	end
	local Shade = MelloUI.Shade
	local front = marker.front
	if not (Shade and Shade.Band and front) then
		return
	end
	local s = {}
	-- (the lines' bands on the texts' frame: they fade with them, Beacon.Turn)
	local words = marker.words or front
	s.distance = TextShade.Band(words, marker.distance, TextShade.FEATHER, TextShade.PAD_X, TextShade.PAD_Y)
	s.label = TextShade.Band(words, marker.label, TextShade.FEATHER, TextShade.PAD_X, TextShade.PAD_Y)
	s.edge = TextShade.Round(front, marker.edge, 40)
	local Kit = MelloUI.Kit
	local gem = marker.gem
	local piece = Kit and Kit.Shadow and Kit.Piece and gem.kitName and Kit:Piece(gem.kitName)
	local w = piece and tonumber(piece.w)
	if w and w > 0 then
		local o = TextShade.OPTS
		o.colour, o.alpha, o.scale = "innerPanel", TextShade.ALPHA, TextShade.GEM / w
		s.gem = Kit:Shadow(gem, o)
		o.scale = nil
		if s.gem then
			s.pop = TextShade.Pop(s.gem)
		end
	end
	marker.shade = s
	TextShade.Sync(marker)
end

-- Each piece shown or hidden as the option and the frame say: on the
-- marker, the lines' bands and the gem's partner while it stands over the
-- destination, the edge arrow's while it is off screen (MarkerTick calls
-- this on a change only). The name line hugs its text while the shade is on.
function TextShade.Sync(f)
	local s = f and f.shade
	if not s then
		return
	end
	local on = TextShade.On()
	f.label:SetWidth(on and 0 or TextShade.LABEL_W)
	if f == marker then
		local over = on and not f.off
		s.distance:SetShown(over)
		s.label:SetShown(over)
		s.edge:SetShown(on and f.off or false)
		if s.gem then
			MelloUI.Kit:ShadowSet(f.gem, on)
		end
	else
		-- (the arrow turning while the roads go in has no lines: Build.ArrowWork)
		s.icon:SetShown(on)
		s.distance:SetShown(on and not f.spinning)
		s.label:SetShown(on and not f.spinning)
	end
end

-- The option changed (or a profile came in: OnEnable): what is made is
-- shown or hidden; what is not made yet is made at the next show with the
-- option on -- the arrow's at its next tick, the marker's at once while it
-- is up. Nothing is made at login (neither has been shown).
function TextShade.Apply()
	if marker then
		if marker.shade then
			TextShade.Sync(marker)
		elseif marker:IsShown() then
			TextShade.Marker()
		end
	end
end

-- Tweaks' Text Shade switched (0.16.0: the one switch lives there): the bus's
-- 'setting', taken at OnEnable (the same owner: once)
function TextShade.OnSetting(module, key)
	if module == "Tweaks" and key == "textShade" and M.isEnabled then
		TextShade.Apply()
	end
end

local function NavFrame()
	if C_Navigation and C_Navigation.GetFrame then
		local ok, f = pcall(C_Navigation.GetFrame)
		if ok and f then
			return f
		end
	end
	return nil
end

-- The game's own marker (SuperTrackedFrame) hidden while ours shows, shown
-- again after. (0.19.2: it was held at alpha 0 by a post-hook on SetAlpha,
-- which the game sets EVERY frame from its OnUpdate (UpdateAlpha): a
-- write undone on a per-frame path, against hard rule 1, and a player's
-- "attempt to call a nil value" in its UpdateAlpha, 1296 times a session.)
-- Hidden, its OnUpdate does not run at all; the game shows it only from its
-- events (InitializeNavigationFrame's SetShown), so a post-hook on Show and
-- SetShown hides it again then. The navigation frame our marker hangs on
-- (C_Navigation.GetFrame) is the engine's own and keeps its place.
local KeepGameMarkerHidden = Perf.Shared("Show / SetShown on the game's navigation marker", function(self)
	if gameMarkerFaded and self:IsShown() then
		self:Hide()
	end
end, "hook")

local function FadeGameMarker(on)
	local f = _G.SuperTrackedFrame
	if not (f and f.Hide) or gameMarkerFaded == on then
		return
	end
	gameMarkerFaded = on
	if not gameMarkerHooked then
		gameMarkerHooked = true
		hooksecurefunc(f, "Show", KeepGameMarkerHidden)
		hooksecurefunc(f, "SetShown", KeepGameMarkerHidden)
	end
	if on then
		f:Hide()
	else
		-- (back as the game had it: shown, its OnUpdate hides it again at once
		-- should it have no navigation frame -- InitializeNavigationFrame)
		f:Show()
	end
end

-- Off screen: the navigation frame (its centre x, y, read by the caller)
-- sits within EDGE_MARGIN of an edge; once off, it is back on only when
-- Beacon.EDGE_BACK inside every edge (`wasOff`: the buffer, so a place at
-- the border does not flip the gem and the edge arrow each frame). Also
-- returns its place as a share of the screen, centre 0.5 / 0.5, and how far
-- it is from the centre in screen heights, squared (a wide screen does not
-- skew it).
local function ScreenPlace(nav, x, y, wasOff)
	if not (x and y) then
		return nil
	end
	local scale = nav:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	if not (w and h and w > 0 and h > 0) then
		return nil
	end
	local fx, fy = x * scale / w, y * scale / h
	if not (fx > -math.huge and fx < math.huge and fy > -math.huge and fy < math.huge) then
		return nil   -- (NaN or endless: no place; the marker waits for a real one)
	end
	local m = wasOff and Beacon.EDGE_BACK or EDGE_MARGIN
	local off = fx < m or fx > 1 - m or fy < m or fy > 1 - m
	local dx, dy = (fx - 0.5) * w / h, fy - 0.5
	return off, fx, fy, dx * dx + dy * dy
end

-- The navigation frame follows whatever the game super-tracks; the marker
-- hangs on it only while that is our destination: the map pin for a pin, the
-- same quest for a quest. With nothing super-tracked the frame is left where
-- it last was (the arrow froze there, user 2026-09-23).
local function NavIsOurs()
	if not destination then
		return false
	end
	if crossContinent and not standIn then
		return false   -- nothing on this continent for the game to show: it sat in the screen's middle
	end
	if not C_SuperTrack then
		return true
	end
	-- (0.18.4) Route's own pin due for it but not up there yet: wait for it
	if StandIn.Pending and StandIn.Pending(destination) then
		return false
	end
	local quest, pin = SuperTrackState()
	if standIn then
		return pin ~= false
	end
	if destination.fromQuest then
		return quest ~= nil and quest == destination.questID
	end
	return pin ~= false
end

local UpdateMarker   -- below: the tick hides the marker through it

-- How far the place is, as the game measures it (C_Navigation.GetDistance),
-- or nil when it cannot say
function Beacon.Distance()
	if C_Navigation and C_Navigation.GetDistance then
		local ok, d = pcall(C_Navigation.GetDistance)
		return ok and Plain(d) or nil
	end
	return nil
end

-- /route pin (user, 2026-10-04: "Navigation pin looks like its under the
-- ground", with a video: from about 60 yards in, the pin sat on the character
-- while the distance went down to 7 yd): where the game has the marker's
-- place. While a quest is followed the marker hangs on the game's own
-- navigation to that quest (NavIsOurs), so the place and its height are the
-- game's quest marker's, not Route's spot. The game's distance against the
-- flat one on the map says how far above or below it lies, if the game
-- measures in three dimensions.
function M.PinReport()
	local quest, pin = SuperTrackState()
	MelloUI:Print("World Marker: the game tracks %s; the marker hangs on it: %s",
		quest and ("quest " .. quest) or pin and "the map pin" or "nothing", tostring(NavIsOurs()))
	local d = Beacon.Distance()
	local pcont, px, py = PlayerYards()
	local function Flat(label, mapID, x, y, z)
		local cont, yx, yy
		if mapID and x and y then
			cont, yx, yy = ToYards(mapID, x, y)
		end
		if not cont then
			print(string.format("   %s: %s", label, mapID and "a place Route cannot measure" or "none"))
			return
		end
		local flat = cont == pcont and px and Dist(px, py, yx, yy) or nil
		local line = string.format("   %s: map %d at %.3f, %.3f%s; flat on the map: %s", label, mapID, x, y,
			z and string.format(", height %.1f", z) or "", flat and string.format("%.1f yd", flat) or "another continent")
		if flat and d and d > flat + 1 then
			line = line .. string.format("  -> the game's point about %.0f yd above or below", math.sqrt(d * d - flat * flat))
		end
		print(line)
	end
	print("   the game's distance (C_Navigation.GetDistance): " .. (d and string.format("%.1f yd", d) or "none"))
	if pin and C_Map.GetUserWaypoint then
		local ok, point = pcall(C_Map.GetUserWaypoint)
		if ok and type(point) == "table" and type(point.position) == "table" then
			Flat("the map pin", Plain(point.uiMapID), Plain(point.position.x), Plain(point.position.y), Plain(point.z))
		end
	end
	if quest then
		Flat("the game's quest marker", QuestObjectivePoint(quest))
		if C_QuestLog and C_QuestLog.GetNextWaypoint then
			local ok, mapID, x, y = pcall(C_QuestLog.GetNextWaypoint, quest)
			Flat("the quest's next waypoint", ok and Plain(mapID) or nil, ok and Plain(x) or nil, ok and Plain(y) or nil)
		end
	end
	if destination then
		local flat = pcont == destination.cont and px and Dist(px, py, destination.x, destination.y) or nil
		print(string.format("   Route's spot (%s): flat %s", tostring(destination.label),
			flat and string.format("%.1f yd", flat) or "another continent"))
	end
	if UnitPosition then
		-- (2026-10-04, the user's report: this client always answers height 0)
		local ok, wy, wx, wz, inst = pcall(UnitPosition, "player")
		wz = ok and Plain(wz) or nil
		print(string.format("   you: world %s, %s, %s (instance %s)", tostring(ok and Plain(wx)), tostring(ok and Plain(wy)),
			(wz == nil or wz == 0) and "no height (the client gives none)" or string.format("height %.1f", wz),
			tostring(ok and Plain(inst))))
	end
	local nav = NavFrame()
	if nav then
		local okC, x, y = pcall(nav.GetCenter, nav)
		local off, fx, fy = ScreenPlace(nav, okC and Plain(x) or nil, okC and Plain(y) or nil)
		local okS, state = pcall(C_Navigation.GetTargetState)
		local okW, clamped = pcall(C_Navigation.WasClampedToScreen)
		print(string.format("   the navigation frame: %s of the screen across, %s up%s; target state %s, clamped %s",
			fx and string.format("%.2f", fx) or "?", fy and string.format("%.2f", fy) or "?", off and " (off screen)" or "",
			tostring(okS and Plain(state)), tostring(okW and Plain(clamped))))
	end
	if marker then
		print(string.format("   the marker: %s%s", marker:IsShown() and "shown" or "hidden",
			marker:IsShown() and (marker.off and ", at the edge" or marker.pin and ", the pin" or ", the beacon") or ""))
	end
end

-- The gem's and the beam's size at `d` yards (see Beacon's SIZE_*): 1 near or
-- unknown, smaller farther
function Beacon.Size(d)
	if not d or d <= Beacon.SIZE_NEAR then
		return 1
	end
	local s = (Beacon.SIZE_NEAR / d) ^ Beacon.SIZE_POWER
	return s < Beacon.SIZE_MIN and Beacon.SIZE_MIN or s
end

-- The marker's gem (its frame: the gem, its shadow partner, the game's icon)
-- and its beam at that size; the pin always full size. Set on a change only
function Beacon.Resize(f, d, pin)
	local s = pin and 1 or Beacon.Size(d)
	if f.size and math.abs(s - f.size) <= Beacon.SIZE_STEP then
		return
	end
	f.size = s
	if f.core then
		f.core:SetScale(s)
	end
	if f.beam then
		f.beam:SetScale(s)
	end
end

-- How much larger or smaller the ring round the character is at the camera's
-- zoom now (see Beacon's RING_*)
function Beacon.RingScale()
	local zoom = GetCameraZoom and GetCameraZoom()
	zoom = Plain(zoom)
	if type(zoom) ~= "number" or zoom <= 0 then
		return 1
	end
	local k = Beacon.RING_ZOOM / zoom
	return k < Beacon.RING_MIN and Beacon.RING_MIN or k > Beacon.RING_MAX and Beacon.RING_MAX or k
end

-- The marker's texts beside the gem: under it far away (the beacon: below the
-- ring on the ground, clear of the beam's light), over it near the place (the
-- distance on top, the name under it, then the gem: the near look's pick A)
function Beacon.LayWords(f, near)
	local gem, distance, label = f.gem, f.distance, f.label
	distance:ClearAllPoints()
	label:ClearAllPoints()
	if near then
		label:SetPoint("BOTTOM", gem, "TOP", 0, 6)
		distance:SetPoint("BOTTOM", label, "TOP", 0, 1)
	else
		distance:SetPoint("TOP", gem, "BOTTOM", 0, -8)
		label:SetPoint("TOP", distance, "BOTTOM", 0, -1)
	end
	f.wordsNear = near
end

-- The chevrons under the gem near the place, made the first time it is near:
-- three small frames on the gem's frame, each the chevron (the palette's gold,
-- Travel.Paint) over its soft dark edge (innerPanel); Anim:Ripple moves and
-- fades them, each from half its fall above where it rests
function Beacon.Chevrons(f)
	if f.chev then
		return f.chev
	end
	local list = {}
	for i, y in ipairs(Beacon.CHEV_Y) do
		local c = CreateFrame("Frame", nil, f.core)
		c:SetSize(Beacon.CHEV_W, Beacon.CHEV_H)
		c:SetPoint("CENTER", f.core, "CENTER", 0, Beacon.RIPPLE_TRAVEL / 2 - y)
		local edge = c:CreateTexture(nil, "ARTWORK", nil, 0)
		edge:SetAllPoints()
		edge:SetTexture(BEAM_ROOT .. "chevron_shade")
		local W = MelloUI.Widgets
		if W and W.Paint then
			W.Paint(edge, "innerPanel", "vertex", 0.75)
		end
		local gold = c:CreateTexture(nil, "ARTWORK", nil, 1)
		gold:SetAllPoints()
		gold:SetTexture(BEAM_ROOT .. "chevron")
		c.gold = gold
		c:Hide()
		list[i] = c
	end
	f.chev = list
	Travel.Paint()
	return list
end

-- Route's own pin set again for the same destination (StandIn calls it): the
-- marker glides from where it stands now to the new place (MarkerTick), from
-- its own middle on the screen. Under Reduce Motion, or unseen, it jumps
StandIn.Moved = function()
	local f = marker
	local anim = MelloUI.Anim
	if not (f and f:IsShown() and not f.off and f.nav) or (anim and anim.reduceMotion) then
		return
	end
	local okC, cx, cy = pcall(f.GetCenter, f)
	cx, cy = okC and Plain(cx) or nil, okC and Plain(cy) or nil
	if not (cx and cy) then
		return
	end
	local scale = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	f.glideX, f.glideY, f.glideAt = cx * scale, cy * scale, GetTime()
end

-- The marker's sound as it changes (Marker Sounds): the user's own. True
-- when it played
function Beacon.Sound()
	if M.db.markerSound ~= false then
		MelloUI:PlayUISound("marker")
		return true
	end
	return false
end

-- One sound for a new destination (0.19.4, the options audit: the tracking
-- notice's chime and the marker's sound played together). The marker's own
-- sound plays (Marker Sounds, the user's pick for its changes), and the
-- "Tracking ..." line goes without its chime when the marker sounds for
-- that destination: it came up for it and sounded, or it is not up for it
-- yet and comes up as soon as the game's frame follows it (Route's own pin
-- going up first). Otherwise the line chimes -- the World Marker or Marker
-- Sounds off, the player inside the quest's area, no marker on this
-- continent, the login's quiet seconds, the next spot of the same quest
-- (the marker stays quiet for it) -- and a marker coming up for that
-- destination within CHIME_SPAN seconds of the chime stays quiet. What was
-- said last: Beacon.saidKey (the destination as the marker knows it: its
-- quest, else itself), saidAt, saidChime (the chime played), saidMarker
-- (the sound left to the marker); Beacon.soundFor, the destination the
-- marker last sounded for. Nothing is made: a few fields set per line
Beacon.QUIET = 10         -- seconds after the login the marker comes up without its sound (a /reload's destination)
Beacon.CHIME_SPAN = 2     -- seconds after a line's chime a marker coming up for that destination stays quiet

-- the login's quiet seconds (Travel.loginAt, EnsureMarker)
function Beacon.Quiet()
	return Travel.loginAt ~= nil and GetTime() - Travel.loginAt < Beacon.QUIET
end

-- whether the marker's sound stands for destination d's line, said now
function Beacon.Takes(d)
	if not (d and marker and M.isEnabled and M.db.worldMarker and M.db.markerSound ~= false) then
		return false
	end
	local key = d.questID or d
	if marker.soundKey == key then
		-- up for it: it sounded for it, and this is the first line since
		return Beacon.soundFor == key and Beacon.saidKey ~= key
	end
	-- not up for it yet: it comes up with its sound, unless it stays away
	return not (Beacon.Quiet() or not NavFrame() or (crossContinent and not standIn) or (d.area and Beacon.InArea()))
end

-- (Route's Announce, above the marker: through M) whether the "Tracking
-- ..." line for destination d goes without its chime; notes what was said
function M.TrackMute(d)
	local mute = Beacon.Takes(d)
	Beacon.saidKey = d and (d.questID or d) or nil
	Beacon.saidAt = GetTime()
	Beacon.saidMarker = mute
	Beacon.saidChime = not mute and MelloUI.AnnounceSounds ~= nil and MelloUI:AnnounceSounds("track") or false
	return mute
end

-- (M:AnnounceSounds) whether the marker's sound stands for the destination
-- set now: its line left the sound to the marker, or, its line still to
-- come (the roads still going in), the marker sounded for it
function M.MarkerSounds()
	local d = destination
	if not (d and M.db and M.db.markerSound ~= false) then
		return false
	end
	local key = d.questID or d
	if Beacon.saidKey == key then
		return Beacon.saidMarker == true
	end
	return Beacon.soundFor == key
end

-- Near the place, or far from it again: the gem glides up over the place (or
-- back down to the beacon's foot), the texts change sides fading out and in,
-- the chevrons ripple under the gem while near (under Reduce Motion all of it
-- at once and still). `from`: the gem's height to start from (the marker
-- coming up near: from the place)
function Beacon.Turn(f, near, from)
	local anim = MelloUI.Anim
	local core, words = f.core, f.words
	local to = near and Beacon.HOVER or 0
	if from then
		core:ClearAllPoints()
		core:SetPoint("CENTER", f, "CENTER", 0, from)
		f.coreY = from
	end
	-- (a glide only when the gem's height changes: none from 0 to 0 when it
	-- comes up far away)
	if (f.coreY or 0) ~= to then
		if anim and anim.To then
			anim:To(core, "y", to, Beacon.GLIDE, "inOutQuad")
		else
			core:ClearAllPoints()
			core:SetPoint("CENTER", f, "CENTER", 0, to)
		end
		f.coreY = to
	end
	if f.wordsNear ~= near then
		Beacon.LayWords(f, near)
		-- (off screen the texts are hidden and the edge arrow on their frame
		-- shows: they change sides at once)
		if anim and anim.To and not f.off then
			words:SetAlpha(0)
			anim:To(words, "alpha", 1, Beacon.WORDS_FADE, "outQuad")
		end
	end
	if near then
		local chev = Beacon.Chevrons(f)
		for _, c in ipairs(chev) do
			c:SetShown(not f.off)
		end
		if anim and anim.Ripple then
			anim:Ripple(chev, Beacon.RIPPLE, Beacon.RIPPLE_TRAVEL, Beacon.RIPPLE_STAGGER)
		end
	elseif f.chev then
		if anim and anim.StopRipple then
			anim:StopRipple(f.chev)
		end
		for _, c in ipairs(f.chev) do
			c:Hide()
		end
	end
end

-- The beam at `d` yards: faded in over BEAM_FADE yards past PIN_OUT, so it
-- is gone before the pin and comes back softly (set on a change only)
function Beacon.BeamFade(beam, d)
	local fade = (d - Beacon.PIN_OUT) / Beacon.BEAM_FADE
	fade = fade < 0 and 0 or fade > 1 and 1 or fade
	if fade ~= beam.fade then
		beam.fade = fade
		beam.glow:SetAlpha(0.85 * fade)
		beam.streaks:SetAlpha(0.7 * fade)
		if beam.ring then
			Beacon.FootFade(beam)
		end
	end
end

-- The light at the beam's foot (user, 2026-09-30: "the icon stops the beam
-- and the icon itself is not red highlighted like the beam"; pick D of
-- BuildData/output/route_marks_sketch): a ring of light on the ground round
-- the foot and a soft glow behind the gem, added as the beam is, and the gem
-- lit by it (its art again, added over it, in a frame of the beam's above
-- the gem's; none when the kit's gem is not there), in Route's red
-- (MelloUI.Meaning.routeBeam). The beam's own: shown, faded and flared with
-- it. Made the first time the beam shows (not at login with the marker)
function Beacon.FootFade(beam)
	local fade = beam.fade or 1
	beam.ring:SetAlpha(Beacon.RING_ALPHA * fade)
	beam.halo:SetAlpha(Beacon.HALO_ALPHA * fade)
end

-- The game's own player arrow (its high-resolution direction arrows, the
-- oldest fallback last): the direction arrow's and the marker's edge arrow
function Travel.PlayerArrow(tex)
	for _, atlas in ipairs({ "ui-hud-minimap-arrow-player-2x", "ui-hud-minimap-arrow-player" }) do
		if pcall(tex.SetAtlas, tex, atlas) and tex:GetAtlas() then
			return
		end
	end
	tex:SetTexture("Interface/Minimap/MinimapArrow")
end

-- The marker's gem and edge arrow in the look (docs/plans/game-look.md wave
-- 3, the user's pick: the game's art): the kit's gem and the player arrow
-- painted; with the reskin off the game's own navigation art, as its
-- super-tracked frame draws it (Navigation-Tracked-Icon at its size, its
-- edge arrow) -- the beam, its light and the text shade off
-- (the game's icon on a texture of its own, marker.gameGem, as the game's
-- SuperTrackedFrame draws it on its Icon: the user's screenshot 2026-10-02,
-- the icon set on the kit's gem texture showed a solid gold block -- what
-- the kit's piece left on it was not all undone by SetAtlas. The gem stays
-- the marker's anchor, empty, at the icon's size: the texts stand under it)
function Beacon.Art()
	if not (marker and marker.gem) then
		return
	end
	local gem, edge, game = marker.gem, marker.edge, marker.gameGem
	if Beacon.painted ~= false then
		gem:SetSize(TextShade.GEM, TextShade.GEM)
		Beacon.FlagMark()
		if game then
			game:Hide()
		end
		if edge then
			edge:SetSize(40, 40)
			Travel.PlayerArrow(edge)
		end
		return
	end
	gem.kitPiece, gem.kitName = nil, nil   -- (no kit piece now: the kit's shadow partner lets it go)
	gem:SetTexture(nil)
	Beacon.FollowGem()   -- (the flag mark's disc and flag go with the painted look)
	if not game then
		-- (made the first time the game's look needs it, set once)
		game = gem:GetParent():CreateTexture(nil, "ARTWORK")
		game:SetPoint("CENTER", gem, "CENTER")
		game:SetAtlas((select(2, MelloUI.Look.Art("navIcon"))), true)
		marker.gameGem = game
	end
	if game then
		gem:SetSize(game:GetSize())
		game:SetShown(gem:IsShown())
	end
	if edge then
		edge:SetAtlas((select(2, MelloUI.Look.Art("navArrow"))), true, nil, true)   -- (resetTexCoords: no crop kept)
	end
end

-- The marker's mark (0.19.5, the user's pick B of BuildData/output/
-- world_marker_flag_sketch): the maps' goal mark -- the flag on the palette's
-- dark disc in its gold ring -- in the kit gem's place. The gem texture is the
-- ring; the disc and the flag stand on it, on the gem's frame (core: sized by
-- the distance with it), made once, shown and hidden with the gem (post-hooks
-- on MelloUI's own texture) and popping in with it. The flag red with Red
-- Beads, the palette's text else (M.GoalFlag); the beam's light follows the
-- same look (Beacon.Tint).
function Beacon.FlagMark()
	local gem, W = marker.gem, MelloUI.Widgets
	gem.kitPiece, gem.kitName = nil, nil   -- (no kit piece: no shadow partner; the disc is its own dark ground)
	gem:SetTexture(M.TRAIL.ROUND)
	gem:SetTexCoord(0, 1, 0, 1)
	if W then
		W.Paint(gem, "selectedTrim", "vertex", 1)
	end
	if not marker.goalDisc then
		local core = marker.core
		local disc = core:CreateTexture(nil, "ARTWORK", nil, 2)
		disc:SetTexture(M.TRAIL.ROUND)
		disc:SetPoint("TOPLEFT", gem, "TOPLEFT", Beacon.FLAG_RING, -Beacon.FLAG_RING)
		disc:SetPoint("BOTTOMRIGHT", gem, "BOTTOMRIGHT", -Beacon.FLAG_RING, Beacon.FLAG_RING)
		local flag = core:CreateTexture(nil, "ARTWORK", nil, 3)
		flag:SetSize(Beacon.FLAG, Beacon.FLAG)
		flag:SetPoint("CENTER", gem, "CENTER")
		if W then
			W.Paint(disc, "innerPanel", "vertex", 0.95)
			W.Glyph(flag, "flag")
		end
		marker.goalDisc, marker.goalFlag = disc, flag
		marker.goalPops = { TextShade.Pop(disc), TextShade.Pop(flag) }
		hooksecurefunc(gem, "Show", Beacon.FollowGem)
		hooksecurefunc(gem, "Hide", Beacon.FollowGem)
		hooksecurefunc(gem, "SetShown", Beacon.FollowGem)
	end
	M.GoalFlag(marker.goalFlag)
	Beacon.FollowGem()
end
function Beacon.FollowGem()
	local disc, flag = marker and marker.goalDisc, marker and marker.goalFlag
	if disc then
		local shown = Beacon.painted ~= false and marker.gem:IsShown() and true or false
		disc:SetShown(shown)
		flag:SetShown(shown)
	end
end

-- The beam's light (its glow, its streaks, the ring at its foot and the glow
-- behind the mark) in the trail's look: Route's red (MelloUI.Meaning.
-- routeBeam) with Red Beads, the palette's gold (selectedTrim) with the line
-- and the dashes (0.19.5, pick B); written only on a change; again at a new
-- palette (Travel.Paint) and a new Trail Look
function Beacon.Tint()
	local beam = marker and marker.beam
	if not beam then
		return
	end
	local c = M.TrailLook() == "beads" and MelloUI.Meaning.routeBeam or MelloUI.Look.Palette().selectedTrim
	if beam.tint == c then
		return
	end
	beam.tint = c
	beam.glow:SetVertexColor(c[1], c[2], c[3])
	beam.streaks:SetVertexColor(math.min(1, c[1]), math.min(1, c[2] + 0.1), math.min(1, c[3] + 0.05))
	if beam.ring then
		beam.ring:SetVertexColor(c[1], c[2], c[3])
		beam.halo:SetVertexColor(c[1], c[2], c[3])
	end
	if marker.goalFlag then
		M.GoalFlag(marker.goalFlag)
	end
end

-- The reskin switched (MelloUI.Look; now, and at each switch): the marks in
-- their look -- the gold, the gem and the edge arrow, the beam (none in the
-- game's look) and the text shade
function Beacon.OnLook(_, painted)
	Beacon.painted = painted and true or false
	Beacon.Art()
	Travel.Paint()
	TextShade.Apply()
	if marker then
		marker.lastX = nil   -- (its next tick lays it again: the beam back in the painted look)
		if not painted and marker.beam then
			marker.beam:Hide()
		end
	end
end

function Beacon.Foot(beam)
	if beam.ring then
		return
	end
	local ring = beam:CreateTexture(nil, "BACKGROUND")
	ring:SetSize(Beacon.RING_W, Beacon.RING_H)
	ring:SetPoint("CENTER", marker, "CENTER", 0, Beacon.RING_DROP)
	ring:SetTexture(BEAM_ROOT .. "beam_ring")
	local halo = beam:CreateTexture(nil, "BACKGROUND", nil, 1)
	halo:SetSize(Beacon.HALO_SIZE, Beacon.HALO_SIZE)
	halo:SetPoint("CENTER", marker, "CENTER")
	halo:SetTexture(BEAM_ROOT .. "beam_halo")
	-- (0.19.5: the kit's gem lit by the beam went with the gem: the flag
	-- mark stands there on its own dark disc)
	local red = MelloUI.Meaning.routeBeam
	for _, t in ipairs({ ring, halo }) do
		t:SetBlendMode("ADD")
		t:SetVertexColor(red[1], red[2], red[3])
	end
	beam.ring, beam.halo = ring, halo
	beam.tint = nil   -- (Beacon.Tint again: the ring and the glow in the look's light)
	Beacon.Tint()
	Beacon.FootFade(beam)
end

-- The beacon faint, or full again: the whole marker, eased (at once under
-- Reduce Motion)
function Beacon.Fade(f, faint)
	local a = faint and Beacon.FAINT_ALPHA or 1
	local anim = MelloUI.Anim
	if anim and anim.To then
		anim:To(f, "alpha", a, Beacon.FAINT_TIME, "outQuad")
	else
		f:SetAlpha(a)
	end
end

-- One of the marker's AnimationGroups played (the pops, the flare): through
-- Anim, which ends it at once under Reduce Motion (audit, 2026-09-24)
function Beacon.Play(group)
	if not group then
		return
	end
	local anim = MelloUI.Anim
	if anim then
		anim:PlayGroup(group)
	else
		group:Play()
	end
end

-- Whether the marker hides for the quest's objective area (see the top):
-- only for what the data calls an area (destination.area: ObjectiveSpot;
-- the game's own point with no data is taken for a spot, ReadTrackedQuest) it
-- hangs on the game's own tracking of the quest, or on Route's own pin on the
-- quest's place (2026-10-04, StandIn: s.spot), and only where the client can
-- say (C_Minimap.IsInsideQuestBlob); never on Route's other pins. Asked
-- every AREA_EVERY seconds at most (from UpdateMarker: the minimap's tick,
-- which runs while there is a destination). In at once; out again only
-- AREA_BUFFER yards from where the player was last seen inside, or after
-- AREA_LEAVE seconds out of it: walking along the border does not flicker
-- it. Kept while the quest is the same (the next spawn of the same area)
-- and it is asked about; not asked for a second (another destination
-- meanwhile, nothing routed), it starts afresh.
function Beacon.InArea()
	local a, d = Beacon.area, destination
	local blob = _G.C_Minimap
	local ask = blob and blob.IsInsideQuestBlob
	if not (ask and d and d.fromQuest and d.area and d.questID) or (standIn and not standIn.spot) then
		a.quest, a.inside = nil, false
		return false
	end
	local now = GetTime()
	if a.quest ~= d.questID or now > a.next + 1 then
		a.quest, a.inside, a.next = d.questID, false, 0
	end
	if now < a.next then
		return a.inside
	end
	a.next = now + Beacon.AREA_EVERY
	local ok, inside = pcall(ask, d.questID)
	inside = ok and Plain(inside) and true or false
	local cont, px, py = PlayerYards(true)
	if inside then
		a.inside, a.since = true, nil
		a.cont, a.x, a.y = cont, px, py
	elseif a.inside then
		a.since = a.since or now
		-- (a place not known now, or not when inside: the time alone)
		local moved = cont ~= nil and a.cont ~= nil and (cont ~= a.cont or Dist(a.x, a.y, px, py) >= Beacon.AREA_BUFFER)
		if moved or now - a.since >= Beacon.AREA_LEAVE then
			a.inside = false
		end
	end
	return a.inside
end

local function MarkerTick(self, elapsed)
	-- every frame (2026-10-04: at most 60 a second made it judder on a faster
	-- screen -- the user's 90 fps video: every other frame or so, unevenly);
	-- a still frame stops at the check below
	local dt = elapsed
	-- the destination cleared (a map pin removed, a quest untracked) or its
	-- navigation frame gone: away at once, whatever else still ticks
	-- (user, 2026-09-23: the arrow stayed round the character after clearing)
	local nav = self.nav
	if not (nav and destination and M.isEnabled and M.db.worldMarker) or NavFrame() ~= nav or not NavIsOurs() then
		UpdateMarker()
		return
	end
	local beam = self.beam
	-- the streaks rise: the strip scrolls up the beam, round and round (they
	-- stand still under Reduce Motion)
	if beam:IsShown() and not (MelloUI.Anim and MelloUI.Anim.reduceMotion) then
		beam.scroll = (beam.scroll + dt * 0.3) % 1
		beam.streaks:SetTexCoord(0, 1, beam.scroll, beam.scroll + BEAM_SPAN)
	end
	-- where the game has the place, and how far. Neither moved since the
	-- last tick (the player and the camera still), the edge arrow eased
	-- round, the gem on this navigation frame and the travel time as its
	-- line says: nothing more to do
	local okC, x, y = pcall(nav.GetCenter, nav)
	x, y = okC and Plain(x) or nil, okC and Plain(y) or nil
	local d = Beacon.Distance()
	if x == self.lastX and y == self.lastY and d == self.lastD and not self.easing and not self.glideAt
		and (self.off or self.anchoredTo == nav) and Travel.suffix == self.lineSuffix
		and not (self.off and Beacon.RingScale() ~= self.ringK) then
		return
	end
	self.lastX, self.lastY, self.lastD = x, y, d
	local off, fx, fy, centre = ScreenPlace(nav, x, y, self.off)
	if off == nil then
		return
	end
	-- the pin near the place, the beacon farther: PIN_IN on the way in,
	-- PIN_OUT on the way out (kept while the distance cannot be read)
	local pin = self.pin
	if d then
		if pin then
			pin = d < Beacon.PIN_OUT
		else
			pin = d < Beacon.PIN_IN
		end
	end
	pin = pin and true or false
	Beacon.Resize(self, d, pin)
	-- (0.18.4) its place moved under it (StandIn.Moved): from where it stood
	-- to the new place, eased, until MOVE_TIME is up; off screen it lets go
	if self.glideAt then
		local t = off and 1 or (GetTime() - self.glideAt) / Beacon.MOVE_TIME
		if t < 1 then
			local ease = MelloUI.Anim and MelloUI.Anim.easing and MelloUI.Anim.easing.inOutQuad
			local e = ease and ease(t) or t
			local scale = nav:GetEffectiveScale() / UIParent:GetEffectiveScale()
			local tx, ty = x * scale, y * scale
			self.mode, self.anchoredTo = "glide", nil
			self:ClearAllPoints()
			self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", self.glideX + (tx - self.glideX) * e, self.glideY + (ty - self.glideY) * e)
		else
			self.glideAt = nil
		end
	end
	-- on screen: over the destination (hung on the navigation frame); off
	-- screen: on the ring round the character, in the destination's direction
	if not off and not self.glideAt and (self.mode ~= "nav" or self.anchoredTo ~= nav) then
		self.mode, self.anchoredTo = "nav", nav
		self:ClearAllPoints()
		self:SetPoint("CENTER", nav, "CENTER")
	end
	-- the gem and the texts, or the edge arrow: set when that changes, not
	-- every tick (the gem's shadow partner follows its show and hide), with
	-- their text shade
	if off ~= self.off then
		self.off = off
		self.gem:SetShown(not off)
		if self.gameGem then
			self.gameGem:SetShown(not off and Beacon.painted == false)
		end
		self.distance:SetShown(not off)
		self.label:SetShown(not off)
		self.edge:SetShown(off)
		if self.chev then
			for _, c in ipairs(self.chev) do
				c:SetShown(not off and self.pin == true)
			end
		end
		TextShade.Sync(self)
	end
	-- the beam: the beacon's, never the pin's, hidden off screen, and hidden
	-- while faded out (PIN_IN to PIN_OUT on the way in: nothing to see, so its
	-- streaks do not scroll unseen)
	if d then
		Beacon.BeamFade(beam, d)
	end
	local lit = Beacon.painted ~= false and not off and not pin and M.db.routeBeam and beam.fade > 0 or false
	if lit ~= beam:IsShown() then
		if lit then
			Beacon.Foot(beam)
		end
		beam:SetShown(lit)
	end
	if d then
		-- the distance and the travel time, made only when either changes
		Travel.Line(self, math.floor(d + 0.5))
	end
	-- near the place or far from it again (0.18.4): the gem glides up over the
	-- place or back down to the beacon's foot, the texts change sides, the
	-- chevrons ripple near it; the marker's sound as it turns, on screen
	if pin ~= self.pin then
		self.pin = pin
		Beacon.Turn(self, pin)
		if not off then
			Beacon.Sound()
		end
	end
	-- faint: the beacon in the middle of the screen, never the pin or the
	-- edge arrow (FAINT_IN on the way in, FAINT_OUT on the way out; `centre`
	-- is squared)
	local r = self.faint and Beacon.FAINT_OUT or Beacon.FAINT_IN
	local faint = not off and not pin and centre < r * r
	if faint ~= self.faint then
		self.faint = faint
		Beacon.Fade(self, faint)
	end
	self.easing = false
	if off then
		-- the direction from the screen's centre to where the game puts the
		-- place (in screen units, so a wide screen does not skew it); the
		-- arrow slides round the ring the short way, eased so it does not jitter
		local want = math.atan2((fy - 0.5) * UIParent:GetHeight(), (fx - 0.5) * UIParent:GetWidth())
		if not (self.angle > -math.huge and self.angle < math.huge) then
			self.angle = want   -- (never stuck on a NaN: it would be set every tick after)
		end
		local diff = (want - self.angle + math.pi) % (2 * math.pi) - math.pi
		-- half the gap a frame at 60 fps: keeps up with a fast turn, still no jitter
		-- (user, 2026-09-23: "kinda slow response when turning"; was dt * 12)
		self.angle = self.angle + diff * math.min(1, dt * 30)
		-- (still easing: the next ticks go on even with nothing moving)
		self.easing = math.abs(diff) > 0.002
		self.mode, self.anchoredTo = "ring", nil
		-- (the ring's size at the camera's zoom: Beacon.RingScale)
		local k = Beacon.RingScale()
		self.ringK = k
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", math.cos(self.angle) * RING_X * k, (math.sin(self.angle) * RING_Y + RING_DY) * k)
		self.edge:SetRotation(self.angle - math.pi / 2)
	end
end

local function EnsureMarker()
	-- Route coming on in the login's pass (OnEnable): a destination seen in
	-- the moments after was there before the /reload (Travel.See)
	if MelloUI.initializingModules and not Travel.loginAt then
		Travel.loginAt = GetTime()
	end
	if marker then
		return
	end
	marker = CreateFrame("Frame", "MelloUIRouteMarker", (MelloUI.Fader and MelloUI.Fader:Host("route") or UIParent))
	marker:SetSize(44, 44)
	marker:SetFrameStrata("LOW")
	marker:SetClampedToScreen(true)
	marker:EnableMouse(false)
	-- the light beam (user, 2026-09-23: "can you build that beam, but make it
	-- red"): a glow column from its foot at the destination up into the sky,
	-- light streaks rising inside it (masked by the column's own shape), both
	-- added to what is behind them. Made by Tools/make_route_beam.py. Route's
	-- red for the world (MelloUI.Meaning.routeBeam), whatever the palette.
	local red = MelloUI.Meaning.routeBeam
	local beam = CreateFrame("Frame", nil, marker)
	beam:SetSize(BEAM_W, BEAM_H)
	beam:SetPoint("BOTTOM", marker, "CENTER", 0, -6)
	beam:SetFrameLevel(marker:GetFrameLevel() + 1)
	beam.glow = beam:CreateTexture(nil, "ARTWORK")
	beam.glow:SetAllPoints()
	beam.glow:SetTexture(BEAM_ROOT .. "beam_glow")
	beam.glow:SetBlendMode("ADD")
	beam.glow:SetVertexColor(red[1], red[2], red[3])
	beam.streaks = beam:CreateTexture(nil, "ARTWORK", nil, 1)
	beam.streaks:SetAllPoints()
	beam.streaks:SetTexture(BEAM_ROOT .. "beam_streaks", "CLAMP", "REPEAT")
	beam.streaks:SetBlendMode("ADD")
	beam.streaks:SetVertexColor(red[1], red[2] + 0.1, red[3] + 0.05)
	if beam.CreateMaskTexture and beam.streaks.AddMaskTexture then
		local shape = beam:CreateMaskTexture()
		shape:SetAllPoints()
		shape:SetTexture(BEAM_ROOT .. "beam_glow", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		beam.streaks:AddMaskTexture(shape)
	end
	beam.glow:SetAlpha(0.85)
	beam.streaks:SetAlpha(0.7)
	-- (the light at its foot: Beacon.Foot, at the beam's first show)
	beam.scroll, beam.fade = 0, 1
	-- the strip's first window, where the streaks stand under Reduce Motion
	beam.streaks:SetTexCoord(0, 1, 0, BEAM_SPAN)
	-- the flare when a destination is set: the column widens from a thread
	-- to its full width, fast at the end (easing in), as it fades up
	local flare = beam:CreateAnimationGroup()
	local widen = flare:CreateAnimation("Scale")
	widen:SetScaleFrom(0.05, 1)
	widen:SetScaleTo(1, 1)
	widen:SetOrigin("BOTTOM", 0, 0)
	widen:SetDuration(0.45)
	widen:SetSmoothing("IN")
	local rise = flare:CreateAnimation("Alpha")
	rise:SetFromAlpha(0)
	rise:SetToAlpha(1)
	rise:SetDuration(0.3)
	flare:SetToFinalAlpha(true)
	beam.flare = flare
	beam:Hide()
	marker.beam = beam
	-- the gem, the texts and the edge arrow in front of the beam
	local front = CreateFrame("Frame", nil, marker)
	front:SetAllPoints()
	front:SetFrameLevel(marker:GetFrameLevel() + 3)
	-- the gem on a frame of its own, sized with the beam by the distance
	-- (Beacon.Resize; its shadow partner and the game's icon are made on it
	-- too), the texts and the edge arrow on `front` at their own size
	local core = CreateFrame("Frame", nil, marker)
	core:SetSize(44, 44)
	core:SetPoint("CENTER")
	core:SetFrameLevel(marker:GetFrameLevel() + 3)
	marker.core = core
	marker.gem = core:CreateTexture(nil, "ARTWORK")
	marker.gem:SetSize(26, 26)
	marker.gem:SetPoint("CENTER")
	-- (its art: Beacon.Art, below -- the flag mark in the painted look)
	-- the texts (0.18.4): they change sides of the gem near the place
	-- (Beacon.LayWords), fading as one with their shade bands: `front` is
	-- their frame (`words`), the edge arrow on it too, shown only off screen,
	-- where they change sides at once (no frame more made at login)
	marker.words = front
	marker.distance = front:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	RouteFont.Style(marker.distance, "fontChat", _G.GameFontNormal)   -- a number
	marker.label = front:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	RouteFont.Style(marker.label, "fontText", _G.GameFontHighlightSmall)   -- the destination's name
	Beacon.LayWords(marker, false)
	marker.label:SetWidth(180)
	marker.label:SetWordWrap(false)
	marker.edge = front:CreateTexture(nil, "ARTWORK")
	marker.edge:SetSize(40, 40)
	marker.edge:SetPoint("CENTER")
	Travel.PlayerArrow(marker.edge)
	Beacon.Art()   -- (the flag mark; the reskin off: the game's own destination icon and edge arrow)
	Travel.Paint()   -- the distance and the edge arrow in the palette's gold
	Beacon.Tint()   -- the beam's light in the trail's look
	marker.edge:Hide()
	-- the texts' frame, where their shade goes at the first show (TextShade)
	marker.front = front
	-- a small pop when the marker comes up: the gem grows in and settles
	marker.pop = TextShade.Pop(marker.gem)
	marker.angle, marker.faint = math.pi / 2, false
	Perf.SetScript(marker, "OnUpdate", MarkerTick)
	marker:Hide()
end

-- Shown while there is a destination and the game has a navigation frame
-- for it; hung on that frame, which the client moves every frame. Hidden
-- inside the quest's objective area (Beacon.InArea), the game's own marker
-- still faded: nothing over the area at all until the player leaves it.
UpdateMarker = function()
	-- (every destination passes here the moment it is set, through Plan's
	-- Redraw: when its way began, for the arrival's travel time; Route
	-- switched off on the way is a pause, and the time is left out)
	local d = destination
	if d then
		Travel.See(d)
		if not M.isEnabled then
			d.untimed = true
		end
	end
	if not marker then
		return
	end
	local nav = M.isEnabled and M.db.worldMarker and destination and NavIsOurs() and NavFrame() or nil
	local inArea = nav and destination.area and Beacon.InArea() or false
	if inArea or not nav then
		if marker:IsShown() then
			marker:Hide()
			-- (full again for its next show: a faint beacon's fade let go)
			local anim = MelloUI.Anim
			if anim and anim.Stop then
				anim:Stop(marker, "alpha")
			end
			marker:SetAlpha(1)
			marker.faint = false
			-- (the chevrons' ripple stopped while unseen: the next show starts it)
			if marker.chev and MelloUI.Anim and MelloUI.Anim.StopRipple then
				MelloUI.Anim:StopRipple(marker.chev)
			end
		end
		marker.nav = nil
		FadeGameMarker(inArea)
		return
	end
	-- the tick places it: over the destination or on the ring round the character
	marker.nav = nav
	marker.label:SetText((standIn and standIn.label) or destination.label or "")
	-- a new destination (another quest, another place: not the next spot of
	-- the same quest) while it shows (0.18.4, the user's video: it jumped
	-- there): it comes up afresh there, its way in played as on its first show.
	-- Known by the quest, else by the destination itself (a new pin is a new
	-- one): nothing made each frame
	local key = destination.questID or destination
	if marker:IsShown() and key ~= marker.soundKey then
		marker:Hide()
		local anim = MelloUI.Anim
		if anim and anim.Stop then
			anim:Stop(marker, "alpha")
		end
		marker:SetAlpha(1)
		marker.faint = false
	end
	if not marker:IsShown() then
		marker.glideAt = nil   -- (a way in, not a glide)
		marker.lineSuffix = nil   -- its distance line made afresh (Travel.Line)
		-- a beacon or the pin as the place is far or near now, its beam as
		-- that says; its parts looked at again at the next tick (MarkerTick)
		local dist = Beacon.Distance()
		marker.pin = dist ~= nil and dist < Beacon.PIN_IN
		marker.lastX, marker.easing = nil, false
		local beam = marker.beam
		if dist then
			Beacon.BeamFade(beam, dist)
		end
		Beacon.Resize(marker, dist, marker.pin)   -- (its size for that distance from the start: no shrink on show)
		TextShade.Marker()   -- its text shade, made at its first show with the option on
		marker:Show()
		-- (0.18.4) the near look or the beacon's as the place is now: near, the
		-- gem rises from the place into its hover (the near look's way in)
		Beacon.Turn(marker, marker.pin, 0)
		-- the pop and the flare end at once under Reduce Motion (audit, 2026-09-24)
		if not marker.pin then
			Beacon.Play(marker.pop)
			if marker.goalPops and Beacon.painted ~= false then
				Beacon.Play(marker.goalPops[1])
				Beacon.Play(marker.goalPops[2])
			end
		end
		local lit = Beacon.painted ~= false and M.db.routeBeam and not marker.pin and beam.fade > 0 or false
		if lit then
			Beacon.Foot(beam)
		end
		beam:SetShown(lit)
		if lit then
			Beacon.Play(beam.flare)
		end
		-- the gem's shadow partner pops in with it (TextShade)
		if MelloUI.Anim and not marker.pin then
			Beacon.Play(marker.shade and marker.shade.pop)
		end
	end
	-- the marker's sound for a new destination (Marker Sounds; 0.18.4): a new
	-- quest or another place, not the next spot of the same quest, and not
	-- the destination a /reload brought back; nor (0.19.4: one sound) one
	-- whose line chimed just now (Beacon.Takes)
	if key ~= marker.soundKey then
		marker.soundKey = key
		local chimed = Beacon.saidKey == key and Beacon.saidChime and GetTime() - Beacon.saidAt < Beacon.CHIME_SPAN
		if not (Beacon.Quiet() or chimed) and Beacon.Sound() then
			Beacon.soundFor = key
		end
	end
	FadeGameMarker(true)
end

-- How the arrow follows the route: the player is projected onto the nearest
-- part of the path (from the part last passed onward, so a path that loops
-- back near itself does not pull the arrow back) and the arrow aims LOOKAHEAD
-- yards further along it. Cutting a corner or running beside the road bends
-- the arrow towards the path ahead instead of back to a missed point. Farther
-- than OFF_ROUTE yards from the path, a new route is planned within a second.
local LOOKAHEAD = 30
local OFF_ROUTE = 45           -- yards beside the path before it counts as left (was 20)
local ADVANCE_TOLERANCE = 15   -- yards: a later part of the path this much farther than the nearest still wins

local function Walkable(a, b, cont)
	return a[1] == cont and b[1] == cont and b[4] ~= "boat" and b[4] ~= "flight"
end

-- Projection of P onto the segment AB: parameter in [0, 1], distance, point.
local function Project(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local len2 = dx * dx + dy * dy
	local t = 0
	if len2 > 0 then
		t = ((px - ax) * dx + (py - ay) * dy) / len2
		if t < 0 then
			t = 0
		elseif t > 1 then
			t = 1
		end
	end
	local qx, qy = ax + dx * t, ay + dy * t
	return t, Dist(px, py, qx, qy), qx, qy
end

-- Where on the route the player is: the segment (between points i and i + 1),
-- the parameter along it, the distance to the path and the point on it.
local function PlaceOnRoute(cont, px, py)
	local points = route.points
	local from = math.max(1, (route.progress or 1) - 2)
	local best, bestT, bestD, bestX, bestY = nil, 0, math.huge, nil, nil
	for i = from, #points - 1 do
		local a, b = points[i], points[i + 1]
		if Walkable(a, b, cont) then
			local t, d, qx, qy = Project(px, py, a[2], a[3], b[2], b[3])
			if d < bestD then
				best, bestT, bestD, bestX, bestY = i, t, d, qx, qy
			end
		end
	end
	if best then
		-- eager: the LATEST part of the path nearly as close as the nearest
		-- one is where the player is (a corner cut, a loop passed) — the
		-- arrow never turns back to a part already passed
		for i = best + 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			if Walkable(a, b, cont) then
				local t, d, qx, qy = Project(px, py, a[2], a[3], b[2], b[3])
				if d <= bestD + ADVANCE_TOLERANCE then
					best, bestT, bestX, bestY = i, t, qx, qy
					bestD = math.min(bestD, d)
				end
			end
		end
	end
	if not best then
		-- a single point, or only boat and flight legs left: the nearest point
		for i = from, #points do
			local p = points[i]
			if p[1] == cont then
				local d = Dist(px, py, p[2], p[3])
				if d < bestD then
					best, bestT, bestD, bestX, bestY = i, 0, d, p[2], p[3]
				end
			end
		end
	end
	return best, bestT, bestD, bestX, bestY
end

-- The point LOOKAHEAD yards along the route from the player's place on it,
-- stopping at a dock or flight master (the walk ends there) and at the goal.
-- A straight guess aims at its end. Also returns the yards left to walk.
local function AimPoint(cont, i, qx, qy, offBy)
	local points = route.points
	local ax, ay = qx, qy
	local tx, ty = qx, qy
	-- farther from the path, farther ahead along it: the arrow points where
	-- the road is going rather than at the road's nearest point beside the
	-- player (running parallel to it no longer reads as "turn around")
	local left = math.min(90, math.max(LOOKAHEAD, (offBy or 0) * 1.5))
	for j = i + 1, #points do
		local b = points[j]
		if not Walkable(points[j - 1], b, cont) then
			break
		end
		if b[4] == "guess" then
			tx, ty = b[2], b[3]
			break
		end
		local seg = Dist(ax, ay, b[2], b[3])
		if seg >= left then
			local f = left / seg
			tx, ty = ax + (b[2] - ax) * f, ay + (b[3] - ay) * f
			break
		end
		tx, ty = b[2], b[3]
		left = left - seg
		ax, ay = b[2], b[3]
	end
	-- yards left to walk: from the player's place on the route to its end,
	-- boat and flight legs not counted (as the planned length does it)
	local remaining = 0
	for j = i + 1, #points do
		local a, b = points[j - 1], points[j]
		if a[1] == b[1] and b[4] ~= "boat" and b[4] ~= "flight" then
			if j == i + 1 then
				remaining = remaining + Dist(qx, qy, b[2], b[3])
			else
				remaining = remaining + Dist(a[2], a[3], b[2], b[3])
			end
		end
	end
	return tx, ty, remaining
end

-- The travel time (see "Travel time" above), once a second at most, from the
-- arrow's tick (the minimap's, which runs only while something is routed): a
-- speed measure, then the time from the player's place on the route.
-- `asked`: the arrow found that place already (i, qx, qy); else it is looked
-- up here, for the marker while the arrow is off.
function Travel.Update(cont, px, py, asked, i, qx, qy)
	local d = Travel.Follow()
	if not M.db.travelTime then
		if Travel.minutes then
			Travel.Show(nil, true)
		end
		if Travel.guess then
			Travel.guess, Travel.suffix = false, ""   -- (the guess's words are Travel Time's too)
		end
		return
	end
	-- each tick: one that finds the player where the last did spoils this
	-- second's speed measure (Travel.Sample)
	if px == Travel.tickX and py == Travel.tickY then
		Travel.still = true
	end
	Travel.tickX, Travel.tickY = px, py
	local now = GetTime()
	if now < Travel.nextAt then
		return
	end
	Travel.nextAt = now + Travel.EVERY
	local onTaxi = Travel.OnTaxi()
	Travel.Sample(now, cont, px, py, not onTaxi)
	local secs
	if d and route and not (onTaxi or offRoute) then
		if not asked then
			local _, off
			i, _, off, qx, qy = PlaceOnRoute(cont, px, py)
			if i and off > OFF_ROUTE then
				i = nil
			end
		end
		secs = Travel.Seconds(i, qx, qy)
	end
	Travel.Show(secs)
end

-- The time kept is for the destination now: a new one starts with none (no
-- other destination's time on the marker as it comes up), estimated at once
function Travel.Follow()
	local d = destination
	if Travel.dest ~= d then
		Travel.dest, Travel.nextAt = d, 0
		Travel.Show(nil, true)
	end
	return d
end

-- The arrow, its distance line, the marker's distance and edge arrow and the
-- distance under the minimap in the palette's gold (the nearest to the gold
-- they had), again whenever the palette changes
function Travel.Paint()
	-- (the reskin off, MelloUI.Look: the game's gold, the arrows in their own colours)
	local r, g, b = MelloUI.Look.RoleColour("gold")
	local ir, ig, ib = MelloUI.Look.RoleColour("picture")
	-- (each part only once it exists: a frame half made, by an error part way
	-- through its making, must not break every later repaint)
	if arrow and arrow.icon then
		arrow.icon:SetVertexColor(ir, ig, ib)   -- (the row's arrow: its lines are the column's)
	end
	if marker and marker.distance and marker.edge then
		marker.distance:SetTextColor(r, g, b)
		marker.edge:SetVertexColor(ir, ig, ib)
	end
	-- (the near look's chevrons, once made: the distance's gold)
	for _, c in ipairs(marker and marker.chev or {}) do
		c.gold:SetVertexColor(r, g, b)
	end
	if mm and mm.text then
		mm.text:SetTextColor(r, g, b)
	end
	local caption = M.flight.caption   -- the flight map's "fly to" line (M.flight)
	if caption then
		caption.text:SetTextColor(r, g, b)
	end
	Beacon.Tint()   -- (the beam's light: the palette's gold with the line and the dashes)
	if not Travel.painted then
		Travel.painted = true
		MelloUI:On("palette", Travel.Paint, "Route gold")
	end
end

local function UpdateArrow(cont, px, py)
	-- a flight's landing countdown has the arrow meanwhile (M.flight, from
	-- Route's half-second tick); the travel time notes the flight
	if M.flight.arrowOn then
		Travel.Update(cont, px, py)
		return true
	end
	if not (arrow and M.db.arrow and destination) then
		if arrow then
			arrow:Hide()
		end
		-- the arrow off: the marker's time, while the marker is up to show it
		if marker and marker:IsShown() then
			Travel.Update(cont, px, py)
		else
			Travel.Follow()
		end
		return false
	end
	local tx, ty, remaining, i, qx, qy
	NoteHeading(cont, px, py)
	if route then
		local _, d
		i, _, d, qx, qy = PlaceOnRoute(cont, px, py)
		if i then
			route.progress = i
			route.atX, route.atY = qx, qy   -- the player's place on the path: the painters draw from here
			local off = d > OFF_ROUTE
			if off and not offRoute then
				offRouteSince = GetTime()
			elseif not off then
				offRouteSince = nil
			end
			offRoute = off
			tx, ty, remaining = AimPoint(cont, i, qx, qy, d)
		end
	end
	Travel.Update(cont, px, py, true, i, qx, qy)
	if not tx and destination.cont == cont then
		tx, ty = destination.x, destination.y
	end
	if not tx then
		arrow.targetX, arrow.aimless = nil, true
		if Build.loading then
			-- (nothing to point at while the roads go in: its working look)
			Build.ArrowWork()
			return arrow:IsShown()
		end
		arrow:Hide()
		return false
	end
	arrow.aimless = nil
	-- the row's turning face turns towards this every frame (M.nav.Angle)
	arrow.targetCont, arrow.targetX, arrow.targetY = cont, tx, ty
	if not remaining or remaining <= 0 then
		remaining = Dist(px, py, destination.x, destination.y)
	end
	if route then
		route.left = remaining   -- (what the arrow says: Route:FollowedRemaining)
	end
	-- the distance and the travel time, made only when either changes
	Travel.Line(arrow, remaining)
	arrow.title = destination.label or ""
	arrow:Show()
	M.nav.Push()
	if Build.loading then
		Build.ArrowWork()   -- (a place to point at now: it stops turning)
	end
	return true
end

-- The arrow's working look while the roads go in (Build.loading, the first
-- route of a session: "Loading navigation..."): with no place to point at
-- yet (a tracked quest's places wait to be priced by route: no destination
-- until then) its row shows for it, the arrow going round and its title the
-- notice's line, the distance line hidden; under Reduce Motion, where it
-- cannot turn, the row is not shown for it (an arrow standing still with
-- nothing to point at would read as a way to go: review, 2026-09-28; the
-- notice's line tells the wait alone). With a place to point at, it points.
-- Asked as the load starts and ends, by UpdateArrow while it lasts and after
-- a setting. Not while the landing countdown has the arrow.
function Build.ArrowWork()
	local a = arrow
	if not a then
		return
	end
	local on = (Build.loading and M.isEnabled and M.db.arrow and not M.flight.arrowOn) and true or false
	-- (aimless: UpdateArrow found nothing to point at, another continent's
	-- place with no route yet)
	local spin = on and (not destination or a.aimless) or false
	if on ~= (a.working or false) then
		a.working = on
	end
	if spin ~= (a.spinning or false) then
		a.spinning, a.quiet = spin, spin
		if spin then
			a.title = Build.LOADING
		elseif not destination then
			a:Hide()   -- (the load over with nothing to route to)
		end
	end
	M.nav.Work()
	if spin then
		local anim = MelloUI.Anim
		if anim and not anim.reduceMotion then
			a:Show()
		else
			a:Hide()
		end
	end
	M.nav.Push()
end

-- The goal's mark on the minimap (0.19.5): at its place while it lies on
-- the map, else on the edge toward it with a gold chevron outside it;
-- hidden off this continent, without a goal or with the minimap's route
-- off. In the view the tick has just set (M.mmView).
function M.GoalOnMinimap(cont, round, R, RX, RY)
	local d, g = destination, M.goalMini
	if not (d and cont and d.cont == cont and M.isEnabled and M.db.minimap) then
		if g then
			g:Hide()
			M.goalChev.on = false
			M.goalChev:Hide()
		end
		return
	end
	if not g then
		g = M.GoalMark(mm)
		g:SetFrameLevel(mm:GetFrameLevel() + 5)
		M.goalMini = g
		local chev = mm:CreateTexture(nil, "OVERLAY", nil, 4)
		chev:SetTexture(M.TRAIL.CHEVRON)
		chev:SetSize(20, 10)
		chev:Hide()   -- (shown when a goal lies beyond the map: a new texture shows at once)
		chev.on = false
		if MelloUI.Widgets then
			MelloUI.Widgets.Paint(chev, "selectedTrim", "vertex", 1)
		end
		M.goalChev = chev
	end
	local gx, gy = M.MinimapOffset(d.x, d.y)
	if not (gx > -math.huge and gx < math.huge and gy > -math.huge and gy < math.huge) then
		g:Hide()
		M.goalChev.on = false
		M.goalChev:Hide()
		return
	end
	local size, chev = M.TRAIL.GOAL_MINI, M.goalChev
	local m = size / 2 + 1
	local inside
	if round then
		inside = gx * gx + gy * gy <= (R - m) * (R - m)
	else
		inside = math.abs(gx) <= RX - m and math.abs(gy) <= RY - m
	end
	if inside then
		M.GoalLay(g, size, mm, "CENTER", gx, gy)
		if chev.on then
			chev.on = false
			chev:Hide()
		end
		return
	end
	-- beyond the map: the mark just inside its edge, the chevron outside it
	local k = M.MinimapEdge(gx, gy, round, R, RX, RY, m + 7)
	M.GoalLay(g, size, mm, "CENTER", gx * k, gy * k)
	local kc = M.MinimapEdge(gx, gy, round, R, RX, RY, 4)
	local cx, cy = gx * kc, gy * kc
	if not chev.atX or (cx - chev.atX) * (cx - chev.atX) + (cy - chev.atY) * (cy - chev.atY) >= 0.25 then
		chev.atX, chev.atY = cx, cy
		chev:ClearAllPoints()
		chev:SetPoint("CENTER", mm, "CENTER", cx, cy)
		chev:SetRotation(math.atan2(gy, gx) + math.pi / 2)   -- (the art's V points down)
	end
	if not chev.on then
		chev.on = true
		chev:Show()
	end
end

-- A route point's offset on the minimap from the player (pixels) and its
-- distance (yards), in the view the tick sets once (M.mmView): no closure
-- made per tick. (Fields of M: this file's main chunk is near Lua's limit.)
M.mmView = { px = 0, py = 0, rotate = false, sin = 0, cos = 1, ppy = 1 }
function M.MinimapOffset(yx, yy)
	local v = M.mmView
	local dx, dy = yx - v.px, yy - v.py
	if v.rotate then
		dx, dy = dx * v.cos - dy * v.sin, dx * v.sin + dy * v.cos
	end
	return dx * v.ppy, -dy * v.ppy, math.sqrt(dx * dx + dy * dy)
end

-- The distance line under the minimap (Distance Under The Minimap: the
-- line's own switch, the route's dots there on or off; the options audit,
-- 2026-10-05): the route's length and the destination, hidden while the
-- arrow shows them. Written only when the route's length or the label
-- changes (no string made per tick); a secret label (asked first, never
-- compared: kept as mm itself, which no label equals) every time.
function M.MinimapLine(arrowShown)
	local text = mm.text
	if arrowShown or not (route and M.isEnabled and M.db.distanceText) then
		text:Hide()
		return
	end
	local remaining = route.length or 0
	local label = destination and destination.label
	local secret = MelloUI.Safe.IsSecret(label)
	if secret or remaining ~= mm.lineLength or label ~= mm.lineLabel then
		mm.lineLength, mm.lineLabel = remaining, secret and mm or label
		text:SetText(label and (Yards(remaining) .. "  " .. label) or Yards(remaining))
	end
	text:Show()
end

-- The minimap's view now (0.19.5: Route's drawing and the other modules'
-- on the minimap, one view a tick): its scale (pixels a yard), its turn, its
-- shape (round, or the square map cropped to its Width x Height:
-- MinimapPanel, 0.15.0) -- set into M.mmView for M.MinimapOffset; returns
-- round, R, RX, RY (pixels from its middle)
function M.MinimapView(px, py)
	local diameter = MinimapDiameter()
	local size = Minimap:GetWidth()
	local rotate = GetCVar("rotateMinimap") == "1"
	local sin, cos = 0, 1
	if rotate and GetPlayerFacing then
		local ok, facing = pcall(GetPlayerFacing)
		facing = ok and Plain(facing) or 0
		sin, cos = math.sin(facing), math.cos(facing)
	end
	local round = IsRoundMinimap()
	local R = size / 2 - 1
	local RX, RY = R, R
	local mp = MelloUI:GetModule("MinimapPanel")
	local shown = mp and mp.MapFrame and mp:MapFrame()
	if shown and shown ~= Minimap then
		local okS, sw, sh = pcall(shown.GetSize, shown)
		sw, sh = okS and Plain(sw) or nil, okS and Plain(sh) or nil
		if type(sw) == "number" and type(sh) == "number" then
			RX, RY = math.min(R, sw / 2 - 1), math.min(R, sh / 2 - 1)
		end
	end
	local view = M.mmView
	view.px, view.py, view.rotate, view.sin, view.cos, view.ppy = px, py, rotate, sin, cos, size / diameter
	return round, R, RX, RY
end

-- How far along (gx, gy) a mark beyond the minimap stands just inside its
-- edge, `inset` pixels in: the factor of the offset (the goal's mark, the
-- objective marks' edge marks)
function M.MinimapEdge(gx, gy, round, R, RX, RY, inset)
	if round then
		return (R - inset) / math.sqrt(gx * gx + gy * gy)
	end
	local kx = gx ~= 0 and (RX - inset) / math.abs(gx) or math.huge
	local ky = gy ~= 0 and (RY - inset) / math.abs(gy) or math.huge
	return math.min(kx, ky)
end

-- The other modules' drawing on the minimap (0.19.5: the Quest List's
-- objective marks): fn(cont, round, R, RX, RY) each tick of Route's minimap
-- layer, cont nil while the player's place or the view is not known (hide
-- then); fn nil: no more (its last call, with nil, hides). The layer ticks
-- while Route has a route or a goal, or a module wants it: one minimap layer,
-- Route's (Route off: none)
M.mmClients = {}
function M.WantMinimap(owner, fn)
	local old = M.mmClients[owner]
	if old == fn then
		return
	end
	M.mmClients[owner] = fn
	if old and not fn then
		pcall(old, nil)
	end
	M.MinimapShown()
end
-- (the frame the marks hang on: shown and hidden with the layer)
function M.MinimapFrame()
	return mm
end
-- the layer shown while it has something to draw (Redraw, M.WantMinimap)
function M.MinimapShown()
	if not mm then
		return
	end
	local mine = (route ~= nil or destination ~= nil)
		and (M.db.minimap or M.db.distanceText or M.db.arrow or M.db.worldMarker)
	mm:SetShown((M.isEnabled and (mine or next(M.mmClients) ~= nil)) and true or false)
end

local mmElapsed = 0
local function MinimapTick(_, elapsed)
	mmElapsed = mmElapsed + elapsed
	if mmElapsed < 0.05 then
		return
	end
	mmElapsed = 0
	mmPainter:Begin()
	local cont, px, py = PlayerYards(true)   -- one ask a frame, shared with the arrow
	local arrowShown = cont and UpdateArrow(cont, px, py) or false
	UpdateMarker()
	-- the distance line before the dots: its own switch, with or without
	-- Route On The Minimap (where the player is not known: kept as it was)
	if cont or not (route and M.isEnabled and M.db.distanceText) then
		M.MinimapLine(arrowShown)
	end
	-- the view, once a tick, for Route's drawing and the other modules' (the
	-- route clipped to the part of the map that shows)
	local drawRoute = (route and M.isEnabled and M.db.minimap and cont) and true or false
	local round, R, RX, RY
	if cont and (drawRoute or next(M.mmClients) ~= nil) then
		round, R, RX, RY = M.MinimapView(px, py)
	end
	for _, fn in pairs(M.mmClients) do
		fn(R and cont or nil, round, R, RX, RY)
	end
	if not drawRoute then
		mmPainter:End()
		M.GoalOnMinimap(nil)
		M.LineMaybeChanged()
		return
	end
	local unit = 2.6 * (tonumber(M.db.lineWidth) or 3)
	local points = RouteAhead()
	local Offset = M.MinimapOffset
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if a[1] == cont and b[1] == cont and b[4] ~= "boat" and b[4] ~= "flight" then
			local ax, ay = Offset(a[2], a[3])
			local bx, by = Offset(b[2], b[3])
			if round then
				ax, ay, bx, by = ClipToCircle(ax, ay, bx, by, R)
			else
				ax, ay, bx, by = ClipToSquare(ax, ay, bx, by, RX, RY)
			end
			if ax then
				mmPainter:Segment(ax, ay, bx, by, STYLE[b[4]] or STYLE.road, unit, "CENTER")
			end
		end
	end
	mmPainter:End()
	M.GoalOnMinimap(cont, round, R, RX, RY)
	M.LineMaybeChanged()
end

Redraw = function()
	DrawWorldMap()
	-- the marker follows the destination straight away; the minimap tick
	-- that also updates it stops as soon as there is no destination
	UpdateMarker()
	if arrow and not (destination and M.isEnabled and M.db.arrow) and not M.flight.arrowOn then
		arrow:Hide()
	end
	if mm then
		M.MinimapShown()
		if not route then
			if mmPainter then
				mmPainter:Clear()
			end
			mm.text:Hide()
			M.GoalOnMinimap(nil)
		end
		M.LineMaybeChanged()
	end
end

--------------------------------------------------------------------------------
-- For the other modules (0.14.0, the levelling features: the Quest
-- Tracker's nearest-first order and turn-in line, the quest tooltips, the
-- Services bar): Route's one way to know where the player is and how far
-- things are. Nothing here plans a route or loads the companion.
--   Route:Where()                    the player's continent map, yards east,
--                                    yards south; nil when not known (the
--                                    game asked once a frame at most)
--   Route:WantWhere(owner, on)       the bus topic 'where' (cont, x, y; all
--                                    nil when the place is lost), fired from
--                                    Route's own half-second tick, every 4th
--                                    one, only while an owner wants it, and
--                                    only when the player moved 10 yards or
--                                    more, changed continent, or was lost or
--                                    found again (a new owner hears the next
--                                    one, as do the owners when Route comes
--                                    back on). None while Route is off.
--   Route:WorldYards(wcont, wx, wy)  world coordinates as the data gives them
--                                    (world map 0, 1 or 2991, x, y) -> cont,
--                                    x, y as Where gives them; nil if unknown
--   Route:ObjectivePlaces(questID)   the places of the quest's open
--                                    objectives, one flat list { cont, x, y,
--                                    cont, x, y, ... }, and how many; nil when
--                                    it is complete, has no data, or the
--                                    objective data is not loaded (it is
--                                    never loaded for this). Kept per quest;
--                                    after a quest log change made again only
--                                    when which objectives are open changed.
--                                    Read only: the list is Route's. nil,
--                                    nil, true ("later") when this frame's
--                                    share of new places is used up (a whole
--                                    quest log asked at once): asked again in
--                                    a later frame, it is made. A needed item
--                                    not in the bags yet: its sources' places
--                                    in its objective's stead (Needed; made
--                                    again when the bags change that).
--   Route:ItemFirst(questID)         { [objective line] = "First: loot ...
--                                    from ..." } while an open objective's
--                                    needed item is not in the bags, else nil
--                                    (a reused table: read it at once)
--   Route:PinnedQuest()              the quest whose game tracking Route's
--                                    own pin holds for now (a needed item's
--                                    source, the dock on the way), else nil
--   Route:FollowedRemaining(questID) the yards left when Route follows that
--                                    quest (what the arrow says, or worked
--                                    out as it does while the arrow is off
--                                    or counting down a flight), else nil
--   Route:YardsText(d)               "240 yd" / "1.2 km", as the arrow's line
--   Route:PlaceNear(wcont, wx, wy[, reach])  the named place a world point
--                                    lies at (MelloUI_PlaceData: within that
--                                    place's reach, capped by `reach`) and
--                                    how far; nil for none. Makes nothing.
--   Route:DistanceTo(c, sameFrame), M.ContinentOf, M.PlayerSide, M.SideOpen
--   (above).
-- (Fields of M, no new locals: this file's main chunk is near Lua's limit.)
--------------------------------------------------------------------------------

function M:Where()
	return PlayerYards(true)
end

M.whereWant = { owners = {}, n = 0, fired = false, cont = nil, x = 0, y = 0,
	EVERY = 4,   -- ticks (2 s)
	MOVE = 10,   -- yards
}

function M:WantWhere(owner, on)
	local w = M.whereWant
	if owner == nil then
		return
	end
	on = on and true or false
	if (w.owners[owner] or false) == on then
		return
	end
	w.owners[owner] = on or nil
	w.n = w.n + (on and 1 or -1)
	if on then
		w.fired = false
	end
end

-- (from Tick, every EVERY-th tick while someone wants it: the place the
-- breadcrumb asked for this tick, no new ask)
function M.WhereTick()
	local w = M.whereWant
	local cont, x, y = PlayerYards(true)
	if w.fired and cont == w.cont and (cont == nil or Dist(x, y, w.x, w.y) < w.MOVE) then
		return
	end
	w.fired, w.cont, w.x, w.y = true, cont, x or 0, y or 0
	MelloUI:Fire("where", cont, x, y)
end

function M:WorldYards(wcont, wx, wy)
	wcont, wx, wy = MelloUI.Safe.Number(wcont), MelloUI.Safe.Number(wx), MelloUI.Safe.Number(wy)
	if not (wcont and wx and wy) then
		return nil
	end
	return YardsOfWorld(wcont, wx, wy)
end

function M:YardsText(d)
	d = MelloUI.Safe.Number(d)
	return d and Yards(d) or nil
end

-- (for the road recorder, Modules/RouteRecorder.lua) continent yards -> a
-- map's 0..1 place, nil off that map's continent: OnMap(mapID, cont, x, y)
M.OnMap = OnMap

function M:FollowedRemaining(questID)
	local d = destination
	if not (d and d.fromQuest and questID and d.questID == questID) then
		return nil
	end
	local r = route
	-- the arrow's own figure while it shows the route
	if r and r.left and not M.flight.arrowOn and arrow and arrow:IsShown() then
		return r.left
	end
	local cont, x, y = PlayerYards(true)
	if r then
		-- else worked out as the arrow does, from the player's place on the
		-- route (the arrow off, or counting down a flight), else the
		-- planned length
		if cont then
			local i, _, off, qx, qy = PlaceOnRoute(cont, x, y)
			if i then
				local _, _, left = AimPoint(cont, i, qx, qy, off)
				if left and left > 0 then
					return left
				end
			end
			if cont == d.cont then
				return Dist(x, y, d.x, d.y)
			end
		end
		return r.length
	end
	if cont and cont == d.cont then
		return Dist(x, y, d.x, d.y)
	end
	return nil
end

M.logGen = 0   -- quest log changes seen (QUEST_LOG_UPDATE)

do
	local KEEP = 40      -- quests kept; past that the list starts again
	-- New places worked out in one frame (each asks the game once or twice):
	-- a quest is begun only while the frame has some left, so a whole quest
	-- log read at once (the tracker's first look) is spread over frames. A
	-- quest not begun gives nil, nil, true ("later"): asked again in a later
	-- frame it is made.
	local BUDGET = 200
	local kept = 0
	local places = {}    -- [questID] = { log, sig, n, cont, x, y, cont, x, y, ... }
	local parts = {}     -- the signature's parts, reused
	local spent, spentAt = 0, nil   -- places worked out in the frame of spentAt (GetTime)
	M.objectiveBudget = BUDGET      -- (for the tests)

	-- which objectives are open, cheaply: complete, and each one finished
	local function Signature(questID)
		local n = 1
		local okC, done = pcall(C_QuestLog.IsComplete, questID)
		parts[1] = (okC and Plain(done)) and "c" or "o"
		if C_QuestLog.GetQuestObjectives then
			local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
			if ok and type(list) == "table" then
				for _, o in ipairs(list) do
					n = n + 1
					parts[n] = Plain(o.finished) and "1" or "0"
				end
			end
		end
		return table.concat(parts, "", 1, n)
	end

	function M:ObjectivePlaces(questID)
		questID = MelloUI.Safe.Number(questID)
		local data = MelloUI_QuestObjectiveData
		if not (questID and type(data) == "table" and type(data[questID]) == "string" and C_QuestLog and C_QuestLog.IsComplete) then
			return nil
		end
		local e = places[questID]
		-- (a quest that needs items: its open places as the route has them,
		-- each needed item held or not with them, asked each time -- the bags
		-- are not the quest log, a needed item looted changes no objective)
		local needed = MelloUI_QuestNeededItems
		local gated = type(needed) == "table" and type(needed[questID]) == "string"
		local open, sig
		if gated then
			local osig
			open, osig = OpenObjectives(questID)
			sig = "g" .. (osig or "")
		else
			sig = (not e or e.log ~= M.logGen) and Signature(questID)
		end
		if e and sig and sig == e.sig then
			e.log = M.logGen   -- the same objectives open: the places as they were
		elseif sig then
			local now = GetTime()
			if now ~= spentAt then
				spentAt, spent = now, 0
			end
			if spent >= BUDGET then
				return nil, nil, true   -- this frame's share used: later
			end
			if not e then
				if kept >= KEEP then
					wipe(places)
					kept = 0
				end
				e = {}
				places[questID] = e
				kept = kept + 1
			end
			for i = 1, e.n or 0 do
				e[i] = nil
			end
			local n = 0
			if not gated then
				open = OpenObjectives(questID)
			end
			for _, entry in ipairs(open or {}) do
				local wmap = entry[4]
				for i = 5, #entry - 1, 2 do
					spent = spent + 1
					local cont, x, y = YardsOfWorld(wmap, entry[i], entry[i + 1], true)
					if cont then
						e[n + 1], e[n + 2], e[n + 3] = cont, x, y
						n = n + 3
					end
				end
			end
			e.n, e.sig, e.log = n, sig, M.logGen
		end
		if e.n == 0 then
			return nil
		end
		return e, e.n / 3
	end
end

-- Route:ItemFirst(questID): what to do first for the quest's open objectives
-- whose needed item the bags do not hold yet (Needed): { [line] = "First:
-- loot Samuel's Remains from Samuel Fipps" }, `line` the objective's index in
-- the game's C_QuestLog.GetQuestObjectives; nil for none. Needs the
-- companion's data (nil until it is loaded; never loads it). The table is
-- reused: read it at once. The source named is the one the route goes to
-- while it follows the quest, else the first the data names (a creature that
-- drops the item before an object that holds it).
do
	local hints, wants, words = {}, {}, {}

	function M:ItemFirst(questID)
		questID = MelloUI.Safe.Number(questID)
		-- (most quests need none)
		local needed = MelloUI_QuestNeededItems
		if not (questID and type(needed) == "table" and type(needed[questID]) == "string") then
			return nil
		end
		wipe(hints)
		wipe(wants)
		wipe(words)
		local d = destination
		local going = d and d.fromQuest and d.questID == questID and d.source
		OpenObjectives(questID, hints, wants, going and going.gate and going.gate.item)
		local any = false
		for line, gate in pairs(hints) do
			if gate.made then
				-- (2026-10-04, Traditions of the Bluff: the four bought, the
				-- incense not made yet) the objective itself: use them
				words[line] = "Next: use " .. gate.gates[1].name .. " to make " .. gate[2]
			else
				local from = going
				if not (from and from.gate and from.gate.item == gate.item) then
					from = gate[1]
				end
				-- (how many are held of how many wanted, when more than one is)
				local want = wants[line] or gate.count
				local held = want > 1 and Needed.Count(gate)
				words[line] = "First: " .. (Needed.VERB[from[1]] or "get") .. " " .. gate.name
					.. (held and string.format(" (%d/%d)", held, want) or "") .. " from " .. from[2]
			end
			any = true
		end
		return any and words or nil
	end
end

-- Route:PinnedQuest(): the quest whose game tracking Route's own map pin
-- holds for now (a needed item's source, or the dock on the way to another
-- continent: StandIn), else nil. The game then tracks the pin; the tracker
-- still shows that quest as the one followed.
function M:PinnedQuest()
	return standIn and standIn.questID or nil
end

do
	local WIDEST = 400   -- yards: the widest reach in the data

	function M:PlaceNear(wcont, x, y, reach)
		local data = MelloUI_PlaceData
		local t = type(data) == "table" and data[wcont]
		local Num = MelloUI.Safe.Number
		x, y, reach = Num(x), Num(y), Num(reach)
		if type(t) ~= "table" or not (x and y) then
			return nil
		end
		-- the first row whose x is within the widest reach of the point, then
		-- along while x stays within it
		local lo, hi = 1, math.floor(#t / 4)
		local from = x - WIDEST
		while lo < hi do
			local mid = math.floor((lo + hi) / 2)
			if t[mid * 4 - 3] < from then
				lo = mid + 1
			else
				hi = mid
			end
		end
		local best, bestD
		local i, n = lo * 4 - 3, #t
		while i <= n do
			local px = t[i]
			if px > x + WIDEST then
				break
			end
			local r = t[i + 2]
			if reach and reach < r then
				r = reach
			end
			local dx, dy = px - x, t[i + 1] - y
			local d = dx * dx + dy * dy
			if d <= r * r and (not bestD or d < bestD) then
				best, bestD = t[i + 3], d
			end
			i = i + 4
		end
		if not best then
			return nil
		end
		return best, math.sqrt(bestD)
	end
end

-- For /route: the player's map and how Route places it (0.14.0: why a map
-- has no position, said in player words)
function M.WhereWords()
	local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	mapID = ok and Plain(mapID) or nil
	if type(mapID) ~= "number" then
		return "your map: the game names none right now"
	end
	local okI, info = pcall(C_Map.GetMapInfo, mapID)
	info = okI and type(info) == "table" and info or nil
	local head = string.format("your map: %d %s", mapID, info and MelloUI.Safe.Text(info.name) or "(no name)")
	local okN, inside = pcall(IsInInstance)
	if okN and Plain(inside) then
		return head .. ", in an instance (Route draws in the open world only)"
	end
	local cont = ContinentOf(mapID)
	if not cont then
		return head .. ", a world map or one the game does not describe: Route can't place you on it"
	end
	local okP, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	local px = okP and VectorXY(pos) or nil
	if not px then
		return head .. ", but the game gives no position for you on it"
	end
	if cont == mapID then
		if info and Plain(info.mapType) == MAP_CONTINENT then
			return head .. ", a continent"
		end
		return head .. ", its own continent (there is no continent above it)"
	end
	if not RectOn(mapID, cont) then
		return head .. string.format(", on continent %d, but where it lies on it is not known", cont)
	end
	return head .. string.format(", on continent %d", cont)
end

--------------------------------------------------------------------------------
-- Flight-master help (0.14.0, the levelling features; the user's picks,
-- 2026-09-26). State in M.flight (above, by the travel time).
--   The flight map (Flight Map Help): where the route flies from here,
--   "Route: fly to Sentinel Hill · about 1:16", on the map window's title
--   band (a line of ours on the window, on the soft text shade), and a small
--   gem on that flight point, no bigger than the point's own button, so the
--   map's picture is never covered. Pointing at a flight point adds its
--   flight time to its tooltip, and "Your route flies here" on that one.
--   The known flight points may change at the map, so the route is planned
--   again as it opens (once routes can be priced).
--   The flight: "Flying to Sentinel Hill, about 1:16" as it takes off; the
--   Direction Arrow points at the landing and counts down, "Landing at
--   Sentinel Hill in about 0:52", then "soon" (Landing Countdown; the arrow
--   shows for the flight also with no route set, and goes back to the route
--   after); "Landed at Sentinel Hill (1:14)" on the ground. The notices are
--   the on-screen notice's (its own switches). No take-off within TIMEOUT
--   seconds of the click (no money for it): nothing happens.
--   Flight times: a timed flight first (from one flight point to another,
--   timed from the click to the landing and kept with the learned paths
--   while learning is on), then the Quest List data's flight paths (their
--   path lengths at SPEED, plus 5 s), then the straight line at SPEED; a
--   flight over several legs is their sum, less 5 s at each stop.
-- Made at the first flight map (TAXIMAP_OPENED), nothing at login; driven by
-- that event, the game's own TakeTaxiNode and TaxiNodeOnButtonEnter (post-
-- hooks, set at the first flight map) and Route's half-second tick while a
-- flight is asked for or under way (the text changes once a second at
-- most). After a /reload mid-flight nothing is shown: its start is not known.
--------------------------------------------------------------------------------

do
	local F = M.flight
	local Safe = MelloUI.Safe
	local Clock = Travel.Clock   -- "1:16"

	-- "Sentinel Hill" of "Sentinel Hill, Westfall"
	function F.Short(name)
		if type(name) ~= "string" or name == "" then
			return nil
		end
		return name:match("^%s*([^,]-)%s*,") or name
	end

	-- A flight timed before, from node a to node b (seconds), or nil
	function F.Learned(a, b)
		if not (a and b) then
			return nil
		end
		local t = live.flights[a .. ">" .. b]
		return type(t) == "number" and t or nil
	end

	-- A flight timed now: kept, half and half with an older time for the
	-- same flight (one slow take-off does not stick)
	function F.Learn(a, b, secs)
		local key = a .. ">" .. b
		local old = live.flights[key]
		if type(old) == "number" then
			secs = (old + secs) / 2
		end
		live.flights[key] = math.floor(secs * 10 + 0.5) / 10
	end

	-- Timed flights another table kept: the saved ones (`mine`: they win)
	-- or the ones that come with MelloUI
	function F.Adopt(list, mine)
		if type(list) ~= "table" then
			return
		end
		local flights = live.flights
		for key, secs in pairs(list) do
			if type(key) == "string" and type(secs) == "number" and secs > 0 and (mine or flights[key] == nil) then
				flights[key] = secs
			end
		end
	end

	-- One leg between two flight points of the open map (their records)
	function F.Leg(a, b)
		local t = F.Learned(a.id, b.id)
		if t then
			return t
		end
		local node = a.id and taxis and taxis[a.id]
		t = node and b.id and node.links[b.id]
		if type(t) == "number" then
			return t
		end
		if a.cont and a.cont == b.cont and a.x and b.x then
			return Dist(a.x, a.y, b.x, b.y) / F.SPEED + 5
		end
		return nil
	end

	-- Seconds from the flight master here to the point in `slot`, or nil
	function F.Estimate(slot)
		local from, to = F.current, F.slots[slot]
		if not (from and to) or from == to then
			return nil
		end
		local t = F.Learned(from.id, to.id)
		if t then
			return t
		end
		local numRoutes, nodeSlot = _G.GetNumRoutes, _G.TaxiGetNodeSlot
		if numRoutes and nodeSlot then
			local ok, hops = pcall(numRoutes, slot)
			hops = ok and Safe.Number(hops) or 0
			local total = hops > 0 and 0 or nil
			for h = 1, hops do
				local okA, sa = pcall(nodeSlot, slot, h, true)
				local okB, sb = pcall(nodeSlot, slot, h, false)
				sa, sb = okA and Safe.Number(sa), okB and Safe.Number(sb)
				local a, b = sa and F.slots[sa], sb and F.slots[sb]
				local secs = a and b and F.Leg(a, b)
				if not secs then
					total = nil
					break
				end
				total = total + secs
			end
			if total then
				return total - 5 * (hops - 1)
			end
		end
		return F.Leg(from, to)
	end

	-- The open flight map's points by slot (node id, name, state, place in
	-- continent yards) and the one the player stands at (F.current)
	function F.ReadMap()
		F.readGen = F.openGen
		local slots = F.slots
		wipe(slots)
		F.current = nil
		local all, mapOf = C_TaxiMap and C_TaxiMap.GetAllTaxiNodes, _G.GetTaxiMapID
		if not (all and mapOf) then
			return
		end
		local okM, mapID = pcall(mapOf)
		mapID = okM and Safe.Number(mapID) or nil
		if not mapID then
			return
		end
		local ok, list = pcall(all, mapID)
		if not (ok and type(list) == "table") then
			return
		end
		for _, info in ipairs(list) do
			local slot = type(info) == "table" and Safe.Number(info.slotIndex)
			if slot then
				local px, py = VectorXY(info.position)
				local cont, x, y
				if px and py then
					cont, x, y = ToYards(mapID, px, py)
				end
				local rec = { id = Safe.Number(info.nodeID), name = Safe.Text(info.name), state = Plain(info.state), cont = cont, x = x, y = y }
				slots[slot] = rec
				if rec.state == FLIGHT_CURRENT then
					F.current = rec
				end
			end
		end
	end

	-- The flight point the route flies to from here: the end of the route's
	-- first run of flights, when this map reaches it; its slot and record
	function F.Wanted()
		local r = route
		if not (r and F.current) then
			return nil
		end
		local points, stop = r.points, nil
		for i = 2, #points do
			local a, b = points[i - 1], points[i]
			local flying = b[4] == "flight"
			if not flying and a[1] == b[1] and b[4] ~= "boat" then
				flying = Travel.LinkFlight(a, b, Dist(a[2], a[3], b[2], b[3])) ~= nil
			end
			if flying then
				stop = b
			elseif stop then
				break
			end
		end
		if not stop then
			return nil
		end
		local id = type(stop[5]) == "string" and tonumber(stop[5]:match("^T(%d+)$")) or nil
		local best, bestD
		for slot, rec in pairs(F.slots) do
			if rec.state == FLIGHT_REACHABLE then
				if id and rec.id == id then
					return slot, rec
				end
				if rec.cont == stop[1] and rec.x then
					local d = Dist(rec.x, rec.y, stop[2], stop[3])
					if d <= F.NEAR and (not bestD or d < bestD) then
						best, bestD = slot, d
					end
				end
			end
		end
		return best, best and F.slots[best]
	end

	-- The "fly to" line on the title band, made at its first use. One level
	-- over the window: above its stone, under the Flight Map Kit's band and
	-- plate (the window + 2 and + 3), so where the plate reaches into the
	-- band it covers our text shade, never the other way round
	function F.Caption(tf)
		local cap = F.caption
		if cap then
			return cap
		end
		cap = CreateFrame("Frame", nil, tf)
		cap:SetPoint("TOPLEFT", tf, "TOPLEFT", 0, 0)
		cap:SetPoint("TOPRIGHT", tf, "TOPRIGHT", 0, 0)
		cap:SetHeight(F.BAND)
		cap:SetFrameLevel((Safe.Number(tf:GetFrameLevel()) or 1) + 1)
		cap:EnableMouse(false)
		local text = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		RouteFont.Style(text, "fontText", _G.GameFontHighlight)
		text:SetWordWrap(false)
		cap.text = text
		-- the text shade under it (the eye-strain rule: no text straight on
		-- the stone), kept inside the band
		if MelloUI.Shade and MelloUI.Shade.Band then
			cap.shade = TextShade.Band(cap, text, TextShade.FEATHER, TextShade.PAD_X, 2)
		end
		F.caption = cap
		Travel.Paint()   -- the arrow's gold, repainted with it
		cap:Hide()
		return cap
	end

	-- Left of the game's title while that title sits on the band (the Flight
	-- Map Kit off), and no wider than the room it leaves; else (the title on
	-- the kit's plate, riding the top rail) centred under that title: the
	-- plate reaches a few units into the band, below the title's letters, so
	-- the line starts CLEAR units under them (at most LOWEST down, which
	-- keeps it on the band)
	F.CLEAR, F.LOWEST = 4, 7
	function F.PlaceCaption(tf, cap)
		local text = cap.text
		text:ClearAllPoints()
		local tl, tb, _, tt = Safe.ScreenRect(tf.TitleText or _G.TaxiFrameTitleText)
		local fl, _, _, ft = Safe.ScreenRect(tf)
		local okS, s = pcall(tf.GetEffectiveScale, tf)
		s = okS and Safe.Number(s) or nil
		if tl and fl and s and s > 0 and (tb + tt) / 2 < ft - 2 * s then
			local room = (tl - fl) / s - F.INSET - 8
			text:SetPoint("LEFT", cap, "LEFT", F.INSET, 0)
			text:SetJustifyH("LEFT")
			local okW, w = pcall(text.GetStringWidth, text)
			w = okW and Safe.Number(w) or nil
			text:SetWidth((w and room > 0 and w > room) and room or 0)
		else
			-- how far the title's letters reach below the window's top
			local reach = (tb and ft and s and s > 0) and (ft - tb) / s or 0
			local down = math.min(F.LOWEST, math.max(2, reach + F.CLEAR))
			text:SetPoint("TOP", cap, "TOP", 0, -down)
			text:SetJustifyH("CENTER")
			text:SetWidth(0)
		end
	end

	-- the gem's picture: the kit's small gem painted, the game's map pin with
	-- the reskin off (MelloUI.Look)
	function F.GemArt(tex, painted)
		if painted then
			local Kit = MelloUI.Kit
			if not (Kit and Kit.Piece and Kit:Piece("deco/gem_small") and Kit:Apply(tex, "deco/gem_small")) then   -- look-ok: F.GemArt's painted branch
				tex:SetTexture("Interface/Common/Indicator-Yellow")
			end
			return
		end
		tex.kitPiece, tex.kitName = nil, nil
		tex:SetAtlas((select(2, MelloUI.Look.Art("mapPin"))), false, nil, true)   -- (resetTexCoords: the kit gem's crop dropped)
	end

	-- The small gem on the wanted flight point's button, made at its first use,
	-- as a child of that button: it shows only while the map shows the button
	-- (a far point's comes and goes as paths through it are pointed at: a gem
	-- without it would lie on the picture)
	function F.Gem(slot)
		local button = _G["TaxiButton" .. slot]
		if type(button) ~= "table" or not (button.GetFrameLevel and button.IsShown) then
			if F.gem then
				F.gem:Hide()
			end
			return
		end
		local g = F.gem
		if not g then
			g = CreateFrame("Frame", nil, button)
			g:SetSize(F.GEM, F.GEM)
			g:EnableMouse(false)
			g.tex = g:CreateTexture(nil, "OVERLAY")
			g.tex:SetAllPoints()
			MelloUI.Look.Watch(g.tex, F.GemArt)   -- (its look now, and at each switch of the reskin)
			F.gem = g
		end
		if g:GetParent() ~= button then
			g:SetParent(button)
		end
		g:SetFrameLevel((Safe.Number(button:GetFrameLevel()) or 1) + 2)
		g:ClearAllPoints()
		g:SetPoint("CENTER", button, "CENTER", 0, 0)
		g:Show()
		-- a gentle pulse, engine-driven (still under Reduce Motion)
		local anim = MelloUI.Anim
		if anim and anim.Pulse then
			F.gemPulse = anim:Pulse(g.tex, 0.55, 1, 1.2)
		end
	end

	function F.HideHint()
		F.wanted = nil
		if F.caption then
			F.caption:Hide()
		end
		if F.gem then
			F.gem:Hide()
			if F.gemPulse and MelloUI.Anim then
				MelloUI.Anim:StopGroup(F.gemPulse)
			end
		end
	end

	-- The line and the gem as the route and the open map say
	function F.Hint()
		local tf = _G.TaxiFrame
		local slot, rec
		if M.isEnabled and M.db.flightHint and type(tf) == "table" and Safe.Call(tf, "IsShown") then
			if F.readGen ~= F.openGen then
				F.ReadMap()
			end
			slot, rec = F.Wanted()
		end
		if not slot then
			F.HideHint()
			return
		end
		F.wanted = slot
		local cap = F.Caption(tf)
		local secs = F.Estimate(slot)
		local node = rec.id and taxis and taxis[rec.id]
		local name = F.Short(rec.name) or F.Short(node and node.name) or "the flight point"
		cap.text:SetText("Route: fly to " .. name .. (secs and (Travel.SEP .. "about " .. Clock(secs)) or ""))
		F.PlaceCaption(tf, cap)
		cap:Show()
		F.Gem(slot)
	end

	-- the route planned again (the known flight points may have changed at
	-- this map), then the line
	function F.PlanHint()
		if not (M.isEnabled and destination) then
			return
		end
		Plan(true)
		-- (0.17.1: a search that goes on in the next frames: the line once it has ended)
		if Search.Busy() then
			Search.After(F.Hint)
		else
			F.Hint()
		end
	end

	-- TAXIMAP_OPENED, a moment later (after Route learned this map)
	function F.Opened()
		if not M.isEnabled then
			return
		end
		F.ReadMap()
		F.Hook()
		F.HideHint()
		if M.db.flightHint and destination then
			M:WhenReady(F.PlanHint)
		end
	end

	-- The game's TakeTaxiNode (a post-hook): the flight asked for
	function F.Took(slot)
		slot = Safe.Number(slot)
		if not (M.isEnabled and slot) then
			return
		end
		if F.readGen ~= F.openGen then
			F.ReadMap()
		end
		local to, from = F.slots[slot], F.current
		if not (to and to.state == FLIGHT_REACHABLE) then
			return
		end
		local node = to.id and taxis and taxis[to.id]
		F.pending = { from = from and from.id, to = to.id, name = F.Short(to.name) or F.Short(node and node.name) or "the flight point",
			cont = to.cont, x = to.x, y = to.y, secs = F.Estimate(slot), at = GetTime() }
	end

	-- The game's TaxiNodeOnButtonEnter (a post-hook): the flight time in the
	-- point's tooltip, and whether the route flies there
	function F.OnEnter(button)
		if not (M.isEnabled and M.db.flightHint) then
			return
		end
		local slot = Safe.Number(Safe.Call(button, "GetID"))
		if not slot then
			return
		end
		if F.readGen ~= F.openGen then
			F.ReadMap()
		end
		local rec = F.slots[slot]
		local tip = _G.GameTooltip
		if not (rec and rec.state == FLIGHT_REACHABLE and tip) then
			return
		end
		local secs = F.Estimate(slot)
		if not (secs or slot == F.wanted) then
			return
		end
		local P = MelloUI.Look.Palette()   -- (the reskin off: the game's white and gold)
		if secs then
			local c = P.text
			tip:AddLine("Flight time: about " .. Clock(secs), c[1], c[2], c[3])
		end
		if slot == F.wanted then
			local c = P.selectedTrim
			tip:AddLine("Your route flies here", c[1], c[2], c[3])
		end
		tip:Show()
	end

	-- the post-hooks, once, at the first flight map
	function F.Hook()
		if F.hooked then
			return
		end
		F.hooked = true
		if type(_G.TakeTaxiNode) == "function" then
			hooksecurefunc("TakeTaxiNode", F.Took)
		end
		if type(_G.TaxiNodeOnButtonEnter) == "function" then
			hooksecurefunc("TaxiNodeOnButtonEnter", F.OnEnter)
		end
		-- the map closed: the line and the gem down, and the gem's pulse
		-- stopped (hidden with its button it would still count as playing)
		local tf = _G.TaxiFrame
		if type(tf) == "table" and tf.HookScript then
			Perf.HookScript(tf, "OnHide", F.HideHint)
		end
	end

	-- The arrow given back to the route (or hidden with none)
	function F.ArrowOff()
		if not F.arrowOn then
			return
		end
		F.arrowOn = false
		F.shown, F.shownD = nil, nil
		if arrow then
			arrow.lineSuffix, arrow.lineD = nil, nil   -- the route's distance line made afresh (Travel.Line)
			arrow.targetX = nil
			if not (destination and M.isEnabled and M.db.arrow) then
				arrow:Hide()
			end
			M.nav.Refresh()   -- (the ring: the way's share again)
		end
	end

	-- The countdown on the arrow (Route's tick, while flying): the text made
	-- only when the whole seconds shown change
	function F.Update(now)
		local a = F.active
		if not (a and M.isEnabled and M.db.flightCountdown and M.db.arrow and arrow) then
			F.ArrowOff()
			return
		end
		local shown = -1   -- no time known
		if a.secs then
			local left = a.secs - (now - a.at)
			shown = left >= 0.5 and math.floor(left + 0.5) or 0
		end
		if not F.arrowOn then
			F.arrowOn = true
			F.shown, F.shownD = nil, nil
			arrow.lineSuffix, arrow.lineD = nil, nil
			M.nav.Refresh()   -- (the ring: the flight's time, its time text on the row)
		end
		if shown ~= F.shown then
			F.shown = shown
			arrow.title = (shown == 0 and "Landing at " or "Flying to ") .. a.name
		end
		M.nav.Push()
		local cont, px, py = PlayerYards(true)
		if cont and a.cont == cont then
			arrow.targetCont, arrow.targetX, arrow.targetY = cont, a.x, a.y
			local d = math.floor(Dist(px, py, a.x, a.y))
			if d ~= F.shownD then
				F.shownD = d
				arrow.distance:SetText(Yards(d))
			end
		else
			arrow.targetX = nil
			if F.shownD ~= false then
				F.shownD = false
				arrow.distance:SetText("")
			end
		end
		arrow:Show()
	end

	function F.TakeOff(p)
		F.active = p
		if F.Listen then
			F.Listen(true)
		end
		M:Notify("Flying to " .. p.name .. (p.secs and (", about " .. Clock(p.secs)) or ""), "track")
		F.Update(GetTime())
	end

	function F.Land(now)
		local a = F.active
		F.active = nil
		if F.Listen then
			F.Listen(false)
		end
		F.ArrowOff()
		if not a then
			return
		end
		local took = now - a.at
		if M.db.learn and a.from and a.to and took >= F.SHORTEST and took <= F.LONGEST then
			F.Learn(a.from, a.to, took)
		end
		M:Notify("Landed at " .. a.name .. " (" .. Clock(took) .. ")", "arrive")
	end

	-- Route's tick, while a flight is asked for or under way
	function F.Tick()
		local now = GetTime()
		local p = F.pending
		if p then
			if Travel.OnTaxi() then
				F.pending = nil
				F.TakeOff(p)
			elseif now - p.at > F.TIMEOUT then
				F.pending = nil   -- no take-off: nothing said
			end
			return
		end
		if F.active then
			if Travel.OnTaxi() then
				F.Update(now)
			else
				F.Land(now)
			end
		end
	end

	-- PLAYER_CONTROL_GAINED (listened to during a flight): landed now
	function F.ControlGained()
		if F.active and not Travel.OnTaxi() then
			F.Land(GetTime())
		end
	end

	-- Route switched off: all of it away (a flight under way is not timed)
	function F.Stop()
		F.pending, F.active = nil, nil
		if F.Listen then
			F.Listen(false)
		end
		F.ArrowOff()
		F.HideHint()
	end

	-- an option changed
	function F.Setting(key)
		if key == "flightHint" then
			if M.db.flightHint then
				F.Hint()
			else
				F.HideHint()
			end
		elseif (key == "flightCountdown" or key == "arrow") and F.active then
			F.Update(GetTime())
		end
	end
end

--------------------------------------------------------------------------------
-- Saved graph
--------------------------------------------------------------------------------

-- The saved variable's pins go in at once; its paths with the graph -- now,
-- or once it is built, in their turn after what was learned before the
-- client brought them
local function AdoptSaved()
	if type(MelloUIRoutes) == "table" and not mergedSaved then
		mergedSaved = true
		local saved = MelloUIRoutes
		MergePins(saved)
		M.flight.Adopt(saved.flights, true)   -- the flights this player timed
		Build.Queue(function()
			if Merge(saved) > 0 then
				BuildDocks()
			end
		end)
		return true
	end
	return false
end

-- The data files are let go once folded in (memory audit, 2026-09-24: the
-- roads stayed in memory twice, 7.5 MB as loaded beside the 7.2 MB graph).
-- Nothing else reads them; /route reset keeps the roads in the graph itself.
-- The graph stays across switching Route off and on, so a reset now holds
-- until the next /reload (it used to bring the baked paths back with it).
-- The baked paths (Media\RouteData.lua, a few KB) are taken off their global
-- here and their pins merged, as ever; their paths wait for the build. The
-- roads come from the companion when the build starts.
local function LoadBaked()
	if type(MelloUI_RouteData) == "table" then
		Build.baked = MelloUI_RouteData
		_G.MelloUI_RouteData = nil
		MergePins(Build.baked)
		M.flight.Adopt(Build.baked.flights, false)
	end
end

--------------------------------------------------------------------------------
-- Building the graph
--
-- (user, 2026-09-24: the road graph is built on the first route request, a
-- little each frame so no frame hitches, not at login) The traced
-- roads are some 18,000 points, 7 MB as a graph, and were merged at every
-- login with Route on, a quarter of a second, whether the session routed
-- or not. Now the first thing that needs them -- a route to plan, places to
-- price, a quest tracked (its objective places come in the same companion)
-- -- loads MelloUI_Companion and starts the build: the roads, the baked
-- paths, then what was learned meanwhile, in the order they always went in
-- (so the graph comes out the same), BUDGET milliseconds a frame. Until it
-- is whole no route is planned; the first one appears when it is, with its
-- notice, and the arrow and the marker point straight at the place meanwhile.
-- Without the companion the graph is built from the learned paths alone.
--------------------------------------------------------------------------------

do
	local BUDGET = 2       -- ms of building a frame
	local RETRY = 5        -- seconds before the companion is asked again after a load the game refused just then
	local TRIES = 3        -- ... this often at most, out of combat and instances; then the graph is built without the roads
	local builder = CreateFrame("Frame")   -- its OnUpdate builds, shown while it does
	builder:Hide()
	-- Where the build is (one table: the main chunk is near its 200 locals):
	-- the part next (0 the roads, 1 the baked paths, 2 what was learned
	-- meanwhile) and how many of Build.pending were made; the companion asked
	-- how often, whether a new try is awaited (a timer or the end of a fight
	-- asks again, nothing else), and whether LoadAddOn runs now (its
	-- ADDON_LOADED runs other code first)
	local at = { stage = 0, applied = 0, tries = 0, waiting = false, loading = false }

	-- The try awaited: the graph is still wanted (a load is only tried when
	-- it is), so the build goes on as if asked now; with Route switched off
	-- meanwhile it waits for the next ask (Route off never loads the data)
	at.Again = function()
		builder:UnregisterAllEvents()
		at.waiting = false
		if M.isEnabled then
			Build.Want()
		end
	end
	Perf.SetScript(builder, "OnEvent", at.Again)

	-- The companion's data, loaded once; false while a load the game refused
	-- just then waits for another try
	local function LoadData()
		if Build.asked then
			return true
		elseif at.loading then
			return false
		end
		if MelloUI.LoadCompanion then
			at.loading = true
			local ok, why, later = MelloUI:LoadCompanion()
			at.loading = false
			if not ok and later then
				at.waiting = true
				-- A fight or an instance is the likely reason the game said no
				-- (review, 2026-09-24: three tries ten seconds apart ran out
				-- inside one fight, and a /reload in combat then kept the
				-- roads and the objective places away for the whole session).
				-- Not counted: asked again once the fight is over, or the
				-- zone changes (leaving the instance).
				local okI, inInstance = pcall(IsInInstance)
				inInstance = okI and Plain(inInstance) and true or false
				if inInstance or (InCombatLockdown and InCombatLockdown()) then
					builder:RegisterEvent("PLAYER_REGEN_ENABLED")
					if inInstance then
						builder:RegisterEvent("PLAYER_ENTERING_WORLD")
					end
					return false
				end
				at.tries = at.tries + 1
				if at.tries < TRIES then
					C_Timer.After(RETRY, at.Again)
					return false
				end
				at.waiting = false
				MelloUI:Notice("Route: the road data could not be loaded (%s); routes follow the paths you have walked until the next /reload.", why)
			end
			-- any other refusal the companion told in chat itself
		end
		Build.asked = true
		return true
	end

	-- The build, in a coroutine: each part is marked done before it runs, so
	-- one that fails is told in chat and the build goes on with the next
	local function Body()
		if at.stage == 0 then
			at.stage = 1
			-- the companion's table: its global let go now, the table itself
			-- once merged
			local roads = MelloUI_RoadData
			_G.MelloUI_RoadData = nil
			M.Ground.Set(roads)
			MergeRoads(roads)
		end
		if at.stage == 1 then
			at.stage = 2
			local baked = Build.baked
			Build.baked = nil
			Merge(baked)
		end
		local pending = Build.pending
		while at.applied < #pending do
			local i = at.applied + 1
			at.applied = i
			local op = pending[i]
			pending[i] = false   -- let it go
			op.fn(unpack(op, 1, op.n))
			Build.Slice()
		end
		Build.pending = {}
		Build.ready = true
	end

	local function Run(budget)
		Build.deadline = debugprofilestop() + budget
		local ok, err = coroutine.resume(Build.job)
		if not ok then
			MelloUI:Print("|cffff4040Error|r in module 'Route' (building the road graph): %s", tostring(err))
			Build.job = coroutine.create(Body)   -- the rest, without the part that failed
			return
		end
		if coroutine.status(Build.job) == "dead" then
			Build.job = nil
		end
	end

	-- The route that waited for the roads: the tracked quest's places priced,
	-- the route planned and announced
	function Build.Replan()
		ReadWaypoint()
		if Build.waiting and destination then
			Plan(true)
		end
	end

	-- A frame's share of the build. The frame after it plans what waited
	-- (the first route's search gets a frame of its own): the route that
	-- waited (Build.Replan), then what was put off until routes could price it
	-- (M:WhenReady), in the order it was asked. Each through pcall, an error
	-- told in chat: the loading line and the arrow's working look go at the
	-- end whatever happened (review, 2026-09-28: held for the session else).
	Perf.SetScript(builder, "OnUpdate", function()
		if Build.job then
			Run(BUDGET)
			return
		end
		builder:Hide()
		local later = Build.later
		Build.later = nil
		if Build.closing or not M.isEnabled then
			Build.waiting = nil
			Build.Loaded()
			return
		end
		local okR, errR = pcall(Build.Replan)
		if not okR then
			MelloUI:Print("|cffff4040Error|r in module 'Route' (after the road graph was built): %s", tostring(errR))
		end
		Build.waiting = nil
		for i = 1, later and #later or 0 do
			local ok, err = pcall(later[i])
			if not ok then
				MelloUI:Print("|cffff4040Error|r in module 'Route' (after the road graph was built): %s", tostring(err))
			end
		end
		-- last: the route's own notice ("Tracking ...") has taken the
		-- loading line's place by now, and the arrow its place to point at
		-- (0.17.1: once its search has ended, when that went on in the next
		-- frames)
		if Search.Busy() then
			Search.After(Build.Loaded)
		else
			Build.Loaded()
		end
	end)

	-- The graph is wanted: the companion loaded (once) and the build started
	function Build.Want()
		if Build.ready or Build.job or at.waiting then
			return
		end
		if not LoadData() then
			return
		end
		Build.job = coroutine.create(Body)
		builder:Show()
		-- something waited while the load was put off (a fight): said now
		-- that the roads really go in (Build.Show)
		if Build.told and not Build.loading then
			C_Timer.After(Build.LOADING_AFTER, Build.Show)
		end
	end

	-- Whether routes can be planned; the first ask starts the build
	function Build.Ready()
		if Build.ready then
			return true
		end
		Build.Want()
		return false
	end

	-- A route asked for while the graph is built: planned once it is, with
	-- the notice of the last one that wanted one
	function Build.Wait(announce, text)
		local w = Build.waiting
		if not w then
			w = {}
			Build.waiting = w
		end
		if announce then
			w.announce, w.text = true, text
		end
		Build.Loading()
	end

	-- "Loading navigation..." (user, 2026-09-28): the first route of a
	-- session waits some 5 s for the roads to go in, and nothing on the
	-- screen said so. From the first thing that waits for them (a route to
	-- plan, places to price: Build.Wait, M:Cheapest, M:WhenReady) until the
	-- build's last frame: the line in the on-screen notice, held for as long
	-- (MelloUI:AnnounceWait: as Route's other lines, with the notice's own
	-- switches, never a sound), and the Direction
	-- Arrow's working look (Build.ArrowWork). Only a wait longer than
	-- LOADING_AFTER says so: a build done sooner (the learned paths alone,
	-- without the companion) would flash the line. Once a session: the
	-- graph, once built, stays; a load Route was switched off during may say
	-- it again. A build nothing waits for (the breadcrumbs of a long walk)
	-- says nothing. Said only while the build runs: a load the game put off
	-- (a fight, a moment's refusal: LoadData) holds no line or working arrow
	-- over the whole fight; Build.Want says it when the build starts.
	Build.LOADING = "Loading navigation..."
	Build.LOADING_AFTER = 0.3   -- seconds
	function Build.Loading()
		if Build.ready or Build.told or not M.isEnabled then
			return
		end
		Build.told = true
		C_Timer.After(Build.LOADING_AFTER, Build.Show)
	end

	-- still waiting a moment later, the build running: said, and the arrow
	-- at work
	function Build.Show()
		if Build.ready or Build.loading or not (Build.told and Build.job and M.isEnabled) then
			return
		end
		Build.loading = true
		if MelloUI.AnnounceWait then
			MelloUI:AnnounceWait(Build.LOADING, "info")
		end
		Build.ArrowWork()
	end

	-- The roads are in (or Route was switched off meanwhile): the line fades
	-- while it is still the one shown, the arrow's working look goes
	function Build.Loaded()
		if not Build.ready then
			Build.told = nil   -- (switched off first: said again the next time)
		end
		if not Build.loading then
			return
		end
		Build.loading = false
		if MelloUI.AnnounceDone then
			MelloUI:AnnounceDone(Build.LOADING)
		end
		Build.ArrowWork()
	end

	-- PLAYER_LOGOUT: the saved variable is the learned part of the whole
	-- graph, so a build under way is run to its end at once, and one never
	-- started is run now, roads and all, when there is anything to keep: a
	-- learned point on a road's cell is the road's and is not kept, so the
	-- roads decide what is written. The logout is a loading screen; the
	-- quarter second the login used to take goes there, and only in a session
	-- that never routed. Without the companion: the learned paths alone.
	function Build.Finish()
		if Build.ready then
			return
		end
		Build.closing = true
		if not Build.job then
			-- anything to keep: the baked paths, or a change other than a reset
			local keeps = Build.baked ~= nil
			for _, op in ipairs(Build.pending) do
				if op and op.fn ~= ForgetLearned then
					keeps = true
				end
			end
			if not keeps then
				return   -- nothing baked or learned (Route never on): the empty graph, as ever
			end
			builder:UnregisterAllEvents()
			at.waiting = false
			LoadData()
			Build.job = coroutine.create(Body)
		end
		while Build.job do
			Run(math.huge)
		end
		builder:Hide()
	end

	function Build.Save()
		Build.Finish()
		MelloUIRoutes = LearnedOnly()
	end
end

--------------------------------------------------------------------------------
-- Events and lifecycle
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local ticker = nil
local adoptTicker = nil

-- Pins recorded by the quest list and the services (/qlmap dock, a service
-- window) land in the store whether Route is on or off: the write at logout
-- must not go with the module's events (audit, 2026-09-22).
-- (Build.Save: the learned part of the whole graph, built first if it is not)
local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
Perf.SetScript(logoutFrame, "OnEvent", function()
	Build.Save()
end)

-- A faction chosen (a Neutral character's, 0.14.0: its rows were the ones
-- open to both factions until then): the docks and the flight points built
-- again for it, and the route planned again. Also asked at every loading
-- screen (a faction the login did not know yet); nothing when it is the same.
function M.SideChanged()
	if not M.isEnabled or M.PlayerSide() == M.builtSide then
		return
	end
	BuildDocks()
	BuildTaxis()
	discoveredAt = 0
	if destination then
		Plan(true)
	end
end

-- Needed items: the bags heard only while the destination is a quest that
-- needs one (Tick keeps it so); a change read again in the next frame, once
-- however many came, so the route, the arrow and the pin go to the objective
-- together the moment the item is looted, not at the next tick
function Needed.Listen(on)
	on = (on and M.isEnabled) and true or false
	if on == (Needed.listening or false) then
		return
	end
	Needed.listening = on
	if on then
		pcall(eventFrame.RegisterEvent, eventFrame, "BAG_UPDATE_DELAYED")
	else
		pcall(eventFrame.UnregisterEvent, eventFrame, "BAG_UPDATE_DELAYED")
	end
end

function Needed.BagsChanged()
	if Needed.pending then
		return
	end
	Needed.pending = true
	C_Timer.After(0, function()
		Needed.pending = false
		local d = destination
		if M.isEnabled and d and d.fromQuest and d.gated then
			ReadWaypoint()
		end
	end)
end

-- The flight-master help listens for the landing while a flight is under
-- way (M.flight)
function M.flight.Listen(on)
	if on then
		pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_CONTROL_GAINED")
	else
		pcall(eventFrame.UnregisterEvent, eventFrame, "PLAYER_CONTROL_GAINED")
	end
end

Perf.SetScript(eventFrame, "OnEvent", function(_, event, unit)
	if event == "PLAYER_LOGOUT" then
		Build.Save()
	elseif event == "PLAYER_ENTERING_WORLD" then
		last = nil
		taxiStart = nil
		Travel.Entered()   -- the travel time's login grace runs from the first one
		M.ForgetNoContinent()
		M.SideChanged()
		C_Timer.After(1, function() ReadWaypoint() end)
	elseif event == "USER_WAYPOINT_UPDATED" or event == "SUPER_TRACKING_CHANGED" then
		if event == "SUPER_TRACKING_CHANGED" then
			DropPinForTrackedQuest()
		end
		ReadWaypoint()
	elseif event == "QUEST_POI_UPDATE" or event == "QUEST_LOG_UPDATE" then
		if destination and destination.fromQuest then
			poiCache[destination.questID] = nil
		end
		if event == "QUEST_LOG_UPDATE" then
			M.logGen = M.logGen + 1   -- the objective places asked again (Route:ObjectivePlaces)
		end
	elseif event == "TAXIMAP_OPENED" then
		-- The routes are known a moment after the map opens; the
		-- flight-master help reads the map after Route learned it.
		C_Timer.After(0.2, LearnFlights)
		C_Timer.After(0.2, KnownFlightsHere)
		M.flight.openGen = M.flight.openGen + 1
		M.flight.HideHint()   -- (the buttons are the last map's until it is read)
		C_Timer.After(0.25, M.flight.Opened)
	elseif event == "PLAYER_CONTROL_GAINED" then
		M.flight.ControlGained()
	elseif event == "BAG_UPDATE_DELAYED" then
		Needed.BagsChanged()
	elseif event == "UNIT_FACTION" or event == "NEUTRAL_FACTION_SELECT_RESULT" then
		if event ~= "UNIT_FACTION" or Plain(unit) == "player" then
			M.SideChanged()
		end
	end
end)

local tickCount = 0
local function Tick()
	if not M.isEnabled then
		return
	end
	tickCount = tickCount + 1
	Record()
	-- a flight asked for or under way (the flight-master help's countdown)
	local flight = M.flight
	if flight.pending or flight.active then
		flight.Tick()
	end
	-- the 'where' topic, while someone wants it (Route:WantWhere)
	local where = M.whereWant
	if where.n > 0 and tickCount % where.EVERY == 0 then
		M.WhereTick()
	end
	if tickCount % 2 == 0 then
		ReadWaypoint()
		if destination then
			Plan(false)
			CheckArrival()
		end
		-- (user, 2026-09-24: nothing runs while nothing is routed) with no
		-- destination and no stand-in pin its only work was to ask where the
		-- player is, a new position table a second; what it would have
		-- concluded is kept: not on another continent
		if destination or standIn then
			StandIn.Update()
		else
			crossContinent = false
		end
		-- the bags heard only while a quest that needs an item is followed
		Needed.Listen(destination ~= nil and destination.gated)
	end
	if route and WorldMapFrame and WorldMapFrame:IsShown() then
		DrawWorldMap()   -- the line on the open map starts at the player (the route is kept now)
	end
end

SLASH_MELLOROUTE1 = "/route"
SlashCmdList.MELLOROUTE = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "dots" then
		-- what the painters draw (the kit gem or the game's dot), for the copy window
		MelloUI:ClearLog()
		for _, entry in ipairs({ { "map", mapPainter }, { "minimap", mmPainter } }) do
			local painter = entry[2]
			MelloUI:Print("%s painter: %s, used=%d, frame shown=%s alpha=%s", entry[1], painter and "yes" or "no", painter and painter.used or 0,
				painter and tostring(painter.frame:IsShown()) or "-", painter and tostring(painter.frame:GetAlpha()) or "-")
			for i = 1, math.min(3, painter and painter.used or 0) do
				local dot = painter.dots[i]
				local okT, tex = pcall(dot.GetTexture, dot)
				local okC, u1, _, _, _, _, _, u2, v2 = pcall(dot.GetTexCoord, dot)
				local r, g, b = dot:GetVertexColor()
				MelloUI:Print("  dot %d: tex=%s piece=%s uv=%s..%s,%s size=%.1f alpha=%.2f rgb=%.2f %.2f %.2f shown=%s layer=%s", i,
					okT and tostring(tex) or "?", tostring(dot.kitName), okC and string.format("%.2f", u1) or "?", okC and string.format("%.2f", u2) or "?",
					okC and string.format("%.2f", v2) or "?", dot:GetWidth() or 0, dot:GetAlpha() or 0, r or 0, g or 0, b or 0, tostring(dot:IsShown()), tostring(dot:GetDrawLayer()))
			end
		end
		MelloUI:Print("kit: %s", MelloUI.Kit and "yes" or "no")
		MelloUI:Print("module enabled=%s worldMap=%s minimap=%s provider=%s destination=%s route=%s (%d points) map shown=%s",
			tostring(M.isEnabled), tostring(M.db and M.db.worldMap), tostring(M.db and M.db.minimap), Provider and "yes" or "no",
			destination and (destination.label or "map pin") or "none", route and "yes" or "no", route and #route.points or 0,
			tostring(WorldMapFrame and WorldMapFrame:IsShown()))
		local okH, has = pcall(C_Map.HasUserWaypoint)
		MelloUI:Print("user waypoint=%s supertracking waypoint=%s", okH and tostring(has) or "?",
			C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and tostring(C_SuperTrack.IsSuperTrackingUserWaypoint()) or "?")
		MelloUI:ShowLog("route dots")
	elseif msg == "clear" then
		M.nav.Stop()   -- (a tracked quest's route stays stopped too)
		MelloUI:Print("Route cleared.")
	elseif msg == "reset confirm" then
		-- the traced roads are not learned data: they stay, counted afresh
		-- (before the graph is built: once it is, after what came before)
		Build.Queue(ForgetLearned)
		wipe(live.flights)   -- the flight times timed go too
		MelloUIRoutes = live
		M:Clear()
		-- (user, 2026-09-24: player words, no developer tools in what players read)
		MelloUI:Print("Learned paths wiped. The paths that come with MelloUI itself come back at the next /reload.")
	elseif msg == "record" and M.Recorder then
		-- (a developer tool, in no help line: the capitals' streets walked by
		-- hand, Modules/RouteRecorder.lua)
		M.Recorder.Open()
	elseif msg == "layers" then
		-- the world map's layers, low to high, and where the route sits
		local canvas = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
		if not canvas then
			MelloUI:Print("Open the world map first.")
		else
			local seen = {}
			for _, row in ipairs(CanvasLayers(canvas)) do
				local key = row[1] .. " " .. row[2] .. (row[3] and "  <- the route" or "")
				if not seen[key] then
					seen[key] = true
					print("   " .. key .. ((not row[3] and row[2] ~= "tiles" and IsArtLayer(row[2])) and "  (art: the route goes above)" or ""))
				end
			end
		end
	elseif msg == "quest" then
		local questID = TrackedQuestID()
		MelloUI:Print("Tracked quest: %s   (C_SuperTrack %s, GetSuperTrackedQuestID %s, watch index %s)", tostring(questID),
			tostring(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID ~= nil), tostring(GetSuperTrackedQuestID ~= nil),
			tostring(C_QuestLog and C_QuestLog.GetQuestIDForQuestWatchIndex ~= nil))
		local okM, playerMap = pcall(C_Map.GetBestMapForUnit, "player")
		playerMap = okM and Plain(playerMap) or nil
		print("   GetQuestsOnMap: " .. tostring(C_QuestLog and C_QuestLog.GetQuestsOnMap ~= nil) .. "   GetNextWaypoint: " .. tostring(C_QuestLog and C_QuestLog.GetNextWaypoint ~= nil) .. "   player map: " .. tostring(playerMap))
		if playerMap and C_QuestLog and C_QuestLog.GetQuestsOnMap then
			local ok, list = pcall(C_QuestLog.GetQuestsOnMap, playerMap)
			if ok and type(list) == "table" then
				print("   quests with a marker on your map: " .. #list)
				for i, info in ipairs(list) do
					if i > 6 then break end
					print(string.format("      quest %s at %.3f, %.3f", tostring(Plain(info.questID)), Plain(info.x) or -1, Plain(info.y) or -1))
				end
			else
				print("   GetQuestsOnMap failed: " .. tostring(list))
			end
		end
		if questID then
			-- (2026-10-04) the quest's lines as the game reports them, and the
			-- objective data Route has for it
			local okO, list = pcall(C_QuestLog.GetQuestObjectives, questID)
			for i, o in ipairs(okO and type(list) == "table" and list or {}) do
				print(string.format("   line %d (%s)%s: %s", i, tostring(Plain(o.type)), Plain(o.finished) and ", done" or "",
					tostring(Plain(o.text))))
			end
			for i, e in ipairs(ObjectivesOf(questID) or {}) do
				print(string.format("   data %d: kind %d, %s%s%s", i, e[1], e[2] ~= "" and e[2] or e[3],
					e.gates and string.format(", %d needed item%s", #e.gates, #e.gates == 1 and "" or "s") or "",
					e.made and ", made of them" or ""))
			end
			poiCache[questID] = nil
			local mapID, x, y = QuestObjectivePoint(questID)
			print(string.format("   objective marker: %s", mapID and string.format("map %d at %.3f, %.3f", mapID, x, y) or "none found"))
			-- (an item the bags must hold first: what the route follows meanwhile)
			for _, text in pairs(M:ItemFirst(questID) or {}) do
				print("   " .. text)
			end
			if destination and destination.fromQuest then
				print("   following it: " .. tostring(destination.label) .. (route and "" or " (no route drawn: within 60 yards, or no route found)"))
			else
				print("   not following it" .. (destination and " (a map pin has priority)" or ""))
			end
		end
	elseif msg == "pin" then
		M.PinReport()
	elseif msg == "reset" then
		MelloUI:Print("This wipes every learned path. Type  /route reset confirm  to do it.")
	else
		local nodes, edges = CountNodes()
		local taxiCount, usable = 0, 0
		RefreshDiscovered()
		for id, t in pairs(taxis or {}) do
			taxiCount = taxiCount + 1
			if TaxiUsable(id, t) then usable = usable + 1 end
		end
		-- No saved paths once the game has had its time to bring them (the
		-- first 90 s) means none were saved before (a first session, learning
		-- off, a reset), so say that, not "not loaded": only while the game
		-- may still bring them is it "not yet"
		MelloUI:Print("Route: %d learned points, %d traced road points, %d links, %d docks, %d flight points (%d usable)%s.",
			nodes - tracedNodes, tracedNodes, edges, docks and #docks or 0,
			taxiCount, usable, mergedSaved and ""
				or adoptTicker and " (paths learned in earlier sessions: the game has not brought them yet)"
				or " (none saved from earlier sessions)")
		if not Build.ready then
			-- (user, 2026-09-24) built on the first route, not at login
			print("   the road graph is built the first time a route is wanted: "
				.. (Build.job and "being built now" or string.format("not yet this session (%d learned changes waiting for it)", #Build.pending)))
		end
		if MelloUI.CompanionState then
			print("   road and quest objective data (MelloUI_Companion): " .. MelloUI:CompanionState())
		end
		local mineCount = 0
		for _ in pairs(CharFlights()) do
			mineCount = mineCount + 1
		end
		if mineCount > 0 then
			print(string.format("   flight points this character knows (from the flight masters' maps): %d", mineCount))
		elseif discovered then
			local n, sample = 0, {}
			for name in pairs(discovered.names) do
				n = n + 1
				if #sample < 4 then sample[#sample + 1] = name end
			end
			print(string.format("   no flight master opened yet; discovered flight points per the world map: %d (%s)", n, table.concat(sample, ", ")))
		else
			print("   no flight master opened yet on this character and the world map lists none: routes walk and sail until one is opened.")
		end
		if route then
			local roads = 0
			for _, p in ipairs(route.points) do
				if p[4] == "road" then roads = roads + 1 end
			end
			print(string.format("   current route: %s, about %d s, %d points (%d along learned paths).",
				Yards(route.length or 0), route.cost or 0, #route.points, roads))
		elseif destination then
			print("   destination set, no route found yet (other continent without a known crossing?).")
		else
			print("   no destination. Place a map pin, click a quest in the Quest List, or track a quest.")
		end
		if destination and destination.fromQuest then
			print("   following the tracked quest: " .. tostring(destination.label))
		end
		-- what is learned lives in the saved variables and is kept from one
		-- session to the next: said here as in the option's text (the reason
		-- a step was skipped only with learning on: off, it is always
		-- "learning is off", which the line already says)
		print(string.format("   learning %s: %d steps recorded this session%s; what is learned is saved and kept for your next session",
			M.db.learn and "on" or "off", recorded,
			M.db.learn and recordSkip ~= "" and (", the last one skipped: " .. recordSkip) or ""))
		do
			-- (0.14.0) the player's map and how Route places it; the flights timed
			local timed = 0
			for _ in pairs(live.flights) do
				timed = timed + 1
			end
			print("   " .. M.WhereWords())
			print(string.format("   flight times learned by timing your flights: %d", timed))
		end
		do
			-- (not before the graph is whole: the search's index would be built
			-- on half of it)
			local cont, px, py = PlayerYards()
			if cont and Build.ready then
				local near, n = NodesNear(cont, px, py, OFFROAD)
				local best = nil
				for _, d in pairs(near) do
					if not best or d < best then best = d end
				end
				local w, h = WorldSize(cont)
				print(string.format("   you: continent %d at %.0f, %.0f yards (world size %.0f x %.0f); nearest path point %s, %d within %d yd",
					cont, px, py, w, h, best and string.format("%.0f yd away", best) or "none", n, OFFROAD))
			end
		end
		if route and WorldMapFrame and WorldMapFrame:IsShown() then
			local shown = Plain(WorldMapFrame:GetMapID())
			local pts = route.points
			local a, b = pts[1], pts[#pts]
			local ax, ay = OnMap(shown, a[1], a[2], a[3])
			local bx, by = OnMap(shown, b[1], b[2], b[3])
			print(string.format("   shown map %s (continent %s): route start %s, end %s",
				tostring(shown), tostring(ContinentOf(shown)),
				ax and string.format("%.2f, %.2f", ax, ay) or "off this continent",
				bx and string.format("%.2f, %.2f", bx, by) or "off this continent"))
		end
		if mapFrame and mapPainter and mapPainter.dots[1] then
			local canvas = WorldMapFrame:GetCanvas()
			local above, top = 0, 0
			for _, child in ipairs({ canvas:GetChildren() }) do
				local lv = child:GetFrameLevel()
				if child ~= mapFrame and lv >= mapFrame:GetFrameLevel() and child:IsShown() then
					above = above + 1
				end
				if lv > top then top = lv end
			end
			local dot = mapPainter.dots[1]
			local cx, cy = dot:GetCenter()
			print(string.format("   route layer level %d (canvas %d, %d shown children at or above, highest %d); dot 1 at %s, visible %s, size %.0f, alpha %.2f",
				mapFrame:GetFrameLevel(), canvas:GetFrameLevel(), above, top,
				cx and string.format("%.0f, %.0f", cx, cy) or "nowhere", tostring(dot:IsVisible()), dot:GetWidth(), dot:GetAlpha()))
		end
		print(string.format("   world map %s, route layer %s, dots drawn %d, provider %s   |   minimap route %s, arrow %s",
			WorldMapFrame and WorldMapFrame:IsShown() and "open" or "closed",
			mapFrame and string.format("%dx%d", mapFrame:GetWidth(), mapFrame:GetHeight()) or "not created",
			mapPainter and mapPainter.used or 0, tostring(Provider ~= nil),
			mmPainter and tostring(mmPainter.used) or "none", arrow and arrow:IsShown() and "shown" or "hidden"))
		print("   /route clear   |   /route reset   |   /route dots")
	end
end

function M:OnInit(db)
	self.db = db
	-- (the Direction Arrow became a row of the widget column, 2026-10-03: its
	-- old place and size keys go)
	db.arrowX, db.arrowY, db.arrowScale = nil, nil, nil
end

function M:OnEnable(db)
	self.db = db
	LoadBaked()
	AdoptSaved()
	BuildDocks()
	BuildTaxis()
	CreateProvider()
	EnsureMinimapFrame()
	EnsureArrow()
	EnsureMarker()
	-- (a profile brought in: the Text Shade as it says; nothing at login)
	TextShade.Apply()
	MelloUI:On("setting", TextShade.OnSetting, "Route text shade")
	MelloUI.Look.Watch(M, Beacon.OnLook)   -- (the reskin off: the game's art for the marks)
	-- (user, 2026-09-24: nothing runs while nothing is routed) the minimap
	-- tick sleeps with its frame: mm is made hidden and shown by Redraw only
	-- while there is a destination, and a hidden frame's OnUpdate never runs.
	-- Every way a destination comes or goes (the map pin, the tracked quest,
	-- SetDestinationTo for the Quest List, the Services bar and /services,
	-- arrival, /route clear, switching Route off) ends in Redraw.
	if mm and not mm.ticking then
		mm.ticking = true
		Perf.SetScript(mm, "OnUpdate", MinimapTick)
	end
	eventFrame:RegisterEvent("PLAYER_LOGOUT")
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	pcall(eventFrame.RegisterEvent, eventFrame, "USER_WAYPOINT_UPDATED")
	pcall(eventFrame.RegisterEvent, eventFrame, "SUPER_TRACKING_CHANGED")
	pcall(eventFrame.RegisterEvent, eventFrame, "TAXIMAP_OPENED")
	pcall(eventFrame.RegisterEvent, eventFrame, "QUEST_POI_UPDATE")
	pcall(eventFrame.RegisterEvent, eventFrame, "QUEST_LOG_UPDATE")
	-- a faction chosen (M.SideChanged): only the events this client has (a
	-- RegisterEvent of an unknown one raises), the unit's for the player alone
	pcall(eventFrame.RegisterEvent, eventFrame, "NEUTRAL_FACTION_SELECT_RESULT")
	if eventFrame.RegisterUnitEvent then
		pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_FACTION", "player")
	else
		pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_FACTION")
	end
	if not ticker then
		ticker = C_Timer.NewTicker(0.5, Tick)
	end
	-- back on: the owners of 'where' still wanting it hear the place again
	-- at the next 4th tick, standing still or not
	M.whereWant.fired = false
	if not adoptTicker and not mergedSaved then
		local polls = 0
		adoptTicker = C_Timer.NewTicker(2, function(t)
			polls = polls + 1
			if AdoptSaved() or polls >= 45 then
				t:Cancel()
				adoptTicker = nil
			end
		end)
	end
	ReadWaypoint()
	-- A destination kept while Route was off (the same pin: ReadWaypoint has
	-- nothing new to read) is drawn now; the minimap slept until the next
	-- plan, a second or more. With none there is nothing to draw: skipped,
	-- so an idle login does no extra work.
	if destination then
		Redraw()
	end
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	Needed.listening = false
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	M.flight.Stop()
	route = nil
	StandIn.Update()
	Redraw()
	UpdateMarker()
	Build.Loaded()   -- (a load under way: its line and the arrow's working look go)
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "worldMarker" then
		StandIn.Update()
	elseif key == "trailLook" then
		Beacon.Tint()   -- (the World Marker's light and flag in the new look; the maps' at the redraw)
	end
	M.flight.Setting(key)
	Redraw()
	if marker then
		marker.lastX = nil   -- (the marker's parts looked at again at its next tick)
	end
	UpdateMarker()
	Build.ArrowWork()   -- (while the roads go in: the arrow's working look as the settings say)
end

MelloUI:Profile("Route", "breadcrumbs + planning tick", Tick)
MelloUI:Profile("Route", "minimap drawing", MinimapTick)
MelloUI:Profile("Route", "world map drawing", DrawWorldMap)

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
-- Persistence: this client keeps saved variables only in memory across
-- /reload and drops them at restart, but it does write the file. The graph
-- is therefore saved as MelloUIRoutes and baked by Tools\bake_routes.py into
-- Media\RouteData.lua, which the addon loads like any other file.
--
-- The traced roads and the quest objective places are the MelloUI_Companion
-- addon's (loaded on demand, Core\Companions.lua), and the graph is built the
-- first time a route is wanted, a couple of milliseconds a frame, not at
-- login (user, 2026-09-24): see "Building the graph" below.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Route")
local hooksecurefunc, C_Timer = Perf.hooksecurefunc, Perf.C_Timer

local M = MelloUI:RegisterModule("Route", {
	title = "Route",
	desc = "Draws the way to your map waypoint on the world map and the minimap, along roads you have walked before.",
	icon = "Interface\\Icons\\Ability_Tracking",
	flavour = "A trail of gems from here to there, along the roads you have walked before.",
	group = "Quests and travel",
	keep = { "^flights_" },   -- each character's own flight points (CharFlightsKey): never in a profile, never wiped by one
	enabledByDefault = true,
	defaults = {
		worldMap = true,
		minimap = true,
		distanceText = true,
		learn = true,
		trackQuests = true,
		trackFirstWatched = false,
		arrow = true,
		arrowScale = 1,
		worldMarker = true,
		routeBeam = true,
		notice = true,
		noticeSound = true,
		lineWidth = 3,
		arrive = 25,
	},
	options = {
		{ type = "header", name = "Drawing" },
		{ type = "toggle", key = "worldMap", name = "Route On The World Map",
		  desc = "Draw the route to the waypoint on the world map. Blue where it follows paths you have walked, orange where it is a straight guess." },
		{ type = "toggle", key = "minimap", name = "Route On The Minimap",
		  desc = "Draw the nearby part of the route on the minimap." },
		{ type = "slider", key = "lineWidth", name = "Route Dot Size", min = 1, max = 8, step = 1,
		  desc = "Size of the gems that mark the route on the world map and the minimap." },
		{ type = "toggle", key = "trackQuests", name = "Route To The Tracked Quest",
		  desc = "When no map pin is set, route to the quest you are tracking (the one with the arrow): to the nearest place for an objective you have not finished yet (a creature to kill, an object to use, where the item drops or is sold, a place to explore), and to its turn-in once it is complete." },
		{ type = "toggle", key = "trackFirstWatched", parent = "trackQuests", name = "Fall Back To The First Tracked Quest",
		  desc = "When nothing is super-tracked, follow the first quest in the objective tracker instead of showing nothing." },
		{ type = "toggle", key = "distanceText", name = "Distance Under The Minimap",
		  desc = "Show the remaining route length under the minimap (hidden while the arrow is shown)." },
		{ type = "toggle", key = "arrow", name = "Direction Arrow",
		  desc = "An arrow that points along the route's next leg, with the distance and destination. Drag it to move it; /route arrow reset puts it back at the top centre." },
		{ type = "slider", key = "arrowScale", parent = "arrow", name = "Arrow Size", min = 0.5, max = 2, step = 0.1 },
		{ type = "toggle", key = "worldMarker", name = "World Marker",
		  desc = "A gem over the destination itself, with the distance, that stays on it as you move the camera; when the place is off screen, an arrow at the screen's edge points the way to turn. Takes the place of the game's own destination marker while it is on." },
		{ type = "toggle", key = "routeBeam", parent = "worldMarker", name = "Light Beam",
		  desc = "A red beam of light rising from the destination into the sky, so the place can be seen from far away. It fades as you arrive and hides while the place is off screen. Part of the World Marker." },
		{ type = "header", name = "Arrival" },
		{ type = "toggle", key = "notice", name = "Tracking Notice",
		  desc = "A one-line notice in the upper third of the screen whenever something new is tracked, and when you arrive." },
		{ type = "toggle", key = "noticeSound", parent = "notice", name = "Notice Sound",
		  desc = "A short chime with the notice: the map's super-track sound for a new destination, a soft tick otherwise." },
		{ type = "slider", key = "arrive", name = "Arrived Within (yards)", min = 10, max = 100, step = 5,
		  desc = "The route ends and the waypoint is cleared when you get this close." },
		{ type = "header", name = "Learning" },
		{ type = "toggle", key = "learn", name = "Learn Paths While Playing",
		  desc = "Remember where you walk and fly so routes can follow real roads. What it learns is kept until you quit the game: this version of the game forgets it when it restarts (a /reload keeps it). /route shows how much has been learned." },
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

-- Continent map sizes in yards, when C_Map.GetMapWorldSize is missing.
local WORLD_SIZE = { [1414] = { 36799.8, 24533.2 }, [1415] = { 40741.2, 27149.7 }, [12] = { 36799.8, 24533.2 }, [13] = { 40741.2, 27149.7 } }

local contCache, rectCache, sizeCache = {}, {}, {}

-- The continent map above a map, walking up the parents.
local function ContinentOf(mapID)
	if not mapID then
		return nil
	end
	local cached = contCache[mapID]
	if cached then
		return cached
	end
	local id = mapID
	for _ = 1, 6 do
		local ok, info = pcall(C_Map.GetMapInfo, id)
		if not ok or type(info) ~= "table" then
			break
		end
		if Plain(info.mapType) == MAP_CONTINENT then
			contCache[mapID] = id
			return id
		end
		id = Plain(info.parentMapID)
		if not id or id == 0 then
			break
		end
	end
	return nil
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
		if not (w and h and w > 0 and h > 0) then
			local f = WORLD_SIZE[cont]
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
-- its role and the game font object it starts from: the Fonts module gives
-- the role's face, its size slider and the Outline, on top of the text's own
-- base size and flags, and calls back whenever any of them changes. Off, or
-- a role on "Keep the game's", a text keeps its own face exactly as before.
-- A table, not more locals: this file's main chunk is near Lua's limit.
--------------------------------------------------------------------------------

local RouteFont = {}
do
	local styled = {}   -- [fontString] = { role, object, size, flags }
	local listening = false

	local function Fonts()
		local fonts = MelloUI:GetModule("Fonts")
		return (fonts and fonts.FaceFor) and fonts or nil
	end

	-- The face, size and flags a text has without the Fonts module: its game
	-- font object's own, with the text's own size and flags where it sets them
	local function Base(entry, fonts)
		local path, size, flags
		if fonts and fonts.BaseFont then
			path, size, flags = fonts:BaseFont(entry.object)
		end
		if not path then
			local ok, p, s, f = pcall(entry.object.GetFont, entry.object)
			if ok then
				path, size, flags = p, s, f
			end
		end
		return path, entry.size or tonumber(Plain(size)), entry.flags or flags or ""
	end

	local function Apply(fs, entry)
		local fonts = Fonts()
		local basePath, baseSize, baseFlags = Base(entry, fonts)
		if not (basePath and baseSize) then
			return
		end
		local path, factor, flags = basePath, 1, baseFlags
		if fonts then
			path, factor, flags = fonts:FaceFor(entry.role, basePath, baseFlags)
		end
		factor = tonumber(factor) or 1
		-- the base size as it is at 100%, so the module off changes nothing
		local size = baseSize
		if math.abs(factor - 1) > 0.001 then
			size = math.max(6, math.floor(baseSize * factor + 0.5))
		end
		-- a face the client cannot load (a font file gone) leaves the text on its own
		local ok, set = pcall(fs.SetFont, fs, path or basePath, size, flags or "")
		if not ok or set == false then
			pcall(fs.SetFont, fs, basePath, size, flags or "")
		end
	end

	function RouteFont.Refresh()
		for fs, entry in pairs(styled) do
			Apply(fs, entry)
		end
	end

	-- fs follows the Fonts module's role ("fontText", "fontChat", ...), from
	-- the game font object it was made with; size and flags, when given,
	-- replace the object's own as the text's base.
	function RouteFont.Style(fs, role, object, size, flags)
		if not (fs and object) then
			return
		end
		styled[fs] = { role = role, object = object, size = size, flags = flags }
		-- the Fonts module loads first (MelloUI.toc), but ask only now: the
		-- texts are made on first use, and one listener serves them all
		if not listening then
			local fonts = Fonts()
			if fonts and fonts.OnFontsChanged then
				listening = true
				fonts:OnFontsChanged(RouteFont.Refresh)
			end
		end
		Apply(fs, styled[fs])
	end
end

--------------------------------------------------------------------------------
-- Tracking notice
--
-- One line of large orange text in the upper third of the screen, held for a
-- few seconds and faded out, with a chime from the client's own sound kit.
-- Every module that sets a destination gets it through M:Notify.
--------------------------------------------------------------------------------

local notice = nil
local NOTICE_HOLD, NOTICE_FADE = 4, 1.5
local SOUNDS = {
	track = { "UI_MAP_WAYPOINT_SUPER_TRACK_ON", "UI_MAP_WAYPOINT_CLICK_TO_PLACE", "IG_QUEST_LIST_OPEN" },
	fail = { "UI_MAP_WAYPOINT_REMOVE", "IG_QUEST_LOG_ABANDON_QUEST", "IG_MAINMENU_OPTION_CHECKBOX_OFF" },
	learn = { "UI_MAP_WAYPOINT_CLICK_TO_PLACE", "IG_MAINMENU_OPTION_CHECKBOX_ON" },
	arrive = { "UI_MAP_WAYPOINT_SUPER_TRACK_OFF", "IG_QUEST_LIST_COMPLETE", "IG_MAINMENU_OPTION_CHECKBOX_ON" },
}

local function EnsureNotice()
	if notice then
		return notice
	end
	notice = CreateFrame("Frame", "MelloUIRouteNotice", UIParent)
	notice:SetSize(900, 40)
	notice:SetPoint("TOP", UIParent, "TOP", 0, -180)
	notice:SetFrameStrata("HIGH")
	notice.text = notice:CreateFontString(nil, "OVERLAY")
	local font = _G.GameFont_Gigantic or _G.NumberFont_Outline_Huge or _G.GameFontNormalHuge3 or _G.GameFontNormalHuge
	if font then
		notice.text:SetFontObject(font)
		-- its own look (20, outlined) in the interface text's face and size:
		-- the base is the object's face and the sizes are in its terms, which
		-- the title faces' factors are not (they are set against Morpheus)
		RouteFont.Style(notice.text, "fontText", font, 20, "OUTLINE")
	end
	notice.text:SetPoint("CENTER")
	notice.text:SetWidth(900)
	notice.text:SetJustifyH("CENTER")
	notice.text:SetWordWrap(false)
	notice.text:SetTextColor(1, 0.5, 0)
	notice.text:SetShadowOffset(2, -2)
	notice.text:SetShadowColor(0, 0, 0, 0.9)
	notice:Hide()
	notice.holds = 0
	return notice
end

-- Held by a timer, then faded out by the Anim engine, which ends the fade at
-- once under Reduce Motion (audit, 2026-09-24: its own OnUpdate ran the whole
-- five and a half seconds). Every notice starts one hold; the last one to
-- run out fades what is shown then.
local function NoticeHide(frame)
	frame:Hide()
end
local function NoticeFade()
	notice.holds = notice.holds - 1
	if notice.holds > 0 or not notice:IsShown() then
		return
	end
	if MelloUI.Anim then
		MelloUI.Anim:To(notice, "alpha", 0, NOTICE_FADE, "linear", NoticeHide)
	else
		notice:Hide()
	end
end

local function PlayNotice(kind)
	if kind == "silent" or not (M.db.noticeSound and PlaySound and SOUNDKIT) then
		return
	end
	for _, name in ipairs(SOUNDS[kind] or SOUNDS.track) do
		local id = SOUNDKIT[name]
		if id then
			local ok, played = pcall(PlaySound, id, "Master")
			if ok and played ~= false then
				return
			end
		end
	end
end

-- kind: "track" (new destination), "arrive", "learn", "fail", "silent" (no chime).
function M:Notify(text, kind)
	if not M.db.notice then
		return
	end
	local frame = EnsureNotice()
	frame.text:SetText(text)
	if MelloUI.Anim then
		MelloUI.Anim:Stop(frame, "alpha")   -- one fading out comes back
	end
	frame:SetAlpha(1)
	frame:Show()
	frame.holds = frame.holds + 1
	C_Timer.After(NOTICE_HOLD, NoticeFade)
	PlayNotice(kind or "track")
end

-- Distance to the current destination for the notices: the route's length
-- when there is one, else the straight line.
local DestinationDistance -- defined with the route state below

--------------------------------------------------------------------------------
-- The graph
--
-- live.graphs[continent][key] = { x, y, { [otherKey] = cost } }, key = cell.
--------------------------------------------------------------------------------

local live = { graphs = {}, pins = { entrances = {}, transports = {} } }
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

-- The learned part of the graph: what the saved variable and the baker keep.
local function LearnedOnly()
	local out = { graphs = {}, pins = live.pins }
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

local function YardsOfWorld(wcont, wx, wy)
	local key = wcont .. ":" .. wx .. ":" .. wy
	local c = worldYards[key]
	if c then
		if c == false then
			return nil
		end
		return c[1], c[2], c[3]
	end
	if not (C_Map.GetMapPosFromWorldPos and CreateVector2D) then
		return nil
	end
	local ok, contMapID, pos = pcall(C_Map.GetMapPosFromWorldPos, wcont, CreateVector2D(wx, wy))
	contMapID = ok and Plain(contMapID) or nil
	local cx, cy = VectorXY(pos)
	if not (contMapID and cx and cy) then
		return nil   -- not cached: the client may answer later (as RectOn does)
	end
	local w, h = WorldSize(contMapID)
	worldYards[key] = { contMapID, cx * w, cy * h }
	return contMapID, cx * w, cy * h
end

local function PlayerFactionCode()
	return UnitFactionGroup("player") == "Horde" and 2 or 1
end

local function BuildDocks()
	docks = {}
	edits.hubs = edits.hubs + 1
	local data = MelloUI_QuestListData
	if type(data) ~= "table" or type(data.transports) ~= "table" then
		return
	end
	local mine = PlayerFactionCode()
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
	local mine = PlayerFactionCode()
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
-- as a Route setting, so the macro backup carries them across restarts.
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

	-- Neighbourhood links of a fixed hub (dock, flight point), kept until a
	-- node is added near it (memory audit, 2026-09-24: every new node threw
	-- all of them away)
	local hubNear, hubAt = {}, {}   -- [id] = its NodesNear, [id] = { cont, x, y } it was taken at
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
				hubNear[id], hubAt[id] = nil, nil
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

	-- A link far quicker than walking is a flight (learned at a flight master,
	-- maybe by another character)
	local function IsFlight(node, o, cost)
		local d = Dist(node[1], node[2], o[1], o[2])
		return d > FLIGHT_LINK_MIN and cost < d / WALK * 0.5
	end

	-- The working tables, kept from one search to the next and wiped. They
	-- keep the size of the biggest search since, so they are let go once no
	-- search has run for SCRATCH_IDLE seconds, or SCRATCH_IDLE_BIG after one
	-- that expanded more than SCRATCH_KEEP nodes (2-4 MB for a road across a
	-- continent): the memory is only held while it is saving garbage. Graph
	-- nodes go by their own table; the start ("S"), the goal ("G"), docks
	-- ("D<i>"), flight points ("T<id>") and a link to a cell with no node
	-- ("c|key") by string.
	local SCRATCH_KEEP, SCRATCH_IDLE, SCRATCH_IDLE_BIG = 500, 20, 4
	local gScore, from, closed = {}, {}, {}   -- per node: cost so far, the node before, expanded
	local heapId, heapF, heapCont, heapN = {}, {}, {}, 0   -- binary heap keyed by f
	local extra, nodeExtra, pos = {}, {}, {}   -- id -> { otherId = cost }, graph node -> its extra, id -> { cont, x, y }
	local flightEnds = {}   -- [node] = a flight point this character may use is at it
	local sBase, sFrom          -- the node being expanded: its cost so far, itself
	local sGoalCont, sGoalX, sGoalY, sSpeed, sHx, sHy   -- the goal, the estimate's speed, the heading
	local lastSearch, releaseQueued, scratchBig = 0, false, false
	-- [scont][gcont] = { hub edits, other continents' edits } of a search that found no way
	local failed = {}

	local function ReleaseIfIdle()
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
		local id, cont = heapId[1], heapCont[1]
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
		return id, cont
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
		if cont ~= sGoalCont then
			return 0
		end
		return Dist(x, y, sGoalX, sGoalY) / sSpeed
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

	local function LinkPoint(id, cont, x, y, cached)
		local near = cached and HubNear(id, cont, x, y) or NodesNear(cont, x, y, OFFROAD)
		local g = live.graphs[cont]
		for key, d in pairs(near) do
			local cost = d / WALK * 1.3
			local node = g and g[key]
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
	end

	-- a straight leg from the start or to the goal to a dock / flight point:
	-- a short hop as walking, a long one only as a last resort
	local function HubLeg(d)
		if d <= OFFROAD then
			return d / WALK * 1.3
		end
		return d / WALK * FAR_HUB_COST
	end

	-- The start, the goal, the docks and the flight points, linked to the
	-- graph and to each other
	local function Begin(scont, sx, sy, gcont, gx, gy, hx, hy)
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
		SetPos("G", gcont, gx, gy)
		LinkPoint("S", scont, sx, sy)
		LinkPoint("G", gcont, gx, gy)
		for i, d in ipairs(docks or {}) do
			local id = "D" .. i
			SetPos(id, d.cont, d.x, d.y)
			LinkPoint(id, d.cont, d.x, d.y, true)
			if d.pair then
				AddExtra(id, "D" .. d.pair, BOAT_COST)
			end
			if d.cont == scont then
				AddExtra("S", id, HubLeg(Dist(d.x, d.y, sx, sy)))
			end
			if d.cont == gcont then
				AddExtra("G", id, HubLeg(Dist(d.x, d.y, gx, gy)))
			end
		end
		for id, t in pairs(taxis or {}) do
			if TaxiUsable(id, t) then
				local nid = "T" .. id
				SetPos(nid, t.cont, t.x, t.y)
				LinkPoint(nid, t.cont, t.x, t.y, true)
				for other, secs in pairs(t.links) do
					if taxis[other] and TaxiUsable(other, taxis[other]) then
						AddExtra(nid, "T" .. other, secs)
					end
				end
				if t.cont == scont then
					AddExtra("S", nid, HubLeg(Dist(t.x, t.y, sx, sy)))
				end
				if t.cont == gcont then
					AddExtra("G", nid, HubLeg(Dist(t.x, t.y, gx, gy)))
				end
			end
		end
		if scont == gcont then
			AddExtra("S", "G", Dist(sx, sy, gx, gy) / WALK * STRAIGHT_COST)
		end
		-- the estimate at the fastest way this character can travel: flying
		-- only with a usable flight point on the goal's continent, else walking
		-- (a far tighter estimate: the long road searches finish)
		local speed = WALK
		for tid, t in pairs(taxis or {}) do
			if t.cont == gcont and TaxiUsable(tid, t) then
				speed = FLIGHT
				break
			end
		end
		sGoalCont, sGoalX, sGoalY, sSpeed = gcont, gx, gy, speed
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
				if not (o and IsFlight(id, o, cost)) or (FlightEnd(cont, id) and FlightEnd(cont, o)) then
					Relax(o or (cont .. "|" .. k), cont, cost)
				end
				degree = degree + 1
			end
			if degree <= 1 then
				-- the end of a path: cross open ground to any path nearby
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
		lastSearch = GetTime()
		if not releaseQueued then
			releaseQueued = true
			C_Timer.After(SCRATCH_IDLE_BIG, ReleaseIfIdle)
		end
		Begin(scont, sx, sy, gcont, gx, gy, hx, hy)
		gScore.S = 0
		Push("S", Heuristic("S"), scont)
		local expanded = 0
		while true do
			local id, cont = Pop()
			if not id then
				scratchBig = scratchBig or expanded > SCRATCH_KEEP
				if others then
					failed[scont] = failed[scont] or {}
					failed[scont][gcont] = { edits.hubs, others }
				end
				return nil
			end
			if id == "G" then
				break
			end
			if not closed[id] then
				closed[id] = true
				expanded = expanded + 1
				if expanded > 60000 then
					scratchBig = true
					return nil
				end
				Expand(id, cont)
			end
		end
		scratchBig = scratchBig or expanded > SCRATCH_KEEP
		return Path()
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
		wipe(failed)
		jumpNear = {}
	end
end

--------------------------------------------------------------------------------
-- Current route
--------------------------------------------------------------------------------

local route = nil        -- { points = {...}, cost = seconds, length = yards, dest = { cont, x, y } }
local destination = nil  -- { cont, x, y, mapID, mx, my, label }
-- The stand-in (see "Another continent"): the map pin on the dock where the
-- route leaves the player's continent while the destination is on another.
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

-- Say what is tracked now; `text` overrides the standard sentence.
local function Announce(text)
	if not destination then
		return
	end
	local d = DestinationDistance()
	local where = d and (", " .. Yards(d) .. " away") or ""
	if text then
		text = text:gsub("{dist}", d and Yards(d) or "?")
	end
	M:Notify(text or ("Tracking " .. (destination.label or "map pin") .. where), "track")
end

local function Plan(force, announce, announceText)
	if not destination then
		route = nil
		Redraw()
		return
	end
	local now = GetTime()
	if not force then
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
		return
	end
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
	local hx, hy = Heading(cont)
	local points, cost = FindRoute(cont, x, y, d.cont, d.x, d.y, hx, hy)
	if points and #points == 2 and cont == d.cont then
		-- the direct line won: its real walking time, not the price that made roads compete
		cost = Dist(x, y, d.x, d.y) / WALK
	end
	if points and cont == d.cont then
		-- A silly detour is worse than a straight guess.
		local beeline = Dist(x, y, d.x, d.y)
		if cost > beeline / WALK * 3 + 60 then
			points, cost = nil, nil
		end
	end
	if not points and cont == d.cont then
		points = { { cont, x, y, "guess" }, { d.cont, d.x, d.y, "guess" } }
		cost = Dist(x, y, d.x, d.y) / WALK
	end
	if points then
		route = { points = points, cost = cost, length = RouteLength(points), dest = { d.cont, d.x, d.y } }
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
--------------------------------------------------------------------------------

local OBJECTIVE_RECHECK = 8     -- seconds between choosing again
local OBJECTIVE_PRICED = 3      -- the nearest this many places are priced by route
local objectiveChoice = {}      -- [questID] = { sig, at, cont, x, y, name }

-- A quest's entries, { { kind, name, alt, map, x1, y1, x2, y2, ... }, ... },
-- or nil. The data keeps each quest as one packed string (memory audit,
-- 2026-09-24: as tables it held 1.7 MB, nearly all of it places of quests
-- never tracked, and made as much again in garbage while loading); a quest's
-- is decoded when it is asked for, and the last few are kept, as the tracked
-- one is asked for again every few seconds.
local ObjectivesOf
do
	local KEPT = 4                  -- decoded quests kept
	local decoded, order = {}, {}   -- [questID] = its entries; the questIDs, oldest first
	-- a coordinate is three characters, base 64 with the digits "0" (48) to
	-- "o" (111), holding the value plus 131072 (Tools/build_quest_objectives.py)
	local BIAS = (48 * 64 + 48) * 64 + 48 + 131072

	-- "<kind><map><name>|<alt>|<x1><y1><x2><y2>...~" for each objective
	local function Decode(packed)
		local list = {}
		for kind, wmap, name, alt, coords in packed:gmatch("(%d)(%d)([^|]*)|([^|]*)|([^~]*)~") do
			local entry, n = { tonumber(kind), name, alt, tonumber(wmap) }, 4
			for i = 1, #coords - 2, 3 do
				local a, b, c = coords:byte(i, i + 2)
				n = n + 1
				entry[n] = (a * 64 + b) * 64 + c - BIAS
			end
			list[#list + 1] = entry
		end
		return list
	end

	function ObjectivesOf(questID)
		local list = decoded[questID]
		if list then
			return list
		end
		local packed = MelloUI_QuestObjectiveData and MelloUI_QuestObjectiveData[questID]
		if type(packed) ~= "string" then
			return nil
		end
		list = Decode(packed)
		decoded[questID] = list
		order[#order + 1] = questID
		if #order > KEPT then
			decoded[table.remove(order, 1)] = nil
		end
		return list
	end
end

-- The data's entries still to do: each { kind, name, points }, and a
-- signature of the open objectives (a new choice when it changes)
local function OpenObjectives(questID)
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
	local texts, open = {}, {}
	if C_QuestLog and C_QuestLog.GetQuestObjectives then
		local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
		if ok and type(list) == "table" then
			for _, o in ipairs(list) do
				local text = Plain(o.text)
				if text then
					texts[#texts + 1] = { text:lower(), Plain(o.finished) and true or false }
				end
			end
		end
	end
	local function Match(name)
		if not name or name == "" then
			return nil
		end
		name = name:lower()
		for _, t in ipairs(texts) do
			if t[1]:find(name, 1, true) then
				return t
			end
		end
		return nil
	end
	local anyMatched, sig = false, {}
	for i, entry in ipairs(data) do
		local kind = entry[1]
		local t = Match(entry[2]) or Match(entry[3])
		if t then
			anyMatched = true
			if not t[2] then
				open[#open + 1] = entry
				sig[#sig + 1] = i
			end
		elseif kind == 4 then
			-- an exploration objective has no line of its own: open until
			-- the quest is complete
			open[#open + 1] = entry
			sig[#sig + 1] = i
		end
	end
	-- no line matched a name at all (another language, a renamed creature):
	-- every place of the quest rather than none
	if not anyMatched and #open == 0 and #texts > 0 then
		for i, entry in ipairs(data) do
			open[#open + 1] = entry
			sig[#sig + 1] = i
		end
	end
	if #open == 0 then
		return nil
	end
	return open, table.concat(sig, ",")
end

-- The place to go for the quest's open objectives: continent yards and the
-- objective's name, or nil; nil and then true while the places cannot be
-- priced yet (the graph not built)
local function ObjectiveSpot(questID)
	local open, sig = OpenObjectives(questID)
	if not open then
		objectiveChoice[questID] = nil
		return nil
	end
	local c = objectiveChoice[questID]
	if c and c.sig == sig and GetTime() - c.at < OBJECTIVE_RECHECK then
		return c.cont, c.x, c.y, c.name
	end
	local pcont, px, py = PlayerYards()
	if not pcont then
		return c and c.cont, c and c.x, c and c.y, c and c.name
	end
	-- every place on the player's continent, nearest first
	local near = {}
	for _, entry in ipairs(open) do
		local wmap = entry[4]
		for i = 5, #entry - 1, 2 do
			local cont, x, y = YardsOfWorld(wmap, entry[i], entry[i + 1])
			if cont == pcont then
				near[#near + 1] = { d = Dist(px, py, x, y), cont = cont, x = x, y = y, wmap = wmap, wx = entry[i], wy = entry[i + 1],
					name = (entry[2] ~= "" and entry[2]) or (entry[3] ~= "" and entry[3]) or nil }
			end
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
	objectiveChoice[questID] = { sig = sig, at = GetTime(), cont = pick.cont, x = pick.x, y = pick.y, name = pick.name }
	return pick.cont, pick.x, pick.y, pick.name
end

local function ReadTrackedQuest()
	if destination and not destination.fromQuest and not destination.fromWaypoint then
		return
	end
	local questID
	if M.db.trackQuests then
		questID = TrackedQuestID()
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
	local ocont, ox, oy, oname, later = ObjectiveSpot(questID)
	if later then
		return   -- chosen by route once the roads are in; nothing changes until then
	end
	if ocont then
		local same = destination and destination.fromQuest and destination.questID == questID
		if same and destination.cont == ocont and Dist(destination.x, destination.y, ox, oy) < 1 then
			return
		end
		local title
		if C_QuestLog and C_QuestLog.GetTitleForQuestID then
			local ok, t = pcall(C_QuestLog.GetTitleForQuestID, questID)
			title = ok and Plain(t) or nil
		end
		destination = { cont = ocont, x = ox, y = oy, fromQuest = true, questID = questID, objective = oname,
			label = "|A:QuestNormal:16:16|a " .. (oname or title or "quest") }
		-- announced once per quest, not at every next spawn
		Plan(true, not same, "|A:QuestNormal:22:22|a  Tracking quest " .. (title or "") .. (oname and (": " .. oname) or "") .. ", {dist} away")
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
		return
	end
	local title
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local ok, t = pcall(C_QuestLog.GetTitleForQuestID, questID)
		title = ok and Plain(t) or nil
	end
	destination = { cont = cont, x = x, y = y, mapID = mapID, mx = px, my = py, fromQuest = true, questID = questID,
		label = "|A:QuestNormal:16:16|a " .. (title or "quest") }
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
		return
	end
	destination = { cont = cont, x = x, y = y, mapID = mapID, mx = px, my = py, fromWaypoint = true,
		label = "|A:Waypoint-MapPin-ChatIcon:16:16|a map pin" }
	Plan(true, true)
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
-- Marker is switched off. Removing the stand-in pin ends it like any pin.
-- Kept in the saved settings, so a reload on the way still gives it back.
--------------------------------------------------------------------------------

-- in a block: its helpers stay out of the main chunk's 200 locals
do
	local STAND_IN_MOVE = 30   -- yards: a new exit dock this far from the pin moves it

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
		if s.questID and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
			if securecallfunction then
				securecallfunction(C_SuperTrack.SetSuperTrackedQuestID, s.questID)
			else
				pcall(C_SuperTrack.SetSuperTrackedQuestID, s.questID)
			end
		end
		if C_Map.ClearUserWaypoint then
			pcall(C_Map.ClearUserWaypoint)
		end
	end

	local function PlaceStandIn(dock, label)
		local mapID, mx, my = MapPointOfYards(dock[1], dock[2], dock[3])
		local before = standIn
		local s = { cont = dock[1], x = dock[2], y = dock[3],
			label = "|A:Waypoint-MapPin-ChatIcon:16:16|a " .. (label or "the boat") }
		if before then
			s.pin, s.questID = before.pin, before.questID
		else
			-- what to give back: the pin there was (the player's own), the quest tracked
			local cont, _, _, pm, px, py = WaypointYards()
			if cont then
				s.pin = { pm, px, py }
			end
			s.questID = destination.fromQuest and destination.questID or nil
		end
		-- known before the pin is set: its USER_WAYPOINT_UPDATED reads it
		standIn = s
		if not SetPin(mapID, mx, my) then
			standIn = before
			return
		end
		SaveStandIn({ cont = s.cont, x = s.x, y = s.y, pin = s.pin, questID = s.questID })
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
		-- the stand-in pin removed or replaced (by the player): no longer ours
		if standIn and not IsPlace(standIn, WaypointYards()) then
			EndStandIn(false)
		end
		local want = crossContinent and M.isEnabled and M.db.worldMarker
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

	-- The route cleared: the stand-in on the dock goes with it
	StandIn.Drop = function()
		local s = standIn
		if s then
			EndStandIn(false)
			if IsPlace(s, WaypointYards()) and C_Map.ClearUserWaypoint then
				pcall(C_Map.ClearUserWaypoint)
			end
		end
	end
end

-- Route to a candidate; with `pin`, also place the map waypoint there so the
-- map and the waypoint arrow show it (removing the pin ends the route).
function M:SetDestinationTo(candidate, label, pin, noticeText)
	local cont, x, y = CandidateYards(candidate)
	if not cont then
		return false
	end
	local mapID, mx, my = candidate.mapID, candidate.x, candidate.y
	if not mapID then
		mapID, mx, my = MapPointOfYards(cont, x, y)
	end
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
function M:DistanceTo(candidate)
	local pcont, px, py = PlayerYards()
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
function M:Cheapest(candidates)
	local pcont, px, py = PlayerYards()
	if not pcont then
		return nil
	end
	if not Build.Ready() then
		return nil, nil, true
	end
	local best, bestCost
	for i, c in ipairs(candidates) do
		local cont, x, y = CandidateYards(c)
		if cont then
			local points, cost = FindRoute(pcont, px, py, cont, x, y)
			if not points and cont == pcont then
				cost = Dist(px, py, x, y) / WALK * 1.3
			end
			if cost and (not bestCost or cost < bestCost) then
				best, bestCost = i, cost
			end
		end
	end
	return best, bestCost
end

-- fn run once routes can be priced: at once when the graph is built, else in
-- the frame after it is (the build started now if it is not yet). For a
-- choice Cheapest could not make yet (its third answer): made then, by route
-- as ever, not by straight line. Dropped when Route is switched off meanwhile.
function M:WhenReady(fn)
	if Build.ready then
		fn()
		return
	end
	local list = Build.later or {}
	Build.later = list
	list[#list + 1] = fn
	Build.Want()
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
		M:Notify("Arrived: " .. (destination.label or "destination"), "arrive")
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

-- The taxi map's own look: a chain of small gems along the way. Gold for
-- paths you have walked, pale blue where the route is a straight guess, green
-- for a flight, blue on the water.
-- The dots are the kit's small gem (deco/gem_small; the user's pick I2,
-- 2026-09-21) on the map and the minimap alike; the game's indicator dots
-- are the fallback when the kit is not loaded. A style's tint colours the gem.
local STYLE = {
	road = { texture = "Interface/Common/Indicator-Yellow", piece = "deco/gem_small", size = 1.0, gap = 1.6, alpha = 1 },
	guess = { texture = "Interface/Common/Indicator-Gray", piece = "deco/gem_small", size = 1.0, gap = 2.2, alpha = 1, color = { 0.8, 0.92, 1 } },
	flight = { texture = "Interface/Common/Indicator-Green", piece = "deco/gem_small", size = 0.9, gap = 3.0, alpha = 0.8 },
	boat = { texture = "Interface/Common/Indicator-Gray", piece = "deco/gem_small", size = 0.7, gap = 3.0, alpha = 0.6 },
}
local MAX_DOTS = 700

-- A pool of small textures on one frame, laid out along route segments with
-- an even spacing that carries over from one segment to the next.
local function NewPainter(frame)
	local painter = { frame = frame, dots = {}, used = 0, carry = 0 }
	function painter:Begin()
		self.used = 0
		self.carry = 0
	end
	function painter:Dot(x, y, size, style, anchor)
		if self.used >= MAX_DOTS then
			return
		end
		self.used = self.used + 1
		local dot = self.dots[self.used]
		if not dot then
			dot = self.frame:CreateTexture(nil, "OVERLAY")
			self.dots[self.used] = dot
		end
		local Kit = MelloUI.Kit
		local piece = style.piece and Kit and Kit:Piece(style.piece) and style.piece
		if piece then
			if dot.kitName ~= piece then
				Kit:Apply(dot, piece)
				dot.styleTexture = nil
			end
		elseif dot.styleTexture ~= style.texture then
			dot:SetTexture(style.texture)
			dot:SetTexCoord(0, 1, 0, 1)
			dot.kitPiece, dot.kitName = nil, nil
			dot.styleTexture = style.texture
		end
		if dot.styleColor ~= style.color then
			local c = style.color
			dot:SetVertexColor(c and c[1] or 1, c and c[2] or 1, c and c[3] or 1)
			dot.styleColor = style.color
		end
		dot:SetAlpha(style.alpha)
		dot:SetSize(size, size)
		dot:ClearAllPoints()
		dot:SetPoint("CENTER", self.frame, anchor, x, y)
		dot:Show()
	end
	-- One route segment; `unit` is the dot size for width 3 in frame units.
	function painter:Segment(ax, ay, bx, by, style, unit, anchor)
		local dx, dy = bx - ax, by - ay
		local len = math.sqrt(dx * dx + dy * dy)
		if len <= 0 then
			return
		end
		local size = unit * style.size
		local step = size * style.gap
		local ux, uy = dx / len, dy / len
		local at = self.carry
		while at <= len do
			self:Dot(ax + ux * at, ay + uy * at, size, style, anchor)
			at = at + step
		end
		self.carry = at - len
	end
	function painter:End()
		for i = self.used + 1, #self.dots do
			self.dots[i]:Hide()
		end
	end
	function painter:Clear()
		self.used = 0
		self:End()
	end
	return painter
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

local function LayerRouteFrame(canvas)
	local tiles, pins = canvas:GetFrameLevel(), nil
	for _, child in ipairs({ canvas:GetChildren() }) do
		if child ~= mapFrame then
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
	if mapFrame:GetFrameLevel() ~= level then
		mapFrame:SetFrameLevel(level)
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
	LayerRouteFrame(map:GetCanvas())
	mapPainter:Begin()
	if not (route and M.isEnabled and M.db.worldMap) then
		mapPainter:End()
		return
	end
	local mapID = Plain(map:GetMapID())
	if not mapID then
		mapPainter:End()
		return
	end
	local W, H = mapFrame:GetWidth(), mapFrame:GetHeight()
	if W < 10 or H < 10 then
		mapPainter:End()
		return
	end
	local scale = map.GetCanvasScale and map:GetCanvasScale() or 1
	local unit = 3.5 * (tonumber(M.db.lineWidth) or 3) / (scale > 0 and scale or 1)
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
	local rel, relPoint, x, y
	if mp and mp.ColumnSlot then
		rel, relPoint, x, y = mp:ColumnSlot("route")
	end
	rel, relPoint, x, y = rel or Minimap, relPoint or "BOTTOM", x or 0, y or -2
	local at = mm.lineAt
	if at and at[1] == rel and at[2] == relPoint and at[3] == x and at[4] == y then
		return
	end
	if not at then
		at = {}
		mm.lineAt = at
	end
	at[1], at[2], at[3], at[4] = rel, relPoint, x, y
	text:ClearAllPoints()
	text:SetPoint("TOP", rel, relPoint, x, y)
end

-- its height in the column while Route keeps the line (Route on, Distance
-- Under The Minimap on): its face's size and a hair; nil otherwise
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
	mm.text:SetTextColor(1, 0.82, 0.25)
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
local function ClipToSquare(ax, ay, bx, by, R)
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
	if Edge(-dx, ax + R) and Edge(dx, R - ax) and Edge(-dy, ay + R) and Edge(dy, R - ay) then
		return ax + dx * t0, ay + dy * t0, ax + dx * t1, ay + dy * t1
	end
	return nil
end

--------------------------------------------------------------------------------
-- Direction arrow
--------------------------------------------------------------------------------

local arrow = nil

-- Its place: MelloUI's one mover and place store (Core.lua; audit,
-- 2026-09-24, rank 6: it dragged itself and kept arrowX / arrowY of its own,
-- so Unlock the Windows, Reset positions and the UI-scale put-back never
-- reached it). Dragged at any time, as always; saved by its centre from the
-- screen's centre, as arrowX / arrowY were, in its own units. (Its parts in
-- one table: the file is near Lua's limit of 200 locals.) key: its place in
-- the store; size: the Arrow Size it was last laid at; resized: the slider
-- moved since (a size the wheel kept gives way); entry: its mover, once it
-- is on it (ArrowPlace.Mover: at its first show, not at login).
local ArrowPlace = { key = "routeArrow", size = nil, resized = nil, entry = nil }

-- the top centre of the screen: where it stands with no place saved (Reset
-- positions and /route arrow reset put it back here)
function ArrowPlace.Home(f)
	f:SetScale(tonumber(M.db and M.db.arrowScale) or 1)
	f:ClearAllPoints()
	f:SetPoint("TOP", UIParent, "TOP", 0, -40)
end

-- an old place (arrowX / arrowY) not moved into the store yet let go, both
-- keys at once and then through the setting path, so the macro backup
-- forgets it too: /route arrow reset, and Reset positions (the mover's
-- reset), or the next placing would move it back in (review, 2026-09-25)
function ArrowPlace.Forget()
	if M.db.arrowX ~= nil or M.db.arrowY ~= nil then
		M.db.arrowX, M.db.arrowY = nil, nil
		MelloUI:NotifySettingChanged(M.name, "arrowX", nil)
		MelloUI:NotifySettingChanged(M.name, "arrowY", nil)
	end
end

-- Rotation for a target dx yards east, dy yards south of the player facing f.
local function ArrowRotation(dx, dy, facing)
	local sin, cos = math.sin(facing), math.cos(facing)
	local rx, ry = dx * cos - dy * sin, dx * sin + dy * cos
	return math.atan2(-rx, -ry)
end

local function EnsureArrow()
	if arrow or not Minimap then
		return
	end
	arrow = CreateFrame("Frame", "MelloUIRouteArrow", UIParent)
	arrow:SetSize(72, 96)
	arrow:SetFrameStrata("MEDIUM")
	arrow:SetClampedToScreen(true)
	arrow:EnableMouse(true)
	arrow.icon = arrow:CreateTexture(nil, "ARTWORK")
	arrow.icon:SetSize(54, 54)
	arrow.icon:SetPoint("TOP", 0, -2)
	-- The client's own high-resolution direction arrows, oldest fallback last.
	local placed = false
	for _, atlas in ipairs({ "ui-hud-minimap-arrow-player-2x", "ui-hud-minimap-arrow-player" }) do
		if pcall(arrow.icon.SetAtlas, arrow.icon, atlas) and arrow.icon:GetAtlas() then
			placed = true
			break
		end
	end
	if not placed then
		arrow.icon:SetTexture("Interface/Minimap/MinimapArrow")
	end
	arrow.icon:SetVertexColor(1, 0.82, 0.25)
	arrow.distance = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	RouteFont.Style(arrow.distance, "fontChat", _G.GameFontNormal)   -- a number
	arrow.distance:SetPoint("TOP", arrow.icon, "BOTTOM", 0, -2)
	arrow.distance:SetTextColor(1, 0.82, 0.25)
	arrow.label = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	RouteFont.Style(arrow.label, "fontText", _G.GameFontHighlightSmall)   -- the destination's name
	arrow.label:SetPoint("TOP", arrow.distance, "BOTTOM", 0, -1)
	arrow.label:SetWidth(180)
	arrow.label:SetWordWrap(false)
	Perf.SetScript(arrow, "OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Route", 1, 1, 1)
		GameTooltip:AddLine("Points along the next leg of the route. Drag to move.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	Perf.SetScript(arrow, "OnLeave", function() GameTooltip:Hide() end)
	arrow.frameAge = 0
	Perf.SetScript(arrow, "OnUpdate", function(self, elapsed)
		self.frameAge = self.frameAge + elapsed
		if self.frameAge < 1 / 60 or not self.targetX then
			return
		end
		self.frameAge = 0
		local cont, px, py = PlayerYards(true)   -- the minimap's ask this frame, when it drew first
		if not cont or cont ~= self.targetCont then
			return
		end
		local facing = 0
		if GetPlayerFacing then
			local ok, f = pcall(GetPlayerFacing)
			facing = ok and Plain(f) or 0
		end
		self.icon:SetRotation(ArrowRotation(self.targetX - px, self.targetY - py, facing))
	end)
	arrow:Hide()
	-- (its drag and its place: ArrowPlace.Mover, when it is first shown)
end

-- The place it had before the store (arrowX / arrowY, its centre's offsets
-- from the screen's centre in its own units), moved into the store once, so
-- it stands exactly where it did: laid the old way at its size, then saved
-- by the store's own measure; the old keys go. The data is the version:
-- while the old keys are there the move has not happened. (A flag would not
-- do: a late settings load carries plain values over from the table used
-- before it, not tables, so the flag would come through without the
-- store's entry.) A profile or backup from before brings its place along.
-- A place the store already has (dragged since) wins; half a place is let
-- go. Returns true while it still stands on the old place (the store could
-- not measure it yet: tried again at the next placing).
function ArrowPlace.Old()
	local x, y = M.db.arrowX, M.db.arrowY
	if x == nil and y == nil then
		return false
	end
	x, y = tonumber(x), tonumber(y)
	if x and y and not MelloUI:GetPosition(ArrowPlace.key) then
		arrow:ClearAllPoints()
		arrow:SetPoint("CENTER", UIParent, "CENTER", x, y)
		-- (through the setting path: the macro backup takes the new place,
		-- and with it the old keys gone)
		if not MelloUI:SavePosition(ArrowPlace.key, arrow) then
			return true
		end
	end
	M.db.arrowX, M.db.arrowY = nil, nil
	return false
end

local function PlaceArrow()
	if not arrow then
		return
	end
	local size = tonumber(M.db.arrowScale) or 1
	-- one size, the Arrow Size slider's: a size the mover's wheel kept with
	-- the place gives way when the slider moves (noted while the arrow is
	-- not on the mover yet, done once it is)
	if ArrowPlace.size and ArrowPlace.size ~= size then
		ArrowPlace.resized = true
	end
	ArrowPlace.size = size
	local entry = ArrowPlace.entry
	if not entry then
		-- laid when it goes on the mover, at its first show (nothing made
		-- or hooked at login: review, 2026-09-25, WINDOW-RULES 2f); at once
		-- only while an old place waits to be moved in (the one login after
		-- the update): the move needs the mover's anchor, and Reset
		-- positions has to reach it
		if M.db.arrowX ~= nil or M.db.arrowY ~= nil then
			ArrowPlace.Mover()
		end
		return
	end
	if ArrowPlace.resized then
		ArrowPlace.resized = nil
		local pos = MelloUI:GetPosition(ArrowPlace.key)
		if pos and pos.scale then
			MelloUI:SavePosition(ArrowPlace.key, arrow, false)
		end
	end
	-- the slider's size is its 100 % in the unlocked windows' size readout
	-- and wheel (read from the entry each time: review, 2026-09-25)
	entry.base = size
	-- the size first: the saved offsets are in its own units
	arrow:SetScale(size)
	if not ArrowPlace.Old() and not MelloUI:RestorePosition(ArrowPlace.key, arrow) then
		ArrowPlace.Home(arrow)
	end
end

-- On the one mover: dragged through it, unlocked or not; the store's place
-- put back on every show and after a UI Scale change, kept on the screen.
-- At its first show (UpdateArrow), or at once while an old place waits
-- (PlaceArrow). It sets no drag, show or hide script of its own (Core hooks
-- those); registered at its size, which the saved offsets are in; the
-- wheel's range while unlocked is the Arrow Size slider's.
function ArrowPlace.Mover()
	if ArrowPlace.entry or not arrow then
		return
	end
	local size = tonumber(M.db.arrowScale) or 1
	arrow:SetScale(size)
	ArrowPlace.entry = MelloUI:RegisterMover(arrow, arrow, { key = ArrowPlace.key, anchor = "CENTER",
		plainDrag = "always", min = 0.5, max = 2, base = size, reset = ArrowPlace.Forget, default = ArrowPlace.Home })
	if ArrowPlace.entry then
		PlaceArrow()
	end
end

-- /route arrow reset: the saved place forgotten, an old one not moved yet
-- too; laid now if it is on the mover, else at its first show
function ArrowPlace.Reset()
	ArrowPlace.Forget()
	MelloUI:ForgetPosition(ArrowPlace.key)
	PlaceArrow()
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
--------------------------------------------------------------------------------

local marker = nil
local BEAM_ROOT = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Route\\"
local BEAM_W, BEAM_H = 48, 420
local BEAM_RED = { 1, 0.16, 0.1 }
local BEAM_SPAN = BEAM_H / (256 * BEAM_W / 64)   -- how many times the streak strip repeats up the beam
local EDGE_MARGIN = 0.07        -- the navigation frame this near a screen edge (share of the screen) = off screen
-- off screen, the arrow goes round the character on this ring (UI units from
-- the screen's centre, the character stands about there) instead of sitting
-- at the screen's edge (user, 2026-09-23: "its too far off the character")
local RING_X, RING_Y, RING_DY = 230, 170, -20
local gameMarkerFaded = false
local gameMarkerHooked = false
local fadingGame = false        -- our own SetAlpha on the game's marker, so the hook lets it through

local function NavFrame()
	if C_Navigation and C_Navigation.GetFrame then
		local ok, f = pcall(C_Navigation.GetFrame)
		if ok and f then
			return f
		end
	end
	return nil
end

-- The game's own marker at alpha 0 while ours shows, back to 1 after. A
-- post-hook keeps it at 0 when the game sets its alpha again.
local function FadeGameMarker(on)
	local f = _G.SuperTrackedFrame
	if not (f and f.SetAlpha) or gameMarkerFaded == on then
		return
	end
	gameMarkerFaded = on
	if not gameMarkerHooked then
		gameMarkerHooked = true
		hooksecurefunc(f, "SetAlpha", function(self)
			if gameMarkerFaded and not fadingGame then
				fadingGame = true
				self:SetAlpha(0)
				fadingGame = false
			end
		end)
	end
	fadingGame = true
	f:SetAlpha(on and 0 or 1)
	fadingGame = false
end

-- Off screen: the navigation frame sits within EDGE_MARGIN of an edge. Also
-- returns its place as a share of the screen, centre 0.5 / 0.5.
local function ScreenPlace(nav)
	local okC, x, y = pcall(nav.GetCenter, nav)
	if not (okC and Plain(x) and Plain(y)) then
		return nil
	end
	local scale = nav:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	if not (w and h and w > 0 and h > 0) then
		return nil
	end
	local fx, fy = x * scale / w, y * scale / h
	local off = fx < EDGE_MARGIN or fx > 1 - EDGE_MARGIN or fy < EDGE_MARGIN or fy > 1 - EDGE_MARGIN
	return off, fx, fy
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

local function MarkerTick(self, elapsed)
	self.age = self.age + elapsed
	if self.age < 1 / 60 then
		return
	end
	local dt = self.age
	self.age = 0
	-- the destination cleared (a map pin removed, a quest untracked) or its
	-- navigation frame gone: away at once, whatever else still ticks
	-- (user, 2026-09-23: the arrow stayed round the character after clearing)
	local nav = self.nav
	if not (nav and destination and M.isEnabled and M.db.worldMarker) or NavFrame() ~= nav or not NavIsOurs() then
		UpdateMarker()
		return
	end
	local off, fx, fy = ScreenPlace(nav)
	if off == nil then
		return
	end
	-- on screen: over the destination (hung on the navigation frame); off
	-- screen: on the ring round the character, in the destination's direction
	if not off and (self.mode ~= "nav" or self.anchoredTo ~= nav) then
		self.mode, self.anchoredTo = "nav", nav
		self:ClearAllPoints()
		self:SetPoint("CENTER", nav, "CENTER")
	end
	self.gem:SetShown(not off)
	self.distance:SetShown(not off)
	self.label:SetShown(not off)
	self.edge:SetShown(off)
	local beam = self.beam
	beam:SetShown(not off and M.db.routeBeam and true or false)
	-- the streaks rise: the strip scrolls up the beam, round and round (they
	-- stand still under Reduce Motion)
	if beam:IsShown() and not (MelloUI.Anim and MelloUI.Anim.reduceMotion) then
		beam.scroll = (beam.scroll + dt * 0.3) % 1
		beam.streaks:SetTexCoord(0, 1, beam.scroll, beam.scroll + BEAM_SPAN)
	end
	if off then
		-- the direction from the screen's centre to where the game puts the
		-- place (in screen units, so a wide screen does not skew it); the
		-- arrow slides round the ring the short way, eased so it does not jitter
		local want = math.atan2((fy - 0.5) * UIParent:GetHeight(), (fx - 0.5) * UIParent:GetWidth())
		local diff = (want - self.angle + math.pi) % (2 * math.pi) - math.pi
		-- half the gap a frame at 60 fps: keeps up with a fast turn, still no jitter
		-- (user, 2026-09-23: "kinda slow response when turning"; was dt * 12)
		self.angle = self.angle + diff * math.min(1, dt * 30)
		self.mode, self.anchoredTo = "ring", nil
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", math.cos(self.angle) * RING_X, math.sin(self.angle) * RING_Y + RING_DY)
		self.edge:SetRotation(self.angle - math.pi / 2)
	end
	if C_Navigation and C_Navigation.GetDistance then
		local okD, d = pcall(C_Navigation.GetDistance)
		if okD and Plain(d) then
			-- the beam fades over the last 50 yards and is gone within 10
			local fade = math.max(0, math.min(1, (d - 10) / 40))
			if fade ~= beam.fade then
				beam.fade = fade
				beam.glow:SetAlpha(0.85 * fade)
				beam.streaks:SetAlpha(0.7 * fade)
			end
			local text = Yards(math.floor(d + 0.5))
			if text ~= self.distanceText then
				self.distanceText = text
				self.distance:SetText(text)
			end
		end
	end
end

local function EnsureMarker()
	if marker then
		return
	end
	marker = CreateFrame("Frame", "MelloUIRouteMarker", UIParent)
	marker:SetSize(44, 44)
	marker:SetFrameStrata("LOW")
	marker:SetClampedToScreen(true)
	marker:EnableMouse(false)
	-- the light beam (user, 2026-09-23: "can you build that beam, but make it
	-- red"): a glow column from its foot at the destination up into the sky,
	-- light streaks rising inside it (masked by the column's own shape), both
	-- added to what is behind them. Made by Tools/make_route_beam.py.
	local beam = CreateFrame("Frame", nil, marker)
	beam:SetSize(BEAM_W, BEAM_H)
	beam:SetPoint("BOTTOM", marker, "CENTER", 0, -6)
	beam:SetFrameLevel(marker:GetFrameLevel() + 1)
	beam.glow = beam:CreateTexture(nil, "ARTWORK")
	beam.glow:SetAllPoints()
	beam.glow:SetTexture(BEAM_ROOT .. "beam_glow")
	beam.glow:SetBlendMode("ADD")
	beam.glow:SetVertexColor(BEAM_RED[1], BEAM_RED[2], BEAM_RED[3])
	beam.streaks = beam:CreateTexture(nil, "ARTWORK", nil, 1)
	beam.streaks:SetAllPoints()
	beam.streaks:SetTexture(BEAM_ROOT .. "beam_streaks", "CLAMP", "REPEAT")
	beam.streaks:SetBlendMode("ADD")
	beam.streaks:SetVertexColor(BEAM_RED[1], BEAM_RED[2] + 0.1, BEAM_RED[3] + 0.05)
	if beam.CreateMaskTexture and beam.streaks.AddMaskTexture then
		local shape = beam:CreateMaskTexture()
		shape:SetAllPoints()
		shape:SetTexture(BEAM_ROOT .. "beam_glow", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		beam.streaks:AddMaskTexture(shape)
	end
	beam.glow:SetAlpha(0.85)
	beam.streaks:SetAlpha(0.7)
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
	marker.gem = front:CreateTexture(nil, "ARTWORK")
	marker.gem:SetSize(26, 26)
	marker.gem:SetPoint("CENTER")
	local Kit = MelloUI.Kit
	if not (Kit and Kit.Apply and Kit:Apply(marker.gem, "deco/gem_large")) then
		marker.gem:SetTexture("Interface/Minimap/POIIcons")
	end
	marker.distance = front:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	RouteFont.Style(marker.distance, "fontChat", _G.GameFontNormal)   -- a number
	marker.distance:SetPoint("TOP", marker.gem, "BOTTOM", 0, -2)
	marker.distance:SetTextColor(1, 0.82, 0.25)
	marker.label = front:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	RouteFont.Style(marker.label, "fontText", _G.GameFontHighlightSmall)   -- the destination's name
	marker.label:SetPoint("TOP", marker.distance, "BOTTOM", 0, -1)
	marker.label:SetWidth(180)
	marker.label:SetWordWrap(false)
	marker.edge = front:CreateTexture(nil, "ARTWORK")
	marker.edge:SetSize(40, 40)
	marker.edge:SetPoint("CENTER")
	local placed = false
	for _, atlas in ipairs({ "ui-hud-minimap-arrow-player-2x", "ui-hud-minimap-arrow-player" }) do
		if pcall(marker.edge.SetAtlas, marker.edge, atlas) and marker.edge:GetAtlas() then
			placed = true
			break
		end
	end
	if not placed then
		marker.edge:SetTexture("Interface/Minimap/MinimapArrow")
	end
	marker.edge:SetVertexColor(1, 0.82, 0.25)
	marker.edge:Hide()
	-- a small pop when the marker comes up: the gem grows in and settles
	local pop = marker.gem:CreateAnimationGroup()
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
	marker.pop = pop
	marker.age, marker.angle = 0, math.pi / 2
	Perf.SetScript(marker, "OnUpdate", MarkerTick)
	marker:Hide()
end

-- Shown while there is a destination and the game has a navigation frame
-- for it; hung on that frame, which the client moves every frame.
UpdateMarker = function()
	if not marker then
		return
	end
	local nav = M.isEnabled and M.db.worldMarker and destination and NavIsOurs() and NavFrame() or nil
	if not nav then
		if marker:IsShown() then
			marker:Hide()
		end
		marker.nav = nil
		FadeGameMarker(false)
		return
	end
	-- the tick places it: over the destination or on the ring round the character
	marker.nav = nav
	marker.label:SetText((standIn and standIn.label) or destination.label or "")
	if not marker:IsShown() then
		marker.distanceText = nil
		marker:Show()
		-- the pop and the flare end at once under Reduce Motion (audit, 2026-09-24)
		local anim = MelloUI.Anim
		if anim then
			anim:PlayGroup(marker.pop)
		else
			marker.pop:Play()
		end
		if M.db.routeBeam then
			marker.beam:Show()
			if anim then
				anim:PlayGroup(marker.beam.flare)
			else
				marker.beam.flare:Play()
			end
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

local function UpdateArrow(cont, px, py)
	if not (arrow and M.db.arrow and destination) then
		if arrow then
			arrow:Hide()
		end
		return false
	end
	local tx, ty, remaining
	NoteHeading(cont, px, py)
	if route then
		local i, _, d, qx, qy = PlaceOnRoute(cont, px, py)
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
	if not tx and destination.cont == cont then
		tx, ty = destination.x, destination.y
	end
	if not tx then
		arrow.targetX = nil
		arrow:Hide()
		return false
	end
	-- the OnUpdate above turns the icon towards this every frame
	arrow.targetCont, arrow.targetX, arrow.targetY = cont, tx, ty
	if not remaining or remaining <= 0 then
		remaining = Dist(px, py, destination.x, destination.y)
	end
	arrow.distance:SetText(Yards(remaining))
	arrow.label:SetText(destination.label or "")
	-- on the one mover at its first show, not at login (ArrowPlace.Mover)
	if not ArrowPlace.entry then
		ArrowPlace.Mover()
	end
	arrow:Show()
	return true
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
	if not (route and M.isEnabled and M.db.minimap) then
		mmPainter:End()
		mm.text:Hide()
		return
	end
	if not cont then
		mmPainter:End()
		return
	end
	local diameter = MinimapDiameter()
	local size = Minimap:GetWidth()
	local pixelsPerYard = size / diameter
	local rotate = GetCVar("rotateMinimap") == "1"
	local sin, cos = 0, 1
	if rotate and GetPlayerFacing then
		local ok, facing = pcall(GetPlayerFacing)
		facing = ok and Plain(facing) or 0
		sin, cos = math.sin(facing), math.cos(facing)
	end
	local round = IsRoundMinimap()
	local R = size / 2 - 1
	local unit = 2.6 * (tonumber(M.db.lineWidth) or 3)
	local points = RouteAhead()
	local function Offset(yx, yy)
		local dx, dy = yx - px, yy - py
		if rotate then
			dx, dy = dx * cos - dy * sin, dx * sin + dy * cos
		end
		return dx * pixelsPerYard, -dy * pixelsPerYard, math.sqrt(dx * dx + dy * dy)
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if a[1] == cont and b[1] == cont and b[4] ~= "boat" and b[4] ~= "flight" then
			local ax, ay = Offset(a[2], a[3])
			local bx, by = Offset(b[2], b[3])
			if round then
				ax, ay, bx, by = ClipToCircle(ax, ay, bx, by, R)
			else
				ax, ay, bx, by = ClipToSquare(ax, ay, bx, by, R)
			end
			if ax then
				mmPainter:Segment(ax, ay, bx, by, STYLE[b[4]] or STYLE.road, unit, "CENTER")
			end
		end
	end
	mmPainter:End()
	if M.db.distanceText and not arrowShown then
		local remaining = route.length or 0
		local label = destination and destination.label
		mm.text:SetText(label and (Yards(remaining) .. "  " .. label) or Yards(remaining))
		mm.text:Show()
	else
		mm.text:Hide()
	end
end

Redraw = function()
	DrawWorldMap()
	-- the marker follows the destination straight away; the minimap tick
	-- that also updates it stops as soon as there is no destination
	UpdateMarker()
	if arrow and not (destination and M.isEnabled and M.db.arrow) then
		arrow:Hide()
	end
	if mm then
		mm:SetShown((route ~= nil or destination ~= nil) and M.isEnabled and (M.db.minimap or M.db.distanceText or M.db.arrow or M.db.worldMarker))
		if not route then
			if mmPainter then
				mmPainter:Clear()
			end
			mm.text:Hide()
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

	-- A frame's share of the build. The frame after it plans what waited
	-- (the first route's search gets a frame of its own): the tracked quest's
	-- places priced, the route planned and announced, then what was put off
	-- until routes could price it (M:WhenReady), in the order it was asked.
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
			return
		end
		ReadWaypoint()
		if Build.waiting and destination then
			Plan(true)
		end
		Build.waiting = nil
		for i = 1, later and #later or 0 do
			local ok, err = pcall(later[i])
			if not ok then
				MelloUI:Print("|cffff4040Error|r in module 'Route' (after the road graph was built): %s", tostring(err))
			end
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

Perf.SetScript(eventFrame, "OnEvent", function(_, event)
	if event == "PLAYER_LOGOUT" then
		Build.Save()
	elseif event == "PLAYER_ENTERING_WORLD" then
		last = nil
		taxiStart = nil
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
	elseif event == "TAXIMAP_OPENED" then
		-- The routes are known a moment after the map opens.
		C_Timer.After(0.2, LearnFlights)
		C_Timer.After(0.2, KnownFlightsHere)
	end
end)

local tickCount = 0
local function Tick()
	if not M.isEnabled then
		return
	end
	tickCount = tickCount + 1
	Record()
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
		MelloUI:Print("kit: %s, gem piece: %s", MelloUI.Kit and "yes" or "no", tostring(MelloUI.Kit and MelloUI.Kit:Piece("deco/gem_small") and "found" or "missing"))
		MelloUI:Print("module enabled=%s worldMap=%s minimap=%s provider=%s destination=%s route=%s (%d points) map shown=%s",
			tostring(M.isEnabled), tostring(M.db and M.db.worldMap), tostring(M.db and M.db.minimap), Provider and "yes" or "no",
			destination and (destination.label or "map pin") or "none", route and "yes" or "no", route and #route.points or 0,
			tostring(WorldMapFrame and WorldMapFrame:IsShown()))
		local okH, has = pcall(C_Map.HasUserWaypoint)
		MelloUI:Print("user waypoint=%s supertracking waypoint=%s", okH and tostring(has) or "?",
			C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and tostring(C_SuperTrack.IsSuperTrackingUserWaypoint()) or "?")
		MelloUI:ShowLog("route dots")
	elseif msg == "clear" then
		if C_Map.ClearUserWaypoint then
			pcall(C_Map.ClearUserWaypoint)
		end
		M:Clear()
		MelloUI:Print("Route cleared.")
	elseif msg == "arrow reset" then
		ArrowPlace.Reset()
		MelloUI:Print("Arrow back at the top centre of the screen.")
	elseif msg == "reset confirm" then
		-- the traced roads are not learned data: they stay, counted afresh
		-- (before the graph is built: once it is, after what came before)
		Build.Queue(ForgetLearned)
		MelloUIRoutes = live
		M:Clear()
		-- (user, 2026-09-24: player words, no developer tools in what players read)
		MelloUI:Print("Learned paths wiped. The paths that come with MelloUI itself come back at the next /reload.")
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
			poiCache[questID] = nil
			local mapID, x, y = QuestObjectivePoint(questID)
			print(string.format("   objective marker: %s", mapID and string.format("map %d at %.3f, %.3f", mapID, x, y) or "none found"))
			if destination and destination.fromQuest then
				print("   following it: " .. tostring(destination.label) .. (route and "" or " (no route drawn: within 60 yards, or no route found)"))
			else
				print("   not following it" .. (destination and " (a map pin has priority)" or ""))
			end
		end
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
		-- No saved paths is the usual case after a restart (this client drops
		-- them then), so say that, not "not loaded": only while the game may
		-- still bring them (the first 90 s) is it "not yet"
		MelloUI:Print("Route: %d learned points, %d traced road points, %d links, %d docks, %d flight points (%d usable)%s.",
			nodes - tracedNodes, tracedNodes, edges, docks and #docks or 0,
			taxiCount, usable, mergedSaved and ""
				or adoptTicker and " (paths learned in earlier sessions: the game has not brought them yet)"
				or " (none from earlier sessions: the game forgets learned paths when it restarts)")
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
		-- what is learned lives in the saved variables, which this client
		-- drops when the game restarts: said here as in the option's text
		-- (the reason a step was skipped only with learning on: off, it is
		-- always "learning is off", which the line already says)
		print(string.format("   learning %s: %d steps recorded this session%s; what is learned is kept until you quit the game (a /reload keeps it)",
			M.db.learn and "on" or "off", recorded,
			M.db.learn and recordSkip ~= "" and (", the last one skipped: " .. recordSkip) or ""))
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
		print("   /route clear   |   /route arrow reset   |   /route reset   |   /route dots")
	end
end

function M:OnInit(db)
	self.db = db
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
	PlaceArrow()
	EnsureMarker()
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
	if not ticker then
		ticker = C_Timer.NewTicker(0.5, Tick)
	end
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
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	route = nil
	StandIn.Update()
	Redraw()
	UpdateMarker()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	if key == "worldMarker" then
		StandIn.Update()
	end
	PlaceArrow()
	Redraw()
	UpdateMarker()
end

MelloUI:Profile("Route", "breadcrumbs + planning tick", Tick)
MelloUI:Profile("Route", "minimap drawing", MinimapTick)
MelloUI:Profile("Route", "world map drawing", DrawWorldMap)

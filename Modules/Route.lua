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
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI

local M = MelloUI:RegisterModule("Route", {
	title = "Route",
	desc = "Draws the way to your map waypoint on the world map and the minimap, along roads you have walked before.",
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
		{ type = "toggle", key = "trackQuests", name = "Route To The Tracked Quest",
		  desc = "When no map pin is set, route to the objective area of the quest you are tracking (the one with the arrow), and to its turn-in once it is complete." },
		{ type = "toggle", key = "trackFirstWatched", name = "Fall Back To The First Tracked Quest",
		  desc = "When nothing is super-tracked, follow the first quest in the objective tracker instead of showing nothing." },
		{ type = "toggle", key = "distanceText", name = "Distance Under The Minimap",
		  desc = "Show the remaining route length under the minimap (hidden while the arrow is shown)." },
		{ type = "toggle", key = "arrow", name = "Direction Arrow",
		  desc = "An arrow that points along the route's next leg, with the distance and destination. Drag it to move it; /route arrow reset puts it back at the top centre." },
		{ type = "slider", key = "arrowScale", name = "Arrow Size", min = 0.5, max = 2, step = 0.1 },
		{ type = "header", name = "Notice" },
		{ type = "toggle", key = "notice", name = "Tracking Notice",
		  desc = "A one-line notice in the upper third of the screen whenever something new is tracked, and when you arrive." },
		{ type = "toggle", key = "noticeSound", name = "Notice Sound",
		  desc = "A short chime with the notice: the map's super-track sound for a new destination, a soft tick otherwise." },
		{ type = "slider", key = "lineWidth", name = "Marker Size", min = 1, max = 8, step = 1,
		  desc = "Size of the gems that mark the route." },
		{ type = "slider", key = "arrive", name = "Arrived Within (yards)", min = 10, max = 100, step = 5,
		  desc = "The route ends and the waypoint is cleared when you get this close." },
		{ type = "header", name = "Learning" },
		{ type = "toggle", key = "learn", name = "Learn Paths While Playing",
		  desc = "Remember where you walk and fly so routes can follow real roads. /route shows how much has been learned." },
	},
})

MelloUI.Route = M

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function IsSecret(v)
	return issecretvalue and issecretvalue(v)
end

local function Plain(v)
	if v == nil or IsSecret(v) then
		return nil
	end
	return v
end

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

local function PlayerYards()
	local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	mapID = ok and Plain(mapID) or nil
	if not mapID then
		return nil
	end
	local okP, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	if not okP then
		return nil
	end
	local x, y = VectorXY(pos)
	if not (x and y) then
		return nil
	end
	return ToYards(mapID, x, y)
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
	end
	local path = notice.text:GetFont()
	if path then
		notice.text:SetFont(path, 20, "OUTLINE")
	end
	notice.text:SetPoint("CENTER")
	notice.text:SetWidth(900)
	notice.text:SetJustifyH("CENTER")
	notice.text:SetWordWrap(false)
	notice.text:SetTextColor(1, 0.5, 0)
	notice.text:SetShadowOffset(2, -2)
	notice.text:SetShadowColor(0, 0, 0, 0.9)
	notice:Hide()
	notice:SetScript("OnUpdate", function(self, elapsed)
		self.age = (self.age or 0) + elapsed
		if self.age <= NOTICE_HOLD then
			self:SetAlpha(1)
		elseif self.age < NOTICE_HOLD + NOTICE_FADE then
			self:SetAlpha(1 - (self.age - NOTICE_HOLD) / NOTICE_FADE)
		else
			self:Hide()
		end
	end)
	return notice
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
	frame.age = 0
	frame:SetAlpha(1)
	frame:Show()
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
local graphVersion = 0   -- bumped when nodes are added; caches below key on it

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

local function Link(a, akey, b, bkey, cost)
	if a[3][bkey] == nil or a[3][bkey] > cost then
		a[3][bkey] = cost
	end
	if b[3][akey] == nil or b[3][akey] > cost then
		b[3][akey] = cost
	end
end

local function AddNode(cont, x, y)
	local g = Graph(cont)
	local key = KeyOf(x, y)
	local node = g[key]
	if not node then
		node = { x, y, {} }
		g[key] = node
		graphVersion = graphVersion + 1
		local cx, cy = math.floor(x / CELL), math.floor(y / CELL)
		for i = -2, 2 do
			for j = -2, 2 do
				local k = (cx + i) .. ":" .. (cy + j)
				local o = g[k]
				if o and k ~= key then
					local d = Dist(x, y, o[1], o[2])
					if d <= NEAR then
						Link(node, key, o, k, d / WALK)
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

-- Fold another graph table (baked data or the saved variable) into live.
local function Merge(other)
	if type(other) ~= "table" then
		return 0
	end
	local added = 0
	if type(other.pins) == "table" then
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
	if type(other.graphs) ~= "table" then
		return 0
	end
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
			end
			for key, node in pairs(g) do
				local k = keyMap[key]
				local target = k and mine[k]
				if target then
					for linked, cost in pairs(node[3] or {}) do
						local ko = keyMap[linked] or linked
						if ko ~= k and type(cost) == "number" and (target[3][ko] == nil or target[3][ko] > cost) then
							target[3][ko] = cost
							local back = mine[ko]
							if back and (back[3][k] == nil or back[3][k] > cost) then
								back[3][k] = cost
							end
						end
					end
				end
			end
		end
	end
	return added
end

-- Roads traced from the map art (Media/RoadData.lua, Tools/trace_roads.py):
-- folded in like baked data but scaled to the continent sizes this client
-- reports, marked as traced so they are never written back into the saved
-- variable, and linked to whatever was learned near them.
local tracedNodes = 0

local function MergeRoads(data)
	if type(data) ~= "table" or type(data.graphs) ~= "table" then
		return 0
	end
	local added = 0
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
			end
			for key, node in pairs(g) do
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

-- Flight points the character can use, from the world map's own flight point
-- list of every zone. Cached for two minutes.
local function RefreshDiscovered()
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap and C_Map.GetMapChildrenInfo) then
		discovered = nil
		return
	end
	if discovered and GetTime() - discoveredAt < 120 then
		return
	end
	discoveredAt = GetTime()
	local names, ids, conts = {}, {}, {}
	for _, t in pairs(taxis or {}) do
		conts[t.cont] = true
	end
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
	if next(names) or next(ids) then
		discovered = { names = names, ids = ids }
	else
		discovered = nil
	end
end

local function TaxiUsable(id, t)
	if not discovered then
		return true
	end
	return discovered.ids[id] or discovered.names[t.name:lower()] or false
end

-- At a flight master: one graph link from here to every reachable point,
-- costed by the real flight route.
local function LearnFlights()
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
	local akey, a = AddNode(ccont, cyx, cyy)
	local learned = 0
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
				local bkey, b = AddNode(dcont, dx, dy)
				if bkey ~= akey then
					Link(a, akey, b, bkey, length / FLIGHT + 5)
					learned = learned + 1
				end
			end
		end
	end
	if learned > 0 then
		discoveredAt = 0
	end
end

--------------------------------------------------------------------------------
-- Search
--------------------------------------------------------------------------------

-- Small binary heap keyed by f.
local function NewHeap()
	local heap = { n = 0 }
	function heap:push(id, f)
		local n = self.n + 1
		self.n = n
		self[n] = { id, f }
		while n > 1 do
			local p = math.floor(n / 2)
			if self[p][2] <= self[n][2] then
				break
			end
			self[p], self[n] = self[n], self[p]
			n = p
		end
	end
	function heap:pop()
		if self.n == 0 then
			return nil
		end
		local top = self[1]
		self[1] = self[self.n]
		self[self.n] = nil
		self.n = self.n - 1
		local n, i = self.n, 1
		while true do
			local l, r, s = i * 2, i * 2 + 1, i
			if l <= n and self[l][2] < self[s][2] then s = l end
			if r <= n and self[r][2] < self[s][2] then s = r end
			if s == i then
				break
			end
			self[s], self[i] = self[i], self[s]
			i = s
		end
		return top[1], top[2]
	end
	return heap
end

-- Nodes grouped in 250-yard buckets per continent, rebuilt when the graph grew.
local BUCKET = 250
local buckets = { version = -1, conts = {} }

local function Buckets(cont)
	if buckets.version ~= graphVersion then
		buckets.version = graphVersion
		buckets.conts = {}
		for c, g in pairs(live.graphs) do
			local index = {}
			for key, node in pairs(g) do
				local bk = math.floor(node[1] / BUCKET) .. ":" .. math.floor(node[2] / BUCKET)
				local list = index[bk]
				if not list then
					list = {}
					index[bk] = list
				end
				list[#list + 1] = key
			end
			buckets.conts[c] = index
		end
	end
	return buckets.conts[cont]
end

-- Graph nodes within `radius` yards of a point, as { key = distance }.
local function NodesNear(cont, x, y, radius)
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
			local list = index[(bx + i) .. ":" .. (by + j)]
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

-- Neighbourhood links of a fixed hub (dock, flight point), cached per graph version.
local hubLinks = { version = -1, links = {} }

local function HubNear(id, cont, x, y)
	if hubLinks.version ~= graphVersion then
		hubLinks.version = graphVersion
		hubLinks.links = {}
	end
	local near = hubLinks.links[id]
	if not near then
		near = NodesNear(cont, x, y, OFFROAD)
		hubLinks.links[id] = near
	end
	return near
end

-- Route from (scont, sx, sy) to (gcont, gx, gy): a list of { cont, x, y, kind }
-- points and the total cost in seconds, or nil.
-- A start link that points back the way the player is walking is priced
-- BEHIND_COST times its length (user, 2026-09-22: the arrow sent the player
-- back to the road behind them, "the checkpoint", after a shortcut): the
-- planner then joins the road ahead unless going back is a real saving.
local BEHIND_COST = 2.5

local function FindRoute(scont, sx, sy, gcont, gx, gy, hx, hy)
	-- Node ids: "c|key" graph nodes, "D<i>" docks, "S", "G".
	local pos = {}     -- id -> { cont, x, y }
	local extra = {}   -- id -> { otherId = cost } for virtual nodes and docks
	local function AddExtra(a, b, cost)
		extra[a] = extra[a] or {}
		extra[b] = extra[b] or {}
		if extra[a][b] == nil or extra[a][b] > cost then extra[a][b] = cost end
		if extra[b][a] == nil or extra[b][a] > cost then extra[b][a] = cost end
	end
	pos.S = { scont, sx, sy }
	pos.G = { gcont, gx, gy }
	local function LinkPoint(id, cont, x, y, cached)
		local near = cached and HubNear(id, cont, x, y) or NodesNear(cont, x, y, OFFROAD)
		for key, d in pairs(near) do
			local cost = d / WALK * 1.3
			if id == "S" and hx and d > 5 then
				local node = live.graphs[cont] and live.graphs[cont][key]
				if node then
					-- the node's direction from the player against the heading
					local dot = ((node[1] - x) * hx + (node[2] - y) * hy) / d
					if dot < -0.3 then
						cost = cost * BEHIND_COST
					elseif dot < 0.3 then
						cost = cost * (1 + (0.3 - dot) * (BEHIND_COST - 1) / 0.6)   -- sideways: in between
					end
				end
			end
			AddExtra(id, cont .. "|" .. key, cost)
		end
	end
	LinkPoint("S", scont, sx, sy)
	LinkPoint("G", gcont, gx, gy)
	for i, d in ipairs(docks or {}) do
		local id = "D" .. i
		pos[id] = { d.cont, d.x, d.y }
		LinkPoint(id, d.cont, d.x, d.y, true)
		if d.pair then
			AddExtra(id, "D" .. d.pair, BOAT_COST)
		end
		if d.cont == scont then
			AddExtra("S", id, Dist(d.x, d.y, sx, sy) / WALK * 1.3)
		end
		if d.cont == gcont then
			AddExtra("G", id, Dist(d.x, d.y, gx, gy) / WALK * 1.3)
		end
	end
	RefreshDiscovered()
	for id, t in pairs(taxis or {}) do
		if TaxiUsable(id, t) then
			local nid = "T" .. id
			pos[nid] = { t.cont, t.x, t.y }
			LinkPoint(nid, t.cont, t.x, t.y, true)
			for other, secs in pairs(t.links) do
				if taxis[other] and TaxiUsable(other, taxis[other]) then
					AddExtra(nid, "T" .. other, secs)
				end
			end
			if t.cont == scont then
				AddExtra("S", nid, Dist(t.x, t.y, sx, sy) / WALK * 1.3)
			end
			if t.cont == gcont then
				AddExtra("G", nid, Dist(t.x, t.y, gx, gy) / WALK * 1.3)
			end
		end
	end
	if scont == gcont then
		AddExtra("S", "G", Dist(sx, sy, gx, gy) / WALK * STRAIGHT_COST)
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
	local function Heuristic(id)
		local cont, x, y = Position(id)
		if not cont or cont ~= gcont then
			return 0
		end
		return Dist(x, y, gx, gy) / FLIGHT
	end
	local gScore, from, closed = { S = 0 }, {}, {}
	local heap = NewHeap()
	heap:push("S", Heuristic("S"))
	local expanded = 0
	while true do
		local id = heap:pop()
		if not id then
			return nil
		end
		if id == "G" then
			break
		end
		if not closed[id] then
			closed[id] = true
			expanded = expanded + 1
			if expanded > 60000 then
				return nil
			end
			local base = gScore[id]
			local function Relax(other, cost)
				local tentative = base + cost
				if gScore[other] == nil or tentative < gScore[other] then
					gScore[other] = tentative
					from[other] = id
					heap:push(other, tentative + Heuristic(other))
				end
			end
			local cont, key = id:match("^(%d+)|(.+)$")
			if cont then
				cont = tonumber(cont)
				local node = live.graphs[cont] and live.graphs[cont][key]
				if node then
					local prefix = cont .. "|"
					local degree = 0
					for k, cost in pairs(node[3]) do
						Relax(prefix .. k, cost)
						degree = degree + 1
					end
					if degree <= 1 then
						-- the end of a path: cross open ground to any path nearby
						local near = NodesNear(cont, node[1], node[2], JUMP)
						for k, d in pairs(near) do
							if k ~= key and node[3][k] == nil then
								Relax(prefix .. k, d / WALK * JUMP_COST)
							end
						end
					end
				end
			end
			if extra[id] then
				for other, cost in pairs(extra[id]) do
					Relax(other, cost)
				end
			end
		end
	end
	-- Walk back.
	local ids = {}
	local id = "G"
	while id do
		table.insert(ids, 1, id)
		id = from[id]
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
			points[#points + 1] = { cont, x, y, kind }
		end
	end
	return points, gScore.G
end

--------------------------------------------------------------------------------
-- Current route
--------------------------------------------------------------------------------

local route = nil        -- { points = {...}, cost = seconds, length = yards, dest = { cont, x, y } }
local destination = nil  -- { cont, x, y, mapID, mx, my, label }
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

local function TrackedQuestID()
	local questID
	if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
		local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
		questID = ok and Plain(id) or nil
	elseif GetSuperTrackedQuestID then
		local ok, id = pcall(GetSuperTrackedQuestID)
		questID = ok and Plain(id) or nil
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

function M:SetDestination(mapID, x, y, label)
	local cont, yx, yy = ToYards(mapID, x, y)
	if not cont then
		return false
	end
	destination = { cont = cont, x = yx, y = yy, mapID = mapID, mx = x, my = y, label = label }
	Plan(true, true)
	return true
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

-- Index and cost (seconds) of the candidate cheapest to reach by route.
function M:Cheapest(candidates)
	local pcont, px, py = PlayerYards()
	if not pcont then
		return nil
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

function M:IsTaxiUsable(id)
	local t = taxis and taxis[id]
	if not t then
		return false
	end
	RefreshDiscovered()
	return TaxiUsable(id, t)
end

function M:HasDestination()
	return destination ~= nil, destination and destination.label
end

function M:Clear()
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

local function Record()
	if not (M.isEnabled and M.db.learn) then
		recordSkip = "learning is off"
		return
	end
	local okI, inInstance = pcall(IsInInstance)
	if not okI or inInstance then
		recordSkip = okI and "in an instance" or "IsInInstance failed"
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
		-- Landed: one edge from take-off to landing.
		local cont, x, y = PlayerYards()
		if cont and cont == taxiStart[1] then
			local akey, a = AddNode(cont, taxiStart[2], taxiStart[3])
			local bkey, b = AddNode(cont, x, y)
			if akey ~= bkey then
				Link(a, akey, b, bkey, Dist(taxiStart[2], taxiStart[3], x, y) / FLIGHT + 20)
			end
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
		local key, node = AddNode(cont, x, y)
		if key ~= last.key and d <= LINK then
			local prev = live.graphs[cont][last.key]
			if prev then
				Link(node, key, prev, last.key, d / WALK)
			end
		end
		last = { cont = cont, key = key, x = x, y = y }
	else
		local key = AddNode(cont, x, y)
		last = { cont = cont, key = key, x = x, y = y }
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
local ART_PINS = {
	PIN_FRAME_LEVEL_MAP_EXPLORATION = true, PIN_FRAME_LEVEL_MAP_HIGHLIGHT = true,
	PIN_FRAME_LEVEL_DEBUG = true, PIN_FRAME_LEVEL_MAP_LINK = true,
}
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
			if kind and not ART_PINS[kind] then
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
		mapFrame:SetScript("OnSizeChanged", function() C_Timer.After(0, DrawWorldMap) end)
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
	WorldMapFrame:HookScript("OnShow", function() C_Timer.After(0, DrawWorldMap) end)
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

local function EnsureMinimapFrame()
	if mm or not Minimap then
		return
	end
	mm = CreateFrame("Frame", nil, Minimap)
	mm:SetAllPoints(Minimap)
	mm:SetFrameLevel(Minimap:GetFrameLevel() + 6)
	mmPainter = NewPainter(mm)
	mm.text = mm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	mm.text:SetPoint("TOP", Minimap, "BOTTOM", 0, -2)
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
	arrow:SetMovable(true)
	arrow:EnableMouse(true)
	arrow:RegisterForDrag("LeftButton")
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
	arrow.distance:SetPoint("TOP", arrow.icon, "BOTTOM", 0, -2)
	arrow.distance:SetTextColor(1, 0.82, 0.25)
	arrow.label = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	arrow.label:SetPoint("TOP", arrow.distance, "BOTTOM", 0, -1)
	arrow.label:SetWidth(180)
	arrow.label:SetWordWrap(false)
	arrow:SetScript("OnDragStart", function(self) self:StartMoving() end)
	arrow:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local x, y = self:GetCenter()
		local ux, uy = UIParent:GetCenter()
		M.db.arrowX, M.db.arrowY = math.floor(x - ux + 0.5), math.floor(y - uy + 0.5)
		MelloUI:NotifySettingChanged(M.name, "arrowX", M.db.arrowX)
	end)
	arrow:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Route", 1, 1, 1)
		GameTooltip:AddLine("Points along the next leg of the route. Drag to move.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)
	arrow.frameAge = 0
	arrow:SetScript("OnUpdate", function(self, elapsed)
		self.frameAge = self.frameAge + elapsed
		if self.frameAge < 1 / 60 or not self.targetX then
			return
		end
		self.frameAge = 0
		local cont, px, py = PlayerYards()
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
end

local function PlaceArrow()
	if not arrow then
		return
	end
	arrow:ClearAllPoints()
	if M.db.arrowX and M.db.arrowY then
		arrow:SetPoint("CENTER", UIParent, "CENTER", M.db.arrowX, M.db.arrowY)
	else
		arrow:SetPoint("TOP", UIParent, "TOP", 0, -40)
	end
	arrow:SetScale(tonumber(M.db.arrowScale) or 1)
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
	local cont, px, py = PlayerYards()
	local arrowShown = cont and UpdateArrow(cont, px, py) or false
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
	if arrow and not (destination and M.isEnabled and M.db.arrow) then
		arrow:Hide()
	end
	if mm then
		mm:SetShown((route ~= nil or destination ~= nil) and M.isEnabled and (M.db.minimap or M.db.distanceText or M.db.arrow))
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

local function AdoptSaved()
	if type(MelloUIRoutes) == "table" and not mergedSaved then
		mergedSaved = true
		local added = Merge(MelloUIRoutes)
		if added > 0 then
			BuildDocks()
		end
		return true
	end
	return false
end

local function LoadBaked()
	if type(MelloUI_RoadData) == "table" then
		MergeRoads(MelloUI_RoadData)
	end
	if type(MelloUI_RouteData) == "table" then
		Merge(MelloUI_RouteData)
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
local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
	MelloUIRoutes = LearnedOnly()
end)

eventFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGOUT" then
		MelloUIRoutes = LearnedOnly()
	elseif event == "PLAYER_ENTERING_WORLD" then
		last = nil
		taxiStart = nil
		C_Timer.After(1, function() ReadWaypoint() end)
	elseif event == "USER_WAYPOINT_UPDATED" or event == "SUPER_TRACKING_CHANGED" then
		ReadWaypoint()
	elseif event == "QUEST_POI_UPDATE" or event == "QUEST_LOG_UPDATE" then
		if destination and destination.fromQuest then
			poiCache[destination.questID] = nil
		end
	elseif event == "TAXIMAP_OPENED" then
		-- The routes are known a moment after the map opens.
		C_Timer.After(0.2, LearnFlights)
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
		-- through the setting path, so the macro backup forgets the old spot
		MelloUI:NotifySettingChanged(M.name, "arrowX", nil)
		MelloUI:NotifySettingChanged(M.name, "arrowY", nil)
		PlaceArrow()
		MelloUI:Print("Arrow back at the top centre of the screen.")
	elseif msg == "reset confirm" then
		live = { graphs = {}, pins = live.pins }
		MelloUIRoutes = live
		-- the traced roads are not learned data: back in, counted afresh
		tracedNodes = 0
		graphVersion = graphVersion + 1
		if type(MelloUI_RoadData) == "table" then
			MergeRoads(MelloUI_RoadData)
		end
		M:Clear()
		MelloUI:Print("Learned paths wiped for this session. Also delete Media\\RouteData.lua (or rerun the baker after the next /reload) to forget them for good.")
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
		MelloUI:Print("Route: %d learned points, %d traced road points, %d links, %d docks, %d flight points (%d usable)%s.",
			nodes - tracedNodes, tracedNodes, edges, docks and #docks or 0,
			taxiCount, usable, mergedSaved and "" or " (saved variable not loaded by the client yet)")
		if discovered then
			local n, sample = 0, {}
			for name in pairs(discovered.names) do
				n = n + 1
				if #sample < 4 then sample[#sample + 1] = name end
			end
			print(string.format("   discovered flight points per the world map: %d (%s)", n, table.concat(sample, ", ")))
		else
			print("   the client lists no flight points for the maps, so every flight point counts as usable.")
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
		print(string.format("   recorder: %d breadcrumbs this session, ticks %d%s", recorded, tickCount,
			recordSkip ~= "" and (", last call skipped: " .. recordSkip) or ""))
		do
			local cont, px, py = PlayerYards()
			if cont then
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
		print("   /route clear   |   /route arrow reset   |   /route reset   |   /route dots   |   the baker: python Tools/bake_routes.py --watch")
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
	if mm and not mm.ticking then
		mm.ticking = true
		mm:SetScript("OnUpdate", MinimapTick)
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
end

function M:OnDisable()
	eventFrame:UnregisterAllEvents()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	route = nil
	Redraw()
end

function M:OnSettingChanged(key, value, db)
	self.db = db
	PlaceArrow()
	Redraw()
end

MelloUI:Profile("Route", "breadcrumbs + planning tick", Tick)
MelloUI:Profile("Route", "minimap drawing", MinimapTick)
MelloUI:Profile("Route", "world map drawing", DrawWorldMap)

--------------------------------------------------------------------------------
-- MelloUI Map - the layers (docs/plans/seamless-map.md, stage M1)
--
-- What the map shows over its art, each a layer of pins (MapPins.lua) fed
-- from the client and from MelloUI's own data, across the whole world at once
-- -- never only the zone under the view:
--
--   the player     the game's own map arrow, turned by the facing
--   the group      your party or raid wherever each one is (their own map: another
--                  zone, the other continent), each one's class pin (the set's
--                  class_<CLASS>: a disc in the class colour), the name on hover;
--                  at every zoom
--   waypoint       your pin (the game's own map pin): drawn while Route is off
--                  (with Route on Route draws its goal: here only its hover and
--                  its click); Shift-click: its link in the chat
--   flights        the flight masters: the client's own nodes on each continent
--                  (C_TaxiMap, by node ID; one you have not learned paler),
--                  your side's and the neutral ones; the Quest List's data when
--                  the client lists none
--   transports     boats, zeppelins, portals and the tram (the Quest List's
--                  data), one pin a dock with every way from it on hover;
--                  (2.1.0) from the world's zoom on, docks that touch one pin
--                  (their trails: MapTrails.lua)
--   entrances      dungeons and raids (the Quest List's data and the client's),
--                  their levels on hover in the colour of how hard they are;
--                  (2.1.0) from the world's zoom on, doors that touch one pin
--                  with their count
--   places         (2.1.0, qu-01: the user's picks W1 and P2 of BuildData/
--                  output/qu01_map_sketch) the capitals the world map names
--                  (MapData.towns: the client's AreaPOI), a gold seal with the
--                  name beside it, from the world's zoom; the towns smaller,
--                  named on hover, from a continent's; both to a zone's (the
--                  zone names' NAMES_TO)
-- The places, the docks, the doors and your quests (MapObjectives.lua) are
-- kept apart from the world's zoom on (MapPins: merged, stepped aside, named)
--   route          Route's trail and its goal flag (the World Marker's goal is
--                  the same), by Route's own painter, across continents
--   quests         the quest givers of every zone and city: the Quest List's own
--                  groups, picture and tooltip, from a zone's zoom on
--   names          (M2) each zone's name on the soft shade, from a continent's
--                  zoom to a zone's
--   gossip         (GitHub issue 2) the game's marker from a guard's directions
--                  (C_GossipInfo), its name on hover, at every zoom; read when
--                  the window opens and when the game says it changed
--
-- The places of the data are the client's: GetMapPosFromWorldPos turns its
-- world yards into a continent's position, the canvas carries that on.
--
-- Read while the window shows (its OnUpdate, a tenth of a second at most);
-- nothing runs while it is closed. Positions and the facing are read through
-- MelloUI.Safe: a secret or missing one leaves the pin where it was, or takes
-- it away (an instance's own map: no place on the world).
--
--   Layers.Init(canvas, pins)   the layers made (the window's first open)
--   Layers.Tick(elapsed)        the window's OnUpdate
--   Layers.GossipChanged()      the game set its directions marker or took it away
--   Layers.FindMe()             a glide to the player
--   Layers.Group(pins, map, seen) (2.1.17) the group on another canvas's pins (a battleground's own map)
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Map (MapLayers)")
local Finite = MelloUI.Safe.Finite
local W = MelloUI.Widgets
local Text = MelloUI.Safe.Text
local pairs, ipairs, pcall, type, tostring = pairs, ipairs, pcall, type, tostring
local wipe = wipe

local Layers = {}
ns.Layers = Layers

local T = {
	EVERY = 0.1,             -- the positions read at most this often
	ARROW_SIZE = 26,
	DOT_SIZE = 12,
	FIND_ZOOM = 6,           -- Find me: at least this close
	ICONS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\",
	ARROW_ATLAS = "UI-WorldMapArrow",                 -- the game's own map arrow
	ARROW_FILE = "Interface\\Minimap\\MinimapArrow",  -- (if the atlas is missing)
	-- the stack (MapPins' layer order): the places under the group, the group under the player; (2.1.65) your corpse
	-- over the group, as the game's own map stacks it (Blizzard_WorldMap.lua: PIN_FRAME_LEVEL_CORPSE after the group's)
	SPIRITS_FROM = 2.5,      -- (2.1.92) the spirit healers from a zone's zoom on (MapAddonPins' ZONE_FROM: as other pins)
	SPIRITS_AGAIN = 5,       -- (2.1.92) ... their list asked again this often while Questie's is not ready yet
	ORDER = { towns = 7, names = 8, places = 9, entrances = 10, transports = 12, spirits = 13, flights = 14, quests = 20,
		gossip = 26,
		route = 30, waypoint = 32, group = 40, corpse = 45, player = 50 },
	GOSSIP_ICON = "chat_general",   -- a guard's directions: the speech bubble (the game's gossip icon in MapAddonPins too)
	MEMBER_SIZE = 16,        -- a party member's class pin (the user, 2026-10-20: "in the theme", "enough just in the color")
	PIN_GOAL = "goal_pin",   -- the game's waypoint, while Route is off
	NAMES_FROM = 1.15,       -- (M2) the zone names from a continent's zoom ...
	NAMES_TO = 6.5,          -- ... to a zone's (closer, the zone's own art names its places)
	NAME_SHADE = 0.6,        -- the soft shade under a name
	NAME_GAP = 6,            -- px kept free round a name
	LEVEL_GAP = 0,           -- (2.1.55) px between a zone's name and its level line under it
	LEVEL_H = 13,            -- ... the line's height in the names' room
	PLACES_FROM = 1.15,      -- the flight masters (2.1.0: and the towns) from a continent's zoom on (the world's: too many)
	PIN_SIZE = 18,
	-- (2.1.0, qu-01: the user's pick W1, "every kind at 16 px") the docks and the doors from the world's zoom on; pins of
	-- one kind that touch become one (MapPins' merge: the docks of one harbour within DOCK_MERGE px)
	PLACE_SIZE = 16,
	-- (2.1.97) two doors of one dungeon in the data are one door within this many yards (Blackfathom Deeps' and
	-- Blackrock Depths' pairs, some 15 apart); farther, each its own pin (Uldaman's side door, Maraudon's, Dire Maul's)
	DOOR_SAME = 100,
	DOCK_MERGE = 12,
	-- (P2) a capital: a slate disc in a gold rim, its name beside it; a town the same, smaller. Drawn as the sketch drew
	-- it, from the set's badge disc (sharp at every size): the gold disc, the slate core RIM px in, a dark EDGE px out
	-- (it stands off the parchment as the set's pins do; the set's thin ring_gold read as a dark dot in wowsim, qu-01 sim)
	CAPITAL_SIZE = 22,   -- (qu-04: the seal holds the city's emblem, the size the user picked it at)
	TOWN_SIZE = 9,
	CAPITAL_RIM = 2,
	TOWN_RIM = 1,
	SEAL_EDGE = 1,
	SEAL = "badge_disc",
	SEAL_GOLD = "selectedTrim",
	SEAL_DISC = "raisedPanel",
	SEAL_DARK = "innerPanel",
	CAPITAL_OWN = "map_capital",   -- (qu-04) the seal's picture where a look draws its own (Skin.ICON, a look's set)
	TOWN_OWN = "map_town",
	-- (qu-04; the user, 2026-10-31: "custom original themed icons for each city", their picks of qu04_map_icons_sketch)
	-- each capital's emblem in its seal, by the data's name (MapData.towns)
	EMBLEM = { Stormwind = "city_stormwind", Ironforge = "city_ironforge", Darnassus = "city_darnassus",
		Orgrimmar = "city_orgrimmar", ["Thunder Bluff"] = "city_thunderbluff", ["The Undercity"] = "city_undercity" },
	NEW_ALPHA = 0.45,        -- a flight master you have not learned
	TRANSPORT_ICON = { "pin_boat", "pin_zeppelin", "pin_portal", "pin_tram", "pin_zeppelin" },   -- (5: an airship, qu-03)
	ENTRANCE_ICON = { "pin_dungeon", "pin_raid" },
	-- the client's FlightPathFaction (Neutral 0, Horde 1, Alliance 2) and the data's faction (0 both, 1 Alliance, 2 Horde)
	CLIENT_SIDE = { Horde = 1, Alliance = 2 },
	DATA_SIDE = { Alliance = 1, Horde = 2 },
}
Layers.T = T

local S = { canvas = nil, pins = nil, wait = 0, seen = {}, docks = {}, built = false }
local EMPTY = {}
local floor = math.floor

local TEXT = {
	notLearned = "Not learned yet",
	spirit = "Spirit Healer",   -- (2.1.92: a graveyard the client names none for)
	yourPin = "Your pin",
	yourPinHint = "Shift-click: share it in the chat\nCtrl-right-click on the map: take it away",
	corpse = "Corpse",   -- (2.1.65: where the game's own CORPSE is missing)
	dungeon = "Dungeon",
	raid = "Raid",
	levels = "%s, levels %s",
	-- (1.2.0: Dungeon Info's lines on a door's tooltip, the user's pick B of journal_placements)
	bosses = "%d bosses: %s",
	dungeonInfo = "Click: open it in Dungeon Info",
	dungeonMap = "Click: its floor plan, with its page in Dungeon Info",   -- (2.1.0: one with a plan, MapDungeon.lua)
	-- (2.1.0) a pin that holds others (MapPins' merge): its title, its click
	dungeons = "%d dungeons",
	raids = "%d raids",
	doors = "%d dungeons and raids",
	spread = "Click: zoom in",
}

--------------------------------------------------------------------------------
-- Reading a unit's place
--------------------------------------------------------------------------------

-- (seen in the test client, 2026-11-17: Forever hands the game's waypoint's position as a plain { x, y } with no
-- GetXY -- asked by the method alone it read as nothing, so the map never laid your pin's own mark and the pad's
-- Marker button could not tell your pin under the crosshair) its fields first, the method where they are not there,
-- as Route reads it (VectorXY)
local function XY(pos)
	if type(pos) ~= "table" then
		return nil
	end
	local x, y = Finite(pos.x), Finite(pos.y)
	if not (x and y) and type(pos.GetXY) == "function" then
		local ok, gx, gy = pcall(pos.GetXY, pos)
		if ok then
			x, y = Finite(gx), Finite(gy)
		end
	end
	if not (x and y) then
		return nil
	end
	return x, y
end
Layers.XY = XY   -- (Map.lua's PadPin: the pad's Marker button on your pin)

-- the player's map (the best the client has for them), or nil
local function PlayerMap()
	local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
	return ok and Finite(id) or nil
end

local function UnitXY(mapID, unit)
	local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, unit)
	if not ok then
		return nil
	end
	return XY(pos)
end

--------------------------------------------------------------------------------
-- The player
--------------------------------------------------------------------------------

local PLAYER = { size = T.ARROW_SIZE, sub = 2, tip = nil }

-- the player's world point now (the map opens on it), or nil: an instance's own map, no place, a secret
function Layers.PlayerPoint()
	local mapID = PlayerMap()
	if not (mapID and S.canvas) then
		return nil
	end
	local x, y = UnitXY(mapID, "player")
	if not (x and y) then
		return nil
	end
	return S.canvas:ToWorld(mapID, x, y)
end

local function ArrowLook()
	local info = C_Texture and C_Texture.GetAtlasInfo and select(2, pcall(C_Texture.GetAtlasInfo, T.ARROW_ATLAS))
	if type(info) == "table" then
		PLAYER.atlas = T.ARROW_ATLAS
	else
		PLAYER.icon = T.ARROW_FILE
	end
end

local function Player(mapID)
	local pins = S.pins
	local x, y = UnitXY(mapID, "player")
	local pin = x and pins:SetAt("player", "player", mapID, x, y, PLAYER)
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

--------------------------------------------------------------------------------
-- The group
--------------------------------------------------------------------------------

local classSpec = {}   -- [class] = its pin (one table a class, shared by every member)

local function MemberTip(pin)
	local name = Text(UnitName(pin.data))
	return name
end

-- a member's pin: the set's class pin (its colour baked in), a plain dot when the class cannot be read
local function PinOf(class)
	local spec = classSpec[class or "?"]
	if not spec then
		if class then
			spec = { icon = T.ICONS .. "class_" .. class, size = T.MEMBER_SIZE, sub = 1, tip = MemberTip,
				lift = "class_" .. class }
		else
			spec = { icon = T.ICONS .. "map_dot", size = T.DOT_SIZE, sub = 1, tip = MemberTip }
		end
		classSpec[class or "?"] = spec
	end
	return spec
end

-- a member's place: on their own map (the client's best for them: another zone, the other continent), else on the
-- player's; the map and the place, or nil
local function MemberXY(unit, mapID)
	local ok, own = pcall(C_Map.GetBestMapForUnit, unit)
	own = ok and Finite(own) or nil
	if own then
		local x, y = UnitXY(own, unit)
		if x then
			return own, x, y
		end
	end
	if mapID then
		local x, y = UnitXY(mapID, unit)
		if x then
			return mapID, x, y
		end
	end
	return nil
end

-- (2.1.17: pins / seen another canvas's -- a battleground's own map, MapDungeon.lua -- else the world's)
local function Group(mapID, pins, seen)
	pins, seen = pins or S.pins, seen or S.seen
	for key in pairs(seen) do
		seen[key] = false
	end
	local raid = IsInRaid and IsInRaid()
	local n = raid and 40 or 4
	local prefix = raid and "raid" or "party"
	for i = 1, n do
		local unit = prefix .. i
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			local on, x, y = MemberXY(unit, mapID)
			if on then
				local _, class = UnitClass(unit)
				local pin = pins:SetAt("group", unit, on, x, y, PinOf(Text(class)))
				if pin then
					pin.data = unit
					seen[unit] = true
				end
			end
		end
	end
	for key, on in pairs(seen) do
		if not on then
			pins:Remove("group", key)
			seen[key] = nil
		end
	end
end

--------------------------------------------------------------------------------
-- The places: flights, transports, entrances
--------------------------------------------------------------------------------

local function Side()
	return UnitFactionGroup and Text((UnitFactionGroup("player"))) or nil
end

local function Data()
	local d = rawget(_G, "MelloUI_QuestListData")
	return type(d) == "table" and d or nil
end

-- the data's world yards (its continent, x, y) on the canvas: the client's own GetMapPosFromWorldPos gives the
-- continent's position, the canvas carries it on
local function WorldPoint(wcont, wx, wy)
	if not (C_Map.GetMapPosFromWorldPos and CreateVector2D) then
		return nil
	end
	local ok, mapID, pos = pcall(C_Map.GetMapPosFromWorldPos, wcont, CreateVector2D(wx, wy))
	if not ok then
		return nil
	end
	local x, y = XY(pos)
	if not x then
		return nil
	end
	return S.canvas:ToWorld(Finite(mapID), x, y)
end
Layers.WorldPoint = WorldPoint   -- (the quest log's Show: a quest's places)

-- (lift: the set's icons the glow is baked for -- the docks' and the entrances' pins; not the flight master's)
local function Icon(name, alpha, tip, lift, size)
	return { icon = T.ICONS .. name, size = size or T.PIN_SIZE, alpha = alpha, tip = tip, sub = 1,
		lift = lift and name or nil }
end

-- flights
local function FlightTip(pin)
	return pin.data, pin.spec.alpha and TEXT.notLearned or nil
end
local FLIGHT, FLIGHT_NEW = Icon("svc_flight", nil, FlightTip), Icon("svc_flight", T.NEW_ALPHA, FlightTip)

local function Flights()
	local pins, side = S.pins, Side()
	pins:Clear("flights")
	local any = false
	local api = rawget(_G, "C_TaxiMap")
	if api and api.GetTaxiNodesForMap then
		for _, p in ipairs(S.canvas.places) do
			if p.kind == "continent" or p.isle then   -- (qu-03: an isle is its own continent)
				local ok, nodes = pcall(api.GetTaxiNodesForMap, p.id)
				for _, n in ipairs(ok and type(nodes) == "table" and nodes or EMPTY) do
					local id, f = Finite(n.nodeID), Finite(n.faction)
					local x, y = XY(n.position)
					if id and x and (f == 0 or f == T.CLIENT_SIDE[side]) then
						local pin = pins:SetAt("flights", id, p.id, x, y, n.isUndiscovered == true and FLIGHT_NEW or FLIGHT)
						if pin then
							pin.data = Text(n.name)
							any = true
						end
					end
				end
			end
		end
	end
	if any then
		return
	end
	-- (the client lists none: the Quest List's flight points, learned as Route keeps them)
	local data, route = Data(), rawget(MelloUI, "Route")
	for id, row in pairs(data and data.taxiNodes or EMPTY) do
		if row[5] == 0 or row[5] == T.DATA_SIDE[side] then
			local wx, wy = WorldPoint(row[2], row[3], row[4])
			if wx then
				local known = route and route.IsTaxiUsable and select(2, pcall(route.IsTaxiUsable, route, id)) == true
				local pin = pins:Set("flights", id, wx, wy, known and FLIGHT or FLIGHT_NEW)
				if pin then
					pin.data = row[1]
				end
			end
		end
	end
end

-- (2.1.92; the user, 2026-11-27: "Spirit Healer Locations are not shown on the MelloUI Map") the spirit healers: the
-- client's own graveyards of each zone (C_DeathInfo.GetGraveyardsForMap -- what the game's own map shows them from,
-- its SelectableGraveyardDataProvider), in MelloUI's spirit healer picture, the graveyard's name on hover, from a
-- zone's zoom on (T.SPIRITS_FROM). Read once a session, as the map first opens: they do not move. The Travel group's
-- Spirit healers switch (Map.lua); the minimap wears them by the same switch (Layers.MiniSpirits)
local function SpiritTip(pin)
	return pin.data
end
local SPIRIT = Icon("svc_spirit", nil, SpiritTip)

-- the client's own graveyards of every zone under the world map (C_Map.GetMapChildrenInfo, as Core/QuestObjectives.lua's
-- scan, so the minimap needs no open map)
local function ClientSpirits(add)
	local api, maps, kinds = rawget(_G, "C_DeathInfo"), rawget(_G, "C_Map"), rawget(_G, "Enum")
	if not (type(api) == "table" and api.GetGraveyardsForMap and type(maps) == "table" and maps.GetMapChildrenInfo) then
		return
	end
	local zone = type(kinds) == "table" and type(kinds.UIMapType) == "table" and kinds.UIMapType.Zone or 3
	local root = 947
	if maps.GetFallbackWorldMapID then
		local okR, id = pcall(maps.GetFallbackWorldMapID)
		root = okR and Finite(id) or root
	end
	local okZ, zones = pcall(maps.GetMapChildrenInfo, root, zone, true)
	for _, info in ipairs(okZ and type(zones) == "table" and zones or EMPTY) do
		local map = type(info) == "table" and Finite(info.mapID) or nil
		local ok, list = false, nil
		if map then
			ok, list = pcall(api.GetGraveyardsForMap, map)
		end
		for _, g in ipairs(ok and type(list) == "table" and list or EMPTY) do
			local id = type(g) == "table" and Finite(g.graveyardID) or nil
			local x, y = XY(type(g) == "table" and g.position or nil)
			if id and x then
				add("g" .. id, map, x, y, Text(g.name))
			end
		end
	end
end

-- (the user in game, 2026-11-27: "Spirit Healer checkbox still does nothing" -- this client lists no graveyards outside
-- a battleground) Questie's spirit healers: its townsfolk list of your side's (Questie.db.char.townsfolk["Spirit
-- Healer"], built a few seconds after the login: Townsfolk.lua) at their spawns (QuestieDB's, by Questie's area ids:
-- ZoneDB's uiMap). true once read; false while Questie is not there or not ready yet
local function QuestieSpirits(add)
	local Q, L = rawget(_G, "Questie"), rawget(_G, "QuestieLoader")
	local char = type(Q) == "table" and type(Q.db) == "table" and type(Q.db.char) == "table" and Q.db.char or nil
	local ids = char and type(char.townsfolk) == "table" and char.townsfolk["Spirit Healer"] or nil
	if type(ids) ~= "table" or type(L) ~= "table" or type(L.ImportModule) ~= "function" then
		return false
	end
	local okD, DB = pcall(L.ImportModule, L, "QuestieDB")
	local okZ, ZoneDB = pcall(L.ImportModule, L, "ZoneDB")
	if not (okD and type(DB) == "table" and type(DB.QueryNPCSingle) == "function" and okZ and type(ZoneDB) == "table"
		and type(ZoneDB.GetUiMapIdByAreaId) == "function") then
		return false
	end
	local side = UnitFactionGroup and Text((UnitFactionGroup("player"))) or nil
	local mine = side == "Alliance" and "A" or side == "Horde" and "H" or nil
	for _, id in pairs(ids) do
		local okF, friendly = pcall(DB.QueryNPCSingle, id, "friendlyToFaction")
		friendly = okF and Text(friendly) or nil
		local okS, spawns = pcall(DB.QueryNPCSingle, id, "spawns")
		if okS and type(spawns) == "table" and (not friendly or friendly == "AH" or friendly == mine) then
			local okN, name = pcall(DB.QueryNPCSingle, id, "name")
			for area, list in pairs(spawns) do
				local okM, map = pcall(ZoneDB.GetUiMapIdByAreaId, ZoneDB, area)
				map = okM and Finite(map) or nil
				for i, p in ipairs(map and type(list) == "table" and list or EMPTY) do
					local x, y = type(p) == "table" and Finite(p[1]) or nil, type(p) == "table" and Finite(p[2]) or nil
					if x and y and x >= 0 and y >= 0 then
						add("q" .. tostring(id) .. ":" .. tostring(area) .. ":" .. i, map, x / 100, y / 100,
							okN and Text(name) or nil)
					end
				end
			end
		end
	end
	return true
end

-- every spirit healer, once a session: { id, map, x, y, name } on its map -- the client's graveyards, else Questie's.
-- While neither has any yet (Questie not ready: its list is built after the login) nothing is kept and the list is
-- asked again, at most every T.SPIRITS_AGAIN seconds
local spiritList, spiritAsked = nil, nil
local function SpiritList()
	if spiritList then
		return spiritList
	end
	local now = GetTime and GetTime() or 0
	if spiritAsked and now - spiritAsked < T.SPIRITS_AGAIN then
		return EMPTY
	end
	spiritAsked = now
	local list, seen = {}, {}
	local function add(id, map, x, y, name)
		if not seen[id] then
			seen[id] = true
			list[#list + 1] = { id = id, map = map, x = x, y = y, name = name }
		end
	end
	ClientSpirits(add)
	local ready = #list > 0 or QuestieSpirits(add) or not rawget(_G, "QuestieLoader")
	if ready then
		spiritList = list
	end
	return list
end
Layers.SpiritList = SpiritList   -- (the minimap's, and the tests')

-- the map's spirit healers laid; true once the list is the session's (laid again at each open until then)
local function Spirits()
	local pins = S.pins
	pins:Clear("spirits")
	for _, g in ipairs(SpiritList()) do
		local pin = pins:SetAt("spirits", g.id, g.map, g.x, g.y, SPIRIT)
		if pin then
			pin.data = g.name or W.Tr(TEXT.spirit)
		end
	end
	return spiritList ~= nil
end

-- (2.1.50; the user, 2026-11-13: "do the flight masters too" -- the rule: the minimap wears what the big map wears)
-- the flight masters on the minimap as this map lays them: MelloUI's flight picture, one not learned yet paler (FLIGHT,
-- FLIGHT_NEW), named on hover, exactly while this map's Flight masters layer is on (the Map module on) -- on Route's
-- minimap layer (Route on: M.WantMinimap), from Route's own flight points (Route.Taxis: your side's and the neutral
-- ones, in its yards; learned as Route keeps them), the ones inside the minimap. Questie's flight masters there are out
-- of sight meanwhile (Core/QuestieLook.lua: MiniFlights). Nothing at login but the switch; the list a continent, read
-- again when a flight master's map closes
local MINI = { OWNER = "Map flight masters", SIZE = 13 }   -- (PIN_SIZE as the quest marks scale: 14 of their 20)
T.MINI_FLIGHT = MINI
local mini = { marks = {}, n = 0, cont = nil, list = nil, want = false, closed = nil }
Layers.mini = mini

local function MiniFlightLeave(f)
	if GameTooltip:GetOwner() == f then
		GameTooltip:Hide()
	end
end

local function MiniFlightEnter(f)
	local P = MelloUI.Look and MelloUI.Look.TipPalette and MelloUI.Look.TipPalette() or MelloUI.Palette
	local t, m = P.text, P.mutedText
	local tip = GameTooltip
	tip:SetOwner(f, "ANCHOR_CURSOR")
	tip:SetText(f.name or "", t[1], t[2], t[3])
	if f.new then
		tip:AddLine(W.Tr(TEXT.notLearned), m[1], m[2], m[3])
	end
	tip:Show()
end

-- a mark (made the first time it is needed): the picture, the mouse's motion only (the minimap keeps its clicks)
local function MiniFlightMark(i, frame)
	local f = mini.marks[i]
	if not f then
		f = CreateFrame("Frame", nil, frame)
		f:SetFrameLevel(frame:GetFrameLevel() + 1)   -- (under the quest marks)
		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetAllPoints(f)
		W.Icon(f.icon, "svc_flight")
		if f.SetMouseClickEnabled then
			f:EnableMouse(true)
			f:SetMouseClickEnabled(false)
			f:SetScript("OnEnter", MiniFlightEnter)
			f:SetScript("OnLeave", MiniFlightLeave)
			f:SetScript("OnHide", MiniFlightLeave)
		end
		mini.marks[i] = f
	end
	return f
end

-- the continent's flight points, each learned or not (once a continent; again after a flight master's map)
local function MiniFlightList(cont)
	if mini.cont == cont and mini.list then
		return mini.list
	end
	local R = MelloUI.Route
	local list = {}
	local ok, taxis = pcall(R.Taxis)
	for id, t in pairs(ok and type(taxis) == "table" and taxis or EMPTY) do
		if t.cont == cont then
			local okU, known = pcall(R.IsTaxiUsable, R, id)
			list[#list + 1] = { x = t.x, y = t.y, name = t.name, new = not (okU and known == true) }
		end
	end
	mini.cont, mini.list = cont, list
	return list
end

-- Route's minimap layer's tick (cont nil: hidden)
function Layers.MiniFlightsDraw(cont, round, R, RX, RY)
	local Route = MelloUI.Route
	local frame = Route.MinimapFrame()
	local n = 0
	if cont and frame then
		local Offset, m = Route.MinimapOffset, MINI.SIZE / 2
		for _, p in ipairs(MiniFlightList(cont)) do
			local gx, gy = Offset(p.x, p.y)
			local on
			if round then
				on = gx * gx + gy * gy <= (R - m) * (R - m)
			else
				on = math.abs(gx) <= RX - m and math.abs(gy) <= RY - m
			end
			if on then
				n = n + 1
				local f = MiniFlightMark(n, frame)
				f.name, f.new = p.name, p.new
				local a = p.new and T.NEW_ALPHA or 1
				if f.atAlpha ~= a then
					f.atAlpha = a
					f:SetAlpha(a)
				end
				Route.MarkPlace(f, MINI.SIZE, frame, "CENTER", gx, gy)
			end
		end
	end
	for i = n + 1, mini.n do
		mini.marks[i]:Hide()
	end
	mini.n = n
end

-- (Map.lua: its OnEnable and OnDisable, its Flight masters switch) the minimap's flight masters wanted or not
function Layers.MiniFlights(on)
	local R = MelloUI.Route
	on = on and type(R) == "table" and type(R.WantMinimap) == "function" and true or false
	mini.want, mini.list = on, nil
	if on and not mini.closed then
		-- (a flight master's map closed: what you learned there)
		mini.closed = CreateFrame("Frame")
		mini.closed:RegisterEvent("TAXIMAP_CLOSED")
		Perf.SetScript(mini.closed, "OnEvent", function()
			mini.list = nil
		end)
	end
	if type(R) == "table" and type(R.WantMinimap) == "function" then
		R.WantMinimap(MINI.OWNER, on and Layers.MiniFlightsDraw or nil)
	end
end

-- (2.1.92) the spirit healers on the minimap as this map lays them, by its Spirit healers switch (the Map module on),
-- on Route's minimap layer as the flight masters: the graveyards in Route's yards a continent (the map's list,
-- Route.ToYards), the ones inside the minimap, named on hover. The list made at the first draw, not at login
local MINI_SPIRIT = { OWNER = "Map spirit healers", SIZE = 13 }
local spiritMini = { marks = {}, n = 0, byCont = nil }
Layers.spiritMini = spiritMini

local function MiniSpiritEnter(f)
	local P = MelloUI.Look and MelloUI.Look.TipPalette and MelloUI.Look.TipPalette() or MelloUI.Palette
	local t = P.text
	GameTooltip:SetOwner(f, "ANCHOR_CURSOR")
	GameTooltip:SetText(f.name or W.Tr(TEXT.spirit), t[1], t[2], t[3])
	GameTooltip:Show()
end

local function MiniSpiritMark(i, frame)
	local f = spiritMini.marks[i]
	if not f then
		f = CreateFrame("Frame", nil, frame)
		f:SetFrameLevel(frame:GetFrameLevel() + 1)   -- (under the quest marks, as the flight masters)
		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetAllPoints(f)
		W.Icon(f.icon, "svc_spirit")
		if f.SetMouseClickEnabled then
			f:EnableMouse(true)
			f:SetMouseClickEnabled(false)
			f:SetScript("OnEnter", MiniSpiritEnter)
			f:SetScript("OnLeave", MiniFlightLeave)
			f:SetScript("OnHide", MiniFlightLeave)
		end
		spiritMini.marks[i] = f
	end
	return f
end

-- the graveyards in Route's yards, a list a continent (made once: the map's list read through Route.ToYards)
local function MiniSpiritList(cont)
	if not spiritMini.byCont then
		local R, by = MelloUI.Route, {}
		local list = SpiritList()
		if not spiritList then
			return EMPTY   -- (Questie's list not ready yet: asked again, SpiritList's own pace)
		end
		for _, g in ipairs(list) do
			local ok, c, x, y = pcall(R.ToYards, g.map, g.x, g.y)
			c, x, y = ok and Finite(c) or nil, ok and Finite(x) or nil, ok and Finite(y) or nil
			if c and x and y then
				by[c] = by[c] or {}
				by[c][#by[c] + 1] = { x = x, y = y, name = g.name }
			end
		end
		spiritMini.byCont = by
	end
	return spiritMini.byCont[cont] or EMPTY
end

-- Route's minimap layer's tick (cont nil: hidden)
function Layers.MiniSpiritsDraw(cont, round, R, RX, RY)
	local Route = MelloUI.Route
	local frame = Route.MinimapFrame()
	local n = 0
	if cont and frame then
		local Offset, m = Route.MinimapOffset, MINI_SPIRIT.SIZE / 2
		for _, p in ipairs(MiniSpiritList(cont)) do
			local gx, gy = Offset(p.x, p.y)
			local on
			if round then
				on = gx * gx + gy * gy <= (R - m) * (R - m)
			else
				on = math.abs(gx) <= RX - m and math.abs(gy) <= RY - m
			end
			if on then
				n = n + 1
				local f = MiniSpiritMark(n, frame)
				f.name = p.name
				Route.MarkPlace(f, MINI_SPIRIT.SIZE, frame, "CENTER", gx, gy)
			end
		end
	end
	for i = n + 1, spiritMini.n do
		spiritMini.marks[i]:Hide()
	end
	spiritMini.n = n
end

-- (Map.lua: its OnEnable and OnDisable, its Spirit healers switch) the minimap's spirit healers wanted or not
function Layers.MiniSpirits(on)
	local R = MelloUI.Route
	if type(R) == "table" and type(R.WantMinimap) == "function" and type(R.ToYards) == "function" then
		R.WantMinimap(MINI_SPIRIT.OWNER, on and Layers.MiniSpiritsDraw or nil)
	end
end

-- transports: one pin a dock, every way from it on hover (2.1.0: docks that touch, every way from each, the harbour
-- named once)
local tipLines = {}
local function DockTip(pin)
	if not pin.members then
		local lines = {}
		for _, line in ipairs(pin.data.lines or EMPTY) do
			lines[#lines + 1] = W.Tr(line)
		end
		return W.Tr(pin.data.title), table.concat(lines, "\n")
	end
	wipe(tipLines)
	for _, m in ipairs(pin.members) do
		local d = m.data
		local other = type(d) == "table" and d.title ~= pin.data.title and d.title
		for _, line in ipairs(type(d) == "table" and d.lines or EMPTY) do
			line = other and W.Tr("%s: %s"):format(W.Tr(other), W.Tr(line)) or W.Tr(line)
			local said = false
			for _, l in ipairs(tipLines) do
				if l == line then
					said = true
					break
				end
			end
			if not said then
				tipLines[#tipLines + 1] = line
			end
		end
	end
	tipLines[#tipLines + 1] = W.Tr(TEXT.spread)   -- (its click glides in until they part, as a door's and a quest's)
	return W.Tr(pin.data.title), table.concat(tipLines, "\n")
end
local transportSpec = {}
local function TransportSpec(kind)
	local spec = transportSpec[kind]
	if not spec then
		spec = Icon(T.TRANSPORT_ICON[kind], nil, DockTip, true, T.PLACE_SIZE)
		transportSpec[kind] = spec
	end
	return spec
end

local function Transports()
	local pins, side, data = S.pins, Side(), Data()
	pins:Clear("transports")
	local docks = S.docks
	wipe(docks)
	for _, row in ipairs(data and data.transports or EMPTY) do
		local kind, f = row[1], row[2]
		if T.TRANSPORT_ICON[kind] and (f == 0 or f == T.DATA_SIDE[side]) then
			local wx, wy = WorldPoint(row[5], row[6], row[7])
			if wx then
				local key = floor(wx * 4) .. ":" .. floor(wy * 4)
				local dock = docks[key]
				if not dock then
					dock = { title = row[4], lines = {}, kind = kind }
					docks[key] = dock
					local pin = pins:Set("transports", key, wx, wy, TransportSpec(kind))
					if pin then
						pin.data = dock
					end
				end
				dock.lines[#dock.lines + 1] = row[3]
			end
		end
	end
end

-- entrances: dungeons and raids, their levels in the colour of how hard they are (the Quest List's own colours)
local function LevelText(lv)
	local lo, hi = lv[1], lv[2]
	local QL = rawget(MelloUI, "QuestList")
	local r, g, b
	if QL and QL.DifficultyColor then
		r, g, b = QL.DifficultyColor(lo)
	elseif GetQuestDifficultyColor then
		local ok, c = pcall(GetQuestDifficultyColor, lo)
		if ok and type(c) == "table" then
			r, g, b = c.r, c.g, c.b
		end
	end
	local text = (hi and hi > lo) and (lo .. "-" .. hi) or tostring(lo)
	if not (r and g and b) then
		return text
	end
	return string.format("|cff%02x%02x%02x%s|r", floor(r * 255), floor(g * 255), floor(b * 255), text)
end

-- (1.2.0) Dungeon Info's instance behind a door, when Dungeon Info is there and on (MelloUI_DungeonInfo)
local function DungeonInfoOf(pin)
	local J = rawget(MelloUI, "DungeonInfo")
	local d = pin.data
	if not (type(J) == "table" and J.Get and J.M and J.M.isEnabled and type(d) == "table") then
		return nil
	end
	-- (2.1.54; the user: "clicking on the dungeon entrance on the map, that it opens the dungeon map and dungeon info
	-- accordingly") a door with no key of its own -- the client's, one learned by walking in, a Forever door named in
	-- the data before its instance was known (The Drowned City, The Shaper's Terrace) -- by its exact name
	local inst = d.dungeonID and d.dungeonID ~= 0 and J.Get(d.dungeonID) or nil
	if not inst and J.Named and d.name then
		inst = J.Named(d.name)
	end
	return J, inst
end

-- the door's click line: its floor plan with the page when the map has one (2.1.0), the page alone else
local function ClickLine(inst)
	local D = ns.Dungeon
	return W.Tr(D and D.Has(inst.map) and TEXT.dungeonMap or TEXT.dungeonInfo)
end

-- its bosses in a line ("4 bosses: Oggleflint, Taragaman the Hungerer, ..."), nil with none known
local function BossLine(inst)
	local n = #inst.bosses
	if n == 0 then
		return nil
	end
	local J = rawget(MelloUI, "DungeonInfo")
	local names = {}
	for i, b in ipairs(inst.bosses) do
		names[i] = (J and J.BossShown) and J.BossShown(b) or b.name   -- (2.1.60: in the client's language)
	end
	return W.Tr(TEXT.bosses):format(n, table.concat(names, ", "))
end

-- (2.1.0) a pin that holds other doors: how many, each one's name and levels, a click zooms in
local function DoorsTip(pin)
	local dungeons, raids = 0, 0
	wipe(tipLines)
	for _, m in ipairs(pin.members) do
		local d = m.data
		if type(d) == "table" then
			if d.kind == 2 then
				raids = raids + 1
			else
				dungeons = dungeons + 1
			end
			tipLines[#tipLines + 1] = d.levels and (d.name .. "  " .. LevelText(d.levels)) or d.name
		end
	end
	local title = raids == 0 and W.Tr(TEXT.dungeons):format(dungeons) or dungeons == 0 and W.Tr(TEXT.raids):format(raids)
		or W.Tr(TEXT.doors):format(dungeons + raids)
	tipLines[#tipLines + 1] = W.Tr(TEXT.spread)
	return title, table.concat(tipLines, "\n")
end

local function EntranceFill(tip, pin)
	local QL = rawget(MelloUI, "QuestList")
	if not (type(QL) == "table" and QL.MarkTip) then
		return
	end
	if pin.members then
		local title, body = DoorsTip(pin)
		tip:SetText(W.Tr(title))
		tip:AddLine(body, 1, 1, 1, true)
		tip:Show()
		return
	end
	local d = pin.data
	pcall(QL.MarkTip, tip, "entrance", { name = d.name, dungeonID = d.dungeonID or 0, raid = d.kind == 2,
		source = d.source }, false)
	local _, inst = DungeonInfoOf(pin)
	if inst then
		local P = MelloUI.Look.TipPalette()
		local gold, text = P.selectedTrim, P.text
		local line = BossLine(inst)
		if line then
			tip:AddLine(line, text[1], text[2], text[3], true)
		end
		tip:AddLine(ClickLine(inst), gold[1], gold[2], gold[3])
		tip:Show()
	end
end

local function EntranceTip(pin)
	if pin.members then
		return DoorsTip(pin)
	end
	local d = pin.data
	local word = d.kind == 2 and TEXT.raid or TEXT.dungeon
	local line = d.levels and W.Tr(TEXT.levels):format(word, LevelText(d.levels)) or W.Tr(word)
	local J, inst = DungeonInfoOf(pin)
	if inst then
		local bosses = BossLine(inst)
		local name = (J and J.Shown) and J.Shown(inst) or d.name   -- (2.1.60: in the client's language)
		return name, line .. (bosses and ("\n" .. bosses) or "") .. "\n" .. ClickLine(inst)
	end
	return d.name, line
end

-- (1.2.0) a click on a door: its page in Dungeon Info (the map's column)
local function EntranceClick(pin, button)
	local J, inst = DungeonInfoOf(pin)
	if button == "LeftButton" and inst then
		MelloUI:PlayUISound("click")
		J.Open(inst.key)
	end
end

local ENTRANCE = { Icon(T.ENTRANCE_ICON[1], nil, EntranceTip, true, T.PLACE_SIZE),
	Icon(T.ENTRANCE_ICON[2], nil, EntranceTip, true, T.PLACE_SIZE) }
ENTRANCE[1].click, ENTRANCE[2].click = EntranceClick, EntranceClick
-- (with the Quest List: its own entrance tooltip, the quests done there with it)
local function EntranceSpec(kind)
	local QL = rawget(MelloUI, "QuestList")
	local spec = ENTRANCE[kind]
	if type(QL) == "table" and QL.MarkTip then
		spec.fillTip = EntranceFill
	end
	return spec
end

-- (2.1.54; the user, 2026-11-15: "Why do we have 2 dungeon entrances dor Hall of Thanes in ironforge") a door's name as
-- doors are told apart: "The" and the case left out -- the data's "The Hall of Thanes" and the one learned by walking in,
-- "Hall of Thanes", are one door, the data's (the Quest List's game-map pins tell them apart the same way)
local function DoorKey(name)
	return (name:lower():gsub("^the ", ""))
end

-- (2.1.97; the user, standing at Uldaman's side door: "on my location is the side entrance to Uldaman - Hall of the
-- Keepers") a door of the data already laid under its name: on the same continent within T.DOOR_SAME yards. One pin a
-- name hid every second door of a dungeon (2.1.54's rule against the Hall of Thanes' two names for one door)
local function DoorLaid(laid, row)
	for _, r in ipairs(type(laid) == "table" and laid or EMPTY) do
		local dx, dy = (r[4] or 0) - (row[4] or 0), (r[5] or 0) - (row[5] or 0)
		if r[3] == row[3] and dx * dx + dy * dy < T.DOOR_SAME * T.DOOR_SAME then
			return true
		end
	end
	return false
end

local function Entrances()
	local pins, data = S.pins, Data()
	pins:Clear("entrances")
	local seen = {}
	-- (a door only one side uses, the City of Dalaran's: yours; both while the side is unknown)
	local mine = T.DATA_SIDE[Side()]
	for _, row in ipairs(data and data.entrances or EMPTY) do
		local id, name, kind, side = row[1], row[2], row[9], row[10]
		local key = name and DoorKey(name)
		if name and not DoorLaid(seen[key], row) and ENTRANCE[kind] and (not (side and mine) or side == 0 or side == mine) then
			local wx, wy = WorldPoint(row[3], row[4], row[5])
			if wx then
				local laid = seen[key] or {}
				seen[key] = laid
				laid[#laid + 1] = row
				local lv = data.dungeonLevel and data.dungeonLevel[id]
				-- (the first door its name, each other "name#2" ...: its own pin; its name the dungeon's)
				local pin = pins:Set("entrances", #laid == 1 and name or (name .. "#" .. #laid), wx, wy, EntranceSpec(kind))
				if pin then
					pin.data = { name = name, kind = kind, levels = lv and (lv[1] or 0) > 0 and lv or nil, dungeonID = id,
						source = "data" }
				end
			end
		end
	end
	-- (2.1.54) the doors learned by walking in (the Quest List's, as the game's map shows them: Forever's newer
	-- dungeons, Alcaz Prison's and Blackmaw Hold's doors in no data yet); a click opens its page by its name
	local QL = rawget(MelloUI, "QuestList")
	local learned = type(QL) == "table" and type(QL.LearnedStore) == "function" and QL.LearnedStore("entrances") or nil
	for name, l in pairs(type(learned) == "table" and learned or EMPTY) do
		if type(name) == "string" and not seen[DoorKey(name)] and type(l) == "table" and l.mapID and l.x and l.y then
			seen[DoorKey(name)] = true
			local kind = l.raid == true and 2 or 1
			local pin = pins:SetAt("entrances", name, l.mapID, l.x, l.y, EntranceSpec(kind))
			if pin then
				pin.data = { name = name, kind = kind, source = "learned" }
			end
		end
	end
	-- (the client's own entrances on each continent: the ones the data lacks)
	local api = rawget(_G, "C_EncounterJournal")
	if not (api and api.GetDungeonEntrancesForMap) then
		return
	end
	for _, p in ipairs(S.canvas.places) do
		if p.kind == "continent" or p.isle then
			local ok, list = pcall(api.GetDungeonEntrancesForMap, p.id)
			for _, e in ipairs(ok and type(list) == "table" and list or EMPTY) do
				local name = Text(e.name)
				local x, y = XY(e.position)
				if name and x and not seen[DoorKey(name)] then
					seen[DoorKey(name)] = true
					local kind = Text(e.atlasName) == "Raid" and 2 or 1
					local pin = pins:SetAt("entrances", name, p.id, x, y, EntranceSpec(kind))
					if pin then
						pin.data = { name = name, kind = kind, source = "client" }
					end
				end
			end
		end
	end
end

-- (2.1.0, qu-01: the user's picks W1 and P2) the capitals and the towns the world map names (MapData.towns, the
-- client's AreaPOI): a capital's seal (a slate disc in a gold rim, a dark edge) with its name beside it, from the world's
-- zoom; a town's smaller, named on hover, from a continent's; both to a zone's, where its own art takes over
local function PlaceTip(pin)
	return pin.name
end

local CAPITAL = { icon = T.ICONS .. T.SEAL, size = T.CAPITAL_SIZE, tint = T.SEAL_GOLD, core = T.SEAL_DISC,
	rim = T.CAPITAL_RIM, disc = T.SEAL_DARK, edge = T.SEAL_EDGE, label = true, tip = PlaceTip, sub = 1,
	own = T.CAPITAL_OWN }
local TOWN = { icon = T.ICONS .. T.SEAL, size = T.TOWN_SIZE, tint = T.SEAL_GOLD, core = T.SEAL_DISC, rim = T.TOWN_RIM,
	disc = T.SEAL_DARK, edge = T.SEAL_EDGE, tip = PlaceTip, sub = 1, own = T.TOWN_OWN }

-- (qu-04) a capital's seal with its city's emblem (one spec a capital; the plain seal for a name with none)
local capitals = {}
local function CapitalSpec(name)
	local spec = capitals[name]
	if not spec then
		local emblem = T.EMBLEM[name]
		if not emblem then
			return CAPITAL
		end
		spec = {}
		for k, v in pairs(CAPITAL) do
			spec[k] = v
		end
		spec.emblem = T.ICONS .. emblem
		capitals[name] = spec
	end
	return spec
end

local function Places()
	local pins, data = S.pins, ns.MapData
	pins:Clear("places")
	pins:Clear("towns")
	for i, row in ipairs(data and data.towns or EMPTY) do
		local rank, name = row[1], row[2]
		local wx, wy = WorldPoint(row[3], row[4], row[5])
		if wx then
			local capital = rank == 1
			local pin = pins:Set(capital and "places" or "towns", i, wx, wy, capital and CapitalSpec(name) or TOWN)
			if pin then
				pin.name = name
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The game's marker from a guard's directions (GitHub issue 2, Nixxen,
-- 2026-11-05: no marker on this map): what the game's own GossipDataProvider
-- reads, one marker a map. The game's map asks for the one map it shows; this
-- one shows them all, so it asks each, the player's first, then the smallest
-- first (a marker on the map round it too: its place from the deepest map)
--------------------------------------------------------------------------------

local function GossipTip(pin)
	return pin.data
end

local GOSSIP = { icon = T.ICONS .. T.GOSSIP_ICON, size = T.PIN_SIZE + 4, sub = 3, tip = GossipTip }

-- its name and place (under a pcall: whatever the client handed out)
local function GossipRead(info)
	return Text(info.name), XY(info.position)
end

local gossipSeen = {}

local function GossipOn(api, mapID)
	local ok, id = pcall(api.GetPoiForUiMapID, mapID)
	id = ok and Finite(id)
	if not id or gossipSeen[id] then
		return
	end
	local got, info = pcall(api.GetPoiInfo, mapID, id)
	local read, name, x, y = pcall(GossipRead, got and info)
	local pin = read and x and y and S.pins:SetAt("gossip", id, mapID, x, y, GOSSIP)
	if pin then
		pin.data = name
		gossipSeen[id] = true
	end
end

local function Gossip()
	local api = rawget(_G, "C_GossipInfo")
	if not (api and api.GetPoiForUiMapID and api.GetPoiInfo) then
		return
	end
	wipe(gossipSeen)
	local playerMap = PlayerMap()
	if playerMap then
		GossipOn(api, playerMap)
	end
	local places, byID = S.canvas.places, S.canvas.byID
	for i = #places, 1, -1 do   -- (biggest first in the list; the fills and the ground after them are no maps)
		local p = places[i]
		if byID[p.id] == p and p.id ~= playerMap then
			GossipOn(api, p.id)
		end
	end
	for id in pairs(S.pins.layers.gossip.pins) do
		if not gossipSeen[id] then
			S.pins:Remove("gossip", id)
		end
	end
end

-- the game set its marker or took it away (DYNAMIC_GOSSIP_POI_UPDATED, while the window shows)
function Layers.GossipChanged()
	if S.pins then
		Gossip()
		S.pins:Lay()
	end
end

-- the window opened: the places laid (the data's once; the flights each time: learned ones change)
function Layers.Open()
	if not S.pins then
		return
	end
	S.shown = true
	if not S.built then
		S.built = true
		Transports()
		Entrances()
		Places()
	end
	if not S.spirits then
		S.spirits = Spirits()   -- (2.1.92: until Questie's list is there, at each open)
	end
	Flights()
	Gossip()
	S.wait = 0
	S.pins:Lay()
	Layers.Route()
end

-- a flight master's map opened or a flight point learned: the flights again
function Layers.Event()
	if S.pins then
		Flights()
		S.pins:Lay()
	end
end

--------------------------------------------------------------------------------
-- Route: its trail and its goal, drawn by Route itself (Route:DrawOn, its one
-- painter and goal mark) on the route layer's frame, at the canvas's
-- projection: a route point's continent yards -> the continent's position ->
-- world units (cached by the point: a new route is a new table) -> the view
--------------------------------------------------------------------------------

local P = { x0 = 0, y0 = 0, k = 1, cache = setmetatable({}, { __mode = "k" }), size = {} }

-- a continent's size in yards (the client's GetMapWorldSize), read once
local function Yards(cont)
	local s = P.size[cont]
	if s == nil then
		local ok, w, h = pcall(C_Map.GetMapWorldSize, cont)
		w, h = ok and Finite(w), ok and Finite(h)
		s = (w and h and w > 0 and h > 0) and { w, h } or false
		P.size[cont] = s
	end
	return s
end

-- a point of the route (its continent and yards) on the route layer's frame, from its top left
local function Project(cont, x, y, key)
	local w = key and P.cache[key]
	local wx, wy
	if w then
		wx, wy = w[1], w[2]
	else
		local s = Yards(cont)
		x, y = Finite(x), Finite(y)
		if not (s and x and y) then
			return nil
		end
		wx, wy = S.canvas:ToWorld(cont, x / s[1], y / s[2])
		if not wx then
			return nil
		end
		if key then
			P.cache[key] = { wx, wy }
		end
	end
	return (wx - P.x0) * P.k, (wy - P.y0) * P.k
end

-- the trail and the goal laid at the view now (every view, and when Route has a new route or goal)
function Layers.Route()
	local c, pins = S.canvas, S.pins
	local route = rawget(MelloUI, "Route")
	local layer = pins and pins.layers.route
	if not (layer and route and route.DrawOn and c.cx) then
		return
	end
	local current, goal = nil, nil
	if route.CurrentRoute then
		current, goal = route:CurrentRoute()
	end
	-- (nothing to draw and nothing drawn before: no work)
	S.tripBeat = route.tripBeat
	if not (current or goal or S.routeDrawn) then
		return
	end
	local k = c.k1 * c.z
	P.k, P.x0, P.y0 = k, c.cx - c.cw / (2 * k), c.cy - c.ch / (2 * k)
	local ok = pcall(route.DrawOn, route, layer.frame, Project)
	S.routeDrawn = ok and (current or goal) and true or false
	S.route, S.goal = current, goal
end

-- the window's beat: a new route or goal drawn
local function RouteChanged()
	local route = rawget(MelloUI, "Route")
	if not (route and route.CurrentRoute) then
		return
	end
	local current, goal = route:CurrentRoute()
	-- (1.2.0) a quest trip's legs found, its stop moved on: Route's tripBeat
	if current ~= S.route or goal ~= S.goal or route.tripBeat ~= S.tripBeat then
		Layers.Route()
	end
end

--------------------------------------------------------------------------------
-- The zone names (stage M2, the user's pick F): each zone's name at the
-- middle of its outline (MapData), in MelloUI's title font and the palette's
-- text, on the soft shade (MelloUI.Shade) -- from a continent's zoom to a
-- zone's; laid with every view, one anchor each, never scaled. The biggest
-- zones first: a name that would cover one already laid is left out at that
-- zoom. Made the first time each shows.
-- (2.1.55, the map's level labels: the user's pick A) with Zone levels on, a
-- smaller line under the name, the zone's level range in the game's difficulty
-- colour for you (MapLevels' Levels.Line), the name's room taller by it
--------------------------------------------------------------------------------

local NAMES = { list = {}, boxes = {} }

local function NameOf(p)
	local label = NAMES.list[p]
	if label then
		return label
	end
	local frame = NAMES.frame
	local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	local Kit = MelloUI.Kit
	if Kit and Kit.TitleFont then
		Kit:TitleFont(fs, true)
	end
	W.Paint(fs, "text", "text")
	fs:SetText(p.name)
	local band = MelloUI.Shade and MelloUI.Shade:Band(frame, { colour = "innerPanel", alpha = T.NAME_SHADE, feather = 14 })
	if band then
		band:Anchor(fs, 2, 1)
		band:SetShown(false)
	end
	label = { fs = fs, band = band, w = Finite(fs:GetStringWidth()) or 80, h = Finite(fs:GetStringHeight()) or 16,
		shown = false }
	fs:Hide()
	NAMES.list[p] = label
	return label
end

-- (2.1.55) the level line under a name: made the first time a zone shows one, in the names' face, smaller
local function LevelLine(label)
	local lv = label.lv
	if not lv then
		lv = NAMES.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		local Kit = MelloUI.Kit
		if Kit and Kit.TitleFont then
			Kit:TitleFont(lv, true)
		end
		lv:SetPoint("TOP", label.fs, "BOTTOM", 0, -T.LEVEL_GAP)
		lv:Hide()
		label.lv = lv
		-- (the names' soft shade under it too: seen in the real client, the red line was hard to read on the painting)
		local band = MelloUI.Shade and MelloUI.Shade:Band(NAMES.frame, { colour = "innerPanel", alpha = T.NAME_SHADE,
			feather = 14 })
		if band then
			band:Anchor(lv, 2, 1)
			band:SetShown(false)
		end
		label.lvBand = band
	end
	return lv
end

-- the line's text and colour for this view (nil: none), shown or hidden with the name
local function SetLevel(label, text, r, g, b)
	if text then
		local lv = LevelLine(label)
		if label.lvText ~= text then
			label.lvText = text
			lv:SetText(text)
		end
		lv:SetTextColor(r, g, b)
		if label.shown then
			lv:Show()
			if label.lvBand then
				label.lvBand:SetShown(true)
			end
		end
	elseif label.lv then
		label.lvText = nil
		label.lv:Hide()
		if label.lvBand then
			label.lvBand:SetShown(false)
		end
	end
end

local function HideName(label)
	if label.shown then
		label.shown = false
		label.fs:Hide()
		label.fs:ClearAllPoints()
		if label.band then
			label.band:SetShown(false)
		end
		if label.lv then
			label.lv:Hide()
		end
		if label.lvBand then
			label.lvBand:SetShown(false)
		end
	end
end

function Layers.Labels()
	local c, pins = S.canvas, S.pins
	if not (c and c.places and c.cx and pins) then
		return
	end
	local frame = NAMES.frame
	if not frame then
		local layer = pins:Layer("names", T.ORDER.names)
		frame = layer.frame
		NAMES.frame = frame
	end
	local to = c.z <= T.NAMES_TO
	local on = c.z >= T.NAMES_FROM and to
	local Levels = ns.Levels   -- (2.1.55: MapLevels.lua, loaded after this file)
	local k = c.k1 * c.z
	local x0, y0 = c.cx - c.cw / (2 * k), c.cy - c.ch / (2 * k)
	local boxes, n = NAMES.boxes, 0
	-- (2.1.0) the capitals' names laid with the pins (MapPins' names): a zone's name keeps clear of them
	if to then
		local lb = pins.labelBoxes
		for i = 1, pins.nLabels or 0 do
			local s = lb[i]
			n = n + 1
			local b = boxes[n]
			if not b then
				b = {}
				boxes[n] = b
			end
			b[1], b[2], b[3], b[4] = s[1], s[2], s[3], s[4]
		end
	end
	for _, p in ipairs(c.places) do
		local at = p.label
		if at then
			local label = NAMES.list[p]
			local x = (p.left + at[1] * p.w - x0) * k
			local y = (p.top + at[2] * p.h - y0) * k
			-- (qu-03) an isle's name from the world's zoom: the world's painting names the continents, never the isle
			local fits = (on or (to and p.isle)) and x > -40 and x < c.cw + 40 and y > -20 and y < c.ch + 20
			if fits then
				label = label or NameOf(p)
				-- (2.1.55) the zone's level line under it: the name's room reaches down over it
				local lvText, lr, lg, lb = nil, nil, nil, nil
				if Levels then
					lvText, lr, lg, lb = Levels.Line(p.id)
				end
				local down = lvText and T.LEVEL_H or 0
				local hw, hh = label.w / 2 + T.NAME_GAP, label.h / 2 + 2
				for i = 1, n do
					local b = boxes[i]
					if not (x + hw < b[1] or x - hw > b[3] or y + hh + down < b[2] or y - hh > b[4]) then
						fits = false
						break
					end
				end
				if fits then
					n = n + 1
					local b = boxes[n]
					if not b then
						b = {}
						boxes[n] = b
					end
					b[1], b[2], b[3], b[4] = x - hw, y - hh, x + hw, y + hh + down
					label.fs:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
					if not label.shown then
						label.shown = true
						label.fs:Show()
						if label.band then
							label.band:SetShown(true)
						end
					end
					SetLevel(label, lvText, lr, lg, lb)
				end
			end
			if label and not fits then
				HideName(label)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- (M4, the search) the named places the layers lay -- flight masters, docks,
-- dungeons and raids -- each handed to add(kind, name, icon, wx, wy)
--------------------------------------------------------------------------------

function Layers.Searchable(add)
	local pins = S.pins
	if not pins then
		return
	end
	for _, pin in pairs(pins.layers.flights and pins.layers.flights.pins or EMPTY) do
		if type(pin.data) == "string" then
			add("flight", pin.data, pin.spec and pin.spec.icon, pin.wx, pin.wy)
		end
	end
	for _, pin in pairs(pins.layers.transports and pins.layers.transports.pins or EMPTY) do
		if type(pin.data) == "table" then
			add(pin.data.kind == 5 and "airship" or "dock", pin.data.title, pin.spec and pin.spec.icon, pin.wx, pin.wy)
		end
	end
	for _, pin in pairs(pins.layers.entrances and pins.layers.entrances.pins or EMPTY) do
		local d = pin.data
		if type(d) == "table" then
			add(d.kind == 2 and "raid" or "dungeon", d.name, pin.spec and pin.spec.icon, pin.wx, pin.wy)
		end
	end
end

--------------------------------------------------------------------------------
-- The game's own map pin (C_Map's user waypoint) while Route is off: Route,
-- when on, takes the pin as its goal and draws it itself
--------------------------------------------------------------------------------

-- your pin's hover and click (the map's own lines; Shift-click: the map module's share)
local function PinTip()
	return TEXT.yourPin, TEXT.yourPinHint
end

local function PinClick(_, button)
	local map = ns.Map
	if button == "LeftButton" and IsShiftKeyDown() and map and map.SharePin then
		map:SharePin()
	end
end

local WAYPOINT = { icon = T.ICONS .. T.PIN_GOAL, size = T.PIN_SIZE + 4, sub = 3, lift = T.PIN_GOAL, tip = PinTip,
	click = PinClick }
-- (Route on: Route draws the goal; this one only takes the hover and the click over it)
local WAYPOINT_HIT = { size = T.PIN_SIZE + 4, sub = 3, tip = PinTip, click = PinClick }

local function Waypoint()
	local route = rawget(MelloUI, "Route")
	local has = C_Map.HasUserWaypoint and select(2, pcall(C_Map.HasUserWaypoint))
	local point = has == true and C_Map.GetUserWaypoint and select(2, pcall(C_Map.GetUserWaypoint))
	local mapID = type(point) == "table" and Finite(point.uiMapID)
	local x, y
	if mapID then
		x, y = XY(point.position)
	end
	if not (mapID and x) then
		S.pins:Remove("waypoint", "pin")
		return
	end
	S.pins:SetAt("waypoint", "pin", mapID, x, y, (route and route.isEnabled) and WAYPOINT_HIT or WAYPOINT)
end

--------------------------------------------------------------------------------
-- Your corpse (2.1.65; the user: "Players Corpse icon is missing from the Map and Minimap")
--------------------------------------------------------------------------------
-- The game marks it on its own world map only (Blizzard_SharedMapDataProviders/DeathMapDataProvider.lua: the map shown
-- asks C_DeathInfo.GetCorpseMapPosition, a CorpsePinTemplate pin over the group, CORPSE_RED on hover), and while this
-- map is on, M and L never open that one. So this map lays it, at the game's place in the game's own picture
-- (DeathMapDataProvider.xml: Interface\Minimap\POIIcons, its corpse cut; MelloUI's set has none: the same in every
-- look), and the minimap the same picture from the same read (CLAUDE.md rule 5), on Route's minimap layer, held just
-- inside its edge while the body is further off (as Route's goal). One switch: the Map module. Read when you die,
-- release, come back to life, change zones or enter the world (MelloUI.Coords.Corpse, the Corpse Run widget's reader
-- too), then kept: a body does not move. While you are dead with no place yet (the game may have none as it moves a
-- released ghost), read again every AGAIN s; alive, nothing runs and the minimap's mark is not wanted
local CORPSE = {
	FILE = "Interface\\Minimap\\POIIcons",
	L = 0.56640625, R = 0.6328125, T = 0.001953125, B = 0.03515625,
	SIZE = T.PIN_SIZE + 2,   -- (the game's 24 at its corpse pin's scale, 0.8)
	MINI = 14,               -- on the minimap (the flight masters' 13, the town marks' 13: a little over them)
	OWNER = "Map corpse",
	AGAIN = 1,
	EVENTS = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" },
}
T.CORPSE = CORPSE
-- on: the Map module's; dead: yours (UnitIsDeadOrGhost, the events' word where it is secret); mapID, x, y: the body's
-- place (Coords.Corpse); cont, yx, yy: the same in Route's yards (the minimap's)
local Corpse = { on = false, dead = false, wait = 0, events = nil, mark = nil, mini = false }
Layers.corpse = Corpse

local Plain = MelloUI.Safe.Value

local function CorpseTip()
	return Text(rawget(_G, "CORPSE")) or TEXT.corpse
end

-- the game's picture, cut as its pin cuts it, at the pin's size
local function CorpseLook(tex)
	MelloUI.Icons.Set(tex, CORPSE.FILE, tex:GetWidth(), CORPSE.L, CORPSE.R, CORPSE.T, CORPSE.B)
end

local CORPSE_PIN = { size = CORPSE.SIZE, sub = 4, look = CorpseLook, tip = CorpseTip }

-- this map's pin (the window's beat)
local function CorpsePin()
	local c = Corpse
	if c.on and c.mapID then
		S.pins:SetAt("corpse", "corpse", c.mapID, c.x, c.y, CORPSE_PIN)
	else
		S.pins:Remove("corpse", "corpse")
	end
end

local function CorpseMarkEnter(f)
	W.ShowTooltip(f, CorpseTip(), nil, nil, "ANCHOR_CURSOR")
end

local function CorpseMarkLeave(f)
	if GameTooltip:GetOwner() == f then
		GameTooltip:Hide()
	end
end

-- the minimap's mark (made the first time a body shows there): the picture, the mouse's motion only (the minimap keeps
-- its clicks), over the flight masters and the town marks
local function CorpseMark(frame)
	local f = Corpse.mark
	if not f then
		f = CreateFrame("Frame", nil, frame)
		f:SetFrameLevel(frame:GetFrameLevel() + 2)
		f:SetSize(CORPSE.MINI, CORPSE.MINI)
		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetAllPoints(f)
		MelloUI.Icons.Set(f.icon, CORPSE.FILE, CORPSE.MINI, CORPSE.L, CORPSE.R, CORPSE.T, CORPSE.B)
		if f.SetMouseClickEnabled then
			f:EnableMouse(true)
			f:SetMouseClickEnabled(false)
			f:SetScript("OnEnter", CorpseMarkEnter)
			f:SetScript("OnLeave", CorpseMarkLeave)
			f:SetScript("OnHide", CorpseMarkLeave)
		end
		Corpse.mark = f
	end
	return f
end

-- Route's minimap layer's tick (cont nil: hidden)
function Layers.MiniCorpseDraw(cont, round, R, RX, RY)
	local Route = MelloUI.Route
	local c = Corpse
	local frame = cont and Route and Route.MinimapFrame()
	if not (frame and c.yx and c.cont == cont) then
		if c.mark then
			c.mark:Hide()
		end
		return
	end
	local f = CorpseMark(frame)
	local gx, gy = Route.MinimapOffset(c.yx, c.yy)
	local m = CORPSE.MINI / 2
	local inside
	if round then
		inside = gx * gx + gy * gy <= (R - m) * (R - m)
	else
		inside = math.abs(gx) <= RX - m and math.abs(gy) <= RY - m
	end
	if not inside and type(Route.MinimapEdge) == "function" then
		local k = Route.MinimapEdge(gx, gy, round, R, RX, RY, m)
		gx, gy = gx * k, gy * k
	end
	Route.MarkPlace(f, CORPSE.MINI, frame, "CENTER", gx, gy)
end

-- the minimap's mark wanted while there is a body to show there (Route on: its minimap layer)
local function CorpseMini()
	local R = MelloUI.Route
	if type(R) ~= "table" or type(R.WantMinimap) ~= "function" then
		return
	end
	local want = (Corpse.on and Corpse.yx) and true or false
	if want ~= Corpse.mini then
		Corpse.mini = want
		R.WantMinimap(CORPSE.OWNER, want and Layers.MiniCorpseDraw or nil)
	end
end

-- the body's place read (Coords.Corpse), and in Route's yards for the minimap
local function CorpseRead()
	local c = Corpse
	local C = MelloUI.Coords
	local mapID, x, y
	if C and C.Corpse then
		mapID, x, y = C.Corpse()
	end
	c.mapID, c.x, c.y, c.cont, c.yx, c.yy = mapID, x, y, nil, nil, nil
	local R = MelloUI.Route
	if mapID and type(R) == "table" and type(R.ToYards) == "function" then
		local ok, cont, yx, yy = pcall(R.ToYards, mapID, x, y)
		if ok and Finite(cont) and Finite(yx) and Finite(yy) then
			c.cont, c.yx, c.yy = cont, yx, yy
		end
	end
end

-- (dead with no place yet) asked again every AGAIN s until the game has one
local function CorpseBeat(frame, elapsed)
	local c = Corpse
	c.wait = c.wait - (elapsed or 0)
	if c.wait > 0 then
		return
	end
	c.wait = CORPSE.AGAIN
	CorpseRead()
	if c.mapID or not c.dead then
		Perf.SetScript(frame, "OnUpdate", nil)
		CorpseMini()
	end
end

-- dead or not now: yours where it reads plain, else the event's word (a death, a release: dead; a ghost back to
-- life: not), else as it was
local function IsDead(event)
	local ok, dead = pcall(UnitIsDeadOrGhost, "player")
	dead = ok and Plain(dead)
	if dead ~= nil then
		return dead == true
	end
	if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
		return true
	elseif event == "PLAYER_UNGHOST" then
		return false
	end
	return Corpse.dead
end

-- a death, a release, a return to life, a new zone or world (event nil: the switch): the place read again or let go
local function CorpseCheck(event)
	local c = Corpse
	c.dead = c.on and IsDead(event) or false
	if c.dead then
		CorpseRead()
	else
		c.mapID, c.x, c.y, c.cont, c.yx, c.yy = nil, nil, nil, nil, nil, nil
	end
	if c.events then
		c.wait = CORPSE.AGAIN
		Perf.SetScript(c.events, "OnUpdate", (c.dead and not c.mapID) and CorpseBeat or nil)
	end
	CorpseMini()
	if S.pins and S.shown then
		CorpsePin()
		S.pins:Lay()
	end
end

-- (Map.lua: its OnEnable and OnDisable) the corpse on this map and the minimap wanted or not
function Layers.Corpse(on)
	local c = Corpse
	c.on = on and true or false
	if c.on and not c.events then
		c.events = CreateFrame("Frame")
		Perf.SetScript(c.events, "OnEvent", function(_, event)
			CorpseCheck(event)
		end)
	end
	if c.events then
		for _, event in ipairs(CORPSE.EVENTS) do
			if c.on then
				c.events:RegisterEvent(event)
			else
				c.events:UnregisterEvent(event)
			end
		end
	end
	CorpseCheck(nil)
end

--------------------------------------------------------------------------------
-- The window's beat
--------------------------------------------------------------------------------

function Layers.Tick(elapsed)
	if not S.pins then
		return
	end
	-- (a new route drawing in, Route's M.DrawIn, as on the game's map: drawn again each frame while it grows, once
	-- more when it is whole)
	local R = rawget(MelloUI, "Route")
	local growing = R and R.DrawIn and R.DrawIn.on and true or false
	if growing or S.growing then
		S.growing = growing
		Layers.Route()
	end
	S.wait = S.wait - (elapsed or 0)
	if S.wait > 0 then
		return
	end
	S.wait = T.EVERY
	local mapID = PlayerMap()
	if mapID then
		Player(mapID)
	else
		S.pins:Clear("player")
	end
	-- (the group on their own maps: shown while you are in an instance too)
	Group(mapID)
	Waypoint()
	CorpsePin()   -- (2.1.65)
	S.pins:Lay()
	RouteChanged()
end

-- (2.1.17) the group on another canvas's pins (a battleground's own map, MapDungeon.lua: its "group" layer), by the
-- same rule as the world's; `seen` that canvas's own (the members it shows)
function Layers.Group(pins, mapID, seen)
	Group(mapID, pins, seen)
end

-- the window closed
function Layers.Close()
	S.shown = false
end

-- a glide to the player: at least FIND_ZOOM close, the zoom kept when closer
function Layers.FindMe()
	local c, pins = S.canvas, S.pins
	local pin = pins and pins.layers.player and pins.layers.player.pins.player
	if not (c and pin) then
		return false
	end
	local z = c.z < T.FIND_ZOOM and T.FIND_ZOOM or c.z
	c:Glide(pin.wx, pin.wy, z)
	return true
end

function Layers.Init(canvas, pins)
	S.canvas, S.pins = canvas, pins
	ArrowLook()
	-- (2.1.0, W1) the doors, the docks and the capitals from the world's zoom on, kept apart (MapPins); the towns and
	-- the flight masters from a continent's
	pins:Layer("entrances", T.ORDER.entrances, { merge = T.PLACE_SIZE, nudge = true })
	pins:Layer("transports", T.ORDER.transports, { merge = T.DOCK_MERGE, nudge = true })
	pins:Layer("places", T.ORDER.places, { maxZ = T.NAMES_TO, nudge = true })
	pins:Layer("towns", T.ORDER.towns, { minZ = T.PLACES_FROM, maxZ = T.NAMES_TO, nudge = true })
	pins:Layer("flights", T.ORDER.flights, { minZ = T.PLACES_FROM })
	pins:Layer("spirits", T.ORDER.spirits, { minZ = T.SPIRITS_FROM })   -- (2.1.92: from a zone's zoom on)
	pins:Layer("route", T.ORDER.route)
	pins:Layer("gossip", T.ORDER.gossip)
	pins:Layer("group", T.ORDER.group)
	pins:Layer("corpse", T.ORDER.corpse)
	pins:Layer("waypoint", T.ORDER.waypoint)
	pins:Layer("player", T.ORDER.player)
	S.wait = 0
end

return Layers

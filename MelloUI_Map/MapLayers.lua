--------------------------------------------------------------------------------
-- MelloUI Map - the layers (docs/plans/seamless-map.md, stage M1)
--
-- What the map shows over its art, each a layer of pins (MapPins.lua) fed
-- from the client and from MelloUI's own data, across the whole world at once
-- -- never only the zone under the view:
--
--   the player     the game's own map arrow, turned by the facing
--   the group      your party or raid on the player's continent, a dot in each
--                  one's class colour, the name on hover
--   flights        the flight masters: the client's own nodes on each continent
--                  (C_TaxiMap, by node ID; one you have not learned paler),
--                  your side's and the neutral ones; the Quest List's data when
--                  the client lists none
--   transports     boats, zeppelins, portals and the tram (the Quest List's
--                  data), one pin a dock with every way from it on hover
--   entrances      dungeons and raids (the Quest List's data and the client's),
--                  their levels on hover in the colour of how hard they are
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
--   Layers.FindMe()             a glide to the player
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Finite = MelloUI.Safe.Finite
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
	-- the stack (MapPins' layer order): the places under the group, the group under the player
	ORDER = { entrances = 10, transports = 12, flights = 14, group = 40, player = 50 },
	PLACES_FROM = 1.15,      -- flights, transports and entrances from a continent's zoom on (the world's: too many)
	PIN_SIZE = 18,
	NEW_ALPHA = 0.45,        -- a flight master you have not learned
	TRANSPORT_ICON = { "pin_boat", "pin_zeppelin", "pin_portal", "pin_tram" },
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
	dungeon = "Dungeon",
	raid = "Raid",
	levels = "%s, levels %s",
}

--------------------------------------------------------------------------------
-- Reading a unit's place
--------------------------------------------------------------------------------

local function XY(pos)
	if type(pos) ~= "table" then
		return nil
	end
	local ok, x, y = pcall(pos.GetXY, pos)
	if not ok then
		return nil
	end
	return Finite(x), Finite(y)
end

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

local classSpec = {}   -- [class] = a dot in that class's colour (one table a class, shared by every member)

local function MemberTip(pin)
	local name = Text(UnitName(pin.data))
	return name
end

local function DotOf(class)
	local spec = classSpec[class or "?"]
	if not spec then
		local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		spec = { icon = T.ICONS .. "map_dot", size = T.DOT_SIZE, rgb = c and { c.r, c.g, c.b } or nil, sub = 1,
			tip = MemberTip }
		classSpec[class or "?"] = spec
	end
	return spec
end

local function Group(mapID)
	local pins, seen = S.pins, S.seen
	for key in pairs(seen) do
		seen[key] = false
	end
	local raid = IsInRaid and IsInRaid()
	local n = raid and 40 or 4
	local prefix = raid and "raid" or "party"
	for i = 1, n do
		local unit = prefix .. i
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			local x, y = UnitXY(mapID, unit)
			if x then
				local _, class = UnitClass(unit)
				local pin = pins:SetAt("group", unit, mapID, x, y, DotOf(Text(class)))
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

local function Icon(name, alpha, tip)
	return { icon = T.ICONS .. name, size = T.PIN_SIZE, alpha = alpha, tip = tip, sub = 1 }
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
			if p.kind == "continent" then
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

-- transports: one pin a dock, every way from it on hover
local function DockTip(pin)
	return pin.data.title, table.concat(pin.data.lines, "\n")
end
local transportSpec = {}
local function TransportSpec(kind)
	local spec = transportSpec[kind]
	if not spec then
		spec = Icon(T.TRANSPORT_ICON[kind], nil, DockTip)
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
					dock = { title = row[4], lines = {} }
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

local function EntranceTip(pin)
	local d = pin.data
	local word = d.kind == 2 and TEXT.raid or TEXT.dungeon
	if d.levels then
		return d.name, string.format(TEXT.levels, word, LevelText(d.levels))
	end
	return d.name, word
end
local ENTRANCE = { Icon(T.ENTRANCE_ICON[1], nil, EntranceTip), Icon(T.ENTRANCE_ICON[2], nil, EntranceTip) }

local function Entrances()
	local pins, data = S.pins, Data()
	pins:Clear("entrances")
	local seen = {}
	for _, row in ipairs(data and data.entrances or EMPTY) do
		local id, name, kind = row[1], row[2], row[9]
		if name and not seen[name] and ENTRANCE[kind] then
			local wx, wy = WorldPoint(row[3], row[4], row[5])
			if wx then
				seen[name] = true
				local lv = data.dungeonLevel and data.dungeonLevel[id]
				local pin = pins:Set("entrances", name, wx, wy, ENTRANCE[kind])
				if pin then
					pin.data = { name = name, kind = kind, levels = lv and (lv[1] or 0) > 0 and lv or nil }
				end
			end
		end
	end
	-- (the client's own entrances on each continent: the ones the data lacks)
	local api = rawget(_G, "C_EncounterJournal")
	if not (api and api.GetDungeonEntrancesForMap) then
		return
	end
	for _, p in ipairs(S.canvas.places) do
		if p.kind == "continent" then
			local ok, list = pcall(api.GetDungeonEntrancesForMap, p.id)
			for _, e in ipairs(ok and type(list) == "table" and list or EMPTY) do
				local name = Text(e.name)
				local x, y = XY(e.position)
				if name and x and not seen[name] then
					seen[name] = true
					local kind = Text(e.atlasName) == "Raid" and 2 or 1
					local pin = pins:SetAt("entrances", name, p.id, x, y, ENTRANCE[kind])
					if pin then
						pin.data = { name = name, kind = kind }
					end
				end
			end
		end
	end
end

-- the window opened: the places laid (the data's once; the flights each time: learned ones change)
function Layers.Open()
	if not S.pins then
		return
	end
	if not S.built then
		S.built = true
		Transports()
		Entrances()
	end
	Flights()
	S.wait = 0
	S.pins:Lay()
end

-- a flight master's map opened or a flight point learned: the flights again
function Layers.Event()
	if S.pins then
		Flights()
		S.pins:Lay()
	end
end

--------------------------------------------------------------------------------
-- The window's beat
--------------------------------------------------------------------------------

function Layers.Tick(elapsed)
	if not S.pins then
		return
	end
	S.wait = S.wait - (elapsed or 0)
	if S.wait > 0 then
		return
	end
	S.wait = T.EVERY
	local mapID = PlayerMap()
	if mapID then
		Player(mapID)
		Group(mapID)
	else
		S.pins:Clear("player")
		S.pins:Clear("group")
	end
	S.pins:Lay()
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
	local from = { minZ = T.PLACES_FROM }
	pins:Layer("entrances", T.ORDER.entrances, from)
	pins:Layer("transports", T.ORDER.transports, from)
	pins:Layer("flights", T.ORDER.flights, from)
	pins:Layer("group", T.ORDER.group)
	pins:Layer("player", T.ORDER.player)
	S.wait = 0
end

return Layers

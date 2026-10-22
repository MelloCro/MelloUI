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
--                  data), one pin a dock with every way from it on hover
--   entrances      dungeons and raids (the Quest List's data and the client's),
--                  their levels on hover in the colour of how hard they are
--   route          Route's trail and its goal flag (the World Marker's goal is
--                  the same), by Route's own painter, across continents
--   quests         the quest givers of every zone and city: the Quest List's own
--                  groups, picture and tooltip, from a zone's zoom on
--   names          (M2) each zone's name on the soft shade, from a continent's
--                  zoom to a zone's
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
local Perf = MelloUI.Perf:Scope("MelloUI_Map (MapLayers)")
local Finite = MelloUI.Safe.Finite
local W = MelloUI.Widgets
local Text = MelloUI.Safe.Text
local Pins = ns.Pins   -- (Pins.Lift: the icon set's glow under a pin)
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
	ORDER = { names = 8, entrances = 10, transports = 12, flights = 14, quests = 20, route = 30, waypoint = 32, group = 40,
		player = 50 },
	MEMBER_SIZE = 16,        -- a party member's class pin (the user, 2026-10-20: "in the theme", "enough just in the color")
	PIN_GOAL = "goal_pin",   -- the game's waypoint, while Route is off
	QUESTS_FROM = 2.5,       -- the quest givers from a zone's zoom on (a continent's: thousands)
	NAMES_FROM = 1.15,       -- (M2) the zone names from a continent's zoom ...
	NAMES_TO = 6.5,          -- ... to a zone's (closer, the zone's own art names its places)
	NAME_SHADE = 0.6,        -- the soft shade under a name
	NAME_GAP = 6,            -- px kept free round a name
	GIVER_SIZE = 20,
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

local S = { canvas = nil, pins = nil, wait = 0, seen = {}, docks = {}, built = false,
	readySeen = setmetatable({}, { __mode = "k" }) }   -- (1.2.0: the givers' ready moments shown, by quest row)
local EMPTY = {}
local floor = math.floor

local TEXT = {
	notLearned = "Not learned yet",
	yourPin = "Your pin",
	yourPinHint = "Shift-click: share it in the chat\nCtrl-right-click on the map: take it away",
	dungeon = "Dungeon",
	raid = "Raid",
	levels = "%s, levels %s",
	-- (1.2.0: Dungeon Info's lines on a door's tooltip, the user's pick B of journal_placements)
	bosses = "%d bosses: %s",
	dungeonInfo = "Click: open it in Dungeon Info",
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
-- The quest givers: the Quest List's own groups (QL.GiverGroups: its filters,
-- its states, its order), picture (QL.GiverIcon) and tooltip (QL.MarkTip),
-- for every zone and city at once; from a zone's zoom on. Made when the
-- window opens and again when the Quest List lays its own marks again (its
-- RefreshPins: a quest taken, done, its data placed)
--------------------------------------------------------------------------------

local function QuestList()
	local QL = rawget(MelloUI, "QuestList")
	return (type(QL) == "table" and QL.GiverGroups and QL.GiverIcon and QL.MarkTip) and QL or nil
end

local function GiverLook(tex, pin)
	local QL = QuestList()
	if QL then
		pcall(QL.GiverIcon, tex, pin.data)
		-- (a quest begun by an item: the set's starter icon, lifted; the game's quest marks none)
		local item = type(pin.data) == "table" and pin.data.item
		local name = item and QL.StarterIconName and select(2, pcall(QL.StarterIconName, item)) or false
		Pins.Lift(tex, type(name) == "string" and name or false, T.GIVER_SIZE)
	end
end

local function GiverTip(tip, pin)
	local QL = QuestList()
	if QL then
		pcall(QL.MarkTip, tip, "giver", pin.data, false)
	end
end

-- (after M4) a giver's click, as on the game's map (QuestListMap's MarkClick): a waypoint there (Route's), again
-- on a tracked one: cleared; Alt: its quests hidden for this character; the givers laid again after
local function GiverClick(pin, button)
	local QL, g = QuestList(), pin.data
	if button ~= "LeftButton" or not (QL and type(g) == "table" and g.quests and g.quests[1]) then
		return
	end
	if IsAltKeyDown() and QL.HideGiver then
		QL.HideGiver(g)
	elseif g.tracked and QL.ClearWaypoint then
		QL.ClearWaypoint()
		MelloUI:PlayUISound("waypoint_clear")
	elseif QL.SetWaypoint then
		local set, chimed = QL.SetWaypoint(g.quests[1].row, g.quests[1].state == "ready")
		if set and not chimed then
			MelloUI:PlayUISound("waypoint_set")
		end
	end
	-- (the givers again at once: the tracked one's look follows the waypoint)
	Layers.Quests()
	S.pins:Lay()
end

local GIVER = { size = T.GIVER_SIZE, look = GiverLook, fillTip = GiverTip, click = GiverClick, sub = 2 }

function Layers.Quests()
	local pins, QL = S.pins, QuestList()
	if not pins then
		return
	end
	S.questsDirty = false
	S.questsBuilt = QL ~= nil
	pins:Clear("quests")
	if not QL then
		return
	end
	local t0 = debugprofilestop()
	for _, p in ipairs(S.canvas.places) do
		if p.kind == "zone" or p.kind == "city" then
			local ok, groups = pcall(QL.GiverGroups, p.id, p.name)
			for i, g in ipairs(ok and type(groups) == "table" and groups or EMPTY) do
				local pin = pins:SetAt("quests", p.id * 1000 + i, p.id, g.x, g.y, GIVER)
				if pin then
					pin.data = g
					-- (1.2.0) a quest newly ready to hand in: its "?" pops in with a ring of light (MapPins' moment)
					if QL.ReadyNew and QL.ReadyNew(g, S.readySeen) then
						pin.moment = { pop = 0, ring = true, at = GetTime() }
					end
				end
			end
		end
	end
	S.questsMs = debugprofilestop() - t0
end

-- the Quest List laid its marks again: the givers again now if the window shows, else at its next open
local function QuestsChanged()
	S.questsDirty = true
	if S.shown then
		Layers.Quests()
		S.pins:Lay()
	end
end

local function WatchQuests()
	local QL = QuestList()
	if S.questWatch or not (QL and type(QL.RefreshPins) == "function") then
		return
	end
	S.questWatch = true
	Perf.hooksecurefunc(QL, "RefreshPins", QuestsChanged)
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
local function Icon(name, alpha, tip, lift)
	return { icon = T.ICONS .. name, size = T.PIN_SIZE, alpha = alpha, tip = tip, sub = 1, lift = lift and name or nil }
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
		spec = Icon(T.TRANSPORT_ICON[kind], nil, DockTip, true)
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

-- (1.2.0) Dungeon Info's instance behind a door, when Dungeon Info is there and on (MelloUI_DungeonInfo)
local function DungeonInfoOf(pin)
	local J = rawget(MelloUI, "DungeonInfo")
	local d = pin.data
	if not (type(J) == "table" and J.Get and J.M and J.M.isEnabled and type(d) == "table" and d.dungeonID) then
		return nil
	end
	return J, J.Get(d.dungeonID)
end

-- its bosses in a line ("4 bosses: Oggleflint, Taragaman the Hungerer, ..."), nil with none known
local function BossLine(inst)
	local n = #inst.bosses
	if n == 0 then
		return nil
	end
	local names = {}
	for i, b in ipairs(inst.bosses) do
		names[i] = b.name
	end
	return string.format(TEXT.bosses, n, table.concat(names, ", "))
end

local function EntranceFill(tip, pin)
	local QL = rawget(MelloUI, "QuestList")
	if not (type(QL) == "table" and QL.MarkTip) then
		return
	end
	local d = pin.data
	pcall(QL.MarkTip, tip, "entrance", { name = d.name, dungeonID = d.dungeonID or 0, raid = d.kind == 2,
		source = d.source }, false)
	local _, inst = DungeonInfoOf(pin)
	if inst then
		local P = MelloUI.Look.Palette()
		local gold, text = P.selectedTrim, P.text
		local line = BossLine(inst)
		if line then
			tip:AddLine(line, text[1], text[2], text[3], true)
		end
		tip:AddLine(TEXT.dungeonInfo, gold[1], gold[2], gold[3])
		tip:Show()
	end
end

local function EntranceTip(pin)
	local d = pin.data
	local word = d.kind == 2 and TEXT.raid or TEXT.dungeon
	local line = d.levels and string.format(TEXT.levels, word, LevelText(d.levels)) or word
	local _, inst = DungeonInfoOf(pin)
	if inst then
		local bosses = BossLine(inst)
		return d.name, line .. (bosses and ("\n" .. bosses) or "") .. "\n" .. TEXT.dungeonInfo
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

local ENTRANCE = { Icon(T.ENTRANCE_ICON[1], nil, EntranceTip, true), Icon(T.ENTRANCE_ICON[2], nil, EntranceTip, true) }
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

local function Entrances()
	local pins, data = S.pins, Data()
	pins:Clear("entrances")
	local seen = {}
	-- (a door only one side uses, the City of Dalaran's: yours; both while the side is unknown)
	local mine = T.DATA_SIDE[Side()]
	for _, row in ipairs(data and data.entrances or EMPTY) do
		local id, name, kind, side = row[1], row[2], row[9], row[10]
		if name and not seen[name] and ENTRANCE[kind] and (not (side and mine) or side == 0 or side == mine) then
			local wx, wy = WorldPoint(row[3], row[4], row[5])
			if wx then
				seen[name] = true
				local lv = data.dungeonLevel and data.dungeonLevel[id]
				local pin = pins:Set("entrances", name, wx, wy, EntranceSpec(kind))
				if pin then
					pin.data = { name = name, kind = kind, levels = lv and (lv[1] or 0) > 0 and lv or nil, dungeonID = id,
						source = "data" }
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
					local pin = pins:SetAt("entrances", name, p.id, x, y, EntranceSpec(kind))
					if pin then
						pin.data = { name = name, kind = kind, source = "client" }
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
	S.shown = true
	if not S.built then
		S.built = true
		Transports()
		Entrances()
	end
	-- (the givers: made again when the Quest List laid its marks again, or when they were last made without it)
	WatchQuests()
	if S.questsDirty or not S.questsBuilt then
		Layers.Quests()
	end
	Flights()
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

local function HideName(label)
	if label.shown then
		label.shown = false
		label.fs:Hide()
		label.fs:ClearAllPoints()
		if label.band then
			label.band:SetShown(false)
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
	local on = c.z >= T.NAMES_FROM and c.z <= T.NAMES_TO
	local k = c.k1 * c.z
	local x0, y0 = c.cx - c.cw / (2 * k), c.cy - c.ch / (2 * k)
	local boxes, n = NAMES.boxes, 0
	for _, p in ipairs(c.places) do
		local at = p.label
		if at then
			local label = NAMES.list[p]
			local x = (p.left + at[1] * p.w - x0) * k
			local y = (p.top + at[2] * p.h - y0) * k
			local fits = on and x > -40 and x < c.cw + 40 and y > -20 and y < c.ch + 20
			if fits then
				label = label or NameOf(p)
				local hw, hh = label.w / 2 + T.NAME_GAP, label.h / 2 + 2
				for i = 1, n do
					local b = boxes[i]
					if not (x + hw < b[1] or x - hw > b[3] or y + hh < b[2] or y - hh > b[4]) then
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
					b[1], b[2], b[3], b[4] = x - hw, y - hh, x + hw, y + hh
					label.fs:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
					if not label.shown then
						label.shown = true
						label.fs:Show()
						if label.band then
							label.band:SetShown(true)
						end
					end
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
			add("dock", pin.data.title, pin.spec and pin.spec.icon, pin.wx, pin.wy)
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
	S.pins:Lay()
	RouteChanged()
end

-- the window closed (the givers wait for its next open)
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
	local from = { minZ = T.PLACES_FROM }
	pins:Layer("entrances", T.ORDER.entrances, from)
	pins:Layer("transports", T.ORDER.transports, from)
	pins:Layer("flights", T.ORDER.flights, from)
	pins:Layer("route", T.ORDER.route)
	pins:Layer("quests", T.ORDER.quests, { minZ = T.QUESTS_FROM })
	pins:Layer("group", T.ORDER.group)
	pins:Layer("waypoint", T.ORDER.waypoint)
	pins:Layer("player", T.ORDER.player)
	S.wait = 0
end

return Layers

--------------------------------------------------------------------------------
-- MelloUI Map (docs/plans/seamless-map.md; the user, 2026-10-20: "i want our
-- map to function like that, just improved version of it")
--
-- One seamless map of the whole world in a window of MelloUI's own
-- (Kit:OwnWindow): the mouse wheel zooms toward the cursor from Azeroth down
-- to a zone, a drag pans, a left click glides into the map under the cursor
-- and a right click goes out one. The view is kept between sessions. It never
-- touches the game's world map: no hook, no key on a Blizzard frame, no
-- method replaced (hard rule 1); the game's map stays as it is, for the quest
-- log, the Gamepad UI and other addons.
--
-- Stage M0 (this file and MapCanvas.lua): the window, the world's places from
-- the client's own data, the art by file ID, zoom, pan and glide, culling,
-- the view saved, /melloperf map. Layers (the player, Route, quests ...), the
-- look of the edges and the close zoom come in the stages after.
--
-- Nothing at login: the module's switch and its slash command only; the
-- window and its canvas are made the first time the map opens.
--
--   Ctrl-click              your pin (Route's way there); Shift-click on it: its
--                           link in the chat (the game's own map pin link: anyone
--                           can click it; in MelloUI's chat it opens on this map)
--   /mellomap share         your pin's link in the chat
--   your quests' objectives every open objective of your log's quests, on the whole map
--                           (MapObjectives.lua)
--   the layers button       (the gear beside the quest column's opener) a check per layer:
--                           what the map shows, kept in the module's settings (db.layers)
--   other addons' pins      Questie's (HereBeDragons), HandyNotes', GatherMate2's, and
--                           MelloUI.Map:AddPin for any addon (MapAddonPins.lua)
--   the search (title row)  places, your quests, dungeons, flight masters, docks
--                           and quest givers: Enter or a click goes there (MapSearch.lua)
--   M (the game's map key)  opens it instead of the game's map (the keys bound
--                           to the game's world map, while the map is on)
--   L (the quest log's key) opens it with your quests beside it (MapQuestLog.lua:
--                           the quest log's column on the map's right)
--   /mellomap, /mmap        open or close it (also a key binding of its own)
--   /mellomap dump          the places and the view, to copy
--   /melloperf map          the canvas's numbers: open, a view's Lua time, the
--                           frames while it moves, tiles made and shown
--------------------------------------------------------------------------------

local ADDON, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Map (Map)")
local Finite = MelloUI.Safe.Finite
local Text = MelloUI.Safe.Text
local W = MelloUI.Widgets
local Kit = MelloUI.Kit
local Canvas, Pins, Layers, Log, Search = ns.Canvas, ns.Pins, ns.Layers, ns.QuestLog, ns.Search
local AddonPins, Objectives = ns.AddonPins, ns.Objectives
local Trails = ns.Trails   -- (2.1.0: the boats' and the zeppelins' trails, MapTrails.lua)
local Dungeon = ns.Dungeon -- (2.1.0: a dungeon's own plan inside one, MapDungeon.lua)
local floor, max, min = math.floor, math.max, math.min

local ICON = "Interface\\Icons\\INV_Misc_Map_01"

local T = {
	SHARE = 0.72,      -- the map's width: this share of the screen's (its height from the world's 3 : 2) ...
	WIDE = 0.95,       -- ... (2.1.0) the window with the column out at most this share (the map narrower to fit)
	MIN_W = 480,       -- (2.1.0: 640 before the column stood beside it; a 4 : 3 screen at UI scale 1 takes the two)
	PAD = 14, TOP = 34, FOOT = 24, IN = 1,
	HOVER = 0.1,       -- the name under the cursor read at most this often
	CLICK = 4,         -- a press that moved less than this is a click
	PIN_ZOOM = 6,      -- a shared pin opened: the map at least this close
	FLING_SMOOTH = 0.05,   -- (2026-10-21) the drag's speed smoothed over about this many seconds ...
	FLING_MIN = 150,       -- ... and a let-go at least this fast (canvas px a second) runs on
}

local TEXT = {
	title = "Map",
	hint = "Wheel: zoom   Drag: look around   Click: in   Right-click: out   Middle-click: find me   Ctrl-click: your pin",
	pinLabel = "Your pin",
	pinNotice = "Route: to your pin",
	pinNone = "The map cannot set a pin there: click on land.",
	pinOff = "Turn on Route or the Quest List to set a pin on the map.",
	pinShared = "Shared pin",
	pinNoShare = "You have no pin to share: Ctrl-click on the map to set one.",
	open = "Open The Map",
	usage = "/mellomap: open or close the map | /mellomap share: your pin's link in the chat | /mellomap dump: its places and the view, to copy",
	off = "The map is off: switch it on in /mello (Quests and travel > Map).",
}

-- (after M4; the user, 2026-10-20: "Layer switches", a button on the map, "Objectives on, rares off") what the map
-- shows: a switch per layer, kept in the module's settings (db.layers[key] = false: off; every one on until switched).
-- (2.1.0, the user's pick B: the gear's page beside the map, MapQuestLog's Log.Layers) each in its group, with its
-- icon (the map's own picture of it, as the look draws it: MelloUI.Icons)
local GROUPS = { "Quests", "Travel", "People and more" }
local SWITCHES = {
	{ key = "quests", label = "Quest givers", layers = { "quests" }, group = 1, icon = "quest_mark" },
	{ key = "objectives", label = "Your quests' objectives", layers = { "objectives", "objective_dots", "objective_quests" },
	  group = 1, icon = "track_todo" },
	{ key = "flights", label = "Flight masters", layers = { "flights" }, group = 2, icon = "svc_flight" },
	{ key = "transports", label = "Boats, zeppelins and portals", layers = { "transports" }, trails = true, group = 2,
	  icon = "pin_boat" },
	{ key = "entrances", label = "Dungeons and raids", layers = { "entrances" }, group = 2, icon = "pin_dungeon" },
	-- (2.1.0, qu-01) the capitals and the towns the world map names
	{ key = "places", label = "Cities and towns", layers = { "places", "towns" }, group = 2, icon = "svc_inn" },
	{ key = "group", label = "Your party and raid", layers = { "group" }, group = 3, icon = "chan_party" },
	{ key = "names", label = "Zone names", layers = { "names" }, group = 3, icon = "page_screentext" },
	{ key = "addons", label = "Other addons' pins", layers = { "addons", "addons_continent", "addons_world" }, group = 3,
	  icon = "svc_addons" },
	{ key = "caves", label = "Caves (zoomed in close)", layers = {}, canvas = true, group = 3, icon = "obj_explore" },
}

local M   -- (the module: its button opens it)
M = MelloUI:RegisterModule("Map", {
	title = "Map",
	desc = "One seamless map of the whole world. Zoom with the mouse wheel, drag to look around.",
	icon = ICON,
	flavour = "The whole world on one sheet, from the continents down to a village.",
	group = "Quests and travel", navOrder = 4,
	enabledByDefault = true,
	defaults = { dungeonMaps = true },
	-- (1.0) the window's own state, the player's: where it looked, its quest log open and on which tab -- never in a
	-- profile or the installer's Full (its layers and Tracked Only travel)
	keep = { "view", "log", "logTab", "logMode" },
	options = {
		{ type = "button", name = TEXT.open, text = "Open",
		  desc = "Opens MelloUI's map. Your map key (M) and /mellomap open it too.",
		  opens = "MelloUIMapFrame",   -- (closed again: back in the configurator, Core/Config.lua's CONFIG.Away)
		  onClick = function() M:Toggle(true) end },
		-- (2.1.0; the user, 2026-11-02: "once inside of the dungeon, to open the dungeon map, with boss positions and
		-- loot seen on the right side of the map") MapDungeon.lua
		{ type = "toggle", key = "dungeonMaps", name = "Dungeon Maps",
		  desc = "Inside a dungeon or raid the map opens on its own map (Blizzard's drawings for the classic ones), Dungeon Info's bosses and loot beside it. From outside, a click on its door or on its row in Dungeon Info shows it." },
	},
})

local win = {}

--------------------------------------------------------------------------------
-- The view kept: the centre on the world (0..1) and the zoom
--------------------------------------------------------------------------------

local function SaveView()
	local c = win.canvas
	if not (c and c.cx and M.db) or c.dungeon then   -- (a dungeon's plan: not the world's view)
		return
	end
	M.db.view = { x = c.cx / c.W, y = c.cy / c.H, z = c.z }
end

-- the view of the first open: the one kept, else the player's zone (or the world); every open then centres on the
-- player (Refit)
local function StartView(c)
	local v = M.db and M.db.view
	if type(v) == "table" then
		local x, y, z = Finite(v.x), Finite(v.y), Finite(v.z)
		if x and y and z then
			return x * c.W, y * c.H, z
		end
	end
	local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
	id = ok and Finite(id) or nil
	local p = id and c.byID[id]
	if p then
		return c:FitOf(p)
	end
	return c.W / 2, c.H / 2, 1
end

--------------------------------------------------------------------------------
-- Input: the wheel, a drag, a click; the name under the cursor
--------------------------------------------------------------------------------

local function ShowName(name)
	local text = name or (Dungeon.Shown() and Dungeon.Hint()) or TEXT.hint
	if text ~= win.shownName then
		win.shownName = text
		win.name:SetText(text)
	end
end

-- (M4) a frame on a pin whose tooltip and clicks are another addon's own (HandyNotes' plugins anchor theirs to the
-- pin's frame): one, laid on the pin it serves
local function PinAnchor(pin)
	local a = win.pinAnchor
	if not a then
		a = CreateFrame("Frame", nil, win.pins.frame)
		a:EnableMouse(false)
		win.pinAnchor = a
	end
	local s = pin.spec.size or 16
	a:SetSize(s, s)
	a:ClearAllPoints()
	a:SetPoint("CENTER", win.pins.frame, "TOPLEFT", pin.x or 0, -(pin.y or 0))
	a:Show()
	return a
end

-- a pin's tooltip (its spec's tip: a text, or fn(pin) -> title, body; enter / leave: another addon's own), or none
local function PinTip(pin)
	if pin == win.tipPin then
		return
	end
	local old = win.tipPin
	win.tipPin = pin
	-- (1.2.0) the pin under the cursor lifts, the one left sets down; an objective's mark lights its area
	if old then
		win.pins:Raise(old, false)
	end
	if pin then
		win.pins:Raise(pin, true)
	end
	Objectives.Hover(pin)
	if old and old.spec.leave then
		old.spec.leave(old, PinAnchor(old))
	end
	if not pin then
		GameTooltip:Hide()
		return
	end
	if pin.spec.enter then
		pin.spec.enter(pin, PinAnchor(pin))
		return
	end
	local fill = pin.spec.fillTip
	if fill then
		-- (a whole tooltip of its own: the Quest List's marks' lines)
		GameTooltip:SetOwner(win.canvas.frame, "ANCHOR_CURSOR")
		fill(GameTooltip, pin)
		GameTooltip:Show()
		return
	end
	local tip = pin.spec.tip
	local title, body = tip, nil
	if type(tip) == "function" then
		title, body = tip(pin)
	end
	if title then
		W.ShowTooltip(win.canvas.frame, title, body, nil, "ANCHOR_CURSOR")
	else
		GameTooltip:Hide()
	end
end

-- the deepest map under the cursor (names the footer), the pin under it (its tooltip)
local function Hover()
	local c = win.canvas
	local x, y = c:Cursor()
	if not x then
		ShowName(nil)
		PinTip(nil)
		return
	end
	PinTip(not win.drag.on and win.pins:At(x, y) or nil)
	local path = c:Path(x, y, win.path)
	local p = path[#path]
	ShowName(p and p.kind ~= "world" and p.name or nil)
end

-- one handler while the cursor is over the canvas or a drag runs: the drag's pan (the point grabbed held under the
-- cursor, the wheel's chase going on about it; its speed smoothed for a let-go), the name (throttled)
local function Watch_OnUpdate(frame, elapsed)
	local c = win.canvas
	local d = win.drag.on and win.drag
	if d then
		local x, y = c:Cursor()
		if x then
			local dx, dy = x - d.x, y - d.y
			if not d.moved and (dx * dx + dy * dy) >= T.CLICK * T.CLICK then
				d.moved = true
				c.moving = true
				c.stats.lastAt = nil
			end
			if d.moved then
				c:Hold(d.wx, d.wy, x, y)
				if elapsed > 0 then
					local s = min(1, elapsed / T.FLING_SMOOTH)
					d.vx = d.vx + ((x - d.lx) / elapsed - d.vx) * s
					d.vy = d.vy + ((y - d.ly) / elapsed - d.vy) * s
				end
			end
			d.lx, d.ly = x, y
		end
	end
	win.hoverIn = (win.hoverIn or 0) - elapsed
	if win.hoverIn <= 0 then
		win.hoverIn = T.HOVER
		Hover()
	end
	if not (d or win.over) then
		Perf.SetScript(frame, "OnUpdate", nil)
	end
end

local function Watch(on)
	local f = win.canvas.frame
	if on then
		Perf.SetScript(f, "OnUpdate", Watch_OnUpdate)
	end
end

local function Canvas_OnMouseWheel(_, delta)
	local c = win.canvas
	local x, y = c:Cursor()
	if not x then
		x, y = c.cw / 2, c.ch / 2
	end
	c:ZoomAt(x, y, delta > 0 and 1 or -1)
end

local function Canvas_OnMouseDown(_, button)
	local c = win.canvas
	if button ~= "LeftButton" then
		return
	end
	local x, y = c:Cursor()
	if not x then
		return
	end
	-- (a press during the wheel's chase: the zoom goes on, the drag carries it; a click's glide or a fling stops)
	if not c.chasing then
		c:Stop()
	end
	local d = win.drag
	d.on, d.x, d.y, d.moved = true, x, y, false
	d.wx, d.wy = c:Point(x, y)
	d.lx, d.ly, d.vx, d.vy = x, y, 0, 0
	Watch(true)
end

--------------------------------------------------------------------------------
-- Your pin (the user, 2026-10-20: "the set pin function so that i can use the
-- navigation"): Ctrl-click sets it where you click -- the game's own map's
-- click -- on the deepest map there; Route navigates to it (its trail, the
-- World Marker; its goal drawn on this map), through the Quest List's own
-- "route to a point" (QL.RouteToPoint: Route's destination, else the game's
-- own waypoint and its arrow). Ctrl-right-click takes it away (Route's stop).
--------------------------------------------------------------------------------

local function QuestList()
	local QL = rawget(MelloUI, "QuestList")
	return type(QL) == "table" and QL.RouteToPoint and QL or nil
end

-- your pin at a map's position (0..1): Route's way there through the Quest List's route-to-a-point, else Route's
-- own; with neither, the game's own map pin alone
local function PinTo(mapID, mx, my, label)
	local QL, R = QuestList(), rawget(MelloUI, "Route")
	local ok, chimed
	if QL then
		ok, chimed = QL.RouteToPoint(mapID, mx, my, label, TEXT.pinNotice)
	elseif R and R.isEnabled and R.SetDestinationTo then
		ok = R:SetDestinationTo({ mapID = mapID, x = mx, y = my }, label, true, TEXT.pinNotice)
		chimed = ok and R.AnnounceSounds ~= nil and R:AnnounceSounds()
	elseif C_Map.SetUserWaypoint and UiMapPoint then
		ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, mx, my))
	else
		MelloUI:Print(TEXT.pinOff)
		return false
	end
	if ok then
		-- (through Route its notice chimes instead: one sound, not two)
		if not chimed then
			MelloUI:PlayUISound("waypoint_set")
		end
	else
		MelloUI:Print(TEXT.pinNone)
	end
	return ok and true or false
end

local function SetPin(x, y)
	local c = win.canvas
	local path = c:Path(x, y, win.path)
	local p = path[#path]
	if not p or p.kind == "world" then
		MelloUI:Print(TEXT.pinNone)
		return false
	end
	local wx, wy = c:Point(x, y)
	return PinTo(p.id, (wx - p.left) / p.w, (wy - p.top) / p.h, TEXT.pinLabel)
end

-- (after M4) a waypoint at a laid pin (the objectives' marks without the Quest List): the map under it, as your pin
function M:PinOn(pin, label)
	local c = win.canvas
	local p = c and pin and pin.wx and c:PlaceAt(pin.wx, pin.wy)
	if not p then
		MelloUI:Print(TEXT.pinNone)
		return false
	end
	return PinTo(p.id, (pin.wx - p.left) / p.w, (pin.wy - p.top) / p.h, label or TEXT.pinLabel)
end

--------------------------------------------------------------------------------
-- The layers' switches (the layers' page beside the map)
--------------------------------------------------------------------------------

local function LayerOn(key)
	local l = M.db and M.db.layers
	return not (type(l) == "table" and l[key] == false)
end

local function ApplyLayers()
	local pins = win.pins
	win.canvas:SetCaves(LayerOn("caves"))   -- (the caves are the canvas's own places, not pins)
	for _, s in ipairs(SWITCHES) do
		local on = LayerOn(s.key)
		for _, name in ipairs(s.layers) do
			if pins.layers[name] then
				pins:Show(name, on)
			end
		end
		if s.trails and Trails then
			Trails.Show(on)   -- (2.1.0: the docks' trails with the docks)
		end
	end
end

-- a layer on or off: shown or hidden at once; the objectives laid (or let go), other addons' icons borrowed (or
-- handed back to the game's map)
local function SetLayer(key, on)
	local db = M.db
	db.layers = type(db.layers) == "table" and db.layers or {}
	if on then
		db.layers[key] = nil
	else
		db.layers[key] = false
	end
	ApplyLayers()
	local shown = win.frame and win.frame:IsShown()
	if key == "objectives" and shown then
		Objectives.Lay()
	elseif key == "addons" and shown then
		if on then
			AddonPins.Open()
		else
			AddonPins.Close()
		end
	end
	win.pins:Lay()
	Log.LayersChanged()
end
M.SetLayer, M.LayerOn = function(_, key, on) SetLayer(key, on) end, function(_, key) return LayerOn(key) end

-- your pin's link in the chat: the game's own map pin link (C_Map.GetUserWaypointHyperlink), which anyone can click
function M:SharePin()
	local ok, link = false, nil
	if C_Map.GetUserWaypointHyperlink then
		ok, link = pcall(C_Map.GetUserWaypointHyperlink)
	end
	link = ok and Text(link) or nil
	local A = rawget(MelloUI, "QuestActs")
	if not (link and A and A.InsertLink and A.InsertLink(link)) then
		MelloUI:Print(TEXT.pinNoShare)
		return false
	end
	return true
end

-- a map pin's link (anyone's shared pin) opened here: your pin set there (Route's way), the map shown on it; false
-- when the link is not a map pin's
function M:OpenPinLink(link)
	if not (self.isEnabled and C_Map.GetUserWaypointFromHyperlink) then
		return false
	end
	local ok, point = pcall(C_Map.GetUserWaypointFromHyperlink, link)
	local mapID = ok and type(point) == "table" and Finite(point.uiMapID) or nil
	local pos = mapID and point.position
	local x, y
	if type(pos) == "table" then
		x, y = Finite(pos.x), Finite(pos.y)
	end
	if not (mapID and x and y) then
		return false
	end
	PinTo(mapID, x, y, TEXT.pinShared)
	self:Toggle(true)
	local c = win.canvas
	local wx, wy
	if c then
		wx, wy = c:ToWorld(mapID, x, y)
	end
	if wx then
		c:Glide(wx, wy, max(c.z or 1, T.PIN_ZOOM))
	end
	return true
end

local function ClearPin()
	local R, QL = rawget(MelloUI, "Route"), QuestList()
	if R and R.StopRoute then
		R.StopRoute()
	elseif QL and QL.ClearWaypoint then
		QL.ClearWaypoint()
	end
	MelloUI:PlayUISound("waypoint_clear")
end

-- (2.1.0, qu-01) a click on a pin that holds others (MapPins' merge): a glide to their middle, in until the nearest
-- one stands apart (half as far again as the merge's reach), at least a notch and a half
local SPREAD = { APART = 1.5, AT_LEAST = 1.6 }
local function Spread(pin)
	local c = win.canvas
	local members, reach = pin.members, pin.layer.merge or 16
	local sx, sy, near = 0, 0, nil
	for _, m in ipairs(members) do
		sx, sy = sx + m.wx, sy + m.wy
		if m ~= pin then
			local d = math.sqrt((m.wx - pin.wx) ^ 2 + (m.wy - pin.wy) ^ 2)
			if d > 0 and (not near or d < near) then
				near = d
			end
		end
	end
	local z = c.z * SPREAD.AT_LEAST
	if near then
		z = max(z, reach * SPREAD.APART / (near * c.k1))
	end
	MelloUI:PlayUISound("click")
	c:Glide(sx / #members, sy / #members, min(z, c.zMax or z))
end

local function Canvas_OnMouseUp(_, button)
	local c = win.canvas
	if button == "RightButton" then
		if IsControlKeyDown() then
			ClearPin()
			return
		end
		-- (a pin that takes a right click: another addon's menu on its node)
		local x, y = c:Cursor()
		local pin = x and win.pins:At(x, y)
		if pin and pin.spec.right and pin.spec.click then
			pin.spec.click(pin, button, PinAnchor(pin))
			return
		end
		if Dungeon.Shown() then
			Dungeon.Out()   -- (2.1.0: a dungeon's plan, then the world)
			return
		end
		c:Out()
		return
	elseif button == "MiddleButton" then
		if Dungeon.Shown() then
			Dungeon.FindMe()
			return
		end
		Layers.FindMe()
		return
	end
	local d = win.drag
	if not d.on then
		return
	end
	d.on = false
	if d.moved then
		-- (let go at speed: the view runs on and is kept where it comes to rest; else here)
		local fast = d.vx * d.vx + d.vy * d.vy >= T.FLING_MIN * T.FLING_MIN
		if not (fast and c:Fling(d.vx, d.vy)) and not c.chasing then
			c.moving = false
			c.stats.lastAt = nil
			c:Refocus()
			SaveView()
		end
	else
		-- (Ctrl: your pin; a click on a pin is the pin's; elsewhere a glide in)
		local pin = win.pins:At(d.x, d.y)
		if IsControlKeyDown() and not Dungeon.Shown() then
			SetPin(d.x, d.y)
		elseif pin and pin.members then
			Spread(pin)   -- (2.1.0: a pin that holds others: in until they part)
		elseif pin and pin.spec.click then
			pin.spec.click(pin, button, pin.spec.enter and PinAnchor(pin) or nil)
		elseif Dungeon.Shown() then
			c:ZoomAt(d.x, d.y, 3)   -- (a dungeon's plan has no maps in it: a step in)
		else
			c:Deeper(d.x, d.y)
		end
	end
end

local function Canvas_OnEnter()
	win.over = true
	win.hoverIn = 0
	Watch(true)
end

local function Canvas_OnLeave()
	win.over = false
	ShowName(nil)
	PinTip(nil)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

-- the map's width (its body: the canvas and the line under it) and the window's height: the map SHARE of the screen's
-- width, the world's 3 : 2 under it, the window at most 90 % of the screen's height; (2.1.0) and with the rail and the
-- column out beside the map at most WIDE of its width (a narrow screen: the map narrower, never under the column)
local function Size()
	local sw = Finite(UIParent:GetWidth()) or 1280
	local sh = Finite(UIParent:GetHeight()) or 720
	local LT = Log.T
	local side = LT.GAP + LT.RAIL + LT.GAP + LT.W
	local w = max(T.MIN_W, min(floor(sw * T.SHARE), floor(sw * T.WIDE) - 2 * T.PAD - side))
	local rest = T.TOP + T.FOOT + T.PAD + 2 * T.IN
	local h = floor((w - 2 * T.IN) * 668 / 1002) + rest
	if h > sh * 0.9 then
		h = floor(sh * 0.9)
		w = floor((h - rest) * 1002 / 668) + 2 * T.IN
	end
	return w, h
end

-- (2.1.0) the window as wide as the map, the rail and the column's share `e` out (MapQuestLog's Reveal, every step of
-- its move): the map stays where it stands -- the window's place moved by the share of the change its anchor takes
-- (none for a left one, half for a centred one, all of it for a right one); `still` (a new look's lay): the place
-- kept as it is
local function Unfold(e, still)
	win.e = e
	local f, edge = win.frame, win.edge
	if not edge then
		return
	end
	local LT = Log.T
	local w = floor(2 * edge + win.mapW + LT.GAP + LT.RAIL + (LT.GAP + LT.W) * e + 0.5)
	local old = Finite(f:GetWidth())
	if old and math.abs(old - w) < 0.5 then
		return
	end
	f:SetWidth(w)
	if old and not still and f:GetNumPoints() == 1 then
		local point, rel, rp, x, y = f:GetPoint(1)
		local share = point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5
		if share > 0 and Finite(x) and Finite(y) then
			f:SetPoint(point, rel, rp, x + (w - old) * share, y)
		end
	end
end

-- (2.1.0) the window's own place until it is moved (the mover's default, and its reset): held by its left edge, the
-- window with the column out centred on the screen -- the map then stands still as the column comes and goes, never
-- pushed aside by the screen's edge
local function Home(frame)
	local sw = Finite(UIParent:GetWidth()) or 1280
	local LT = Log.T
	local wide = (win.mapW or 0) + 2 * T.PAD + LT.GAP + LT.RAIL + LT.GAP + LT.W
	frame:ClearAllPoints()
	frame:SetPoint("LEFT", UIParent, "LEFT", floor(max(0, (sw - wide) / 2)), 0)
end

-- the window's parts where the look puts them, at the build and at every switch (shell:OnKit): the map at the left,
-- as wide as Size made it; the window round it, the rail and the column
local function Lay(sh)
	local body, f = win.body, win.frame
	local edge, top = sh:Inset(T.PAD, -T.TOP)
	body:ClearAllPoints()
	body:SetPoint("TOPLEFT", f, "TOPLEFT", edge, top)
	body:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", edge, edge)
	body:SetWidth(win.mapW)
	win.edge = edge
	Unfold(win.e or 0, true)
end

-- the view laid again on the canvas's size: the first one (the one kept, else your zone) the first time it has a
-- size -- at the show, or at a later size change when the show came before the layout
-- the view laid again (a new size); at an open (onPlayer) centred on the player at the zoom kept (the user, 2026-10-20:
-- "it does not reopen on top of my character location as it should"), where the player's place can be read
local function Refit(onPlayer)
	local c = win.canvas
	if not (c.places and c:Size()) then
		return
	end
	c.box[5] = nil
	local x, y
	if onPlayer then
		x, y = Layers.PlayerPoint()
	end
	if x and y then
		local z = c.z
		if not z then
			local _, _, kept = StartView(c)
			z = kept
		end
		c:SetView(x, y, z)
	elseif c.cx then
		c:SetView(c.cx, c.cy, c.z)
	else
		c:SetView(StartView(c))
	end
end

local function Canvas_OnSizeChanged()
	if win.frame:IsShown() then
		Refit()
	end
end

-- (2.1.0) inside a dungeon: Dungeon Info's page of it beside its plan (MelloUI_DungeonInfo, when it is there and on)
local function OpenInside(mapID)
	local J = rawget(MelloUI, "DungeonInfo")
	if type(J) == "table" and J.ByMap and J.Open and J.M and J.M.isEnabled then
		local ok, inst = pcall(J.ByMap, mapID)
		if ok and type(inst) == "table" and inst.key then
			pcall(J.Open, inst.key)
		end
	end
end

local function Shown()
	-- (2.1.0) the world's canvas first (its view, its layers), the plan after; the plan kept when it shows again now
	local inside = Dungeon.Current()
	Dungeon.Hide(inside ~= nil and inside == Dungeon.Shown())
	local c = win.canvas
	local t0 = debugprofilestop()
	c:Layout()
	Refit(true)   -- (on the player)
	Layers.Open()
	if Trails then
		Trails.Open()   -- (2.1.0: the trails worked out at the first open, laid at the view)
	end
	AddonPins.Open()   -- (nothing while its switch is off: other addons' icons left to the game's map)
	Objectives.Open()
	Log.Shown()
	c.stats.openMs = debugprofilestop() - t0
	local f = win.frame
	f:RegisterEvent("MAP_EXPLORATION_UPDATED")
	f:RegisterEvent("TAXIMAP_OPENED")
	f:RegisterEvent("TAXI_NODE_STATUS_CHANGED")
	f:RegisterEvent("QUEST_LOG_UPDATE")
	f:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
	if inside then
		win.opening = true   -- (Dungeon Info's column out at once: the window opens as wide as it)
		OpenInside(inside)   -- (first: Dungeon Info's column out, so the plan's first view fits beside it)
		win.opening = false
		Dungeon.Show(inside)
		ShowName(nil)
	end
end

local function Hidden()
	Layers.Close()
	if Trails then
		Trails.Close()
	end
	AddonPins.Close()
	Objectives.Close()
	Log.Hidden()
	Search.Hidden()
	win.drag.on = false
	PinTip(nil)
	if win.pinAnchor then
		win.pinAnchor:Hide()
	end
	win.over = false
	if win.canvas then
		win.canvas:Stop()
		win.canvas.moving = false
	end
	SaveView()
	local f = win.frame
	f:UnregisterEvent("MAP_EXPLORATION_UPDATED")
	f:UnregisterEvent("TAXIMAP_OPENED")
	f:UnregisterEvent("TAXI_NODE_STATUS_CHANGED")
	f:UnregisterEvent("QUEST_LOG_UPDATE")
	f:UnregisterEvent("QUEST_WATCH_LIST_CHANGED")
end

-- the window's beat while it shows (the layers' positions; nothing runs while it is closed)
local function Frame_OnUpdate(_, elapsed)
	Layers.Tick(elapsed)
	Dungeon.Tick(elapsed)
	AddonPins.Tick()
	Objectives.Tick(elapsed)
	Log.Tick()
end

local function Frame_OnEvent(_, event)
	if event == "MAP_EXPLORATION_UPDATED" and win.canvas then
		win.canvas:Explored()
	elseif event == "TAXIMAP_OPENED" or event == "TAXI_NODE_STATUS_CHANGED" then
		Layers.Event()   -- (a flight point learned, or a flight master's map: the flights again)
	elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_LIST_CHANGED" then
		Objectives.Soon()   -- (the objectives again after the burst)
		Layers.LogChanged()   -- (2.1.7: the givers' marks, if what they show moved)
	end
end

-- a canvas's mouse (the world's; 2.1.0: each dungeon's plan's the same)
local function HookCanvas(cf)
	Perf.SetScript(cf, "OnMouseWheel", Canvas_OnMouseWheel)
	Perf.SetScript(cf, "OnMouseDown", Canvas_OnMouseDown)
	Perf.SetScript(cf, "OnMouseUp", Canvas_OnMouseUp)
	Perf.SetScript(cf, "OnEnter", Canvas_OnEnter)
	Perf.SetScript(cf, "OnLeave", Canvas_OnLeave)
	Perf.SetScript(cf, "OnSizeChanged", Canvas_OnSizeChanged)
end

local function Build()
	local f = CreateFrame("Frame", "MelloUIMapFrame", UIParent)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	local mw, h = Size()
	win.mapW = mw
	f:SetSize(mw + 2 * T.PAD + Log.T.GAP + Log.T.RAIL, h)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:Hide()
	win.frame = f
	win.path = {}
	win.drag = { on = false }
	win.shell = Kit:OwnWindow(f, {
		area = "config", ring = { at = "tl", texture = ICON }, plate = "rail",
		title = TEXT.title, close = true, escape = true, fit = true, sounds = true,
		mover = { key = "MelloUIMap", label = TEXT.title, page = "Map", default = Home },
	})
	local body = W.Panel(f)
	win.body = body
	-- the canvas over the body, the name under the cursor on the line below it (on the panel: dark ground)
	local canvas = Canvas.New(body)
	local cf = canvas.frame
	cf:SetPoint("TOPLEFT", body, "TOPLEFT", T.IN, -T.IN)
	cf:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -T.IN, T.FOOT)
	cf:EnableMouse(true)
	cf:EnableMouseWheel(true)
	win.canvas = canvas
	canvas.onRest = SaveView
	-- the pins over it (never scaled), laid with every view; the layers that feed them
	local pins = Pins.New(canvas)
	win.pins = pins
	canvas.onView = function()
		pins:Lay()
		Objectives.View()   -- (1.2.0: the quest areas' edge width and the ones in view)
		Layers.Route()
		Layers.Labels()
		if Trails then
			Trails.View()   -- (2.1.0: the trails' width and the stretches in view)
		end
		Log.ViewChanged()   -- (the Quest List's tab: its Current zone the zone under the view)
		AddonPins.View()    -- (other addons' OnViewChanged)
	end
	Layers.Init(canvas, pins)
	if Trails then
		Trails.Init(canvas)
	end
	AddonPins.Init(canvas, pins)
	Objectives.Init(canvas, pins)
	pins:Layer("names", Layers.T.ORDER.names)   -- (made here: its switch applies before the first names are laid)
	-- the quest log's column beside the map, the rail between them (2.1.0): out or folded as it was left
	win.module = M
	win.Unfold = Unfold
	Log.Init(win)
	-- (M4) the search in the title row
	Search.Init(win)
	-- (2.1.0) the layers' page, the rail's gear; the layers as they were left
	Log.Layers({ switches = SWITCHES, groups = GROUPS, on = LayerOn, set = SetLayer })
	ApplyLayers()
	local name = W.Text(body, "GameFontHighlight", nil, "text")
	name:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 8, 5)
	name:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -8, 5)
	name:SetJustifyV("BOTTOM")
	name:SetWordWrap(false)
	win.name = name
	ShowName(false)
	HookCanvas(cf)
	Dungeon.Init(win, HookCanvas)
	Perf.HookScript(f, "OnShow", Shown)
	Perf.HookScript(f, "OnHide", Hidden)
	Perf.SetScript(f, "OnEvent", Frame_OnEvent)
	Perf.SetScript(f, "OnUpdate", Frame_OnUpdate)
	Lay(win.shell)
	win.shell:OnKit(Lay)
end

-- the canvas and its pins (nil until the map first opens): the layers' and the tests' way in
function M:Canvas()
	return win.canvas, win.pins
end

-- the quest log's column (MapQuestLog.lua): the tests' and the dump's way in
function M:QuestLog()
	return Log
end

-- the search (MapSearch.lua): the tests' way in
function M:Search()
	return Search
end

function M:Toggle(show)
	if not self.isEnabled then
		MelloUI:Print(TEXT.off)
		return
	end
	if not win.frame then
		Build()
	end
	if show == nil then
		show = not win.frame:IsShown()
	end
	win.frame:SetShown(show and true or false)
end

-- (the quest log's key, L) the map with your quests beside it; again while they show: the map closed
function M:ToggleLog()
	if not self.isEnabled then
		MelloUI:Print(TEXT.off)
		return
	end
	if not win.frame then
		Build()
	end
	local f = win.frame
	if f:IsShown() and Log.IsOn("log") then
		f:Hide()
		return
	end
	local opening = not f:IsShown()   -- (2.1.0: the window opens with the column out, no move to watch)
	f:Show()
	Log.Mode("log", opening)
	Log.SetOut(true, opening)
end

-- (1.2.0) the map with Dungeon Info beside it (MelloUI_DungeonInfo's J.Open; the page is its own to show)
function M:OpenDungeonInfo()
	if not self.isEnabled then
		MelloUI:Print(TEXT.off)
		return false
	end
	if not win.frame then
		Build()
	end
	local opening = win.opening or not win.frame:IsShown()   -- (as the log's: out at once as the window opens)
	win.frame:Show()
	Log.Mode("dungeonInfo", opening)
	Log.SetOut(true, opening)
	return Log.IsDungeonInfo()
end

-- the map shown with Dungeon Info out (Dungeon Info's key toggles it)
function M:DungeonInfoShown()
	return win.frame ~= nil and win.frame:IsShown() and Log.IsDungeonInfo()
end

-- (2.1.0; the user, 2026-11-03) an instance's plan in place of the world while the window shows (Dungeon Info's page
-- of it: a click on its door or its row), when it has one and Dungeon Maps is on; the plan shown already kept as it is
-- (its wing and view: a boss's page opened from it)
function M:ShowDungeon(mapID)
	if not (self.isEnabled and win.frame and win.frame:IsShown() and Dungeon.Has(mapID)) then
		return false
	end
	if Dungeon.Shown() == mapID then
		return true
	end
	if not Dungeon.Show(mapID) then
		return false
	end
	ShowName(nil)
	return true
end

-- (2.1.0) an instance has a plan to show (Dungeon Info's row tooltip)
function M:HasDungeonMap(mapID)
	return self.isEnabled and Dungeon.Has(mapID)
end

-- (1.2.0) the map glides to a place given in the game's world coordinates (Dungeon Info's Show: a dungeon's door), a
-- box `box` world units across round it (the quest log's Show's least box, 3 times: the door and what is round it)
function M:ShowWorld(wcont, wx, wy, box)
	if not (self.isEnabled and win.canvas and Layers and Layers.WorldPoint) then
		return false
	end
	Dungeon.Hide()   -- (2.1.0: a place on the world, not in a dungeon's plan)
	local x, y = Layers.WorldPoint(wcont, wx, wy)
	if not x then
		return false
	end
	local h = (box or 36) / 2
	win.canvas:Glide(win.canvas:FitBox(x - h, y - h, x + h, y + h))
	return true
end

-- a quest's page in the map's quest log (the Quest Tracker's click: the game's map and quest log are this map
-- while it is on); false when the quest is not in the log
function M:OpenQuest(questID)
	questID = Finite(questID)
	if not (self.isEnabled and questID) then
		return false
	end
	if not win.frame then
		Build()
	end
	win.frame:Show()
	return Log.Select(questID)
end

--------------------------------------------------------------------------------
-- /mellomap dump and /melloperf map
--------------------------------------------------------------------------------

local function F(v)
	return v and string.format("%.4f", v) or "-"
end

local function Dump()
	local c = win.canvas
	if not (c and c.places) then
		return "The map has not been opened yet."
	end
	local out = {}
	out[#out + 1] = string.format("world %s x %s, view %s %s zoom %s (max %s), canvas %s x %s", F(c.W), F(c.H),
		F(c.cx), F(c.cy), F(c.z), F(c.zMax), F(c.cw), F(c.ch))
	local caves, cavesLive = 0, 0
	c:EachPlace(function(p)
		if p.kind == "cave" then
			-- (the caves counted in one line: 358 of them)
			caves = caves + 1
			cavesLive = cavesLive + (p.live and 1 or 0)
			return
		end
		out[#out + 1] = string.format("%5d %-9s %-24s %s %s %s %s alpha %s %s tiles %s", p.id, p.kind, p.name or "?",
			F(p.left / c.W), F(p.right / c.W), F(p.top / c.H), F(p.bottom / c.H), F(p.alpha), p.live and "live" or "-",
			p.tiles and #p.tiles or "-")
	end)
	out[#out + 1] = string.format("caves %d, %d in view now", caves, cavesLive)
	return table.concat(out, "\n")
end

local function PerfReport()
	local c = win.canvas
	if not (c and c.places) then
		return "The map has not been opened yet: open it (/mellomap), move it about, then /melloperf map again."
	end
	local s = c:Stats()
	local avg = s.moveFrames > 0 and s.moveSum / s.moveFrames or 0
	local lines = {
		string.format("Places laid: %d (in %.2f ms, at the first open)", s.placed, s.layoutMs or 0),
		string.format("Last open: %.2f ms", s.openMs or 0),
		string.format("View set %d times: the last %.3f ms, the most %.3f ms of Lua", s.views, s.lastMs, s.maxMs),
		string.format("While it moved: %d frames, %.1f ms on average, %.1f ms the longest", s.moveFrames, avg, s.moveMax),
		string.format("Culled %d times; maps in view %d; tiles shown %d of %d known, %d made, %d files set, %d waiting",
			s.culls, s.live, s.shown, s.tiles, s.made, s.files, s.queued),
		"The numbers since the last /melloperf map reset.",
	}
	return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- The game's map key (the user, 2026-10-20: "this map is going to be a
-- replacement for the Default "M" "L" keybinds map, and users will only see
-- and interract with this one"): while the map is on, every key bound to the
-- game's world map opens this one, every key bound to the game's quest
-- log opens it with the quest log out (MapQuestLog.lua) -- override bindings
-- on a frame of ours, never the player's own bindings changed; set out of a
-- fight (the bindings are locked in one: done as it ends); set again when the
-- player binds other keys; given back when the map goes off.
--------------------------------------------------------------------------------

-- the game's action, and the map's command (Bindings.xml) its keys run instead
local KEYS = { { "TOGGLEWORLDMAP", "MELLOUI_MAP_TOGGLE" }, { "TOGGLEQUESTLOG", "MELLOUI_MAP_QUESTLOG" } }
local Keys = { on = false, bound = {}, want = {}, cmd = {}, boundCmd = {} }

-- the keys to take now, sorted, and each one's command into `cmd`
local function KeysNow(out, cmd)
	wipe(out)
	wipe(cmd)
	for _, pair in ipairs(KEYS) do
		local keys = { GetBindingKey(pair[1]) }
		for _, key in ipairs(keys) do
			if type(key) == "string" and key ~= "" and not cmd[key] then
				out[#out + 1] = key
				cmd[key] = pair[2]
			end
		end
	end
	table.sort(out)
	return out
end

local function Same(a, b, ca, cb)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] or ca[a[i]] ~= cb[b[i]] then
			return false
		end
	end
	return true
end

local function ApplyKeys()
	local f = Keys.frame
	if InCombatLockdown() then
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	f:UnregisterEvent("PLAYER_REGEN_ENABLED")
	local want, cmd = Keys.want, Keys.cmd
	if Keys.on then
		KeysNow(want, cmd)
	else
		wipe(want)
		wipe(cmd)
	end
	if Keys.applied and Same(want, Keys.bound, cmd, Keys.boundCmd) then
		return
	end
	ClearOverrideBindings(f)
	local bound, boundCmd = wipe(Keys.bound), wipe(Keys.boundCmd)
	for _, key in ipairs(want) do
		SetOverrideBinding(f, false, key, cmd[key])
		bound[#bound + 1] = key
		boundCmd[key] = cmd[key]
	end
	Keys.applied = true
end

local function Keys_OnEvent(_, event)
	if event == "PLAYER_REGEN_ENABLED" or event == "UPDATE_BINDINGS" then
		ApplyKeys()
	end
end

local function TakeKeys(on)
	Keys.on = on and true or false
	if not Keys.frame then
		Keys.frame = CreateFrame("Frame")
		Perf.SetScript(Keys.frame, "OnEvent", Keys_OnEvent)
	end
	if Keys.on then
		Keys.frame:RegisterEvent("UPDATE_BINDINGS")
	else
		Keys.frame:UnregisterEvent("UPDATE_BINDINGS")
	end
	Keys.applied = false
	ApplyKeys()
end

-- the keys this map holds now (the tests and the dump), and each one's command
function M:Keys()
	return Keys.bound, Keys.boundCmd
end

-- The minimap's zone header (1.0; the user, 2026-10-20: "clicking on the top part of the minimap, opens the default
-- wow Map"): the game's zone button (MinimapCluster.ZoneTextButton) calls ToggleWorldMap, which these keys never
-- reach. While this map is on, an own click catcher lies over the button -- a cover: nothing of the game's button is
-- changed -- from its left edge to the clock's (TimeManagerClockButton keeps its own click), one level over it; its
-- tooltip the game's own (the zone, its PvP state, the World Map key). Off: hidden, the game's click again.
local Header = {}

local function HeaderTip(self)
	local button = Header.button
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	local ok = false
	local pvp, setTip = rawget(_G, "C_PvP"), rawget(_G, "Minimap_SetTooltip")
	if pvp and pvp.GetZonePVPInfo and type(setTip) == "function" then
		local pvpType, _, factionName = pvp.GetZonePVPInfo()
		ok = pcall(setTip, pvpType, factionName)
	end
	if not ok then
		local zone = rawget(_G, "GetZoneText")
		GameTooltip:SetText(zone and zone() or "")
	end
	local line = button and button.tooltipText
	if type(line) == "string" then
		GameTooltip:AddLine(line, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function HeaderLevel()
	local cover, button = Header.cover, Header.button
	if cover and button then
		cover:SetFrameLevel((button:GetFrameLevel() or 0) + 2)
	end
end

local function TakeHeader(on)
	local button = MinimapCluster and MinimapCluster.ZoneTextButton
	if not button then
		return
	end
	local cover = Header.cover
	if not on then
		if cover then
			cover:Hide()
		end
		return
	end
	if not cover then
		Header.button = button
		cover = CreateFrame("Button", nil, button)
		cover:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		Perf.SetScript(cover, "OnClick", function()
			M:Toggle()
		end)
		Perf.SetScript(cover, "OnEnter", HeaderTip)
		Perf.SetScript(cover, "OnLeave", function()
			GameTooltip:Hide()
		end)
		Perf.SetScript(cover, "OnShow", HeaderLevel)
		Header.cover = cover
		-- (MinimapPanel lifts the zone row over the map by its levels: one over the button again after each)
		;(Perf.hooksecurefunc or hooksecurefunc)(button, "SetFrameLevel", HeaderLevel)
	end
	cover:ClearAllPoints()
	local clock = rawget(_G, "TimeManagerClockButton")
	cover:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT")
	if clock and clock:IsShown() then
		cover:SetPoint("TOPRIGHT", clock, "TOPLEFT", -1, 0)
	else
		cover:SetPoint("TOPRIGHT", button, "TOPRIGHT")
	end
	HeaderLevel()
	cover:Show()
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db or self.db
	TakeKeys(true)
	TakeHeader(true)
	Dungeon.Listen(true)   -- (2.1.0: the bosses down this run, for a dungeon's plan)
end

-- (MelloUI.Map:Show(uiMapID), the API's) the map opened, framed on that map
AddonPins.Shown(function(uiMapID)
	if not M.isEnabled then
		return false
	end
	M:Toggle(true)
	if uiMapID and win.canvas then
		Dungeon.Hide()
		if win.canvas.byID[uiMapID] then
			win.canvas:Fit(uiMapID)
		end
	end
	return true
end)

function M:OnDisable()
	TakeKeys(false)
	TakeHeader(false)
	Dungeon.Listen(false)
	if win.frame then
		Dungeon.Hide()
	end
	Log.Unmount()   -- (the Quest List's page back to the game's column, whose map is the player's again)
	if win.frame then
		win.frame:Hide()
	end
end

SLASH_MELLOMAP1 = "/mellomap"
SLASH_MELLOMAP2 = "/mmap"
SlashCmdList.MELLOMAP = function(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "dump" then
		MelloUI:ShowText("Map", Dump())
	elseif cmd == "share" then
		M:SharePin()
	elseif cmd == "" then
		M:Toggle()
	else
		MelloUI:Print(TEXT.usage)
	end
end

if MelloUI.Perf.AddReport then
	MelloUI.Perf:AddReport("map", "Performance: the map", function(arg)
		if arg == "reset" and win.canvas then
			win.canvas:ResetStats()
			return "The map's numbers start again."
		end
		return PerfReport()
	end)
end

-- the key binding's names (Bindings.xml)
BINDING_HEADER_MELLOUI = "MelloUI"
BINDING_NAME_MELLOUI_MAP_TOGGLE = "Open or close MelloUI's map"
BINDING_NAME_MELLOUI_MAP_QUESTLOG = "Open MelloUI's map with your quests"

ns.Map = M
ns.addon = ADDON

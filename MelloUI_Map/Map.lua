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
local floor, max = math.floor, math.max

local ICON = "Interface\\Icons\\INV_Misc_Map_01"

local T = {
	SHARE = 0.72,      -- the window's width: this share of the screen's (its height from the world's 3 : 2)
	MIN_W = 640,
	PAD = 14, TOP = 34, FOOT = 24, IN = 1,
	HOVER = 0.1,       -- the name under the cursor read at most this often
	CLICK = 4,         -- a press that moved less than this is a click
	PIN_ZOOM = 6,      -- a shared pin opened: the map at least this close
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
	layers = "The map shows",
}

-- (after M4; the user, 2026-10-20: "Layer switches", a button on the map, "Objectives on, rares off") what the map
-- shows: a check per layer, kept in the module's settings (db.layers[key] = false: off; every one on until switched)
local SWITCHES = {
	{ key = "quests", label = "Quest givers", layers = { "quests" } },
	{ key = "objectives", label = "Your quests' objectives", layers = { "objectives", "objective_dots" } },
	{ key = "flights", label = "Flight masters", layers = { "flights" } },
	{ key = "transports", label = "Boats, zeppelins and portals", layers = { "transports" } },
	{ key = "entrances", label = "Dungeons and raids", layers = { "entrances" } },
	{ key = "group", label = "Your party and raid", layers = { "group" } },
	{ key = "names", label = "Zone names", layers = { "names" } },
	{ key = "addons", label = "Other addons' pins", layers = { "addons", "addons_continent", "addons_world" } },
}

local M   -- (the module: its button opens it)
M = MelloUI:RegisterModule("Map", {
	title = "Map",
	desc = "One seamless map of the whole world: zoom from Azeroth down to a zone with the mouse wheel and drag to look around.",
	icon = ICON,
	flavour = "The whole world on one sheet, from the continents down to a village.",
	group = "Quests and travel", navOrder = 4,
	role = "feature",
	enabledByDefault = true,
	defaults = {},
	options = {
		{ type = "button", name = TEXT.open, text = "Open", new = "0.25.0",
		  desc = "Open MelloUI's map: the wheel zooms toward the cursor, a drag looks around, a click glides into the zone under the cursor and a right-click goes out again. Your map key (M) opens it, your quest log key (L) opens it with your quests beside it; /mellomap opens it too.",
		  onClick = function() M:Toggle(true) end },
	},
})

local win = {}

--------------------------------------------------------------------------------
-- The view kept: the centre on the world (0..1) and the zoom
--------------------------------------------------------------------------------

local function SaveView()
	local c = win.canvas
	if not (c and c.cx and M.db) then
		return
	end
	M.db.view = { x = c.cx / c.W, y = c.cy / c.H, z = c.z }
end

-- the view to open at: the one kept, else the player's zone (or the world)
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
	if name ~= win.shownName then
		win.shownName = name
		win.name:SetText(name or TEXT.hint)
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

-- one handler while the cursor is over the canvas or a drag runs: the drag's pan, the name (throttled)
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
				local k = c.k1 * c.z
				c:SetView(d.cx - dx / k, d.cy - dy / k, c.z)
			end
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
	c:Stop()
	local d = win.drag
	d.on, d.x, d.y, d.cx, d.cy, d.moved = true, x, y, c.cx, c.cy, false
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
	local ok
	if QL then
		ok = QL.RouteToPoint(mapID, mx, my, label, TEXT.pinNotice)
	elseif R and R.isEnabled and R.SetDestinationTo then
		ok = R:SetDestinationTo({ mapID = mapID, x = mx, y = my }, label, true, TEXT.pinNotice)
	elseif C_Map.SetUserWaypoint and UiMapPoint then
		ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, mx, my))
	else
		MelloUI:Print(TEXT.pinOff)
		return false
	end
	if ok then
		MelloUI:PlayUISound("click")
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
-- The layers' switches (the layers button's menu)
--------------------------------------------------------------------------------

local function LayerOn(key)
	local l = M.db and M.db.layers
	return not (type(l) == "table" and l[key] == false)
end

local function ApplyLayers()
	local pins = win.pins
	for _, s in ipairs(SWITCHES) do
		local on = LayerOn(s.key)
		for _, name in ipairs(s.layers) do
			if pins.layers[name] then
				pins:Show(name, on)
			end
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
end
M.SetLayer, M.LayerOn = function(_, key, on) SetLayer(key, on) end, function(_, key) return LayerOn(key) end

local function LayersMenu(_, root)
	root:CreateTitle(TEXT.layers)
	for _, s in ipairs(SWITCHES) do
		root:CreateCheckbox(s.label, function()
			return LayerOn(s.key)
		end, function()
			SetLayer(s.key, not LayerOn(s.key))
		end)
	end
end

-- (the game's menu, as the Quest List's filter; not in the Gamepad UI, where the button hides: the game's menu
-- opened from MelloUI code runs its frame manager in MelloUI's run -- the Services note)
local FilterClick = Perf.Shared("OnClick on the map's layers button", function(self)
	if MelloUI.Safe.GamepadUI() or not (MenuUtil and MenuUtil.CreateContextMenu) then
		return
	end
	MelloUI:PlayUISound("click")
	MenuUtil.CreateContextMenu(self, LayersMenu)
end, "script")

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
	MelloUI:PlayUISound("click")
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
		c:Out()
		return
	elseif button == "MiddleButton" then
		Layers.FindMe()
		return
	end
	local d = win.drag
	if not d.on then
		return
	end
	d.on = false
	if d.moved then
		c.moving = false
		c.stats.lastAt = nil
		c:Refocus()
		SaveView()
	else
		-- (Ctrl: your pin; a click on a pin is the pin's; elsewhere a glide in)
		local pin = win.pins:At(d.x, d.y)
		if IsControlKeyDown() then
			SetPin(d.x, d.y)
		elseif pin and pin.spec.click then
			pin.spec.click(pin, button, pin.spec.enter and PinAnchor(pin) or nil)
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

local function Size()
	local sw = Finite(UIParent:GetWidth()) or 1280
	local sh = Finite(UIParent:GetHeight()) or 720
	local w = max(T.MIN_W, floor(sw * T.SHARE))
	local h = floor(w * 668 / 1002) + T.TOP + T.FOOT + T.PAD
	if h > sh * 0.9 then
		h = floor(sh * 0.9)
		w = floor((h - T.TOP - T.FOOT - T.PAD) * 1002 / 668)
	end
	return w, h
end

-- the window's parts where the look puts them, at the build and at every switch (shell:OnKit)
local function Lay(sh)
	local body, f = win.body, win.frame
	local edge, top = sh:Inset(T.PAD, -T.TOP)
	body:ClearAllPoints()
	body:SetPoint("TOPLEFT", f, "TOPLEFT", edge, top)
	body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -edge, edge)
end

-- the view laid again on the canvas's size: the first one (the one kept, else your zone) the first time it has a
-- size -- at the show, or at a later size change when the show came before the layout
local function Refit()
	local c = win.canvas
	if not (c.places and c:Size()) then
		return
	end
	c.box[5] = nil
	if c.cx then
		c:SetView(c.cx, c.cy, c.z)
	else
		c:SetView(StartView(c))
	end
end

local function Canvas_OnSizeChanged()
	Log.Size()
	if win.frame:IsShown() then
		Refit()
	end
end

local function Shown()
	local c = win.canvas
	local t0 = debugprofilestop()
	c:Layout()
	Refit()
	Layers.Open()
	AddonPins.Open()   -- (nothing while its switch is off: other addons' icons left to the game's map)
	Objectives.Open()
	Log.Shown()
	local filter = Log.Filter()
	if filter then
		filter:SetShown(not MelloUI.Safe.GamepadUI())
	end
	c.stats.openMs = debugprofilestop() - t0
	local f = win.frame
	f:RegisterEvent("MAP_EXPLORATION_UPDATED")
	f:RegisterEvent("TAXIMAP_OPENED")
	f:RegisterEvent("TAXI_NODE_STATUS_CHANGED")
	f:RegisterEvent("QUEST_LOG_UPDATE")
	f:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
end

local function Hidden()
	Layers.Close()
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
	end
end

local function Build()
	local f = CreateFrame("Frame", "MelloUIMapFrame", UIParent)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetSize(Size())
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:Hide()
	win.frame = f
	win.path = {}
	win.drag = { on = false }
	win.shell = Kit:OwnWindow(f, {
		area = "config", ring = { at = "tl", texture = ICON }, plate = "rail",
		title = TEXT.title, close = true, escape = true, fit = true, sounds = true,
		mover = { key = "MelloUIMap", label = TEXT.title, page = "Map" },
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
		Layers.Route()
		Layers.Labels()
		Log.ViewChanged()   -- (the Quest List's tab: its Current zone the zone under the view)
		AddonPins.View()    -- (other addons' OnViewChanged)
	end
	Layers.Init(canvas, pins)
	AddonPins.Init(canvas, pins)
	Objectives.Init(canvas, pins)
	pins:Layer("names", Layers.T.ORDER.names)   -- (made here: its switch applies before the first names are laid)
	-- the quest log's column on the canvas's right: out or folded as it was left
	win.module = M
	Log.Init(win)
	-- (M4) the search in the title row
	Search.Init(win)
	-- (after M4) the layers button beside the column's opener; the layers as they were left
	Log.Filter(FilterClick)
	ApplyLayers()
	local name = W.Text(body, "GameFontHighlight", nil, "text")
	name:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 8, 5)
	name:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -8, 5)
	name:SetJustifyV("BOTTOM")
	name:SetWordWrap(false)
	win.name = name
	ShowName(false)
	Perf.SetScript(cf, "OnMouseWheel", Canvas_OnMouseWheel)
	Perf.SetScript(cf, "OnMouseDown", Canvas_OnMouseDown)
	Perf.SetScript(cf, "OnMouseUp", Canvas_OnMouseUp)
	Perf.SetScript(cf, "OnEnter", Canvas_OnEnter)
	Perf.SetScript(cf, "OnLeave", Canvas_OnLeave)
	Perf.SetScript(cf, "OnSizeChanged", Canvas_OnSizeChanged)
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
	if f:IsShown() and Log.IsOut() then
		f:Hide()
		return
	end
	f:Show()
	Log.SetOut(true)
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
	c:EachPlace(function(p)
		out[#out + 1] = string.format("%5d %-9s %-24s %s %s %s %s alpha %s %s tiles %s", p.id, p.kind, p.name or "?",
			F(p.left / c.W), F(p.right / c.W), F(p.top / c.H), F(p.bottom / c.H), F(p.alpha), p.live and "live" or "-",
			p.tiles and #p.tiles or "-")
	end)
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

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function M:OnInit(db)
	self.db = db
end

function M:OnEnable(db)
	self.db = db or self.db
	TakeKeys(true)
end

-- (MelloUI.Map:Show(uiMapID), the API's) the map opened, framed on that map
AddonPins.Shown(function(uiMapID)
	if not M.isEnabled then
		return false
	end
	M:Toggle(true)
	if uiMapID and win.canvas and win.canvas.byID[uiMapID] then
		win.canvas:Fit(uiMapID)
	end
	return true
end)

function M:OnDisable()
	TakeKeys(false)
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

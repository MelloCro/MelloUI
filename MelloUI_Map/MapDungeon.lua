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
-- was. Its pins: the bosses in Dungeon Info's order (the map's seal with the
-- number; one down this run grey, the one whose page is open bigger), and you
-- (the game's arrow, where the game gives your place inside). Dungeon Info's
-- page of the instance stands beside it; a boss's click opens his loot there.
-- The "World map" button at the top left, or a right-click at the plan's
-- widest view, goes back to the world.
--
-- Blizzard's drawings (the user, 2026-11-03: "use the Blizzard own dungeon
-- maps for the existing ones"): an old dungeon's wings are Blizzard's own drawn
-- floors -- the client holds their art, no map of them -- laid by their place
-- (MapDungeons' drawn, rect, art; MapCanvas' DrawnPlace); Forever's own keep
-- the plan made from the client's floor pictures.
--
-- From outside (the user, 2026-11-03: "Can i open the dungeon map by clicking
-- on it on the map, or clicking on the dungeon in the dungeon info?"): Dungeon
-- Info's page of an instance shows its plan too (M:ShowDungeon) -- a click on
-- its door on the world map, or on its row in Dungeon Info's list. Your arrow
-- and the wing that follows you are the instance's you stand in only.
--
-- Wings (the user, 2026-11-02: "Several floors, we need to spread them into
-- Wings"): a dungeon whose floors lie over each other comes in wings (the
-- data's, each named by the game's own area name), one shown at a time, picked
-- with the chips beside the World map button. The map opens on the wing you
-- stand in -- the minimap's area name (GetMinimapZoneText) is one of its own --
-- and follows you into another as the name changes; your arrow shows on yours.
--
-- Doors and wing arrows (the user, 2026-11-02: "show where the entrances and
-- exits are in the dungeon, and arrows in specific spots where you enter other
-- wings"): the way in and out (the world map's dungeon door pin), and at each
-- doorway into another wing an arrow up or down named with that wing -- a click
-- shows that wing there.
--
--   Dungeon.Init(win, hook)      at the window's build (hook(frame): the canvas's
--                                mouse, as the world's)
--   Dungeon.Current() -> map     the instance you are in, when it has a plan and
--                                the option is on; else nil
--   Dungeon.Has(map) -> bool     a plan of it, and the option on
--   Dungeon.Show(map)          the plan shown (its canvas made the first time)
--   Dungeon.Hide(keep)           the world again (keep: the plan's files kept, it
--                                shows again at once)
--   Dungeon.Shown() -> map       the plan shown now, or nil
--   Dungeon.Out()                a right-click: out, then the world
--   Dungeon.FindMe()             a middle-click: the view on you
--   Dungeon.Tick(elapsed)        your arrow (the window's beat)
--   Dungeon.Listen(on)           the run's kills (the module on / off)
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
local Canvas, Pins = ns.Canvas, ns.Pins
local ipairs, pcall, type, wipe, max = ipairs, pcall, type, wipe, math.max

local Dungeon = {}
ns.Dungeon = Dungeon

local T = {
	GRID = 32 * 1600 / 3,    -- yards from the world's middle to the terrain grid's 0, 0
	ICONS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\",
	SEAL = "badge_disc",     -- the bosses' seal: the map's capitals' (MapLayers' CAPITAL)
	SEAL_GOLD = "selectedTrim",
	SEAL_DOWN = "border",    -- (a boss down this run: his seal grey)
	SEAL_DISC = "raisedPanel",
	SEAL_DARK = "innerPanel",
	PIN = 22,
	PIN_PICKED = 28,         -- the boss whose page is open
	RIM = 2,
	EDGE = 1,
	ARROW_SIZE = 26,
	ARROW_ATLAS = "UI-WorldMapArrow",                 -- the game's own map arrow
	ARROW_FILE = "Interface\\Minimap\\MinimapArrow",  -- (if the atlas is missing)
	EVERY = 0.1,             -- your place read at most this often
	ORDER = { doors = 14, links = 16, bosses = 20, player = 50 },
	DOOR = "pin_dungeon",    -- the way in and out: the world map's dungeon door (MapLayers' ENTRANCE_ICON)
	DOOR_SIZE = 20,
	-- the doorways into another wing: the game's own dungeon-map door arrows (the user's pick A of
	-- Workspace/BuildData/output/dungeonmap_sketch/marks_sheet.png, 2026-11-02): up, down, a door on the same floor
	LINK_ATLAS = { [1] = "poi-door-arrow-up", [-1] = "poi-door-arrow-down", [0] = "poi-door" },
	LINK_SIZE = 22,
	BACK_AT = 8,             -- the World map button: px in from the canvas's top left
	FIND_ZOOM = 2,           -- Find me: at least this close
	OUT_AT = 1.02,           -- a right-click at this share of the wing's whole view or wider: the world
	CHIPS_GAP = 8,           -- the wings' chips: px right of the World map button ...
	CHIPS_RIGHT = 8,         -- ... and in from the canvas's right (2.1.0: the map's buttons on the rail beside it)
	CHIPS_MIN = 160,
}

local TEXT = {
	back = "World map",
	hint = "Wheel: zoom   Drag: look around   Click a boss: his loot   Right-click: out, then the world map",
	open = "Click: his loot",
	down = "Down this run",
	wing = "Wing %d",        -- (a wing the game names nothing)
	door = "Way in and out",
	linkUp = "Up to %s",
	linkDown = "Down to %s",
	linkLevel = "To %s",
	linkClick = "Click: show this wing",
}

local S = { canvases = {}, killed = {}, areas = {}, wingOf = {} }

--------------------------------------------------------------------------------
-- The instance you are in
--------------------------------------------------------------------------------

local function Plan(mapID)
	local all = ns.MapDungeons
	return mapID and type(all) == "table" and all[mapID] or nil
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

function Dungeon.Current()
	if not On() then
		return nil
	end
	local mapID = InstanceMap()
	return Plan(mapID) and mapID or nil
end

function Dungeon.Has(mapID)
	return On() and Plan(mapID) ~= nil
end

function Dungeon.Shown()
	return S.shown
end

function Dungeon.Hint()
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

--------------------------------------------------------------------------------
-- The bosses
--------------------------------------------------------------------------------

-- Dungeon Info's instance of a map (MelloUI_DungeonInfo, when it is there and on) and his bosses' names by encounter
local function Info(mapID)
	local J = rawget(MelloUI, "DungeonInfo")
	if not (type(J) == "table" and J.ByMap and J.M and J.M.isEnabled) then
		return nil
	end
	local ok, inst = pcall(J.ByMap, mapID)
	return J, ok and type(inst) == "table" and inst or nil
end

local function BossTip(pin)
	local down = S.killed[pin.data.encounter]
	return pin.name, down and (TEXT.down .. "\n" .. TEXT.open) or TEXT.open
end

local function BossClick(pin)
	S.picked = pin.data.encounter
	Dungeon.Bosses()
	local J, inst = Info(S.shown)
	if J and inst then
		pcall(J.Open, inst.key, pin.data.encounter)
	end
end

local specs = {}

-- a boss's seal: the map's capitals' (the gold rim round a slate core), his number in it; down this run: grey; his
-- page open: bigger
local function BossSpec(n, down, picked)
	local key = n .. (down and "d" or "") .. (picked and "p" or "")
	local spec = specs[key]
	if not spec then
		spec = {
			icon = T.ICONS .. T.SEAL, size = picked and T.PIN_PICKED or T.PIN, tint = down and T.SEAL_DOWN or T.SEAL_GOLD,
			core = T.SEAL_DISC, rim = T.RIM, disc = T.SEAL_DARK, edge = T.EDGE, number = n,
			numberKey = down and "mutedText" or "text", label = true, sub = picked and 2 or 1,
			tip = BossTip, click = BossClick,
		}
		specs[key] = spec
	end
	return spec
end

-- the way in and out, and the doorways into other wings, of the wing shown
local DOOR = { size = T.DOOR_SIZE, sub = 1, lift = T.DOOR }
local linkSpecs = {}

local function WingName(d, w)
	local wing = d.wings and d.wings[w]
	return wing and wing.name or TEXT.wing:format(w)
end

local function LinkTip(pin)
	return pin.name, TEXT.linkClick
end

local function LinkClick(pin)
	local c = S.canvases[S.shown]
	Dungeon.SetWing(pin.data.to)
	if c then
		c:Glide(pin.wx, pin.wy, c.z)   -- (that wing, at this doorway)
	end
end

local function LinkSpec(way)
	local spec = linkSpecs[way]
	if not spec then
		-- (its wing named on hover)
		spec = { atlas = T.LINK_ATLAS[way] or T.LINK_ATLAS[0], size = T.LINK_SIZE, sub = 1, tip = LinkTip,
			click = LinkClick }
		linkSpecs[way] = spec
	end
	return spec
end

local function Marks(d, shown)
	local pins = S.pins
	DOOR.icon = DOOR.icon or T.ICONS .. T.DOOR
	DOOR.tip = DOOR.tip or TEXT.door
	pins:Clear("doors")
	local doors = type(d.doors) == "table" and d.doors or {}
	for i = 1, #doors - 2, 3 do
		local x, y, w = Finite(doors[i]), Finite(doors[i + 1]), Finite(doors[i + 2])
		if x and y and (w or 1) == shown then
			pins:Set("doors", i, x, y, DOOR)
		end
	end
	pins:Clear("links")
	local links = type(d.links) == "table" and d.links or {}
	for i = 1, #links - 4, 5 do
		local x, y, w, to, way = Finite(links[i]), Finite(links[i + 1]), Finite(links[i + 2]), Finite(links[i + 3]),
			Finite(links[i + 4])
		if x and y and w == shown and to then
			local pin = pins:Set("links", i, x, y, LinkSpec(way or 0))
			if pin then
				local text = way == 1 and TEXT.linkUp or way == -1 and TEXT.linkDown or TEXT.linkLevel
				pin.name = text:format(WingName(d, to))
				pin.data = { to = to }
			end
		end
	end
end

-- every boss of the wing shown, numbered in Dungeon Info's order (the data's own order without it) through all wings;
-- its doors and doorways
function Dungeon.Bosses()
	local mapID, pins = S.shown, S.pins
	local d = Plan(mapID)
	if not (d and pins) then
		return
	end
	pins:Clear("bosses")
	local list = type(d.bosses) == "table" and d.bosses or {}
	local _, inst = Info(mapID)
	local order, names = {}, {}
	for i, b in ipairs(inst and inst.bosses or {}) do
		local enc = type(b) == "table" and Finite(b.id or b[1])
		if enc then
			order[enc] = i
			names[enc] = type(b.name) == "string" and b.name or nil
		end
	end
	local c = S.canvases[mapID]
	local shown = c and c.wing or 1
	Marks(d, shown)
	for i = 1, #list - 3, 4 do
		local enc, x, y, wing = Finite(list[i]), Finite(list[i + 1]), Finite(list[i + 2]), Finite(list[i + 3])
		if enc and x and y and (wing or 1) == shown then
			local n = order[enc] or (i + 3) / 4
			local pin = pins:Set("bosses", enc, x, y, BossSpec(n, S.killed[enc], S.picked == enc))
			if pin then
				pin.name = names[enc] or tostring(n)
				pin.data = { encounter = enc }
			end
		end
	end
	pins:Lay()
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

-- your place on the plan shown (yards from its top left), or nil: the game gives none inside, or a secret, or you are
-- not in that instance (its plan shown from outside)
local function You()
	local d = Plan(S.shown)
	if not (d and UnitPosition) or InstanceMap() ~= S.shown then
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

function Dungeon.Tick(elapsed)
	if not S.shown then
		return
	end
	S.wait = (S.wait or 0) - elapsed
	if S.wait <= 0 then
		S.wait = T.EVERY
		Player()
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
	pins:Layer("doors", T.ORDER.doors)
	pins:Layer("links", T.ORDER.links, { nudge = true })
	pins:Layer("bosses", T.ORDER.bosses, { nudge = true })
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

-- the wing shown: its rooms, its bosses, the view on the whole of it (glide: there in a glide)
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
	Dungeon.Bosses()
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
	Dungeon.Bosses()
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
-- The run: the bosses down since you came in (ENCOUNTER_END's success); the
-- wing you walk into (the minimap's area name)
--------------------------------------------------------------------------------

local function Listen_OnEvent(_, event, ...)
	if event == "ENCOUNTER_END" then
		local enc, _, _, _, success = ...
		enc, success = Finite(enc), Finite(success)
		if enc and success == 1 then
			S.killed[enc] = true
			if S.shown then
				Dungeon.Bosses()
			end
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		local mapID = InstanceMap()
		if mapID and mapID ~= S.run then
			wipe(S.killed)
			S.picked = nil
		end
		S.run = mapID or S.run
	elseif S.shown then
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
		f:RegisterEvent("ENCOUNTER_END")
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
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

Dungeon.S = S   -- (the tests' way in: the run's kills, the event frame)

return Dungeon

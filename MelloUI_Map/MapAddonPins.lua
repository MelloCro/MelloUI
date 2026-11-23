--------------------------------------------------------------------------------
-- MelloUI Map - other addons' pins (docs/plans/seamless-map.md, stage M4; the
-- user, 2026-10-20: GatherMate2, HandyNotes and Questie on the map, and an API
-- for other addons)
--
-- Three ways in, each read only while the map shows, and only from the other
-- addon's own tables and calls (no Blizzard frame or table touched: the game's
-- map keeps its data providers as they are):
--
--   HereBeDragons  the icons addons put on the game's world map through
--                  HereBeDragons-Pins-2.0 (Questie's own copy, renamed,
--                  included): each icon frame is borrowed onto this map, as the
--                  library itself moves it between the game's maps, at the
--                  place the library's own conversions give, gated by its show
--                  flag (its zone from a zone's zoom on, the continent's or the
--                  world's further out); its own mouse, tooltip and clicks.
--                  Handed back hidden when the map closes. The library's adds
--                  and removes are followed by post-hooks on its own table.
--   HandyNotes     its plugins' nodes (GetNodes2) and GatherMate2's (its
--   GatherMate2    GetNodesForZone, with its own filters): they draw on the
--                  game's map through data providers of their own, so here
--                  they are this map's pins, per zone, built for the zones in
--                  view from a zone's zoom on (GatherMate2's imported data runs
--                  to tens of thousands) and let go further away; their own
--                  size, alpha and pictures. HandyNotes' tooltips and clicks
--                  are its plugins' own (OnEnter / OnClick on a frame laid on
--                  the pin); GatherMate2's tooltip its node's name in its
--                  tracking colour. Built again when either redraws its pins.
--   MelloUI.Map    the API below: pins of other addons' own, this map's.
--
--   MelloUI.Map:AddPin(owner, key, uiMapID, x, y, spec) -> true, or false (no such map here)
--       owner      your addon's name (or any value: the pins are kept under it)
--       x, y       0..1 on uiMapID (the game's map positions)
--       spec       icon (a file path or file ID) or atlas, size (px, 16), rgb { r, g, b }, alpha,
--                  tip (a text, or fn(key) -> title, body), click (fn(key, button)),
--                  show ("zone": from a zone's zoom on, the default; "continent"; "world": at every zoom)
--   MelloUI.Map:ClearPin(owner, key)       MelloUI.Map:ClearPins(owner)
--   MelloUI.Map:OnViewChanged(owner, fn)   fn(uiMapID): the map under the view's middle changed (the zone, or the
--                                          continent zoomed out; nil over the sea), and as the map opens; nil: none
--   MelloUI.Map:IsShown()                  MelloUI.Map:Show(uiMapID)   (the map opened, framed on that map)
--
-- Pins added while the map was never opened are kept and laid at its first
-- open; nothing runs at login (the API's table only).
--
--   AddonPins.Init(canvas, pins)   the layers (the window's first open)
--   AddonPins.Open() / Close()     the window shown / hidden
--   AddonPins.Tick()               the window's OnUpdate (queued changes; zones coming into view)
--   AddonPins.View()               the canvas's view moved (OnViewChanged)
--   AddonPins.Shown(fn)            (Map.lua) how the API asks whether the map shows, and opens it
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Map (AddonPins)")
local Safe = MelloUI.Safe
local Finite, Text = Safe.Finite, Safe.Text
local hooksecurefunc = Perf.hooksecurefunc
local pairs, ipairs, pcall, type, next = pairs, ipairs, pcall, type, next
local floor, min, max = math.floor, math.min, math.max
local wipe = wipe

local AddonPins = {}
ns.AddonPins = AddonPins

local T = {
	-- the layers: under the quest givers (20), over the docks and flights (14)
	ORDER = { zone = 16, continent = 17, world = 18 },
	ZONE_FROM = 2.5,         -- a zone's pins from a zone's zoom on (a zone's zoom)
	CONTINENT_FROM = 1.15,   -- a continent's from a continent's zoom on (the docks' and flights': PLACES_FROM)
	NODE = 14,               -- HandyNotes' and GatherMate2's 12 px icon at the game's map's top pin scale (1.2)
	KEEP = 12,               -- zones' nodes kept built: the ones in view, then the nearest seen last
	BUILD_PER_FRAME = 2,     -- zones built in one frame (a zone of imported gathering data: hundreds of nodes)
	SIZE = 16,               -- an API pin's size by default
	QUESTIE = 18,            -- (2.1.56) a dressed Questie icon's picture: this map's own pin size (MapLayers' PIN_SIZE)
	-- HereBeDragons' world map pins: the library's own name, and Questie's renamed copy
	HBD = {
		{ pins = "HereBeDragons-Pins-2.0", hbd = "HereBeDragons-2.0" },
		{ pins = "HereBeDragonsQuestie-Pins-2.0", hbd = "HereBeDragonsQuestie-2.0", questie = true },
	},
	SHOW_CONTINENT = 2,      -- HBD_PINS_WORLDMAP_SHOW_CONTINENT
	SHOW_WORLD = 3,          -- HBD_PINS_WORLDMAP_SHOW_WORLD
	DEPTH = 8,               -- parents walked up from a map this canvas does not have (a micro zone's, a cave's)
	PICTURES = { "texture", "icon", "Texture", "Icon" },   -- (2.1.53) where an addon's icon frame keeps its picture
}
AddonPins.T = T

local LAYER = { zone = "addons", continent = "addons_continent", world = "addons_world" }
-- (2.1.51) Questie's givers and turn-ins while they are the givers (QuestieLook's Givers): a layer of their own under
-- the map's Quest givers switch (Map.lua's SWITCHES), never the one of the other addons' pins
LAYER.questGivers = "quests_questie"
-- (2.1.52, stage 2) Questie's objective icons while Questie wears its own look (its switch on the Addons page off):
-- a layer of their own under the map's Your quests' objectives switch. In MelloUI's look this map lays its own marks
-- there and Questie's of that kind are never borrowed (Covered)
LAYER.questObjectives = "objectives_questie"
-- (2.1.53) the town marks (MapTownMarks: the plugin's places in MelloUI's icons): a layer of their own, each kind
-- under its own switch of the layers' page -- never the other addons' pins' one
LAYER.town = "addons_town"
AddonPins.LAYER = LAYER

local S = {
	canvas = nil, pins = nil, shown = false,
	libs = {}, byLib = {},          -- HereBeDragons: each library found { pins, hbd, maps = {}, conts = {}, full }
	owner = {}, layerOf = {}, specs = {},   -- [icon frame] = its library's entry / its layer / its spec (one per icon)
	queue = {}, queued = false,     -- [icon] = entry: added or removed while the map showed
	ours = {},                      -- [layer frame] = true
	zones = {}, zoneCount = 0, zoneGen = 0, stale = false, cut = nil,   -- HandyNotes' and GatherMate2's zones built
	api = {}, apiCount = 0, views = {}, viewID = false,
	shownFn = nil,
}
AddonPins.S = S

--------------------------------------------------------------------------------
-- Questie's icons in MelloUI's own look (2.1.4; the user, 2026-11-05: "Those polestar and questie icons need to be
-- replaced by our own, we have the library for it, and match the themes"; a player's screenshot: Questie's "!" cut off
-- on this map). An icon of Questie's (its renamed library's) is known by its picture's file name (Questie.icons):
--   a quest whose giver or ender the quest givers show already, or whose objectives this map's objectives lay: not
--   borrowed -- nothing twice, as the followed guide's goals (MapObjectives); looked at again whenever either lays
--   one with a picture of MelloUI's own (QUESTIE_LOOK): that picture on the frame -- the quest givers' (the game's
--   quest marks, greyed as the Quest List greys them) or the icon set's in the look on (MelloUI.Icons), lifted as
--   this map's marks -- and Questie's own pictures out of sight; its tooltip and clicks Questie's still. Given back as
--   it was (Release: the library shows the same frame on the game's map)
--   any other (gathering nodes, townsfolk, its own markers): Questie's own, as before
-- (Polestar's pins stay on the game's map; on this one its guide's goals are this map's marks already: MapObjectives)
--------------------------------------------------------------------------------

-- (2.1.39) the pictures are the core's (Core/QuestieLook.lua): one table for this map, the minimap and the game's map
local QUESTIE_LOOK = MelloUI.QuestieLook.ICONS
AddonPins.QUESTIE_LOOK = QUESTIE_LOOK
local QUESTIE_PARTS = { "texture", "glowTexture", "overlayTexture" }   -- (QuestieFrame.lua's own pictures)
local ICONS = MelloUI.QuestieLook.ICON_DIR
local styled = setmetatable({}, { __mode = "k" })   -- [Questie's frame] = our picture on it

-- a Questie icon's look: its kind (2.1.43, the core's QL.Look: Questie's data.Icon type, whatever picture the player
-- picked), else its picture's file name (data.Icon, else the texture's own), nil for one of no look of ours
local function QuestieLook(icon)
	local tex = rawget(icon, "texture")
	local ok, p = pcall(tex and tex.GetTexture, tex)
	return MelloUI.QuestieLook.Look(icon, ok and Text(p) or nil)
end

-- (2.1.43; the user's pick, 2026-11-11: "Hide Questie's town icons that MelloUI already draws") Questie's townsfolk
-- (its "manual" icons: one flight master, inn and mailbox a zone, the game's tracking pictures) of a kind this map
-- draws itself are not borrowed.
-- (2.1.53; the user, 2026-11-15: "i only want 1 addon to have Priority on that even if 5 different addons are being
-- used, no duplicate Icons from Different addons") ONE owner a kind of place, for every source: MapTownMarks' Held --
-- a town pin's kind is known by the picture it wears (Questie's: its data's, QL.TownPicture; another addon's: its
-- frame's own), and one whose kind an owner before its source has is not drawn
local function TownKind(entry, icon)
	local Town = ns.TownMarks
	if not Town then
		return nil
	end
	if entry.questie then
		return Town.KindOfPicture(MelloUI.QuestieLook.TownPicture(icon))
	end
	for _, key in ipairs(T.PICTURES) do
		local tex = rawget(icon, key)
		if type(tex) == "table" and tex.GetTexture then
			local get = tex.GetTextureFilePath or tex.GetTexture
			local ok, path = pcall(get, tex)
			local kind = ok and Town.KindOfPicture(path) or nil
			if kind then
				return kind
			end
		end
	end
	return nil
end

-- what this map shows of the quests already (taken once a pass): MapObjectives' objectives laid;
-- (2.1.39; the user, 2026-11-10: "didnt i say that we provide the look? this way we have lost our own function which i
-- like very much") and this map's own layer of them: while the objectives' layer is on, it draws them itself --
-- MelloUI's areas and motions -- and Questie's of that kind are never borrowed; with the layer switched off,
-- Questie's fill in, in MelloUI's pictures. (2.1.52: the quest givers are Questie's alone, never covered)
local function Cover()
	local O = ns.Objectives
	if not (O and O.Laid) then
		return nil
	end
	local Map = MelloUI.modules and MelloUI.modules.Map
	local on = type(Map) == "table" and type(Map.LayerOn) == "function"
	return { laid = O.Laid,
		objectives = on and Map:LayerOn("objectives") and true or false,
		flights = on and Map:LayerOn("flights") and true or false }
end

local function Covered(look, icon, cover)
	-- (2.1.51; the user: "i dont want melloUI Quests to show if Questie is active") Questie's givers and turn-ins are
	-- the givers (QuestieLook's Givers): always drawn, in this map's pictures, on their own layer, which the Quest givers
	-- switch shows or hides (Place)
	if look.cover ~= "objective" or not cover then
		return false
	end
	if cover.objectives then
		return true
	end
	local data = rawget(icon, "data")
	local q = type(data) == "table" and Finite(data.Id)
	return (q and cover.laid(q)) and true or false
end

-- (2.1.51; the user, 2026-11-13: Questie's givers on this map, "mouseovering the quests does not give me the tooltip")
-- Questie's own pictures under ours: hidden (Hide), never at alpha 0 -- on this client a picture's alpha is its vertex
-- colour's, and Questie's tooltip (MapIconTooltip.ShowOnTooltip) shows nothing for an icon whose picture's vertex alpha
-- is 0; its hover recolour (SetVertexColor) and its fade cannot bring a hidden one back either. Each one given back as
-- it was (shown or not: Questie's glow is shown only where it wants one)
local partsOff = setmetatable({}, { __mode = "k" })   -- [Questie's picture] = true while hidden under ours

local function PartsOff(icon)
	for _, key in ipairs(QUESTIE_PARTS) do
		local part = rawget(icon, key)
		if part and part.Hide and part:IsShown() then
			partsOff[part] = true
			part:Hide()
		end
	end
end

local function PartsBack(icon)
	for _, key in ipairs(QUESTIE_PARTS) do
		local part = rawget(icon, key)
		if part and partsOff[part] then
			partsOff[part] = nil
			part:Show()
		end
	end
end

-- (2.1.56; the user, 2026-11-16: "people have questie, but the quest icons on the map are kinda small and they cant
-- click to navigate to them", a picture of a "!" a few pixels tall) a dressed icon's picture at this map's own pin
-- size, by the icons' slider as every pin of this map's (MapPins' Pins.scale: its SetScale asks Recheck) -- it filled
-- Questie's frame until now, which is Questie's size to set (16 px by its Icon Scale settings: 11.5 px a giver as it
-- comes, less on a continent's map) and stays so: the picture is MelloUI's own and only stands on its middle. The
-- frame's mouse area out to the picture's edge and the pins' own margin round it (MapPins' HIT), so its tooltip and
-- its click (GiverClick) answer where this map's own marks do; given back with the picture (Unstyle). Questie in its
-- own look (never dressed) keeps its own sizes
local grown = setmetatable({}, { __mode = "k" })   -- [Questie's frame] = true: its mouse area grown to our picture's

local function QuestiePx()
	local P = ns.Pins
	return floor(T.QUESTIE * (P and Finite(P.scale) or 1) + 0.5)
end
AddonPins.QuestiePx = QuestiePx

local function Restyle(icon, look)
	local tex = styled[icon]
	if not tex then
		tex = icon:CreateTexture(nil, "OVERLAY", nil, 7)
		styled[icon] = tex
	end
	local px = QuestiePx()
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", icon, "CENTER")
	tex:SetSize(px, px)
	if icon.SetHitRectInsets then
		local P = ns.Pins
		local w, h = Finite(icon:GetWidth()) or 0, Finite(icon:GetHeight()) or 0
		local hit = P and P.T and Finite(P.T.HIT) or 0
		local dx, dy = max((px - w) / 2, 0) + hit, max((px - h) / 2, 0) + hit
		icon:SetHitRectInsets(-dx, -dx, -dy, -dy)
		grown[icon] = true
	end
	PartsOff(icon)
	if look.atlas then
		MelloUI.Icons.Release(tex)
		tex:SetTexCoord(0, 1, 0, 1)
		tex:SetAtlas(look.atlas)
	else
		MelloUI.Icons.Set(tex, ICONS .. look.icon)
	end
	tex:SetDesaturated(look.grey == true)
	tex:SetAlpha(look.grey and 0.75 or 1)
	tex:Show()
	-- (lifted as this map's own marks: the look's shade)
	local P = ns.Pins
	if P and P.Lift then
		P.Lift(tex, look.icon or false, px)
	end
end

-- Questie's frame as it was (given back: its library shows it on the game's map too); (2.1.50; the user, 2026-11-13:
-- "im still seeing Questie Icons on the minimap") only while our picture is on it -- Questie's frames are pooled, and
-- one given back late may be a minimap icon by then, which the core keeps out of sight: its pictures given back, then
-- the core's rules laid on it again (MelloUI.QuestieLook.Relay); `quiet`: Questie let it go (its Unload), the next use
-- lays it
local function Unstyle(icon, quiet)
	local tex = styled[icon]
	if not (tex and tex:IsShown()) then
		return
	end
	tex:Hide()
	if grown[icon] then
		grown[icon] = nil
		icon:SetHitRectInsets(0, 0, 0, 0)   -- (2.1.56: its mouse area its own frame's again)
	end
	local P = ns.Pins
	if P and P.Lift then
		P.Lift(tex, false)
	end
	PartsBack(icon)
	if not quiet then
		MelloUI.QuestieLook.Relay(icon)
	end
end
-- (2.1.50) Questie let an icon go: our picture goes with it, never onto the frame's next use
MelloUI.QuestieLook.OnRelease(function(icon)
	Unstyle(icon, true)
end)
-- (2.1.51) Questie set an icon's picture again (its UpdateTexture shows its glow where it wants one): while ours is on
-- it, its own stay hidden under ours
-- (2.1.52) the Questie icons this map holds now, for Questie's tooltip of one of them (QuestieLook's QL.MapIcons: it
-- gathers a tooltip from the icons of the map it is on); the set reused
local held = {}
if MelloUI.QuestieLook.MapIcons then
	MelloUI.QuestieLook.MapIcons(function()
		wipe(held)
		for icon, entry in pairs(S.owner) do
			if entry.questie and icon:IsShown() then
				held[icon] = true
			end
		end
		return held
	end)
end
if MelloUI.QuestieLook.OnMapPicture then
	MelloUI.QuestieLook.OnMapPicture(function(icon)
		local tex = styled[icon]
		if tex and tex:IsShown() then
			PartsOff(icon)
		end
	end)
end
AddonPins.Restyled = function(icon)
	local tex = styled[icon]
	return tex ~= nil and tex:IsShown() and tex or nil
end

-- (MapLayers' quest givers and MapObjectives' objectives laid again) Questie's icons looked at again on the next beat;
-- (2.1.53) `others`: the other addons' instead -- their borrowed icons and their nodes (a town kind got an owner)
function AddonPins.Recheck(others)
	others = others == true
	for _, entry in ipairs(S.libs) do
		if entry.questie ~= others then
			entry.full = true
			S.queued = true
		end
	end
	if others then
		S.stale = true
	end
end

-- (2.1.53; MapTownMarks: a kind's switch, a profession learned) the zones' nodes built again on the next beat
function AddonPins.Stale()
	S.stale = true
end

--------------------------------------------------------------------------------
-- HereBeDragons: the icons borrowed
--------------------------------------------------------------------------------

-- a borrowed icon back where its library keeps an icon it does not show: hidden, on UIParent (its own release)
local function Release(frame)
	Unstyle(frame)
	if S.ours[frame:GetParent()] then
		frame:Hide()
		frame:ClearAllPoints()
		frame:SetParent(UIParent)
	end
end

-- the map of this canvas a pin is placed on: its own map, else the nearest parent the canvas has; a pin set by world
-- yards: the continent of its instance (each answer kept)
local function Target(entry, t)
	local c = S.canvas
	local data = entry.hbd.mapData
	local id = t.uiMapID
	if id then
		local v = entry.maps[id]
		if v == nil then
			v = false
			local m, n = id, 0
			while m and n < T.DEPTH do
				local p = c.byID[m]
				if p and (p.kind == "zone" or p.kind == "city" or p.kind == "continent") then
					v = m
					break
				end
				local d = type(data) == "table" and data[m]
				m = type(d) == "table" and d.parent or nil
				n = n + 1
			end
			entry.maps[id] = v
		end
		return v or nil
	end
	local inst = t.instanceID
	local v = entry.conts[inst]
	if v == nil then
		v = false
		for _, p in ipairs(c.places or {}) do
			local d = p.kind == "continent" and type(data) == "table" and data[p.id]
			if type(d) == "table" and d.instance == inst then
				v = p.id
				break
			end
		end
		entry.conts[inst] = v
	end
	return v or nil
end

local function Drop(icon)
	local layer = S.layerOf[icon]
	if layer then
		S.pins:Remove(layer, icon)
	end
	S.owner[icon], S.layerOf[icon] = nil, nil
end

-- (2.1.52; the user, 2026-11-14: "when clicking on a quest on the map to navigate to it, it does not draw a route to
-- it, nor does it navigate") Questie's givers and turn-ins stand where MelloUI's own did, whose click set Route's way
-- there, and Questie's own click does nothing off the game's map (QuestieFrame.lua's OnClick: only Shift, Ctrl with
-- TomTom, or a link into the chat line). A plain left click on one held here: Route's way to it through the Quest
-- List, as its giver pins did (QL.RouteToPoint, at Questie's own place of it), else the map's own pin there
-- (Map:PinOn). Questie's click runs first as before; one post-hook per frame, and a frame given back (S.owner) or
-- pooled into another kind is left to Questie
local clickHooked = setmetatable({}, { __mode = "k" })   -- [Questie's frame] = true: GiverClick hooked on it
local GIVER_MARK = { giver = "quest_mark", ender = "turnin_mark" }
local GIVER_WHAT = { giver = "quest giver", ender = "turn-in" }
local GiverClick = Perf.Shared("OnClick on Questie's givers on MelloUI's map", function(icon, button)
	if button ~= "LeftButton" or _G.IsModifierKeyDown() or not S.owner[icon] then
		return
	end
	local okC, chat = pcall(_G.ChatEdit_GetActiveWindow)
	if okC and chat then
		return   -- (Questie's own: the quest's link into the chat line)
	end
	local look = QuestieLook(icon)
	local cover = look and look.cover
	if not GIVER_MARK[cover] then
		return
	end
	local d = rawget(icon, "data")
	d = type(d) == "table" and d or nil
	local quest = d and type(d.QuestData) == "table" and d.QuestData or nil
	local title = quest and Text(quest.name) or ""
	local who = d and Text(d.Name) or ""
	local W = MelloUI.Widgets
	local mark = W.IconMarkup(GIVER_MARK[cover], 16) .. " "
	local label = mark .. title .. (who ~= "" and (" - " .. who) or "")
	local QL = rawget(MelloUI, "QuestList")
	local mapID, x, y = Finite(rawget(icon, "UiMapID")), Finite(rawget(icon, "x")), Finite(rawget(icon, "y"))
	if type(QL) == "table" and QL.RouteToPoint and mapID and x and y then
		local notice = mark .. string.format(W.Tr("Tracking %s %s for %s, {dist} away"), W.Tr(GIVER_WHAT[cover]), who,
			title)
		local set, chimed = QL.RouteToPoint(mapID, x / 100, y / 100, label, notice)
		if set and not chimed then
			MelloUI:PlayUISound("waypoint_set")
		end
		return
	end
	local Map = MelloUI.modules and MelloUI.modules.Map
	local layer = S.pins and S.pins.layers[S.layerOf[icon]]
	local pin = layer and layer.pins[icon]
	if type(Map) == "table" and Map.PinOn and pin then
		Map:PinOn(pin, label)
	end
end, "script")

-- one icon of the library's registry laid (or let go: no place here); `cover`: Questie's, what this map shows already
local function Place(entry, icon, t, cover)
	if type(icon) ~= "table" or type(t) ~= "table" or not icon.SetPoint then
		return
	end
	-- (a secure frame is never moved by MelloUI: hard rule 1)
	if icon.IsProtected and icon:IsProtected() then
		return
	end
	-- (2.1.4) Questie's: a quest this map shows already is not drawn twice; the rest in MelloUI's own look; (2.1.43) its
	-- townsfolk of a kind this map draws (its flight masters) not twice either
	-- (2.1.52, stage 2; the user, 2026-11-14: "with Questie Installed, the Quests are shown on the Map and Minimap from
	-- the QuestieDB database with its default look") Questie's switch on the Addons page off, its own look: its icons
	-- are hosted as Questie draws them (never restyled, its townsfolk all its own), and this map's two quest switches
	-- still decide them -- its givers and turn-ins on the Quest givers' layer, its objectives on Your quests'
	-- objectives' (each layer shown or hidden by its switch). MelloUI lays no quest marks of its own then (MapObjectives)
	local questie = entry.questie
	local dressed = questie and MelloUI.QuestieLook.Used()
	local look = questie and QuestieLook(icon) or nil
	local covered = false
	if dressed and look then
		covered = Covered(look, icon, cover) or false
	end
	-- (2.1.53) a town pin (Questie's townsfolk, another addon's) of a kind an owner before it has: not twice
	local town = not look and TownKind(entry, icon) or nil
	if town then
		local Town = ns.TownMarks
		if Town.Held(town, questie and "questie" or "other") then
			covered = true
		elseif questie and not Town.questie[town] then
			-- (Questie's townsfolk of this kind stand here now: the other addons' pins of it looked at again)
			Town.questie[town] = true
			AddonPins.Recheck(true)
		end
	end
	if questie then
		MelloUI.QuestieLook.Unlist(icon, covered)   -- (2.1.39: left out of Questie's tooltip too)
	end
	if covered then
		if S.owner[icon] then
			Drop(icon)
			Release(icon)
		end
		return
	end
	local c = S.canvas
	local target = Target(entry, t)
	local wx, wy
	if target then
		local ok, zx, zy = pcall(entry.hbd.GetZoneCoordinatesFromWorldInstance, entry.hbd, t.x, t.y, t.instanceID, target)
		if ok and Finite(zx) and Finite(zy) then
			wx, wy = c:ToWorld(target, zx, zy)
		end
	end
	if not wx then
		Drop(icon)
		return
	end
	local flag = Finite(t.worldMapShowFlag) or 0
	local kind = flag >= T.SHOW_WORLD and "world"
		-- (a pin on a continent's own map: there; one set by world yards placed through its continent: a zone's)
		or ((flag >= T.SHOW_CONTINENT or (t.uiMapID and c.byID[target].kind == "continent")) and "continent") or "zone"
	local layer = LAYER[kind]
	-- (2.1.51) Questie's givers, the givers: on the Quest givers switch's layer, from a zone's zoom on as MelloUI's own
	-- (Questie lays them with the world's flag, SHOW_WORLD: on every zoom else)
	if look and (look.cover == "giver" or look.cover == "ender") then
		layer = LAYER.questGivers
	elseif look and not dressed and look.cover == "objective" then
		layer = LAYER.questObjectives   -- (2.1.52: Questie's own look, its objectives under their switch)
	end
	if S.layerOf[icon] and S.layerOf[icon] ~= layer then
		Drop(icon)
	end
	local spec = S.specs[icon]
	if not spec then
		spec = { frame = icon, release = Release }
		S.specs[icon] = spec
	end
	S.pins:Set(layer, icon, wx, wy, spec)
	S.owner[icon], S.layerOf[icon] = entry, layer
	if look and GIVER_MARK[look.cover] and not clickHooked[icon] and icon.HookScript then
		clickHooked[icon] = true
		-- (2.1.52: a giver's or turn-in's click, Route's way there; 2.1.56: by the script the frame has, whatever
		-- Questie's version made it -- a button's click, else a plain frame's mouse-up)
		local script = (icon.HasScript and icon:HasScript("OnClick")) and "OnClick" or "OnMouseUp"
		Perf.HookScript(icon, script, GiverClick)
	end
	if look and dressed then
		Restyle(icon, look)
	elseif styled[icon] then
		Unstyle(icon)   -- (Questie's pooled frame now one of no look of ours)
	end
end

-- every icon of a library again (the map's open, or the library's remove-all)
local function Sync(entry)
	local reg = entry.pins.worldmapPins
	if type(reg) ~= "table" then
		return
	end
	local cover = entry.questie and Cover() or nil
	for icon, t in pairs(reg) do
		Place(entry, icon, t, cover)
	end
	for icon, e in pairs(S.owner) do
		if e == entry and not reg[icon] then
			Drop(icon)
		end
	end
	entry.full = false
end

local function Changed(entry, icon)
	if S.shown then
		S.queue[icon] = entry
		S.queued = true
	else
		entry.full = true
	end
end

-- the library's adds and removes followed: post-hooks on its own table, never a Blizzard one; again for a method a
-- newer copy of the library (loaded by another addon later) defined anew
local HOOKED = { "AddWorldMapIconMap", "AddWorldMapIconWorld", "RemoveWorldMapIcon", "RemoveAllWorldMapIcons" }
local function Hook(entry)
	local lib = entry.pins
	for _, fn in ipairs(HOOKED) do
		local now = lib[fn]
		if type(now) == "function" and entry.hooked[fn] ~= now then
			hooksecurefunc(lib, fn, fn == "RemoveAllWorldMapIcons" and entry.onAll or entry.onOne)
			entry.hooked[fn] = lib[fn]
		end
	end
end

-- the libraries the addons loaded (looked for at each open: a load-on-demand addon may bring one later)
local function FindLibs()
	local LibStub = rawget(_G, "LibStub")
	if type(LibStub) ~= "table" and type(LibStub) ~= "function" then
		return
	end
	for _, names in ipairs(T.HBD) do
		local lib, hbd
		local QLook = MelloUI.QuestieLook
		if names.questie and QLook and QLook.PinsLib then
			-- (2.1.52) Questie's own copy: a LibStub library until Questie 12.9, a module of its loader since
			lib, hbd = QLook.PinsLib()
		else
			local okP, okH
			okP, lib = pcall(LibStub, names.pins, true)
			okH, hbd = pcall(LibStub, names.hbd, true)
			lib, hbd = okP and lib or nil, okH and hbd or nil
		end
		if type(lib) == "table" and type(hbd) == "table" and not S.byLib[lib]
			and type(lib.worldmapPins) == "table" and type(hbd.GetZoneCoordinatesFromWorldInstance) == "function" then
			local entry = { pins = lib, hbd = hbd, maps = {}, conts = {}, full = true, hooked = {},
				questie = names.questie == true }
			entry.onOne = function(_, _, icon)
				Changed(entry, icon)
			end
			entry.onAll = function()
				entry.full = true
				S.queued = true
			end
			S.byLib[lib] = entry
			S.libs[#S.libs + 1] = entry
		end
	end
	for _, entry in ipairs(S.libs) do
		Hook(entry)
	end
end

local function Queue()
	S.queued = false
	for _, entry in ipairs(S.libs) do
		if entry.full then
			Sync(entry)
		end
	end
	local cover
	for icon, entry in pairs(S.queue) do
		local t = entry.pins.worldmapPins[icon]
		if t then
			if entry.questie and not cover then
				cover = Cover() or false
			end
			Place(entry, icon, t, entry.questie and cover or nil)
		else
			Drop(icon)
		end
	end
	wipe(S.queue)
end

--------------------------------------------------------------------------------
-- HandyNotes and GatherMate2: their nodes, per zone in view
--------------------------------------------------------------------------------

local function Ace(name)
	local LibStub = rawget(_G, "LibStub")
	local okA, ace = pcall(LibStub, "AceAddon-3.0", true)
	if not (okA and type(ace) == "table") then
		return nil
	end
	local ok, addon = pcall(ace.GetAddon, ace, name, true)
	return ok and type(addon) == "table" and addon or nil
end
AddonPins.Ace = Ace   -- (MapTownMarks)

-- a node's own picture cut from a sheet (HandyNotes' iconpath tables)
local function CutLook(tex, pin)
	local tc = pin.spec.tc
	tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
end

-- (HandyNotes) its plugins' own tooltip and clicks, on a frame laid on the pin (Map.lua's PinAnchor)
local function NodeArgs(anchor, pin)
	local d = pin.spec.data
	anchor.pluginName, anchor.coord, anchor.uiMapID = d[1], d[3], d[2]
	local hn = Ace("HandyNotes")
	local handler = hn and hn.plugins and hn.plugins[d[1]]
	return handler, d[2], d[3]
end

local function NodeEnter(pin, anchor)
	local handler, mapID, coord = NodeArgs(anchor, pin)
	if handler and type(handler.OnEnter) == "function" then
		pcall(handler.OnEnter, anchor, mapID, coord)
	end
end

local function NodeLeave(pin, anchor)
	local handler, mapID, coord = NodeArgs(anchor, pin)
	if handler and type(handler.OnLeave) == "function" then
		pcall(handler.OnLeave, anchor, mapID, coord)
	end
end

local function NodeClick(pin, button, anchor)
	local handler, mapID, coord = NodeArgs(anchor, pin)
	if handler and type(handler.OnClick) == "function" then
		pcall(handler.OnClick, anchor, button, true, mapID, coord)
		pcall(handler.OnClick, anchor, button, false, mapID, coord)
	end
end
-- (2.1.53, MapTownMarks: a town mark's tooltip and click are its plugin's too; data = { plugin, map, coord })
AddonPins.NODE = { enter = NodeEnter, leave = NodeLeave, click = NodeClick }

-- (GatherMate2) the node's name in its tracking colour, as its own tooltip has it
local function GatherTip(tooltip, pin)
	local d = pin.spec.data
	local c = d[2]
	if type(c) == "table" then
		tooltip:SetText(d[1], Finite(c.Red) or 1, Finite(c.Green) or 1, Finite(c.Blue) or 1)
	else
		tooltip:SetText(d[1])
	end
end

local Sources = {}

-- (2.1.57; the user, 2026-11-17: "Conflict between RareScanner and Handy Notes, Both show rare locations") ONE owner a
-- kind of place across the addons (MapTownMarks' rule): a rare creature's place is RareScanner's while it shows them
-- (Core/RareScannerLook.lua's RL.Rares), and another addon's mark of one is not drawn too. A HandyNotes node is known
-- for a rare by what its own plugin keeps of it: the zone's node table its GetNodes2 hands out as the iterator's
-- state ([coord] = the node), the node naming its creature (RARE_FIELDS: `npc`, the treasures-and-rares plugins'
-- field for a creature to find -- HandyNotes: WoW Forever is one). Never by the plugin's name, and never by its
-- picture (an item's icon with the plugin's own option on). A plugin that keeps no such table, a node without the
-- field (its treasures): drawn as before
local RARE_FIELDS = { "npc" }
local function Field(t, key)
	return t[key]
end
local function RareNode(state, coord)
	if type(state) ~= "table" or coord == nil then
		return false
	end
	local ok, node = pcall(Field, state, coord)
	if not (ok and type(node) == "table") then
		return false
	end
	for _, field in ipairs(RARE_FIELDS) do
		local okF, v = pcall(Field, node, field)
		if okF and type(v) == "number" then
			return true
		end
	end
	return false
end
AddonPins.RareNode = RareNode

-- HandyNotes: every enabled plugin's nodes of the zone (GetNodes2: their own map, 0..1 there)
-- (2.1.44) an addon's nodes only while its switch on the Addons page, Use with MelloUI, is on (Core/Integrations.lua)
local function Used(key)
	local I = rawget(MelloUI, "Integrations")
	return not (I and not I.Use(key))
end

Sources[1] = function(id, add)
	local hn = Used("HandyNotes") and Ace("HandyNotes")
	if not (hn and type(hn.plugins) == "table" and hn.db and hn.db.profile) then
		return
	end
	local okE, on = pcall(hn.IsEnabled, hn)
	if okE and not on then
		return
	end
	local db = hn.db.profile
	local enabled = type(db.enabledPlugins) == "table" and db.enabledPlugins or {}
	local scale, alpha = Finite(db.icon_scale) or 1, Finite(db.icon_alpha) or 1
	-- (2.1.53) the town marks' plugin in MelloUI's look: its places are MapTownMarks' (their own layer and switches),
	-- never drawn here too; and another plugin's node of a town kind an owner before it has: not twice (Town.Held)
	local Town = ns.TownMarks
	local mine = Town and Town.Used() and Town.T.PLUGIN or nil
	-- (2.1.57) the rares RareScanner's while it shows them: a plugin's rare nodes not drawn too (RareNode); while it
	-- does not, a plugin's rare wears MelloUI's rare seal, RareScanner's look (RL.PlainSeal) -- the plugin's own
	-- tooltip, clicks and fade kept, its picture and size not: one kind, one look
	local RL = MelloUI.RareScannerLook
	local rares = RL and RL.Rares and RL.Rares() or false
	local seal = RL and not rares and RL.PlainSeal or nil
	for name, handler in pairs(hn.plugins) do
		if name ~= mine and enabled[name] and type(handler) == "table" and type(handler.GetNodes2) == "function" then
			local ok, iter, state, value = pcall(handler.GetNodes2, handler, id, false)
			if ok and type(iter) == "function" then
				local guard = 0
				while guard < 5000 do
					local okN, coord, map2, icon, s, a = pcall(iter, state, value)
					if not okN or coord == nil then
						break
					end
					value, guard = coord, guard + 1
					coord = Finite(coord)
					local rare = coord and RareNode(state, value)
					if coord and not (rare and rares) then
						local x, y = floor(coord / 10000) / 10000, (coord % 10000) / 10000
						local fade = min(max(alpha * (Finite(a) or 1), 0), 1)
						local spec
						if rare and seal then
							spec = seal("rare")
							spec.alpha = fade < 1 and fade or spec.alpha
						else
							spec = { size = T.NODE * scale * (Finite(s) or 1), alpha = fade }
							if type(icon) == "table" then
								spec.icon = icon.icon
								if icon.tCoordLeft then
									spec.tc = { icon.tCoordLeft, icon.tCoordRight, icon.tCoordTop, icon.tCoordBottom }
									spec.look = CutLook
								end
								if icon.r then
									spec.rgb = { icon.r, icon.g, icon.b }
								end
							else
								spec.icon = icon
							end
						end
						spec.enter, spec.leave, spec.click, spec.right = NodeEnter, NodeLeave, NodeClick, true
						spec.data = { name, map2 or id, coord }
						if (rare and seal) or not (Town and Town.Held(Town.KindOfPicture(spec.icon), "other")) then
							add("hn:" .. name .. ":" .. (map2 or id) .. ":" .. coord, map2 or id, x, y, spec)
						end
					end
				end
			end
		end
	end
end

-- (2.1.61; the user, 2026-11-20: "we have stated that we have compatibility, but we didnt make new icons for the
-- resources", then the pick "One per kind") GatherMate2's nodes in MelloUI's icons, one a kind of node: a herb, a vein,
-- a fishing pool, a treasure. GatherMate2 stays the engine (its nodes, its filters, its scale and alpha, its tracking
-- circle on the minimap); the picture is MelloUI's while the look in use has one for the kind -- the icon set's, the
-- Oldschool set's, the Default look's game picture (Core/Skin.lua) -- and GatherMate2's own for a kind with none (gas,
-- archaeology, logging). Bare, with the map's shade, as the rares (the user: "a bit too thich ... just leave the
-- Skull icons"). The minimap wears what the big map wears: its own minimap pins get the same picture while MelloUI's
-- map is on, laid over its own (its texture's alpha only; given back when it draws its tracking circle or the look
-- goes). Nothing of GatherMate2's is written but that alpha.
-- (2.1.72; the user, 2026-11-22: "copper for copper, iron etc ... also for every herb kind") one icon a resource: each
-- vein and herb GatherMate2 marks in Forever's world by its own node id (its Constants.lua) -> MelloUI's icon for that
-- metal or herb; the variants of a metal (ooze covered, small, rich, heavy) share its icon. A node with none, or whose
-- picture the look in use lacks, wears its kind's icon (ICON), else GatherMate2's own picture.
local Gather = {
	ICON = { ["Herb Gathering"] = "gather_herb", ["Mining"] = "gather_ore", ["Fishing"] = "gather_fish",
		["Treasure"] = "ql_chest" },
	NODE = {
		["Mining"] = {
			[201] = "ore_copper", [202] = "ore_tin", [203] = "ore_iron", [204] = "ore_silver", [205] = "ore_gold",
			[206] = "ore_mithril", [207] = "ore_mithril", [208] = "ore_truesilver", [209] = "ore_silver",
			[210] = "ore_gold", [211] = "ore_truesilver", [212] = "ore_thorium", [213] = "ore_thorium",
			[214] = "ore_thorium", [215] = "ore_thorium", [216] = "ore_thorium", [217] = "ore_darkiron",
			[218] = "ore_bloodstone", [219] = "ore_incendicite", [220] = "ore_indurium", [4201] = "ore_thorium",
		},
		["Herb Gathering"] = {
			[401] = "herb_peacebloom", [402] = "herb_silverleaf", [403] = "herb_earthroot", [404] = "herb_mageroyal",
			[405] = "herb_briarthorn", [407] = "herb_stranglekelp", [408] = "herb_bruiseweed",
			[409] = "herb_steelbloom", [410] = "herb_gravemoss", [411] = "herb_kingsblood", [412] = "herb_liferoot",
			[413] = "herb_fadeleaf", [414] = "herb_goldthorn", [415] = "herb_khadgarswhisker",
			[416] = "herb_wintersbite", [417] = "herb_firebloom", [418] = "herb_purplelotus",
			[420] = "herb_arthastears", [421] = "herb_sungrass", [422] = "herb_blindweed",
			[423] = "herb_ghostmushroom", [424] = "herb_gromsblood", [425] = "herb_goldensansam",
			[426] = "herb_dreamfoil", [427] = "herb_silversage", [428] = "herb_plaguebloom", [429] = "herb_icecap",
			[430] = "herb_bloodvine", [431] = "herb_blacklotus", [4401] = "herb_demonsage",
		},
	},
	FRESH = 1,   -- s the answers below are kept (asked for every minimap pin at every update of GatherMate2's)
	has = {}, dressed = setmetatable({}, { __mode = "k" }),
}
AddonPins.Gather = Gather

-- what was asked in the last second is answered from memory: the look on, and each kind's icon
local function GatherFresh()
	local now = GetTime()
	if not Gather.at or now - Gather.at >= Gather.FRESH or now < Gather.at then
		Gather.at = now
		wipe(Gather.has)
		local ok, on = pcall(MelloUI.IsModuleEnabled, MelloUI, "Map")
		Gather.look = (ok and on and Used("GatherMate2")) and true or false
	end
end

-- a name in the set while the look in use has that picture, else nil
local function Drawn(name)
	if not name then
		return nil
	end
	-- (the Default look draws the game's own art: only what it has a game picture for, Core/Skin.lua -- else
	-- GatherMate2's own pictures stay there, which are the game's item icons already)
	local Icons, Skin = MelloUI.Icons, rawget(MelloUI, "Skin")
	local drawn
	if type(Skin) == "table" and type(Skin.IsDefault) == "function" and Skin.IsDefault() then
		drawn = type(Skin.Icon) == "function" and Skin.Icon(name) ~= nil
	else
		drawn = type(Icons) == "table" and type(Icons.Has) == "function" and Icons.Has(ICONS .. name)
	end
	return drawn and name or nil
end

-- MelloUI's icon for a node -- its name in the set: its resource's (2.1.72, `nodeID` given), else its kind's -- while
-- the look in use has that picture, else nil
function Gather.Icon(kind, nodeID)
	GatherFresh()
	if kind == nil then
		return nil
	end
	local id = type(nodeID) == "number" and nodeID or nil
	local key = id and (tostring(kind) .. ":" .. id) or kind
	local known = Gather.has[key]
	if known ~= nil then
		return known or nil
	end
	local name
	if id then
		local list = type(kind) == "string" and Gather.NODE[kind]
		name = Drawn(type(list) == "table" and list[id] or nil) or Gather.Icon(kind)
	else
		name = Drawn(type(kind) == "string" and Gather.ICON[kind] or nil)
	end
	Gather.has[key] = name or false
	return name
end

-- (GatherMate2's Display:addMiniPin, after it: a minimap pin of its own laid or moved) its picture covered by
-- MelloUI's for its resource or kind (2.1.72); its own again while it shows its tracking circle (pin.isCircle), for a
-- node with no icon, or with MelloUI's map off. Runs for every pin at each of its updates: nothing is set that already stands.
local GatherMini = Perf.Shared("GatherMate2's minimap pin laid (MelloUI's icon over its own)", function(_, pin)
	if type(pin) ~= "table" then
		return
	end
	GatherFresh()
	local d = Gather.dressed[pin]
	local name = (Gather.look and not rawget(pin, "isCircle")) and Gather.Icon(rawget(pin, "nodeType"), rawget(pin, "nodeID")) or nil
	local own = rawget(pin, "texture")
	if not name then
		if d and d.on then
			d.on = false
			d.tex:Hide()
			if type(own) == "table" and own.SetAlpha then
				own:SetAlpha(1)
			end
		end
		return
	end
	if not d then
		d = { tex = pin:CreateTexture(nil, "OVERLAY", nil, 7) }
		d.tex:SetAllPoints(pin)
		Gather.dressed[pin] = d
	end
	if d.name ~= name or not d.on then
		d.name, d.on = name, true
		MelloUI.Icons.Set(d.tex, ICONS .. name, Finite(pin:GetWidth()) or T.NODE)
		d.tex:Show()
	end
	if type(own) == "table" and own.GetAlpha and own:GetAlpha() ~= 0 then
		own:SetAlpha(0)   -- (it drew its picture anew: once a change of its, never a frame)
	end
end)
Gather.Mini = GatherMini

-- GatherMate2: the zone's nodes of each kind it shows (its own filters), in MelloUI's icon for the resource or the
-- kind (Gather)
Sources[2] = function(id, add)
	local gm = Used("GatherMate2") and Ace("GatherMate2")
	if not (gm and gm.db and gm.db.profile and type(gm.db_types) == "table" and type(gm.GetNodesForZone) == "function") then
		return
	end
	local db = gm.db.profile
	if db.showWorldMap == false then
		return
	end
	local dataID = type(gm.phasing) == "table" and gm.phasing[id] or id
	local textures, visible = gm.nodeTextures, gm.Visible
	local replace = type(gm.nodeIDReplacementMap) == "table" and gm.nodeIDReplacementMap or {}
	local colors = type(db.trackColors) == "table" and db.trackColors or {}
	local size, alpha = T.NODE * (Finite(db.scale) or 1), Finite(db.alpha) or 1
	for _, kind in pairs(gm.db_types) do
		if type(visible) ~= "table" or visible[kind] then
			local ok, iter, state, value = pcall(gm.GetNodesForZone, gm, dataID, kind)
			local pics = type(textures) == "table" and textures[kind]
			if ok and type(iter) == "function" then
				local guard = 0
				while guard < 20000 do
					local okN, coord, nodeID = pcall(iter, state, value)
					if not okN or coord == nil then
						break
					end
					value, guard = coord, guard + 1
					nodeID = replace[nodeID] or nodeID
					-- (2.1.72: MelloUI's icon for its resource, else for its kind, else its own picture)
					local mine = Gather.Icon(kind, nodeID)
					local okL, x, y = pcall(gm.DecodeLoc, gm, coord)
					local okT, title = pcall(gm.GetNameForNode, gm, kind, nodeID)
					if okL and Finite(x) and Finite(y) then
						add("gm:" .. kind .. ":" .. id .. ":" .. coord, id, x, y, {
							icon = mine and (ICONS .. mine) or (pics and pics[nodeID]), lift = mine or nil,
							size = size, alpha = alpha, fillTip = GatherTip,
							data = { okT and Text(title) or kind, colors[kind] },
						})
					end
				end
			end
		end
	end
end

-- (2.1.43; the user: "Rarescanner is the engine, we provide the look"; the pick B of rarescanner_sketch) RareScanner:
-- what it would lay on the game's map for the zone (its own provider, hosted: Core/RareScannerLook.lua) -- its rares,
-- treasures and events, its filters -- as MelloUI's seals (MelloUI's icon on a plate, the rim its state); the tooltip
-- MelloUI's (the name, its kind and state), a click your pin there (Route's way)
local function RareTip(tooltip, pin)
	local RL = MelloUI.RareScannerLook
	local P = MelloUI.Look and MelloUI.Look.TipPalette and MelloUI.Look.TipPalette() or MelloUI.Palette
	local title, what, names = RL.Lines(pin.spec.data)
	local g, t, m = P.selectedTrim, P.text, P.mutedText
	tooltip:SetText(title, g[1], g[2], g[3])
	tooltip:AddLine(what, t[1], t[2], t[3])
	if names then
		tooltip:AddLine(names, t[1], t[2], t[3], true)
	end
	tooltip:AddLine(MelloUI.Widgets.Tr(RL.TEXT.by), m[1], m[2], m[3])
end
local function RareClick(pin)
	local Map = MelloUI.modules and MelloUI.modules.Map
	if type(Map) == "table" and Map.PinOn then
		Map:PinOn(pin, (MelloUI.RareScannerLook.Lines(pin.spec.data)))
	end
end
Sources[3] = function(id, add)
	local RL = MelloUI.RareScannerLook
	if not (RL and RL.On()) then
		return
	end
	for i, POI in ipairs(RL.POIs(id) or {}) do
		local x, y = Finite(POI.x), Finite(POI.y)
		if x and y then
			local spec = RL.Seal(POI)
			spec.fillTip, spec.click, spec.data = RareTip, RareClick, POI
			add("rs:" .. id .. ":" .. tostring(POI.entityID or i) .. ":" .. x .. ":" .. y, Finite(POI.mapID) or id, x, y, spec)
		end
	end
end
local building, buildingTown   -- the zone being built (its pins' keys: the other addons' nodes, the town marks)
local function AddNode(key, mapID, x, y, spec)
	if spec.icon or spec.atlas then
		local pin = S.pins:SetAt(LAYER.zone, key, mapID, x, y, spec)
		if pin then
			building[#building + 1] = key
		end
	end
end
local function AddTown(key, mapID, x, y, spec)
	if S.pins:SetAt(LAYER.town, key, mapID, x, y, spec) then
		buildingTown[#buildingTown + 1] = key
	end
end

local function DropZone(id)
	local z = S.zones[id]
	if not z then
		return
	end
	for _, key in ipairs(z.keys) do
		S.pins:Remove(LAYER.zone, key)
	end
	for _, key in ipairs(z.town) do
		S.pins:Remove(LAYER.town, key)
	end
	S.zones[id] = nil
	S.zoneCount = S.zoneCount - 1
end

local function DropZones()
	for id in pairs(S.zones) do
		DropZone(id)
	end
	S.cut = nil
end

-- (2.1.53) the other addons' nodes only while their layer is on (its switch off, and the map open for Questie's
-- givers or the town marks: none built for a layer nobody sees -- Map.lua's SetLayer builds the zones again as the
-- switch turns); the town marks by their own switches (MapTownMarks)
local function BuildZone(id)
	building, buildingTown = {}, {}
	if S.pins.layers[LAYER.zone].on then
		for _, source in ipairs(Sources) do
			source(id, AddNode)
		end
	end
	local Town = ns.TownMarks
	if Town then
		Town.Zone(id, AddTown)
	end
	S.zones[id] = { keys = building, town = buildingTown, gen = S.zoneGen }
	S.zoneCount = S.zoneCount + 1
	building, buildingTown = nil, nil
end

-- the zones in view at a zone's zoom built (a few a frame), the farthest seen last let go past KEEP
local function Zones()
	local c = S.canvas
	S.cut = c.cuts
	local RL = MelloUI.RareScannerLook
	if c.z < T.ZONE_FROM or not (Ace("HandyNotes") or Ace("GatherMate2") or (RL and RL.On())) then
		return
	end
	local box = c.box
	S.zoneGen = S.zoneGen + 1
	local gen, built, pending = S.zoneGen, 0, false
	for _, p in ipairs(c.places or {}) do
		if (p.kind == "zone" or p.kind == "city") and p.left < box[3] and p.left + p.w > box[1]
			and p.top < box[4] and p.top + p.h > box[2] then
			local z = S.zones[p.id]
			if z then
				z.gen = gen
			elseif built < T.BUILD_PER_FRAME then
				BuildZone(p.id)
				S.zones[p.id].gen = gen
				built = built + 1
			else
				pending = true
			end
		end
	end
	while S.zoneCount > T.KEEP do
		local oldest, at
		for id, z in pairs(S.zones) do
			if z.gen < gen and (not at or z.gen < at) then
				oldest, at = id, z.gen
			end
		end
		if not oldest then
			break
		end
		DropZone(oldest)
	end
	-- (more to build: again next frame)
	if pending then
		S.cut = nil
	end
	if built > 0 then
		S.pins:Lay()
	end
end

-- HandyNotes or GatherMate2 drew their pins again (on the game's map): ours again while the map shows
local function Redrawn()
	S.stale = true
end

local hookedSources = {}
local function HookSources()
	local hn = Ace("HandyNotes")
	if hn and not hookedSources[hn] then
		hookedSources[hn] = true
		for _, fn in ipairs({ "UpdateWorldMap", "UpdateWorldMapPlugin" }) do
			if type(hn[fn]) == "function" then
				hooksecurefunc(hn, fn, Redrawn)
			end
		end
	end
	local gm = Ace("GatherMate2")
	local okD, display = false, nil
	if gm and type(gm.GetModule) == "function" then
		okD, display = pcall(gm.GetModule, gm, "Display", true)
	end
	if okD and type(display) == "table" and not hookedSources[display] and type(display.UpdateWorldMap) == "function" then
		hookedSources[display] = true
		hooksecurefunc(display, "UpdateWorldMap", Redrawn)
		-- (2.1.61) its minimap pins in MelloUI's icons (Gather.Mini)
		if type(display.addMiniPin) == "function" then
			hooksecurefunc(display, "addMiniPin", Gather.Mini)
		end
	end
end

--------------------------------------------------------------------------------
-- The minimap: another addon's rares there -- off while RareScanner's stand, in MelloUI's seal otherwise
--------------------------------------------------------------------------------

-- (2.1.57) the minimap wears what the map wears. HandyNotes lays a plugin's minimap icons itself (its
-- UpdateMinimapPlugin: frames of its own on HereBeDragons, each keeping its coord, from the plugin's nodes of your
-- zone). Right after it has, the icons of rare nodes (RareNode, by the same node table) are taken off HereBeDragons
-- again -- HandyNotes keeps the frames and takes them back at its next update, as with the town marks' plugin
-- (MapTownMarks' OwnOff) -- and what stands there instead goes by who draws the rares (Mode):
--   "owned"    RareScanner shows its own rares on the minimap (RL.MiniRares): nothing of the plugin's
--   "dressed"  it does not: a mark of MelloUI's own in the rare seal (RL.MiniSeal) at the plugin's place, on Route's
--              minimap layer (as the town marks), the plugin's own tooltip on it; the minimap keeps its clicks
--   nil        the map off, HandyNotes not used with MelloUI, or no Route: HandyNotes' own stand as it lays them
-- Nothing of HandyNotes' or the plugin's is written. A plugin's minimap icons are its own option (HandyNotes: WoW
-- Forever's is off as it comes), so most players see none of this
do
	local OWNER = "Map rares of other addons"   -- on Route's minimap layer
	local mini = { want = false, hooked = false, drawn = false, by = {}, marks = {}, n = 0 }

	local function Lib(name, method)
		local LibStub = rawget(_G, "LibStub")
		local ok, lib = pcall(LibStub, name, true)
		return ok and type(lib) == "table" and type(lib[method]) == "function" and lib or nil
	end

	local function RouteLayer()
		local R = MelloUI.Route
		return type(R) == "table" and type(R.WantMinimap) == "function" and type(R.ToYards) == "function"
			and type(R.MinimapFrame) == "function" and type(R.MinimapOffset) == "function"
			and type(R.MarkPlace) == "function" and R or nil
	end

	local function Mode()
		local RL = MelloUI.RareScannerLook
		if not (mini.want and RL and Used("HandyNotes")) then
			return nil
		end
		if RL.MiniRares and RL.MiniRares() then
			return "owned"
		end
		return RL.MiniSeal and RouteLayer() and "dressed" or nil
	end

	-- a mark's tooltip: its plugin's own, as on the map
	local function Handler(f)
		local hn = Ace("HandyNotes")
		local handler = hn and type(hn.plugins) == "table" and hn.plugins[f.plugin]
		return type(handler) == "table" and handler or nil
	end

	local function Enter(f)
		local handler = Handler(f)
		if handler and type(handler.OnEnter) == "function" then
			f.over = true
			pcall(handler.OnEnter, f, f.mapID, f.coord)
		end
	end

	local function Leave(f)
		if not f.over then
			return
		end
		f.over = nil
		local handler = Handler(f)
		if handler and type(handler.OnLeave) == "function" then
			pcall(handler.OnLeave, f, f.mapID, f.coord)
		end
		if GameTooltip:GetOwner() == f then
			GameTooltip:Hide()
		end
	end

	-- a mark (made the first time it is needed): the seal, the mouse's motion only
	local function Mark(i, frame)
		local f = mini.marks[i]
		if not f then
			f = CreateFrame("Frame", nil, frame)
			f:SetFrameLevel(frame:GetFrameLevel() + 1)   -- (under the quest marks, as the town marks)
			MelloUI.RareScannerLook.MiniSeal(f, "rare")
			if f.SetMouseClickEnabled then
				f:EnableMouse(true)
				f:SetMouseClickEnabled(false)
				f:SetScript("OnEnter", Enter)
				f:SetScript("OnLeave", Leave)
				f:SetScript("OnHide", Leave)
			end
			mini.marks[i] = f
		end
		return f
	end

	-- Route's minimap layer's tick (cont nil: hidden)
	local function Draw(cont, round, R, RX, RY)
		local Route = MelloUI.Route
		local frame = Route.MinimapFrame()
		local n = 0
		if cont and frame then
			local Offset, size = Route.MinimapOffset, MelloUI.RareScannerLook.T.MINI
			local m = size / 2
			for _, list in pairs(mini.by) do
				for _, p in ipairs(list) do
					if p.cont == cont then
						local gx, gy = Offset(p.x, p.y)
						local on
						if round then
							on = gx * gx + gy * gy <= (R - m) * (R - m)
						else
							on = math.abs(gx) <= RX - m and math.abs(gy) <= RY - m
						end
						if on then
							n = n + 1
							local f = Mark(n, frame)
							f.plugin, f.mapID, f.coord = p.plugin, p.mapID, p.coord
							Route.MarkPlace(f, size, frame, "CENTER", gx, gy)
						end
					end
				end
			end
		end
		for i = n + 1, mini.n do
			mini.marks[i]:Hide()
		end
		mini.n = n
	end

	-- the layer asked for exactly while a plugin has rares to show
	local function Want()
		local any = next(mini.by) ~= nil
		if any == mini.drawn then
			return
		end
		mini.drawn = any
		local R = RouteLayer()
		if R then
			R.WantMinimap(OWNER, any and Draw or nil)
		end
		if not any then
			for i = 1, mini.n do
				mini.marks[i]:Hide()
			end
			mini.n = 0
		end
	end

	-- a plugin's rare icons HandyNotes just laid: off HereBeDragons, and (dressed) their places for MelloUI's marks
	local function Take(name, mode)
		local hn = Ace("HandyNotes")
		local handler = hn and type(hn.plugins) == "table" and hn.plugins[name]
		local pins = Lib("HereBeDragons-Pins-2.0", "RemoveMinimapIcon")
		local hbd = Lib("HereBeDragons-2.0", "GetPlayerZone")
		local ref = "HandyNotes" .. tostring(name)
		local laid = pins and type(pins.minimapPinRegistry) == "table" and pins.minimapPinRegistry[ref]
		if not (mode and hbd and type(laid) == "table" and next(laid) ~= nil and type(handler) == "table"
			and type(handler.GetNodes2) == "function") then
			return nil
		end
		-- the node table HandyNotes itself just went through: the plugin's, of your zone, for the minimap
		local okZ, zone = pcall(hbd.GetPlayerZone, hbd)
		zone = okZ and Finite(zone) or nil
		if not zone then
			return nil
		end
		local okN, _, state = pcall(handler.GetNodes2, handler, zone, true)
		if not (okN and type(state) == "table") then
			return nil
		end
		local gone
		for icon in pairs(laid) do
			if type(icon) == "table" and RareNode(state, icon.coord) then
				gone = gone or {}
				gone[#gone + 1] = icon
			end
		end
		local R = mode == "dressed" and RouteLayer() or nil
		local list
		for _, icon in ipairs(gone or {}) do
			pcall(pins.RemoveMinimapIcon, pins, ref, icon)
			local c = R and Finite(icon.coord)
			if c then
				local okY, cont, x, y = pcall(R.ToYards, zone, floor(c / 10000) / 10000, (c % 10000) / 10000)
				if okY and cont and x and y then
					list = list or {}
					list[#list + 1] = { cont = cont, x = x, y = y, mapID = zone, coord = c, plugin = name }
				end
			end
		end
		return list
	end

	local function Sort(name)
		mini.by[name] = Take(name, Mode())
		Want()
	end

	local Laid = Perf.Shared("HandyNotes' UpdateMinimapPlugin, for the rares", function(_, name)
		Sort(name)
	end, "hook")

	-- (Map.lua: its OnEnable and OnDisable) the map on or off: on, the hook (once) and the icons laid before it;
	-- off, MelloUI's marks gone and HandyNotes lays its own again
	function AddonPins.MiniRares(enabled)
		local was = mini.want
		mini.want = enabled and true or false
		local hn = Ace("HandyNotes")
		if not hn then
			return
		end
		if mini.want then
			if not mini.hooked and type(hn.UpdateMinimapPlugin) == "function" then
				mini.hooked = true
				hooksecurefunc(hn, "UpdateMinimapPlugin", Laid)
			end
			if type(hn.plugins) == "table" then
				for name in pairs(hn.plugins) do
					Sort(name)
				end
			end
		else
			wipe(mini.by)
			Want()
			if was and type(hn.UpdateMinimap) == "function" then
				pcall(hn.UpdateMinimap, hn)
			end
		end
	end
	AddonPins.mini = mini   -- (the tests)
end

--------------------------------------------------------------------------------
-- The API: other addons' own pins (MelloUI.Map)
--------------------------------------------------------------------------------

local SHOW = { zone = "zone", continent = "continent", world = "world" }

local function ApiTip(pin)
	local d = pin.spec.data
	local tip = d.tip
	if type(tip) == "function" then
		local ok, title, body = pcall(tip, d.key)
		if ok then
			return Text(title), Text(body)
		end
		return nil
	end
	return Text(tip)
end

local function ApiClick(pin, button)
	local d = pin.spec.data
	pcall(d.click, d.key, button)
end

local function ApiLay(e)
	if not (S.pins and S.apiLaid) then
		return
	end
	S.pins:SetAt(e.layer, e.pinKey, e.mapID, e.x, e.y, e.spec)
	S.pins.dirty = true
end

local API = {}
MelloUI.Map = API

function API:AddPin(owner, key, uiMapID, x, y, spec)
	uiMapID, x, y = Finite(uiMapID), Finite(x), Finite(y)
	if owner == nil or key == nil or not (uiMapID and x and y) or type(spec) ~= "table" then
		return false
	end
	if S.apiLaid and not S.canvas.byID[uiMapID] then
		return false
	end
	local list = S.api[owner]
	if not list then
		list = {}
		S.api[owner] = list
	end
	local old = list[key]
	local layer = LAYER[SHOW[spec.show] or "zone"]
	if old and S.pins and old.layer ~= layer then
		S.pins:Remove(old.layer, old.pinKey)
	end
	local e = old or { pinKey = {} }   -- (its pin's key a table of its own: never the same as another owner's)
	e.layer, e.mapID, e.x, e.y = layer, uiMapID, x, y
	e.spec = {
		icon = spec.icon, atlas = spec.atlas, size = Finite(spec.size) or T.SIZE, rgb = spec.rgb, alpha = Finite(spec.alpha),
		tip = spec.tip ~= nil and ApiTip or nil, click = type(spec.click) == "function" and ApiClick or nil,
		data = { key = key, tip = spec.tip, click = spec.click },
	}
	if not old then
		S.apiCount = S.apiCount + 1
	end
	list[key] = e
	ApiLay(e)
	return true
end

function API:ClearPin(owner, key)
	local list = S.api[owner]
	local e = list and list[key]
	if not e then
		return
	end
	if S.pins then
		S.pins:Remove(e.layer, e.pinKey)
	end
	list[key] = nil
	S.apiCount = S.apiCount - 1
	if not next(list) then
		S.api[owner] = nil
	end
end

function API:ClearPins(owner)
	local list = S.api[owner]
	if not list then
		return
	end
	for key in pairs(list) do
		self:ClearPin(owner, key)
	end
end

function API:OnViewChanged(owner, fn)
	if owner == nil then
		return
	end
	S.views[owner] = type(fn) == "function" and fn or nil
end

function API:IsShown()
	return S.shown
end

function API:Show(uiMapID)
	return S.shownFn ~= nil and S.shownFn(Finite(uiMapID)) or false
end

--------------------------------------------------------------------------------
-- The window's
--------------------------------------------------------------------------------

function AddonPins.Shown(fn)
	S.shownFn = fn
end

function AddonPins.Init(canvas, pins)
	S.canvas, S.pins = canvas, pins
	local zone = pins:Layer(LAYER.zone, T.ORDER.zone, { minZ = T.ZONE_FROM })
	local cont = pins:Layer(LAYER.continent, T.ORDER.continent, { minZ = T.CONTINENT_FROM })
	local world = pins:Layer(LAYER.world, T.ORDER.world)
	local givers = pins:Layer(LAYER.questGivers, T.ORDER.zone, { minZ = T.ZONE_FROM })   -- (2.1.51: as the zone's)
	local objectives = pins:Layer(LAYER.questObjectives, T.ORDER.zone, { minZ = T.ZONE_FROM })   -- (2.1.52: too)
	S.ours[zone.frame], S.ours[cont.frame], S.ours[world.frame], S.ours[givers.frame] = true, true, true, true
	S.ours[objectives.frame] = true
	pins:Layer(LAYER.town, T.ORDER.zone, { minZ = T.ZONE_FROM })   -- (2.1.53: the town marks, as the zone's)
end

-- (the API's pins added before the map's places were made: laid at its first open, the canvas laid out)
local function ApiEarly()
	S.apiLaid = true
	for owner, list in pairs(S.api) do
		for key, e in pairs(list) do
			if S.canvas.byID[e.mapID] then
				ApiLay(e)
			else
				API:ClearPin(owner, key)
			end
		end
	end
end

-- (2.1.51) borrowing wanted: other addons' pins on, or Questie's givers -- the givers while Questie is active
-- (QuestieLook's Givers) -- with the Quest givers switch on (their own layer); the other addons' layer stays hidden
-- while its switch is off, so nothing of theirs shows then
function AddonPins.Wanted()
	if not S.pins then
		return false
	end
	if S.pins.layers[LAYER.zone].on then
		return true
	end
	-- (2.1.53) the town marks: their own layer, whatever the other addons' pins' switch says
	local Town = ns.TownMarks
	if Town and Town.Used() then
		return true
	end
	local QLook = MelloUI.QuestieLook
	if not (QLook.Givers and QLook.Givers()) then
		return false
	end
	local givers = S.pins.layers[LAYER.questGivers]
	if givers and givers.on then
		return true
	end
	-- (2.1.52, stage 2) Questie in its own look: its objectives too, on their own layer, while their switch is on
	local objectives = S.pins.layers[LAYER.questObjectives]
	return (objectives and objectives.on and not QLook.Used()) and true or false
end

function AddonPins.Open()
	if not AddonPins.Wanted() then
		return   -- (switched off: other addons' icons left to the game's map)
	end
	S.shown = true
	if not S.apiLaid then
		ApiEarly()
	end
	FindLibs()
	HookSources()
	for _, entry in ipairs(S.libs) do
		entry.full = true
	end
	Queue()
	S.cut, S.stale, S.viewID = nil, false, false
	S.pins:Lay()
	AddonPins.View()
end

function AddonPins.Close()
	if not S.pins then
		return
	end
	S.shown = false
	-- (the borrowed icons back to their libraries; the nodes let go: built again for the zones in view at the next open)
	for icon in pairs(S.owner) do
		Drop(icon)
	end
	wipe(S.queue)
	DropZones()
	if ns.TownMarks then
		wipe(ns.TownMarks.questie)   -- (2.1.53: which town kinds Questie has, found again at the next open)
	end
	-- (2.1.43: RareScanner asked again at the next open: what was killed or opened since)
	local RL = MelloUI.RareScannerLook
	if RL and RL.Forget then
		RL.Forget()
	end
end

function AddonPins.Tick()
	if not S.shown then
		return
	end
	local lay = false
	if S.queued or next(S.queue) then
		Queue()
		lay = true
	end
	if S.stale then
		S.stale = false
		DropZones()
	end
	if S.cut ~= S.canvas.cuts then
		Zones()
	end
	if lay then
		S.pins:Lay()
	end
end

function AddonPins.View()
	if not (S.shown and next(S.views)) then
		return
	end
	local id = S.canvas:ViewMap()
	if id ~= S.viewID then
		S.viewID = id
		for _, fn in pairs(S.views) do
			pcall(fn, id)
		end
	end
end

return AddonPins

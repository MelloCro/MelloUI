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
	ZONE_FROM = 2.5,         -- a zone's pins from a zone's zoom on (the quest givers' zoom: Layers.T.QUESTS_FROM)
	CONTINENT_FROM = 1.15,   -- a continent's from a continent's zoom on (the docks' and flights': PLACES_FROM)
	NODE = 14,               -- HandyNotes' and GatherMate2's 12 px icon at the game's map's top pin scale (1.2)
	KEEP = 12,               -- zones' nodes kept built: the ones in view, then the nearest seen last
	BUILD_PER_FRAME = 2,     -- zones built in one frame (a zone of imported gathering data: hundreds of nodes)
	SIZE = 16,               -- an API pin's size by default
	-- HereBeDragons' world map pins: the library's own name, and Questie's renamed copy
	HBD = {
		{ pins = "HereBeDragons-Pins-2.0", hbd = "HereBeDragons-2.0" },
		{ pins = "HereBeDragonsQuestie-Pins-2.0", hbd = "HereBeDragonsQuestie-2.0", questie = true },
	},
	SHOW_CONTINENT = 2,      -- HBD_PINS_WORLDMAP_SHOW_CONTINENT
	SHOW_WORLD = 3,          -- HBD_PINS_WORLDMAP_SHOW_WORLD
	DEPTH = 8,               -- parents walked up from a map this canvas does not have (a micro zone's, a cave's)
}
AddonPins.T = T

local LAYER = { zone = "addons", continent = "addons_continent", world = "addons_world" }

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
-- draws itself: [the picture's file name] = the map's layer that draws it. Its inns and mailboxes stay (none here)
-- (2.1.50: the core's table and test, MelloUI.QuestieLook.TOWN / Town -- one for this map and the minimap)
local TOWN = MelloUI.QuestieLook.TOWN
AddonPins.TOWN = TOWN
local Town = MelloUI.QuestieLook.Town

-- what this map shows of the quests already (taken once a pass): MapObjectives' givers shown and objectives laid;
-- (2.1.39; the user, 2026-11-10: "didnt i say that we provide the look? this way we have lost our own function which i
-- like very much") and this map's own layers of them: while the quest givers' layer (quests) or the objectives' layer
-- is on, it draws that kind itself -- MelloUI's filters, areas and motions -- and Questie's of that kind are never
-- borrowed; with the layer switched off, Questie's fill in, in MelloUI's pictures
local function Cover()
	local O = ns.Objectives
	if not (O and O.GiversShown and O.Laid) then
		return nil
	end
	local ok, givers = pcall(O.GiversShown)
	local Map = MelloUI.modules and MelloUI.modules.Map
	local on = type(Map) == "table" and type(Map.LayerOn) == "function"
	return { givers = ok and type(givers) == "table" and givers or {}, laid = O.Laid,
		quests = on and Map:LayerOn("quests") and true or false,
		objectives = on and Map:LayerOn("objectives") and true or false,
		flights = on and Map:LayerOn("flights") and true or false }
end

local function Covered(look, icon, cover)
	if cover and ((look.cover == "objective" and cover.objectives)
		or ((look.cover == "giver" or look.cover == "ender") and cover.quests)) then
		return true
	end
	local data = rawget(icon, "data")
	local q = cover and look.cover and type(data) == "table" and Finite(data.Id)
	if not q then
		return false
	end
	if look.cover == "objective" then
		return cover.laid(q) and true or false
	end
	local g = cover.givers[q]
	if not g then
		return false
	end
	if look.cover == "giver" then
		return (g.available or g.locked) and true or false
	end
	return (g.ready or g.progress) and true or false
end

local function Restyle(icon, look)
	local tex = styled[icon]
	if not tex then
		tex = icon:CreateTexture(nil, "OVERLAY", nil, 7)
		tex:SetAllPoints(icon)
		styled[icon] = tex
	end
	for _, key in ipairs(QUESTIE_PARTS) do
		local part = rawget(icon, key)
		if part and part.SetAlpha then
			part:SetAlpha(0)
		end
	end
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
		local w = Finite(icon:GetWidth())
		P.Lift(tex, look.icon or false, w and w > 0 and w or 16)
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
	local P = ns.Pins
	if P and P.Lift then
		P.Lift(tex, false)
	end
	for _, key in ipairs(QUESTIE_PARTS) do
		local part = rawget(icon, key)
		if part and part.SetAlpha then
			part:SetAlpha(1)
		end
	end
	if not quiet then
		MelloUI.QuestieLook.Relay(icon)
	end
end
-- (2.1.50) Questie let an icon go: our picture goes with it, never onto the frame's next use
MelloUI.QuestieLook.OnRelease(function(icon)
	Unstyle(icon, true)
end)
AddonPins.Restyled = function(icon)
	local tex = styled[icon]
	return tex ~= nil and tex:IsShown() and tex or nil
end

-- (MapLayers' quest givers and MapObjectives' objectives laid again) Questie's icons looked at again on the next beat
function AddonPins.Recheck()
	for _, entry in ipairs(S.libs) do
		if entry.questie then
			entry.full = true
			S.queued = true
		end
	end
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
	-- (2.1.44: Questie's icons as any addon's while its switch on the Addons page, Use with MelloUI, is off)
	local questie = entry.questie and MelloUI.QuestieLook.Used()
	local look = questie and QuestieLook(icon) or nil
	local town = questie and not look and Town(icon) or nil
	local covered = (look and Covered(look, icon, cover)) or (town and cover and cover[town]) or false
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
	if look then
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
		local okP, lib = pcall(LibStub, names.pins, true)
		local okH, hbd = pcall(LibStub, names.hbd, true)
		if okP and okH and type(lib) == "table" and type(hbd) == "table" and not S.byLib[lib]
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
	for name, handler in pairs(hn.plugins) do
		if enabled[name] and type(handler) == "table" and type(handler.GetNodes2) == "function" then
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
					if coord then
						local x, y = floor(coord / 10000) / 10000, (coord % 10000) / 10000
						local spec = {
							size = T.NODE * scale * (Finite(s) or 1), alpha = min(max(alpha * (Finite(a) or 1), 0), 1),
							enter = NodeEnter, leave = NodeLeave, click = NodeClick, right = true,
							data = { name, map2 or id, coord },
						}
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
						add("hn:" .. name .. ":" .. (map2 or id) .. ":" .. coord, map2 or id, x, y, spec)
					end
				end
			end
		end
	end
end

-- GatherMate2: the zone's nodes of each kind it shows (its own filters), its own pictures
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
					local okL, x, y = pcall(gm.DecodeLoc, gm, coord)
					local okT, title = pcall(gm.GetNameForNode, gm, kind, nodeID)
					if okL and Finite(x) and Finite(y) then
						add("gm:" .. kind .. ":" .. id .. ":" .. coord, id, x, y, {
							icon = pics and pics[nodeID], size = size, alpha = alpha, fillTip = GatherTip,
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
local building   -- the zone being built (its pins' keys)
local function AddNode(key, mapID, x, y, spec)
	if spec.icon or spec.atlas then
		local pin = S.pins:SetAt(LAYER.zone, key, mapID, x, y, spec)
		if pin then
			building[#building + 1] = key
		end
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
	S.zones[id] = nil
	S.zoneCount = S.zoneCount - 1
end

local function DropZones()
	for id in pairs(S.zones) do
		DropZone(id)
	end
	S.cut = nil
end

local function BuildZone(id)
	building = {}
	for _, source in ipairs(Sources) do
		source(id, AddNode)
	end
	S.zones[id] = { keys = building, gen = S.zoneGen }
	S.zoneCount = S.zoneCount + 1
	building = nil
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
	end
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
	S.ours[zone.frame], S.ours[cont.frame], S.ours[world.frame] = true, true, true
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

function AddonPins.Open()
	if not S.pins or not S.pins.layers[LAYER.zone].on then
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

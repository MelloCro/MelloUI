--------------------------------------------------------------------------------
-- MelloUI Map - the town marks (2.1.53; docs/plans/handynotes-npcs.md; the user, 2026-11-15: "people were asking for
-- Important NPC locations on the Map and minimap, can we utilize HandyNotes Addon for this as Compatibility?", then
-- "we need to make sure that the map doesent get crowded"; the Town NPC Marks sketch, "Yes, as proposed")
--
-- The places are the plugin's, HandyNotes: NPCs (Forever) -- read through its own handler (GetNodes2 hands out the
-- zone's node table: each node its kinds, their sorts, its faction), none of its code or data copied, none of its
-- settings written. What shows is MelloUI's to decide ("Yes, MelloUI Decides"): a switch a kind on the map's layers
-- page, under HandyNotes (Map.lua's SWITCHES, kept in db.layers as the other layers), each kind in MelloUI's own icon
-- in the look on show (MelloUI.Icons: Modern's set, Oldschool's painted one, the game's pictures under Default).
--
--   the important kinds on from the start (Town.KINDS' `on`), the rest behind their switches;
--   only your side's and the neutral ones; a profession's trainer only of a profession you have, a class trainer
--   only of your class;
--   a node of several kinds (a vendor who repairs) wears the first of its kinds whose switch is on;
--   from a zone's zoom on, as the other addons' pins; the tooltip and the click the plugin's own.
--
-- ONE owner a kind of place (the user: "i only want 1 addon to have Priority on that even if 5 different addons are
-- being used, no duplicate Icons from Different addons"), the first of these that has the kind:
--   1  MelloUI's own data     the flight masters, (2.1.92) the spirit healers (the Travel group's switches)
--   2  the plugin             every kind of Town.KINDS, while MelloUI's look of it is used
--   3  Questie's townsfolk    (without the plugin: as before)
--   4  any other addon's pin  known by the game's tracking picture it wears (Town.PICTURE)
-- A pin of a kind an owner before its source has is not drawn (Town.Held, asked by MapAddonPins), whatever that
-- owner's switch says: the switch decides the kind.
--
-- The minimap wears what the map wears: the same kinds by the same switches, from the same table, on Route's
-- minimap layer (as the flight masters: MapLayers' MiniFlights); the plugin's own minimap icons are taken off
-- HereBeDragons right after HandyNotes lays them (a post-hook on HandyNotes' own UpdateMinimapPlugin). Without Route
-- the plugin's own stay.
--
-- With the plugin's switch on the Addons page off (Core/Integrations.lua, "MelloUI's look") nothing here runs: the
-- plugin shows its own way, on MelloUI's map too (MapAddonPins' HandyNotes source). Nothing at login but the tables.
--
--   Town.KINDS                the kinds, in the layers' page's order
--   Town.There() / Used()     the plugin is registered with HandyNotes / and MelloUI's look of it is used
--   Town.Starts(layerKey)     false for a layer's key that starts off (Map.lua's LayerOn)
--   Town.Zone(id, add)        a zone's marks (MapAddonPins' BuildZone)
--   Town.Held(kind, source)   whether a pin of that kind from that source gives way
--   Town.KindOfPicture(path)  a town kind by the picture a pin wears, nil for none
--   Town.Mini(enabled)        the minimap's marks wanted (the map on) or not
--   Town.Changed()            a kind's switch turned: the map's marks and the minimap's built again
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = (ns and ns.MelloUI) or _G.MelloUI
local Perf = MelloUI.Perf:Scope("MelloUI_Map (TownMarks)")
local Safe = MelloUI.Safe
local Finite, Text, Plain = Safe.Finite, Safe.Text, Safe.Value
local pairs, ipairs, pcall, type, rawget = pairs, ipairs, pcall, type, rawget
local floor, abs = math.floor, math.abs

local Town = {}
ns.TownMarks = Town

local T = {
	PLUGIN = "HandyNotes_NPCs_Forever",   -- its name among HandyNotes' plugins, and its folder
	USE = "HandyNotesNPCs",               -- its switch on the Addons page (Core/Integrations.lua)
	PREFIX = "npc_",                      -- a kind's key among the map's layers (db.layers)
	SIZE = 22,                            -- a mark on the map (the sketch's)
	MINI = 13,                            -- on the minimap (the flight masters': MapLayers' MINI.SIZE)
	OWNER = "Map town marks",             -- on Route's minimap layer
	ICONS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\",
	EVENTS = { "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "SKILL_LINES_CHANGED" },
}
Town.T = T

-- the kinds, in the layers' page's order: key, label (the page's row), icon (its name in MelloUI's set: Modern's
-- picture, Oldschool's painted one, the game's under Default -- Core/Skin.lua's ICON; the last seven drawn for these
-- marks, the user's pick "All A" of town_mark_icons_sketch, 2026-11-15), on (shown from the start: true, or a
-- class's token -- on for that class), yours ("profession" | "class": only your own)
Town.KINDS = {
	{ key = "auction", label = "Auction house", icon = "svc_auction", on = true },
	{ key = "bank", label = "Bank", icon = "svc_bank", on = true },
	{ key = "riding", label = "Riding trainers", icon = "svc_riding", on = true },
	{ key = "mounts", label = "Mount sellers", icon = "svc_mounts", on = true },
	{ key = "proftrainer", label = "Your professions' trainers", icon = "svc_proftrainer", on = true,
	  yours = "profession" },
	{ key = "classtrainer", label = "Your class's trainers", icon = "svc_classtrainer", on = true, yours = "class" },
	{ key = "inn", label = "Innkeepers", icon = "svc_inn", on = true },
	{ key = "mail", label = "Mailboxes", icon = "svc_mail", on = true },
	{ key = "repair", label = "Repair", icon = "svc_repair" },
	{ key = "stable", label = "Stable masters", icon = "svc_stable", on = "HUNTER" },
	{ key = "v_reagents", label = "Vendors: reagents", icon = "svc_vendor" },
	{ key = "v_food", label = "Vendors: food and drink", icon = "svc_vendor" },
	{ key = "v_general", label = "Vendors: general goods", icon = "svc_vendor" },
	{ key = "v_bags", label = "Vendors: bags", icon = "svc_vendor" },
	{ key = "v_pets", label = "Vendors: pets", icon = "svc_vendor" },
	{ key = "v_weapons", label = "Vendors: weapons", icon = "svc_vendor" },
	{ key = "v_armor", label = "Vendors: armor", icon = "svc_vendor" },
	{ key = "v_supplies", label = "Vendors: profession supplies", icon = "svc_vendor" },
	{ key = "v_quartermasters", label = "Vendors: quartermasters", icon = "svc_vendor" },
	{ key = "v_other", label = "Vendors: other", icon = "svc_vendor" },
	{ key = "battlemaster", label = "Battlemasters", icon = "svc_battlemaster" },
	{ key = "weaponmaster", label = "Weapon masters", icon = "svc_weaponmaster" },
	{ key = "guild", label = "Guild masters and tabards", icon = "svc_guild" },
	{ key = "transmog", label = "Transmogrifiers", icon = "svc_transmog" },
	-- (2.1.92) no spirit healers' row here: MelloUI's own, from the client's graveyards, are the owner (the Travel
	-- group's Spirit healers switch, MapLayers' Spirits) -- the plugin's data has none anyway
}
local byKey, byLayer = {}, {}
for _, k in ipairs(Town.KINDS) do
	k.layer = T.PREFIX .. k.key
	byKey[k.key], byLayer[k.layer] = k, k
end
Town.byKey = byKey

-- the plugin's kinds (a node's c) as MelloUI's; a vendor's by its sort (VENDOR; any other sort: the last row). Its
-- flight masters are never drawn from it: MelloUI's own are the owner. Its rares: RareScanner's field, not a town's
local KIND = {
	auctioneer = "auction", banker = "bank", mounttrainer = "riding", trainer = "proftrainer",
	classtrainer = "classtrainer", innkeeper = "inn", mailbox = "mail", repair = "repair", stablemaster = "stable",
	battlemaster = "battlemaster", weaponmaster = "weaponmaster", guildmaster = "guild", tabard = "guild",
	transmogrifier = "transmog", spirithealer = "spirit",
}
local VENDOR = {
	["Mounts"] = "mounts", ["Reagents & Potions"] = "v_reagents", ["Food & Drink"] = "v_food",
	["General Goods"] = "v_general", ["Bags"] = "v_bags", ["Pets"] = "v_pets", ["Weapons"] = "v_weapons",
	["Armor"] = "v_armor", ["Profession Supplies"] = "v_supplies", ["Quartermasters"] = "v_quartermasters",
}
local VENDOR_OTHER = "v_other"
Town.KIND, Town.VENDOR = KIND, VENDOR

-- a profession's sort as the game's skill line (C_SkillInfo: the same in every language)
local SKILL = {
	["Alchemy"] = 171, ["Blacksmithing"] = 164, ["Enchanting"] = 333, ["Engineering"] = 202, ["Herbalism"] = 182,
	["Leatherworking"] = 165, ["Mining"] = 186, ["Skinning"] = 393, ["Tailoring"] = 197, ["Cooking"] = 185,
	["First Aid"] = 129, ["Fishing"] = 356,
}
Town.SKILL = SKILL

-- a town kind by the picture a pin of another source wears (its file's name, lower case): the game's tracking and
-- gossip pictures, and the ones Questie's townsfolk and the plugin itself wear. "flight": MelloUI's own kind
local PICTURE = {
	auctioneer = "auction", banker = "bank", innkeeper = "inn", mailbox = "mail", repair = "repair",
	stablemaster = "stable", ["stable master"] = "stable", class = "classtrainer", ["class trainer"] = "classtrainer",
	profession = "proftrainer", battlemaster = "battlemaster", flightmaster = "flight", ["flight master"] = "flight",
	transmogrifier = "transmog", food = "vendor", reagents = "vendor", ammunition = "vendor", poisons = "vendor",
	["weapon master"] = "weaponmaster", ["spirit healer"] = "spirit",
	vendorgossipicon = "vendor", trainergossipicon = "proftrainer", tabardgossipicon = "guild",
	petitiongossipicon = "guild", battlemastergossipicon = "battlemaster", bankergossipicon = "bank",
	taxigossipicon = "flight", bindergossipicon = "inn",
	-- (Questie's profession trainers, each its profession's picture; its riding trainers)
	trade_blacksmithing = "proftrainer", trade_leatherworking = "proftrainer", trade_alchemy = "proftrainer",
	trade_herbalism = "proftrainer", trade_mining = "proftrainer", trade_tailoring = "proftrainer",
	trade_engineering = "proftrainer", trade_engraving = "proftrainer", trade_fishing = "proftrainer",
	inv_misc_food_15 = "proftrainer", inv_misc_pelt_wolf_01 = "proftrainer", spell_holy_sealofsacrifice = "proftrainer",
	spell_nature_swiftness = "riding",
	-- (the plugin's own, worn by a copy of it or a plugin made after it)
	ability_mount_ridinghorse = "riding", inv_sword_27 = "weaponmaster", spell_holy_guardianspirit = "spirit",
	inv_letter_15 = "mail", inv_chest_cloth_17 = "transmog",
}
Town.PICTURE = PICTURE

function Town.KindOfPicture(path)
	path = Text(path)
	local name = path and path:match("([^\\/]+)$")
	name = name and name:gsub("%.%w+$", ""):lower()
	return name and PICTURE[name] or nil
end

--------------------------------------------------------------------------------
-- The plugin
--------------------------------------------------------------------------------

local function Ace(name)
	return ns.AddonPins.Ace(name)
end

-- its handler and HandyNotes, nil while it is not registered (it registers at the login)
local function Plugin()
	local hn = Ace("HandyNotes")
	local handler = hn and type(hn.plugins) == "table" and hn.plugins[T.PLUGIN] or nil
	if type(handler) ~= "table" or type(handler.GetNodes2) ~= "function" then
		return nil
	end
	return handler, hn
end
Town.Plugin = Plugin

function Town.There()
	return Plugin() ~= nil
end

-- MelloUI's look of it used: the plugin there, its switch and HandyNotes' on the Addons page on, HandyNotes itself
-- on and the plugin ticked in its list (both the player's own settings there: read, never written)
function Town.Used()
	local handler, hn = Plugin()
	if not handler then
		return false
	end
	local I = rawget(MelloUI, "Integrations")
	if I and not (I.Use("HandyNotes") and I.Use(T.USE)) then
		return false
	end
	local okE, on = pcall(hn.IsEnabled, hn)
	if okE and not on then
		return false
	end
	local profile = type(hn.db) == "table" and hn.db.profile
	local enabled = type(profile) == "table" and profile.enabledPlugins
	return type(enabled) ~= "table" or enabled[T.PLUGIN] ~= false
end

-- a zone's node table as the plugin hands it out (its GetNodes2's state: [coord] = node), nil for none -- a zone it
-- has nothing for, or its own display of that place (the map, the minimap) switched off in its options
local function Nodes(id, minimap)
	local handler = Plugin()
	if not handler then
		return nil
	end
	local ok, _, state = pcall(handler.GetNodes2, handler, id, minimap and true or false)
	return ok and type(state) == "table" and state or nil
end

--------------------------------------------------------------------------------
-- The switches and what is yours
--------------------------------------------------------------------------------

local me = { side = nil, class = nil }

-- your side as the plugin writes it ("A" | "H"), false while unknown or neutral
local function Side()
	if me.side == nil then
		local ok, f = pcall(_G.UnitFactionGroup, "player")
		f = ok and Text(f) or nil
		if f == "Alliance" or f == "Horde" then
			me.side = f:sub(1, 1)
		else
			return false
		end
	end
	return me.side
end

local function Class()
	if me.class == nil then
		local ok, _, token = pcall(_G.UnitClass, "player")
		token = ok and Text(token) or nil
		if not token then
			return nil
		end
		me.class = token
	end
	return me.class
end

-- (Map.lua's LayerOn) false for a layer's key that starts off; nil for a key that is not a town kind's
function Town.Starts(layer)
	local k = byLayer[layer]
	if not k then
		return nil
	end
	if type(k.on) == "string" then
		return k.on == Class()
	end
	return k.on == true
end

local function On(k)
	local Map = MelloUI.modules and MelloUI.modules.Map
	if type(Map) == "table" and type(Map.LayerOn) == "function" then
		return Map:LayerOn(k.layer) and true or false
	end
	return Town.Starts(k.layer) and true or false
end
Town.On = On

-- a trainer's sort yours: a profession you have (its skill line read; one that cannot be read: shown), your class
-- (the sort begins with it: "Hunter (Pets)")
local function Yours(what, sort)
	sort = Text(sort)
	if not sort then
		return true
	end
	if what == "class" then
		local class = Class()
		return not class or sort:upper():gsub("[^A-Z]", ""):sub(1, #class) == class
	end
	local line = SKILL[sort]
	local get = line and C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
	if not get then
		return true
	end
	local ok, info = pcall(get, line)
	if not ok then
		return true
	end
	if info == nil then
		return false
	end
	local rank = type(info) == "table" and Plain(info.rank)
	return type(rank) ~= "number" or rank > 0
end
Town.Yours = Yours

-- the kind a node is shown as: the first of its kinds (the plugin's own order) whose switch is on and that is
-- yours; nil for none, and for the other side's
function Town.KindOf(node)
	if type(node) ~= "table" or type(node.c) ~= "table" then
		return nil
	end
	local side = Side()
	if node.f and side and node.f ~= side then
		return nil
	end
	local sorts = type(node.s) == "table" and node.s or nil
	for _, c in ipairs(node.c) do
		local sort = sorts and sorts[c] or nil
		local key = c == "vendor" and (VENDOR[sort] or VENDOR_OTHER) or KIND[c]
		local k = key and byKey[key]
		if k and On(k) and (not k.yours or Yours(k.yours, sort)) then
			return k
		end
	end
	return nil
end

-- a kind's picture: MelloUI's icon of it, in the look on show (MelloUI.Icons)
function Town.Icon(k)
	return T.ICONS .. k.icon
end

--------------------------------------------------------------------------------
-- One owner a kind
--------------------------------------------------------------------------------

local RANK = { own = 1, npcs = 2, questie = 3, other = 4 }
Town.questie = {}   -- [kind] = true: Questie's townsfolk of it stand on the map now (MapAddonPins' Place)

-- whether a pin of `kind` (Town.KindOfPicture's) from `source` ("questie" | "other") gives way to an owner before it
function Town.Held(kind, source)
	if not kind then
		return false
	end
	local rank = RANK[source] or RANK.other
	if kind == "flight" or kind == "spirit" then
		-- (2.1.92: the spirit healers too -- MelloUI's own from the client's graveyards, its Spirit healers switch)
		local Map = MelloUI.modules and MelloUI.modules.Map
		return type(Map) == "table" and type(Map.LayerOn) == "function"
			and Map:LayerOn(kind == "flight" and "flights" or "spirits") and true or false
	end
	if rank > RANK.npcs and Town.Used() then
		return true
	end
	return rank > RANK.questie and Town.questie[kind] == true
end

--------------------------------------------------------------------------------
-- The map: a zone's marks
--------------------------------------------------------------------------------

function Town.Zone(id, add)
	if not Town.Used() then
		return
	end
	local nodes = Nodes(id, false)
	if not nodes then
		return
	end
	local node = ns.AddonPins.NODE
	for coord, n in pairs(nodes) do
		local c = Finite(coord)
		local k = c and Town.KindOf(n)
		if k then
			add("town:" .. id .. ":" .. c, id, floor(c / 10000) / 10000, (c % 10000) / 10000, {
				icon = Town.Icon(k), size = T.SIZE, enter = node.enter, leave = node.leave, click = node.click,
				right = true, data = { T.PLUGIN, id, c }, kind = k.key,
			})
		end
	end
end

--------------------------------------------------------------------------------
-- The minimap: the same marks round you, on Route's minimap layer
--------------------------------------------------------------------------------

local mini = { marks = {}, n = 0, list = nil, want = false, events = nil, hooked = false }
Town.mini = mini

local function MiniLeave(f)
	if GameTooltip:GetOwner() == f then
		GameTooltip:Hide()
	end
end

-- (the plugin's own tooltip, as on the map)
local function MiniEnter(f)
	local handler = Plugin()
	if handler and type(handler.OnEnter) == "function" then
		pcall(handler.OnEnter, f, f.mapID, f.coord)
	end
end

-- a mark (made the first time it is needed): the picture, the mouse's motion only (the minimap keeps its clicks)
local function MiniMark(i, frame)
	local f = mini.marks[i]
	if not f then
		f = CreateFrame("Frame", nil, frame)
		f:SetFrameLevel(frame:GetFrameLevel() + 1)   -- (under the quest marks, as the flight masters)
		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetAllPoints(f)
		if f.SetMouseClickEnabled then
			f:EnableMouse(true)
			f:SetMouseClickEnabled(false)
			f:SetScript("OnEnter", MiniEnter)
			f:SetScript("OnLeave", MiniLeave)
			f:SetScript("OnHide", MiniLeave)
		end
		mini.marks[i] = f
	end
	return f
end

-- your zone's marks in Route's yards (once a zone; again when the zone, your skills or a switch changes). While the
-- plugin is not registered yet (the login) nothing is kept: asked again
local EMPTY = {}
local function MiniList()
	if mini.list then
		return mini.list
	end
	if not Plugin() then
		return EMPTY
	end
	local list = {}
	mini.list = list
	local Route = MelloUI.Route
	local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
	id = ok and Finite(id) or nil
	local nodes = id and Town.Used() and Nodes(id, true)
	if not nodes then
		return list
	end
	for coord, n in pairs(nodes) do
		local c = Finite(coord)
		local k = c and Town.KindOf(n)
		if k then
			local okY, cont, x, y = pcall(Route.ToYards, id, floor(c / 10000) / 10000, (c % 10000) / 10000)
			if okY and cont and x and y then
				list[#list + 1] = { cont = cont, x = x, y = y, icon = Town.Icon(k), mapID = id, coord = c }
			end
		end
	end
	return list
end

-- Route's minimap layer's tick (cont nil: hidden)
function Town.MiniDraw(cont, round, R, RX, RY)
	local Route = MelloUI.Route
	local frame = Route.MinimapFrame()
	local n = 0
	if cont and frame then
		local Offset, m = Route.MinimapOffset, T.MINI / 2
		for _, p in ipairs(MiniList()) do
			if p.cont == cont then
				local gx, gy = Offset(p.x, p.y)
				local on
				if round then
					on = gx * gx + gy * gy <= (R - m) * (R - m)
				else
					on = abs(gx) <= RX - m and abs(gy) <= RY - m
				end
				if on then
					n = n + 1
					local f = MiniMark(n, frame)
					f.mapID, f.coord = p.mapID, p.coord
					if f.at ~= p.icon then
						f.at = p.icon
						MelloUI.Icons.Set(f.icon, p.icon, T.MINI)
					end
					Route.MarkPlace(f, T.MINI, frame, "CENTER", gx, gy)
				end
			end
		end
	end
	for i = n + 1, mini.n do
		mini.marks[i]:Hide()
	end
	mini.n = n
end

local function PinsLib()
	local LibStub = rawget(_G, "LibStub")
	local ok, lib = pcall(LibStub, "HereBeDragons-Pins-2.0", true)
	return ok and type(lib) == "table" and type(lib.RemoveAllMinimapIcons) == "function" and lib or nil
end

-- the plugin's own minimap icons off HereBeDragons while MelloUI's marks stand there (HandyNotes keeps the frames:
-- its next update takes them back and lays them again -- OwnLaid, the post-hook, takes those off too)
local function OwnOff()
	local lib = mini.want and Town.Used() and PinsLib()
	if lib then
		pcall(lib.RemoveAllMinimapIcons, lib, "HandyNotes" .. T.PLUGIN)
	end
end

local OwnLaid = Perf.Shared("HandyNotes' UpdateMinimapPlugin, for the town marks", function(_, name)
	if name == T.PLUGIN then
		mini.list = nil   -- (its options changed, or the zone)
		OwnOff()
	end
end, "hook")

-- (Map.lua: its OnEnable and OnDisable) the minimap's town marks wanted or not: the map on, with Route's minimap
-- layer and the plugin's folder loaded -- the plugin itself registers at the login, so the list waits for it
-- (MiniList)
function Town.Mini(enabled)
	local R = MelloUI.Route
	local can = type(R) == "table" and type(R.WantMinimap) == "function" and type(R.ToYards) == "function"
	local I = rawget(MelloUI, "Integrations")
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and select(2, pcall(C_AddOns.IsAddOnLoaded, T.PLUGIN))
	local on = enabled and can and Plain(loaded) == true
		and not (I and not (I.Use("HandyNotes") and I.Use(T.USE))) and true or false
	local was = mini.want
	mini.want, mini.list = on, nil
	local hn = Ace("HandyNotes")
	if on and hn and not mini.hooked and type(hn.UpdateMinimapPlugin) == "function" then
		mini.hooked = true
		Perf.hooksecurefunc(hn, "UpdateMinimapPlugin", OwnLaid)
	end
	if on and not mini.events then
		mini.events = CreateFrame("Frame")
		Perf.SetScript(mini.events, "OnEvent", function(_, event)
			mini.list = nil
			if event == "SKILL_LINES_CHANGED" then
				ns.AddonPins.Stale()   -- (a profession learned: its trainers on the map)
			end
		end)
	end
	if mini.events then
		for _, event in ipairs(T.EVENTS) do
			if on then
				mini.events:RegisterEvent(event)
			else
				mini.events:UnregisterEvent(event)
			end
		end
	end
	if can then
		R.WantMinimap(T.OWNER, on and Town.MiniDraw or nil)
	end
	if on then
		OwnOff()
	elseif was and hn and type(hn.UpdateMinimapPlugin) == "function" then
		pcall(hn.UpdateMinimapPlugin, hn, T.PLUGIN)   -- (its own back)
	end
end

-- a switch of the layers' page changed: the map's zones built again, the minimap's list too
function Town.Changed()
	mini.list = nil
	ns.AddonPins.Stale()
end

return Town

--------------------------------------------------------------------------------
-- MelloUI - RareScanner's look (2.1.43; CurseForge, whatever_69: "Any chance we can get the Map to work with
-- Rarescanner?"; the user, 2026-11-11: "make sure we do it like we did with Questie, Rarescanner is the engine, we
-- provide the look, we already have the rare notification in our widget"; the picks: its alert button switched off
-- once, Rare Alert fed by its rare finds too, its minimap icons in MelloUI's look; of
-- Workspace/BuildData/output/rarescanner_sketch: B, MelloUI's icons on a plate. Plan: docs/plans/rarescanner.md)
--
-- RareScanner (maqjav, All Rights Reserved: only what it shows or keeps global is read here, nothing of its code)
-- decides -- its database, its filters, what you found, killed or opened; MelloUI draws:
--   RL.On()                    RareScanner loaded, its world map provider there
--   RL.POIs(mapID) -> list     what RareScanner would lay on the game's map for a map: its own world map provider
--                              (its global RareScannerDataProviderMixin) hosted on a stand-in map that keeps what
--                              it is handed -- the game's map never touched (MelloUI_Map's rule)
--   RL.Kind(POI), RL.State(POI)  "rare" / "treasure" / "event"; "seen" (just now) / "notfound" (not found yet) /
--                              "found" / "done" (killed or opened): its own picture says which (its colours' meanings)
--   RL.Seal(POI, size) -> spec  look B: MelloUI's icon on a plate, the plate's rim the state's (gold, red, steel),
--                              the whole pin faded once done -- a pin spec of MelloUI_Map's Pins (its seals)
--   the minimap: RareScanner's own icons (HereBeDragons-Pins, its frames) wear the same plate as they are added
--   RL.MapLook() -> bool       (2.1.50) the big map wears the seals (MelloUI's map on): the minimap follows it --
--                              its icons dressed exactly then, RareScanner's own pictures while not (RL.Relay())
--   its alert button: switched off once (the user: "Yes, switch it off once"; a player who switches it on again keeps
--                              it); each find it reports (its DisplayMessages) a rare's sighting for Rare Alert
-- Nothing at login while RareScanner is not loaded; with it, the minimap's hook as it loads, then one hook, the one
-- switch and a look at the minimap icons laid already at PLAYER_LOGIN.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("RareScannerLook")
local Finite = MelloUI.Safe.Finite
local Text = MelloUI.Safe.Text
local Secret = MelloUI.Safe.IsSecret

local RL = {}
MelloUI.RareScannerLook = RL

local T = {
	ICONS = "Interface\\AddOns\\MelloUI\\Media\\Textures\\Icons\\",
	EMBLEM = { rare = "kill_rare", treasure = "ql_chest", event = "obj_explore" },
	PLATE = "badge_disc",
	RIM = { seen = "selectedTrim", found = "mutedText", done = "mutedText" },   -- (palette keys; notfound: a meaning)
	CORE = "innerPanel",
	DONE = 0.45,          -- a done pin's alpha
	RIM_PX = 2.5,         -- the rim's width at a pin of SIZE
	HALO = 3,             -- px of gold round a pin seen just now
	SIZE = 26,            -- a pin on the map (the sketch's plate: 1.25 times its 21 px icon)
	MINI = 17,            -- on the minimap (the sketch's)
	CACHE = 10,           -- s a map's POIs are kept before RareScanner is asked again
	TEMPLATES = { RSEntityPinTemplate = true, RSGroupPinTemplate = true },
	PARTS = { "Texture", "IconTexture" },   -- (2.1.50) its minimap pin's own pictures (RSMinimapPinTemplate)
}
RL.T = T

local S = { got = nil, map = nil, provider = nil, cache = {}, dressed = setmetatable({}, { __mode = "k" }),
	pins = nil, hooked = nil }   -- (2.1.50: the pins library hooked, and the function the hook made)

local function Loaded()
	local api = rawget(_G, "C_AddOns")
	local is = api and api.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded")
	local ok, on = pcall(is, "RareScanner")
	return ok and on == true
end

-- (2.1.44) and its switch on the Addons page, Use with MelloUI (Core/Integrations.lua)
function RL.On()
	local I = rawget(MelloUI, "Integrations")
	return type(rawget(_G, "RareScannerDataProviderMixin")) == "table" and Loaded()
		and not (I and not I.Use("RareScanner"))
end

local function Addon()
	local LibStub = rawget(_G, "LibStub")
	local okA, ace = pcall(LibStub, "AceAddon-3.0", true)
	if not (okA and type(ace) == "table") then
		return nil
	end
	local ok, addon = pcall(ace.GetAddon, ace, "RareScanner", true)
	return ok and type(addon) == "table" and addon or nil
end

--------------------------------------------------------------------------------
-- The data: RareScanner's world map provider, hosted
--------------------------------------------------------------------------------

-- a pin object for whatever the provider asks of the pins it is handed (pin.ShowSearchAnim:Play() while its map
-- search is on, guidePin.ShowPingAnim:SetLooping(...)): every field is it again, and calling it gives it back
local nothing
nothing = setmetatable({}, {
	__index = function()
		return nothing
	end,
	__call = function()
		return nothing
	end,
})
local function NoPins()
	return nil
end
local closed = { IsShown = function() return false end }

local function Host()
	if S.provider then
		return S.provider
	end
	local map = { mapID = nil }
	function map:GetMapID()
		return self.mapID
	end
	function map:AcquirePin(template, POI)
		if T.TEMPLATES[template] and S.got and type(POI) == "table" then
			S.got[#S.got + 1] = POI
		end
		return nothing
	end
	function map:RemoveAllPinsByTemplate() end
	function map:RemovePin() end
	function map:TriggerEvent() end
	function map:EnumeratePinsByTemplate()
		return NoPins
	end
	function map:GetMapFrame()
		return closed
	end
	local provider = CreateFromMixins(rawget(_G, "RareScannerDataProviderMixin"))
	function provider:GetMap()
		return map
	end
	S.map, S.provider = map, provider
	return provider
end

function RL.POIs(mapID)
	mapID = Finite(mapID)
	if not (mapID and RL.On()) then
		return nil
	end
	local now = GetTime()
	local c = S.cache[mapID]
	if c and now - c.at < T.CACHE then
		return c.list
	end
	local provider = Host()
	S.map.mapID = mapID
	local list = {}
	S.got = list
	local ok = pcall(provider.RefreshAllData, provider)
	S.got = nil
	if not ok then
		list = {}
	end
	S.cache[mapID] = { at = now, list = list }
	return list
end

-- (the map closed and opened again: asked again)
function RL.Forget()
	wipe(S.cache)
end

--------------------------------------------------------------------------------
-- The look: kind, state, the plate
--------------------------------------------------------------------------------

local function First(POI)
	if POI.isGroup and type(POI.POIs) == "table" and type(POI.POIs[1]) == "table" then
		return POI.POIs[1]
	end
	return POI
end

-- its picture's file name (RareScanner's colours: Pink seen just now, Red not found yet, Blue killed or opened,
-- BlueSkullLight a friendly one, Original found before)
local function Picture(POI)
	local t = Text(POI.Texture)
	return t and t:match("([^\\/]+)%.%w+$") or ""
end

function RL.Kind(POI)
	local p = First(POI)
	if p.isContainer then
		return "treasure"
	elseif p.isEvent then
		return "event"
	end
	return "rare"
end

function RL.State(POI)
	local p = First(POI)
	if p.isDead or p.isOpened then
		return "done"
	end
	local name = Picture(p)
	if name:find("^Pink") then
		return "seen"
	elseif name:find("^Red") then
		return "notfound"
	elseif name:find("^Blue") and not name:find("Light") then
		return "done"
	end
	return "found"
end

-- the plate's rim: a palette key, or (not found yet) the meaning red
local function Rim(state)
	return T.RIM[state], state == "notfound" and MelloUI.Meaning.rareNotFound or nil
end

-- a map pin's spec in look B (the map's seals: MapPins' spec.tint / rgb, core, rim, disc, edge, emblem); seen just
-- now: a gold halo round it (its outer disc gold and wider), as the sketch's glow
function RL.Seal(POI, size)
	local state, kind = RL.State(POI), RL.Kind(POI)
	local key, rgb = Rim(state)
	size = size or T.SIZE
	local seen = state == "seen"
	return {
		icon = T.ICONS .. T.PLATE, size = size, tint = key, rgb = rgb and { rgb[1], rgb[2], rgb[3] } or nil,
		core = T.CORE, rim = math.max(1, math.floor(T.RIM_PX * size / T.SIZE + 0.5)),
		disc = seen and T.RIM.seen or T.CORE, edge = seen and T.HALO or 1,
		emblem = T.ICONS .. T.EMBLEM[kind], alpha = state == "done" and T.DONE or nil,
	}
end

-- a POI's lines for MelloUI's tooltip: its name, its kind, its state
local TEXT = {
	rare = "Rare", treasure = "Treasure", event = "Event",
	seen = "Seen just now", notfound = "Not found yet", found = "Found before", done = "Killed",
	opened = "Opened", by = "RareScanner",
}
RL.TEXT = TEXT
function RL.Lines(POI)
	local state, kind = RL.State(POI), RL.Kind(POI)
	local W = MelloUI.Widgets
	local names = {}
	if POI.isGroup and type(POI.POIs) == "table" then
		for _, p in ipairs(POI.POIs) do
			local n = Text(p.name)
			if n then
				names[#names + 1] = n
			end
		end
	end
	local title = Text(POI.name) or names[1] or W.Tr(TEXT[kind])
	local what = W.Tr(TEXT[kind]) .. "  \194\183  " .. W.Tr((state == "done" and kind == "treasure") and TEXT.opened or TEXT[state])
	return title, what, #names > 1 and table.concat(names, ", ") or nil
end

--------------------------------------------------------------------------------
-- The minimap: RareScanner's icons wear the plate -- exactly while the big map wears the seals
--------------------------------------------------------------------------------

-- (2.1.50; the user, 2026-11-13: "the rare mobs are still default Rarescanner icons, make this a rule, if we use
-- Certain Icons on the Big Map, i want the Minimap to match the same settings") the big map decides: RareScanner's pins
-- are MelloUI's seals on MelloUI's map (its module on, RareScanner used with MelloUI), and its minimap icons wear the
-- plate exactly then; with MelloUI's map off the game's map shows RareScanner's own pictures, and so does the minimap
function RL.MapLook()
	if not RL.On() then
		return false
	end
	local ok, on = pcall(MelloUI.IsModuleEnabled, MelloUI, "Map")
	return ok and on and true or false
end

local function Ours(icon)
	local POI = type(icon) == "table" and rawget(icon, "POI")
	local tex = POI and Text(POI.Texture)
	return tex and tex:find("RareScanner", 1, true) and POI or nil
end

-- (2.1.50) what the pin shows now: RareScanner gives a laid pin a new picture without a new POI (its
-- RefreshEntityState: killed, opened, seen again), so the state is read from the picture on the pin, the kind from
-- its POI
local function Shown(icon, POI)
	local tex = rawget(icon, "Texture")
	local ok, path = pcall(tex and tex.GetTexture, tex)
	path = ok and Text(path) or nil
	if not (path and path:find("RareScanner", 1, true)) then
		return POI
	end
	return { Texture = path, isContainer = POI.isContainer, isEvent = POI.isEvent }
end

local function Dress(icon, POI)
	local W = MelloUI.Widgets
	local d = S.dressed[icon]
	if not d then
		d = {}
		d.plate = icon:CreateTexture(nil, "OVERLAY", nil, 5)
		d.core = icon:CreateTexture(nil, "OVERLAY", nil, 6)
		d.emblem = icon:CreateTexture(nil, "OVERLAY", nil, 7)
		for _, t in ipairs({ d.plate, d.core, d.emblem }) do
			t:SetPoint("CENTER", icon, "CENTER", 0, 0)
		end
		S.dressed[icon] = d
	end
	local s = T.MINI
	local state, kind = RL.State(POI), RL.Kind(POI)
	local key, rgb = Rim(state)
	d.plate:SetSize(s, s)
	MelloUI.Icons.Set(d.plate, T.PLATE, s)
	if key then
		W.Paint(d.plate, key, "vertex")
	else
		local P = rawget(MelloUI, "Painter")
		if P and P.Unpaint then
			P.Unpaint(d.plate, "vertex")
		end
		d.plate:SetVertexColor(rgb[1], rgb[2], rgb[3])
	end
	local r = math.max(1, math.floor(T.RIM_PX * s / T.SIZE + 0.5))
	d.core:SetSize(s - 2 * r, s - 2 * r)
	MelloUI.Icons.Set(d.core, T.PLATE, s - 2 * r)
	W.Paint(d.core, T.CORE, "vertex")
	d.emblem:SetSize(s - 2 * r, s - 2 * r)   -- (as the sketch: the icon as big as the core)
	MelloUI.Icons.Set(d.emblem, T.EMBLEM[kind], s - 2 * r)
	local a = state == "done" and T.DONE or 1
	for _, t in ipairs({ d.plate, d.core, d.emblem }) do
		t:SetAlpha(a)
		t:Show()
	end
	-- (its own pictures out of sight, its frame -- its tooltip and click -- as it is)
	for _, part in ipairs(T.PARTS) do
		local p = rawget(icon, part)
		if p and p.SetAlpha then
			p:SetAlpha(0)
		end
	end
end

-- (2.1.50) RareScanner's own pictures back: the big map shows its own (MelloUI's map off)
local function Undress(icon)
	local d = S.dressed[icon]
	if not (d and d.plate:IsShown()) then
		return
	end
	for _, t in ipairs({ d.plate, d.core, d.emblem }) do
		t:Hide()
	end
	for _, part in ipairs(T.PARTS) do
		local p = rawget(icon, part)
		if p and p.SetAlpha then
			p:SetAlpha(1)
		end
	end
end

local function Lay(icon, POI, look)
	if look then
		Dress(icon, Shown(icon, POI))
	else
		Undress(icon)
	end
end

local OnMinimapIcon = Perf.Shared("HereBeDragons-Pins AddMinimapIconMap (RareScanner's icons dressed)",
	function(_, _, icon)
		local POI = Ours(icon)
		if POI then
			Lay(icon, POI, RL.MapLook())
		end
	end)

-- (2.1.50) every RareScanner icon on the minimap laid again -- the ones it laid before the hook, and on MelloUI's map
-- switched on or off -- from the pins library's own list of its minimap icons
function RL.Relay()
	local list = S.pins and rawget(S.pins, "minimapPins")
	if type(list) ~= "table" then
		return
	end
	local look = RL.MapLook()
	for icon in pairs(list) do
		local POI = Ours(icon)
		if POI then
			Lay(icon, POI, look)
		end
	end
end

-- (2.1.50) the pins library hooked as soon as RareScanner has loaded, before its first minimap pins: it lays them from
-- a ticker begun as it loads and, in the same zone, never again until the zone changes -- a hook at PLAYER_LOGIN came
-- after them, and they kept RareScanner's own pictures after a /reload (wowsim, 2026-11-13). Hooked again should a
-- newer copy of the library, loaded later, have replaced the hooked function
local function Hook()
	local LibStub = rawget(_G, "LibStub")
	local okP, pins = pcall(LibStub, "HereBeDragons-Pins-2.0", true)
	if not (okP and type(pins) == "table" and type(pins.AddMinimapIconMap) == "function") then
		return
	end
	if S.pins == pins and S.hooked == pins.AddMinimapIconMap then
		return
	end
	hooksecurefunc(pins, "AddMinimapIconMap", OnMinimapIcon)
	S.pins, S.hooked = pins, pins.AddMinimapIconMap
end

--------------------------------------------------------------------------------
-- Its alert: switched off once; its finds Rare Alert's too
--------------------------------------------------------------------------------

-- (the user: "Yes, switch it off once") RareScanner's alert button off, once: Rare Alert is MelloUI's (the Widgets
-- module keeps that it was done: a player who switches it on again in RareScanner keeps it)
function RL.AlertOffOnce()
	local widgets = MelloUI.GetModuleDB and MelloUI:GetModuleDB("Widgets")
	if type(widgets) ~= "table" or widgets.rareScannerAlertOff then
		return
	end
	local addon = Addon()
	local db = addon and addon.db
	local profile = type(db) == "table" and db.profile
	local display = type(profile) == "table" and profile.display
	if type(display) ~= "table" then
		return
	end
	display.displayButton = false
	widgets.rareScannerAlertOff = true
end

-- a find RareScanner reports (its DisplayMessages: the entity, its name): a rare's sighting for Rare Alert, its place
-- from RareScanner's own map of your zone; a treasure or an event left to RareScanner
local function Found(entityID, name)
	entityID = Finite(entityID)
	name = Text(name)
	local widgets = MelloUI.GetModule and MelloUI:GetModule("Widgets")
	if not (entityID and name and widgets and widgets.RareSpot) then
		return
	end
	local okM, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	mapID = okM and Finite(mapID) or nil
	for _, POI in ipairs(mapID and RL.POIs(mapID) or {}) do
		local list = POI.isGroup and type(POI.POIs) == "table" and POI.POIs or { POI }
		for _, p in ipairs(list) do
			if Finite(p.entityID) == entityID then
				if not p.isNpc then
					return
				end
				widgets:RareSpot("rare", name, entityID, Finite(p.mapID) or mapID, Finite(p.x), Finite(p.y))
				return
			end
		end
	end
end
RL.Found = Found

--------------------------------------------------------------------------------
-- Login
--------------------------------------------------------------------------------

local login = CreateFrame("Frame")
login:RegisterEvent("ADDON_LOADED")
login:RegisterEvent("PLAYER_LOGIN")
Perf.SetScript(login, "OnEvent", function(self, event, addon)
	if event == "ADDON_LOADED" then
		-- (2.1.50) the minimap's hook as RareScanner loads (Hook)
		if addon == "RareScanner" then
			self:UnregisterEvent("ADDON_LOADED")
			if RL.On() then
				Hook()
			end
		end
		return
	end
	self:UnregisterAllEvents()
	if not RL.On() then
		return
	end
	Hook()
	RL.Relay()
	MelloUI:On("module", function(module)
		if module == "Map" then
			RL.Relay()
		end
	end, "RareScannerLook")
	local button = rawget(_G, "RARESCANNER_BUTTON")
	if type(button) == "table" and type(button.DisplayMessages) == "function" then
		hooksecurefunc(button, "DisplayMessages", function(_, entityID, name)
			if not (Secret(entityID) or Secret(name)) then
				Found(entityID, name)
			end
		end)
	end
	RL.AlertOffOnce()
end)

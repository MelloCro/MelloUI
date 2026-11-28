--------------------------------------------------------------------------------
-- MelloUI - Integrations (2.1.44; the user, 2026-11-11: "the best approach for us would be to have our core
-- features ... but to focus on other addon integration from now on", then the Addons page sketch,
-- BuildData/output/addons_page_sketch: "Looks good").
-- The one list of the addons MelloUI works with: what MelloUI does with each, its link, where its settings are, what
-- MelloUI changed in it once (each with its way back), its parts' health, and one switch each, "Use with MelloUI"
-- (MelloUIDB.integrations[key] = false: off; on until switched), read where MelloUI meets that addon (I.Use(key)):
-- Questie in Core/QuestSource.lua, Core/QuestieLook.lua, MelloUI_Map/MapAddonPins.lua and Modules/Nameplates.lua;
-- RareScanner in Core/RareScannerLook.lua; Polestar in Core/Overlaps.lua; GatherMate2 and HandyNotes in
-- MapAddonPins' sources; HandyNotes: NPCs (Forever) in MelloUI_Map/MapTownMarks.lua (2.1.53); the guides (RestedXP, Zygor, TomTom, Polestar's) in MelloUI_Route/Guides.lua; Clique in
-- MelloUI:ClickCast; SharedMedia in Core/SharedMedia.lua (2.1.45: the sounds too); the bag addons in Core/Overlaps.lua's
-- "bags" job (2.1.49: MelloUI's bag window steps aside); AHledger's auction prices in Modules/Discard.lua (2.1.50);
-- ManaRise in Modules/ManaRise.lua (2.1.71: MelloUI's action buttons handed to it); Spoken in Core/Spoken.lua (2.1.96:
-- Voice Over, the quest log, the tracker's menu and Dungeon Info through it). Off, MelloUI leaves that addon alone (its look, its data, its settings) from the next /reload --
-- but two quest trackers never show at once (Core/Overlaps.lua's questTracker stays).
-- Shown by the configurator's Addons page (Core/AddonsPage.lua). Nothing at login: read when asked.
--   I.GROUPS, I.LIST, I.ByKey     the addons by group, in the page's order
--   I.Use(key) -> bool            its switch (an unknown key: on)
--   I.SetUse(key, on)             the switch set; the /reload it needs asked (MelloUI:AskReload)
--   I.Installed(e) -> folder|nil  the first of its folders loaded
--   I.Version(e) -> text|nil      that folder's Version, plain
--   I.Status(e) -> state, why     "working" | "partly" (why: the parts MelloUI could not read) | "off" (switched off)
--   I.Changed(e) -> list          what MelloUI changed in it once: { label, off (still as MelloUI left it), Undo }
--   I.Jobs() -> rows              who does what now: { job, by, note }
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Plain = MelloUI.Safe.Value

local I = {}
MelloUI.Integrations = I

local function Loaded(folder)
	local fn = C_AddOns and C_AddOns.IsAddOnLoaded
	if not fn then
		return false
	end
	local ok, on = pcall(fn, folder)
	return ok and Plain(on) == true
end

local function Ace(name)
	local LibStub = rawget(_G, "LibStub")
	local okA, ace = pcall(LibStub, "AceAddon-3.0", true)
	if not (okA and type(ace) == "table") then
		return nil
	end
	local ok, addon = pcall(ace.GetAddon, ace, name, true)
	return ok and type(addon) == "table" and addon or nil
end

local function Global(name)
	local v = rawget(_G, name)
	return type(v) == "table" and v or nil
end

local function QuestieProfile()
	local Q = Global("Questie")
	local db = Q and rawget(Q, "db")
	local profile = type(db) == "table" and db.profile
	return type(profile) == "table" and profile or nil
end

local function ModuleDB(name)
	local m = MelloUI.modules and MelloUI.modules[name]
	return type(m) == "table" and type(m.db) == "table" and m.db or nil
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

I.GROUPS = {
	{ key = "quests", name = "Quests and guides" },
	{ key = "map", name = "Map and minimap" },
	{ key = "frames", name = "Frames" },
	{ key = "look", name = "Look and sound" },
	{ key = "bags", name = "Bags" },
}

-- (2.1.49) the bag addons' lines: one for all of them
local BAG_DOES = { "Its bag window shows your bags: MelloUI's bag window and its bank by kind step aside while it runs, so B opens one bag window." }
local BAG_SHORT = "Its bags in place of MelloUI's bag window"
local BAG_LINKS = { { "MelloUI Bag Window", id = "BagWindow.columns" } }
-- (2.1.54; the user: "leveling addons have buttons to go back to certain stepps and skip some") every guide whose
-- steps show on the Quest Tracker: its own step back and skip on two arrows in its heading (MelloUI_Route/Guides.lua)
local STEP_BUTTONS = "Back and Skip arrows in its heading on the Quest Tracker run the guide's own step back and skip."

-- (2.1.52) needed (what is missing without it: its card shown on the Installed tab even while it is not installed),
-- use (its switch's own name, in place of Use with MelloUI), offPill / offLine (its state with the switch off)
-- an addon: key (its switch's key), name, folders (any one loaded: installed), group, url (its page: the configurator
-- opens no web page, its copy box does), switch (false: nothing of MelloUI's to switch off -- it only stays clear),
-- does (what MelloUI does with it, a line each), short (the Compatibility tab's one line), links (its settings in
-- MelloUI: { label, id = an option's "Module.key" | map = true: the map's layers }), parts ({ name, Check }),
-- changed (fn -> the list I.Changed hands out), arrow (2.1.51: a guide Route follows, by its reader's key in
-- MelloUI_Route/Guides.lua: its card's switch, its own arrow shown beside the World Marker -- Guide.ArrowShown),
-- noSwitch (with switch = false: the card's own line in place of "Nothing to switch")
I.LIST = {
	-- (2.1.52, stage 2; the user, 2026-11-14: "Current and Future addons are the Engine, MelloUI Provides the Look")
	-- MelloUI has no quest data of its own: the quests are Questie's (Core/QuestSource.lua's three states). Its card
	-- stands first on the Installed tab even while it is not installed (`needed`); its switch is the look only (`use`),
	-- and off is a state of its own, Questie's look (`offPill`, `offLine`), never "MelloUI leaves it alone"
	{ key = "Questie", name = "Questie", folders = { "Questie" }, group = "quests",
	  url = "https://www.curseforge.com/wow/addons/questie",
	  needed = "Quests on the map and minimap, the Quest List and Route to a quest come from Questie.",
	  use = "MelloUI's look",
	  offPill = "Questie's look",
	  offLine = "Questie shows its own icons and its own tracker, on MelloUI's map too. MelloUI's Quest List and Route to a quest still use its quest data.",
	  does = {
		"Its quest data feeds MelloUI's Quest List, map marks and Route.",
		"Its icons and its tracker wear MelloUI's look.",
		-- (2.1.53; the user: "Yes, write them") Core/QuestieLook.lua's Apply / Give
		"Its tracker follows the Quest Tracker page's width, height, text sizes, Nearest Quest First and Reset Position; its own come back with the look off.",
		"Leveling guide steps dock under its tracker, and stand on their own while it has no quest.",
		-- (2.1.58) one owner for the quest lines in tooltips (Core/Overlaps.lua)
		"Its quest lines in tooltips are the ones: Polestar's on creatures and objects and MelloUI's own on items step aside.",
	  },
	  short = "Its quest data for MelloUI's quests; its icons and its tracker in MelloUI's look",
	  links = { { "Quest List > Map", id = "QuestList.mapPins" }, { "Quest Tracker", id = "QuestTracker.showXP" },
		{ "Nameplates > Quest Icon", id = "Nameplates.questIcon" }, { "Map layers", map = true } },
	  parts = {
		{ "its quest database", function()
			local QS = rawget(MelloUI, "QuestSource")
			return not (QS and QS.Lib) or QS.Lib() ~= nil
		end },
		{ "its icons", function()
			local QL = rawget(MelloUI, "QuestieLook")
			local names = QL and QL.TypeNames and QL.TypeNames()
			return type(names) == "table" and next(names) ~= nil
		end },
	  },
	  changed = function()
		local out, profile = {}, QuestieProfile()
		local np = ModuleDB("Nameplates")
		if np and np.questieIconsOff and profile then
			out[#out + 1] = { label = "Nameplate quest icons", off = Plain(profile.nameplateEnabled) == false,
				Undo = function()
					profile.nameplateEnabled = true
				end }
		end
		local qt = ModuleDB("QuestTracker")
		if qt and qt.questieInstancesOpen and profile then
			out[#out + 1] = { label = "Minimize tracker in dungeons", off = Plain(profile.minimizeTrackerInInstances) == false,
				Undo = function()
					profile.minimizeTrackerInInstances = true
					local QL = Global("QuestieLoader")
					local okT, QT = pcall(function()
						return QL and QL:ImportModule("QuestieTracker")
					end)
					local changed = okT and type(QT) == "table" and rawget(QT, "OnMinimizeInInstancesChanged")
					if type(changed) == "function" then
						pcall(changed, true)
					end
				end }
		end
		return out
	  end },
	{ key = "MaxDps", name = "MaxDPS", folders = { "MaxDps" }, group = "frames",
	  url = "https://www.curseforge.com/wow/addons/maxdps-rotation-helper",
	  does = { "Its spell recommendations highlight MelloUI's action buttons, including the controller's display buttons." },
	  short = "Spell recommendations on MelloUI's action bars",
	  -- (2.1.52, PR #18: Modules/MaxDps.lua hooks its AddButton and asks its ButtonFetch -- both there: working)
	  parts = { { "its spell highlights", function()
		local m = Global("MaxDps")
		return type(m) == "table" and type(m.AddButton) == "function" and type(m.ButtonFetch) == "function"
	  end } },
	},
	{ key = "RestedXP", name = "RestedXP Guide", folders = { "RXPGuides" }, group = "quests", arrow = "rxp",
	  url = "https://www.curseforge.com/wow/addons/restedxp-guide",
	  does = { "Route follows the guide's steps, and its steps show on MelloUI's Quest Tracker (its own step frame hidden).", STEP_BUTTONS },
	  short = "Its steps on the tracker; Route follows them",
	  links = { { "Quest Tracker", id = "QuestTracker.showXP" } },
	  parts = { { "its guide", function()
		return Global("RXP") ~= nil
	  end } } },
	{ key = "Zygor", name = "Zygor Guides", folders = { "ZygorGuidesViewerForever", "ZygorGuidesViewer" }, group = "quests",
	  arrow = "zygor", url = "https://zygorguides.com",
	  does = { "Route follows the guide's steps, and its steps show on MelloUI's Quest Tracker (its own step frame hidden).", STEP_BUTTONS },
	  short = "Its steps on the tracker; Route follows them",
	  links = { { "Quest Tracker", id = "QuestTracker.showXP" } },
	  parts = { { "its guide", function()
		return (Global("ZGV") or Global("ZygorGuidesViewer")) ~= nil
	  end } } },
	{ key = "Polestar", name = "Polestar", folders = { "Polestar" }, group = "quests", arrow = "polestar",
	  url = "https://github.com/fitzforge/polestar",
	  does = { "The jobs it does while its own switches are on go before MelloUI's (Who does what lists them).",
		"Route follows its guide's steps.", STEP_BUTTONS,
		-- (2.1.58) Core/Overlaps.lua's QuestLines
		"With Questie, its quest lines on creatures and objects are left out: Questie writes them." },
	  short = "Its jobs go before MelloUI's; Route follows its guide",
	  links = {},
	  parts = { { "its settings", function()
		local P = Global("Polestar")
		return P ~= nil and type(rawget(P, "Get")) == "function"
	  end } } },
	{ key = "TomTom", name = "TomTom", folders = { "TomTom" }, group = "quests", arrow = "tomtom",
	  url = "https://www.curseforge.com/wow/addons/tomtom",
	  does = { "Route follows its waypoint arrow." },
	  short = "Route follows its waypoints",
	  links = {},
	  parts = { { "its arrow", function()
		local T = Global("TomTom")
		return T ~= nil and type(T.SetCrazyArrow) == "function"
	  end } } },
	-- (2.1.51; the user: "we didnt add under 'Addons' category, all the Different Leveling Addons that we provide
	-- Compatibility with") the guides Route follows since 1.2.0 (MelloUI_Route/Guides.lua), links from CurseForge
	{ key = "FollowTheArrow", name = "Follow The Arrow", folders = { "FollowTheArrow" }, group = "quests", arrow = "fta",
	  url = "https://www.curseforge.com/wow/addons/follow-the-arrow",
	  does = { "Route follows the guide's steps, and its steps show on MelloUI's Quest Tracker (its own step frame hidden).", STEP_BUTTONS },
	  short = "Its steps on the tracker; Route follows them",
	  links = { { "Quest Tracker", id = "QuestTracker.showXP" } },
	  parts = { { "its guide", function()
		local F = Global("FollowTheArrow")
		return F ~= nil and type(F.On) == "function"
	  end } } },
	{ key = "APR", name = "Azeroth Pilot Reloaded", folders = { "APR" }, group = "quests", arrow = "apr",
	  url = "https://www.curseforge.com/wow/addons/azeroth-pilot-reloaded",
	  does = { "Route follows the guide's steps, and its steps show on MelloUI's Quest Tracker (its own step frame hidden).", STEP_BUTTONS },
	  short = "Its steps on the tracker; Route follows them",
	  links = { { "Quest Tracker", id = "QuestTracker.showXP" } },
	  parts = { { "its guide", function()
		local A = Global("APR")
		return A ~= nil and type(rawget(A, "currentStep")) == "table"
	  end } } },
	{ key = "Guidelime", name = "Guidelime", folders = { "Guidelime" }, group = "quests", switch = false,
	  url = "https://www.curseforge.com/wow/addons/guidelime",
	  does = { "With its own Use TomTom arrow option on, Route follows its steps through TomTom's arrow (TomTom's card shows that arrow or not)." },
	  short = "Route follows its steps through TomTom", links = {},
	  noSwitch = "Followed through TomTom: TomTom's card switches it, and shows its arrow or not." },
	-- (2.1.51; the user installed it) FlowUp keeps its steps to itself: Route follows the game's map pin it lays; its
	-- arrow is part of its own window (drawn every frame), so MelloUI leaves it to FlowUp's own Arrow option
	{ key = "FlowUp", name = "FlowUp", folders = { "FlowUp" }, group = "quests", switch = false,
	  url = "https://flowup-wow.com",
	  does = { "Route follows the map pin it lays for each step, so MelloUI's route and World Marker lead there.",
		"Its steps and arrow stay in its own window (it keeps its steps to itself); its own Arrow option shows its arrow or not.",
		"With another leveling guide loaded too, MelloUI asks at login which one to keep." },
	  short = "Route follows the map pins it lays", links = {},
	  noSwitch = "Route follows any map pin, FlowUp's too: nothing of MelloUI's to switch off." },
	{ key = "RareScanner", name = "RareScanner", folders = { "RareScanner" }, group = "map",
	  url = "https://www.curseforge.com/wow/addons/rarescanner",
	  does = { "Its rares, treasures and events on MelloUI's map and minimap, as MelloUI's icons on a plate.",
		"The rares it finds come up on Rare Alert, with where they are.",
		"One addon draws the rares: while it shows them, other addons' rare marks are not drawn too, on MelloUI's map and the minimap." },
	  short = "Its finds in MelloUI's look, and on Rare Alert",
	  links = { { "Quality of Life > Widgets", id = "Widgets.rare" }, { "Map layers", map = true } },
	  parts = {
		{ "its map data", function()
			return type(rawget(_G, "RareScannerDataProviderMixin")) == "table"
		end },
		{ "its finds", function()
			local b = Global("RARESCANNER_BUTTON")
			return b ~= nil and type(b.DisplayMessages) == "function"
		end },
	  },
	  changed = function()
		local out = {}
		local w = ModuleDB("Widgets")
		local addon = Ace("RareScanner")
		local db = addon and addon.db
		local display = type(db) == "table" and type(db.profile) == "table" and db.profile.display
		if w and w.rareScannerAlertOff and type(display) == "table" then
			out[#out + 1] = { label = "Its alert button", off = Plain(display.displayButton) == false,
				Undo = function()
					display.displayButton = true
				end }
		end
		return out
	  end },
	{ key = "GatherMate2", name = "GatherMate2", folders = { "GatherMate2" }, group = "map",
	  url = "https://www.curseforge.com/wow/addons/gathermate2",
	  -- (2.1.72) each ore and herb its own icon (MelloUI_Map/MapAddonPins.lua, Gather.NODE)
	  does = { "Its gathering nodes on MelloUI's map and on its own minimap pins in MelloUI's icons: each ore and each herb its own (copper, iron, peacebloom ...), and one each for fishing pools and treasures." },
	  short = "Its gathering nodes in MelloUI's icons",
	  links = { { "Map layers", map = true } },
	  parts = { { "its nodes", function()
		local gm = Ace("GatherMate2")
		return gm ~= nil and type(gm.GetNodesForZone) == "function"
	  end } } },
	{ key = "HandyNotes", name = "HandyNotes", folders = { "HandyNotes" }, group = "map",
	  url = "https://www.curseforge.com/wow/addons/handynotes",
	  does = { "Its notes on MelloUI's map.",
		"A plugin's rares wear MelloUI's rare seal, on the map and the minimap. While RareScanner shows its rares, they step aside." },
	  short = "Its notes on MelloUI's map",
	  links = { { "Map layers", map = true } },
	  parts = { { "its notes", function()
		local hn = Ace("HandyNotes")
		return hn ~= nil and type(hn.plugins) == "table"
	  end } } },
	-- (2.1.53; the user, 2026-11-15: "people were asking for Important NPC locations on the Map and minimap, can we
	-- utilize HandyNotes Addon for this", "Yes, MelloUI Decides") the HandyNotes plugin with the town NPCs' places:
	-- MelloUI_Map/MapTownMarks.lua reads its places and shows them by the map's layers page's switches, in MelloUI's
	-- icons, one owner a kind across the addons. Its switch is the look only: off, it shows its own way
	{ key = "HandyNotesNPCs", name = "HandyNotes: NPCs (Forever)", folders = { "HandyNotes_NPCs_Forever" }, group = "map",
	  url = "https://www.curseforge.com/wow/addons/handynotes-npcs-forever",
	  use = "MelloUI's look",
	  offPill = "Its own look",
	  offLine = "It shows its own icons, chosen in its own menu, on MelloUI's map and on the minimap.",
	  does = {
		"Its places of the auction house, the bank, trainers, mount sellers and more on MelloUI's map and the minimap, in MelloUI's icons.",
		"The map's layers page chooses which kinds show, under HandyNotes: your side's only, and trainers of your own professions and class.",
		"One addon draws a kind of place: its places stand before Questie's innkeepers and mailboxes and other addons' pins of the same kind.",
	  },
	  short = "Its town NPC places in MelloUI's icons, chosen on the map's layers page",
	  links = { { "Map layers", map = true } },
	  parts = { { "its places", function()
		local hn = Ace("HandyNotes")
		local handler = hn and type(hn.plugins) == "table" and hn.plugins.HandyNotes_NPCs_Forever
		return type(handler) == "table" and type(handler.GetNodes2) == "function"
	  end } } },
	-- (2.1.55, docs/plans/controller-forever.md stage 1; the user, 2026-11-16) Controller Forever is the controller's
	-- engine: the two step aside for each other, each way on one of its tables (Core/ControllerForever.lua)
	{ key = "ControllerForever", name = "Controller Forever", folders = { "ControllerForever" }, group = "frames",
	  url = "https://www.curseforge.com/wow/addons/controllerforever",
	  does = { "The controller's buttons and binds are its own: MelloUI's gamepad bars are not shown while it runs.",
		"While a MelloUI window holds the controller, its bind manager gives MelloUI the buttons, so the D-pad, A and B walk MelloUI's window.",
		"Where MelloUI has the part (unit frames, party frames, minimap, chat, damage meter, bags, automatic quests) its own version steps back, and its menu says so." },
	  short = "Its buttons and binds, MelloUI's windows and frames",
	  links = {},
	  parts = {
		{ "its bind manager", function()
			local C = rawget(MelloUI, "ControllerForever")
			return C ~= nil and C.Claims() ~= false
		end },
		{ "its list of parts another addon has", function()
			local C = rawget(MelloUI, "ControllerForever")
			return C ~= nil and C.Parts() ~= nil
		end },
		{ "its healer mode's list of party frames", function()
			local C = rawget(MelloUI, "ControllerForever")
			return C ~= nil and C.Frames() ~= nil
		end },
	  } },
	-- (2.1.51; Shumi's report) Offhand keeps the game on one screen and panels on another: what centres on the character
	-- centres on its main screen (I.PlayArea); (2.1.53) THE RULE for every animation and every place by the screen's
	-- middle (I.PlayPoint, below)
	{ key = "Offhand", name = "Offhand", folders = { "Offhand" }, group = "frames",
	  url = "https://offhand-wow.onrender.com/",   -- (its TOC's X-Website)
	  does = { "The World Marker's arrow round your character, its wisp and the Level Up card's wisp center on the main screen it keeps for the game, not between your screens.",
		"Quest Moments play on that screen too, and the Level Up card, the on-screen line, Combat Text, Gains, the reminders and the Personal Display start there until you give them a place of your own." },
	  short = "MelloUI's character-centered parts on its main screen",
	  links = {},
	  parts = { { "its main screen", function()
		local O = Global("Offhand")
		local api = O and rawget(O, "API")
		return type(api) == "table" and type(api.GetMainhandFrame) == "function"
	  end } } },
	{ key = "NodeSight", name = "NodeSight", folders = { "NodeSight" }, group = "map", switch = false,
	  url = "https://www.curseforge.com/wow/addons/node-sight",
	  does = { "While it scans the minimap for herbs and ore, MelloUI keeps the minimap and what hangs on it in place." },
	  short = "The minimap stays in place while it scans", links = {} },
	-- (2.1.72; the user, 2026-11-22: "full compatibility with Lueur addon") its glow on what you walk up to: Loot
	-- Sparkles' gathering glints and their hold on soft targeting step aside (Core/Overlaps.lua, job gatherGlow)
	{ key = "Lueur", name = "Lueur", folders = { "Lueur" }, group = "map",
	  url = "https://www.curseforge.com/wow/addons/lueur",
	  does = { "Its glow on the ore, herb or quest object you walk up to: MelloUI's Loot Sparkles glints step aside while it is on, and leave the game's soft targeting settings to it.",
		"While it scans the minimap for herbs and ore, MelloUI keeps the minimap and what hangs on it in place." },
	  short = "Its glow in place of MelloUI's gathering glints",
	  links = { { "Loot Sparkles: Ore Veins", id = "Sparkles.ore" } },
	  parts = { { "its own switch", function() return Global("LueurDB") ~= nil end } } },
	-- (2.1.71; the user, 2026-11-22: "manarise addon full compatibility") its resource fill on MelloUI's own action
	-- buttons: Modules/ManaRise.lua hands them to its ManaRise_RegisterBarAddon (working while that call is there)
	{ key = "ManaRise", name = "ManaRise", folders = { "ManaRise" }, group = "frames",
	  url = "https://www.curseforge.com/wow/addons/manarise",
	  does = { "Its mana, rage and energy fill on MelloUI's action bars, including the controller's display buttons." },
	  short = "Its resource fill on MelloUI's action bars",
	  links = {},
	  parts = { { "its fill on MelloUI's action bars", function()
		return type(rawget(_G, "ManaRise_RegisterBarAddon")) == "function"
	  end } } },
	{ key = "Clique", name = "Clique", folders = { "Clique" }, group = "frames",
	  url = "https://www.curseforge.com/wow/addons/clique",
	  does = { "Its click-casting on MelloUI's unit and group frames." },
	  short = "Click-casting on MelloUI's frames",
	  links = {},
	  parts = { { "its click-casting", function()
		return rawget(_G, "ClickCastHeader") ~= nil
	  end } } },
	-- (2.1.49; pmyszczynski, GitHub issue #8: "With both enabled, pressing B shows two bag interfaces") the bag addons:
	-- while one runs, MelloUI's bag window and its bank by kind step aside (Core/Overlaps.lua's "bags" job), so B opens
	-- one bag window; its switch off, MelloUI's comes back
	{ key = "Baganator", name = "Baganator", folders = { "Baganator" }, group = "bags",
	  url = "https://www.curseforge.com/wow/addons/baganator",
	  does = BAG_DOES, short = BAG_SHORT, links = BAG_LINKS,
	  parts = { { "its bags", function() return Global("Baganator") ~= nil end } } },
	{ key = "Bagnon", name = "Bagnon", folders = { "Bagnon" }, group = "bags",
	  url = "https://www.curseforge.com/wow/addons/bagnon",
	  does = BAG_DOES, short = BAG_SHORT, links = BAG_LINKS,
	  parts = { { "its bags", function() return Global("Bagnon") ~= nil end } } },
	{ key = "ArkInventory", name = "ArkInventory", folders = { "ArkInventory" }, group = "bags",
	  url = "https://www.curseforge.com/wow/addons/ark-inventory",
	  does = BAG_DOES, short = BAG_SHORT, links = BAG_LINKS,
	  parts = { { "its bags", function() return Global("ArkInventory") ~= nil end } } },
	{ key = "BetterBags", name = "BetterBags", folders = { "BetterBags" }, group = "bags",
	  url = "https://www.curseforge.com/wow/addons/better-bags",
	  does = BAG_DOES, short = BAG_SHORT, links = BAG_LINKS,
	  parts = { { "its bags", function() return Ace("BetterBags") ~= nil or Global("BetterBags") ~= nil end } } },
	-- (2.1.50; Nixxen, 2026-11-12: "AHLedger", the user's picks of restock_discard_sketch) its auction prices in
	-- Discard, through its API (AHledgerAPI, from its 0.9.8), its credit wherever they show
	{ key = "AHledger", name = "AHledger", folders = { "AHledger" }, group = "bags",
	  url = "https://www.curseforge.com/wow/addons/ahledger",
	  does = {
		"Its auction prices in Discard: an item is worth its auction price when that is more than the vendor's, so the cheapest goes first by that worth.",
		"At a vendor, Discard's Sell skips what sells for clearly more at the auction house.",
	  },
	  short = "Its auction prices in Discard",
	  links = { { "Discard Button", id = "Discard.bagButton" } },
	  parts = { { "its prices", function()
		local api = Global("AHledgerAPI")
		return api ~= nil and type(api.GetMedian) == "function"
	  end } } },
	-- (2.1.96; the user, 2026-11-28: "can we add full integration with Spoken addon?", Spoken first) Core/Spoken.lua,
	-- through Spoken's own API for other addons (its Public calls), nothing of it hooked
	{ key = "Spoken", name = "Spoken", folders = { "Spoken" }, group = "look",
	  url = "https://www.curseforge.com/wow/addons/spoken",
	  does = { "Spoken speaks first: MelloUI's Voice Over stays quiet for quests and NPC greetings while Spoken's quests are on, and for books while its readables are on.",
		"Read on the quest log plays Spoken's recording of the quest where it has one. The Quest Tracker's right-click menu and Dungeon Info's dungeon and boss pages play its stories too.",
		"Spoken offers MelloUI as its narrator style once (also in its settings): picked, its lines show in MelloUI's Voice Over widget." },
	  short = "Its voices first; its stories from the quest log, tracker and Dungeon Info",
	  links = { { "Voice Over", id = "VoiceOver.questDetail" } },
	  parts = { { "its API", function()
		local S = Global("Spoken")
		if not (S and type(S.IsCompatible) == "function") then
			return false
		end
		local ok, yes = pcall(S.IsCompatible, S, 1)
		return ok and yes == true
	  end }, { "its stories", function()
		local S = Global("Spoken")
		return S ~= nil and type(S.HasStory) == "function" and type(S.PlayStory) == "function"
			and type(S.StopStory) == "function"
	  end } } },
	-- (2.1.32 read its media; 2.1.45, Custom Sounds' Your Sounds: its sounds, the player's own files through the
	-- MelloUI_MySounds template, docs/custom-sounds.md) the library any pack brings: working while it is found
	{ key = "SharedMedia", name = "SharedMedia", folders = { "SharedMedia" }, group = "look",
	  url = "https://www.curseforge.com/wow/addons/sharedmedia",
	  does = {
		"Its fonts, bar textures, backgrounds and borders in MelloUI's lists, and those of any pack that shares them.",
		"Its sounds in Custom Sounds' Your Sounds lists, your own files too (the MelloUI_MySounds guide).",
	  },
	  short = "Its fonts, textures and sounds in MelloUI's lists",
	  links = { { "Fonts", id = "Fonts.style" }, { "Bar textures", id = "BarTextures.texture" },
		{ "Your Sounds", id = "CustomSounds.yours" } },
	  parts = { { "the shared media library", function()
		local SM = rawget(MelloUI, "SharedMedia")
		return not (SM and SM.Find) or SM.Find() ~= nil
	  end } } },
}
I.ByKey = {}
for _, e in ipairs(I.LIST) do
	I.ByKey[e.key] = e
end

--------------------------------------------------------------------------------
-- The switch, the facts
--------------------------------------------------------------------------------

-- the saved settings as the core holds them (2.1.52): MelloUI.db -- the saved variable itself, or in a new player's
-- first session the table the logout hands the client, while the global is still nil (the switches saved nothing
-- then and stayed on: wowsim's fresh login, 2026-11-14). A world without the core's: the global
local function DB()
	local db = MelloUI.db
	if type(db) ~= "table" then
		db = rawget(_G, "MelloUIDB")
	end
	return type(db) == "table" and db or nil
end

local function Store()
	local db = DB()
	if not db then
		return nil
	end
	if type(db.integrations) ~= "table" then
		db.integrations = {}
	end
	return db.integrations
end

-- (2.1.51; Shumi, Discord: with Offhand's two screens "the route arrow ... is centered between the two screens instead
-- of being centered on my character") where the game's world is drawn, in UIParent's units -> left, bottom, width,
-- height: Offhand's main screen (its OffhandMainhandFrame, Offhand.API.GetMainhandFrame) while Offhand runs with its
-- switch on, else UIParent whole. What centres on the character reads it: the World Marker's ring and wisp
-- (MelloUI_Route), the Level Up card's wisp (Core/LevelCard.lua)
--
-- THE RULE (2.1.53; the user, 2026-11-15, after the Quest Moments played between the screens: "we have fixed that
-- but we didnt make it a rule for future animations to follow the same rule"): whatever MelloUI places by the
-- screen's middle -- a moment's animation, what centres on the character, an element's place before the player gave
-- it one -- goes by the GAME'S SCREEN, never by the whole UI's middle (with Offhand the UI spans two screens and its
-- middle is the gap between them):
--   I.PlayArea()                          the rect, for a place that is worked out (a moment's middle)
--   I.PlayPoint(frame, point, rel, x, y)  an anchor: `point` of the frame on the game's screen's `rel`, x, y from it
-- Tools/lint/check_panels.py's "screen-middle" counts the code that still goes by the whole UI's middle (windows,
-- the HUD's bars); one more fails the check.
local function OffhandAPI()
	local O = Global("Offhand")
	local api = O and rawget(O, "API")
	if type(api) == "table" and type(api.GetMainhandFrame) == "function" and I.Use("Offhand") then
		return api
	end
	return nil
end

function I.PlayArea()
	local W, H = UIParent:GetWidth(), UIParent:GetHeight()
	local api = OffhandAPI()
	if api then
		local ok, f = pcall(api.GetMainhandFrame)
		if ok and type(f) == "table" and f.GetRect then
			local okR, l, b, w, h = pcall(f.GetRect, f)
			local Finite = MelloUI.Safe.Finite
			l, b, w, h = okR and Finite(l), okR and Finite(b), okR and Finite(w), okR and Finite(h)
			if l and b and w and h and w > 0 and h > 0 then
				return l, b, w, h
			end
		end
	end
	return 0, 0, W, H
end

-- a point's share of a rect's width and height, from its bottom left
local SHARE_X = { LEFT = 0, TOPLEFT = 0, BOTTOMLEFT = 0, CENTER = 0.5, TOP = 0.5, BOTTOM = 0.5, RIGHT = 1, TOPRIGHT = 1,
	BOTTOMRIGHT = 1 }
local SHARE_Y = { BOTTOM = 0, BOTTOMLEFT = 0, BOTTOMRIGHT = 0, CENTER = 0.5, LEFT = 0.5, RIGHT = 0.5, TOP = 1, TOPLEFT = 1,
	TOPRIGHT = 1 }
-- [frame] = { point, rel, x, y; at = where it was put }: placed by I.PlayPoint while Offhand runs, for Offhand's
-- next layout of its main screen (it lays it after the login, and again as its screens or the UI's scale change)
local placed = setmetatable({}, { __mode = "k" })
local listening = false

-- on UIParent always: on its own point while the game's screen is the UI whole (as without Offhand: it follows the
-- UI's size by itself), else by the screen's rect from the UI's bottom left -- never on Offhand's own frame, which a
-- secure frame hung on it would tie down
local function LayPoint(frame, p)
	local l, b, w, h = I.PlayArea()
	frame:ClearAllPoints()
	local at = p.at
	if l == 0 and b == 0 and w == UIParent:GetWidth() and h == UIParent:GetHeight() then
		at[1], at[2], at[3] = p[2], p[3], p[4]
	else
		at[1], at[2], at[3] = "BOTTOMLEFT", l + w * SHARE_X[p[2]] + p[3], b + h * SHARE_Y[p[2]] + p[4]
	end
	frame:SetPoint(p[1], UIParent, at[1], at[2], at[3])
end

-- Offhand laid its main screen anew: each frame still standing where PlayPoint put it, put again; one that was
-- moved since (the player's drag, a saved place) is let go
local function LayAgain()
	local Finite = MelloUI.Safe.Finite
	for frame, p in pairs(placed) do
		local ok, point, relTo, rel, x, y = pcall(frame.GetPoint, frame, 1)
		x, y = ok and Finite(x), ok and Finite(y)
		local at = p.at
		if ok and frame:GetNumPoints() == 1 and point == p[1] and relTo == UIParent and rel == at[1] and x and y
			and math.abs(x - at[2]) < 0.5 and math.abs(y - at[3]) < 0.5 then
			LayPoint(frame, p)
		else
			placed[frame] = nil
		end
	end
end

local function OnGeometry()
	-- (a secure frame is only placed out of a fight: Core/Schedule.lua's queue)
	MelloUI.Schedule:WhenOutOfCombat(LayAgain, "Integrations.PlayPoint")
end

function I.PlayPoint(frame, point, rel, x, y)
	rel, x, y = rel or point, x or 0, y or 0
	local api = OffhandAPI()
	if not api then
		frame:ClearAllPoints()
		frame:SetPoint(point, UIParent, rel, x, y)
		return
	end
	local p = { point, rel, x, y, at = {} }
	LayPoint(frame, p)
	placed[frame] = p
	if not listening and type(api.RegisterGeometryCallback) == "function" then
		local ok, kept = pcall(api.RegisterGeometryCallback, "MelloUI", OnGeometry)
		listening = ok and kept == true
	end
end

function I.Use(key)
	local db = DB()
	local t = db and db.integrations
	return not (type(t) == "table" and t[key] == false)
end

local RELOAD = "Type /reload to finish switching %s."
function I.SetUse(key, on)
	local t = Store()
	if not t or (t[key] ~= false) == (on and true or false) then
		return
	end
	if on then
		t[key] = nil
	else
		t[key] = false
	end
	local e = I.ByKey[key]
	MelloUI:AskReload(MelloUI.Lang.F(RELOAD, e and e.name or key))
end

-- (2.1.52, stage 2) a needed addon's card (the map's layers page and the Quest List without Questie: Get Questie):
-- the Addons page on its Installed tab, at its top -- the needed addons' cards stand first there, installed or not
-- (Core/AddonsPage.lua). The button's words: Get <its name>
-- (2.1.53) `key`: an addon that is not installed and has no card of its own there (not `needed`: the town marks'
-- plugin) is on the Compatibility tab, with its link
function I.Open(key)
	local e = key and I.ByKey[key]
	MelloUI:OpenConfig((e and not e.needed and not I.Installed(e)) and "compatibility" or "installed addons")
	local okT, tour = pcall(MelloUI.ConfigTour, MelloUI)
	local page = okT and type(tour) == "table" and type(tour.page) == "function" and tour.page("Addons")
	if type(page) == "table" and page.pager and page.pager.ScrollTo then
		page.pager:ScrollTo(0, true)
	end
end

function I.GetLabel(key)
	local e = I.ByKey[key]
	return MelloUI.Lang.F("Get %s", e and e.name or key)
end

function I.Installed(e)
	for _, folder in ipairs(e.folders) do
		if Loaded(folder) then
			return folder
		end
	end
	return nil
end

function I.Version(e)
	local folder = I.Installed(e)
	local get = folder and C_AddOns and C_AddOns.GetAddOnMetadata
	if not get then
		return nil
	end
	local ok, v = pcall(get, folder, "Version")
	v = ok and MelloUI.Safe.Text(v) or nil
	if not v then
		return nil
	end
	v = v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s*[vV]", ""):gsub("%s+$", "")
	return v ~= "" and v or nil
end

function I.Status(e)
	if e.switch ~= false and not I.Use(e.key) then
		return "off"
	end
	local broken
	for _, part in ipairs(e.parts or {}) do
		local ok, fine = pcall(part[2])
		if not (ok and fine) then
			broken = broken and (broken .. ", " .. MelloUI.Lang.T(part[1])) or MelloUI.Lang.T(part[1])
		end
	end
	if broken then
		return "partly", broken
	end
	return "working"
end

function I.Changed(e)
	if type(e.changed) ~= "function" then
		return {}
	end
	local ok, list = pcall(e.changed)
	return ok and type(list) == "table" and list or {}
end

--------------------------------------------------------------------------------
-- Who does what (Core/Overlaps.lua's jobs, read live, and what the integrations settle)
--------------------------------------------------------------------------------

local function By(job)
	local OV = rawget(MelloUI, "Overlaps")
	local ok, who = pcall(function()
		return OV and OV.By(job)
	end)
	return ok and who or nil
end

local function Used(key)
	local e = I.ByKey[key]
	return e and I.Installed(e) and I.Use(key) and true or false
end

local POLESTAR_JOBS = {
	{ "Objective marks on the minimap", "minimapObjectives" },
	{ "Quest icons on nameplates", "nameplateQuest" },
	{ "Quest items in tooltips", "questItemTips" },
	{ "Accepting quests", "accept" },
	{ "Handing in quests", "turnIn" },
	{ "Picking quest rewards", "rewardPick" },
	{ "Selling junk", "sellJunk" },
	{ "Repairing", "repair" },
	{ "The way back to your corpse", "corpse" },
	{ "Flight helper", "flightHelp" },
}

function I.Jobs()
	local rows = {}
	local questie = Used("Questie")
	if By("questTracker") == "Questie" then
		rows[#rows + 1] = { "Quest tracker", "Questie's tracker, in MelloUI's look", "MelloUI's own tracker steps aside" }
	else
		rows[#rows + 1] = { "Quest tracker", "MelloUI's Quest Tracker" }
	end
	-- (2.1.52, stage 2) the quests on the maps are Questie's: none without it, its own icons with its switch off
	local QS = rawget(MelloUI, "QuestSource")
	local quests = QS and QS.State and QS.State() or "none"
	rows[#rows + 1] = { "Quest givers and objective marks on the maps",
		quests == "look" and "Questie's quest data, in MelloUI's look"
			or (quests == "questie" and "Questie, in its own look" or "Not shown (Questie adds them)") }
	rows[#rows + 1] = { "Flight masters on MelloUI's map", "MelloUI",
		questie and "Questie's hidden while the Flight masters layer is on" or nil }
	-- (2.1.53) the town NPCs' places: one owner a kind (MelloUI_Map/MapTownMarks.lua)
	local places = Used("HandyNotes") and Used("HandyNotesNPCs")
	local installed = I.Installed(I.ByKey.Questie) ~= nil
	rows[#rows + 1] = { "Auction houses, banks, trainers, inns and mailboxes on the maps",
		places and "HandyNotes: NPCs (Forever), in MelloUI's icons"
			or (installed and "Questie's innkeepers and mailboxes" or "Not shown (HandyNotes: NPCs (Forever) adds them)"),
		places and installed and "Questie's of the same kinds hidden on MelloUI's map" or nil }
	if By("rare") == "Polestar" then
		rows[#rows + 1] = { "Rare alerts", "Polestar", "MelloUI's Rare Alert steps aside" }
	else
		local w = ModuleDB("Widgets")
		rows[#rows + 1] = { "Rare alerts", "MelloUI's Rare Alert",
			(Used("RareScanner") and w and w.rareScannerAlertOff) and "RareScanner's own alert button switched off once" or nil }
	end
	-- (2.1.49) the bag window
	local bags = By("bags")
	rows[#rows + 1] = { "Bag window", bags or "MelloUI's Bag Window", bags and "MelloUI's bag window steps aside" or nil }
	-- (2.1.72) the glow on what you walk up to: Lueur's while it is on, else Loot Sparkles' glints (with it or
	-- Lueur there only)
	local glow = By("gatherGlow")
	local sparkles = MelloUI.modules and MelloUI.modules.Sparkles
	if glow or Used("Lueur") or (type(sparkles) == "table" and sparkles.isEnabled) then
		rows[#rows + 1] = { "Glow on the ore or herb you walk up to", glow or "MelloUI's Loot Sparkles",
			glow and "MelloUI's glints step aside" or nil }
	end
	-- (2.1.57) one owner a kind: the rares RareScanner's while it shows them (RL.Rares), a HandyNotes plugin's aside
	local RL = rawget(MelloUI, "RareScannerLook")
	local rares = Used("RareScanner")
	rows[#rows + 1] = { "Rares, treasures and events on the map",
		rares and "RareScanner's finds, in MelloUI's look" or "Not shown (RareScanner adds them)",
		(rares and Used("HandyNotes") and RL and RL.Rares and RL.Rares())
			and "Other addons' rare marks hidden on MelloUI's map and the minimap" or nil }
	local polestar = Used("Polestar")
	-- (2.1.58) one owner for a creature's and an object's quest lines: Questie's while it writes them (Overlaps'
	-- QuestLines), Polestar's of the same kind left out
	if polestar and questie then
		local OV = rawget(MelloUI, "Overlaps")
		if OV and OV.QuestLines and OV.QuestLines() then
			rows[#rows + 1] = { "Quest lines in creature and object tooltips", "Questie",
				"Polestar's of the same kind are left out" }
		elseif By("questItemTips") == "Polestar" then
			rows[#rows + 1] = { "Quest lines in creature and object tooltips", "Polestar" }
		end
	end
	for _, j in ipairs(POLESTAR_JOBS) do
		local who = By(j[2])
		if who == "Polestar" then
			rows[#rows + 1] = { j[1], "Polestar", "MelloUI's own steps aside while Polestar's switch is on" }
		elseif who == "Questie" then
			-- (2.1.58: Questie's item lines, where Polestar does not write them)
			rows[#rows + 1] = { j[1], "Questie", "MelloUI's own steps aside while Questie's tooltips are on" }
		else
			rows[#rows + 1] = { j[1], "MelloUI", polestar and "Polestar's switch for it is off" or nil }
		end
	end
	-- (2.1.55) the controller's buttons, only where the controller's engine is installed
	local C = rawget(MelloUI, "ControllerForever")
	if C and I.Installed(I.ByKey.ControllerForever) then
		if C.Used() then
			rows[#rows + 1] = { "The controller's buttons and binds", "Controller Forever", "MelloUI's gamepad bars step aside" }
		else
			rows[#rows + 1] = { "The controller's buttons and binds", "MelloUI's gamepad bars and Controller Forever's, both" }
		end
	end
	return rows
end

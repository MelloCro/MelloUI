--------------------------------------------------------------------------------
-- MelloUI - Integrations (2.1.44; the user, 2026-11-11: "the best approach for us would be to have our core
-- features ... but to focus on other addon integration from now on", then the Addons page sketch,
-- BuildData/output/addons_page_sketch: "Looks good").
-- The one list of the addons MelloUI works with: what MelloUI does with each, its link, where its settings are, what
-- MelloUI changed in it once (each with its way back), its parts' health, and one switch each, "Use with MelloUI"
-- (MelloUIDB.integrations[key] = false: off; on until switched), read where MelloUI meets that addon (I.Use(key)):
-- Questie in Core/QuestSource.lua, Core/QuestieLook.lua, MelloUI_Map/MapAddonPins.lua and Modules/Nameplates.lua;
-- RareScanner in Core/RareScannerLook.lua; Polestar in Core/Overlaps.lua; GatherMate2 and HandyNotes in
-- MapAddonPins' sources; the guides (RestedXP, Zygor, TomTom, Polestar's) in MelloUI_Route/Guides.lua; Clique in
-- MelloUI:ClickCast; SharedMedia in Core/SharedMedia.lua (2.1.45: the sounds too). Off, MelloUI leaves that addon alone (its look, its data, its settings) from the next /reload --
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
}

-- an addon: key (its switch's key), name, folders (any one loaded: installed), group, url (its page: the configurator
-- opens no web page, its copy box does), switch (false: nothing of MelloUI's to switch off -- it only stays clear),
-- does (what MelloUI does with it, a line each), short (the Compatibility tab's one line), links (its settings in
-- MelloUI: { label, id = an option's "Module.key" | map = true: the map's layers }), parts ({ name, Check }),
-- changed (fn -> the list I.Changed hands out)
I.LIST = {
	{ key = "Questie", name = "Questie", folders = { "Questie" }, group = "quests",
	  url = "https://www.curseforge.com/wow/addons/questie",
	  does = {
		"Its quest database feeds MelloUI's Quest List, map pins, objective marks and Route (MelloUI's own data fills any gaps).",
		"Its tracker wears MelloUI's look; MelloUI's own tracker steps aside (never both).",
		"Its map and minimap icons: hidden where MelloUI draws the same thing, the rest in MelloUI's pictures.",
		"Leveling guide steps dock under its tracker.",
	  },
	  short = "Its quest data for MelloUI's quests; its tracker in MelloUI's look",
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
	{ key = "RestedXP", name = "RestedXP Guide", folders = { "RXPGuides" }, group = "quests",
	  url = "https://www.curseforge.com/wow/addons/restedxp-guide",
	  does = { "Route follows the guide's steps, and its steps show on MelloUI's Quest Tracker (its own step frame hidden)." },
	  short = "Its steps on the tracker; Route follows them",
	  links = { { "Quest Tracker", id = "QuestTracker.showXP" } },
	  parts = { { "its guide", function()
		return Global("RXP") ~= nil
	  end } } },
	{ key = "Zygor", name = "Zygor Guides", folders = { "ZygorGuidesViewerForever", "ZygorGuidesViewer" }, group = "quests",
	  url = "https://zygorguides.com",
	  does = { "Route follows the guide's steps, and its steps show on MelloUI's Quest Tracker (its own step frame hidden)." },
	  short = "Its steps on the tracker; Route follows them",
	  links = { { "Quest Tracker", id = "QuestTracker.showXP" } },
	  parts = { { "its guide", function()
		return (Global("ZGV") or Global("ZygorGuidesViewer")) ~= nil
	  end } } },
	{ key = "Polestar", name = "Polestar", folders = { "Polestar" }, group = "quests",
	  url = "https://github.com/fitzforge/polestar",
	  does = { "The jobs it does while its own switches are on go before MelloUI's (Who does what lists them).",
		"Route follows its guide's steps." },
	  short = "Its jobs go before MelloUI's; Route follows its guide",
	  links = {},
	  parts = { { "its settings", function()
		local P = Global("Polestar")
		return P ~= nil and type(rawget(P, "Get")) == "function"
	  end } } },
	{ key = "TomTom", name = "TomTom", folders = { "TomTom" }, group = "quests",
	  url = "https://www.curseforge.com/wow/addons/tomtom",
	  does = { "Route follows its waypoint arrow." },
	  short = "Route follows its waypoints",
	  links = {},
	  parts = { { "its arrow", function()
		local T = Global("TomTom")
		return T ~= nil and type(T.SetCrazyArrow) == "function"
	  end } } },
	{ key = "RareScanner", name = "RareScanner", folders = { "RareScanner" }, group = "map",
	  url = "https://www.curseforge.com/wow/addons/rarescanner",
	  does = { "Its rares, treasures and events on MelloUI's map and minimap, as MelloUI's icons on a plate.",
		"The rares it finds come up on Rare Alert, with where they are." },
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
	  does = { "Its gathering nodes on MelloUI's map." },
	  short = "Its gathering nodes on MelloUI's map",
	  links = { { "Map layers", map = true } },
	  parts = { { "its nodes", function()
		local gm = Ace("GatherMate2")
		return gm ~= nil and type(gm.GetNodesForZone) == "function"
	  end } } },
	{ key = "HandyNotes", name = "HandyNotes", folders = { "HandyNotes" }, group = "map",
	  url = "https://www.curseforge.com/wow/addons/handynotes",
	  does = { "Its notes on MelloUI's map." },
	  short = "Its notes on MelloUI's map",
	  links = { { "Map layers", map = true } },
	  parts = { { "its notes", function()
		local hn = Ace("HandyNotes")
		return hn ~= nil and type(hn.plugins) == "table"
	  end } } },
	{ key = "NodeSight", name = "NodeSight", folders = { "NodeSight" }, group = "map", switch = false,
	  url = "https://www.curseforge.com/wow/addons/node-sight",
	  does = { "While it scans the minimap for herbs and ore, MelloUI keeps the minimap and what hangs on it in place." },
	  short = "The minimap stays in place while it scans", links = {} },
	{ key = "Lueur", name = "Lueur", folders = { "Lueur" }, group = "map", switch = false,
	  url = "https://www.curseforge.com/wow/addons/lueur",
	  does = { "While it scans the minimap for herbs and ore, MelloUI keeps the minimap and what hangs on it in place." },
	  short = "The minimap stays in place while it scans", links = {} },
	{ key = "Clique", name = "Clique", folders = { "Clique" }, group = "frames",
	  url = "https://www.curseforge.com/wow/addons/clique",
	  does = { "Its click-casting on MelloUI's unit and group frames." },
	  short = "Click-casting on MelloUI's frames",
	  links = {},
	  parts = { { "its click-casting", function()
		return rawget(_G, "ClickCastHeader") ~= nil
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

local function Store()
	local db = rawget(_G, "MelloUIDB")
	if type(db) ~= "table" then
		return nil
	end
	if type(db.integrations) ~= "table" then
		db.integrations = {}
	end
	return db.integrations
end

function I.Use(key)
	local db = rawget(_G, "MelloUIDB")
	local t = type(db) == "table" and db.integrations
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
	rows[#rows + 1] = { "Quest givers and objective marks on the maps", "MelloUI",
		questie and "Questie's of the same kind hidden" or nil }
	rows[#rows + 1] = { "Flight masters on MelloUI's map", "MelloUI",
		questie and "Questie's hidden while the Flight masters layer is on" or nil }
	if By("rare") == "Polestar" then
		rows[#rows + 1] = { "Rare alerts", "Polestar", "MelloUI's Rare Alert steps aside" }
	else
		local w = ModuleDB("Widgets")
		rows[#rows + 1] = { "Rare alerts", "MelloUI's Rare Alert",
			(Used("RareScanner") and w and w.rareScannerAlertOff) and "RareScanner's own alert button switched off once" or nil }
	end
	rows[#rows + 1] = { "Rares, treasures and events on the map",
		Used("RareScanner") and "RareScanner's finds, in MelloUI's look" or "Not shown (RareScanner adds them)" }
	local polestar = Used("Polestar")
	for _, j in ipairs(POLESTAR_JOBS) do
		if By(j[2]) == "Polestar" then
			rows[#rows + 1] = { j[1], "Polestar", "MelloUI's own steps aside while Polestar's switch is on" }
		else
			rows[#rows + 1] = { j[1], "MelloUI", polestar and "Polestar's switch for it is off" or nil }
		end
	end
	return rows
end

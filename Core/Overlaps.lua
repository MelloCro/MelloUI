--------------------------------------------------------------------------------
-- MelloUI - Overlaps (2.1.0; the user, 2026-10-31, on the features Polestar has
-- that MelloUI has too: "Polestar takes priority since those are its main
-- features").
--
-- Another addon doing one of MelloUI's jobs: while it does, MelloUI's part
-- steps aside. Read live from that addon's own settings each time a job is
-- asked about (never written, nothing kept), so its feature switched off gives
-- the job back to MelloUI at once. MelloUI's own options stay as they are;
-- their rows say so (the option's hint) while the addon is loaded.
--
--   O.By(job) -> name | nil         the addon doing the job now, else nil
--   O.Quest(verb, questID) -> name | nil
--                                   verb "accept" or "turnin": a quest it takes
--                                   or hands in itself now (its own switch on
--                                   and its guide wanting the quest)
--   bus "overlap" (job)             its setting for a job changed: a module
--                                   that holds what it shows reads it again
--   O.QuestLines() -> "Questie"|nil (2.1.58) Questie writes a creature's and an
--                                   object's quest lines now, Polestar's of the
--                                   same kind are left out (below)
--
-- Questie (2.1.39): its own tracker only (questTracker: MelloUI's steps aside,
-- Questie's dressed in MelloUI's look, Core/QuestieLook.lua). Its map and
-- minimap icons never take MelloUI's jobs: MelloUI's givers, objective marks
-- and quest areas stay, and Questie's icons of the same kind hide where
-- MelloUI draws them (the user, 2026-11-10: "we have lost our own function
-- which i like very much"; Core/QuestieLook.lua).
--
-- Bag addons (2.1.49; pmyszczynski, GitHub issue #8: "With both enabled, pressing B shows two bag interfaces"): the
-- "bags" job -- Baganator, Bagnon, ArkInventory or BetterBags loaded (and its Use with MelloUI switch on, the Addons
-- page): MelloUI's bag window and its bank by kind step aside (Modules/BagWindow.lua), as if switched off.
--
-- Lueur (2.1.72; the user, 2026-11-22: "full compatibility with Lueur addon"): the "gatherGlow" job -- Lueur loaded,
-- its Use with MelloUI switch on and its own switch on (LueurDB.enabled, read live): it lights the object the game's
-- soft targeting picks and holds soft targeting's settings for that, so Loot Sparkles' gathering glints and their hold
-- on the same settings step aside (Modules/Sparkles.lua). The quest item sparkle stays MelloUI's (Lueur leaves it).
--
-- Polestar 0.2.6 (its settings by path, Polestar.Get; Shift held at the
-- window skips its merchant, quest and reward automation, as its own code
-- does; its quest data's features only while Polestar_QuestDB runs).
-- Nothing at login beyond the rows' notes and one hook on its own messages,
-- both at PLAYER_LOGIN and only when it is loaded.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Overlaps")
local Plain = MelloUI.Safe.Value

local O = {}
MelloUI.Overlaps = O

local POLESTAR = "Polestar"

-- job -> its settings (every one on), shift (Shift held: it does nothing), data (its quest data must run)
local JOBS = {
	sellJunk = { "qol.sellJunk", shift = true },
	repair = { "qol.autoRepair", shift = true },
	accept = { "behavior.autoAccept", shift = true },
	turnIn = { "behavior.autoTurnin", shift = true },
	rewardPick = { "qol.rewardAutoPick", shift = true },
	corpse = { "qol.deathHelper" },
	rare = { "rares.enabled", "rares.alerts" },
	flightHelp = { "qol.flightHighlight" },
	questItemTips = { "qol.questDB", "qol.questTooltips", data = true },
	nameplateQuest = { "qol.questDB", "qol.nameplateIcons", data = true },
	minimapObjectives = { "qol.questDB", "qol.minimapObjectives", data = true },
}
O.JOBS = JOBS

-- the rows that say so: module, option key, the line
local DOES = "Polestar does this while it is on."
local DOES_QUESTS = "Polestar does this for its guide's quests while it is on."
local NOTES = {
	{ "Vendor", "autoRepair", DOES }, { "Vendor", "guildRepair", DOES }, { "Vendor", "autoSell", DOES },
	{ "QuestAuto", "accept", DOES_QUESTS }, { "QuestAuto", "handIn", DOES_QUESTS },
	{ "QuestAuto", "takeUpgrade", DOES },
	{ "Widgets", "corpse", DOES }, { "Widgets", "rare", DOES }, { "Widgets", "rareSound", DOES },
	{ "Route", "flightHint", DOES },
	{ "QuestList", "tipQuestItems", DOES }, { "QuestList", "objectiveMinimap", DOES },
	{ "Nameplates", "questIcon", DOES },
}
O.NOTES = NOTES

-- its namespace when it is loaded and has its settings, else nil
-- (2.1.44: not while its switch on the Addons page, Use with MelloUI, is off -- Core/Integrations.lua)
local function Polestar()
	local P = rawget(_G, POLESTAR)
	local I = rawget(MelloUI, "Integrations")
	if I and not I.Use(POLESTAR) then
		return nil
	end
	return type(P) == "table" and type(rawget(P, "Get")) == "function" and P or nil
end

local function Get(P, path)
	local ok, v = pcall(P.Get, path)
	return ok and Plain(v) or nil
end

local function Shift()
	local ok, down = pcall(IsShiftKeyDown)
	return ok and Plain(down) and true or false
end

-- its quest data running (Polestar_QuestDB loaded and read)
local function DataRuns(P)
	local Q = rawget(P, "QuestDB")
	if type(Q) ~= "table" or type(Q.IsRunning) ~= "function" then
		return false
	end
	local ok, on = pcall(Q.IsRunning)
	return ok and Plain(on) and true or false
end

-- (2.1.39) Questie's jobs: its profile's switches (Questie.db.profile, AceDB; read, never written), every one on --
-- nil counts as on, Questie's own defaults. Only its tracker (the user, 2026-11-10: "Questie Function but our Look":
-- MelloUI's tracker steps aside -- Modules/QuestTracker.lua)
-- (2.1.58) its tooltips' quest lines too: an item one of your quests asks for gets Questie's lines, so MelloUI's own
-- "Quest: ..." line on it steps aside (questItemTips, after Polestar)
local QUESTIE = "Questie"
local QUESTIE_JOBS = {
	questTracker = { "trackerEnabled" },
	questItemTips = { "enableTooltips" },
}
O.QUESTIE_JOBS = QUESTIE_JOBS

-- Questie's profile when the addon runs, else nil
local function QuestieProfile()
	local Q = rawget(_G, QUESTIE)
	local db = type(Q) == "table" and rawget(Q, "db")
	local profile = type(db) == "table" and db.profile
	return type(profile) == "table" and profile or nil
end

local function ByQuestie(job)
	local spec, profile = QUESTIE_JOBS[job], QuestieProfile()
	if not (spec and profile) then
		return nil
	end
	for _, key in ipairs(spec) do
		if Plain(profile[key]) == false then
			return nil
		end
	end
	return QUESTIE
end

--------------------------------------------------------------------------------
-- One owner for a creature's and an object's quest lines (2.1.58; the user, 2026-11-17, with a picture of a
-- creature's tooltip: "we have double quest text in the tooltip", then "Fix the double quest text in the tooltip").
-- Neither block was MelloUI's: Polestar wrote "<Quest>:  Kill <creature> 5/5" and Questie its own block under it
-- ("[35] <Quest>", "5/5 <creature> slain", the drop chances). Questie is the quests' engine here (the user,
-- 2026-11-10: "Questie Function but our Look"), so its lines are the ones: while Questie writes a creature's or an
-- object's quest lines, Polestar's of the same kind are left out.
--
-- How: Polestar adds those lines through two functions it keeps public for other tooltip paths
-- (Polestar.QuestDB.AddUnitLines, AddObjectLines). Each is looked at before it is used; at the login, with both
-- addons loaded, each gets a plain Lua stand-in that adds nothing while Questie writes and is Polestar's own function
-- otherwise (no hooksecurefunc: nothing of Polestar's runs through a C call of ours). Nothing of either addon is
-- written or kept: Questie's switch is read each time (its profile's enableTooltips; nil counts as on), and either
-- addon's Use with MelloUI switch off (the Addons page) leaves Polestar's lines as they are. In an instance Questie
-- writes none on this client, so Polestar's stay there. Polestar's lines on an ITEM stay too: they also say what its
-- guide needs ahead, which Questie does not.
--
--   O.QuestLines() -> "Questie" | nil   Questie writes a creature's and an object's quest lines now and Polestar's
--                                        are left out; nil: nothing is left out
--------------------------------------------------------------------------------
local yield = { names = { "AddUnitLines", "AddObjectLines" }, own = {} }
O.yield = yield

-- Questie writes a creature's and an object's quest lines now
local function QuestieTips()
	local profile = QuestieProfile()
	if not profile or Plain(profile.enableTooltips) == false then
		return false
	end
	local ok, inside = pcall(IsInInstance)
	return not (ok and Plain(inside) == true)
end

function O.QuestLines()
	if not next(yield.own) then
		return nil   -- (Polestar's adders were never stood in for: nothing is left out)
	end
	local I = rawget(MelloUI, "Integrations")
	if I and not (I.Use(POLESTAR) and I.Use(QUESTIE)) then
		return nil
	end
	return QuestieTips() and QUESTIE or nil
end

-- at the login: Polestar's two adders stood in for, once, when Questie is loaded too
local function Yield()
	local P, Q = rawget(_G, POLESTAR), rawget(_G, QUESTIE)
	local db = type(P) == "table" and rawget(P, "QuestDB")
	if type(db) ~= "table" or type(Q) ~= "table" then
		return
	end
	for _, name in ipairs(yield.names) do
		local own = rawget(db, name)
		if type(own) == "function" and not yield.own[name] then
			yield.own[name] = own
			db[name] = function(...)
				if O.QuestLines() then
					return 0   -- (as Polestar's own answer for "no line added")
				end
				return own(...)
			end
		end
	end
end
O.Yield = Yield

-- (2.1.49) the bag addons whose bag window MelloUI's makes room for, in the Addons page's order (Core/Integrations.lua)
O.BAG_ADDONS = { "Baganator", "Bagnon", "ArkInventory", "BetterBags" }
local function ByBags()
	local I = rawget(MelloUI, "Integrations")
	if type(I) ~= "table" or type(I.ByKey) ~= "table" then
		return nil
	end
	for _, key in ipairs(O.BAG_ADDONS) do
		local e = I.ByKey[key]
		if e and I.Installed(e) and I.Use(key) then
			return e.name
		end
	end
	return nil
end

-- (2.1.72) Lueur lighting the object you walk up to: its card's switch on and its own on (nil before it ever saved)
local function ByLueur()
	local I = rawget(MelloUI, "Integrations")
	local e = type(I) == "table" and type(I.ByKey) == "table" and I.ByKey.Lueur
	if not (e and I.Installed(e) and I.Use("Lueur")) then
		return nil
	end
	local db = rawget(_G, "LueurDB")
	if type(db) == "table" and Plain(db.enabled) == false then
		return nil
	end
	return e.name
end

function O.By(job)
	if job == "bags" then
		return ByBags()
	elseif job == "gatherGlow" then
		return ByLueur()
	end
	local spec, P = JOBS[job], Polestar()
	if not (spec and P) or (spec.shift and Shift()) or (spec.data and not DataRuns(P)) then
		return ByQuestie(job)
	end
	for _, path in ipairs(spec) do
		if Get(P, path) ~= true then
			return ByQuestie(job)
		end
	end
	return POLESTAR
end

-- its guide wants the quest now (its Engine.WantsQuest: this step or the next two)
local function Wants(P, verb, id)
	local E = rawget(P, "Engine")
	if type(E) ~= "table" or type(E.WantsQuest) ~= "function" then
		return false
	end
	local ok, yes = pcall(E.WantsQuest, verb, id)
	return ok and Plain(yes) == true
end

function O.Quest(verb, questID)
	local id = tonumber(Plain(questID))
	if not (id and id ~= 0) or not O.By(verb == "accept" and "accept" or "turnIn") then
		return nil
	end
	local P = Polestar()
	if verb == "accept" then
		return Wants(P, "accept", id) and POLESTAR or nil
	end
	-- (a quest in the log by its turn-in; one handed in from the giver's offers by its `direct` goal)
	return (Wants(P, "turnin", id) or Wants(P, "direct", id)) and POLESTAR or nil
end

-- the rows' notes: the option's hint, unless it has one of its own
local QUESTIE_NOTES = { { "QuestList", "tipQuestItems", "Questie does this while its tooltips are on." } }
O.QUESTIE_NOTES = QUESTIE_NOTES
-- (2.1.72) Loot Sparkles' gathering kinds while Lueur is used (its card's switch on)
local LUEUR_DOES = "Lueur does this while it is on."
local LUEUR_NOTES = { { "Sparkles", "ore", LUEUR_DOES }, { "Sparkles", "herbs", LUEUR_DOES },
	{ "Sparkles", "questObjects", LUEUR_DOES } }
O.LUEUR_NOTES = LUEUR_NOTES
local function Notes(list)
	for _, n in ipairs(list or NOTES) do
		local m = MelloUI.modules and MelloUI.modules[n[1]]
		for _, o in ipairs(type(m) == "table" and type(m.options) == "table" and m.options or {}) do
			if o.key == n[2] and o.hint == nil then
				o.hint = n[3]
			end
		end
	end
end

-- its setting for a job changed (its own SETTING_CHANGED: path, value; "" or a section for a reset): the bus
local function Changed(path)
	path = type(path) == "string" and path or ""
	for job, spec in pairs(JOBS) do
		for _, p in ipairs(spec) do
			if path == "" or p == path or p:sub(1, #path + 1) == path .. "." then
				MelloUI:Fire("overlap", job)
				break
			end
		end
	end
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
Perf.SetScript(login, "OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	Yield()   -- (2.1.58: Polestar's creature and object quest lines aside for Questie's; only with both loaded)
	local P = Polestar()
	if P then
		Notes()
	end
	-- (2.1.58) Questie's own note on the row it does, where Polestar's is not there
	if type(rawget(_G, QUESTIE)) == "table" then
		Notes(QUESTIE_NOTES)
	end
	-- (2.1.72) Lueur's, its own switch read whenever the job is asked about
	local I = rawget(MelloUI, "Integrations")
	local lueur = type(I) == "table" and type(I.ByKey) == "table" and I.ByKey.Lueur
	if lueur and I.Installed(lueur) and I.Use("Lueur") then
		Notes(LUEUR_NOTES)
	end
	if not P then
		return
	end
	if type(P.On) == "function" then
		pcall(P.On, "SETTING_CHANGED", Changed)
	end
end)

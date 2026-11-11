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
--
-- Questie (2.1.39): its own tracker only (questTracker: MelloUI's steps aside,
-- Questie's dressed in MelloUI's look, Core/QuestieLook.lua). Its map and
-- minimap icons never take MelloUI's jobs: MelloUI's givers, objective marks
-- and quest areas stay, and Questie's icons of the same kind hide where
-- MelloUI draws them (the user, 2026-11-10: "we have lost our own function
-- which i like very much"; Core/QuestieLook.lua).
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
local QUESTIE = "Questie"
local QUESTIE_JOBS = {
	questTracker = { "trackerEnabled" },
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

function O.By(job)
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
local function Notes()
	for _, n in ipairs(NOTES) do
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
	local P = Polestar()
	if not P then
		return
	end
	Notes()
	if type(P.On) == "function" then
		pcall(P.On, "SETTING_CHANGED", Changed)
	end
end)

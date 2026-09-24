--------------------------------------------------------------------------------
-- MelloUI - Companions
--
-- (user, 2026-09-24: one load-on-demand companion, MelloUI_Companion, holding
-- the Route data only -- the road network and the quest objective places --
-- loaded when Route needs it) Those two data files were most of what MelloUI
-- kept in memory, and only Route reads them. They ship beside MelloUI in the
-- same download as an addon of their own ("## LoadOnDemand: 1",
-- "## Dependencies: MelloUI") and load the first time a route is wanted, so
-- a session without routes, or with Route off, never holds them.
--
-- The client keeps each addon's locals to itself: the companion's files only
-- set their data globals (MelloUI_RoadData, MelloUI_QuestObjectiveData), and
-- Route reads those once they are there.
--
-- ok, why, later = MelloUI:LoadCompanion()
--   Loads it at once (LoadAddOn is synchronous: when it returns, the data is
--   there) and returns true, or false and a sentence saying why not and how
--   to fix it. A refusal is kept for the session -- switched off, not
--   installed, from another version, damaged: nothing changes that before a
--   restart -- and told once, as a notice (Chat Notices can mute it). A load
--   that threw (the game would not allow it just now) is not kept: `later` is
--   true, and asking again later may work.
--   Safe in combat: LoadAddOn is not a protected call, and the companion's
--   files only build tables (no frames, no hooks, no saved variables).
-- MelloUI:CompanionState()
--   What /route says about it: loaded, ready (loads when needed) or why not.
--   Never loads anything.
-- MelloUI:MemoryKB()
--   MelloUI's memory together with the companion's, in KB (then MelloUI's
--   own and the companion's): the number the FPS tooltip and /melloperf show,
--   which would otherwise drop by the data's share once it lives next door.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
MelloUI.Perf:Scope("Companions")   -- this file's load time (/melloperf load); it sets no script or timer

local COMPANION = "MelloUI_Companion"

-- The client's addon calls: C_AddOns where this client has them, else the
-- old globals
local function API(name)
	return (C_AddOns and C_AddOns[name]) or _G[name]
end

local function Plain(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return v
end

-- How to put any of it right: one download, every folder, a full restart
-- (a folder the client has not seen yet only shows up after one)
local FIX = "copy every folder of one MelloUI download (MelloUI and MelloUI_Companion) into Interface\\AddOns, then restart the game fully"

-- LoadAddOn's reasons, in words that say what to do
local REASONS = {
	MISSING = "the MelloUI_Companion folder is not installed (" .. FIX .. ")",
	DISABLED = "MelloUI_Companion is switched off in the AddOn list (tick it there, then /reload)",
	INTERFACE_VERSION = "MelloUI_Companion is out of date (" .. FIX .. ")",
	CORRUPT = "MelloUI_Companion is damaged (" .. FIX .. ")",
	INCOMPATIBLE = "the game refuses MelloUI_Companion (" .. FIX .. ")",
	DEP_DISABLED = "MelloUI_Companion is switched off in the AddOn list (tick it there, then /reload)",
}

local state = nil   -- true once loaded, or the sentence why it cannot load (kept for the session)

-- The companion's own "## Version", read from its TOC without loading it; nil
-- when the client cannot say (not installed: LoadAddOn tells that better)
local function TheirVersion()
	local Meta = API("GetAddOnMetadata")
	if not Meta then
		return nil
	end
	local ok, version = pcall(Meta, COMPANION, "Version")
	version = ok and Plain(version) or nil
	return type(version) == "string" and version ~= "" and version or nil
end

-- A folder from another MelloUI version: its data may not be what this
-- Route reads, so it is refused before any of it runs, and told (user,
-- 2026-09-24: refused with a message, not only warned about). A development
-- copy without a version ("dev") takes any.
local function OtherVersion()
	local mine, theirs = MelloUI.version, TheirVersion()
	if theirs and mine and mine ~= "dev" and theirs ~= mine then
		return theirs
	end
	return nil
end

-- Loaded and holding the data: a file of it that failed still lets LoadAddOn
-- say yes (the client runs the rest), so what it set is what counts
local function HoldsData()
	return type(_G.MelloUI_RoadData) == "table" or type(_G.MelloUI_QuestObjectiveData) == "table"
end

local function IsLoaded()
	local IsAddOnLoaded = API("IsAddOnLoaded")
	if not IsAddOnLoaded then
		return false
	end
	local ok, loaded = pcall(IsAddOnLoaded, COMPANION)
	return ok and Plain(loaded) and true or false
end

-- A refusal: kept, and told once, as a notice Chat Notices can mute (user,
-- 2026-09-24)
local function Refuse(why)
	state = why
	MelloUI:Notice("Route's road and quest objective data could not be loaded: %s. Until then routes follow only the paths you have walked, and a tracked quest keeps the game's own marker.", why)
	return false, why
end

function MelloUI:LoadCompanion()
	if state == true then
		return true
	elseif state then
		return false, state
	end
	local Load = API("LoadAddOn")
	if not (Load and API("IsAddOnLoaded")) then
		return Refuse("this client cannot load addons on demand")
	end
	local theirs = OtherVersion()
	if theirs then
		return Refuse(string.format("MelloUI_Companion is from MelloUI %s, not %s (%s)", theirs, tostring(self.version), FIX))
	end
	if not IsLoaded() then
		-- its parse time and memory under its own name in /melloperf load
		-- (the slice ends with its ADDON_LOADED, inside LoadAddOn)
		if self.Perf and self.Perf.Scope then
			self.Perf:Scope(COMPANION)
		end
		local ok, done, reason = pcall(Load, COMPANION)
		if not ok then
			-- not kept: the caller may ask again later
			return false, "the game did not allow it just now", true
		end
		done, reason = Plain(done), Plain(reason)
		if not done then
			reason = tostring(reason or "?")
			local text = _G["ADDON_" .. reason]
			return Refuse(REASONS[reason] or string.format("the game says %s (%s)", type(text) == "string" and text or reason, FIX))
		end
	end
	if not HoldsData() then
		return Refuse("MelloUI_Companion loaded but holds no route data (" .. FIX .. ")")
	end
	state = true
	return true
end

function MelloUI:CompanionState()
	if state == true or (state == nil and IsLoaded()) then
		return "loaded"
	elseif state then
		return state
	end
	local Exists = API("DoesAddOnExist")
	if Exists then
		local ok, exists = pcall(Exists, COMPANION)
		if ok and Plain(exists) == false then
			return "not installed"
		end
	end
	local Info = API("GetAddOnInfo")
	if Info then
		local ok, _, _, _, loadable, reason = pcall(Info, COMPANION)
		reason = ok and Plain(reason) or nil
		if reason == "MISSING" then
			return "not installed"
		elseif reason == "DISABLED" or reason == "DEP_DISABLED" then
			return "switched off in the AddOn list"
		elseif reason == "INTERFACE_VERSION" then
			return "out of date"
		elseif ok and not Plain(loadable) and reason and reason ~= "DEMAND_LOADED" then
			local text = _G["ADDON_" .. tostring(reason)]
			return "not loadable: " .. (type(text) == "string" and text or tostring(reason))
		end
	end
	-- switched off for this character (the enable state, where the AddOn
	-- list's per-character tick lives)
	local EnableState = C_AddOns and C_AddOns.GetAddOnEnableState
	if EnableState then
		local ok, enabled = pcall(EnableState, COMPANION, UnitName and UnitName("player") or nil)
		if ok and Plain(enabled) == 0 then
			return "switched off in the AddOn list"
		end
	end
	local theirs = OtherVersion()
	if theirs then
		return string.format("from MelloUI %s, not %s", theirs, tostring(self.version))
	end
	return "ready (loads when Route needs it)"
end

-- MelloUI with its companion, in KB; then MelloUI's own and the companion's
-- (0 until it loads). nil when this client cannot say.
function MelloUI:MemoryKB()
	local Update, Usage = UpdateAddOnMemoryUsage, GetAddOnMemoryUsage
	if not (Update and Usage) then
		return nil
	end
	pcall(Update)
	local ok, mine = pcall(Usage, self.name or "MelloUI")
	mine = ok and Plain(mine) or nil
	if type(mine) ~= "number" then
		return nil
	end
	local theirs = 0
	if IsLoaded() then
		local okC, kb = pcall(Usage, COMPANION)
		kb = okC and Plain(kb) or nil
		theirs = type(kb) == "number" and kb or 0
	end
	return mine + theirs, mine, theirs
end

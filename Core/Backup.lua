--------------------------------------------------------------------------------
-- MelloUI - Backup store
--
-- The settings live in the MelloUIDB saved variable, which the game saves and
-- brings back like any addon's. This file holds their text form (profiles,
-- share strings and the installer use it too) and the MACRO BACKUP: every
-- non-default setting copied into a few account macros named "MelloUI1",
-- "MelloUI2", ... (account macros are kept on the game's server, so they
-- reach another PC). It was made when the Forever beta client did not read
-- its saved variables back after a restart; the client was fixed on
-- 2026-09-25. Since 0.14.0 (user, 2026-09-26: opt-in, never an automatic
-- restore, the old macros freed):
--   - it is a switch, Macro Backup on the Profiles page, OFF for everyone
--     (players who have the macros included); off, nothing is written;
--   - a copy is NEVER read back by itself. A session that starts without
--     saved variables and finds a copy says so once and remembers it (the
--     'found' copy); the player brings it back (/mello backup restore) or
--     removes it, and until then switching the backup on is refused, so the
--     first write can never overwrite the only copy;
--   - the macros earlier versions wrote are freed once this PC's saved
--     variables have proved themselves: armed at one login, deleted at a
--     later full login (not a /reload) that read them back at the load;
--     never from a session that started without them, never a found copy.
-- Its state is top-level MelloUIDB keys, so no profile, share string or
-- copy carries it: macroBackup (true: on), macroBackupFound (true),
-- macroBackupRetire ({ at = time }: armed), macroBackupFreed (how many old
-- macros were freed).
--
-- API (the configurator's Profiles page and /mello backup):
--   MelloUI:MacroBackupOn() -> on
--   MelloUI:SetMacroBackup(on) -> ok[, why]
--       on: refused while a found copy waits ("found"; the mark goes with
--       its copy, however that is removed), and without the macro API or
--       before the account's macros are in ("unavailable"); the copy is
--       written at once (after the fight, in combat). off: the copy is
--       deleted (DeleteMacroBackup)
--   MelloUI:RestoreMacroBackup() -> true, applied | false, why
--       the copy's settings in place of these, the player's own keys
--       included, in one Batch; refused ("combat", "busy": the installer is
--       open or deciding, "pending": an install waits for Keep or Revert,
--       "none": no copy, "unavailable": no macro API, or the macros not in
--       yet). World fonts follow at the next
--       /reload (they are read at the addon's load).
--   MelloUI:DeleteMacroBackup(reason) -> deleted | false, "combat"
--       every macro of the copy removed (in combat: when the fight ends)
--       and the switch off
--   MelloUI:GetBackupStatus() -> status (a table, made per call: for a
--       command or a page's refresh, never per frame)
--       on, found, armed      the switch, a found copy, old macros armed
--       macros                how many macros of the copy there are
--       length, capacity      the copy's characters, and the most it holds
--       inSync                the copy is the settings as they are now
--       freed                 old macros freed on this PC (0: none)
--       restored              brought back this session (restoredStage "by
--                             you", restoredCount: its entries)
--       available, chunks (= macros), lastWrite, lastReason, lastError,
--       pending, deferredForCombat
--   MelloUI:SettingsSettled()   below
--   MelloUI:BackupAfterAdopt()  Core's: its look for late saved variables
--       is over (a copy is looked for only then)
-- The bus topic 'backup' (no arguments) goes out after the engine changed
-- the copy or its state by itself: a delayed write, a write or delete held
-- for a fight's end, the login's look (a found copy, old macros armed or
-- freed). Changes the API calls make are the caller's to show.
-- Nothing runs idle: the macros are looked at once a session, when they
-- come in; PLAYER_REGEN_ENABLED is taken only while a write or a delete
-- waits for a fight to end.
--
-- Format (one line, ';' separated, values type-prefixed):
--   Module.key=b1      boolean true      Module.key=b0   boolean false
--   Module.key=n0.25   number            Module.key=sText string (escaped)
--   !Module=b1         module enabled flag
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Backup")
local C_Timer = Perf.C_Timer

local MACRO_PREFIX = "MelloUI"
local MACRO_ICON = 134400        -- INV_Misc_QuestionMark
local CHUNK_SIZE = 250           -- macro bodies are limited to 255 characters
-- 24 account macros = 6000 characters (the account holds 120). Eight were
-- full at 1985 characters with a dozen moved windows (user, 2026-09-22: every
-- change past the limit was refused and the old settings came back on reload);
-- 16 held 3568 of 4000 on the user's own setup of 2026-09-24, personal keys
-- and window places included (user, 2026-09-25, with the installer: 8 more).
-- Only as many as the text needs are made. MelloUI1 .. MelloUI24 is also the
-- range the old macros are looked for in (gaps included).
local MAX_CHUNKS = 24
local WRITE_DELAY = 3

-- the chat lines (printed, not Notices: Chat Notices off must not hide them)
local TEXT = {
	found = "Found a copy of earlier settings in your account macros. /mello backup restore brings it back; "
		.. "/mello backup delete removes it.",
	freed = "The game keeps your settings now, so the copy in your account macros is gone: %d macro slots are free "
		.. "again. Macro Backup on the Profiles page turns the copy back on.",
	freedOne = "The game keeps your settings now, so the copy in your account macros is gone: 1 macro slot is free "
		.. "again. Macro Backup on the Profiles page turns the copy back on.",
}

--------------------------------------------------------------------------------
-- Serialisation
--------------------------------------------------------------------------------

local function Escape(s)
	return (s:gsub("\\", "\\\\"):gsub(";", "\\s"):gsub("=", "\\e"):gsub("|", "\\p"):gsub("\n", "\\n"))
end

local function Unescape(s)
	return (s:gsub("\\(.)", function(c)
		if c == "s" then return ";" end
		if c == "e" then return "=" end
		if c == "p" then return "|" end
		if c == "n" then return "\n" end
		return c
	end))
end

-- A table setting (the window positions: [name] = { point, x, y ... }) is
-- written as "t" + entries "key:value" joined by "|", a nested table's
-- fields as "key{f:value,g:value}"; one level deep, scalar leaves only
-- (user, 2026-09-21: the positions did not survive a reload, the backup
-- knew only scalars). Keys and values go through Escape.
local EncodeValue

local function EncodeScalar(v)
	local t = type(v)
	if t == "boolean" then
		return "b" .. (v and "1" or "0")
	elseif t == "number" then
		return "n" .. tostring(v)
	elseif t == "string" then
		return "s" .. Escape(v)
	end
	return nil
end

local function SortedKeys(tbl)
	local keys = {}
	for k in pairs(tbl) do
		if type(k) == "string" or type(k) == "number" then
			keys[#keys + 1] = k
		end
	end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

EncodeValue = function(v)
	if type(v) ~= "table" then
		return EncodeScalar(v)
	end
	local items = {}
	for _, k in ipairs(SortedKeys(v)) do
		local inner = v[k]
		local key = Escape(tostring(k)):gsub(":", "\\c"):gsub(",", "\\m"):gsub("{", "\\o"):gsub("}", "\\k")
		if type(inner) == "table" then
			local fields = {}
			for _, fk in ipairs(SortedKeys(inner)) do
				local enc = EncodeScalar(inner[fk])
				if enc then
					fields[#fields + 1] = Escape(tostring(fk)) .. ":" .. enc:gsub(",", "\\m"):gsub("}", "\\k")
				end
			end
			items[#items + 1] = key .. "{" .. table.concat(fields, ",") .. "}"
		else
			local enc = EncodeScalar(inner)
			if enc then
				items[#items + 1] = key .. ":" .. enc:gsub("|", "\\p")
			end
		end
	end
	return "t" .. table.concat(items, "|")
end

local function UnescapeKey(s)
	return Unescape((s:gsub("\\c", ":"):gsub("\\m", ","):gsub("\\o", "{"):gsub("\\k", "}")))
end

local function DecodeScalar(s)
	local kind, rest = s:sub(1, 1), s:sub(2)
	if kind == "b" then
		return rest == "1"
	elseif kind == "n" then
		return tonumber(rest)
	elseif kind == "s" then
		return Unescape(rest)
	end
	return nil
end

local function DecodeValue(s)
	local kind, rest = s:sub(1, 1), s:sub(2)
	if kind ~= "t" then
		return DecodeScalar(s)
	end
	local tbl = {}
	for item in rest:gmatch("[^|]+") do
		local key, body = item:match("^(.-)%{(.*)%}$")
		if key then
			local inner = {}
			for field in body:gmatch("[^,]+") do
				local fk, fv = field:match("^(.-):(.*)$")
				if fk then
					local decoded = DecodeScalar((fv:gsub("\\m", ","):gsub("\\k", "}")))
					if decoded ~= nil then
						inner[Unescape(fk)] = decoded
					end
				end
			end
			tbl[UnescapeKey(key)] = inner
		else
			local k, v = item:match("^(.-):(.*)$")
			if k then
				local decoded = DecodeScalar((v:gsub("\\p", "|")))
				if decoded ~= nil then
					tbl[UnescapeKey(k)] = decoded
				end
			end
		end
	end
	return tbl
end

function MelloUI:SerializeSettings()
	local parts = {}
	for name, module in self:IterateModules() do
		local stored = self.db.modules[name]
		if type(stored) == "table" then
			local keys = {}
			for k in pairs(stored) do
				if type(k) == "string" then keys[#keys + 1] = k end
			end
			table.sort(keys)
			for _, k in ipairs(keys) do
				local v = stored[k]
				local differs = module.defaults[k] ~= v
				if type(v) == "table" then
					differs = next(v) ~= nil
				end
				if differs then
					local enc = EncodeValue(v)
					if enc then
						parts[#parts + 1] = name .. "." .. k .. "=" .. enc
					end
				end
			end
		end
		-- A module driven by UI Modifications (hidden) has its state in the
		-- umbrella's own switches; its flag is re-derived at every login and
		-- would only take room here (audit, 2026-09-22).
		local flag = self.db.enabled[name]
		if flag ~= nil and flag ~= module.enabledByDefault and not module.hidden then
			parts[#parts + 1] = "!" .. name .. "=" .. EncodeValue(flag)
		end
	end
	return table.concat(parts, ";")
end

-- a module's settings inside `into` (DeserializeSettings), its defaults laid
-- on as GetModuleDB lays them on the live ones
local function IntoDB(self, into, name)
	local t = into.modules[name]
	if type(t) ~= "table" then
		t = {}
		into.modules[name] = t
	end
	return self.ApplyDefaults(t, self.modules[name].defaults)
end

-- Reads serialised settings. into (optional): a state { modules = { [module]
-- = settings }, enabled = { [module] = flag } } read into instead of the
-- live db, which is then not touched (the installer's targets): each module's
-- table there with its defaults laid on, and the flags in into.enabled; an
-- old flag of a module UI Modifications drives lands on the umbrella's
-- switch there too. Returns how many entries were applied.
function MelloUI:DeserializeSettings(text, into)
	if type(text) ~= "string" then
		return 0
	end
	local enabled
	if into ~= nil then
		assert(type(into) == "table", "MelloUI:DeserializeSettings(text, into): into must be a table")
		into.modules = type(into.modules) == "table" and into.modules or {}
		into.enabled = type(into.enabled) == "table" and into.enabled or {}
		enabled = into.enabled
	else
		enabled = self.db.enabled
	end
	local applied = 0
	for entry in text:gmatch("[^;]+") do
		local key, value = entry:match("^([^=]+)=(.*)$")
		if key and value then
			local decoded = DecodeValue(value)
			if decoded ~= nil then
				local flagName = key:match("^!(.+)$")
				if flagName then
					-- An older backup or profile carries the flag of a module
					-- that UI Modifications drives now: it lands on the
					-- umbrella's switch for it, or the umbrella would put the
					-- module back at the next login.
					local umbrella = self.modules.UIModifications
					local switch = umbrella and umbrella.defaults and (
						(umbrella.defaults[flagName] ~= nil and flagName)
						or (umbrella.defaults["qol_" .. flagName] ~= nil and ("qol_" .. flagName)) or nil)
					if switch and flagName ~= "UIModifications" then
						local db = into and IntoDB(self, into, "UIModifications") or self:GetModuleDB("UIModifications")
						db[switch] = decoded
						applied = applied + 1
					elseif self.modules[flagName] then
						enabled[flagName] = decoded
						applied = applied + 1
					end
				else
					local moduleName, settingKey = key:match("^([^.]+)%.(.+)$")
					if moduleName and self.modules[moduleName] then
						local db = into and IntoDB(self, into, moduleName) or self:GetModuleDB(moduleName)
						db[settingKey] = decoded
						applied = applied + 1
					end
				end
			end
		end
	end
	return applied
end

--------------------------------------------------------------------------------
-- Macro access
--------------------------------------------------------------------------------

-- (the macro API's answers read through MelloUI.Safe, a secret asked first)
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text
local Secret = MelloUI.Safe.IsSecret
local CAPACITY = CHUNK_SIZE * MAX_CHUNKS

local function MacrosAvailable()
	return type(GetNumMacros) == "function" and type(GetMacroInfo) == "function"
		and type(CreateMacro) == "function" and type(EditMacro) == "function"
end

local function FindMacro(name)
	if type(GetMacroIndexByName) == "function" then
		local index = Num(GetMacroIndexByName(name))
		if index and index > 0 then
			return index
		end
		return nil
	end
	local numAccount = Num((GetNumMacros())) or 0
	for i = 1, numAccount do
		local macroName = GetMacroInfo(i)
		if not Secret(macroName) and macroName == name then
			return i
		end
	end
	return nil
end

-- a macro's body as the copy wrote it: the client hands bodies back with a
-- trailing newline, and real newlines inside values are escaped, so any
-- raw one is an artifact (it would end up glued to the chunk's last value)
local function Body(index)
	local _, _, body = GetMacroInfo(index)
	body = Text(body)
	return body and (body:gsub("\n", "")) or ""
end

-- MelloUI<n> as a macro of the copy (the copy's icon): its index, or nil. A
-- player's own macro of that name, with another icon, is never deleted.
local function OwnMacro(n)
	local index = FindMacro(MACRO_PREFIX .. n)
	if not index then
		return nil
	end
	local _, icon = GetMacroInfo(index)
	if Secret(icon) then
		return nil
	end
	if icon == MACRO_ICON or (type(icon) == "string" and icon:lower():find("inv_misc_questionmark", 1, true)) then
		return index
	end
	return nil
end

-- the copy's text: MelloUI1, MelloUI2 ... up to the first missing or empty one
local function ReadChunks()
	local chunks = {}
	for i = 1, MAX_CHUNKS do
		local index = FindMacro(MACRO_PREFIX .. i)
		if not index then
			break
		end
		local body = Body(index)
		if body == "" then
			break
		end
		chunks[#chunks + 1] = body
	end
	return table.concat(chunks)
end

-- the copy's text, "" when there is none or it cannot be read
local function Copy()
	local ok, text = pcall(ReadChunks)
	return (ok and type(text) == "string") and text or ""
end

-- the game's DeleteMacro (looked up when used: the game's, or a test world's)
local function Deleter()
	local Delete = _G.DeleteMacro
	return type(Delete) == "function" and Delete or nil
end

-- MelloUI<first> .. MelloUI24 of the copy deleted, from the highest down (a
-- delete shifts the numbers after it; each is looked up by its name), gaps
-- and all. A client without DeleteMacro gets them blanked (the copy reads
-- as ending there; a blank one is not counted again). Returns how many.
local function RemoveFrom(first)
	local removed = 0
	local Delete = Deleter()
	for n = MAX_CHUNKS, first, -1 do
		local index = OwnMacro(n)
		if index then
			if Delete then
				Delete(index)
				removed = removed + 1
			elseif Body(index) ~= "" then
				EditMacro(index, MACRO_PREFIX .. n, MACRO_ICON, "")
				removed = removed + 1
			end
		end
	end
	return removed
end

-- whether any macro of the copy is there
local function AnyOwn()
	for n = 1, MAX_CHUNKS do
		if OwnMacro(n) then
			return true
		end
	end
	return false
end

-- The copy written: a chunk the macros already hold as it is left alone, a
-- missing one made, the ones a longer copy left deleted (0.14.0: it edited
-- every chunk and blanked the leftovers, each a server change and an
-- UPDATE_MACROS). Refused whole when it does not fit: a prefix cut at an
-- arbitrary character would come back as wrong values (a number cut to
-- "0.", a flag cut to "b"), so the previous macros stay as they are.
local function WriteChunks(text)
	if #text > CAPACITY then
		return false, string.format("settings too large for the macro backup (%d of %d characters)", #text, CAPACITY)
	end
	local count = math.ceil(#text / CHUNK_SIZE)
	for i = 1, count do
		local body = text:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
		local name = MACRO_PREFIX .. i
		local index = FindMacro(name)
		if index then
			if Body(index) ~= body then
				EditMacro(index, name, MACRO_ICON, body)
			end
		elseif not CreateMacro(name, MACRO_ICON, body, false) then
			return false, "no free account macro slot"
		end
	end
	RemoveFrom(count + 1)
	return true
end

--------------------------------------------------------------------------------
-- Restore / write
--------------------------------------------------------------------------------

local lastWritten = nil   -- the text this session's copy holds (written or brought back)
local writePending = false
-- what waits for the fight to end: a write, a delete (its reason; "retire":
-- the old macros freed)
local deferred = { write = false, delete = nil }
local frame   -- the event frame (below)

local settled = false     -- MelloUI:SettingsSettled() (below), once true for the session
local macrosIn = false    -- the account's macros are loaded
-- this session's own looks at the macros, once each: whether a copy was
-- found, whether old macros are armed or freed (after the first
-- PLAYER_ENTERING_WORLD, which says whether this is a full login);
-- writeWaits: a write asked for before the macros were in (Look runs it)
local session = { entered = false, initialLogin = false, foundLooked = false, retireLooked = false, writeWaits = false }

-- the account's macros are loaded: UPDATE_MACROS came, or it holds some.
-- Before that the game answers "no such macro" for every name, so nothing
-- is written, found or restored (a write then made every chunk again,
-- beside the copy already there)
local function MacrosIn()
	if not macrosIn then
		local ok, numAccount = pcall(GetNumMacros)
		numAccount = ok and Num(numAccount) or nil
		if numAccount and numAccount > 0 then
			macrosIn = true
		end
	end
	return macrosIn
end

-- A session that started without saved variables looks for a copy once
-- the macros are in: one there is from before, maybe from another PC; it is
-- said once and kept safe (the found mark), never taken in by itself. Run
-- from Look (the macros in, after the login) or first by SetMacroBackup(true)
-- (`now`: the switch never goes on over a copy not looked for yet). Look's
-- waits while Core still looks for late saved variables (up to a minute
-- after the login: an existing player's may yet come, and theirs is no
-- copy to tell of); it looks once that is over (BackupAfterAdopt).
local function LookForCopy(now)
	if session.foundLooked then
		return
	end
	local M = MelloUI
	if not now and M.dbIsTemporary and not M.savedVariablesNone and not M.restoredFromBackup then
		return
	end
	session.foundLooked = true
	local db = M.db
	if M.dbIsTemporary and not M.restoredFromBackup and not db.macroBackupFound then
		local text = Copy()
		if text ~= "" and text ~= lastWritten then
			db.macroBackupFound = true
			M:Print(TEXT.found)
		end
	end
end

-- A found mark stands only while its copy does: macros removed some other
-- way (the game's macro window; another PC that freed them, account macros
-- being the account's) take the mark with them, or the switch would stay
-- refused for good. Only read once the macros are in.
local function FoundStands(db)
	if db.macroBackupFound and MacrosAvailable() and MacrosIn() and Copy() == "" then
		db.macroBackupFound = nil
	end
	return db.macroBackupFound == true
end

-- (the macro calls are refused in combat: a write or a delete waits for its end)
local function InCombat()
	return InCombatLockdown and InCombatLockdown() and true or false
end

-- a write or a delete for the fight's end: PLAYER_REGEN_ENABLED taken now,
-- let go once they ran
local function Defer(what, reason)
	if what == "write" then
		deferred.write = true
	else
		deferred.delete = reason or "delete"
	end
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function MelloUI:MacroBackupOn()
	local db = self.db
	return (type(db) == "table" and db.macroBackup == true) and true or false
end

function MelloUI:WriteBackup(reason)
	local db = self.db
	if not self:MacroBackupOn() or not MacrosAvailable() then
		return
	end
	if not MacrosIn() then
		session.writeWaits = true   -- (written when they come in: Look)
		return
	end
	if FoundStands(db) then
		return
	end
	if InCombat() then
		Defer("write")
		return
	end
	local text = self:SerializeSettings()
	if text == lastWritten then
		return
	end
	local ok, success, err = pcall(WriteChunks, text)
	if ok and success then
		lastWritten = text
		self.backupLastWrite = time()
		self.backupLastReason = reason
		self.backupLastError = nil
	else
		local message = tostring(ok and err or success)
		if message ~= self.backupLastError and reason ~= "switched on" then
			-- said once per distinct cause; the write is tried again on the next change
			-- (the switch's own write: its caller, the configurator, says it)
			self:Print("|cffff4040Could not back up settings to macros:|r %s", message)
		end
		self.backupLastError = message
	end
end

-- Every call site asks for a write here (Core's setting paths, a Batch's
-- end, the flight points ...); off, it returns at once, so they need not know
function MelloUI:ScheduleBackup(reason)
	if writePending or not self.initialized or not self:MacroBackupOn() then
		return
	end
	writePending = true
	C_Timer.After(WRITE_DELAY, function()
		writePending = false
		self:WriteBackup(reason or "change")
		self:Fire("backup")   -- (the copy changed by itself: an open Profiles page follows)
	end)
end

function MelloUI:DeleteMacroBackup(reason)
	local db = self.db
	if type(db) == "table" then
		-- (the copy goes: nothing found waits any more, and nothing is
		-- written again until the switch is turned on)
		db.macroBackup, db.macroBackupFound = nil, nil
	end
	deferred.write = false
	if not MacrosAvailable() then
		return 0
	end
	if InCombat() then
		Defer("delete", reason)
		return false, "combat"
	end
	local removed = RemoveFrom(1)
	lastWritten = nil
	if type(db) == "table" then
		db.macroBackupRetire = nil
	end
	return removed
end

function MelloUI:SetMacroBackup(on)
	local db = self.db
	if type(db) ~= "table" then
		return false, "unavailable"
	end
	on = on and true or false
	if on == self:MacroBackupOn() then
		return true
	end
	if not on then
		self:DeleteMacroBackup("switched off")
		return true
	end
	if not (MacrosAvailable() and MacrosIn()) then
		return false, "unavailable"   -- (the macros not in yet: whether a copy is there is not known)
	end
	LookForCopy(true)
	if FoundStands(db) then
		return false, "found"   -- (the copy found must be brought back or removed first)
	end
	db.macroBackup = true
	db.macroBackupRetire = nil   -- (the macros are the copy again: nothing to free)
	db.macroBackupFreed = nil    -- (nor an old freeing to tell of once it is off again)
	if deferred.delete then
		deferred.delete = nil    -- (a delete still waiting for the fight: the write replaces it)
	end
	self:WriteBackup("switched on")
	return true
end

-- The copy's settings in place of these, when the player asks (0.14.0: never
-- by itself). Its personal keys come too (the copy is this player's own).
function MelloUI:RestoreMacroBackup()
	if not (MacrosAvailable() and MacrosIn()) then
		return false, "unavailable"
	end
	if InCombat() then
		return false, "combat"
	end
	local installer = self.Installer
	if type(installer) == "table" and type(installer.Busy) == "function" and installer:Busy() then
		return false, "busy"
	end
	local db = self.db
	local point = type(db) == "table" and db.installer
	if type(point) == "table" and point.pending then
		return false, "pending"
	end
	local text = Copy()
	if text == "" then
		if type(db) == "table" then
			db.macroBackupFound = nil   -- (the copy is gone: nothing found waits)
		end
		return false, "none"
	end
	local applied = self:Batch(self.ApplySettingsText, self, text, true)
	lastWritten = text
	self.backupLastError = nil   -- (the copy is the settings now: an earlier failed write is past)
	self.restoredFromBackup = true
	self.backupRestoredStage = "by you"
	self.backupRestoredCount = applied
	if type(self.db) == "table" then
		self.db.macroBackupFound = nil
	end
	return true, applied
end

-- Facts for /mello status and the Profiles page (see the header).
function MelloUI:GetBackupStatus()
	local db = type(self.db) == "table" and self.db or {}
	local status = {
		on = self:MacroBackupOn(),
		found = db.macroBackupFound == true,
		armed = type(db.macroBackupRetire) == "table",
		macros = 0,
		length = 0,
		capacity = CAPACITY,
		inSync = false,
		freed = tonumber(db.macroBackupFreed) or 0,
		restored = self.restoredFromBackup == true,
		available = MacrosAvailable(),
		chunks = 0,
		lastWrite = self.backupLastWrite,
		lastReason = self.backupLastReason,
		lastError = self.backupLastError,
		pending = writePending or session.writeWaits,
		deferredForCombat = deferred.write or deferred.delete ~= nil,
		restoredStage = self.backupRestoredStage,
		restoredCount = self.backupRestoredCount,
	}
	if status.available then
		local text = Copy()
		status.length = #text
		if status.found and text == "" and MacrosIn() then
			-- (a found copy removed some other way: the mark goes with it)
			db.macroBackupFound = nil
			status.found = false
		end
		for n = 1, MAX_CHUNKS do
			if OwnMacro(n) then
				status.macros = status.macros + 1
			end
		end
		status.chunks = status.macros
		if text ~= "" then
			local okSer, current = pcall(self.SerializeSettings, self)
			status.inSync = (okSer and current == text) and true or false
		end
	end
	return status
end

--------------------------------------------------------------------------------
-- Settled: the real settings are in place
--
-- The saved variables can load late (or be missing), and the account
-- macros (the backup) can arrive after PLAYER_LOGIN, so for a few
-- seconds an existing player can look new. MelloUI:SettingsSettled() is true
-- once one of these held (and stays true for the session):
--   - the real saved variables were adopted (not dbIsTemporary);
--   - the player brought a copy back (restoredFromBackup);
--   - the macros are in (UPDATE_MACROS came, or the account holds some):
--     with no saved variables by then, the settings are a new player's,
--     whatever copy the macros hold (0.14.0: a copy is never read back by
--     itself, so it no longer keeps the login waiting).
-- The installer's login check and its Install wait for it: a new player is
-- only known to be new once it holds.
--------------------------------------------------------------------------------

-- (settled, macrosIn and MacrosIn: with the writes above)
function MelloUI:SettingsSettled()
	if settled then
		return true
	end
	if not self.db then
		return false
	end
	if not self.dbIsTemporary or self.restoredFromBackup or (MacrosAvailable() and MacrosIn()) then
		settled = true
	end
	return settled
end

--------------------------------------------------------------------------------
-- The old macros freed (0.14.0), two steps per PC. The macros earlier
-- versions wrote hold nothing the saved variables do not (the copy is a
-- strict part of them), and they were never read on a PC whose saved
-- variables loaded. So, with the switch off, no copy found, the saved
-- variables read back at the addon's load and macros of the copy there:
-- the first session arms (macroBackupRetire); a LATER full login (not a
-- /reload) that read the mark back deletes MelloUI24 down to MelloUI1 (the
-- copy's icon only), after the fight in combat, says so once and clears the
-- mark. Account macros are the account's: a PC still on an older version
-- writes them again, and this PC frees them again the same way.
--------------------------------------------------------------------------------

local function FreeOld()
	local M = MelloUI
	local db = M.db
	if type(db) ~= "table" or M:MacroBackupOn() or db.macroBackupFound or type(db.macroBackupRetire) ~= "table" then
		return
	end
	if InCombat() then
		Defer("delete", "retire")
		return
	end
	local removed = RemoveFrom(1)
	db.macroBackupRetire = nil
	lastWritten = nil
	if removed > 0 then
		db.macroBackupFreed = removed
		M:Print(removed == 1 and TEXT.freedOne or TEXT.freed, removed)
	end
end

local function Retire()
	local M = MelloUI
	local db = M.db
	if M:MacroBackupOn() or db.macroBackupFound then
		db.macroBackupRetire = nil   -- (the live copy, or one found: never freed by this)
		return
	end
	if M.dbIsTemporary or M.savedVariablesStage ~= "ADDON_LOADED" then
		return   -- (only saved variables read back at the load prove themselves)
	end
	if not Deleter() or not AnyOwn() then
		-- (none there; or a client without DeleteMacro, where a blanked
		-- macro would still hold its slot: nothing to free)
		db.macroBackupRetire = nil
		return
	end
	if type(db.macroBackupRetire) ~= "table" then
		db.macroBackupRetire = { at = time() }   -- armed: a later full login frees them
	elseif session.initialLogin then
		FreeOld()
	end
end

-- The macros are in (and the login far enough along): a found copy looked
-- for, once (LookForCopy); a write asked for before they were in, made; the
-- old macros' step, once, after the first PLAYER_ENTERING_WORLD. When all
-- are done UPDATE_MACROS is let go.
local function Look()
	local M = MelloUI
	if not (M.initialized and type(M.db) == "table" and MacrosAvailable() and MacrosIn()) then
		return
	end
	if not settled then
		M:SettingsSettled()
	end
	local looked = session.foundLooked
	local changed = session.writeWaits
	LookForCopy()
	if session.foundLooked ~= looked then
		changed = true
	end
	if session.writeWaits then
		session.writeWaits = false
		M:WriteBackup("macros in")
	end
	if session.entered and not session.retireLooked then
		session.retireLooked = true
		changed = true
		Retire()
	end
	if settled and session.foundLooked and session.retireLooked then
		frame:UnregisterEvent("UPDATE_MACROS")
	end
	if changed then
		M:Fire("backup")   -- (once per step taken: an open Profiles page follows)
	end
end

-- Core's look for late saved variables is over (they came, or none came
-- in its minute: MelloUI.savedVariablesNone): the macros' look goes on
function MelloUI:BackupAfterAdopt()
	Look()
end

-- the fight ended: a delete first (the player's, or the old macros'), then a write
local function AfterCombat()
	frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
	local reason = deferred.delete
	deferred.delete = nil
	if reason == "retire" then
		FreeOld()
	elseif reason then
		MelloUI:DeleteMacroBackup(reason)
	end
	if deferred.write then
		deferred.write = false
		MelloUI:WriteBackup("after combat")
	end
	MelloUI:Fire("backup")
end

frame = CreateFrame("Frame")
frame:RegisterEvent("UPDATE_MACROS")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
Perf.SetScript(frame, "OnEvent", function(self, event, isInitialLogin)
	if event == "PLAYER_REGEN_ENABLED" then
		AfterCombat()
	elseif event == "UPDATE_MACROS" then
		macrosIn = true
		if not settled then
			MelloUI:SettingsSettled()
		end
		Look()
	elseif event == "PLAYER_ENTERING_WORLD" then
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		session.entered = true
		session.initialLogin = (not Secret(isInitialLogin) and isInitialLogin == true) and true or false
		Look()
	end
end)

MelloUI:Profile("Backup", "backup writes", frame)

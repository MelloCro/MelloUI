--------------------------------------------------------------------------------
-- MelloUI - Backup store
--
-- The settings live in the MelloUIDB saved variable, which the game saves and
-- brings back like any addon's. This file holds their text form (profiles,
-- share strings and the installer use it), MelloUI:SettingsSettled(), and the
-- freeing of the old MACRO BACKUP's macros.
--
-- The Macro Backup (0.10 - 0.24) copied every setting into account macros
-- "MelloUI1", "MelloUI2", ... while the Forever beta did not read its saved
-- variables back after a restart; the client was fixed on 2026-09-25 and the
-- backup is gone since 0.25.0 (user, 2026-10-15: "no need for macro backup
-- anymore"). Players who had it on still hold its macros: they are freed
-- once (below), and the backup's top-level keys (macroBackup,
-- macroBackupFound, macroBackupRetire, macroBackupFreed) are dropped.
--
-- API:
--   MelloUI:SerializeSettings() -> text      every non-default setting
--   MelloUI:DeserializeSettings(text[, into]) and MelloUI:HoldDeep(text)
--   MelloUI:SettingsSettled()                below
-- Nothing runs idle: the macros are looked at once a session, when they come
-- in; PLAYER_REGEN_ENABLED is taken only while a freeing waits for a fight to
-- end.
--
-- Format (one line, ';' separated, values type-prefixed):
--   Module.key=b1      boolean true      Module.key=b0   boolean false
--   Module.key=n0.25   number            Module.key=sText string (escaped)
--   Module.key=t...    a table, two levels deep at most (below)
--   Module.key=T{...}  a declared deep table (DEEP, below), any depth to 8
--   !Module=b1         module enabled flag
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("Backup")

local MACRO_PREFIX = "MelloUI"
local MACRO_ICON = 134400        -- INV_Misc_QuestionMark (the old copy's icon)
-- MelloUI1 .. MelloUI24: the range the old copy's macros are looked for in
-- (gaps included)
local MAX_CHUNKS = 24

-- the chat line (printed, not a Notice: Chat Notices off must not hide it)
local TEXT = {
	freed = "Macro Backup is gone (the game keeps your settings): its %d account macros were removed, so the "
		.. "slots are free again.",
	freedOne = "Macro Backup is gone (the game keeps your settings): its account macro was removed, so the slot is "
		.. "free again.",
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
-- (user, 2026-09-21: the positions did not survive a reload, the old macro
-- backup knew only scalars). Keys and values go through Escape.
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

--------------------------------------------------------------------------------
-- Deep table settings (0.25.0). The 't' form above keeps two levels, so a
-- table setting deeper than that lost the rest: Group Frames' indicator
-- lists (sets[spec] = { indicator, ... }, each with its text and count
-- tables) went into every profile and backup as empty lists, and loading
-- one emptied the player's (since 0.20.0). Such a setting is declared here,
-- in core, so it is known while its feature addon is turned off. The list
-- per key names its companions: the settings that belong with it and are
-- kept or replaced with it (started: the lists the player made his own;
-- nextId: the next indicator's id, so new ids never meet a kept one's).
-- Add an entry when a table setting grows past two levels (the tests scan
-- for one). A declared key is always written as 'T', whatever its depth:
--   T{entry,entry,...}      entry = key ':' value
--   key    n<number> | s<escaped>      (number keys come back as numbers)
--   value  b1 | b0 | n<finite number> | s<escaped> | a nested {...}
-- Strings go through Escape plus \c \m \o \k for : , { }, so no raw ; = | :
-- , { } is ever written. The reader goes 8 levels deep and reads 256 KB at
-- most (every class's starter lists, both frame kinds, four specs each:
-- 52 KB); a value it cannot read is skipped whole. A load that brings one
-- the reader cannot take keeps the player's own (MelloUI:HoldDeep, Core's
-- ApplySettingsText).
--------------------------------------------------------------------------------

local DEEP = { GroupFrames = { sets = { "started", "nextId" } } }
MelloUI.DEEP_SETTINGS = DEEP   -- (read only: the tests')
local DEEP_DEPTH, DEEP_LENGTH = 8, 262144

local function IsDeep(moduleName, key)
	local keys = moduleName and DEEP[moduleName]
	return keys ~= nil and keys[key] ~= nil
end

local function Finite(v)
	return v == v and v ~= math.huge and v ~= -math.huge
end

local function DeepString(s)
	return (Escape(s):gsub(":", "\\c"):gsub(",", "\\m"):gsub("{", "\\o"):gsub("}", "\\k"))
end

local DEEP_UNESCAPE = { s = ";", e = "=", p = "|", n = "\n", c = ":", m = ",", o = "{", k = "}" }
local function DeepUnescape(s)
	return (s:gsub("\\(.)", function(c) return DEEP_UNESCAPE[c] or c end))
end

-- the numbers first, in order, then the strings
local function DeepOrder(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		return ta == "number"
	end
	return a < b
end

-- a table's body "{...}"; a table past DEEP_DEPTH levels is left out (as
-- every value the format has no letter for)
local function EncodeDeepTable(t, depth)
	local keys = {}
	for k in pairs(t) do
		if type(k) == "string" or (type(k) == "number" and Finite(k)) then
			keys[#keys + 1] = k
		end
	end
	table.sort(keys, DeepOrder)
	local items = {}
	for _, k in ipairs(keys) do
		local v, enc = t[k], nil
		local kind = type(v)
		if kind == "table" then
			if depth < DEEP_DEPTH then
				enc = EncodeDeepTable(v, depth + 1)
			end
		elseif kind == "boolean" then
			enc = v and "b1" or "b0"
		elseif kind == "number" then
			enc = Finite(v) and ("n" .. tostring(v)) or nil
		elseif kind == "string" then
			enc = "s" .. DeepString(v)
		end
		if enc then
			items[#items + 1] = (type(k) == "number" and ("n" .. tostring(k)) or ("s" .. DeepString(k))) .. ":" .. enc
		end
	end
	return "{" .. table.concat(items, ",") .. "}"
end

local function EncodeDeep(v)
	return "T" .. EncodeDeepTable(v, 1)
end

local function DeepScalar(tok)
	local kind, rest = tok:sub(1, 1), tok:sub(2)
	if kind == "b" then
		if rest == "1" then
			return true
		elseif rest == "0" then
			return false
		end
	elseif kind == "n" then
		local n = tonumber(rest)
		if n and Finite(n) then
			return n
		end
	elseif kind == "s" and not rest:find("[:{=|]") then
		return DeepUnescape(rest)
	end
	return nil
end

-- the table whose "{" is at s[i], read by index: it and the index after its
-- "}", or nil when it is not whole
local function DeepTable(s, i, depth)
	if depth > DEEP_DEPTH then
		return nil
	end
	local t = {}
	i = i + 1
	if s:sub(i, i) == "}" then
		return t, i + 1
	end
	while true do
		local colon = s:find(":", i, true)
		if not colon then
			return nil
		end
		local ktok = s:sub(i, colon - 1)
		if ktok:find("[,{}=|]") then
			return nil
		end
		local key
		if ktok:sub(1, 1) == "n" then
			key = tonumber(ktok:sub(2))
			if not (key and Finite(key)) then
				return nil
			end
		elseif ktok:sub(1, 1) == "s" then
			key = DeepUnescape(ktok:sub(2))
		else
			return nil
		end
		i = colon + 1
		local value
		if s:sub(i, i) == "{" then
			value, i = DeepTable(s, i, depth + 1)
			if value == nil then
				return nil
			end
		else
			local stop = s:find("[,}]", i)
			if not stop then
				return nil
			end
			value = DeepScalar(s:sub(i, stop - 1))
			if value == nil then
				return nil
			end
			i = stop
		end
		t[key] = value
		local sep = s:sub(i, i)
		if sep == "}" then
			return t, i + 1
		elseif sep ~= "," then
			return nil
		end
		i = i + 1
	end
end

-- a 'T' value's table, or nil when it is not one whole
local function DecodeDeep(value)
	if type(value) ~= "string" or #value > DEEP_LENGTH or value:sub(1, 2) ~= "T{" then
		return nil
	end
	local t, after = DeepTable(value, 2, 1)
	if t == nil or after ~= #value + 1 then
		return nil
	end
	return t
end

-- (one setting's text: a declared deep key as 'T', the others as before; nil
-- when it is not written)
local function EncodeSetting(name, k, v)
	if IsDeep(name, k) then
		return type(v) == "table" and EncodeDeep(v) or nil
	end
	return EncodeValue(v)
end

-- The deep settings a load of `text` must leave as they are, with their
-- companions: { [module] = { [key] = true } }, or nil when none. A declared
-- key is held when the text carries it only in a form the reader does not
-- take (the old 't', which carried the lists empty, or a 'T' that is not
-- whole). Absent from a profile it is not held: a profile saved with no
-- lists means the starters.
-- Core's ApplySettingsText keeps the held keys and hands the hold to
-- DeserializeSettings, which skips their entries.
function MelloUI:HoldDeep(text)
	if type(text) ~= "string" then
		return nil
	end
	local hold
	for moduleName, keys in pairs(DEEP) do
		for key, companions in pairs(keys) do
			local prefix = moduleName .. "." .. key .. "="
			local seen, readable = false, false
			for entry in text:gmatch("[^;]+") do
				if entry:sub(1, #prefix) == prefix then
					seen = true
					readable = readable or DecodeDeep(entry:sub(#prefix + 1)) ~= nil
				end
			end
			if not readable and seen then
				hold = hold or {}
				local held = hold[moduleName] or {}
				hold[moduleName] = held
				held[key] = true
				for i = 1, #companions do
					held[companions[i]] = true
				end
			end
		end
	end
	return hold
end

-- every non-default setting as text (profiles, share strings, the installer)
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
					local enc = EncodeSetting(name, k, v)
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
	-- (0.19.9) a feature of its own addon that is not loaded (turned off in
	-- the game's AddOns list): its saved settings as they are kept, every
	-- one (its defaults are in its own file), and its switch -- a profile
	-- made meanwhile still carries them
	local features = {}
	for name in pairs(self.Features or {}) do
		if not self.modules[name] then
			features[#features + 1] = name
		end
	end
	table.sort(features)
	for _, name in ipairs(features) do
		local stored = self.db.modules[name]
		if type(stored) == "table" then
			local keys = {}
			for k in pairs(stored) do
				if type(k) == "string" then keys[#keys + 1] = k end
			end
			table.sort(keys)
			for _, k in ipairs(keys) do
				local v = stored[k]
				if type(v) ~= "table" or next(v) ~= nil then
					local enc = EncodeSetting(name, k, v)
					if enc then
						parts[#parts + 1] = name .. "." .. k .. "=" .. enc
					end
				end
			end
		end
		local flag = self.db.enabled[name]
		if flag ~= nil then
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
-- switch there too. hold (optional, MelloUI:HoldDeep's): the deep settings
-- whose entries are skipped. A declared deep key is taken only as 'T': its
-- old 't' value carried the lists empty and is never applied (a target of
-- the installer's keeps its defaults there). Returns how many entries were
-- applied.
function MelloUI:DeserializeSettings(text, into, hold)
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
			local owner, setting = key:match("^([^.]+)%.(.+)$")
			local decoded
			if not (owner and hold and hold[owner] and hold[owner][setting]) then   -- (held: the player's own stays)
				if IsDeep(owner, setting) then
					decoded = DecodeDeep(value)
				else
					decoded = DecodeValue(value)
				end
			end
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
					elseif self.modules[flagName] or (self.Features and self.Features[flagName]) then
						enabled[flagName] = decoded
						applied = applied + 1
					end
				else
					local moduleName, settingKey = owner, setting
					if moduleName and self.modules[moduleName] then
						local db = into and IntoDB(self, into, moduleName) or self:GetModuleDB(moduleName)
						db[settingKey] = decoded
						applied = applied + 1
						-- (one look C12: what the live settings' text set itself, for
						-- the next MergeSettings -- Core.lua's ApplySettingsText)
						if not into and self.textKeys then
							self.textKeys[key] = true
						end
					elseif moduleName and self.Features and self.Features[moduleName] then
						-- (0.19.9) a feature not loaded: kept as it came,
						-- its defaults laid on when its addon loads again
						local all = into and into.modules or self.db.modules
						local t = all[moduleName]
						if type(t) ~= "table" then
							t = {}
							all[moduleName] = t
						end
						t[settingKey] = decoded
						applied = applied + 1
					end
				end
			end
		end
	end
	return applied
end

--------------------------------------------------------------------------------
-- Settled: the real settings are in place
--
-- The saved variables can load late (Core's look for them runs up to a
-- minute after the login), so for a moment an existing player can look new.
-- MelloUI:SettingsSettled() is true once one of these held (and stays true
-- for the session):
--   - the real saved variables were adopted (not dbIsTemporary);
--   - the world was entered without them: the client reads them at the
--     addon's load since its fix (2026-09-25), so none by then is a new
--     player's (the old macros' arrival, which settled it before 0.25.0,
--     came at the same moment).
-- The installer's login check and its Install wait for it.
--------------------------------------------------------------------------------

local settled = false     -- once true for the session
local entered = false     -- PLAYER_ENTERING_WORLD came
local macrosIn = false    -- the account's macros are loaded
local frame               -- the event frame (below)

function MelloUI:SettingsSettled()
	if settled then
		return true
	end
	if not self.db then
		return false
	end
	if not self.dbIsTemporary or entered then
		settled = true
	end
	return settled
end

--------------------------------------------------------------------------------
-- The old Macro Backup's macros freed (one look, 0.25.0). Once the
-- account's macros are in, after the world is entered: every MelloUI<n> of
-- the copy (its name AND its icon: a player's own macro of that name is
-- never touched) is deleted, after the fight in combat, and said once. Each
-- session looks once (24 names), then lets its events go; a PC still on an
-- older version may write them again, and this frees them again.
--------------------------------------------------------------------------------

-- (the macro API's answers read through MelloUI.Safe, a secret asked first)
local Num = MelloUI.Safe.Number
local Text = MelloUI.Safe.Text
local Secret = MelloUI.Safe.IsSecret

local function MacrosAvailable()
	return type(GetNumMacros) == "function" and type(GetMacroInfo) == "function"
		and type(EditMacro) == "function"
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

-- a macro's body (the client hands bodies back with a trailing newline)
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

-- the game's DeleteMacro (looked up when used: the game's, or a test world's)
local function Deleter()
	local Delete = _G.DeleteMacro
	return type(Delete) == "function" and Delete or nil
end

-- MelloUI24 .. MelloUI1 of the copy deleted, from the highest down (a delete
-- shifts the numbers after it; each is looked up by its name), gaps and all.
-- A client without DeleteMacro gets them blanked (a blank one is not counted
-- again). Returns how many.
local function RemoveAll()
	local removed = 0
	local Delete = Deleter()
	for n = MAX_CHUNKS, 1, -1 do
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

-- the account's macros are loaded: UPDATE_MACROS came, or it holds some.
-- Before that the game answers "no such macro" for every name
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

-- (the macro calls are refused in combat: the freeing waits for its end)
local function InCombat()
	return InCombatLockdown and InCombatLockdown() and true or false
end

-- the look, once a session: the backup's keys dropped from the real saved
-- variables, the copy's macros freed; then the events let go
local function Free()
	local M = MelloUI
	if not (M.initialized and type(M.db) == "table" and entered) then
		return
	end
	if not M.dbIsTemporary then
		local db = M.db
		db.macroBackup, db.macroBackupFound, db.macroBackupRetire, db.macroBackupFreed = nil, nil, nil, nil
	end
	if not MacrosAvailable() then
		frame:UnregisterAllEvents()
		return
	end
	if not MacrosIn() then
		return   -- (UPDATE_MACROS brings them)
	end
	if InCombat() then
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	frame:UnregisterAllEvents()
	local ok, removed = pcall(RemoveAll)
	if ok and removed > 0 then
		M:Print(removed == 1 and TEXT.freedOne or TEXT.freed, removed)
	end
end

frame = CreateFrame("Frame")
frame:RegisterEvent("UPDATE_MACROS")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
Perf.SetScript(frame, "OnEvent", function(self, event)
	if event == "UPDATE_MACROS" then
		macrosIn = true
	elseif event == "PLAYER_ENTERING_WORLD" then
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		entered = true
		if not settled then
			MelloUI:SettingsSettled()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	end
	Free()
end)

MelloUI:Profile("Backup", "the old macros freed", frame)

--------------------------------------------------------------------------------
-- MelloUI - Backup store
--
-- The Forever beta client (build 1.60.1.69913) does not reliably load addon
-- SavedVariables from disk: it keeps them in memory across /reload, but drops
-- them when the client restarts or when addon files change. Account macros
-- are stored server-side and always come back, so every non-default setting
-- is mirrored into a few hidden account macros named "MelloUI1", "MelloUI2",
-- ... and restored from there whenever the saved variables are missing.
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

-- true pauses the store: nothing is read from or written to the macros, the
-- settings run from the defaults / the baked profile and the macros keep what
-- they hold (used 2026-09-22 to test whether the client reads its saved
-- variables again: it still does not, build 1.60.1.69913).
local BACKUP_PAUSED = false

local MACRO_PREFIX = "MelloUI"
local MACRO_ICON = 134400        -- INV_Misc_QuestionMark
local CHUNK_SIZE = 250           -- macro bodies are limited to 255 characters
-- 16 account macros = 4000 characters (the account holds 120). Eight were
-- full at 1985 characters with a dozen moved windows (user, 2026-09-22: every
-- change past the limit was refused and the old settings came back on reload).
local MAX_CHUNKS = 16
local WRITE_DELAY = 3

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

function MelloUI:DeserializeSettings(text)
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
						self:GetModuleDB("UIModifications")[switch] = decoded
						applied = applied + 1
					elseif self.modules[flagName] then
						self.db.enabled[flagName] = decoded
						applied = applied + 1
					end
				else
					local moduleName, settingKey = key:match("^([^.]+)%.(.+)$")
					if moduleName and self.modules[moduleName] then
						self:GetModuleDB(moduleName)[settingKey] = decoded
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

local function MacrosAvailable()
	return type(GetNumMacros) == "function" and type(GetMacroInfo) == "function"
		and type(CreateMacro) == "function" and type(EditMacro) == "function"
end

local function FindMacro(name)
	if type(GetMacroIndexByName) == "function" then
		local index = GetMacroIndexByName(name)
		if index and index > 0 then
			return index
		end
		return nil
	end
	local numAccount = GetNumMacros()
	for i = 1, numAccount do
		local macroName = GetMacroInfo(i)
		if macroName == name then
			return i
		end
	end
	return nil
end

local function ReadChunks()
	local chunks = {}
	for i = 1, MAX_CHUNKS do
		local index = FindMacro(MACRO_PREFIX .. i)
		if not index then
			break
		end
		local _, _, body = GetMacroInfo(index)
		if type(body) ~= "string" or body == "" then
			break
		end
		-- The client hands macro bodies back with a trailing newline. Real
		-- newlines inside values are escaped, so any raw one is an artifact
		-- and would otherwise end up glued to the last value of the chunk.
		chunks[#chunks + 1] = body:gsub("\n", "")
	end
	return table.concat(chunks)
end

local function WriteChunks(text)
	-- Refused whole: a prefix cut at an arbitrary character would come back
	-- as wrong values at the next login (a number cut to "0.", a flag cut
	-- to "b"), so the previous macros stay as they are.
	if #text > CHUNK_SIZE * MAX_CHUNKS then
		return false, string.format("settings too large for the macro backup (%d of %d characters)", #text, CHUNK_SIZE * MAX_CHUNKS)
	end
	local written = 0
	local i = 1
	local pos = 1
	while pos <= #text and i <= MAX_CHUNKS do
		local body = text:sub(pos, pos + CHUNK_SIZE - 1)
		local name = MACRO_PREFIX .. i
		local index = FindMacro(name)
		if index then
			EditMacro(index, name, MACRO_ICON, body)
		else
			local created = CreateMacro(name, MACRO_ICON, body, false)
			if not created then
				return false, "no free account macro slot"
			end
		end
		written = i
		pos = pos + CHUNK_SIZE
		i = i + 1
	end
	if pos <= #text then
		return false, "settings too large for the macro backup"
	end
	-- Blank out leftover chunks from a previous, larger save.
	for j = written + 1, MAX_CHUNKS do
		local index = FindMacro(MACRO_PREFIX .. j)
		if not index then
			break
		end
		EditMacro(index, MACRO_PREFIX .. j, MACRO_ICON, "")
	end
	return true
end

--------------------------------------------------------------------------------
-- Restore / write
--------------------------------------------------------------------------------

local lastWritten = nil
local writePending = false
local writeDeferredForCombat = false

function MelloUI:RestoreFromBackup(stage)
	if BACKUP_PAUSED or not MacrosAvailable() then
		return false
	end
	local ok, text = pcall(ReadChunks)
	if not ok then
		return false
	end
	if type(text) ~= "string" or text == "" then
		return false
	end
	if text == lastWritten then
		-- the macros echo our own write (UPDATE_MACROS fires for it): nothing new
		return false
	end
	local applied = self:DeserializeSettings(text)
	lastWritten = text
	self.restoredFromBackup = true
	self.backupRestoredStage = stage
	self.backupRestoredCount = applied
	return applied > 0
end

function MelloUI:WriteBackup(reason)
	if BACKUP_PAUSED or not MacrosAvailable() then
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		writeDeferredForCombat = true
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
		if message ~= self.backupLastError then
			-- said once per distinct cause; the write is tried again on the next change
			self:Print("|cffff4040Could not back up settings to macros:|r %s", message)
		end
		self.backupLastError = message
	end
end

-- Facts for /mello status.
function MelloUI:GetBackupStatus()
	local status = {
		available = MacrosAvailable(),
		paused = BACKUP_PAUSED,
		chunks = 0,
		length = 0,
		capacity = CHUNK_SIZE * MAX_CHUNKS,
		lastWrite = self.backupLastWrite,
		lastReason = self.backupLastReason,
		lastError = self.backupLastError,
		pending = writePending,
		deferredForCombat = writeDeferredForCombat,
		restoredStage = self.backupRestoredStage,
		restoredCount = self.backupRestoredCount,
		inSync = false,
	}
	if status.available then
		local ok, text = pcall(ReadChunks)
		if ok and type(text) == "string" then
			status.length = #text
			for i = 1, MAX_CHUNKS do
				if not FindMacro(MACRO_PREFIX .. i) then
					break
				end
				status.chunks = i
			end
			local okSer, current = pcall(self.SerializeSettings, self)
			status.inSync = okSer and current == text
		end
	end
	return status
end

function MelloUI:ScheduleBackup(reason)
	if writePending or not self.initialized then
		return
	end
	writePending = true
	C_Timer.After(WRITE_DELAY, function()
		writePending = false
		self:WriteBackup(reason or "change")
	end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("UPDATE_MACROS")
Perf.SetScript(frame, "OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if writeDeferredForCombat then
			writeDeferredForCombat = false
			MelloUI:WriteBackup("after combat")
		end
	elseif event == "UPDATE_MACROS" then
		-- Macros can arrive after PLAYER_LOGIN. If the saved variables were
		-- missing and nothing was restored yet, try again now.
		if MelloUI.initialized and MelloUI.dbIsTemporary and not MelloUI.restoredFromBackup then
			if MelloUI:RestoreFromBackup("UPDATE_MACROS") then
				MelloUI:RestartModules()
				MelloUI:Notice("Settings restored from the macro backup.")
			end
		end
	end
end)

MelloUI:Profile("Backup", "backup writes", frame)

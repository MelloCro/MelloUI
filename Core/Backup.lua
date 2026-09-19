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

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI

local MACRO_PREFIX = "MelloUI"
local MACRO_ICON = 134400        -- INV_Misc_QuestionMark
local CHUNK_SIZE = 250           -- macro bodies are limited to 255 characters
local MAX_CHUNKS = 8
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

local function EncodeValue(v)
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

local function DecodeValue(s)
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
				if module.defaults[k] ~= v then
					local enc = EncodeValue(v)
					if enc then
						parts[#parts + 1] = name .. "." .. k .. "=" .. enc
					end
				end
			end
		end
		local flag = self.db.enabled[name]
		if flag ~= nil and flag ~= module.enabledByDefault then
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
					if self.modules[flagName] then
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
	if not MacrosAvailable() then
		return false
	end
	local ok, text = pcall(ReadChunks)
	if not ok then
		return false
	end
	if type(text) ~= "string" or text == "" then
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
	if not MacrosAvailable() then
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
		self.backupLastError = tostring(ok and err or success)
		if not ok or err == "no free account macro slot" then
			self:Print("|cffff4040Could not back up settings to macros:|r %s", tostring(ok and err or success))
		end
	end
end

-- Facts for /mello status.
function MelloUI:GetBackupStatus()
	local status = {
		available = MacrosAvailable(),
		chunks = 0,
		length = 0,
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
frame:SetScript("OnEvent", function(_, event)
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
				MelloUI:Print("Settings restored from the macro backup.")
			end
		end
	end
end)

MelloUI:Profile("Backup", "backup writes", frame)

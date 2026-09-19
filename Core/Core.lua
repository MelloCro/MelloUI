--------------------------------------------------------------------------------
-- MelloUI - Core
--
-- Module registry, saved variables and lifecycle.
--
-- A module is a plain table registered through MelloUI:RegisterModule(name, tbl).
-- Supported fields:
--   title            display name shown in the config panel
--   desc             tooltip / description text
--   defaults         table of default settings for the module
--   enabledByDefault boolean (default true)
--   options          declarative list used by Core/Config.lua to build controls
--   OnAddonLoaded(db) called at ADDON_LOADED (only if the module is enabled)
--   OnInit(db)       called once after saved variables are available
--   OnEnable(db)     called when the module is switched on (and at login if enabled)
--   OnDisable(db)    called when the module is switched off
--   OnSettingChanged(key, value, db)  called when one of its options changes
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local MelloUI = CreateFrame("Frame")
ns.MelloUI = MelloUI
_G.MelloUI = MelloUI

MelloUI.name = ADDON_NAME
MelloUI.version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
MelloUI.modules = {}
MelloUI.moduleOrder = {}

local DB_VERSION = 1

local DB_DEFAULTS = {
	version = DB_VERSION,
	enabled = {},   -- [moduleName] = boolean
	modules = {},   -- [moduleName] = { settings }
	profiles = {},  -- [name] = serialised settings (see Profiles below)
}

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

local PREFIX = "|cff9b8cffMello|rUI: "

function MelloUI:Print(msg, ...)
	if select("#", ...) > 0 then
		msg = string.format(msg, ...)
	end
	print(PREFIX .. tostring(msg))
end

-- Fill missing keys of tbl from defaults (shallow, one nested level for tables).
local function ApplyDefaults(tbl, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(tbl[k]) ~= "table" then
				tbl[k] = {}
			end
			ApplyDefaults(tbl[k], v)
		elseif tbl[k] == nil then
			tbl[k] = v
		end
	end
	return tbl
end
MelloUI.ApplyDefaults = ApplyDefaults

-- Safe call wrapper so one broken module cannot take the whole addon down.
local function SafeCall(module, method, ...)
	local fn = module[method]
	if type(fn) ~= "function" then
		return true
	end
	local ok, err = pcall(fn, module, ...)
	if not ok then
		MelloUI:Print("|cffff4040Error|r in module '%s' (%s): %s", module.name, method, tostring(err))
	end
	return ok
end

--------------------------------------------------------------------------------
-- Module registry
--------------------------------------------------------------------------------

function MelloUI:RegisterModule(name, module)
	assert(type(name) == "string" and name ~= "", "MelloUI:RegisterModule requires a name")
	assert(not self.modules[name], "MelloUI module '" .. name .. "' is already registered")

	module = module or {}
	module.name = name
	module.title = module.title or name
	module.desc = module.desc or ""
	module.defaults = module.defaults or {}
	module.options = module.options or {}
	if module.enabledByDefault == nil then
		module.enabledByDefault = true
	end
	module.isEnabled = false

	self.modules[name] = module
	table.insert(self.moduleOrder, name)

	-- Late registration (after login) still gets initialised.
	if self.initialized then
		self:InitModule(module)
	end

	return module
end

function MelloUI:GetModule(name)
	return self.modules[name]
end

function MelloUI:IterateModules()
	local i = 0
	return function()
		i = i + 1
		local name = self.moduleOrder[i]
		if name then
			return name, self.modules[name]
		end
	end
end

--------------------------------------------------------------------------------
-- CPU profiling (/mello cpu, needs the scriptProfile CVar)
--------------------------------------------------------------------------------

MelloUI.profiled = {}

-- Register a frame (its script handlers) or a function so that /mello cpu can
-- report how much CPU it used. Costs nothing while profiling is off.
function MelloUI:Profile(moduleName, label, target)
	if target ~= nil then
		self.profiled[#self.profiled + 1] = { module = moduleName, label = label, target = target }
	end
	return target
end

function MelloUI:GetModuleDB(name)
	local module = self.modules[name]
	if not module then
		return nil
	end
	self.db.modules[name] = self.db.modules[name] or {}
	return ApplyDefaults(self.db.modules[name], module.defaults)
end

function MelloUI:IsModuleEnabled(name)
	local module = self.modules[name]
	if not module then
		return false
	end
	local flag = self.db.enabled[name]
	if flag == nil then
		return module.enabledByDefault
	end
	return flag
end

function MelloUI:SetModuleEnabled(name, enabled)
	local module = self.modules[name]
	if not module then
		return
	end
	enabled = not not enabled
	self.db.enabled[name] = enabled

	if not self.initialized then
		return
	end
	if self.ScheduleBackup then
		self:ScheduleBackup("module " .. name)
	end

	if enabled and not module.isEnabled then
		module.isEnabled = true
		SafeCall(module, "OnEnable", self:GetModuleDB(name))
	elseif not enabled and module.isEnabled then
		module.isEnabled = false
		SafeCall(module, "OnDisable", self:GetModuleDB(name))
	end
end

function MelloUI:EnableModule(name)
	self:SetModuleEnabled(name, true)
end

function MelloUI:DisableModule(name)
	self:SetModuleEnabled(name, false)
end

-- Called by the config panel when a module setting changes.
function MelloUI:NotifySettingChanged(name, key, value)
	local module = self.modules[name]
	if not module then
		return
	end
	local db = self:GetModuleDB(name)
	db[key] = value
	if module.isEnabled then
		SafeCall(module, "OnSettingChanged", key, value, db)
	end
	if self.ScheduleBackup then
		self:ScheduleBackup("setting " .. tostring(key))
	end
end

function MelloUI:InitModule(module)
	if module.initialized then
		return
	end
	module.initialized = true
	local db = self:GetModuleDB(module.name)
	SafeCall(module, "OnInit", db)
	if self:IsModuleEnabled(module.name) then
		module.isEnabled = true
		SafeCall(module, "OnEnable", db)
	end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function MelloUI:InitDB()
	if type(MelloUIDB) == "table" then
		self.db = MelloUIDB
		self.dbIsTemporary = false
		self.savedVariablesStage = "ADDON_LOADED"
	else
		-- Saved variables are not in place yet. Forever loads them late and
		-- will NOT overwrite a global that already exists, so the global must
		-- stay untouched until the real data shows up. Work on a private
		-- table meanwhile and adopt the real one as soon as it appears.
		self.db = {}
		self.dbIsTemporary = true
	end
	ApplyDefaults(self.db, DB_DEFAULTS)
	self.db.version = DB_VERSION
end

-- Called at every later lifecycle point. If the client replaced the global
-- with the loaded saved variables after we initialised, switch to that table.
-- If it replaced it with something else, keep ours and make sure ours is what
-- gets saved.
function MelloUI:AdoptSavedVariables(stage)
	if self.dbIsTemporary then
		if type(MelloUIDB) ~= "table" then
			return false -- still not loaded; keep waiting
		end
		local temp = self.db
		ApplyDefaults(MelloUIDB, DB_DEFAULTS)
		MelloUIDB.version = DB_VERSION
		self.db = MelloUIDB
		self.dbIsTemporary = false
		self.savedVariablesStage = stage or "late"
		-- Carry over anything changed while the temporary table was in use
		-- (this includes values restored from the macro backup).
		for name, values in pairs(temp.modules or {}) do
			local module = self.modules[name]
			if module then
				local real = self:GetModuleDB(name)
				for k, v in pairs(values) do
					if module.defaults[k] ~= v and real[k] == module.defaults[k] then
						real[k] = v
					end
				end
			end
		end
		for name, flag in pairs(temp.enabled or {}) do
			if self.db.enabled[name] == nil then
				self.db.enabled[name] = flag
			end
		end
		self.db.profiles = self.db.profiles or {}
		for name, text in pairs(temp.profiles or {}) do
			if self.db.profiles[name] == nil then
				self.db.profiles[name] = text
			end
		end
		if self.db.defaultProfile == nil then
			self.db.defaultProfile = temp.defaultProfile
		end
		if self.db.activeProfile == nil then
			self.db.activeProfile = temp.activeProfile
		end
		-- Modules that acted on the temporary table get a second pass.
		for _, module in self:IterateModules() do
			module.db = nil
			if self:IsModuleEnabled(module.name) and type(module.OnAddonLoaded) == "function" then
				SafeCall(module, "OnAddonLoaded", self:GetModuleDB(module.name))
			end
		end
		return true
	end
	if type(MelloUIDB) == "table" and not rawequal(MelloUIDB, self.db) then
		MelloUIDB = self.db
	end
	return false
end

-- After a (late) adoption, modules that are already running must re-read
-- their settings.
function MelloUI:RestartModules()
	for _, module in self:IterateModules() do
		if module.isEnabled then
			local db = self:GetModuleDB(module.name)
			SafeCall(module, "OnDisable", db)
			SafeCall(module, "OnEnable", db)
		end
	end
	for _, module in self:IterateModules() do
		if module._enableSettings then
			for _, setting in ipairs(module._enableSettings) do
				pcall(setting.NotifyUpdate, setting)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Profiles
--
-- A profile is the settings serialised the way the macro backup does it
-- (only values that differ from the defaults). Profiles live in
-- MelloUIDB.profiles; Tools\bake_routes.py bakes them into Media\Profiles.lua
-- (MelloUI_Profiles) so they survive this client's saved variable handling,
-- and the one marked default is applied on a fresh install, that is when no
-- setting differs from the defaults after login.
--------------------------------------------------------------------------------

function MelloUI:Profiles()
	self.db.profiles = self.db.profiles or {}
	if type(MelloUI_Profiles) == "table" then
		if type(MelloUI_Profiles.profiles) == "table" then
			for name, text in pairs(MelloUI_Profiles.profiles) do
				if self.db.profiles[name] == nil and type(text) == "string" then
					self.db.profiles[name] = text
				end
			end
		end
		if self.db.defaultProfile == nil and type(MelloUI_Profiles.default) == "string" and MelloUI_Profiles.default ~= "" then
			self.db.defaultProfile = MelloUI_Profiles.default
		end
	end
	return self.db.profiles
end

function MelloUI:IsProfileBaked(name)
	return type(MelloUI_Profiles) == "table" and type(MelloUI_Profiles.profiles) == "table"
		and MelloUI_Profiles.profiles[name] == self:Profiles()[name]
end

function MelloUI:SaveProfile(name)
	name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if name == "" then
		return false, "a profile needs a name"
	end
	self:Profiles()[name] = self:SerializeSettings()
	self.db.activeProfile = name
	return true
end

function MelloUI:DeleteProfile(name)
	local profiles = self:Profiles()
	if profiles[name] == nil then
		return false
	end
	profiles[name] = nil
	if self.db.defaultProfile == name then
		self.db.defaultProfile = nil
	end
	if self.db.activeProfile == name then
		self.db.activeProfile = nil
	end
	return true
end

function MelloUI:SetDefaultProfile(name)
	if name ~= nil and self:Profiles()[name] == nil then
		return false
	end
	self.db.defaultProfile = name
	return true
end

-- Replace every setting with the serialised ones: defaults first, then the
-- profile, then the running modules pick the new values up.
function MelloUI:ApplySettingsText(text)
	for name, module in self:IterateModules() do
		local db = self:GetModuleDB(name)
		for k in pairs(db) do
			db[k] = nil
		end
		ApplyDefaults(db, module.defaults)
	end
	for name in pairs(self.db.enabled) do
		self.db.enabled[name] = nil
	end
	local applied = self:DeserializeSettings(text)
	if self.initialized then
		for name, module in self:IterateModules() do
			local want = self:IsModuleEnabled(name)
			if want ~= (module.isEnabled or false) then
				self:SetModuleEnabled(name, want)
			end
		end
		self:RestartModules()
		for _, module in self:IterateModules() do
			for _, setting in ipairs(module._settings or {}) do
				pcall(setting.NotifyUpdate, setting)
			end
		end
		if self.ScheduleBackup then
			self:ScheduleBackup("profile")
		end
	end
	return applied
end

function MelloUI:LoadProfile(name)
	local text = self:Profiles()[name]
	if type(text) ~= "string" then
		return false
	end
	self:ApplySettingsText(text)
	self.db.activeProfile = name
	return true
end

-- Nothing configured at all (fresh install, or nothing came back from the
-- saved variables and the macro backup): apply the default profile.
function MelloUI:ApplyDefaultProfileIfFresh()
	if self:SerializeSettings() ~= "" then
		return false
	end
	local profiles = self:Profiles()
	local name = self.db.defaultProfile
	if not name or type(profiles[name]) ~= "string" then
		return false
	end
	self:DeserializeSettings(profiles[name])
	self.db.activeProfile = name
	self.profileAppliedAtLogin = name
	return true
end

MelloUI:RegisterEvent("ADDON_LOADED")
MelloUI:RegisterEvent("VARIABLES_LOADED")
MelloUI:RegisterEvent("PLAYER_LOGIN")
MelloUI:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		self:UnregisterEvent("ADDON_LOADED")
		self:InitDB()
		self:RegisterEvent("PLAYER_LOGOUT")
		-- Early hook for modules that must act before PLAYER_LOGIN (e.g. world fonts).
		for _, module in self:IterateModules() do
			if self:IsModuleEnabled(module.name) and type(module.OnAddonLoaded) == "function" then
				SafeCall(module, "OnAddonLoaded", self:GetModuleDB(module.name))
			end
		end
	elseif event == "VARIABLES_LOADED" then
		self:UnregisterEvent("VARIABLES_LOADED")
		if not self.db then
			self:InitDB()
		end
		self:AdoptSavedVariables("VARIABLES_LOADED")
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		if not self.db then
			self:InitDB()
		end
		self:AdoptSavedVariables("PLAYER_LOGIN")
		if self.dbIsTemporary and self.RestoreFromBackup then
			self:RestoreFromBackup("PLAYER_LOGIN")
		end
		if self:ApplyDefaultProfileIfFresh() then
			self:Print("No settings found; the default profile '%s' was applied.", tostring(self.db.activeProfile))
		end
		self.initialized = true
		for _, module in self:IterateModules() do
			self:InitModule(module)
		end
		if self.BuildConfig then
			self:BuildConfig()
		end
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
	elseif event == "PLAYER_LOGOUT" then
		-- Whatever table we have been editing is the one that must be saved.
		self:AdoptSavedVariables("PLAYER_LOGOUT")
		MelloUIDB = self.db
		if self.WriteBackup then
			self:WriteBackup("logout")
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if self:AdoptSavedVariables("PLAYER_ENTERING_WORLD") then
			self:RestartModules()
		end
		-- Saved variables may still be on their way: keep checking for a while.
		if self.dbIsTemporary and not self.adoptTicker then
			local ticks = 0
			self.adoptTicker = C_Timer.NewTicker(1, function(ticker)
				ticks = ticks + 1
				if not self.dbIsTemporary then
					ticker:Cancel()
					self.adoptTicker = nil
					return
				end
				if self:AdoptSavedVariables("late poll " .. ticks .. "s") then
					self:RestartModules()
					self:Print("Settings loaded late by the client and applied.")
					ticker:Cancel()
					self.adoptTicker = nil
				elseif ticks >= 60 then
					ticker:Cancel()
					self.adoptTicker = nil
				end
			end)
		end
	end
end)

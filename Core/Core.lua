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
--   applyWhenDisabled  true: OnDisable is called at start-up too when the
--                    module is off, for a module that drives others
--   OnSettingChanged(key, value, db)  called when one of its options changes
--   hidden           true: not listed in the configurator (driven by another
--                    module: the kit panels by Painted UI); /mello list shows it
--   important        true: the configurator's tile keeps a gold border, a glowing
--                    icon and an IMPORTANT badge (the UI Modifications entry)
--   options entries may carry `module = "<name>"` (the option belongs to that
--   module: built against its settings) or be `{ type = "include", module = }`
--   (that module's whole option list laid out in place); a toggle with
--   `important = true` is drawn gold with an IMPORTANT hint
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local MelloUI = CreateFrame("Frame")
ns.MelloUI = MelloUI
_G.MelloUI = MelloUI

MelloUI.name = ADDON_NAME
MelloUI.version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
MelloUI.modules = {}

--------------------------------------------------------------------------------
-- The palette (user, 2026-09-23: "a Color Palette that i would like us to hold
-- as a rule in this UI"; the hex of each is the colour of its swatch -- "match
-- the hex code with the actual color" -- not the label written under it).
-- Every colour MelloUI draws itself -- fills, lines, text, selection, hover --
-- comes from here; the painted kit art is tuned to sit with it. { r, g, b } in
-- 0..1. Contrast on mainWindow: text 8.0:1, selectedTrim 5.1:1, mutedText
-- 3.2:1 (large or bold labels only, never small body text).
--   mainWindow    #1F1B16  a window's ground
--   innerPanel    #11100D  a panel sunk into the window (lists, insets)
--   raisedPanel   #2E1F14  a panel standing out of it (cards, plates)
--   border        #3D342A  rules and plain borders
--   trim          #8D642F  ornamental trim
--   text          #C6AF85  body text
--   mutedText     #7F6846  secondary text: labels, hints
--   selectedTab   #4E1812  the selected tab or row
--   selectedTrim  #AE8546  the selected tab's trim, gold highlights, headings
--   hover         #5A3C24  what the pointer is over
--------------------------------------------------------------------------------
local function Hex(hex)
	return { tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255, tonumber(hex:sub(6, 7), 16) / 255, hex = hex:sub(2) }
end
MelloUI.Palette = {
	mainWindow   = Hex("#1F1B16"),
	innerPanel   = Hex("#11100D"),
	raisedPanel  = Hex("#2E1F14"),
	border       = Hex("#3D342A"),
	trim         = Hex("#8D642F"),
	text         = Hex("#C6AF85"),
	mutedText    = Hex("#7F6846"),
	selectedTab  = Hex("#4E1812"),
	selectedTrim = Hex("#AE8546"),
	hover        = Hex("#5A3C24"),
}

-- A palette colour as a chat / font-string colour code: "|cffAE8546"
function MelloUI:PaletteCode(role)
	local c = self.Palette[role]
	return "|cff" .. (c and c.hex or "FFFFFF")
end
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

-- Everything printed is also kept (the last LOG_MAX lines, colour codes
-- stripped) for the copy window: /mellolog shows it in a text box that can
-- be selected and copied, so a dump travels as text instead of screenshots.
local LOG_MAX = 2000
local log = {}

-- A secret value (this client) prints as "[secret]": a format with one
-- secret argument would make the whole message secret and unindexable.
local function Plain(v)
	if issecretvalue and issecretvalue(v) then
		return "[secret]"
	end
	return v
end

function MelloUI:Print(msg, ...)
	local n = select("#", ...)
	if n > 0 then
		local args = { ... }
		for i = 1, n do
			args[i] = Plain(args[i])
		end
		local ok, formatted = pcall(string.format, Plain(msg), unpack(args, 1, n))
		if ok then
			msg = formatted
		else
			-- a "[secret]" where a number was expected: the pieces, joined
			local parts = { tostring(Plain(msg)) }
			for i = 1, n do
				parts[#parts + 1] = tostring(args[i])
			end
			msg = table.concat(parts, " ")
		end
	end
	msg = tostring(Plain(msg))
	print(PREFIX .. msg)
	log[#log + 1] = (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	if #log > LOG_MAX then
		table.remove(log, 1)
	end
end

function MelloUI:ClearLog()
	wipe(log)
end

local copyFrame

-- The copy window: a large text box to select and copy from. In PASTE mode
-- (MelloUI:ShowPaste) the box takes typing and an Import button hands the
-- text on; otherwise whatever is typed is put back at once.
local function CopyFrame()
	if copyFrame then
		return copyFrame
	end
	local f = CreateFrame("Frame", "MelloUICopyFrame", UIParent, "BackdropTemplate")
	f:SetSize(760, 480)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	f:SetBackdropColor(0.06, 0.06, 0.07, 0.97)
	f:SetBackdropBorderColor(0.4, 0.35, 0.25, 1)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", 12, -10)
	f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.hint:SetPoint("TOPRIGHT", -40, -12)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	local scroll = CreateFrame("ScrollFrame", "MelloUICopyScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -32)
	scroll:SetPoint("BOTTOMRIGHT", -32, 12)
	f.scroll = scroll
	local edit = CreateFrame("EditBox", "MelloUICopyEdit", scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(700)
	edit:SetScript("OnEscapePressed", function() f:Hide() end)
	edit:SetScript("OnEditFocusGained", function(self)
		if not f.onAccept then
			self:HighlightText()
		end
	end)
	-- typing must not change the text: put it back (not while pasting)
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and not f.onAccept then
			self:SetText(f.text or "")
			self:HighlightText()
		end
	end)
	scroll:SetScrollChild(edit)
	f.edit = edit
	f.accept = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.accept:SetSize(120, 24)
	f.accept:SetPoint("BOTTOMRIGHT", -34, 10)
	f.accept:SetText("Import")
	f.accept:SetScript("OnClick", function()
		local fn = f.onAccept
		if fn and fn(f.edit:GetText()) then
			f:Hide()
		end
	end)
	f:SetScript("OnHide", function() f.onAccept = nil end)
	tinsert(UISpecialFrames, "MelloUICopyFrame")
	copyFrame = f
	return f
end

-- Show `text` to be selected and copied.
function MelloUI:ShowText(title, text)
	local f = CopyFrame()
	f.onAccept = nil
	f.accept:Hide()
	f.scroll:SetPoint("BOTTOMRIGHT", -32, 12)
	f.hint:SetText("Ctrl+A, Ctrl+C to copy  -  Esc closes")
	f.title:SetText(PREFIX .. (title or ""))
	f.text = text or ""
	f.edit:SetText(f.text)
	f:Show()
	f.edit:SetFocus()
	f.edit:HighlightText()
end

-- An empty box to paste into; Import calls onAccept(text), and the window
-- closes when it returns true.
function MelloUI:ShowPaste(title, onAccept)
	local f = CopyFrame()
	f.onAccept = onAccept
	f.accept:Show()
	f.scroll:SetPoint("BOTTOMRIGHT", -32, 42)
	f.hint:SetText("Ctrl+V to paste  -  Esc closes")
	f.title:SetText(PREFIX .. (title or ""))
	f.text = ""
	f.edit:SetText("")
	f:Show()
	f.edit:SetFocus()
end

function MelloUI:ShowLog(title)
	self:ShowText((title or "log") .. string.format("  (%d lines)", #log), table.concat(log, "\n"))
end

SLASH_MELLOLOG1 = "/mellolog"
SlashCmdList.MELLOLOG = function(msg)
	if msg == "clear" then
		MelloUI:ClearLog()
		MelloUI:Print("Log cleared.")
		return
	end
	MelloUI:ShowLog("log")
end

-- Chat lines nobody asked for: something learned, settings restored late, a
-- hint. Replies to slash commands use Print and always show; these can be
-- turned off with Tweaks > Chat Notices.
function MelloUI:Notice(msg, ...)
	local tweaks = self.db and self.db.modules and self.db.modules.Tweaks
	if tweaks and tweaks.chatNotices == false then
		return
	end
	self:Print(msg, ...)
end

-- One-time hint after the update that moved the settings out of Options > AddOns.
-- The flag lives in the Tweaks settings so the macro backup keeps it.
function MelloUI:ShowMenuButtonTip()
	local tweaks = self.db and self.db.modules and self.db.modules.Tweaks
	if not tweaks or tweaks.menuTipShown then
		return
	end
	tweaks.menuTipShown = true
	if self.ScheduleBackup then
		self:ScheduleBackup("menu tip")
	end
	self:Notice("The settings have their own window now: the MelloUI button in the game menu (Escape), or /mello.")
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
	local perf = MelloUI.Perf
	local t0, m0 = perf and debugprofilestop(), perf and collectgarbage("count")
	local ok, err = pcall(fn, module, ...)
	if perf then
		perf:ModuleCall(module.name, method, debugprofilestop() - t0, collectgarbage("count") - m0)
	end
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
	elseif module.applyWhenDisabled then
		-- A module that DRIVES other modules has to be obeyed while it is off
		-- as well. OnDisable otherwise only runs on the switch being thrown,
		-- never at login, so what it drives came up from its own saved flags
		-- and the screen disagreed with the switch (UI Modifications off with
		-- the whole reskin still on screen, 2026-09-22).
		SafeCall(module, "OnDisable", db)
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
		-- The kit editor writes straight into the db rather than through a
		-- module, so it was not on this list and every edit made before the
		-- client got round to loading its saved variables was thrown away
		-- here (they load late on this client). What was edited THIS session
		-- is the newer of the two, so it wins.
		local function Graft(into, from)
			for key, value in pairs(from) do
				if type(value) ~= "table" then
					into[key] = value
				elseif value[1] ~= nil or type(into[key]) ~= "table" then
					-- an array (a tint, a crop) is replaced whole, never
					-- merged index by index
					into[key] = value
				else
					Graft(into[key], value)
				end
			end
		end
		for _, key in ipairs({ "kitTuning", "kitEditor" }) do
			if type(temp[key]) == "table" then
				if type(self.db[key]) ~= "table" then
					self.db[key] = temp[key]
				else
					Graft(self.db[key], temp[key])
				end
			end
		end
		if self.KitTuning then
			self.KitTuning:Reload()
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
	if self.RefreshConfig then
		self:RefreshConfig()
	end
end

--------------------------------------------------------------------------------
-- Unit names on this client have a first name and a surname (user,
-- 2026-09-22: "only show the character's first name, last name or both").
-- The game's NameUtil (C side) gives the display name with or without the
-- surname and the first name alone; the surname is the rest of the full
-- name. A unit token or a name can be a secret value here (nameplates): a
-- secret first or full name is still handed back (SetText takes it), only
-- the surname needs string work and is nil when it cannot be done.
-- mode: "first", "last", "both". nil when nothing could be read.
local function PlainOrSecret(ok, value)
	if not ok or value == nil then
		return nil
	end
	return value
end

function MelloUI:UnitNameAs(unit, mode)
	if not unit then
		return nil
	end
	local util = NameUtil
	local full, first
	if type(util) == "table" and util.FormatUnitNameForDisplay then
		full = PlainOrSecret(pcall(util.FormatUnitNameForDisplay, unit, true))
		if util.GetUnitFirstName then
			first = PlainOrSecret(pcall(util.GetUnitFirstName, unit))
		end
	end
	if full == nil then
		full = PlainOrSecret(pcall(UnitName, unit))
	end
	if full == nil then
		return nil
	end
	local secretFull = issecretvalue and issecretvalue(full)
	if first == nil and not secretFull then
		first = full:match("^(%S+)") or full
	end
	if mode == "both" then
		return full
	elseif mode == "first" then
		return first
	elseif mode == "last" then
		if secretFull or first == nil or (issecretvalue and issecretvalue(first)) then
			return nil
		end
		local rest = full:sub(#first + 1):gsub("^%s+", "")
		if rest == "" then
			return full   -- no surname: the name as it is
		end
		return rest
	end
	return nil
end

-- Profiles
--
-- A profile is the settings serialised the way the macro backup does it
-- (only values that differ from the defaults). Profiles live in
-- MelloUIDB.profiles; Tools\bake_routes.py bakes them into Media\Profiles.lua
-- (MelloUI_Profiles) so they survive this client's saved variable handling,
-- and the one marked default is applied on a fresh install, that is when no
-- setting differs from the defaults after login.
--------------------------------------------------------------------------------

-- The built-in profile with every module off (user, 2026-09-22: "when the
-- addon is installed for the first time, everything should be off"): the
-- default for a fresh install, made from the module list at every login so
-- a module added later is off in it too. Not baked, not deletable, not
-- overwritable.
MelloUI.FRESH_PROFILE = "Everything Off"

function MelloUI:FreshProfileText()
	local parts = {}
	for name, module in self:IterateModules() do
		if module.enabledByDefault and not module.hidden then
			parts[#parts + 1] = "!" .. name .. "=b0"
		end
		-- the tweak modules folded under UI Modifications follow its qol_
		-- switches: those off too, so switching the umbrella on brings the
		-- reskin alone (user, 2026-09-22: "it should only auto enable the
		-- full reskin and the custom sounds")
		local keys = {}
		for key, value in pairs(module.defaults) do
			if type(key) == "string" and key:sub(1, 4) == "qol_" and value == true then
				keys[#keys + 1] = key
			end
		end
		table.sort(keys)
		for _, key in ipairs(keys) do
			parts[#parts + 1] = name .. "." .. key .. "=b0"
		end
	end
	return table.concat(parts, ";")
end

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
	end
	self.db.profiles[self.FRESH_PROFILE] = self:FreshProfileText()
	if self.db.defaultProfile == nil then
		self.db.defaultProfile = self.FRESH_PROFILE
	end
	return self.db.profiles
end

function MelloUI:IsProfileBaked(name)
	if name == self.FRESH_PROFILE then
		return true
	end
	return type(MelloUI_Profiles) == "table" and type(MelloUI_Profiles.profiles) == "table"
		and MelloUI_Profiles.profiles[name] == self:Profiles()[name]
end

function MelloUI:SaveProfile(name)
	name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if name == "" then
		return false, "a profile needs a name"
	end
	if name == self.FRESH_PROFILE then
		return false, "'" .. name .. "' is built in"
	end
	self:Profiles()[name] = self:SerializeSettings()
	self.db.activeProfile = name
	return true
end

function MelloUI:DeleteProfile(name)
	local profiles = self:Profiles()
	if profiles[name] == nil or name == self.FRESH_PROFILE then
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
	-- false, not nil: "none" chosen, as against never set (Profiles() makes
	-- the built-in profile the default when nothing was chosen)
	self.db.defaultProfile = name or false
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
		if self.RefreshConfig then
			self:RefreshConfig()
		end
		if self.ScheduleBackup then
			self:ScheduleBackup("profile")
		end
	end
	return applied
end

--------------------------------------------------------------------------------
-- Share strings (user, 2026-09-23: "Profile share strings with the game's own
-- encoders"). A profile is already its settings' differences from the
-- defaults, as text; to share it, that text is compressed and turned into
-- plain letters by the game's own encoders (C_EncodingUtil: Deflate, then
-- Base64) behind a tag naming the format:
--
--   !MelloUI1!<base64 of the deflated profile text>
--
-- An import is decoded back and checked -- every entry "key=value", at least
-- one for a module this addon has -- before it becomes a profile. It is only
-- stored under the name given: nothing changes until it is loaded.
--------------------------------------------------------------------------------

local SHARE_TAG = "!MelloUI1!"

local function Deflate()
	return Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
end

function MelloUI:ExportProfile(name)
	local text = self:Profiles()[name]
	if type(text) ~= "string" then
		return nil, "no profile '" .. tostring(name) .. "'"
	end
	local enc = C_EncodingUtil
	if not (enc and enc.CompressString and enc.EncodeBase64) then
		return nil, "this client cannot make share strings"
	end
	local method = Deflate()
	local okC, packed
	if method then
		okC, packed = pcall(enc.CompressString, text, method)
	else
		okC, packed = pcall(enc.CompressString, text)
	end
	if not (okC and type(packed) == "string") then
		return nil, "the profile could not be compressed"
	end
	local okB, letters = pcall(enc.EncodeBase64, packed)
	if not (okB and type(letters) == "string") then
		return nil, "the profile could not be encoded"
	end
	return SHARE_TAG .. letters
end

-- The profile text inside a share string, and how many of its entries are for
-- modules this addon has; nil and the reason when it is not one.
function MelloUI:DecodeProfileString(str)
	if type(str) ~= "string" then
		return nil, "nothing to import"
	end
	-- copied from a chat or a web page it may have gained spaces or line breaks
	str = str:gsub("%s+", "")
	if str:sub(1, #SHARE_TAG) ~= SHARE_TAG then
		return nil, "not a MelloUI profile string (it starts with " .. SHARE_TAG .. ")"
	end
	local enc = C_EncodingUtil
	if not (enc and enc.DecodeBase64 and enc.DecompressString) then
		return nil, "this client cannot read share strings"
	end
	local okB, packed = pcall(enc.DecodeBase64, str:sub(#SHARE_TAG + 1))
	if not (okB and type(packed) == "string" and packed ~= "") then
		return nil, "the string is damaged (cut short while copying?)"
	end
	local method = Deflate()
	local okD, text
	if method then
		okD, text = pcall(enc.DecompressString, packed, method)
	else
		okD, text = pcall(enc.DecompressString, packed)
	end
	if not (okD and type(text) == "string") then
		return nil, "the string is damaged (cut short while copying?)"
	end
	local total, known = 0, 0
	for entry in text:gmatch("[^;]+") do
		total = total + 1
		local key = entry:match("^([^=]+)=.")
		if not key then
			return nil, "the string holds something that is not a MelloUI setting"
		end
		local module = key:match("^!?([^.]+)")
		if module and self.modules[module] then
			known = known + 1
		end
	end
	if text ~= "" and known == 0 then
		return nil, "none of its settings belong to a MelloUI module"
	end
	return text, known, total
end

-- Store a share string as the profile `name` (replacing one of that name).
function MelloUI:ImportProfile(name, str)
	name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if name == "" then
		return false, "type a name for the profile first"
	end
	if name == self.FRESH_PROFILE then
		return false, "'" .. name .. "' is built in"
	end
	local text, known, total = self:DecodeProfileString(str)
	if not text then
		return false, known
	end
	self:Profiles()[name] = text
	if self.ScheduleBackup then
		self:ScheduleBackup("profile import")
	end
	return true, known, total
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
		if self.dbIsTemporary and self.RestoreFromBackup and self:RestoreFromBackup("PLAYER_LOGIN") then
			-- the early hook ran on the defaults at ADDON_LOADED: once more
			-- on the restored settings (the world fonts)
			for _, module in self:IterateModules() do
				module.db = nil
				if self:IsModuleEnabled(module.name) and type(module.OnAddonLoaded) == "function" then
					SafeCall(module, "OnAddonLoaded", self:GetModuleDB(module.name))
				end
			end
		end
		if self:ApplyDefaultProfileIfFresh() then
			self:Notice("No settings found; the default profile '%s' was applied.", tostring(self.db.activeProfile))
		end
		self.initialized = true
		-- the modules come up in TOC order; a module that drives others
		-- (UI Modifications) must not pull them forward out of that order
		-- during this pass (the unit frame panel read the bars' layers
		-- before Bar Textures had set them, 2026-09-21): it sets their
		-- flags and lets this loop enable them in their turn
		self.initializingModules = true
		for _, module in self:IterateModules() do
			self:InitModule(module)
		end
		self.initializingModules = nil
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
		if not self.menuTipTimer then
			-- a few seconds in, after the login spam and a possible late settings load
			self.menuTipTimer = C_Timer.NewTimer(8, function() self:ShowMenuButtonTip() end)
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
					self:Notice("Settings loaded late by the client and applied.")
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

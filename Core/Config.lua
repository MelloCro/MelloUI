--------------------------------------------------------------------------------
-- MelloUI - Config
--
-- Builds the in-game configuration panel using the Blizzard Settings API.
-- Layout:
--   MelloUI                     -> one checkbox per module (enable / disable)
--     +-- <Module title>        -> module specific options (only if it has any)
--
-- Module options are declared as a list, e.g.
--   options = {
--     { type = "header", name = "Components" },
--     { type = "toggle", key = "unitframes", name = "Unit Frames", desc = "..." },
--     { type = "slider", key = "shade", name = "Brightness", min = 0, max = 1, step = 0.05, percent = true },
--     { type = "dropdown", key = "style", name = "Style", values = { {value="a", label="A"}, ... } },
--   }
--------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local MelloUI = ns.MelloUI

local mainCategory

local function VarName(moduleName, key)
	return "MelloUI_" .. moduleName .. "_" .. key
end

local function AddHeader(layout, name)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
end

local function AddToggle(category, moduleName, db, opt)
	local setting = Settings.RegisterAddOnSetting(
		category, VarName(moduleName, opt.key), opt.key, db,
		Settings.VarType.Boolean, opt.name, db[opt.key])
	Settings.CreateCheckbox(category, setting, opt.desc)
	setting:SetValueChangedCallback(function(_, value)
		MelloUI:NotifySettingChanged(moduleName, opt.key, value)
	end)
	return setting
end

local function AddSlider(category, moduleName, db, opt)
	local setting = Settings.RegisterAddOnSetting(
		category, VarName(moduleName, opt.key), opt.key, db,
		Settings.VarType.Number, opt.name, db[opt.key])
	local options = Settings.CreateSliderOptions(opt.min or 0, opt.max or 1, opt.step or 0.05)
	local formatter
	if opt.format then
		formatter = opt.format
	elseif opt.percent then
		formatter = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
	else
		formatter = function(v) return tostring(v) end
	end
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
	Settings.CreateSlider(category, setting, options, opt.desc)
	setting:SetValueChangedCallback(function(_, value)
		MelloUI:NotifySettingChanged(moduleName, opt.key, value)
	end)
	return setting
end

local function AddDropdown(category, moduleName, db, opt)
	local varType = type(db[opt.key]) == "number" and Settings.VarType.Number or Settings.VarType.String
	local setting = Settings.RegisterAddOnSetting(
		category, VarName(moduleName, opt.key), opt.key, db,
		varType, opt.name, db[opt.key])
	local function GetOptions()
		local container = Settings.CreateControlTextContainer()
		for _, entry in ipairs(opt.values) do
			container:Add(entry.value, entry.label, entry.tooltip)
		end
		return container:GetData()
	end
	Settings.CreateDropdown(category, setting, GetOptions, opt.desc)
	setting:SetValueChangedCallback(function(_, value)
		MelloUI:NotifySettingChanged(moduleName, opt.key, value)
	end)
	return setting
end

local builders = {
	toggle = AddToggle,
	slider = AddSlider,
	dropdown = AddDropdown,
}

local function BuildModuleCategory(module)
	if #module.options == 0 then
		return
	end
	local db = MelloUI:GetModuleDB(module.name)
	local category, layout = Settings.RegisterVerticalLayoutSubcategory(mainCategory, module.title)

	-- Enable toggle at the top of every module page as well.
	local enableSetting = Settings.RegisterProxySetting(
		category, VarName(module.name, "__enabled"), Settings.VarType.Boolean,
		"Enable " .. module.title, module.enabledByDefault,
		function() return MelloUI:IsModuleEnabled(module.name) end,
		function(value) MelloUI:SetModuleEnabled(module.name, value) end)
	Settings.CreateCheckbox(category, enableSetting, module.desc)
	module._enableSettings = module._enableSettings or {}
	table.insert(module._enableSettings, enableSetting)

	for _, opt in ipairs(module.options) do
		if opt.type == "header" then
			AddHeader(layout, opt.name)
		else
			local builder = builders[opt.type]
			if builder then
				if db[opt.key] == nil then
					db[opt.key] = module.defaults[opt.key]
				end
				local setting = builder(category, module.name, db, opt)
				module._settings = module._settings or {}
				table.insert(module._settings, setting)
			else
				MelloUI:Print("Unknown option type '%s' in module %s", tostring(opt.type), module.name)
			end
		end
	end
	module.settingsCategory = category
end

--------------------------------------------------------------------------------
-- Profiles page
--------------------------------------------------------------------------------

local profilesFrame

local function ProfileNames()
	local names = {}
	for name in pairs(MelloUI:Profiles()) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

local function RefreshProfilesPage()
	local frame = profilesFrame
	if not frame then
		return
	end
	local db = MelloUI.db
	local active = db.activeProfile and ("|cffffd200" .. db.activeProfile .. "|r") or "|cff888888none|r"
	local default = db.defaultProfile and ("|cffffd200" .. db.defaultProfile .. "|r") or "|cff888888none|r"
	frame.status:SetText(string.format("Active: %s      Default on a fresh install: %s", active, default))
	local names = ProfileNames()
	for i, name in ipairs(names) do
		local row = frame.rows[i]
		if not row then
			row = CreateFrame("Frame", nil, frame)
			row:SetHeight(26)
			row:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 0, -(i - 1) * 28)
			row:SetPoint("RIGHT", frame.list, "RIGHT")
			row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.name:SetPoint("LEFT", 4, 0)
			row.name:SetWidth(200)
			row.name:SetJustifyH("LEFT")
			row.name:SetWordWrap(false)
			row.load = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.load:SetSize(60, 22)
			row.load:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
			row.load:SetText("Load")
			row.default = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.default:SetSize(90, 22)
			row.default:SetPoint("LEFT", row.load, "RIGHT", 4, 0)
			row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.delete:SetSize(60, 22)
			row.delete:SetPoint("LEFT", row.default, "RIGHT", 4, 0)
			row.delete:SetText("Delete")
			row.baked = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			row.baked:SetPoint("LEFT", row.delete, "RIGHT", 8, 0)
			frame.rows[i] = row
		end
		row.profile = name
		row.name:SetText(name)
		local isDefault = db.defaultProfile == name
		row.default:SetText(isDefault and "Default  |cff40ff40*|r" or "Set default")
		row.baked:SetText(MelloUI:IsProfileBaked(name) and "baked" or "not baked yet")
		row.load:SetScript("OnClick", function()
			if MelloUI:LoadProfile(name) then
				MelloUI:Print("Profile '%s' loaded.", name)
			end
			RefreshProfilesPage()
		end)
		row.default:SetScript("OnClick", function()
			MelloUI:SetDefaultProfile(isDefault and nil or name)
			if MelloUI.ScheduleBackup then
				MelloUI:ScheduleBackup("profile default")
			end
			RefreshProfilesPage()
		end)
		row.delete:SetScript("OnClick", function()
			MelloUI:DeleteProfile(name)
			RefreshProfilesPage()
		end)
		row:Show()
	end
	for i = #names + 1, #frame.rows do
		frame.rows[i]:Hide()
	end
	frame.empty:SetShown(#names == 0)
end

local function BuildProfilesPage()
	if profilesFrame or not Settings.RegisterCanvasLayoutSubcategory then
		return
	end
	local frame = CreateFrame("Frame")
	profilesFrame = frame
	frame.rows = {}

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOPLEFT", 16, -16)
	frame.title:SetText("Profiles")
	frame.desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.desc:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
	frame.desc:SetPoint("RIGHT", -16, 0)
	frame.desc:SetJustifyH("LEFT")
	frame.desc:SetText("A profile is a copy of every setting of every module. The one marked default is applied when the addon starts with no settings at all, such as on a fresh install. Profiles are baked into the addon's own files by Tools\\bake_routes.py after a /reload, which is what makes them survive this client's saved-variable handling.")

	frame.nameBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	frame.nameBox:SetSize(220, 22)
	frame.nameBox:SetPoint("TOPLEFT", frame.desc, "BOTTOMLEFT", 6, -16)
	frame.nameBox:SetAutoFocus(false)
	frame.nameBox:SetMaxLetters(40)
	frame.save = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.save:SetSize(150, 22)
	frame.save:SetPoint("LEFT", frame.nameBox, "RIGHT", 8, 0)
	frame.save:SetText("Save current as")
	local function Save()
		local ok, err = MelloUI:SaveProfile(frame.nameBox:GetText())
		if ok then
			MelloUI:Print("Profile '%s' saved. /reload writes it out for the baker.", frame.nameBox:GetText():gsub("^%s+", ""):gsub("%s+$", ""))
			frame.nameBox:SetText("")
			frame.nameBox:ClearFocus()
		else
			MelloUI:Print(err)
		end
		RefreshProfilesPage()
	end
	frame.save:SetScript("OnClick", Save)
	frame.nameBox:SetScript("OnEnterPressed", Save)
	frame.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.status:SetPoint("TOPLEFT", frame.nameBox, "BOTTOMLEFT", -6, -14)
	frame.status:SetJustifyH("LEFT")

	frame.list = CreateFrame("Frame", nil, frame)
	frame.list:SetPoint("TOPLEFT", frame.status, "BOTTOMLEFT", 0, -12)
	frame.list:SetPoint("RIGHT", -16, 0)
	frame.list:SetHeight(400)

	frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 4, -4)
	frame.empty:SetText("No profiles yet. Type a name above and save the current settings.")

	frame:SetScript("OnShow", RefreshProfilesPage)
	local ok, category = pcall(Settings.RegisterCanvasLayoutSubcategory, mainCategory, frame, "Profiles")
	if ok and category then
		MelloUI.profilesCategory = category
	end
end

function MelloUI:BuildConfig()
	if mainCategory then
		return
	end

	local layout
	mainCategory, layout = Settings.RegisterVerticalLayoutCategory("MelloUI")
	self.settingsCategory = mainCategory

	AddHeader(layout, "Modules  -  v" .. tostring(self.version))

	for _, module in self:IterateModules() do
		local setting = Settings.RegisterProxySetting(
			mainCategory, VarName(module.name, "__enabledMain"), Settings.VarType.Boolean,
			module.title, module.enabledByDefault,
			function() return MelloUI:IsModuleEnabled(module.name) end,
			function(value)
				MelloUI:SetModuleEnabled(module.name, value)
				-- keep the checkbox on the module page in sync
				if module._enableSettings then
					for _, other in ipairs(module._enableSettings) do
						other:NotifyUpdate()
					end
				end
			end)
		Settings.CreateCheckbox(mainCategory, setting, module.desc)
		module._enableSettings = module._enableSettings or {}
		table.insert(module._enableSettings, setting)
	end

	for _, module in self:IterateModules() do
		BuildModuleCategory(module)
	end
	BuildProfilesPage()

	Settings.RegisterAddOnCategory(mainCategory)
end

function MelloUI:OpenConfig(moduleName)
	if not mainCategory then
		self:BuildConfig()
	end
	local module = moduleName and self.modules[moduleName]
	if not module and moduleName then
		local wanted = moduleName:lower()
		for name, m in self:IterateModules() do
			if name:lower() == wanted or m.title:lower() == wanted then
				module = m
				break
			end
		end
	end
	if module and module.settingsCategory then
		Settings.OpenToCategory(module.settingsCategory:GetID())
	else
		Settings.OpenToCategory(mainCategory:GetID())
	end
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

SLASH_MELLOUI1 = "/mello"
SLASH_MELLOUI2 = "/melloui"
SlashCmdList.MELLOUI = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S+)%s*(.-)$")

	if cmd == "list" then
		MelloUI:Print("Modules:")
		for name, module in MelloUI:IterateModules() do
			local state = MelloUI:IsModuleEnabled(name) and "|cff40ff40on|r" or "|cffff4040off|r"
			print(string.format("   %s  -  %s (%s)", state, module.title, name))
		end
	elseif cmd == "enable" or cmd == "disable" then
		local module = MelloUI:GetModule(rest)
		if not module then
			for name, m in MelloUI:IterateModules() do
				if name:lower() == rest or m.title:lower() == rest then
					module = m
					break
				end
			end
		end
		if module then
			MelloUI:SetModuleEnabled(module.name, cmd == "enable")
			if module._enableSettings then
				for _, s in ipairs(module._enableSettings) do
					s:NotifyUpdate()
				end
			end
			MelloUI:Print("%s %s", module.title, cmd == "enable" and "enabled" or "disabled")
		else
			MelloUI:Print("Unknown module '%s'. Use /mello list.", rest)
		end
	elseif cmd == "profile" or cmd == "profiles" then
		local sub, name = rest:match("^(%S+)%s*(.-)$")
		if sub == "save" and name ~= "" then
			local ok, err = MelloUI:SaveProfile(name)
			MelloUI:Print(ok and ("Profile '" .. name .. "' saved. /reload writes it out for the baker.") or err)
		elseif sub == "load" and name ~= "" then
			MelloUI:Print(MelloUI:LoadProfile(name) and ("Profile '" .. name .. "' loaded.") or ("No profile '" .. name .. "'."))
		elseif sub == "delete" and name ~= "" then
			MelloUI:Print(MelloUI:DeleteProfile(name) and ("Profile '" .. name .. "' deleted.") or ("No profile '" .. name .. "'."))
		elseif sub == "default" then
			if name == "" or name == "none" then
				MelloUI:SetDefaultProfile(nil)
				MelloUI:Print("No default profile.")
			else
				MelloUI:Print(MelloUI:SetDefaultProfile(name) and ("'" .. name .. "' is applied on a fresh install.") or ("No profile '" .. name .. "'."))
			end
		elseif sub == "list" or sub == nil then
			local names = ProfileNames()
			MelloUI:Print("Profiles (%d). Active: %s, default: %s.", #names, tostring(MelloUI.db.activeProfile or "none"), tostring(MelloUI.db.defaultProfile or "none"))
			for _, n in ipairs(names) do
				print("   " .. n .. (MelloUI:IsProfileBaked(n) and "" or "  (not baked yet)"))
			end
		else
			MelloUI:Print("/mello profile save <name> | load <name> | delete <name> | default <name|none> | list")
		end
		if profilesFrame then
			RefreshProfilesPage()
		end
	elseif cmd == "cpu" then
		if not (GetCVar and GetCVar("scriptProfile") == "1") then
			MelloUI:Print("CPU profiling is off. Run  /console scriptProfile 1  then /reload, and /mello cpu again. Turn it off afterwards with  /console scriptProfile 0  (profiling itself costs a little performance).")
			return
		end
		if rest == "reset" then
			ResetCPUUsage()
			MelloUI:Print("CPU counters reset. Play a while, then /mello cpu.")
			return
		end
		UpdateAddOnCPUUsage()
		local total = GetAddOnCPUUsage(ADDON_NAME) or 0
		local rows = {}
		for _, entry in ipairs(MelloUI.profiled) do
			local ms, calls
			if type(entry.target) == "function" then
				ms, calls = GetFunctionCPUUsage(entry.target, true)
			elseif type(entry.target) == "table" then
				ms, calls = GetFrameCPUUsage(entry.target, true)
			end
			if ms and ms > 0 then
				rows[#rows + 1] = { module = entry.module, label = entry.label, ms = ms, calls = calls or 0 }
			end
		end
		table.sort(rows, function(a, b) return a.ms > b.ms end)
		MelloUI:Print("CPU since login or the last reset: %.0f ms in MelloUI in total.", total)
		for i, row in ipairs(rows) do
			if i > 25 or row.ms < 0.5 then
				break
			end
			print(string.format("   %8.1f ms  %6d calls  %s: %s", row.ms, row.calls, row.module, row.label))
		end
		print("   Hooks and handlers not listed used less than half a millisecond. /mello cpu reset clears the counters.")
	elseif cmd == "dump" then
		local function DumpModule(name, module)
			local db = MelloUI:GetModuleDB(name)
			local state = MelloUI:IsModuleEnabled(name) and "|cff40ff40on|r" or "|cffff4040off|r"
			print(string.format("|cff9b8cff%s|r (%s)", module.title, state))
			local keys = {}
			for k in pairs(db) do keys[#keys + 1] = tostring(k) end
			table.sort(keys)
			for _, k in ipairs(keys) do
				print(string.format("   %s = %s", k, tostring(db[k])))
			end
		end
		local target = MelloUI:GetModule(rest)
		if not target then
			for name, m in MelloUI:IterateModules() do
				if name:lower() == rest or m.title:lower() == rest then
					target = m
					break
				end
			end
		end
		if target then
			DumpModule(target.name, target)
		else
			for name, module in MelloUI:IterateModules() do
				DumpModule(name, module)
			end
		end
	elseif cmd == "status" then
		local green, red, yellow = "|cff40ff40", "|cffff4040", "|cffffff00"
		MelloUI:Print("Status (v%s):", tostring(MelloUI.version))
		if not MelloUI.dbIsTemporary then
			print(string.format("   Saved variables: %sloaded by the client|r (at %s)", green, tostring(MelloUI.savedVariablesStage or "?")))
		else
			print(string.format("   Saved variables: %snot loaded by the client|r (still waiting; the file is only written, never read back)", red))
		end
		local source
		if MelloUI.restoredFromBackup then
			source = string.format("%smacro backup|r (%d values restored at %s)", yellow,
				tonumber(MelloUI.backupRestoredCount) or 0, tostring(MelloUI.backupRestoredStage or "?"))
		elseif not MelloUI.dbIsTemporary then
			source = green .. "saved variables|r"
		else
			source = red .. "defaults|r (nothing to restore from)"
		end
		print("   Settings in use come from: " .. source)
		if type(MelloUI.GetBackupStatus) == "function" then
			local b = MelloUI:GetBackupStatus()
			if not b.available then
				print("   Macro backup: " .. red .. "macro API not available|r")
			else
				local when = b.lastWrite and date("%H:%M:%S", b.lastWrite) or "not yet this session"
				print(string.format("   Macro backup: %d macro(s), %d characters, %s", b.chunks, b.length,
					b.inSync and (green .. "in sync with current settings|r") or (yellow .. "differs from current settings|r")))
				print(string.format("   Last write: %s%s%s", when,
					b.lastReason and (" (" .. tostring(b.lastReason) .. ")") or "",
					b.pending and ", write scheduled" or (b.deferredForCombat and ", waiting for combat to end" or "")))
				if b.lastError then
					print("   Last error: " .. red .. tostring(b.lastError) .. "|r")
				end
			end
		end
	elseif cmd == "help" then
		MelloUI:Print("Commands:")
		print("   /mello              open the configuration panel")
		print("   /mello list         list modules and their state")
		print("   /mello enable <m>   enable a module")
		print("   /mello disable <m>  disable a module")
		print("   /mello dump [m]     print the stored settings of all modules or one module")
		print("   /mello status       where the settings came from and the state of the macro backup")
	else
		MelloUI:OpenConfig(cmd ~= "" and cmd or nil)
	end
end

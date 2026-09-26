--------------------------------------------------------------------------------
-- MelloUI - Edit Mode layout
--
-- The painted reskin is drawn for one arrangement of the HUD: the user's
-- own Edit Mode layout (action bars, side bars, reputation bar, unit and
-- party frames, the two end caps). It ships as the game's share string in
-- Media/EditModeLayout.lua (the 21:9 Immersive) and is put into Edit Mode as
-- an account layout, and made active, when the reskin is switched on (user,
-- 2026-09-22: "if people enable the reskin ... it needs to load my current
-- UI layout"), by the installer, and by /mello layout apply.
--
-- Every screen gets it fitted first (Core/LayoutFit.lua: one fitter for
-- every path), under one name per screen: plain "MelloUI" on the screen it
-- was drawn on, "MelloUI 1920x1080" on another, so two machines sharing the
-- account's layouts keep one each. The UI scale is only read, never set.
--
-- Only the C_EditMode API is used, never the manager frame's own methods
-- (Edit Mode code run from addon code taints and errors on secrets): the
-- layouts table is read, the new layout inserted where the game's import
-- dialog would put it (after the last account layout, else after the
-- presets), saved back, and the game told a layout was added. The manager
-- then applies it on its own EDIT_MODE_LAYOUTS_UPDATED. Never in combat and
-- never while Edit Mode is open (the manager would save its own copy of the
-- list over it): such a change waits until that ends.
--
-- C_EditMode.GetLayouts() returns the SAVED layouts only, while its
-- activeLayout and every index the API takes count the presets (Modern,
-- Classic...) first, the way the manager keeps them (a copy of the presets
-- with the saved ones appended, EditModeManager.lua UpdateLayoutInfo). The
-- list is built the same way here (user, 2026-09-22: "no active layout").
--
--   MelloUI:EditModeLayoutInfo() -> info | nil, why
--       the baked layout as the game's layout info: an account layout named
--       after it, the input-style fix applied (a new table each call)
--   MelloUI:ApplyEditModeLayout(quiet, info, done) -> ok, why, replacedString
--       info given (the installer's fitted layout): put in now under its own
--       name (info.layoutName) and made active; replacedString is the share
--       string of the layout of that name it replaced (nil when it added).
--       info nil (/mello layout apply, the reskin switch): the baked layout
--       fitted to this screen first (LayoutFit:Run, about 2 ms a frame), then
--       put in on a frame of its own; returns true, "fitting" at once. A FAIL
--       (a screen too small for it) keeps the player's own layout.
--       In combat or while Edit Mode is open: false and why, and it is put
--       in when that ends. done(ok, why, report) is told once, at the end.
--       `quiet` skips the chat lines.
--   MelloUI:EditModeState([name | info]) -> state                 read only
--       what putting in the layout of that name (default: this screen's)
--       would change: { name, activeName, activeType, hadMello, melloType,
--       melloString (or melloInfo) }; plain data (kept in the saved settings)
--   MelloUI:ActivateEditModeLayout(name) -> ok, why, gone
--       the saved layout of that name made active, nothing fitted or saved
--       (an alt's answer to the installer's layout question: the account's
--       layouts are shared, so the one the installing character uses stays
--       as it is). gone: there is no layout of that name (the caller puts
--       one in instead). In combat or while Edit Mode is open: false and
--       why, and it is made active when that ends.
--   MelloUI:RestoreEditModeState(state) -> ok, why
--       back to that state: the layout removed when the apply added it, or
--       its old content put back when the apply replaced it; the old active
--       layout made active again, found by name and type (the indices
--       shift); one SaveLayouts. An apply still waiting or fitting is
--       dropped. In combat or while Edit Mode is open: when that ends.
--   MelloUI:ExportEditModeLayout(), MelloUI:EditModeLayoutStatus()
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("EditModeLayout")
local C_Timer = Perf.C_Timer or C_Timer

local Secret = MelloUI.Safe.IsSecret

local pairs, ipairs, type, pcall, tostring = pairs, ipairs, type, pcall, tostring
local tinsert, tremove = table.insert, table.remove

local EMPTY = {}
local BASE = "MelloUI"                 -- the layout's name when the data has none
local WAIT_OWNER = "Edit Mode layout"  -- the bus owner while a change waits for Edit Mode to close
local TEXT = {
	noBake = "no layout is baked (Media/EditModeLayout.lua is empty)",
	noApi = "this client has no Edit Mode layout API",
	unreadable = "the baked layout string is not readable by this client (re-export it with /mello layout export)",
	noRead = "the layouts could not be read",
	noSave = "the layouts could not be saved: %s",
	combat = "in combat; the layout is applied when it ends",
	editMode = "Edit Mode is open; the layout is applied when it closes",
	fitting = "fitting",
	noScreen = "the screen size could not be read",
	notFitted = "the layout could not be fitted",
	installer = "the installer puts its own layout in",
	gone = "that layout is no longer in Edit Mode's list",
	activateCombat = "in combat; the layout is made active when it ends",
	activateEditMode = "Edit Mode is open; the layout is made active when it closes",
	dropped = "not applied: Edit Mode went back to an earlier state",
	noState = "there is no Edit Mode state to go back to",
	noContent = "the old layout's content was not kept",
	noRoom = "Edit Mode already keeps %d layouts of this kind, the most it can; delete one in Edit Mode and try again",
	restoreCombat = "in combat; Edit Mode goes back when it ends",
	restoreEditMode = "Edit Mode is open; it goes back when Edit Mode closes",
}

local function Data()
	local data = MelloUI_EditModeLayout
	if type(data) ~= "table" or type(data.layout) ~= "string" or data.layout == "" then
		return nil
	end
	return data
end

local function Api()
	return C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts and C_EditMode.ConvertStringToLayoutInfo and true or false
end

local function LayoutType(name)
	return Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType[name]
end

-- The presets the game puts in front of the saved layouts (a copy).
local function Presets()
	local list = {}
	local manager = EditModePresetLayoutManager
	local source = type(manager) == "table" and type(manager.presetLayoutInfo) == "table" and manager.presetLayoutInfo or {}
	for i, layout in ipairs(source) do
		list[i] = layout
	end
	return list
end

-- The full list the API indexes: presets, then the saved layouts.
local function FullList()
	local ok, info = pcall(C_EditMode.GetLayouts)
	if not (ok and type(info) == "table" and type(info.layouts) == "table") then
		return nil
	end
	local full = Presets()
	local presets = #full
	for _, layout in ipairs(info.layouts) do
		full[#full + 1] = layout
	end
	return full, info, presets
end

-- The active layout as the game's share string, for baking.
function MelloUI:ExportEditModeLayout()
	if not (Api() and C_EditMode.ConvertLayoutInfoToString) then
		return nil, "this client has no Edit Mode layout API"
	end
	local full, info = FullList()
	if not full then
		return nil, "the layouts could not be read"
	end
	local active = full[info.activeLayout]
	if not active then
		return nil, string.format("no active layout (active index %s of %d)", tostring(info.activeLayout), #full)
	end
	local okS, text = pcall(C_EditMode.ConvertLayoutInfoToString, active)
	if not (okS and type(text) == "string") then
		return nil, "the layout could not be converted"
	end
	return text, active.layoutName
end

--------------------------------------------------------------------------------
-- Layouts as plain values
--------------------------------------------------------------------------------

-- a layout's name and type (nil when there is none, or it cannot be read)
local function NameOf(layout)
	local name = type(layout) == "table" and layout.layoutName or nil
	if Secret(name) or type(name) ~= "string" then
		return nil
	end
	return name
end

local function TypeOf(layout)
	local kind = type(layout) == "table" and layout.layoutType or nil
	if Secret(kind) then
		return nil
	end
	return kind
end

-- the index of the saved (never a preset) layout of that name
local function Find(full, name)
	if name == nil then
		return nil
	end
	local preset = LayoutType("Preset")
	for i, layout in ipairs(full) do
		if NameOf(layout) == name and TypeOf(layout) ~= preset then
			return i
		end
	end
	return nil
end

-- Where the game's import dialog puts a new layout of that type: after the
-- last one of its type (a character layout with none: after the last
-- account one), else after the presets (EditModeManager.lua MakeNewLayout)
local function InsertAt(full, presets, kind)
	local account = LayoutType("Account")
	local same, accountLast = 0, 0
	for i, layout in ipairs(full) do
		local t = TypeOf(layout)
		if t == kind then
			same = i
		end
		if t == account then
			accountLast = i
		end
	end
	if same > 0 then
		return same + 1
	elseif kind ~= account and accountLast > 0 then
		return accountLast + 1
	end
	return presets + 1
end

-- whether Edit Mode keeps one more layout of that type: it keeps at most
-- Constants.EditModeConsts.EditModeMaxLayoutsPerType of each. Returns the
-- answer and that most.
local function RoomFor(full, kind)
	local consts = type(Constants) == "table" and Constants.EditModeConsts
	local most = type(consts) == "table" and consts.EditModeMaxLayoutsPerType
	if Secret(most) or type(most) ~= "number" then
		return true
	end
	local n = 0
	for _, layout in ipairs(full) do
		if TypeOf(layout) == kind then
			n = n + 1
		end
	end
	return n < most, most
end

-- the input style (client 1.60.1.70009 added it after the version: a
-- string exported before that is read with its record count as the
-- style, and SaveLayouts then refuses the whole list -- user,
-- 2026-09-25): mouse and keyboard unless the string gave a real one
local function FixStyle(info)
	local styles = Enum and Enum.InputDeviceInterfaceType
	if styles then
		local style = info.interfaceStyle
		if style ~= styles.Mkb and style ~= styles.Gamepad then
			info.interfaceStyle = styles.Mkb
		end
	end
end

-- a copy with plain keys and values only (the saved settings can keep it)
local function PlainCopy(v, depth)
	if Secret(v) then
		return nil
	end
	local kind = type(v)
	if kind == "string" or kind == "number" or kind == "boolean" then
		return v
	elseif kind ~= "table" or depth > 8 then
		return nil
	end
	local c = {}
	for k, x in pairs(v) do
		if not Secret(k) and (type(k) == "string" or type(k) == "number") then
			c[k] = PlainCopy(x, depth + 1)
		end
	end
	return c
end

-- the name the fitter gives the layout on this screen (LayoutFit:LayoutName)
local function ScreenName()
	local LayoutFit = MelloUI.LayoutFit
	if type(LayoutFit) ~= "table" or not (LayoutFit.LayoutName and LayoutFit.ScreenSize) then
		return nil
	end
	local W, H = LayoutFit:ScreenSize()
	local sw, sh
	if LayoutFit.PhysicalSize then
		sw, sh = LayoutFit:PhysicalSize()
	end
	local data = Data()
	return LayoutFit:LayoutName(W, H, sw, sh, data and data.name)
end

-- The baked layout as the game's layout info: an account layout named after
-- it, the input style fixed. A new table each call (the fitter and Edit Mode
-- may keep it).
function MelloUI:EditModeLayoutInfo()
	local data = Data()
	if not data then
		return nil, TEXT.noBake
	end
	if not (C_EditMode and C_EditMode.ConvertStringToLayoutInfo) then
		return nil, TEXT.noApi
	end
	local ok, info = pcall(C_EditMode.ConvertStringToLayoutInfo, data.layout)
	if not (ok and type(info) == "table") then
		return nil, TEXT.unreadable
	end
	info.layoutType = LayoutType("Account") or info.layoutType
	info.layoutName = data.name
	FixStyle(info)
	return info
end

--------------------------------------------------------------------------------
-- Putting a layout in (now: every check is the caller's)
--------------------------------------------------------------------------------

-- `source` into Edit Mode under its own name, made active; the caller's
-- table is not changed. Returns ok, why, and the share string of the layout
-- of that name it replaced.
local function Put(quiet, source)
	local full, info, presets = FullList()
	if not full then
		return false, TEXT.noRead
	end
	local new = {}
	for k, v in pairs(source) do
		new[k] = v
	end
	local data = Data()
	new.layoutType = LayoutType("Account") or new.layoutType
	new.layoutName = NameOf(source) or (data and data.name) or BASE
	FixStyle(new)
	local index = Find(full, new.layoutName)
	local replaced, replacedString = index ~= nil, nil
	if replaced then
		if C_EditMode.ConvertLayoutInfoToString then
			local ok, text = pcall(C_EditMode.ConvertLayoutInfoToString, full[index])
			if ok and not Secret(text) and type(text) == "string" then
				replacedString = text
			end
		end
		full[index] = new
	else
		-- (a list with more than Edit Mode keeps would not save at all)
		local room, most = RoomFor(full, new.layoutType)
		if not room then
			return false, TEXT.noRoom:format(most)
		end
		index = InsertAt(full, presets, new.layoutType)
		tinsert(full, index, new)
	end
	-- saved the way the manager saves: the full list, presets in front
	info.layouts = full
	local okS, err = pcall(C_EditMode.SaveLayouts, info)
	if not okS then
		return false, TEXT.noSave:format(tostring(err))
	end
	if replaced then
		if info.activeLayout ~= index and C_EditMode.SetActiveLayout then
			pcall(C_EditMode.SetActiveLayout, index)
		end
	elseif C_EditMode.OnLayoutAdded then
		pcall(C_EditMode.OnLayoutAdded, index, true, true)
	elseif C_EditMode.SetActiveLayout then
		pcall(C_EditMode.SetActiveLayout, index)
	end
	if not quiet then
		MelloUI:Print("Edit Mode layout '%s' %s and made active.", new.layoutName, replaced and "updated" or "added")
	end
	return true, nil, replacedString
end

-- the old content of the layout a state recorded (from its share string)
local function OldLayout(state)
	local old
	if type(state.melloString) == "string" and C_EditMode.ConvertStringToLayoutInfo then
		local ok, info = pcall(C_EditMode.ConvertStringToLayoutInfo, state.melloString)
		if ok and type(info) == "table" then
			old = info
		end
	end
	if not old and type(state.melloInfo) == "table" then
		old = PlainCopy(state.melloInfo, 0)
	end
	if old then
		FixStyle(old)
	end
	return old
end

-- Back to a state (now: every check is the caller's). The one layout the
-- apply touched (state.name): removed when the apply added it, its old
-- content put back when it replaced one; the old active layout found again
-- by name and type. Saved once, then the game told as its own dialogs tell
-- it (a layout deleted or added: the characters' active layouts follow).
local function Restore(state)
	local full, info, presets = FullList()
	if not full then
		return false, TEXT.noRead
	end
	local data = Data()
	local name = type(state.name) == "string" and state.name or (data and data.name) or BASE
	local at = Find(full, name)
	local changed, removed, added, why = false, nil, nil, nil
	if state.hadMello then
		local old = OldLayout(state)
		if old then
			old.layoutName = name
			old.layoutType = state.melloType or LayoutType("Account") or old.layoutType
			if at then
				full[at] = old
				changed = true
			elseif RoomFor(full, old.layoutType) then
				added = InsertAt(full, presets, old.layoutType)
				tinsert(full, added, old)
				changed = true
			else
				why = TEXT.noRoom:format((select(2, RoomFor(full, old.layoutType))))
			end
		else
			why = TEXT.noContent   -- (the layout stays as the apply left it)
		end
	elseif at then
		tremove(full, at)
		removed, changed = at, true
	end
	local target
	if type(state.activeName) == "string" then
		for i, layout in ipairs(full) do
			if NameOf(layout) == state.activeName and (state.activeType == nil or TypeOf(layout) == state.activeType) then
				target = i
				break
			end
		end
	end
	if changed then
		-- (the active index saved as the manager saves it after its own
		-- delete or add; the game fixes it, then the old one is made active)
		info.layouts = full
		local ok, err = pcall(C_EditMode.SaveLayouts, info)
		if not ok then
			return false, TEXT.noSave:format(tostring(err))
		end
		if removed and C_EditMode.OnLayoutDeleted then
			pcall(C_EditMode.OnLayoutDeleted, removed)
		elseif added and C_EditMode.OnLayoutAdded then
			pcall(C_EditMode.OnLayoutAdded, added, false, false)
		end
	end
	if target and C_EditMode.SetActiveLayout and (changed or target ~= info.activeLayout) then
		pcall(C_EditMode.SetActiveLayout, target)
	end
	return true, why
end

-- The saved layout of that name made active (now: every check is the
-- caller's). Nothing is saved: the list stays as it is. Returns ok, why,
-- and whether there is no layout of that name.
local function Activate(name)
	local full, info = FullList()
	if not full then
		return false, TEXT.noRead, false
	end
	local at = Find(full, name)
	if not at then
		return false, TEXT.gone, true
	end
	if info.activeLayout ~= at and C_EditMode.SetActiveLayout then
		local ok, err = pcall(C_EditMode.SetActiveLayout, at)
		if not ok then
			return false, tostring(err), false
		end
	end
	return true, nil, false
end

--------------------------------------------------------------------------------
-- Waiting: combat, Edit Mode open, the fit
--------------------------------------------------------------------------------

-- what waits for the fight or Edit Mode to end: an apply (its layout, or nil
-- for this screen's fit of the baked one), a restore, a layout to make
-- active (its name), and who is told
local wait = { apply = false, quiet = true, info = nil, dones = nil, report = nil, restore = nil, activate = nil }
-- the fit under way for a plain apply: { job, quiet, dones, fitted, report }
local fitting
local Resume, Request

-- (Core's readers, one each: the fight; Edit Mode open, read only -- its
-- manager shown, or still active while a game panel hides it for a moment)
local InCombat, EditModeOpen = MelloUI.InCombat, MelloUI.EditModeOpen

local function Blocked()
	if InCombat() then
		return "combat"
	elseif EditModeOpen() then
		return "editmode"
	end
	return nil
end

-- fn(key) on the next frame (the kit's shared pass; a timer before the kit is there)
local function Later(key, fn)
	local Kit = MelloUI.Kit
	if type(Kit) == "table" and Kit.NextFrame then
		Kit:NextFrame(key, fn)
	else
		C_Timer.After(0, function()
			fn(key)
		end)
	end
end

-- every caller told, once (an error in one goes to the error handler)
local function Tell(dones, ok, why, report)
	if not dones then
		return
	end
	for i = 1, #dones do
		local okC, err = pcall(dones[i], ok, why, report)
		if not okC then
			local handler = geterrorhandler and geterrorhandler()
			if type(handler) == "function" then
				handler(err)
			end
		end
	end
end

-- two lists of callers as one
local function Join(a, b)
	if not a then
		return b
	end
	for i = 1, #(b or EMPTY) do
		a[#a + 1] = b[i]
	end
	return a
end

local waiter = CreateFrame("Frame")
Perf.SetScript(waiter, "OnEvent", function(self)
	self:UnregisterAllEvents()
	Resume()
end)

local function OnEditMode(entering)
	if entering == false then
		-- (a frame later: the manager is hidden by then, and nothing is saved
		-- from inside its own exit)
		Later(wait, Resume)
	end
end

-- the fight's end (the game's event) or Edit Mode's close (the bus), taken
-- only while something waits
local function Wait(why)
	if why == "combat" then
		waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
	else
		MelloUI:On("editmode", OnEditMode, WAIT_OWNER)
	end
end

Resume = function()
	waiter:UnregisterAllEvents()
	MelloUI:Off(WAIT_OWNER, "editmode")
	if not (wait.apply or wait.restore or wait.activate) then
		return
	end
	local why = Blocked()
	if why then
		Wait(why)
		return
	end
	local restore, apply, quiet, info, dones, report = wait.restore, wait.apply, wait.quiet, wait.info, wait.dones, wait.report
	local activate = wait.activate
	wait.restore, wait.apply, wait.quiet, wait.info, wait.dones, wait.report = nil, false, true, nil, nil, nil
	wait.activate = nil
	if restore then
		local ok, err = Restore(restore)
		if not ok then
			MelloUI:Print("Edit Mode layout: %s", tostring(err))
		end
	end
	if activate then
		local ok, err = Activate(activate)
		if not ok then
			MelloUI:Print("Edit Mode layout: %s", tostring(err))
		end
	end
	if apply then
		local ok, err = Request(quiet, info, dones, report)
		if not ok and not quiet then
			MelloUI:Print("Edit Mode layout: %s", tostring(err))
		end
	end
end

-- an apply (or a layout to make active) waiting or fitting is not wanted
-- any more (Edit Mode goes back)
local function Drop()
	local f, dones = fitting, wait.dones
	fitting = nil
	wait.apply, wait.quiet, wait.info, wait.dones, wait.report = false, true, nil, nil, nil
	wait.activate = nil
	if f and f.job and MelloUI.LayoutFit then
		MelloUI.LayoutFit:Cancel(f.job)
	end
	Tell(f and f.dones, false, TEXT.dropped)
	Tell(dones, false, TEXT.dropped)
end

-- the fit's answer, on a frame of its own: put in on a pass, or the
-- player's own layout kept
local function PutFitted(f)
	if fitting ~= f then
		return
	end
	fitting = nil
	local report = f.report
	if not (type(f.fitted) == "table" and type(report) == "table" and report.pass) then
		local why = type(report) == "table" and (report.why or report.verdict) or TEXT.notFitted
		if not f.quiet then
			MelloUI:Print("Edit Mode layout: %s", tostring(why))
		end
		Tell(f.dones, false, why, report)
		return
	end
	-- (the caller had its answer frames ago: a refusal is said here)
	local ok, why = Request(f.quiet, f.fitted, f.dones, report)
	if not ok and not f.quiet then
		MelloUI:Print("Edit Mode layout: %s", tostring(why))
	end
end

-- The baked layout fitted to this screen (LayoutFit:Run, a frame's share at
-- a time), then put in. One fit at a time: a caller that comes meanwhile is
-- told when it ends.
local function Fit(quiet, dones)
	if fitting then
		fitting.quiet = fitting.quiet and quiet and true or false
		fitting.dones = Join(fitting.dones, dones)
		return true, TEXT.fitting
	end
	local info, why = MelloUI:EditModeLayoutInfo()
	if not info then
		Tell(dones, false, why)
		return false, why
	end
	local LayoutFit = MelloUI.LayoutFit
	if type(LayoutFit) ~= "table" or not LayoutFit.Run then
		-- (no fitter: the layout as it was drawn)
		local ok, err, replaced = Put(quiet, info)
		Tell(dones, ok, err)
		return ok, err, replaced
	end
	local W, H = LayoutFit:ScreenSize()
	if not (W and H) then
		Tell(dones, false, TEXT.noScreen)
		return false, TEXT.noScreen
	end
	local data = Data()
	local f = { quiet = quiet and true or false, dones = dones }
	fitting = f
	-- (MelloUI's own settings as they are now: the window places, the
	-- tracker, the bars that hold actions)
	local ok, job = pcall(LayoutFit.Inputs, LayoutFit)
	if ok then
		ok, job = pcall(LayoutFit.Run, LayoutFit, info, W, H, job, function(fitted, _, report)
			if fitting == f then
				f.fitted, f.report = fitted, report
				Later(f, PutFitted)
			end
		end, { baseName = data and data.name })
	end
	if not ok then
		fitting = nil
		why = TEXT.notFitted .. ": " .. tostring(job)
		Tell(dones, false, why)
		return false, why
	end
	f.job = job
	return true, TEXT.fitting
end

-- now, when nothing is in the way; else when that ends
Request = function(quiet, info, dones, report)
	local why = Blocked()
	if why then
		if wait.apply then
			wait.quiet = wait.quiet and quiet and true or false
		else
			wait.quiet = quiet and true or false
		end
		wait.apply, wait.info, wait.report = true, info, report   -- (the newest layout wins)
		wait.dones = Join(wait.dones, dones)
		Wait(why)
		return false, why == "combat" and TEXT.combat or TEXT.editMode
	end
	if info then
		local ok, err, replaced = Put(quiet, info)
		Tell(dones, ok, err, report)
		return ok, err, replaced
	end
	return Fit(quiet, dones)
end

--------------------------------------------------------------------------------
-- The API
--------------------------------------------------------------------------------

-- A layout into Edit Mode, made active (see the header): `info` now, or the
-- baked one fitted to this screen first.
function MelloUI:ApplyEditModeLayout(quiet, info, done)
	local dones = type(done) == "function" and { done } or nil
	if type(info) ~= "table" then
		info = nil
		if not Data() then
			Tell(dones, false, TEXT.noBake)
			return false, TEXT.noBake
		end
		-- (the installer's own apply puts in its fitted layout itself)
		local installer = MelloUI.Installer
		if type(installer) == "table" and installer.applying then
			Tell(dones, false, TEXT.installer)
			return false, TEXT.installer
		end
	end
	if not Api() then
		Tell(dones, false, TEXT.noApi)
		return false, TEXT.noApi
	end
	return Request(quiet, info, dones)
end

-- What putting in the layout of that name (a name, or a layout info; by
-- default this screen's) would change, read only: the active layout by name
-- and type, and the layout of that name if there is one, as its share
-- string. Plain data: the installer keeps it in the saved settings.
function MelloUI:EditModeState(which)
	local name
	if type(which) == "string" then
		name = which
	elseif type(which) == "table" then
		name = NameOf(which)
	end
	local data = Data()
	name = name or ScreenName() or (data and data.name) or BASE
	local state = { name = name, hadMello = false }
	if not Api() then
		return state
	end
	local full, info = FullList()
	if not full then
		return state
	end
	local active = full[info.activeLayout]
	if active then
		state.activeName, state.activeType = NameOf(active), TypeOf(active)
	end
	local at = Find(full, name)
	if at then
		local layout = full[at]
		state.hadMello, state.melloType = true, TypeOf(layout)
		if C_EditMode.ConvertLayoutInfoToString then
			local ok, text = pcall(C_EditMode.ConvertLayoutInfoToString, layout)
			if ok and not Secret(text) and type(text) == "string" then
				state.melloString = text
			end
		end
		if not state.melloString then
			state.melloInfo = PlainCopy(layout, 0)
		end
	end
	return state
end

-- A layout already in Edit Mode's list made active (see the header).
function MelloUI:ActivateEditModeLayout(name)
	if type(name) ~= "string" then
		return false, TEXT.gone, true
	end
	if not Api() then
		return false, TEXT.noApi, false
	end
	local full = FullList()
	if full and not Find(full, name) then
		return false, TEXT.gone, true
	end
	local why = Blocked()
	if why then
		wait.activate = name
		Wait(why)
		return false, why == "combat" and TEXT.activateCombat or TEXT.activateEditMode, false
	end
	return Activate(name)
end

-- Back to a state EditModeState read (see the header).
function MelloUI:RestoreEditModeState(state)
	if type(state) ~= "table" then
		return false, TEXT.noState
	end
	if not Api() then
		return false, TEXT.noApi
	end
	Drop()
	local why = Blocked()
	if why then
		wait.restore = state
		Wait(why)
		return false, why == "combat" and TEXT.restoreCombat or TEXT.restoreEditMode
	end
	return Restore(state)
end

function MelloUI:EditModeLayoutStatus()
	local data = Data()
	if not Api() then
		return "no Edit Mode layout API on this client"
	end
	local full, info, presets = FullList()
	local active = full and full[info.activeLayout]
	local names = {}
	for i, layout in ipairs(full or {}) do
		names[#names + 1] = string.format("%d:%s%s", i, tostring(layout.layoutName), i == info.activeLayout and "*" or "")
	end
	return string.format("baked layout %s (%d chars); Edit Mode: %d presets + %d saved, active %s: %s", data and "'" .. data.name .. "'" or "none",
		data and #data.layout or 0, presets or 0, full and (#full - (presets or 0)) or 0, active and tostring(active.layoutName) or "?", table.concat(names, " "))
end

-- the media data files load next: their time is counted from here
MelloUI.Perf:Scope("Media data files")

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
--   MelloUI:EditModeSystemAnchor(system, index) -> point, relativeTo,
--       relativePoint, x, y, inDefault | nil                          read only
--       where the ACTIVE saved layout puts one system (Enum.EditModeSystem;
--       index: its systemIndex, nil for a system without one): relativeTo is
--       a frame's name ("UIParent" when it names none), inDefault true while
--       the system sits at Edit Mode's default place (a frame the game's
--       managed containers lay out then goes where they say). nil when the
--       active layout is a preset (its place is the game's own), the system
--       is not in it, or anything reads secret. Edit Layout's "Back to Edit
--       Mode's place" for the minimap, the chat, the objective tracker and
--       the damage meter (Core/EditLayoutWindows.lua's four). Each value checked
--       plainly, as the Quest Tracker's own read of the tracker's place.
--
--   MelloUI:EditModeSystemSettings(system, index) -> values, preset, name,
--       layoutType | nil, why                                         read only
--       the ACTIVE layout's raw values of one system ({ [setting] = value },
--       the settings it has only; Enum.EditModeSystem, its systemIndex),
--       held changes over them; preset true while the active layout is one
--       of the game's presets; name and layoutType (Enum.EditModeLayoutType)
--       the layout's
--   MelloUI:EditModeLayoutSystemSettings(name, system, index, layoutType)
--       -> values | nil, why                                (0.25.0) read only
--       a SAVED layout's raw values of one system, found by name (and type,
--       when given), active or not, never a preset; as saved, nothing held
--   MelloUI:EditModeAnchorSoon(system, index, anchor, done)        (0.20.2)
--       a system's place held with the settings' changes and written with
--       them (one save, the preset question once, the reload line once):
--       anchor = { point, relativeTo (a frame's name), relativePoint,
--       offsetX, offsetY } at scale 1, as Edit Mode keeps it; written as its
--       anchorInfo, its second anchor dropped, isInDefaultPosition false (Edit
--       Layout's moves of Edit Mode's systems: Core/EditLayoutBridge.lua D);
--       (2.1.0) anchor.inDefault: isInDefaultPosition true instead (the game's
--       default anchor: Edit Layout's "Default place")
--   MelloUI:EditModeHeldAnchor(system, index) -> as EditModeSystemAnchor (2.1.0)
--       the place held to be written (above), nil when none is held: a place
--       Edit Layout saved a moment ago (its box's "Attached to")
--   MelloUI:SetEditModeSystemSettings(system, index, values, copy, done)
--       -> ok, why, saved
--       values saved into the active layout's system (0.19.9); the game
--       shows them from the next reload (never told to lay out from here).
--       A preset active: false, "preset", nothing changed -- unless `copy`:
--       the preset copied first as an account layout "<preset> (MelloUI)",
--       saved as the active one ((2.1.0) the account's copy of it made
--       before is used again, never a second one). In combat or while Edit Mode is open: false
--       and why, saved when that ends. done(ok, why, saved) once; saved:
--       something changed and the layouts were saved.
--   MelloUI:SetEditModeLayoutSettings(entries, done) -> ok, why, saved
--       (0.25.0) values saved into saved layouts BY NAME, the active one or
--       not: entries { { layout = name, layoutType (optional: that type
--       only), system, index, values }, ... } in ONE save; never a preset (a
--       preset's name is no saved layout); a layout no longer there (or not
--       this character's: GetLayouts lists only its own character layouts),
--       or without the system, skipped (nothing to change).
--       Otherwise as SetEditModeSystemSettings (Action Bars' Hide Bar Art
--       giving the game's value back to every layout it changed).
--   MelloUI:SayEditModeReload()
--       (0.25.0) the line to type /reload, once a session (the one the
--       configurator's way in says), for a change the player asked for.
--   MelloUI:EditModeLayoutCheck(add)                    (2.1.0) read only
--       /mello layout check: the client's layouts, Edit Mode's own copy,
--       Mello's layout, the last install's answer, this session's writes,
--       each system's saved place against its frame's; add(fmt, ...) a line
--       (the end of this file)
--   MelloUI:EditModeSettingsSoon(system, index, values[, done])
--       the configurator's way in: the values held (the readers show them),
--       saved 0.4 s after the last change, every held one in one save; a
--       preset active: asked once (MelloUI:Confirm) whether to copy it,
--       nothing saved on No; the first save of a session says to type
--       /reload (the game blocks a reload MelloUI's code asks for).
--
-- Told on the bus once a layout went in (Core.lua's topic table):
--   "editmodelayout", "put", name     put into Edit Mode and made active
--                                     (every path: the installer's fitted
--                                     layout, /mello layout apply, the
--                                     reskin switch's one-time layout, a
--                                     wait that ended)
--   "editmodelayout", "active", name  a saved layout made active (an alt's
--                                     answer, now or once the wait ended)
-- Never for a FAIL, a refusal, a dropped wait or a restore. The Quest
-- Tracker records there where the layout hangs the game's tracker.
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
	-- (0.19.9: one system's settings)
	noActive = "the active layout could not be read",
	noSystem = "the active layout has no such element",
	settingsCombat = "in combat; the layout changes when the fight ends",
	settingsEditMode = "Edit Mode is open; the layout changes when it closes",
	copyName = "%s (MelloUI)",
	presetAsk = "Your active Edit Mode layout is the game's %s preset, which can't be changed. Make a copy called '%s' and use it?",
	presetYes = "Make a copy",
	-- (2.1.0, el-15) the copy made before (another character, an earlier session): used again, never a second one
	presetUse = "Your active Edit Mode layout is the game's %s preset, which can't be changed. Use your copy '%s' for this change?",
	presetUseYes = "Use it",
	presetNo = "Cancel",
	reloadSay = "Edit Mode layout saved: type /reload to see it.",
	reloadPending = "Edit Mode layout saved into '%s'. The game switches to it only with a reload: Edit Layout > Layout > Reload now.",
	-- (0.22.0: an older MelloUI layout deleted at the player's word)
	deleteCombat = "not in a fight: delete it when the fight ends",
	deleteEditMode = "close Edit Mode first",
	-- (2.1.0, el-15) Edit Mode opened on its older copy of the list (Unread below)
	unread = "Edit Mode still shows your layout from before MelloUI's last change. Close it without saving to load the change, or type /reload: saving here puts the older layout back.",
}

-- (2.1.0, el-15) what this session's writes did, newest first (the last JOURNAL_KEEP): read by /mello layout check
-- only; nothing saved (an install's own answer is kept on its restore point, MelloUI.db.installer)
local journal = {}
local JOURNAL_KEEP = 8
local function Note(fmt, ...)
	local ok, line = pcall(string.format, fmt, ...)
	tinsert(journal, 1, tostring(date("%H:%M:%S")) .. " " .. (ok and line or tostring(fmt)))
	journal[JOURNAL_KEEP + 1] = nil
end

-- (2.1.0, el-15) Edit Mode keeps its own copy of the layouts, read at login, when the game is told to lay out
-- (EDIT_MODE_LAYOUTS_UPDATED) and when Edit Mode CLOSES (ExitEditMode -> RevertAllChanges reads C_EditMode.GetLayouts
-- and lays it out), never when it opens (EnterEditMode). After a save of ours the game was not told about, Edit Mode
-- opens on the older list, and its own Save puts that list back over ours (el-14's finding; with it Edit Layout's
-- copies of those places go too). Its first open since is told so, once: closed without saving, it loads ours.
-- Listened to only while such a save waits (nothing at login).
local UNREAD_OWNER = "Edit Mode layout: unread"
local unread = false
local function OnUnreadEditMode(entering)
	if entering then
		MelloUI:Announce(TEXT.unread, "info")
		local look = MelloUI.CentreLook
		if not (look and look.Setting and look.Setting("noticeToChat")) then
			MelloUI:Print(TEXT.unread)
		end
	else
		unread = false   -- (its close read the saved list)
		MelloUI:Off(UNREAD_OWNER, "editmode")
	end
end

local function Unread(on)
	if on == unread then
		return
	end
	unread = on
	if on then
		MelloUI:On("editmode", OnUnreadEditMode, UNREAD_OWNER)
	else
		MelloUI:Off(UNREAD_OWNER, "editmode")
	end
end

local function Data(skin)
	-- (1.0: the painted reskin's own while MelloUI_Oldschool is loaded; 1.2.4: a skin's own when the installer names it)
	local data = MelloUI:ShippedEditMode(skin)
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

-- the index of the saved (never a preset) layout of that name; (0.25.0) of
-- that type too when `kind` is given (an account and a character layout can
-- share a name)
local function Find(full, name, kind)
	if name == nil then
		return nil
	end
	local preset = LayoutType("Preset")
	for i, layout in ipairs(full) do
		local t = TypeOf(layout)
		if NameOf(layout) == name and t ~= preset and (kind == nil or t == kind) then
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
-- may keep it). skin (1.2.4, the installer's Skin step): that skin's shipped
-- layout (MelloUI:ShippedEditMode)
function MelloUI:EditModeLayoutInfo(skin)
	local data = Data(skin)
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
		Note("put '%s': refused by SaveLayouts: %s", new.layoutName, tostring(err))
		return false, TEXT.noSave:format(tostring(err))
	end
	-- (2.1.0, el-15) told: the game lays it out at once (its synchronous EDIT_MODE_LAYOUTS_UPDATED); a layout of
	-- that name replaced while it was already the active one is only saved -- the game shows it from the next
	-- reload, so the player is told to type it (the installer's Keep reloads by itself)
	local told = true
	if replaced then
		if info.activeLayout ~= index and C_EditMode.SetActiveLayout then
			pcall(C_EditMode.SetActiveLayout, index)
		else
			told = false
		end
	elseif C_EditMode.OnLayoutAdded then
		pcall(C_EditMode.OnLayoutAdded, index, true, true)
	elseif C_EditMode.SetActiveLayout then
		pcall(C_EditMode.SetActiveLayout, index)
	end
	Note("put '%s' at %d (%s); the game told to lay it out: %s", new.layoutName, index, replaced and "replaced" or "added",
		told and "yes" or "no (it was the active one already: after a reload)")
	Unread(not told)
	-- (told on the bus: the Quest Tracker records where it hangs the game's
	-- tracker, whichever path put it in)
	MelloUI:Fire("editmodelayout", "put", new.layoutName)
	if not quiet then
		MelloUI:Print("Edit Mode layout '%s' %s and made active.", new.layoutName, replaced and "updated" or "added")
		if not told then
			MelloUI:Print(TEXT.reloadSay)
		end
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
			Note("restore '%s': refused by SaveLayouts: %s", name, tostring(err))
			return false, TEXT.noSave:format(tostring(err))
		end
		Note("restore '%s': %s", name, removed and "removed" or "its old content back")
		if removed and C_EditMode.OnLayoutDeleted then
			pcall(C_EditMode.OnLayoutDeleted, removed)
		elseif added and C_EditMode.OnLayoutAdded then
			pcall(C_EditMode.OnLayoutAdded, added, false, false)
		end
	end
	if target and C_EditMode.SetActiveLayout and (changed or target ~= info.activeLayout) then
		pcall(C_EditMode.SetActiveLayout, target)
		Unread(false)
	elseif changed and not (removed or added) then
		Unread(true)   -- (the old content saved over the same index: the game reads it at the next reload)
	elseif removed or added then
		Unread(false)
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
			Note("activate '%s': %s", name, tostring(err))
			return false, tostring(err), false
		end
	end
	Note("activate '%s' at %d", name, at)
	if info.activeLayout ~= at then
		Unread(false)
	end
	MelloUI:Fire("editmodelayout", "active", name)
	return true, nil, false
end

--------------------------------------------------------------------------------
-- (2.1.0, el-15; the user's switch test in the real client, 2026-10-31: "'Classic' saved as the active one", then
-- "the game kept 'Modern (MelloUI)' active") The client does not take info.activeLayout from SaveLayouts. A layout
-- MelloUI saved as the active one while the game kept another (the Layout list's Use / New / Copy / Import / Delete,
-- a preset's copy) waits here, and is made active right before the reload the player asks for with the bridge's
-- secure "Reload now" button (its PreClick: MelloUI:EditModeActivateNow), the installer's way: the manager's
-- synchronous re-layout then runs in a session the reload ends at once, never in a live one. Out of combat, Edit
-- Mode closed. One at a time (the newest wins); this session only.
--   MelloUI:EditModeActivePending() -> name, layoutType | nil
--   MelloUI:EditModeActivateNow() -> ok   (a secure /reload button's PreClick only)
--------------------------------------------------------------------------------
local pendingActive = nil   -- { name, kind = Enum.EditModeLayoutType }

-- after a save that named `active` the active one: read back; the game kept another -> it waits (returns that name)
local function ReadBackActive(full, active)
	local back, backInfo = FullList()
	local now = back and backInfo and backInfo.activeLayout
	local wanted = full[active]
	if not (back and wanted and not Secret(now) and type(now) == "number") then
		return nil
	end
	if now == active then
		pendingActive = nil
		return nil
	end
	pendingActive = { name = NameOf(wanted), kind = TypeOf(wanted) }
	return NameOf(back[now]) or "?", now
end

function MelloUI:EditModeActivePending()
	if pendingActive then
		return pendingActive.name, pendingActive.kind
	end
	return nil
end

function MelloUI:EditModeActivateNow()
	local want = pendingActive
	if not (want and Api() and C_EditMode.SetActiveLayout) or InCombatLockdown() or MelloUI.EditModeOpen() then
		return false
	end
	pendingActive = nil
	local full, info = FullList()
	for i, layout in ipairs(full or EMPTY) do
		if NameOf(layout) == want.name and TypeOf(layout) == want.kind then
			if info.activeLayout == i then
				return true
			end
			local ok, err = pcall(C_EditMode.SetActiveLayout, i)
			Note("activate '%s' at %d right before the reload: %s", tostring(want.name), i, ok and "done" or tostring(err))
			return ok
		end
	end
	Note("activate '%s' before the reload: no longer in the list", tostring(want.name))
	return false
end

--------------------------------------------------------------------------------
-- Waiting: combat, Edit Mode open, the fit
--------------------------------------------------------------------------------

-- what waits for the fight or Edit Mode to end: an apply (its layout, or nil
-- for this screen's fit of the baked one), a restore, a layout to make
-- active (its name), and who is told
local wait = { apply = false, quiet = true, info = nil, dones = nil, report = nil, restore = nil, activate = nil,
	settings = {} }   -- (0.19.9: one system's settings: { entries, copy, done } batches, in order)
-- the fit under way for a plain apply: { job, quiet, dones, fitted, report }
local fitting
local Resume, Request
local WriteSettings   -- (below: one system's settings)

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
	if not (wait.apply or wait.restore or wait.activate or #wait.settings > 0) then
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
	-- (0.19.9) one system's settings: every batch that waited in ONE save, in
	-- order (a later entry for a system wins), the copy if any asked for it
	if #wait.settings > 0 then
		local batches = wait.settings
		wait.settings = {}
		local entries, copy = {}, false
		for _, b in ipairs(batches) do
			for _, entry in ipairs(b.entries) do
				entries[#entries + 1] = entry
			end
			copy = copy or b.copy and true or false
		end
		local ok, err, _, saved = WriteSettings(entries, copy)
		for _, b in ipairs(batches) do
			if b.done then
				pcall(b.done, ok, err, saved == true)
			end
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
	-- (2.1.0, el-15) in like the installer's: a pass, the screen it is drawn for, or adapted to this one
	if not (type(f.fitted) == "table" and type(report) == "table" and (report.pass or report.drawn or report.adapted)) then
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

-- (2.1.0, el-15) Whether Mello's layout for this screen is the active Edit Mode layout on this character, read only:
-- true / false, nil when it cannot be read (no API, no screen size). A profile load offers the installer's Fit when it
-- is not (Core/Config.lua, CONFIG.OfferProfileFit): the action bars, the experience bar, the bags and the micro menu
-- move only with the layout
function MelloUI:MelloLayoutActive()
	if not Api() then
		return nil
	end
	local full, info = FullList()
	local name = ScreenName()
	local at = info and info.activeLayout
	if not (full and name) or Secret(at) or type(at) ~= "number" then
		return nil
	end
	local active = full[at]
	return active ~= nil and NameOf(active) == name and TypeOf(active) ~= LayoutType("Preset")
end

-- One system's place in the active saved layout, read only (see the
-- header): the layouts table is only read, no manager method is called
function MelloUI:EditModeSystemAnchor(system, index)
	local Num, Finite = MelloUI.Safe.Number, MelloUI.Safe.Finite
	system = Num(system)
	if index ~= nil then
		index = Num(index)
		if index == nil then
			return nil
		end
	end
	if system == nil or not (C_EditMode and C_EditMode.GetLayouts) then
		return nil
	end
	local full, info, presets = FullList()
	if not full then
		return nil
	end
	-- (the index counts the presets first: one of them active is no saved
	-- layout of the player's)
	local active = info.activeLayout
	if Secret(active) or type(active) ~= "number" or active <= presets then
		return nil
	end
	local layout = full[active]
	local systems = type(layout) == "table" and layout.systems
	if Secret(systems) or type(systems) ~= "table" then
		return nil
	end
	for _, s in ipairs(systems) do
		local kind = type(s) == "table" and s.system
		if not Secret(kind) and kind == system then
			local at = s.systemIndex
			if Secret(at) then
				return nil
			end
			if index == nil or at == index then
				local a = s.anchorInfo
				if Secret(a) or type(a) ~= "table" then
					return nil
				end
				local p, to, rp, x, y = a.point, a.relativeTo, a.relativePoint, a.offsetX, a.offsetY
				if Secret(p) or Secret(to) or Secret(rp) or type(p) ~= "string" or type(rp) ~= "string"
					or not Finite(x) or not Finite(y) then
					return nil
				end
				local default = s.isInDefaultPosition
				return p, (type(to) == "string" and to ~= "") and to or "UIParent", rp, x, y,
					(not Secret(default) and default == true) and true or false
			end
		end
	end
	return nil
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

--------------------------------------------------------------------------------
-- One system's settings (0.19.9: Action Bars > Bars > Layout, Buffs &
-- Debuffs > Layout; docs/plans/keybind-bar-layout.md L1). Read from the
-- active layout, and SAVED as the game's own Edit Mode saves a change: the
-- system's entry for each setting changed in the active layout, the list
-- saved. Only saved: the game lays its systems out with them from the next
-- reload -- told to lay out from here, its synchronous re-layout ran inside
-- MelloUI's call, on MelloUI's script budget (WriteSettings). Only the
-- settings the system has (a bar without an icon count keeps none). A preset
-- cannot be changed (the game's own Save asks for a new layout first,
-- EditModeManager SaveLayoutChanges): with `copy` the preset goes in as an
-- account layout "<preset> (MelloUI)" (a number after a character layout's name
-- taken; (2.1.0) the account's copy made before used again), saved as
-- the active one, and changed there. Never in combat or while Edit Mode is
-- open: the change waits. MelloUI:EditModeSettingsSoon is the configurator's
-- way in: a slider's every step held, written once it is let go (every held
-- change in one save), the preset question asked once (MelloUI:Confirm), the
-- values held shown by the readers meanwhile, and once a session the line
-- to type /reload.
--------------------------------------------------------------------------------

local SOON = 0.4   -- s after the last change before the values are written (a slider let go)
local held = {}    -- [system .. ":" .. index] = { system, index, values, dones }: changes not written yet
local heldOrder = {}
local soonTimer = nil
local asking = false   -- the preset question open
local laidOut = false  -- the game's EDIT_MODE_LAYOUTS_UPDATED seen during our write
local watcher          -- (made with the first write)
local readAt, readFull, readInfo   -- the readers' list and the frame it was read in (ReadList)

local function Key(system, index)
	return tostring(system) .. ":" .. tostring(index)
end

-- a line for /mellolog only (not the chat): what a write did, for the
-- in-game check of the game's answer
local function LogOnly(fmt, ...)
	MelloUI.printHold = (MelloUI.printHold or 0) + 1
	local ok, err = pcall(MelloUI.Print, MelloUI, fmt, ...)
	MelloUI.printHold = MelloUI.printHold - 1
	if not ok then
		error(err, 0)
	end
end

-- the system's table in a layout (its `systemIndex` asked when given)
local function SystemOf(layout, system, index)
	local systems = type(layout) == "table" and layout.systems
	if Secret(systems) or type(systems) ~= "table" then
		return nil
	end
	for _, s in ipairs(systems) do
		if type(s) == "table" and not Secret(s.system) and s.system == system
			and (index == nil or (not Secret(s.systemIndex) and s.systemIndex == index)) then
			return s
		end
	end
	return nil
end

-- its plain values: { [setting] = raw value }
local function ValuesOf(sys)
	local out = {}
	local settings = sys.settings
	if Secret(settings) or type(settings) ~= "table" then
		return out
	end
	for _, e in ipairs(settings) do
		if type(e) == "table" and not Secret(e.setting) and not Secret(e.value)
			and type(e.setting) == "number" and type(e.value) == "number" then
			out[e.setting] = e.value
		end
	end
	return out
end

-- a free name for a preset's copy: "<name> (MelloUI)", then " 2", " 3" ...
local function FreeName(full, base)
	local name, n = base, 1
	while Find(full, name) do
		n = n + 1
		name = base .. " " .. n
	end
	return name
end

-- the active layout and its index in the full list (nil while unreadable)
local function Active(full, info)
	local at = info.activeLayout
	if Secret(at) or type(at) ~= "number" then
		return nil
	end
	return full[at], at
end

-- Now (every check is the caller's): `entries` -- { system, index, values }
-- each (a held change is one) -- into the active layout in ONE save; ok, why,
-- the copy's name when a preset was copied, and whether anything was saved.
-- (0.25.0) An entry naming a saved layout (`layout`, its name; `layoutType`,
-- its type, when given) goes into that one instead, never a preset; a layout
-- no longer there, or without the system, has nothing to change (no error).
-- A batch of such entries alone never reads the active layout.
WriteSettings = function(entries, copy)
	local full, info, presets = FullList()
	if not full then
		return false, TEXT.noRead
	end
	local toActive = false
	for _, entry in ipairs(entries) do
		if entry.layout == nil then
			toActive = true
		end
	end
	local layout, at
	if toActive then
		layout, at = Active(full, info)
		if not layout then
			return false, TEXT.noActive
		end
	end
	local copied, reused
	if layout and TypeOf(layout) == LayoutType("Preset") then
		if not copy then
			return false, "preset"
		end
		local account = LayoutType("Account")
		local base = TEXT.copyName:format(NameOf(layout) or "Layout")
		-- (2.1.0, el-15; the user's /mello layout check: 'Modern (MelloUI)', '... 2', '... 3') the account's copy of
		-- this preset, made before (on another character, which the game keeps on its own active layout, or in an
		-- earlier session), is used again and made active: never one more copy -- each took one of the five account
		-- layouts Edit Mode keeps, and the installer needs one for Mello's layout
		local have = Find(full, base, account)
		if have then
			at, layout, reused = have, full[have], base
		else
			local room, most = RoomFor(full, account)
			if not room then
				return false, TEXT.noRoom:format(most)
			end
			-- (a copy: the preset is the game's own table, never changed)
			local new = PlainCopy(layout, 0)
			new.layoutType = account
			new.layoutName = FreeName(full, base)
			FixStyle(new)
			at = InsertAt(full, presets, account)
			tinsert(full, at, new)
			layout, copied = new, new.layoutName
		end
	end
	local changed, found, names = (copied or reused) ~= nil, false, {}
	for _, entry in ipairs(entries) do
		local target = layout
		if entry.layout ~= nil then
			local i = Find(full, entry.layout, entry.layoutType)
			target = i and full[i] or nil
			found = true
		end
		local sys = target and SystemOf(target, entry.system, entry.index)
		if sys then
			found = true
			names[#names + 1] = tostring(entry.system) .. ":" .. tostring(entry.index)
				.. (entry.layout ~= nil and (" in '" .. tostring(entry.layout) .. "'") or "")
			for _, e in ipairs(type(sys.settings) == "table" and sys.settings or EMPTY) do
				local v = type(e) == "table" and not Secret(e.setting) and entry.values[e.setting]
				if type(v) == "number" and (Secret(e.value) or e.value ~= v) then
					e.value = v
					changed = true
				end
			end
			-- (0.20.2) its place, as Edit Mode's own drag keeps one (EditModeManager UpdateSystemAnchorInfo): the
			-- anchor at scale 1, no second anchor, out of its default place; (2.1.0, el-14) `inDefault`: the game's
			-- default anchor, in its default place, as Edit Mode's Reset To Default Position keeps it
			local a = entry.anchor
			if type(a) == "table" then
				sys.anchorInfo = { point = a.point, relativeTo = a.relativeTo, relativePoint = a.relativePoint,
					offsetX = a.offsetX, offsetY = a.offsetY }
				sys.anchorInfo2 = nil
				sys.isInDefaultPosition = a.inDefault == true
				changed = true
			end
		end
	end
	if not found then
		return false, TEXT.noSystem
	end
	if not changed then
		return true
	end
	-- Saved only (a preset's copy saved as the active layout): the game is
	-- never asked to lay its systems out from here. Its EDIT_MODE_LAYOUTS_UPDATED
	-- is synchronous: told from MelloUI's code (SetActiveLayout, OnLayoutAdded),
	-- the manager's whole re-layout, and every hook it sets off, ran inside
	-- MelloUI's call and was charged to MelloUI's script budget -- past the
	-- client's 1 s burst after a Bar Layout slider (the user, 2026-10-08: the
	-- micro menu's "attempt to call a nil value"). The saved layout shows from
	-- the next reload (MelloUI:EditModeSettingsSoon says so once a session).
	if copied or reused then
		info.activeLayout = at
	end
	info.layouts = full
	if not watcher then
		watcher = CreateFrame("Frame")
		Perf.SetScript(watcher, "OnEvent", function()
			laidOut = true
		end)
	end
	laidOut = false
	watcher:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	local okS, err = pcall(C_EditMode.SaveLayouts, info)
	watcher:UnregisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	if not okS then
		Note("settings %s: refused by SaveLayouts: %s", table.concat(names, ", "), tostring(err))
		return false, TEXT.noSave:format(tostring(err))
	end
	readFull = nil
	Unread(not laidOut)
	-- (el-15) a preset's copy saved as the active one: the real client keeps the preset; the copy waits for Reload now
	if copied or reused then
		local kept = ReadBackActive(full, at)
		if kept then
			Note("settings: the game kept '%s' active; '%s' waits for Reload now", kept, tostring(NameOf(layout)))
		end
	end
	Note("settings %s saved%s%s; laid out during the save: %s", table.concat(names, ", "),
		layout and (" in '" .. tostring(NameOf(layout)) .. "'") or "", copied and " (a preset's copy, saved as the active one)"
		or reused and " (the preset's copy made before, used again and saved as the active one)" or "",
		laidOut and "yes" or "no")
	-- (logged for the in-game check: whether the save itself made the game
	-- lay out inside this call)
	LogOnly("Edit Mode layout: %s saved%s%s; shows after a reload; laid out during the save: %s",
		table.concat(names, ", "), layout and (" in '" .. tostring(NameOf(layout)) .. "'") or "",
		copied and " (a copy of the preset, saved as the active one)"
		or reused and " (the preset's copy made before, saved as the active one)" or "", laidOut and "yes" or "no")
	return true, nil, copied or reused, true
end

-- the readers' list, kept for the frame it was read in (a page's rows read
-- it once, not once each); a write lets it go (readFull nil)
local function ReadList()
	local now = GetTime()
	if not (readFull and readAt == now) then
		readFull, readInfo = FullList()
		readAt = now
	end
	return readFull, readInfo
end

-- The active layout's values of one system (see the header), the held ones
-- over them
function MelloUI:EditModeSystemSettings(system, index)
	if not Api() then
		return nil, TEXT.noApi
	end
	local full, info = ReadList()
	if not full then
		return nil, TEXT.noRead
	end
	local layout = Active(full, info)
	if not layout then
		return nil, TEXT.noActive
	end
	local sys = SystemOf(layout, system, index)
	if not sys then
		return nil, TEXT.noSystem
	end
	local values = ValuesOf(sys)
	local h = held[Key(system, index)]
	if h then
		for setting, v in pairs(h.values) do
			if values[setting] ~= nil then
				values[setting] = v
			end
		end
	end
	local kind = TypeOf(layout)
	return values, kind == LayoutType("Preset"), NameOf(layout), kind
end

-- (0.25.0) A saved layout's values of one system, found by name (and type,
-- when given), the active one or not, never a preset; as saved (the held
-- changes are the active layout's)
function MelloUI:EditModeLayoutSystemSettings(name, system, index, kind)
	if not Api() then
		return nil, TEXT.noApi
	end
	local full = ReadList()
	if not full then
		return nil, TEXT.noRead
	end
	local at = Find(full, name, kind)
	local sys = at and SystemOf(full[at], system, index)
	if not sys then
		return nil, TEXT.noSystem
	end
	return ValuesOf(sys)
end

-- entries now, or when the fight or Edit Mode ends (a batch waits whole, in
-- order: the newest values win); done(ok, why, saved) told once (saved: the
-- layouts were saved, something changed)
local function Write(entries, copy, done)
	if not Api() then
		if done then done(false, TEXT.noApi) end
		return false, TEXT.noApi
	end
	local why = Blocked()
	if why then
		wait.settings[#wait.settings + 1] = { entries = entries, copy = copy, done = done }
		Wait(why)
		return false, why == "combat" and TEXT.settingsCombat or TEXT.settingsEditMode
	end
	local ok, err, _, saved = WriteSettings(entries, copy)
	saved = saved == true
	if done then
		done(ok, err, saved)
	end
	return ok, err, saved
end

-- Values into the active layout's system (see the header): now, or when the
-- fight or Edit Mode ends. done(ok, why, saved) told once.
function MelloUI:SetEditModeSystemSettings(system, index, values, copy, done)
	return Write({ { system = system, index = index, values = values } }, copy, done)
end

-- (0.25.0) Values into saved layouts by name (see the header): each entry
-- { layout = name, system, index, values }, every one in ONE save; now, or
-- when the fight or Edit Mode ends. done(ok, why, saved) told once.
function MelloUI:SetEditModeLayoutSettings(entries, done)
	return Write(entries, false, done)
end

-- the saved layout shows from the next reload: said once a session, after
-- the first change saved. Never a Reload button: the game blocks a reload
-- MelloUI's code asks for (C_UI.Reload, "MelloUI blocked by the game:
-- Reload()", 0.19.9's in-game test); the player's own /reload is allowed
local reloadAsked = false
local function AskReload()
	-- (2.1.0, el-15) saved into a layout the game makes active only with a reload (a preset's copy): the way to it,
	-- once for each such layout; a typed /reload would not switch it
	local waiting = pendingActive and pendingActive.name
	local text = TEXT.reloadSay
	if waiting then
		if reloadAsked == waiting then
			return
		end
		reloadAsked, text = waiting, MelloUI.Lang.F(TEXT.reloadPending, waiting)
	elseif reloadAsked then
		return
	else
		reloadAsked = true
	end
	MelloUI:Announce(text, "info")
	-- (and the chat keeps it after the line fades, unless notices go there)
	local look = MelloUI.CentreLook
	if not (look and look.Setting and look.Setting("noticeToChat")) then
		MelloUI:Print("%s", text)
	end
end

-- (0.25.0) the same line, once a session, for a change the player asked for
-- that was saved another way (Action Bars' Hide Bar Art switched)
function MelloUI:SayEditModeReload()
	AskReload()
end

-- the held changes written (the timer's end): the preset question first
-- when the active layout is one
local FlushHeld
local function Ask(name, have)
	asking = true
	MelloUI:Confirm({
		text = (have and TEXT.presetUse or TEXT.presetAsk):format(name or "preset", TEXT.copyName:format(name or "Layout")),
		accept = have and TEXT.presetUseYes or TEXT.presetYes,
		cancel = TEXT.presetNo,
		onAccept = function()
			asking = false
			FlushHeld(true)
		end,
		onCancel = function()
			asking = false
			wipe(held)
			wipe(heldOrder)
			if MelloUI.RefreshConfig then
				MelloUI:RefreshConfig()
			end
		end,
	})
end

FlushHeld = function(copy)
	soonTimer = nil
	if asking or #heldOrder == 0 then
		return
	end
	if not copy then
		local full, info = FullList()
		local layout = full and Active(full, info)
		if layout and TypeOf(layout) == LayoutType("Preset") then
			-- (2.1.0, el-15) the account's copy of it there already: asked to use that one (WriteSettings reuses it)
			local name = NameOf(layout)
			Ask(name, Find(full, TEXT.copyName:format(name or "Layout"), LayoutType("Account")) ~= nil)
			return
		end
	end
	-- (each held change is an entry: { system, index, values, dones }; still
	-- shown by the readers until it is written or refused)
	local list = {}
	for _, key in ipairs(heldOrder) do
		if held[key] then
			list[#list + 1] = held[key]
		end
	end
	wipe(heldOrder)
	Write(list, copy, function(ok, why)
		for _, h in ipairs(list) do
			local key = Key(h.system, h.index)
			if held[key] == h then
				held[key] = nil
			end
			for _, fn in ipairs(h.dones) do
				pcall(fn, ok, why)
			end
		end
		if ok then
			AskReload()
		elseif why ~= "preset" then
			MelloUI:Print("Edit Mode layout: %s", tostring(why))
		end
		if MelloUI.RefreshConfig then
			MelloUI:RefreshConfig()
		end
	end)
end

-- A change from the configurator: held and shown at once, written SOON s
-- after the last one (see the header). done(ok, why) told once it went in.
function MelloUI:EditModeSettingsSoon(system, index, values, done)
	local key = Key(system, index)
	local h = held[key]
	if not h then
		h = { system = system, index = index, values = {}, dones = {} }
		held[key] = h
	end
	local listed = false
	for _, k in ipairs(heldOrder) do
		if k == key then
			listed = true
		end
	end
	if not listed then
		heldOrder[#heldOrder + 1] = key
	end
	for setting, v in pairs(values) do
		h.values[setting] = v
	end
	if done then
		h.dones[#h.dones + 1] = done
	end
	if soonTimer then
		soonTimer:Cancel()
	end
	soonTimer = C_Timer.NewTimer(SOON, function()
		FlushHeld(false)
	end)
end

-- (0.20.2) A system's place, held and written as the settings are (see the header)
function MelloUI:EditModeAnchorSoon(system, index, anchor, done)
	if type(anchor) ~= "table" then
		return
	end
	MelloUI:EditModeSettingsSoon(system, index, {}, done)
	local h = held[Key(system, index)]
	if h then
		h.anchor = { point = anchor.point, relativeTo = anchor.relativeTo or "UIParent",
			relativePoint = anchor.relativePoint, offsetX = anchor.offsetX, offsetY = anchor.offsetY,
			inDefault = anchor.inDefault == true or nil }
	end
end

-- (2.1.0, el-14) A system's place held to be written (above), as MelloUI:EditModeSystemAnchor answers one: point,
-- relativeTo (a frame's name), relativePoint, offsetX, offsetY, inDefault; nil when none is held (Edit Layout's box
-- reads it first: a place saved a moment ago is not in the saved layout yet)
function MelloUI:EditModeHeldAnchor(system, index)
	local h = held[Key(system, index)]
	local a = h and h.anchor
	if type(a) ~= "table" then
		return nil
	end
	return a.point, a.relativeTo or "UIParent", a.relativePoint, a.offsetX, a.offsetY, a.inDefault == true
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

--------------------------------------------------------------------------------
-- (0.22.0; a player's report, 2026-10-14: the installer could not go on -- Edit Mode already kept the five account
-- layouts it allows) An older MelloUI layout, deleted at the player's word on the installer's Screen step, as Edit
-- Mode's own Delete does it (EditModeManagerFrameMixin:DeleteLayout: out of the full list, the list saved, the game
-- told). Never the layout of this screen, never a preset nor another addon's or the player's own layout.
--   MelloUI:OldMelloLayouts(keep) -> names   the account's saved MelloUI layouts ("MelloUI", "MelloUI <w>x<h>"),
--                                            `keep` (this screen's name) left out
--   MelloUI:DeleteEditModeLayout(name) -> ok, why   one of those (out of combat, Edit Mode closed)
--------------------------------------------------------------------------------
local function OldName(name, base, keep)
	return name ~= keep and (name == base or name:sub(1, #base + 1) == base .. " ")
end

function MelloUI:OldMelloLayouts(keep)
	local out = {}
	if not Api() then
		return out
	end
	local full = FullList()
	if not full then
		return out
	end
	local data = Data()
	local base = data and data.name or BASE
	local account = LayoutType("Account")
	for _, layout in ipairs(full) do
		local name = NameOf(layout)
		if name and TypeOf(layout) == account and OldName(name, base, keep) then
			out[#out + 1] = name
		end
	end
	return out
end

function MelloUI:DeleteEditModeLayout(name)
	if not Api() then
		return false, TEXT.noApi
	elseif InCombatLockdown() then
		return false, TEXT.deleteCombat
	elseif EditModeManagerFrame and EditModeManagerFrame.IsShown and EditModeManagerFrame:IsShown() then
		return false, TEXT.deleteEditMode
	end
	local full, info = FullList()
	if not full then
		return false, TEXT.noRead
	end
	local data = Data()
	local at = Find(full, name)
	if not (at and type(name) == "string" and OldName(name, data and data.name or BASE, ScreenName())
		and TypeOf(full[at]) == LayoutType("Account")) then
		return false, TEXT.gone
	end
	tremove(full, at)
	info.layouts = full
	local ok, err = pcall(C_EditMode.SaveLayouts, info)
	if not ok then
		return false, TEXT.noSave:format(tostring(err))
	end
	readFull = nil
	if C_EditMode.OnLayoutDeleted then
		pcall(C_EditMode.OnLayoutDeleted, at)
	end
	LogOnly("Edit Mode layout '%s' deleted (the installer, at the player's word)", name)
	return true
end

--------------------------------------------------------------------------------
-- (2.1.0, el-14; the user's rule, 2026-10-27: everything Edit Mode does in Edit Layout) Edit Mode's layout list from
-- Edit Layout (its Layouts list, Core/EditLayoutPicker.lua): use, new, copy, rename, delete, import, share. Each
-- change is ONE SaveLayouts of the full list (the presets in front, as the manager saves it), the active layout saved
-- as info.activeLayout -- as the preset's copy has been since 0.19.9 (WriteSettings). Never SetActiveLayout,
-- OnLayoutAdded or OnLayoutDeleted from here: the game answers them with its synchronous EDIT_MODE_LAYOUTS_UPDATED, its
-- whole re-layout run inside MelloUI's call (0.19.9: past the script budget; Blizzard's layout code from addon code,
-- hard rule 1). The game shows the change from the next /reload. The saved list read back at once: a client that kept
-- another active layout than the one saved is told ("kept" and the name it kept), so the player is never left
-- guessing. Never in combat, never while Edit Mode is open (its own Save would put its old list back): refused, not
-- waited -- these are the player's clicks. A name follows Edit Mode's own dialog: not empty, at most 30 letters, no
-- other layout (a preset included) of that name, the game's IsValidLayoutName. Each type keeps at most
-- Constants.EditModeConsts.EditModeMaxLayoutsPerType.
--   MelloUI:EditModeLayouts() -> list | nil, why                                                       read only
--       { { name, kind = "preset" | "account" | "character", active }, ... } in Edit Mode's order
--   MelloUI:ManageEditModeLayout(action, spec) -> ok, why, kept
--       "use"    { name, kind }                     that layout active
--       "new"    { name, kind }                     the game's default preset copied as a new layout, made active
--       "copy"   { from, fromKind, name, kind }     that layout copied, made active
--       "rename" { name, kind, to }                 (never a preset)
--       "delete" { name, kind }                     (never a preset) the active one deleted: the default preset active
--       "import" { text, name, kind }               a share string as a new layout, made active
--       kind of a new one: "account" (default) or "character". why "kept": the game kept `kept` active.
--   MelloUI:ShareEditModeLayout(name, kind) -> text | nil, why                                         read only
--------------------------------------------------------------------------------
do
	local NAME_LETTERS = 30   -- (EditModeDialogs.xml: the name box's letters)
	local KINDS = { preset = "Preset", account = "Account", character = "Character" }
	local MG = {
		combat = "Not during a fight.",
		editMode = "Close the game's Edit Mode first.",
		noName = "Type a name first.",
		long = "A name can have at most 30 letters.",
		taken = "A layout is already called that.",
		badName = "The game does not take that name.",
		full = "Edit Mode keeps at most %d layouts of this kind: delete one first.",
		gone = "That layout is no longer there.",
		preset = "The game's own layouts can't be renamed or deleted.",
		badString = "That is not an Edit Mode layout string.",
		noShare = "The game could not turn that layout into a string.",
	}
	MelloUI.EditModeLayoutText = MG

	local function KindOf(layout)
		local t = TypeOf(layout)
		for kind, enumName in pairs(KINDS) do
			if t ~= nil and t == LayoutType(enumName) then
				return kind
			end
		end
		return nil
	end

	-- the index of the layout of that name and kind (a preset too)
	local function At(full, name, kind)
		for i, layout in ipairs(full) do
			if NameOf(layout) == name and (kind == nil or KindOf(layout) == kind) then
				return i
			end
		end
		return nil
	end

	-- a name as Edit Mode's dialog takes it, or nil and why (`skip`: the layout being renamed)
	local function Named(full, name, skip)
		name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
		if name == "" then
			return nil, MG.noName
		elseif #name > NAME_LETTERS then
			return nil, MG.long
		end
		for i, layout in ipairs(full) do
			if i ~= skip and NameOf(layout) == name then
				return nil, MG.taken
			end
		end
		local api = C_EditMode
		if api.IsValidLayoutName then
			local ok, valid = pcall(api.IsValidLayoutName, name)
			if ok and not Secret(valid) and valid == false then
				return nil, MG.badName
			end
		end
		return name
	end

	-- the default preset's index in the full list (the one C_EditMode.GetEditModeDefaultLayout names; else the first)
	local function DefaultIndex(full, presets)
		local want
		if C_EditMode.GetEditModeDefaultLayout then
			local ok, v = pcall(C_EditMode.GetEditModeDefaultLayout)
			want = ok and not Secret(v) and v or nil
		end
		for i = 1, presets do
			local layout = full[i]
			if want ~= nil and type(layout) == "table" and layout.layoutIndex == want then
				return i
			end
		end
		return presets > 0 and 1 or nil
	end

	-- the list saved with `active` as the active one; then read back: ok, nil | "kept", the name the game kept
	local function SaveAs(full, info, active, what)
		info.layouts = full
		info.activeLayout = active
		local ok, err = pcall(C_EditMode.SaveLayouts, info)
		if not ok then
			Note("layouts %s: refused by SaveLayouts: %s", what, tostring(err))
			return false, TEXT.noSave:format(tostring(err))
		end
		readFull = nil
		local wanted = full[active] and NameOf(full[active]) or "?"
		LogOnly("Edit Mode layouts: %s; '%s' saved as the active one; shows after a reload", what, wanted)
		Note("layouts %s: '%s' saved as the active one (index %d)", what, wanted, active)
		Unread(true)
		-- (el-15: the real client keeps its own; the wanted one then waits for the Reload now button)
		local kept, now = ReadBackActive(full, active)
		if kept then
			LogOnly("Edit Mode layouts: the game kept '%s' active (index %s, not %s)", kept, tostring(now), tostring(active))
			Note("layouts: the game kept '%s' active (index %s, not %s); '%s' waits for Reload now", kept, tostring(now),
				tostring(active), wanted)
			return true, "kept", kept
		end
		return true
	end

	-- a new layout (a copy of `source`) of that name and kind into the list, made active
	local function AddNew(full, info, presets, source, name, kind, what)
		local layoutType = LayoutType(KINDS[kind == "character" and "character" or "account"])
		local room, most = RoomFor(full, layoutType)
		if not room then
			return false, MG.full:format(most or 5)
		end
		local new = PlainCopy(source, 0)
		if type(new) ~= "table" then
			return false, MG.gone
		end
		new.layoutType = layoutType
		new.layoutName = name
		FixStyle(new)
		local at = InsertAt(full, presets, layoutType)
		tinsert(full, at, new)
		return SaveAs(full, info, at, what)
	end

	function MelloUI:EditModeLayouts()
		if not Api() then
			return nil, TEXT.noApi
		end
		local full, info = FullList()
		if not full then
			return nil, TEXT.noRead
		end
		local active = info.activeLayout
		local out = {}
		for i, layout in ipairs(full) do
			local name, kind = NameOf(layout), KindOf(layout)
			if name and kind then
				out[#out + 1] = { name = name, kind = kind, active = (not Secret(active) and active == i) }
			end
		end
		return out
	end

	function MelloUI:ManageEditModeLayout(action, spec)
		if not Api() then
			return false, TEXT.noApi
		end
		local why = Blocked()
		if why then
			return false, why == "combat" and MG.combat or MG.editMode
		end
		spec = type(spec) == "table" and spec or EMPTY
		local full, info, presets = FullList()
		if not full then
			return false, TEXT.noRead
		end
		local active = info.activeLayout
		if Secret(active) or type(active) ~= "number" then
			return false, TEXT.noActive
		end
		if action == "use" then
			local at = At(full, spec.name, spec.kind)
			if not at then
				return false, MG.gone
			end
			if at == active then
				pendingActive = nil   -- (el-15: the game's own active one picked: nothing waits any more)
				return true
			end
			return SaveAs(full, info, at, "use '" .. tostring(spec.name) .. "'")
		elseif action == "new" or action == "copy" or action == "import" then
			local name, bad = Named(full, spec.name)
			if not name then
				return false, bad
			end
			local source
			if action == "new" then
				local d = DefaultIndex(full, presets)
				source = d and full[d]
			elseif action == "copy" then
				local from = At(full, spec.from, spec.fromKind)
				source = from and full[from]
			else
				local ok, layout = false, nil
				if type(spec.text) == "string" and spec.text:find("%S") then
					ok, layout = pcall(C_EditMode.ConvertStringToLayoutInfo, (spec.text:gsub("^%s+", ""):gsub("%s+$", "")))
				end
				if not (ok and type(layout) == "table") then
					return false, MG.badString
				end
				source = layout
			end
			if not source then
				return false, MG.gone
			end
			return AddNew(full, info, presets, source, name, spec.kind, action .. " '" .. name .. "'")
		elseif action == "rename" or action == "delete" then
			local at = At(full, spec.name, spec.kind)
			if not at then
				return false, MG.gone
			elseif at <= presets or KindOf(full[at]) == "preset" then
				return false, MG.preset
			end
			if action == "rename" then
				local name, bad = Named(full, spec.to, at)
				if not name then
					return false, bad
				end
				full[at].layoutName = name
				return SaveAs(full, info, active, "rename '" .. tostring(spec.name) .. "' to '" .. name .. "'")
			end
			tremove(full, at)
			if at == active then
				active = DefaultIndex(full, presets) or 1
			elseif at < active then
				active = active - 1
			end
			return SaveAs(full, info, active, "delete '" .. tostring(spec.name) .. "'")
		end
		return false, "unknown action " .. tostring(action)
	end

	function MelloUI:ShareEditModeLayout(name, kind)
		if not (Api() and C_EditMode.ConvertLayoutInfoToString) then
			return nil, TEXT.noApi
		end
		local full = FullList()
		local at = full and At(full, name, kind)
		if not at then
			return nil, MG.gone
		end
		local ok, text = pcall(C_EditMode.ConvertLayoutInfoToString, full[at])
		if not (ok and not Secret(text) and type(text) == "string" and text ~= "") then
			return nil, MG.noShare
		end
		return text
	end
end

--------------------------------------------------------------------------------
-- (2.1.0, el-15; players: "the Edit Mode layout does not apply") /mello layout check: what the game and MelloUI hold
-- for the Edit Mode layout, read only, for a player to copy and send (the log window). Never a layout call: the
-- layouts and Edit Mode's own copy of them are read, the share string is made only to read its version, each system's
-- frame is asked where it stands. Its lines are a report, in English (never translated).
--   MelloUI:EditModeLayoutCheck(add)   add(fmt, ...) once a line
--------------------------------------------------------------------------------
do
	local POINT_EPS = 1   -- units: a frame within this of its saved offsets stands where the layout says

	local function Get(t, key)
		return t[key]
	end

	local function Field(t, key)
		local ok, v = pcall(Get, t, key)
		if not ok or Secret(v) then
			return nil
		end
		return v
	end

	local function Kind(layout)
		local t = TypeOf(layout)
		for _, name in ipairs({ "Preset", "Account", "Character" }) do
			if t ~= nil and t == LayoutType(name) then
				return name:lower()
			end
		end
		return tostring(t)
	end

	-- a region's name, plain, or nil
	local function NameOfRegion(r)
		if type(r) ~= "table" then
			return nil
		end
		local ok, n = pcall(r.GetName, r)
		return (ok and not Secret(n) and type(n) == "string") and n or nil
	end

	local function Fmt(v)
		local n = MelloUI.Safe.Finite(v)
		return n and string.format("%.1f", n) or "?"
	end

	-- where a system frame stands: its first point (the offsets at scale 1, as the layout keeps them), or nil and why
	local function PointNow(frame)
		local ok, p, rel, rp, x, y = pcall(frame.GetPoint, frame, 1)
		if not ok then
			return nil, "unreadable"
		end
		if Secret(p) or Secret(rp) or Secret(x) or Secret(y) then
			return nil, "secret"
		end
		if p == nil then
			return nil, "no point"
		end
		local okS, s = pcall(frame.GetScale, frame)
		s = (okS and MelloUI.Safe.Finite(s)) or 1
		return { point = p, relativeTo = NameOfRegion(rel) or (rel == nil and "UIParent" or "?"), relativePoint = rp,
			offsetX = (MelloUI.Safe.Finite(x) or 0) * s, offsetY = (MelloUI.Safe.Finite(y) or 0) * s }
	end

	local function Same(a, b)
		local ax, ay = MelloUI.Safe.Finite(a.offsetX), MelloUI.Safe.Finite(a.offsetY)
		return a.point == b.point and a.relativePoint == b.relativePoint and a.relativeTo == b.relativeTo
			and ax ~= nil and ay ~= nil and math.abs(ax - b.offsetX) <= POINT_EPS and math.abs(ay - b.offsetY) <= POINT_EPS
	end

	local function Anchor(a)
		return string.format("%s %s %s %s %s", tostring(a.point), tostring(a.relativeTo), tostring(a.relativePoint),
			Fmt(a.offsetX), Fmt(a.offsetY))
	end

	local function Version(text)
		return (type(text) == "string" and not Secret(text) and text:match("^%s*(%d+)")) or "?"
	end

	-- the client: its build, the screen, the baked layout as it reads it
	local function Client(add)
		local okB, build, buildNo = pcall(GetBuildInfo)
		add("MelloUI %s, Edit Mode layout check, %s; client %s (%s)", tostring(MelloUI.version), tostring(date("%Y-%m-%d %H:%M")),
			okB and tostring(build) or "?", okB and tostring(buildNo) or "?")
		add("In combat: %s; Edit Mode open: %s", InCombat() and "yes" or "no", EditModeOpen() and "yes" or "no")
		local okW, w, h = pcall(UIParent.GetSize, UIParent)
		add("Screen: %s x %s UI units; Mello's layout for this screen is called '%s'", okW and Fmt(w) or "?",
			okW and Fmt(h) or "?", tostring(ScreenName()))
		local data = Data()
		if not data then
			add("Baked layout: none")
			return
		end
		local okC, baked = pcall(C_EditMode.ConvertStringToLayoutInfo, data.layout)
		local systems = okC and type(baked) == "table" and Field(baked, "systems")
		add("Baked layout '%s': string version %s, %d characters; the client reads it: %s", tostring(data.name),
			Version(data.layout), #data.layout, type(systems) == "table"
			and string.format("yes, %d systems, input style %s", #systems, tostring(Field(baked, "interfaceStyle")))
			or ("NO (" .. tostring(okC and "nothing" or baked) .. ")"))
	end

	-- the account's answer, this character's, the last install's (kept on its restore point) and this session's writes
	local function Answers(add)
		local um = MelloUI:GetModuleDB("UIModifications") or EMPTY
		local I = MelloUI.Installer
		local key = type(I) == "table" and I.AltKey and I.AltKey()
		add("Account: layoutFitFor %s, skin %s, reskin %s, UI Modifications %s; took Mello's layout: %s",
			tostring(um.layoutFitFor), tostring(um.skin), tostring(um.reskin),
			MelloUI:IsModuleEnabled("UIModifications") and "on" or "off",
			(type(I) == "table" and I.TookLayout) and (I.TookLayout(um) and "yes" or "no") or "?")
		add("This character: asked about Mello's layout: %s", key and tostring(um[key]) or "?")
		local rp = MelloUI.db and MelloUI.db.installer
		if type(rp) == "table" and type(rp.at) == "number" then
			-- (the answer: waiting, reverted -- its reason since 2.1.0; before, a setup's layout facts gone tell it --, kept)
			local waiting = type(rp.pending) == "table"
			local reverted = not waiting and (rp.reverted or (rp.option == "setup" and not rp.layoutFlags))
			local answer = waiting and "waiting for Keep or Revert"
				or reverted and ("reverted (" .. (rp.reverted and tostring(rp.reverted) or "no reason kept: an older MelloUI") .. ")")
				or "kept"
			local lay
			if reverted then
				lay = "taken back with the revert" .. (rp.layoutWanted == false and " (the player's own layout was picked)" or "")
			elseif rp.layoutPut then
				lay = "put in"
			elseif rp.layoutWritten then
				lay = "refused by the game"
			elseif rp.layoutWanted == false then
				lay = "the player's own kept (picked on the Layout step)"
			elseif rp.layoutWanted then
				lay = "picked, but NOT put in"
			else
				lay = "not put in (an older MelloUI kept no pick)"
			end
			add("Last install: %s, %s, %s; the layout: %s%s", tostring(date("%Y-%m-%d %H:%M", rp.at)), tostring(rp.option),
				answer, lay, rp.layoutWhy and (" (" .. tostring(rp.layoutWhy) .. ")") or "")
			-- (el-15) the fit's own answer, as the installer kept it
			local lf = rp.layoutFit
			if type(lf) == "table" then
				add("  its fit: %s x %s UI units; %s; cause %s%s", tostring(lf.W), tostring(lf.H), tostring(lf.verdict),
					tostring(lf.cause), lf.drawn and "; drawn for this screen: put in" or lf.adapted
					and string.format("; adapted to this screen (scaled to %d%%): put in", math.floor((tonumber(lf.scaled) or 1) * 100 + 0.5))
					or "")
				for _, k in ipairs({ "flags", "hard", "off", "centre", "stores" }) do
					for _, x in ipairs(type(lf[k]) == "table" and lf[k] or EMPTY) do
						add("    %s: %s", k, tostring(x))
					end
				end
			end
		else
			add("Last install: none kept")
		end
		add("This session's Edit Mode writes: %s", #journal > 0 and tostring(#journal) or "none")
		for _, line in ipairs(journal) do
			add("  %s", line)
		end
	end

	-- each system: the active layout's place against where its frame stands
	local function Systems(add, current, manager)
		local bridge = MelloUI.EditLayout and MelloUI.EditLayout.Bridge
		local list = (bridge and bridge.Systems and bridge.Systems())
			or (type(manager) == "table" and Field(manager, "registeredSystemFrames"))
		if type(list) ~= "table" or not current then
			return
		end
		local differ, n = 0, 0
		add("Systems ('%s'): saved place | where the frame stands", tostring(NameOf(current)))
		for _, frame in ipairs(list) do
			local sys, idx = Field(frame, "system"), Field(frame, "systemIndex")
			local label = (bridge and bridge.Label and bridge.Label(frame)) or NameOfRegion(frame) or "?"
			local saved = type(sys) == "number" and SystemOf(current, sys, idx)
			local a = saved and Field(saved, "anchorInfo")
			local now, why = PointNow(frame)
			local okV, shown = pcall(frame.IsShown, frame)
			-- (a frame MelloUI places from its own store -- the minimap, the chat, the tracker, the damage meter while UI
			-- Modifications is on: Core/EditLayoutWindows.lua -- stands where MelloUI says, not where the layout does)
			local entry = MelloUI.MoverEntry and MelloUI:MoverEntry(frame)
			local own = type(entry) == "table" and type(entry.key) == "string" and entry.key:sub(1, 9) ~= "EditMode."
				and (not MelloUI.EntryLive or MelloUI:EntryLive(entry)) and entry.key or nil
			local tag
			n = n + 1
			if type(a) ~= "table" then
				tag = "not in the layout"
			elseif own then
				tag = "MelloUI's own place (" .. own .. ")"
			elseif not now then
				tag = why
			elseif Field(saved, "isInDefaultPosition") == true then
				tag = "default place (the game lays it)"
			elseif Same(a, now) then
				tag = "same"
			else
				tag, differ = "DIFFERS", differ + 1
			end
			add("  %s:%s %s: %s | %s | %s%s", tostring(sys), tostring(idx), label,
				type(a) == "table" and Anchor(a) or "-", now and Anchor(now) or "-", tag,
				(okV and not Secret(shown) and shown == false) and ", hidden" or "")
		end
		add("%d systems, %d not where the active layout says (MelloUI's own places not counted)", n, differ)
		local handed = bridge and bridge.handedOver
		if type(handed) == "table" and next(handed) then
			add("Edit Layout's copies at login (/mello layout places for more):")
			for k, v in pairs(handed) do
				add("  %s: %s", tostring(k), tostring(v))
			end
		end
	end

	function MelloUI:EditModeLayoutCheck(add)
		Client(add)
		if not Api() then
			add("This client has no Edit Mode layout API.")
			return
		end
		-- the client's list, and Edit Mode's own copy of it
		local full, info, presets = FullList()
		if not full then
			add("The layouts could not be read.")
			return
		end
		local active = info.activeLayout
		active = (not Secret(active) and type(active) == "number") and active or nil
		local names = {}
		for i, layout in ipairs(full) do
			names[#names + 1] = string.format("%d:%s(%s)%s", i, tostring(NameOf(layout)), Kind(layout), i == active and "*" or "")
		end
		add("Layouts (%d presets + %d saved), * active: %s", presets or 0, #full - (presets or 0), table.concat(names, " "))
		local current = active and full[active]
		add("Active: index %s, '%s' (%s)", tostring(active), tostring(current and NameOf(current)),
			current and Kind(current) or "none")
		if current and C_EditMode.ConvertLayoutInfoToString then
			local okS, text = pcall(C_EditMode.ConvertLayoutInfoToString, current)
			add("The client writes layout strings as version %s", okS and Version(text) or ("? (" .. tostring(text) .. ")"))
		end
		local manager = rawget(_G, "EditModeManagerFrame")
		local mine = type(manager) == "table" and Field(manager, "layoutInfo")
		if type(mine) == "table" then
			local mActive = Field(mine, "activeLayout")
			local mLayouts = Field(mine, "layouts")
			local mName = type(mLayouts) == "table" and type(mActive) == "number" and NameOf(mLayouts[mActive]) or nil
			add("Edit Mode's own copy: active index %s, '%s'%s", tostring(mActive), tostring(mName),
				(mActive ~= active or mName ~= (current and NameOf(current)))
				and " -- NOT the client's: Edit Mode shows an older list until a /reload (its Save would put that back)" or "")
		end
		-- Mello's layout for this screen, and the others of its name
		local screen = ScreenName()
		local at = screen and Find(full, screen)
		local others = {}
		for _, layout in ipairs(full) do
			local n = NameOf(layout)
			if n and n ~= screen and (n == BASE or n:sub(1, #BASE + 1) == BASE .. " ") then
				others[#others + 1] = "'" .. n .. "'"
			end
		end
		add("Mello's layout for this screen: %s%s%s", at and "in the list" or "NOT in the list",
			at and (at == active and ", ACTIVE" or ", not active on this character") or "",
			#others > 0 and ("; other MelloUI layouts: " .. table.concat(others, ", ")) or "")
		local waiting = MelloUI:EditModeActivePending()
		add("Waiting to be made active (Edit Layout > Layout > Reload now): %s", waiting and ("'" .. waiting .. "'") or "none")
		Answers(add)
		Systems(add, current, manager)
		-- blocked actions kept (/mellobug)
		local bug = type(MelloUI.Perf) == "table" and rawget(MelloUI.Perf, "bug")
		local blocked = (type(bug) == "table" and type(bug.List) == "function" and bug.List()) or EMPTY
		add("Blocked actions kept: %d", #blocked)
		for i = 1, math.min(3, #blocked) do
			local e = blocked[i]
			add("  %s %s %s%s", tostring(e.when), tostring(e.func), e.combat and "in combat" or "out of combat",
				(tonumber(e.count) or 1) > 1 and (" x" .. tostring(e.count)) or "")
		end
	end
end

--------------------------------------------------------------------------------
-- (2.1.46) The Edit Mode layout a profile carries (the user, 2026-11-12: "I want this profile issue to be fixed once
-- and for all, i dont want people to tell me, i moved x thing here, saved the profile, loaded on another character
-- and x thing is somewhere else, make sure that even if we add things to the addon, they also imidietlly get saved by
-- the profile"). The game's frames Edit Layout and Edit Mode move (the action bars, the bags, the micro menu, the
-- experience bar ...) stand where the ACTIVE Edit Mode layout puts them, and the game keeps the active layout per
-- character: a profile now carries that layout whole -- every system, its place and its settings, and any system a
-- later client adds -- as the game's own share string (UI Modifications' emKind / emName / emText, written by
-- Core.lua's MelloUI:RecordEditMode on every save, the logout's included). Putting a profile on a character makes
-- that character's layout the profile's: a preset made active by name; a saved layout's string put into this
-- character's OWN character layout and made active -- never into an account layout, which every character shares,
-- so nothing one character's Edit Layout does reaches another (the other's next login puts its own back).
--   MelloUI:EditModeForProfile() -> kind, name, text | nil      read only: the active layout's kind ("preset" |
--       "account" | "character"), its name and share string (nil text for a preset); nil when unreadable
--   MelloUI:EditModeToProfile(kind, name, text) -> ok, why       this character's active layout made the profile's:
--       nothing when it already reads as that string (or is that preset); in a fight or with Edit Mode open, when
--       that ends (the newest wins). A layout replaced while active shows from the next reload (the line to type it)
--------------------------------------------------------------------------------
do
	local OWN = "MelloUI Profile"
	MelloUI.EDIT_MODE_OWN = OWN   -- (read only: the tests, /mello layout check)

	local function KindName(layout)
		local t = TypeOf(layout)
		if t ~= nil and t == LayoutType("Preset") then
			return "preset"
		elseif t ~= nil and t == LayoutType("Character") then
			return "character"
		end
		return "account"
	end

	local function StringOf(layout)
		if not C_EditMode.ConvertLayoutInfoToString then
			return nil
		end
		local ok, text = pcall(C_EditMode.ConvertLayoutInfoToString, layout)
		if ok and not Secret(text) and type(text) == "string" and text ~= "" then
			return text
		end
		return nil
	end

	local function ActiveOf(full, info)
		local at = info and info.activeLayout
		if Secret(at) or type(at) ~= "number" then
			return nil
		end
		return full[at], at
	end

	function MelloUI:EditModeForProfile()
		if not Api() then
			return nil
		end
		local full, info = FullList()
		local active = full and ActiveOf(full, info)
		local name = active and NameOf(active)
		if not name then
			return nil
		end
		local kind = KindName(active)
		if kind == "preset" then
			return kind, name, nil
		end
		local text = StringOf(active)
		if not text then
			return nil
		end
		return kind, name, text
	end

	-- the profile's string into this character's own layout, made active
	local function ToOwn(text)
		local full, info, presets = FullList()
		if not full then
			return false, TEXT.noRead
		end
		local okI, new = pcall(C_EditMode.ConvertStringToLayoutInfo, text)
		if not okI or type(new) ~= "table" then
			return false, TEXT.noRead
		end
		local character = LayoutType("Character")
		new.layoutType = character
		new.layoutName = OWN
		FixStyle(new)
		local index = Find(full, OWN, character)
		local replaced = index ~= nil
		if replaced then
			full[index] = new
		else
			local room, most = RoomFor(full, character)
			if not room then
				return false, TEXT.noRoom:format(most)
			end
			index = InsertAt(full, presets, character)
			tinsert(full, index, new)
		end
		info.layouts = full
		local okS, err = pcall(C_EditMode.SaveLayouts, info)
		if not okS then
			Note("profile layout: refused by SaveLayouts: %s", tostring(err))
			return false, TEXT.noSave:format(tostring(err))
		end
		-- (as Put: told, the game lays it out at once; the active one replaced shows from the next reload)
		local told = true
		if replaced then
			if info.activeLayout ~= index and C_EditMode.SetActiveLayout then
				pcall(C_EditMode.SetActiveLayout, index)
			else
				told = false
			end
		elseif C_EditMode.OnLayoutAdded then
			pcall(C_EditMode.OnLayoutAdded, index, true, true)
		elseif C_EditMode.SetActiveLayout then
			pcall(C_EditMode.SetActiveLayout, index)
		end
		Note("profile layout put into '%s' at %d (%s); laid out: %s", OWN, index, replaced and "replaced" or "added",
			told and "yes" or "after a reload")
		Unread(not told)
		MelloUI:Fire("editmodelayout", "put", OWN)
		if not told then
			MelloUI:SayEditModeReload()
		end
		return true
	end

	local pending   -- { kind, name, text }: the newest, waiting for the fight or Edit Mode to end
	local resume    -- (the fight's end, made the first time one waits: nothing at login)
	local RESUME_OWNER = "Edit Mode layout: a profile's"
	local function ProfileResume()
		if resume then
			resume:UnregisterAllEvents()
		end
		MelloUI:Off(RESUME_OWNER, "editmode")
		local p = pending
		pending = nil
		if p then
			MelloUI:EditModeToProfile(p[1], p[2], p[3])
		end
	end

	function MelloUI:EditModeToProfile(kind, name, text)
		if type(kind) ~= "string" or not Api() then
			return false
		end
		local why = Blocked()
		if why then
			pending = { kind, name, text }
			if why == "combat" then
				if not resume then
					resume = CreateFrame("Frame")
					Perf.SetScript(resume, "OnEvent", ProfileResume)
				end
				resume:RegisterEvent("PLAYER_REGEN_ENABLED")
			else
				MelloUI:Off(RESUME_OWNER, "editmode")
				MelloUI:On("editmode", function(entering)
					if entering == false then
						C_Timer.After(0, ProfileResume)
					end
				end, RESUME_OWNER)
			end
			return false, why
		end
		local full, info = FullList()
		if not full then
			return false, TEXT.noRead
		end
		local active, at = ActiveOf(full, info)
		if kind == "preset" then
			if active and KindName(active) == "preset" and NameOf(active) == name then
				return true
			end
			for i, layout in ipairs(full) do
				if KindName(layout) == "preset" and NameOf(layout) == name and C_EditMode.SetActiveLayout then
					local ok, err = pcall(C_EditMode.SetActiveLayout, i)
					Note("profile layout: preset '%s' made active: %s", tostring(name), ok and "yes" or tostring(err))
					return ok, not ok and tostring(err) or nil
				end
			end
			return false, TEXT.gone
		end
		if type(text) ~= "string" or text == "" then
			return false
		end
		if active and at and KindName(active) ~= "preset" and StringOf(active) == text then
			return true   -- (as the profile has it already)
		end
		return ToOwn(text)
	end
end

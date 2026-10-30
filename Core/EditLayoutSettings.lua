--------------------------------------------------------------------------------
-- MelloUI - Edit Layout: Edit Mode's settings in the element's box (1.2.4)
--
-- The user, 2026-10-27: Edit Layout replaces Edit Mode -- "everything that
-- edit mode does needs to be possible to do in Edit Layout"; their pick A +
-- C's settings panel of MelloUI-BuildData/output/editlayout_dock_sketch
-- (docs/plans/edit-layout-parity.md). An Edit Mode system's box (its
-- right-click, or a right-click on its row in the Elements list) lists the
-- settings Edit Mode's own dialog offers for it, in its order, names and
-- ranges: read from the game's table of them
-- (EditModeSettingDisplayInfoManager.systemSettingDisplayInfo, a plain read),
-- shown when the system has the setting in the active layout and the game's
-- own test says so (the system's ShouldShowSetting: a read of its settings,
-- in pcall). A change waits with the session's other changes (counted with
-- them) and is written at Save into the active layout, as the configurator's
-- are (MelloUI:EditModeSettingsSoon: raw values, a preset copied after one
-- question, never the game's layout code run from here -- the hard rule);
-- the layout shows it from the next /reload (one line says so). Discard drops
-- it. A setting another mirrors (the cast bar's Lock to Player Frame and the
-- player frame's Cast Bar Underneath) is written on both; the chat window's
-- width and height go in as the game keeps them (hundreds, tens and ones).
-- An action bar's Bar Visible offers the Fader's On Mouseover too (the game
-- has none; the Fader's "show_barN" its one store, set at once). A system
-- the game switches with a setting of its own (Edit Mode's gated "Show"
-- boxes: the cooldown viewer, the damage meter, the loot window ...; the
-- bridge's Gate) gets that switch on top: the game's CVar, set at once as
-- Edit Mode's shift-click sets it; off and locked while a MelloUI part holds
-- it (MelloUI:CVarHeldBy), with that part's page.
-- (1.2.4, el-07) A MelloUI part that stands in for an Edit Mode system with a
-- frame of its own (the Quest Tracker for the game's objective tracker) is no
-- system: its box lists its module's own counterparts of that system's
-- settings instead (MelloUI:EditLayoutOptions), drawn from the module's
-- schema -- the module's setting the one store. Such a change shows at once
-- (the settings bus), counts with the session's others, stays at Save and is
-- put back at Discard.
--
--   ES = MelloUI.EditLayout.Settings
--     ES.For(entry) -> system, index | nil   an Edit Mode system's entry
--     ES.Lay(box, entry, y, width) -> y      its rows laid into the box from
--                                            y (hidden when it has none)
--     ES.Hide()                              the rows away (the box closed)
--     ES.Count()                             the settings changed, unsaved
--     ES.Save(), ES.Discard()                at the session's end
--   MelloUI:EditLayoutOptions(frame, spec)   (el-07) frame's box lists those
--     settings of a module: spec { module = name, keys = { key, ... } }, in
--     that order (a slider or a toggle of its schema; another kind is left
--     out)
-- Nothing at load: the rows are made at the first box that needs them.
-- No colour number: palette keys through W.Paint.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("EditLayoutSettings")
local C_Timer = Perf.C_Timer
local Safe = MelloUI.Safe
local Secret = Safe.IsSecret
local Num = Safe.Number
local W = MelloUI.Widgets
local E = MelloUI.EditLayout
if not E then
	return   -- (Edit Layout's own file did not load)
end

local ES = {}
E.Settings = ES

local TEXT = {
	heading = "Edit Mode settings",
	note = "Sizes and opacity show at once; the others after a /reload. Saved with Save.",
	none = "This element has no settings in Edit Mode.",
	-- (1.2.4, el-03) a game feature's own switch (its setting, as Edit Mode's shift-click turns it on)
	gateTip = "Turns the game's %s on or off now, as the game's own setting does. Discard does not undo it.",
	held = "MelloUI's %s stands in for it.",
	heldLink = "%s >",
	-- (1.2.4, el-07) a MelloUI part's own settings (MelloUI:EditLayoutOptions)
	own = "Settings",
}
ES.TEXT = TEXT

local ROW_H = 28
local LABEL_W = 150      -- a setting's name, wrapped onto two lines when it must
local GAP = 8

-- the changes waiting: [system .. ":" .. index] = { system, index, values = { [setting] = raw } }
local pend = {}
-- (1.2.4, el-07) the parts' own settings: [frame] = spec (MelloUI:EditLayoutOptions); and what each changed one was
-- before the session's first change of it: [module .. "." .. key] = { module, key, value }
local own = setmetatable({}, { __mode = "k" })
local ownWas = {}

local function Key(system, index)
	return tostring(system) .. ":" .. tostring(index)
end

-- an entry's frame as an Edit Mode system: its system and index (a plain
-- read of the frame's fields; nil for anything else)
function ES.For(entry)
	local frame = type(entry) == "table" and entry.frame or nil
	if type(frame) ~= "table" or entry.covered then
		return nil   -- (a covered system: a MelloUI part stands in for it, the settings are the hidden frame's)
	end
	local system, index = rawget(frame, "system"), rawget(frame, "systemIndex")
	if Secret(system) or type(system) ~= "number" then
		return nil
	end
	if Secret(index) or (index ~= nil and type(index) ~= "number") then
		index = nil
	end
	return system, index
end

-- the game's list of a system's settings (read only)
local function Infos(system)
	local M = _G.EditModeSettingDisplayInfoManager
	local all = type(M) == "table" and M.systemSettingDisplayInfo
	local list = type(all) == "table" and all[system]
	return type(list) == "table" and list or nil
end

local function KindOf(info)
	local T = Enum and Enum.EditModeSettingDisplayType
	local t = info.type
	if not T then
		return nil
	end
	if t == T.Dropdown then
		return "dropdown"
	elseif t == T.Slider then
		return "slider"
	elseif t == T.Checkbox then
		return "check"
	end
	return nil
end

-- the saved raw values (the active layout's, the configurator's held ones
-- over them), then ours over those
local function Raw(system, index)
	local values = MelloUI.EditModeSystemSettings and MelloUI:EditModeSystemSettings(system, index)
	if type(values) ~= "table" then
		return nil
	end
	local p = pend[Key(system, index)]
	if p then
		for setting, v in pairs(p.values) do
			values[setting] = v
		end
	end
	return values
end

-- a setting's value as its control shows it (the display value)
local function DisplayOf(info, raw)
	if info.isCompositeNumberSetting then
		local h, t = raw[info.compositeNumberHundredsSetting], raw[info.compositeNumberTensAndOnesSetting]
		if type(h) ~= "number" or type(t) ~= "number" then
			return nil
		end
		return math.floor(h * 100 + t)
	end
	local v = raw[info.setting]
	if type(v) ~= "number" then
		return nil
	end
	local ok, d = pcall(info.ConvertValueForDisplay, info, v)
	return ok and Num(d) or v
end

-- (1.2.4; the user: changes "do not update in real time, changes occur only after a reload") a setting the game
-- draws as a plain scale, alpha or size is shown at once on the system's frame -- its own *Base method where it has one
-- (Edit Mode's overrides are never called: hard rule 1), out of combat only -- relative to the saved value the game
-- shows now; the rest show after a /reload. Discard puts every frame back as it was; Save keeps the look (the reload
-- then shows the same, drawn by the game).
local PREVIEW = { Size = "scale", FrameSize = "scale", BarSize = "scale", IconSize = "scale", Scale = "scale",
	Opacity = "alpha", Width = "width", Height = "height" }
local orig = {}    -- [frame] = { scale, alpha, w, h }: as it was before the session's first preview

-- a setting's name in its system's enum ("IconSize"), read once a setting
local nameOf = {}
local function SettingName(system, setting)
	local key = tostring(system) .. ":" .. tostring(setting)
	local v = nameOf[key]
	if v ~= nil then
		return v or nil
	end
	v = false
	local systems = Enum and Enum.EditModeSystem
	local sysName
	for k, n in pairs(type(systems) == "table" and systems or {}) do
		if n == system then
			sysName = k
		end
	end
	for _, tableName in ipairs({ sysName and ("EditMode" .. sysName .. "Setting"),
		sysName and ("EditMode" .. sysName .. "DisplayOnlySetting") }) do
		local e = tableName and Enum[tableName]
		if type(e) == "table" then
			for k, n in pairs(e) do
				if n == setting then
					v = k
				end
			end
		end
	end
	nameOf[key] = v
	return v or nil
end

local function Call(frame, method, ...)
	local fn = frame[method .. "Base"] or frame[method]
	if type(fn) == "function" then
		pcall(fn, frame, ...)
	end
end

local function Preview(frame, system, index, info, value)
	local kind = PREVIEW[SettingName(system, info.setting) or ""]
	if not (kind and type(frame) == "table") or InCombatLockdown() then
		return false
	end
	local saved = MelloUI:EditModeSystemSettings(system, index)
	local base
	if info.isCompositeNumberSetting then
		local h, t = saved and saved[info.compositeNumberHundredsSetting], saved and saved[info.compositeNumberTensAndOnesSetting]
		base = (type(h) == "number" and type(t) == "number") and math.floor(h * 100 + t) or nil
	elseif saved and type(saved[info.setting]) == "number" then
		local ok, d = pcall(info.ConvertValueForDisplay, info, saved[info.setting])
		base = ok and Num(d) or nil
	end
	value = Num(value)
	if not (base and base > 0 and value) then
		return false
	end
	local o = orig[frame]
	if not o then
		local okS, s = pcall(frame.GetScale, frame)
		local okA, a = pcall(frame.GetAlpha, frame)
		local okW, w = pcall(frame.GetWidth, frame)
		local okH, h = pcall(frame.GetHeight, frame)
		o = { scale = okS and Num(s) or 1, alpha = okA and Num(a) or 1, w = okW and Num(w), h = okH and Num(h) }
		orig[frame] = o
	end
	if kind == "scale" then
		Call(frame, "SetScale", o.scale * value / base)
	elseif kind == "alpha" then
		Call(frame, "SetAlpha", math.max(0, math.min(1, o.alpha * value / base)))
	elseif kind == "width" and o.w then
		Call(frame, "SetWidth", value)
	elseif kind == "height" and o.h then
		Call(frame, "SetHeight", value)
	end
	local P = E.Movers
	if P and P.SyncSoon then
		P.SyncSoon()   -- (its plate laid again over the new size)
	end
	return true
end

-- every previewed frame back as it was (Discard, a session dropped)
local function Unpreview()
	if InCombatLockdown() then
		wipe(orig)
		return
	end
	for frame, o in pairs(orig) do
		Call(frame, "SetScale", o.scale)
		Call(frame, "SetAlpha", o.alpha)
		if o.w and o.h then
			Call(frame, "SetSize", o.w, o.h)
		end
	end
	wipe(orig)
end

local function Hold(system, index, setting, raw)
	local key = Key(system, index)
	local p = pend[key]
	if not p then
		p = { system = system, index = index, values = {} }
		pend[key] = p
	end
	p.values[setting] = raw
end

-- a display value set: its raw value(s) held, and a mirror's too
local function SetDisplay(system, index, info, value)
	value = Num(value)
	if not value then
		return
	end
	if info.isCompositeNumberSetting then
		value = math.floor(value + 0.5)
		Hold(system, index, info.compositeNumberHundredsSetting, math.floor(value / 100))
		Hold(system, index, info.compositeNumberTensAndOnesSetting, math.floor(value % 100))
		return
	end
	local ok, raw = pcall(info.ConvertValue, info, value)
	raw = ok and Num(raw) or value
	Hold(system, index, info.setting, raw)
	local M = _G.EditModeSettingDisplayInfoManager
	local okM, mirrors = false, nil
	if type(M) == "table" and M.GetMirroredSettings then
		okM, mirrors = pcall(M.GetMirroredSettings, M, system, index, info.setting)
	end
	if okM and type(mirrors) == "table" then
		for _, m in ipairs(mirrors) do
			if type(m) == "table" and type(m.system) == "number" and type(m.setting) == "number" then
				Hold(m.system, m.systemIndex, m.setting, raw)
			end
		end
	end
end

-- whether the system has the setting now: in its layout (a composite by its
-- parts), and the game's own test of the system frame (a read)
local function Has(frame, info, raw)
	if info.isCompositeNumberSetting then
		if raw[info.compositeNumberHundredsSetting] == nil then
			return false
		end
	elseif raw[info.setting] == nil then
		return false
	end
	if frame and frame.ShouldShowSetting then
		local ok, show = pcall(frame.ShouldShowSetting, frame, info.setting)
		if ok and not Secret(show) and show == false then
			return false
		end
	end
	return true
end

-- (el-07) a part's own setting as it is now
local function OwnValue(module, key)
	local db = MelloUI:GetModuleDB(module)
	if type(db) ~= "table" then
		return nil
	end
	return db[key]
end

function ES.Count()
	local n = 0
	for _, p in pairs(pend) do
		for _ in pairs(p.values) do
			n = n + 1
		end
	end
	for _, was in pairs(ownWas) do
		if OwnValue(was.module, was.key) ~= was.value then
			n = n + 1
		end
	end
	return n
end

-- the session saved: every held change into the active layout (the
-- configurator's writer: soon, after the preset question when the active
-- layout is one; the reload line once)
function ES.Save()
	wipe(orig)   -- (the look kept: the reload shows the same, drawn by the game)
	wipe(ownWas)   -- (a part's own settings: set already)
	for key, p in pairs(pend) do
		pend[key] = nil
		if next(p.values) and MelloUI.EditModeSettingsSoon then
			MelloUI:EditModeSettingsSoon(p.system, p.index, p.values)
		end
	end
end

function ES.Discard()
	wipe(pend)
	Unpreview()
	-- (el-07) a part's own settings back as they were
	for id, was in pairs(ownWas) do
		ownWas[id] = nil
		if OwnValue(was.module, was.key) ~= was.value then
			MelloUI:NotifySettingChanged(was.module, was.key, was.value)
		end
	end
end

--------------------------------------------------------------------------------
-- The rows (a pool; each makes its controls the first time a setting of
-- that kind needs them)
--------------------------------------------------------------------------------

local rows, used = {}, 0
local heading, note
local cur = { system = nil, index = nil, frame = nil }

-- (1.2.4; the user, 2026-10-28: "Action Bars are missing the Bar Visibility option "Mouseover"") the game has no
-- such choice; the Fader has (Modules/Fader.lua: its "show_barN", the one store -- no second fade, no key of ours).
-- An action bar's Bar Visible offers it where the Fader offers it for that bar (Edit Mode's bar N the Fader's
-- "barN"), in the Fader's own words: shown while the Fader's bar is on it; picked, the game's value goes to Always
-- (the bar must be there to fade: held with the session's others, at Save) and the Fader's bar on it at once;
-- another pick puts a bar that was on it back to Always.
local MOUSEOVER = "mouseover"   -- (the Fader's value)

-- the Fader's key for a setting's row and the choice's label, nil for every other setting
local function FadeKey(system, index, info)
	local S, A = Enum and Enum.EditModeSystem, Enum and Enum.EditModeActionBarSetting
	if not (S and A and system == S.ActionBar and info.setting == A.VisibleSetting and type(index) == "number") then
		return nil
	end
	local F = MelloUI:GetModule("Fader")
	local name = "show_bar" .. index
	for _, o in ipairs(F and F.options or {}) do
		if o.key == name then
			for _, v in ipairs(type(o.values) == "table" and o.values or {}) do
				if v.value == MOUSEOVER then
					return "bar" .. index, v.label
				end
			end
		end
	end
	return nil
end

local function FadeValue(key)
	local db = MelloUI:GetModuleDB("Fader")
	return db and db["show_" .. key]
end

-- a pick on a row the Fader shares
local function SetFade(row, v)
	local name, was = "show_" .. row.fade, FadeValue(row.fade)
	if v ~= MOUSEOVER then
		SetDisplay(cur.system, cur.index, row.info, v)
		if was == MOUSEOVER then
			MelloUI:NotifySettingChanged("Fader", name, "always")
		end
		return
	end
	local always = Enum.ActionBarVisibleSetting and Enum.ActionBarVisibleSetting.Always
	local raw = Raw(cur.system, cur.index)
	if always and raw and raw[row.info.setting] ~= always then
		SetDisplay(cur.system, cur.index, row.info, always)
	end
	if was ~= MOUSEOVER then
		MelloUI:NotifySettingChanged("Fader", name, MOUSEOVER)
	end
end

local function Changed(row)
	E:Refresh()
	if row.kind ~= "check" then
		return
	end
	-- (a switch can bring a setting under it in or out: Party's Raid-Style)
	if E.RelayBox then
		E.RelayBox()
	end
end

-- (el-07) a row of a part's own setting: the module's value, set at once (what it was kept for Discard)
local function OwnSet(row, v)
	local module, key = row.ownModule, row.own.key
	local id = module .. "." .. key
	if not ownWas[id] then
		ownWas[id] = { module = module, key = key, value = OwnValue(module, key) }
	end
	MelloUI:NotifySettingChanged(module, key, v)
	local P = E.Movers
	if P and P.SyncSoon then
		P.SyncSoon()   -- (its plate laid again over a new size)
	end
end

local function RowGet(row)
	if row.own then
		local v = OwnValue(row.ownModule, row.own.key)
		if row.kind == "check" then
			return v == true
		end
		return v
	end
	if row.fade and FadeValue(row.fade) == MOUSEOVER then
		return MOUSEOVER
	end
	local raw = Raw(cur.system, cur.index)
	local v = raw and DisplayOf(row.info, raw)
	if row.kind == "check" then
		return v == 1
	end
	return v
end

local function RowSet(row, v)
	if row.own then
		OwnSet(row, row.kind == "check" and (v and true or false) or v)
		Changed(row)
		return
	end
	if row.kind == "check" then
		v = v and 1 or 0
	end
	if row.fade then
		SetFade(row, v)
	else
		SetDisplay(cur.system, cur.index, row.info, v)
		Preview(cur.frame, cur.system, cur.index, row.info, v)
	end
	Changed(row)
end

-- a format and a list of choices per setting, made once (the game's tables
-- stay as they are)
local formats, choices = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })

local function FormatOf(info)
	local f = formats[info]
	if f == nil then
		local fn = info.formatter
		if type(fn) == "function" then
			f = function(v)
				local ok, text = pcall(fn, v)
				return ok and type(text) == "string" and not Secret(text) and text or tostring(math.floor((Num(v) or 0) + 0.5))
			end
		else
			f = false
		end
		formats[info] = f
	end
	return f or nil
end

local function ChoicesOf(info)
	local c = choices[info]
	if not c then
		c = {}
		for _, o in ipairs(type(info.options) == "table" and info.options or {}) do
			if type(o) == "table" and type(o.value) == "number" then
				c[#c + 1] = { value = o.value, label = tostring(o.text or o.value) }
			end
		end
		choices[info] = c
	end
	return c
end

-- the game's choices and the Fader's On Mouseover after them (one list: the setting is the same on every bar)
local fadeChoices = setmetatable({}, { __mode = "k" })
local function FadeChoicesOf(info, label)
	local c = fadeChoices[info]
	if not c then
		c = {}
		for i, o in ipairs(ChoicesOf(info)) do
			c[i] = o
		end
		c[#c + 1] = { value = MOUSEOVER, label = label }
		fadeChoices[info] = c
	end
	return c
end

local function NewRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_H)
	row.label = W.Text(row, "GameFontHighlight", nil, "text")
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(true)
	row.label:SetWidth(LABEL_W)
	row.label:SetPoint("LEFT", row, "LEFT", 12, 0)
	row.get = function()
		return RowGet(row)
	end
	row.set = function(v)
		RowSet(row, v)
	end
	return row
end

local function Control(row, kind, width)
	local c = row[kind]
	if not c then
		if kind == "dropdown" then
			c = W.Dropdown(row, width, row.get, row.set, {})
		elseif kind == "slider" then
			c = W.Slider(row, width, row.get, row.set, { min = 0, max = 1, step = 1 })
		else
			c = W.Switch(row, row.get, row.set)
		end
		c:SetPoint("LEFT", row, "LEFT", 12 + LABEL_W + GAP, 0)
		row[kind] = c
	end
	return c
end

local function TakeRow(box)
	used = used + 1
	local row = rows[used]
	if not row then
		row = NewRow(box)
		rows[used] = row
	end
	return row
end

--------------------------------------------------------------------------------
-- (1.2.4, el-03) A game feature's own switch: one row, made at its first need
--------------------------------------------------------------------------------

local gate = { row = nil, spec = nil, owner = nil }

local function GateGet()
	local spec, api = gate.spec, _G.C_CVar
	if not (spec and api and api.GetCVarBool) then
		return false
	end
	local ok, on = pcall(api.GetCVarBool, spec.cvar)
	on = ok and not Secret(on) and on and true or false
	return on ~= spec.inverted
end

local function GateSync()
	local P = E.Movers
	if P and P.SyncSoon then
		P.SyncSoon()   -- (the feature shown or gone: the plates again)
	end
end

local function GateSet(on)
	local spec, api = gate.spec, _G.C_CVar
	if spec and api and api.SetCVar and not gate.owner and not InCombatLockdown() then
		pcall(api.SetCVar, spec.cvar, ((on and true or false) ~= spec.inverted) and "1" or "0")
		GateSync()
		C_Timer.After(0.5, GateSync)   -- (the game shows a feature a moment after its setting: one look more)
	end
	if gate.row then
		gate.row.switch:Refresh()
	end
end

local GateEnter = Perf.Shared("OnEnter on Edit Layout's feature switch", function(self)
	local label = gate.spec and (gate.spec.label or gate.spec.cvar) or ""
	E:Tooltip(self, label, TEXT.gateTip:format(label))
end, "script")
local GateLeave = Perf.Shared("OnLeave on Edit Layout's feature switch", function(self)
	E:TooltipHide(self)
end, "script")
local HeldClick = Perf.Shared("OnClick on Edit Layout's feature switch's page link", function()
	local owner = gate.owner
	E:CloseBox()
	if owner then
		MelloUI:OpenConfig(owner)
	end
end, "script")
local HeldEnter = Perf.Shared("OnEnter on Edit Layout's feature switch's page link", function(self)
	self.underline:Show()
end, "script")
local HeldLeave = Perf.Shared("OnLeave on Edit Layout's feature switch's page link", function(self)
	self.underline:Hide()
end, "script")

local function GateRow(box)
	local row = gate.row
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, box)
	row:SetHeight(ROW_H)
	row.label = W.Text(row, "GameFontHighlight", nil, "text")
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(true)
	row.label:SetWidth(LABEL_W)
	row.label:SetPoint("LEFT", row, "LEFT", 12, 0)
	row.switch = W.Switch(row, GateGet, GateSet)
	row.switch:SetPoint("LEFT", row, "LEFT", 12 + LABEL_W + GAP, 0)
	Perf.HookScript(row.switch, "OnEnter", GateEnter)
	Perf.HookScript(row.switch, "OnLeave", GateLeave)
	row.held = W.Text(box, "GameFontHighlight", nil, "text")
	row.held:SetJustifyH("LEFT")
	row.held:SetWordWrap(true)
	local link = CreateFrame("Button", nil, box)
	link:SetSize(100, 20)
	link.text = W.Text(link, "GameFontHighlight", nil, "selectedTrim")
	link.text:SetPoint("LEFT", link, "LEFT", 0, 0)
	link.underline = W.Solid(link, "ARTWORK", "selectedTrim", 1)
	link.underline:SetHeight(1)
	link.underline:SetPoint("TOPLEFT", link.text, "BOTTOMLEFT", 0, -1)
	link.underline:SetPoint("TOPRIGHT", link.text, "BOTTOMRIGHT", 0, -1)
	link.underline:Hide()
	Perf.SetScript(link, "OnClick", HeldClick)
	Perf.SetScript(link, "OnEnter", HeldEnter)
	Perf.SetScript(link, "OnLeave", HeldLeave)
	row.link = link
	gate.row = row
	return row
end

-- the switch laid into the box from y; y after it
local function LayGate(box, spec, y, width)
	local row = GateRow(box)
	gate.spec = spec
	local owner = MelloUI.CVarHeldBy and MelloUI:CVarHeldBy(spec.cvar) or nil
	gate.owner = owner
	row.label:SetText(spec.label or spec.cvar)
	row.switch:Refresh()
	row.switch:SetEnabled(owner == nil)
	row:SetWidth(width)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
	row:Show()
	local h = math.max(ROW_H, math.ceil(Num(row.label:GetStringHeight()) or 14) + 8)
	row:SetHeight(h)
	y = y + h
	if not owner then
		row.held:Hide()
		row.link:Hide()
		return y + 2
	end
	local module = MelloUI:GetModule(owner)
	local title = module and module.title or owner
	row.held:SetText(TEXT.held:format(title))
	row.held:SetWidth(width - 24)
	row.held:ClearAllPoints()
	row.held:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -y)
	row.held:Show()
	y = y + math.ceil(Num(row.held:GetStringHeight()) or 14) + 2
	local link = row.link
	link.text:SetText(TEXT.heldLink:format(title))
	link:SetWidth(math.ceil(Num(link.text:GetStringWidth()) or 80) + 4)
	link:ClearAllPoints()
	link:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -y)
	link:Show()
	return y + 24
end

function ES.Hide()
	for i = 1, #rows do
		rows[i]:Hide()
	end
	used = 0
	if heading then
		heading:Hide()
		note:Hide()
	end
	local row = gate.row
	if row then
		row:Hide()
		row.held:Hide()
		row.link:Hide()
	end
	gate.spec, gate.owner = nil, nil
end

-- the part's heading at y (made at its first need); y under it
local function LayHeading(box, text, y)
	if not heading then
		heading = W.Text(box, "GameFontNormal", TEXT.heading, "selectedTrim")
		note = W.Text(box, "GameFontHighlight", TEXT.note, "text")
		note:SetJustifyH("LEFT")
		note:SetWordWrap(true)
	end
	heading:SetText(text)
	heading:ClearAllPoints()
	heading:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -y)
	heading:Show()
	return y + 18
end

-- a row taken, its controls hidden (its fields are set before its control is made: a new control reads its value)
local function FreshRow(box)
	local row = TakeRow(box)
	for _, k in ipairs({ "dropdown", "slider", "check" }) do
		if row[k] then
			row[k]:Hide()
		end
	end
	return row
end

-- a row shown at y, as tall as its label; y under it
local function LayRow(box, row, c, y, width)
	c:Show()
	c:Refresh()
	row:SetWidth(width)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
	row:Show()
	local lh = Num(row.label:GetStringHeight()) or 14
	local h = math.max(ROW_H, math.ceil(lh) + 8)
	row:SetHeight(h)
	return y + h
end

--------------------------------------------------------------------------------
-- (1.2.4, el-07) A MelloUI part's own settings (the header: MelloUI:EditLayoutOptions)
--------------------------------------------------------------------------------

function MelloUI:EditLayoutOptions(frame, spec)
	if type(frame) ~= "table" or type(spec) ~= "table" or type(spec.module) ~= "string" or type(spec.keys) ~= "table" then
		return
	end
	own[frame] = spec
end

-- the schema's controls a row shows
local OWN_KIND = { slider = "slider", toggle = "check" }

-- a module's option of that key (its schema's own table, read only)
local function OptionOf(module, key)
	for _, o in ipairs(type(module.options) == "table" and module.options or {}) do
		if type(o) == "table" and o.key == key then
			return o
		end
	end
	return nil
end

-- the part's own rows from y; y after them (y when it has none)
local function LayOwn(box, entry, y, width)
	local frame = type(entry) == "table" and entry.frame or nil
	local spec = frame and own[frame]
	local module = spec and MelloUI:GetModule(spec.module)
	if not module then
		return y
	end
	local controlW = width - 12 - LABEL_W - GAP - 12
	local any = false
	for _, key in ipairs(spec.keys) do
		local o = OptionOf(module, key)
		local kind = o and OWN_KIND[o.type]
		if kind then
			if not any then
				any = true
				y = LayHeading(box, TEXT.own, y + 6)
			end
			local row = FreshRow(box)
			row.info, row.kind, row.fade = nil, kind, nil
			row.own, row.ownModule = o, spec.module
			local c = Control(row, kind, controlW)
			row.label:SetText(W.Tr(tostring(o.name or key)))
			if kind == "slider" then
				c:SetRange(Num(o.min) or 0, Num(o.max) or 1, Num(o.step) or 0.05, o.percent and true or false,
					type(o.format) == "function" and o.format or nil)
			end
			y = LayRow(box, row, c, y, width)
		end
	end
	return any and y + 4 or y
end

-- the box's Edit Mode part from y (UI units from its top); y after it
function ES.Lay(box, entry, y, width)
	ES.Hide()
	local system, index = ES.For(entry)
	if not system then
		return LayOwn(box, entry, y, width)
	end
	local infos = Infos(system)
	local raw = infos and Raw(system, index)
	local Bridge = E.Bridge
	local spec = Bridge and Bridge.Gate and Bridge.Gate(system, index) or nil
	if not (raw or spec) then
		return y
	end
	cur.system, cur.index, cur.frame = system, index, entry.frame
	y = LayHeading(box, TEXT.heading, y + 6)
	note:SetWidth(width - 24)
	note:ClearAllPoints()
	note:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -y)
	note:Show()
	y = y + math.ceil(Num(note:GetStringHeight()) or 14) + 4
	if spec then
		y = LayGate(box, spec, y, width)
	end
	local controlW = width - 12 - LABEL_W - GAP - 12
	local any = false
	for _, info in ipairs(raw and infos or {}) do
		local kind = type(info) == "table" and KindOf(info)
		if kind and Has(entry.frame, info, raw) then
			any = true
			local fade, fadeLabel
			if kind == "dropdown" then
				fade, fadeLabel = FadeKey(system, index, info)
			end
			local row = FreshRow(box)
			row.info, row.kind, row.fade = info, kind, fade
			row.own, row.ownModule = nil, nil
			local c = Control(row, kind, controlW)
			row.label:SetText(tostring(info.name or "?"))
			if kind == "dropdown" then
				c:SetValues(fade and FadeChoicesOf(info, fadeLabel) or ChoicesOf(info))
			elseif kind == "slider" then
				c:SetRange(Num(info.minValue) or 0, Num(info.maxValue) or 1, Num(info.stepSize) or 1, false, FormatOf(info))
			end
			y = LayRow(box, row, c, y, width)
		end
	end
	if not any then
		note:SetText(TEXT.none)
	else
		note:SetText(TEXT.note)
	end
	return y + 4
end

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
--
--   ES = MelloUI.EditLayout.Settings
--     ES.For(entry) -> system, index | nil   an Edit Mode system's entry
--     ES.Lay(box, entry, y, width) -> y      its rows laid into the box from
--                                            y (hidden when it has none)
--     ES.Hide()                              the rows away (the box closed)
--     ES.Count()                             the settings changed, unsaved
--     ES.Save(), ES.Discard()                at the session's end
-- Nothing at load: the rows are made at the first box that needs them.
-- No colour number: palette keys through W.Paint.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
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
}
ES.TEXT = TEXT

local ROW_H = 28
local LABEL_W = 150      -- a setting's name, wrapped onto two lines when it must
local GAP = 8

-- the changes waiting: [system .. ":" .. index] = { system, index, values = { [setting] = raw } }
local pend = {}

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

function ES.Count()
	local n = 0
	for _, p in pairs(pend) do
		for _ in pairs(p.values) do
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
end

--------------------------------------------------------------------------------
-- The rows (a pool; each makes its controls the first time a setting of
-- that kind needs them)
--------------------------------------------------------------------------------

local rows, used = {}, 0
local heading, note
local cur = { system = nil, index = nil, frame = nil }

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

local function RowGet(row)
	local raw = Raw(cur.system, cur.index)
	local v = raw and DisplayOf(row.info, raw)
	if row.kind == "check" then
		return v == 1
	end
	return v
end

local function RowSet(row, v)
	if row.kind == "check" then
		v = v and 1 or 0
	end
	SetDisplay(cur.system, cur.index, row.info, v)
	Preview(cur.frame, cur.system, cur.index, row.info, v)
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

function ES.Hide()
	for i = 1, #rows do
		rows[i]:Hide()
	end
	used = 0
	if heading then
		heading:Hide()
		note:Hide()
	end
end

-- the box's Edit Mode part from y (UI units from its top); y after it
function ES.Lay(box, entry, y, width)
	ES.Hide()
	local system, index = ES.For(entry)
	local infos = system and Infos(system)
	local raw = infos and Raw(system, index)
	if not raw then
		return y
	end
	cur.system, cur.index, cur.frame = system, index, entry.frame
	if not heading then
		heading = W.Text(box, "GameFontNormal", TEXT.heading, "selectedTrim")
		note = W.Text(box, "GameFontHighlight", TEXT.note, "text")
		note:SetJustifyH("LEFT")
		note:SetWordWrap(true)
	end
	y = y + 6
	heading:ClearAllPoints()
	heading:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -y)
	heading:Show()
	y = y + 18
	note:SetWidth(width - 24)
	note:ClearAllPoints()
	note:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -y)
	note:Show()
	y = y + math.ceil(Num(note:GetStringHeight()) or 14) + 4
	local controlW = width - 12 - LABEL_W - GAP - 12
	local any = false
	for _, info in ipairs(infos) do
		local kind = type(info) == "table" and KindOf(info)
		if kind and Has(entry.frame, info, raw) then
			any = true
			local row = TakeRow(box)
			row.info, row.kind = info, kind
			row.label:SetText(tostring(info.name or "?"))
			for _, k in ipairs({ "dropdown", "slider", "check" }) do
				if row[k] then
					row[k]:Hide()
				end
			end
			local c = Control(row, kind, controlW)
			if kind == "dropdown" then
				c:SetValues(ChoicesOf(info))
			elseif kind == "slider" then
				c:SetRange(Num(info.minValue) or 0, Num(info.maxValue) or 1, Num(info.stepSize) or 1, false, FormatOf(info))
			end
			c:Show()
			c:Refresh()
			row:SetWidth(width)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
			row:Show()
			local lh = Num(row.label:GetStringHeight()) or 14
			local h = math.max(ROW_H, math.ceil(lh) + 8)
			row:SetHeight(h)
			y = y + h
		end
	end
	if not any then
		note:SetText(TEXT.none)
	else
		note:SetText(TEXT.note)
	end
	return y + 4
end

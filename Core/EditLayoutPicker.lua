--------------------------------------------------------------------------------
-- MelloUI - Edit Layout: the Elements picker (1.2.4)
--
-- The user, 2026-10-27, over a screenshot of Edit Layout with every plate
-- shown: "having everything enabled at the same time leaves you with this
-- window, we need a way to show and hide certain things" -- their pick A of
-- MelloUI-BuildData/output/editlayout_dock_sketch (docs/plans/
-- edit-layout-parity.md): the dock's Elements button drops this list under
-- it. Every element Edit Layout knows, in groups (an entry's `category`,
-- Core's RegisterMover; Edit Mode's systems sorted by the bridge): a search,
-- the groups as chips, Show all / Hide all / What the game shows, and per row
-- its eye (its plate shown in Edit Layout), its lock (never dragged) and,
-- under the mouse, its plate lit with the others faint. A group's solo shows
-- that group alone (the dock says so, with a way back); a double-click shows
-- one element alone. Hidden plates and locks are kept (UI Modifications'
-- `editLayout`: { hidden = { [key] = true }, locked = { [key] = true },
-- pinned }); a solo lasts the session.
--
--   K = MelloUI.EditLayout.Picker
--     K.Category(entry) -> "frames" | "bars" | ... | "misc"
--     K.CATEGORIES      { { key, label } } in the list's order
--     K.Shows(entry)    its plate wanted now (the eyes and the solo); a
--                       layer's group name (the bridge's "editmode") is
--                       shown unless a solo holds the screen
--     K.LockedReason(entry) -> the lock's line, or nil
--     K.Toggle(), K.Open(), K.Close(), K.IsOpen()
--     K.Refresh()       the rows again (a sync, a lock, a pause's end)
--     K.Counts() -> shown, total    the plates the eyes let show, of all
--     K.Solo(kind, id[, label])  one group ("cat", its key) or one element ("key")
--                       alone, for the session;  K.SoloLabel() -> text | nil,  K.Unsolo()
--     K.EndSession()    the solo let go, the list put away (the session's end)
--     K.Hide()          the list put away (a pause; it comes back pinned)
-- Nothing at load: the list is made at its first open, a player's click.
-- No colour number: palette keys through W.Paint.
--------------------------------------------------------------------------------

local _, ns = ...
local MelloUI = ns.MelloUI
local Perf = MelloUI.Perf:Scope("EditLayoutPicker")
local Shared = Perf.Shared
local Safe = MelloUI.Safe
local Num = Safe.Number
local W = MelloUI.Widgets
local E = MelloUI.EditLayout
if not E then
	return   -- (Edit Layout's own file did not load)
end

local K = {}
E.Picker = K

local UIMOD = "UIModifications"
local PREFS = "editLayout"

K.CATEGORIES = {
	{ key = "frames", label = "Frames" },
	{ key = "bars", label = "Action Bars" },
	{ key = "combat", label = "Combat" },
	{ key = "text", label = "Text & Notices" },
	{ key = "quests", label = "Map & Quests" },
	{ key = "chat", label = "Chat" },
	{ key = "windows", label = "Windows" },
	{ key = "misc", label = "Misc" },
}
local LABEL_OF = {}
for _, c in ipairs(K.CATEGORIES) do
	LABEL_OF[c.key] = c.label
end

local TEXT = {
	title = "Elements",
	find = "Find an element",
	all = "All",
	showAll = "Show all", hideAll = "Hide all", gameShows = "What the game shows",
	keepOpen = "Keep open",
	footHint = "Double-click: it alone",
	hidden = "%s (hidden)",
	none = "Nothing here is called that.",
	eye = "Its plate",
	eyeOn = "Shown in Edit Layout. Click to hide its plate.",
	eyeOff = "Hidden in Edit Layout. Click to show its plate.",
	lock = "Lock",
	lockOn = "Locked: it can't be dragged or resized. Click to unlock it.",
	lockOff = "Click to lock it in place.",
	solo = "Show alone",
	soloBody = "Only this group's plates. Click again, or the cross under the bar, to see all of them again.",
	groupEye = "The group's plates",
	groupEyeBody = "Click to hide them all, or to show them all again.",
	row = "Click: pick it on the screen. Right-click: its settings. Double-click: it alone.",
	gameHidden = "The game hides it right now: its plate shows while the game shows it.",
	locked = "Locked in the Elements list.",
	soloOf = "Solo: %s",
	pinTip = "Keep the list open while you move things: a click on the screen leaves it open.",
	showAllTip = "Every plate shown again.",
	hideAllTip = "Every plate hidden: pick the ones you want.",
	gameShowsTip = "The plates of everything the game shows now; the hidden ones' plates away.",
}
K.TEXT = TEXT

-- the list's measures (UI units)
local PANEL_W, PANEL_H = 360, 520
local PAD = 10
local ROW_H, HEAD_H = 24, 26
local ICON = 18          -- an eye's or a lock's glyph
local BTN = 22           -- its button
local PICK_STRATA, PICK_LEVEL = "FULLSCREEN_DIALOG", 36   -- over the box (30), under the dock (40)
local WHEEL_STEP = 48

local panel                    -- made at the first open
local S = { open = false, pinned = false, cat = "all", query = "", solo = nil }
K.state = S

--------------------------------------------------------------------------------
-- The saved choices (UI Modifications' `editLayout`)
--------------------------------------------------------------------------------

local function DB()
	return MelloUI.modules[UIMOD] and MelloUI:GetModuleDB(UIMOD) or nil
end

-- the saved table, read (never nil: an empty one when nothing is kept)
local EMPTY = { hidden = {}, locked = {} }
local function Prefs()
	local db = DB()
	local t = db and db[PREFS]
	if type(t) ~= "table" then
		return EMPTY
	end
	return t
end

-- the saved table to change: made when missing, then told (profiles carry it)
local function Edit()
	local db = DB()
	if not db then
		return nil
	end
	local t = type(db[PREFS]) == "table" and db[PREFS] or {}
	if type(t.hidden) ~= "table" then
		t.hidden = {}
	end
	if type(t.locked) ~= "table" then
		t.locked = {}
	end
	return t
end

local function Save(t)
	if t then
		MelloUI:NotifySettingChanged(UIMOD, PREFS, t)
	end
end
K.Prefs, K.EditPrefs, K.SavePrefs = Prefs, Edit, Save

--------------------------------------------------------------------------------
-- An element, read
--------------------------------------------------------------------------------

function K.Category(entry)
	local c = type(entry) == "table" and entry.category or nil
	if LABEL_OF[c] then
		return c
	end
	if type(entry) == "table" and entry.group == "window" then
		return "windows"
	end
	return "misc"
end

local function Movers()
	return E.Movers
end

local function Label(entry)
	local P = Movers()
	return P and P.Label(entry) or tostring(entry.key or "?")
end

local function Hidden(key)
	local h = Prefs().hidden
	return key ~= nil and type(h) == "table" and h[key] == true
end

local function LockedKey(key)
	local l = Prefs().locked
	return key ~= nil and type(l) == "table" and l[key] == true
end

function K.LockedReason(entry)
	if type(entry) == "table" and LockedKey(entry.key) then
		return TEXT.locked
	end
	return nil
end

function K.Shows(entry)
	local solo = S.solo
	if type(entry) ~= "table" then
		return solo == nil   -- (a layer's own plates: the bridge's)
	end
	if solo then
		if solo.kind == "cat" then
			return K.Category(entry) == solo.id
		end
		return entry.key ~= nil and entry.key == solo.id
	end
	return not Hidden(entry.key)
end

-- the listed elements: one per key, live, no tool; read into `items` (each
-- { entry, key, label, cat, gameHidden }). An element keeps its own item for
-- good (itemOf): a row holds its item, so an item is never handed to another
-- element -- 1.2.4's first build reused them in the read's order, and a read
-- (the dock's count after every change) left each row pointing at another
-- element (the user: a hidden one's eye, the locks, "breaks constantly")
local items, itemOf = {}, {}
local seenKey, standIns = {}, {}

local function Item(key)
	local it = itemOf[key]
	if not it then
		it = {}
		itemOf[key] = it
	end
	return it
end

local function ByLabel(a, b)
	return a.label < b.label
end

local function ReadItems()
	wipe(items)
	wipe(seenKey)
	local list = MelloUI:MoverEntries()
	for i = 1, #list do
		local entry = list[i]
		local key = entry.key
		if key ~= nil and entry.group ~= "tool" and not seenKey[key] and MelloUI:EntryLive(entry) then
			seenKey[key] = true
			local it = Item(key)
			it.entry, it.key, it.label, it.cat = entry, key, Label(entry), K.Category(entry)
			it.gameHidden = not MelloUI:EntryShown(entry)
			items[#items + 1] = it
		end
	end
	-- (the systems the bridge lays: "Move via Edit Mode" plates, no mover of their own)
	local Bridge = E.Bridge
	if Bridge and Bridge.StandIns then
		wipe(standIns)
		Bridge.StandIns(standIns)
		for i = 1, #standIns do
			local p = standIns[i]
			local key = p.key
			if key ~= nil and not seenKey[key] then
				seenKey[key] = true
				local it = Item(key)
				it.entry, it.key, it.label, it.cat = p, key, p.label, K.Category(p)
				it.gameHidden = not p.shown
				items[#items + 1] = it
			end
		end
	end
	table.sort(items, ByLabel)
	return items
end

function K.Counts()
	ReadItems()
	local shown = 0
	for i = 1, #items do
		if K.Shows(items[i].entry) then
			shown = shown + 1
		end
	end
	return shown, #items
end

function K.SoloLabel()
	local solo = S.solo
	if not solo then
		return nil
	end
	if solo.kind == "cat" then
		return TEXT.soloOf:format(LABEL_OF[solo.id] or solo.id)
	end
	return TEXT.soloOf:format(solo.label or tostring(solo.id))
end

--------------------------------------------------------------------------------
-- Changes: each one lays the plates again (one sync), the list and the dock
--------------------------------------------------------------------------------

local Lay   -- below

local function Changed()
	local P = Movers()
	if P and E:IsShowing() then
		P.SyncAll()
	end
	if panel and panel:IsShown() then
		Lay()
	end
	E:Refresh()
end

local function SetHidden(key, hide)
	local t = Edit()
	if not t or key == nil then
		return
	end
	t.hidden[key] = hide and true or nil
	Save(t)
end

local function SetSolo(kind, id, label)
	S.solo = { kind = kind, id = id, label = label }
	MelloUI:PlayUISound("tick")
	Changed()
end

function K.Solo(kind, id, label)
	if (kind == "cat" or kind == "key") and id ~= nil then
		SetSolo(kind, id, label)
	end
end

function K.Unsolo()
	if S.solo then
		S.solo = nil
		MelloUI:PlayUISound("tick")
		Changed()
	end
end

-- every listed element's eye at once: true shows all, false hides all, "game"
-- shows what the game shows
local function SetAll(how)
	local t = Edit()
	if not t then
		return
	end
	S.solo = nil
	ReadItems()
	for i = 1, #items do
		local it = items[i]
		local hide = how == false or (how == "game" and it.gameHidden)
		t.hidden[it.key] = hide and true or nil
	end
	Save(t)
	MelloUI:PlayUISound("tick")
	Changed()
end

--------------------------------------------------------------------------------
-- The list: made once, rows from a pool
--------------------------------------------------------------------------------

local rows, used = {}, 0

local function Tip(owner, title, body)
	E:Tooltip(owner, title, body)
end

local IconEnter = Shared("OnEnter on an Elements list button", function(self)
	if self.melloTitle then
		Tip(self, self.melloTitle, self.melloBody)
	end
	local row = self.melloRow
	if row and row.item then
		local P = Movers()
		if P and P.Peek then
			P.Peek(row.item.entry)
		end
	end
end, "script")
local IconLeave = Shared("OnLeave on an Elements list button", function(self)
	E:TooltipHide(self)
	local P = Movers()
	if P and P.Peek then
		P.Peek(nil)
	end
end, "script")

-- a small glyph button: its glyph painted gold (on) or in the text colour
local function GlyphOn(b, glyph, on)
	W.Glyph(b.tex, glyph)
	W.Paint(b.tex, on and "selectedTrim" or "text", "vertex", on and 1 or 0.55)
end

local function SmallButton(parent, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(BTN, BTN)
	b:RegisterForClicks("LeftButtonUp")
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetSize(ICON, ICON)
	b.tex:SetPoint("CENTER")
	W.HoverLight(b, "round")
	Perf.SetScript(b, "OnClick", onClick)
	Perf.SetScript(b, "OnEnter", IconEnter)
	Perf.SetScript(b, "OnLeave", IconLeave)
	return b
end

local EyeClick = Shared("OnClick on an Elements list eye", function(self)
	local row = self.melloRow
	local it = row and row.item
	if not it then
		return
	end
	if row.head then
		-- the group's: all its plates hidden while any shows, else all shown
		local t = Edit()
		if not t then
			return
		end
		local any = false
		ReadItems()
		for i = 1, #items do
			if items[i].cat == it.cat and K.Shows(items[i].entry) then
				any = true
			end
		end
		S.solo = nil
		for i = 1, #items do
			if items[i].cat == it.cat then
				t.hidden[items[i].key] = any and true or nil
			end
		end
		Save(t)
	else
		if S.solo then
			-- (a solo: the eyes stand for the saved choice; it is let go first)
			S.solo = nil
		end
		SetHidden(it.key, not Hidden(it.key))
	end
	MelloUI:PlayUISound("tick")
	Changed()
end, "script")

local LockClick = Shared("OnClick on an Elements list lock", function(self)
	local row = self.melloRow
	local it = row and row.item
	local t = Edit()
	if not (it and t) then
		return
	end
	t.locked[it.key] = not LockedKey(it.key) and true or nil
	Save(t)
	MelloUI:PlayUISound("tick")
	Changed()
end, "script")

local SoloClick = Shared("OnClick on an Elements list solo", function(self)
	local row = self.melloRow
	local it = row and row.item
	if not it then
		return
	end
	if S.solo and S.solo.kind == "cat" and S.solo.id == it.cat then
		K.Unsolo()
	else
		SetSolo("cat", it.cat)
	end
end, "script")

-- a row: a click picks its plate (shown first when its eye hid it), a
-- right-click opens its settings, a double-click shows it alone
local function Pick(it, open)
	local P = Movers()
	if not P then
		return
	end
	if not K.Shows(it.entry) then
		if S.solo then
			S.solo = nil
		end
		SetHidden(it.key, false)
		Changed()
	end
	P.SelectKey(it.key)
	local plate = P.PlateOf and P.PlateOf(it.entry)
	if plate then
		if P.Flash then
			P.Flash(plate)
		end
		if open then
			E:OpenBoxForPlate(plate)
		end
	end
end

local RowClick = Shared("OnClick on an Elements list row", function(self, button)
	local it = self.item
	if not it or self.head then
		return
	end
	MelloUI:PlayUISound("tick")
	-- (the list stays open: the row and its plate picked, the plate glowing a moment -- the sketch's)
	Pick(it, button == "RightButton")
	K.MarkSelected()
end, "script")

local RowDouble = Shared("OnDoubleClick on an Elements list row", function(self)
	local it = self.item
	if not it or self.head then
		return
	end
	SetSolo("key", it.key, it.label)
	local P = Movers()
	if P then
		P.SelectKey(it.key)
	end
end, "script")

local RowEnter = Shared("OnEnter on an Elements list row", function(self)
	local it = self.item
	if not it then
		return
	end
	if not self.head then
		Tip(self, it.label, it.gameHidden and (TEXT.row .. "\n" .. TEXT.gameHidden) or TEXT.row)
	end
	local P = Movers()
	if P and P.Peek and not self.head then
		P.Peek(it.entry)
	end
end, "script")
local RowLeave = Shared("OnLeave on an Elements list row", function(self)
	E:TooltipHide(self)
	local P = Movers()
	if P and P.Peek then
		P.Peek(nil)
	end
end, "script")

local function NewRow(content)
	local row = CreateFrame("Button", nil, content)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetHeight(ROW_H)
	W.RowPlate(row)
	-- (the picked element's row: the selected fill under it)
	row.sel = W.Solid(row, "BACKGROUND", "selectedTab", 1)
	row.sel:SetAllPoints(row)
	row.sel:Hide()
	row.eye = SmallButton(row, EyeClick)
	row.eye.melloRow = row
	row.eye:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.label = W.Text(row, "GameFontHighlight", nil, "text")
	row.label:SetWordWrap(false)
	row.label:SetJustifyH("LEFT")
	row.count = W.Text(row, "GameFontHighlight", nil, "text")
	row.lock = SmallButton(row, LockClick)
	row.lock.melloRow = row
	row.lock:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.solo = SmallButton(row, SoloClick)
	row.solo.melloRow = row
	row.solo:SetPoint("RIGHT", row.lock, "LEFT", -2, 0)
	W.RowPlateChild(row, row.eye)
	W.RowPlateChild(row, row.lock)
	W.RowPlateChild(row, row.solo)
	Perf.SetScript(row, "OnClick", RowClick)
	Perf.SetScript(row, "OnDoubleClick", RowDouble)
	Perf.HookScript(row, "OnEnter", RowEnter)
	Perf.HookScript(row, "OnLeave", RowLeave)
	return row
end

local function TakeRow()
	used = used + 1
	local row = rows[used]
	if not row then
		row = NewRow(panel.content)
		rows[used] = row
	end
	row:Show()
	return row
end

-- a group's heading row
local function LayHead(row, it, shownN, n)
	row.head, row.item = true, it
	row.sel:Hide()
	row:SetHeight(HEAD_H)
	row.label:SetFontObject("GameFontNormal")
	W.Paint(row.label, "selectedTrim", "text")
	row.label:SetText(LABEL_OF[it.cat] or it.cat)
	row.label:ClearAllPoints()
	row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.count:SetText(string.format("%d / %d", shownN, n))
	row.count:ClearAllPoints()
	row.count:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
	row.count:Show()
	row.eye:ClearAllPoints()
	row.eye:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	GlyphOn(row.eye, shownN > 0 and "eye" or "eyeOff", shownN > 0)
	row.eye.melloTitle, row.eye.melloBody = TEXT.groupEye, TEXT.groupEyeBody
	local soloOn = S.solo and S.solo.kind == "cat" and S.solo.id == it.cat
	row.solo:ClearAllPoints()
	row.solo:SetPoint("RIGHT", row.eye, "LEFT", -2, 0)
	GlyphOn(row.solo, "solo", soloOn)
	row.solo.melloTitle, row.solo.melloBody = TEXT.solo, TEXT.soloBody
	row.solo:Show()
	row.lock:Hide()
end

local function Picked(it)
	local P = Movers()
	return P ~= nil and it ~= nil and it.entry ~= nil and P.Selected() == it.entry
end

local function LayItem(row, it)
	row.head, row.item = nil, it
	row.sel:SetShown(Picked(it))
	row:SetHeight(ROW_H)
	local on = K.Shows(it.entry)
	row.eye:ClearAllPoints()
	row.eye:SetPoint("LEFT", row, "LEFT", 10, 0)
	GlyphOn(row.eye, on and "eye" or "eyeOff", on)
	row.eye.melloTitle, row.eye.melloBody = TEXT.eye, on and TEXT.eyeOn or TEXT.eyeOff
	row.label:SetFontObject("GameFontHighlight")
	W.Paint(row.label, "text", "text")
	row.label:SetAlpha(on and 1 or 0.55)
	row.label:SetText(it.gameHidden and TEXT.hidden:format(it.label) or it.label)
	row.label:ClearAllPoints()
	row.label:SetPoint("LEFT", row.eye, "RIGHT", 6, 0)
	row.label:SetPoint("RIGHT", row.lock, "LEFT", -6, 0)
	row.count:Hide()
	local locked = LockedKey(it.key)
	GlyphOn(row.lock, locked and "padlock" or "padlockOpen", locked)
	row.lock.melloTitle, row.lock.melloBody = TEXT.lock, locked and TEXT.lockOn or TEXT.lockOff
	row.lock:Show()
	row.solo:Hide()
end

local heads = {}   -- [cat] = the heading's item (reused)

Lay = function()
	if not panel then
		return
	end
	ReadItems()
	for i = 1, used do
		rows[i]:Hide()
		rows[i].item = nil
	end
	used = 0
	local q = S.query
	local y = 0
	local width = PANEL_W - 2 * PAD - 10
	for _, c in ipairs(K.CATEGORIES) do
		if S.cat == "all" or S.cat == c.key then
			local n, shownN, first = 0, 0, nil
			for i = 1, #items do
				local it = items[i]
				if it.cat == c.key and (q == "" or it.label:lower():find(q, 1, true)) then
					n = n + 1
					if K.Shows(it.entry) then
						shownN = shownN + 1
					end
					first = first or i
				end
			end
			if n > 0 then
				local h = heads[c.key] or {}
				heads[c.key] = h
				h.cat, h.entry, h.key, h.label = c.key, nil, nil, c.label
				local head = TakeRow()
				LayHead(head, h, shownN, n)
				head:ClearAllPoints()
				head:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -y)
				head:SetWidth(width)
				y = y + HEAD_H
				for i = first, #items do
					local it = items[i]
					if it.cat == c.key and (q == "" or it.label:lower():find(q, 1, true)) then
						local row = TakeRow()
						LayItem(row, it)
						row:ClearAllPoints()
						row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -y)
						row:SetWidth(width)
						y = y + ROW_H
					end
				end
				y = y + 4
			end
		end
	end
	panel.none:SetShown(used == 0)
	panel.content:SetHeight(math.max(1, y))
	local view = Num(panel.scroll:GetHeight()) or 1
	local range = math.max(0, y - view)
	panel.bar:SetMinMaxValues(0, range)
	panel.bar:SetShown(range > 0)
	if (Num(panel.scroll:GetVerticalScroll()) or 0) > range then
		panel.scroll:SetVerticalScroll(range)
		panel.bar:SetValue(range)
	end
	GlyphOn(panel.pin, "pin", S.pinned)
end

local Wheel = Shared("OnMouseWheel on the Elements list", function(_, delta)
	local range = select(2, panel.bar:GetMinMaxValues())
	local v = math.max(0, math.min(Num(range) or 0, (Num(panel.scroll:GetVerticalScroll()) or 0) - delta * WHEEL_STEP))
	panel.scroll:SetVerticalScroll(v)
	panel.bar:SetValue(v)
end, "script")

local BarChanged = Shared("OnValueChanged on the Elements list's scroll bar", function(_, v)
	panel.scroll:SetVerticalScroll(Num(v) or 0)
end, "script")

local SearchChanged = Shared("OnTextChanged on the Elements list's search", function(self)
	local text = self:GetText()
	S.query = type(text) == "string" and text:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
	Lay()
end, "script")

local SearchEscape = Shared("OnEscapePressed on the Elements list's search", function(self)
	self:ClearFocus()
end, "script")

local function OnChip(_, key)
	S.cat = key or "all"
	MelloUI:PlayUISound("tick")
	Lay()
end

local ShowAllClick = Shared("OnClick on the Elements list's Show all", function()
	SetAll(true)
end, "script")
local HideAllClick = Shared("OnClick on the Elements list's Hide all", function()
	SetAll(false)
end, "script")
local GameClick = Shared("OnClick on the Elements list's What the game shows", function()
	SetAll("game")
end, "script")

local PinClick = Shared("OnClick on the Elements list's Keep open", function()
	S.pinned = not S.pinned
	local t = Edit()
	if t then
		t.pinned = S.pinned or nil
		Save(t)
	end
	MelloUI:PlayUISound("tick")
	GlyphOn(panel.pin, "pin", S.pinned)
end, "script")

local QuickEnter = Shared("OnEnter on an Elements list quick button", function(self)
	Tip(self, self.melloTipTitle, self.melloTipBody)
end, "script")
local QuickLeave = Shared("OnLeave on an Elements list quick button", function(self)
	E:TooltipHide(self)
end, "script")

local function QuickButton(parent, text, onClick, tip)
	local b = W.Button(parent, text, 80, nil, { onClick = onClick, height = 22 })
	local fs = b:GetFontString()
	local ok, w = pcall(fs.GetUnboundedStringWidth or fs.GetStringWidth, fs)
	b:SetWidth(math.max(60, math.ceil((ok and Num(w) or 60) + 18)))
	b.melloTipTitle, b.melloTipBody = text, tip
	Perf.HookScript(b, "OnEnter", QuickEnter)
	Perf.HookScript(b, "OnLeave", QuickLeave)
	return b
end

local function Make()
	panel = CreateFrame("Frame", "MelloUIEditLayoutPicker", UIParent)
	panel:Hide()
	panel:SetFrameStrata(PICK_STRATA)
	panel:SetFrameLevel(PICK_LEVEL)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:SetSize(PANEL_W, PANEL_H)
	-- (as the sketch has it: the window's slate in round corners, its top edge the trim)
	panel.plate = W.RoundPlate(panel, { radius = 10, fill = "mainWindow", edge = "border" })
	local top = W.Solid(panel, "BORDER", "trim", 1)
	top:SetHeight(1)
	top:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, 0)
	top:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, 0)
	MelloUI.Kit:ShadeElement(panel, "windows"):Add(panel, { shape = "shade/square" })
	-- the search
	local search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 6, -PAD)
	search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -PAD)
	search:SetHeight(24)
	search:SetAutoFocus(false)
	search:SetMaxLetters(40)
	W.Paint(search, "text", "text")
	if search.Instructions then
		search.Instructions:SetText(TEXT.find)
	end
	Perf.HookScript(search, "OnTextChanged", SearchChanged)
	Perf.SetScript(search, "OnEscapePressed", SearchEscape)
	W.FlatSearch(search)
	panel.search = search
	-- the groups
	local chips = W.Chips(panel, { width = PANEL_W - 2 * PAD, height = 22, gap = 4, onPick = OnChip })
	local list = { { key = "all", label = TEXT.all } }
	for _, c in ipairs(K.CATEGORIES) do
		list[#list + 1] = { key = c.key, label = c.label }
	end
	chips:SetItems(list)
	chips:Select("all")
	chips:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -8)
	panel.chips = chips
	-- the three at once
	local quick = CreateFrame("Frame", nil, panel)
	quick:SetHeight(22)
	quick:SetPoint("TOPLEFT", chips, "BOTTOMLEFT", 0, -8)
	quick:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
	local a = QuickButton(quick, TEXT.showAll, ShowAllClick, TEXT.showAllTip)
	a:SetPoint("LEFT", quick, "LEFT", 0, 0)
	local b = QuickButton(quick, TEXT.hideAll, HideAllClick, TEXT.hideAllTip)
	b:SetPoint("LEFT", a, "RIGHT", 6, 0)
	local g = QuickButton(quick, TEXT.gameShows, GameClick, TEXT.gameShowsTip)
	g:SetPoint("LEFT", b, "RIGHT", 6, 0)
	panel.quick = quick
	-- the footer
	local foot = CreateFrame("Frame", nil, panel)
	foot:SetHeight(28)
	foot:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, 6)
	foot:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, 6)
	panel.pin = SmallButton(foot, PinClick)
	panel.pin:SetPoint("LEFT", foot, "LEFT", 0, 0)
	panel.pin.melloTitle, panel.pin.melloBody = TEXT.keepOpen, TEXT.pinTip
	local keep = W.Text(foot, "GameFontHighlight", TEXT.keepOpen, "text")
	keep:SetPoint("LEFT", panel.pin, "RIGHT", 4, 0)
	local hint = W.Text(foot, "GameFontHighlight", TEXT.footHint, "text")
	hint:SetPoint("RIGHT", foot, "RIGHT", 0, 0)
	-- the list: a dark well, scrolled by the wheel and its thin bar
	local well = W.Solid(panel, "BORDER", "innerPanel", 1)
	well:SetPoint("TOPLEFT", quick, "BOTTOMLEFT", -PAD + 1, -8)
	well:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", PAD - 1, 6)
	local line = W.Solid(panel, "ARTWORK", "border", 1)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT", well, "TOPLEFT")
	line:SetPoint("BOTTOMRIGHT", well, "TOPRIGHT")
	local scroll = CreateFrame("ScrollFrame", nil, panel)
	scroll:SetPoint("TOPLEFT", well, "TOPLEFT", PAD - 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -14, 4)
	scroll:EnableMouseWheel(true)
	Perf.SetScript(scroll, "OnMouseWheel", Wheel)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(PANEL_W - 2 * PAD - 10, 1)
	scroll:SetScrollChild(content)
	panel.scroll, panel.content = scroll, content
	local bar = W.ThinScrollBar(panel, 4)
	bar:SetPoint("TOPRIGHT", well, "TOPRIGHT", -5, -6)
	bar:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -5, 6)
	bar:SetMinMaxValues(0, 0)
	bar:SetValue(0)
	Perf.SetScript(bar, "OnValueChanged", BarChanged)
	panel.bar = bar
	panel.none = W.Text(content, "GameFontHighlight", TEXT.none, "text")
	panel.none:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -10)
	panel.none:Hide()
end

-- under the dock (its lines under the row included), its left edge under the
-- Elements button's; laid again as the dock grows or shrinks (E:Refresh)
local function Place()
	local bar = E.Bar and E.Bar()
	local button = bar and bar.elements
	panel:ClearAllPoints()
	local bl, el = bar and Num(bar:GetLeft()), button and Num(button:GetLeft())
	if bl and el then
		local depth = E.DockDepth and E.DockDepth() or Num(bar:GetHeight()) or 0
		panel:SetPoint("TOPLEFT", bar, "TOPLEFT", el - bl - 6, -(depth + 8))
	else
		panel:SetPoint("TOP", UIParent, "TOP", 0, -60)
	end
end
K.Place = function()
	if panel and panel:IsShown() then
		Place()
	end
end

function K.IsOpen()
	return panel ~= nil and panel:IsShown()
end

function K.Open()
	if not E:IsShowing() then
		return
	end
	if not panel then
		Make()
		S.pinned = Prefs().pinned == true
	end
	Place()
	panel:Show()
	S.open = true
	Lay()
	E:Refresh()
end

function K.Close()
	S.open = false
	if panel and panel:IsShown() then
		panel.search:ClearFocus()
		panel:Hide()
		local P = Movers()
		if P and P.Peek then
			P.Peek(nil)
		end
	end
	E:Refresh()
end

function K.Toggle()
	if K.IsOpen() then
		K.Close()
	else
		K.Open()
	end
	MelloUI:PlayUISound("tick")
end

function K.Refresh()
	if panel and panel:IsShown() then
		Lay()
	end
end

-- the picked element's row marked (a pick on the screen, in the list, none)
function K.MarkSelected()
	for i = 1, used do
		local r = rows[i]
		r.sel:SetShown(not r.head and Picked(r.item))
	end
end

-- a click outside the list (the world, a plate) closes it, unless Keep open
-- is on; a click on the dock, its crest, its pills, the box or the list itself
-- leaves it
local function Over(frame)
	return frame ~= nil and frame:IsShown() and frame:IsMouseOver()
end
function K.ClickedOutside()
	if not (panel and panel:IsShown()) or S.pinned or Over(panel) then
		return
	end
	local bar = E.Bar and E.Bar()
	if bar and (Over(bar) or Over(bar.crest) or Over(bar.under)) then
		return
	end
	if Over(rawget(_G, "MelloUIEditLayoutBox")) then
		return
	end
	K.Close()
end

-- a pause: away, and back on the resume when it was open
function K.Hide()
	if panel and panel:IsShown() then
		panel:Hide()
	end
end

function K.Resume()
	if S.open and not K.IsOpen() then
		K.Open()
	end
end

function K.EndSession()
	S.solo, S.open = nil, false
	S.query, S.cat = "", "all"
	if panel then
		panel:Hide()
		panel.search:SetText("")
		panel.chips:Select("all")
	end
end
